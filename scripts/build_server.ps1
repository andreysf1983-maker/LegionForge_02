<#
.SYNOPSIS
    LEGIONFORGE 7.3.5.26124 (2026-10-18) - автоматическая сборка сервера из core\.
.DESCRIPTION
    Полностью автономная сборка: все зависимости скачиваются в tools\
    (scripts\bootstrap_tools.ps1): CMake 4.2.1, Boost 1.87.0, OpenSSL 3.5.9 LTS, MySQL portable,
    при отсутствии компилятора - Visual Studio 2022 Build Tools (нужен
    администратор и интернет, это единственный системный шаг Microsoft).
    Собирает: worldserver, bnetserver, mapextractor, vmap4extractor,
    vmap4assembler, mmaps_generator, connection_patcher - и копирует их
    в server\ вместе с нужными DLL. Лог: build_log.txt.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\build_server.ps1
    powershell -ExecutionPolicy Bypass -File scripts\build_server.ps1 -PrepareOnly
    powershell -ExecutionPolicy Bypass -File scripts\build_server.ps1 -Clean
#>
[CmdletBinding()]
param([switch]$PrepareOnly, [switch]$Clean, [string]$Root = '')
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$log = Join-Path $Root 'build_log.txt'
function Step([string]$s) { $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $s; Write-Host $line; Add-Content -LiteralPath $log -Value $line -Encoding UTF8 }

"==== LEGIONFORGE build $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====" | Set-Content -LiteralPath $log -Encoding UTF8
$boot = Join-Path $PSScriptRoot 'bootstrap_tools.ps1'

# 1. Инструменты (скачивание в tools\)
Step 'Шаг 1/4. Портативные инструменты...'
& powershell -NoProfile -ExecutionPolicy Bypass -File $boot -Root $Root -SevenZip -CMake -MySQL -Boost -OpenSSL
if ($LASTEXITCODE -ne 0) { throw 'bootstrap_tools завершился с ошибкой (инструменты)' }

# 2. Компилятор
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsPath = $null
if (Test-Path -LiteralPath $vswhere) {
    $vsPath = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
}
if (-not $vsPath) {
    Step 'Компилятор MSVC не найден - устанавливаю Visual Studio 2022 Build Tools...'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $boot -Root $Root -Compiler
    $vsPath = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if (-not $vsPath) { throw 'Компилятор по-прежнему не найден после установки Build Tools.' }
}
Step "Компилятор: $vsPath"
if ($PrepareOnly) { Step 'PrepareOnly: сборка пропущена.'; exit 0 }

# 3. CMake configure
$cmake = Join-Path $Root 'tools\cmake\bin\cmake.exe'
$build = Join-Path $Root 'build'
if ((Test-Path -LiteralPath (Join-Path $build 'CMakeCache.txt'))) {
    $cacheText = Get-Content -LiteralPath (Join-Path $build 'CMakeCache.txt') -Raw
    if ($cacheText -match 'boost_1_86_0|Win64OpenSSL-3_5_1') { $Clean = $true }
}
if ($Clean -and (Test-Path -LiteralPath $build)) { Remove-Item -LiteralPath $build -Recurse -Force }
$boost = Join-Path $Root 'tools\boost_1_87_0'
$ssl = Join-Path $Root 'tools\openssl'
$mysql = Join-Path $Root 'tools\mysql\server'
$sslLib = Join-Path $ssl 'lib\VC\x64\MD\libssl.lib'
$cryptoLib = Join-Path $ssl 'lib\VC\x64\MD\libcrypto.lib'
Step 'Шаг 2/4. Генерация проекта CMake...'
$cfg = @('-S', (Join-Path $Root 'core'), '-B', $build, '-G', 'Visual Studio 17 2022', '-A', 'x64',
    "-DCMAKE_GENERATOR_INSTANCE=$vsPath",
    "-DBOOST_ROOT=$boost", "-DBOOST_LIBRARYDIR=$(Join-Path $boost 'lib64-msvc-14.3')",
    '-DBoost_COMPILER=-vc143', '-DBoost_NO_SYSTEM_PATHS=ON', '-DBoost_NO_BOOST_CMAKE=ON', '-DBoost_ADDITIONAL_VERSIONS=1.87.0;1.87',
    "-DOPENSSL_ROOT_DIR=$ssl", "-DOPENSSL_INCLUDE_DIR=$(Join-Path $ssl 'include')",
    "-DMYSQL_INCLUDE_DIR=$(Join-Path $mysql 'include')", "-DMYSQL_LIBRARY=$(Join-Path $mysql 'lib\libmysql.lib')",
    '-DSERVERS=1', '-DTOOLS=1', '-DSCRIPTS=static', '-DWITHOUT_GIT=1')
if (Test-Path -LiteralPath $sslLib) { $cfg += "-DOPENSSL_SSL_LIBRARY=$sslLib", "-DOPENSSL_CRYPTO_LIBRARY=$cryptoLib" }
& $cmake @cfg 2>&1 | Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw 'CMake configure завершился с ошибкой - см. build_log.txt' }

# 4. Сборка и копирование
Step 'Шаг 3/4. Компиляция (первый раз - долго)...'
& $cmake --build $build --config Release --parallel 2>&1 | Tee-Object -FilePath $log -Append
if ($LASTEXITCODE -ne 0) { throw 'Компиляция завершилась с ошибкой - см. build_log.txt' }

Step 'Шаг 4/4. Копирование программ в server\...'
$binDir = Get-ChildItem -LiteralPath $build -Recurse -Filter 'worldserver.exe' | Select-Object -First 1
if (-not $binDir) { throw 'worldserver.exe не найден в результатах сборки' }
$bin = $binDir.DirectoryName
$server = Join-Path $Root 'server'
foreach ($exe in 'worldserver.exe','bnetserver.exe','mapextractor.exe','vmap4extractor.exe','vmap4assembler.exe','mmaps_generator.exe','connection_patcher.exe') {
    $src = Join-Path $bin $exe
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $server $exe) -Force; Step "  [OK] $exe" }
    else { Step "  [!] Не собран: $exe" }
}
foreach ($dll in 'libmysql.dll','libssl-1_1-x64.dll','libcrypto-1_1-x64.dll','libssl-3-x64.dll','libcrypto-3-x64.dll','libssl-3_5-x64.dll','libcrypto-3_5-x64.dll') {
    foreach ($from in @((Join-Path $bin $dll), (Join-Path $mysql "lib\$dll"), (Join-Path $ssl "bin\$dll"))) {
        if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination (Join-Path $server $dll) -Force; break }
    }
}
Step '[OK] Сервер собран и скопирован в server\.'
exit 0
