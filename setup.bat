@echo off
rem LegionForge installer: the window must stay visible even if cmd.exe aborts
rem on a parser error (a parser error happens before any pause/goto, so the
rem window would just vanish). The guard below re-launches via cmd /k.
if /i "%LF_SETUP_CONSOLE%"=="LF26124" goto :LF_SETUP_MAIN
set "LF_SETUP_CONSOLE=LF26124"
"%ComSpec%" /d /k call "%~f0" %*
exit /b %errorlevel%
:LF_SETUP_MAIN
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion
title LEGIONFORGE 7.3.5.26124 (2026-10-18) - Установка

rem ============================================================
rem  LEGIONFORGE 7.3.5.26124 - Установка
rem  Сервер: LegionForge 7.3.5.26124, сборка 2026-10-18.
rem  EXE сервера собираются из core\ автоматически.
rem  Всё самодостаточно: MySQL, 7-Zip, CMake, Boost, OpenSSL
rem  скачиваются портативно в папку tools\ (система не трогается).
rem  Все временные файлы: tools\setup_tmp (в корне ничего нет).
rem  Файл подключения MySQL: tools\mysql.cnf.
rem ============================================================

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "SERVER_DIR=%ROOT%\server"
set "SQL_DIR=%ROOT%\sql"
set "TOOLS_DIR=%ROOT%\tools"
set "TMP_DIR=%TOOLS_DIR%\setup_tmp"
set "MYSQL_CNF=%TOOLS_DIR%\mysql.cnf"
if not exist "%TOOLS_DIR%" mkdir "%TOOLS_DIR%"
if not exist "%TMP_DIR%" mkdir "%TMP_DIR%"

echo.
echo  =========================================================
echo   LEGIONFORGE 7.3.5.26124 (2026-10-18) - Установка
echo  =========================================================
echo.

rem ---- 1. Права администратора ----
net session >nul 2>&1
if not errorlevel 1 goto :ADMIN_OK
echo  [ОШИБКА] Нужны права администратора: закройте окно и запустите снова как администратор.
goto :FAIL
:ADMIN_OK
echo  [OK] Права администратора есть.

rem ---- 2. Поиск mysql.exe ----
set "MYSQL="
if exist "%TOOLS_DIR%\mysql\server\bin\mysql.exe" set "MYSQL=%TOOLS_DIR%\mysql\server\bin\mysql.exe"
if not defined MYSQL for /f "delims=" %%P in ('where mysql.exe 2^>nul') do if not defined MYSQL set "MYSQL=%%P"
if not defined MYSQL (
    echo  [*] MySQL не найден - скачиваю портативную версию в tools\mysql...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\bootstrap_tools.ps1" -Root "%ROOT%" -MySQL -StartMySQL
    if exist "%TOOLS_DIR%\mysql\server\bin\mysql.exe" set "MYSQL=%TOOLS_DIR%\mysql\server\bin\mysql.exe"
)
if defined MYSQL goto :MYSQL_FOUND
echo  [ОШИБКА] Не найден mysql.exe.
echo      Возможная причина: недоступен официальный сайт MySQL.
echo      Проверьте internet; скачанный архив лежит в tools\downloads.
echo      Либо положите mysql-8.0.46-winx64.zip в tools\downloads и повторите.
goto :FAIL
:MYSQL_FOUND
echo  [OK] MySQL найден: %MYSQL%

rem ---- 3. MySQL слушает порт 3306 ----
netstat -ano -p tcp | findstr /r /c:":3306 .*LISTENING" >nul 2>&1
if not errorlevel 1 goto :MYSQL_UP
echo  [*] Порт 3306 не слушается - запускаю портативный MySQL...
if exist "%TOOLS_DIR%\mysql\server\bin\mysqld.exe" powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\bootstrap_tools.ps1" -Root "%ROOT%" -MySQL -StartMySQL >nul 2>&1
timeout /t 10 /nobreak >nul
netstat -ano -p tcp | findstr /r /c:":3306 .*LISTENING" >nul 2>&1
if not errorlevel 1 goto :MYSQL_UP
echo  [ОШИБКА] MySQL не слушает порт 3306. Разберите причину и повторите setup.bat.
goto :FAIL
:MYSQL_UP
echo  [OK] MySQL слушает порт 3306.

rem ---- 4. Авторизация root ----
echo.
echo  [*] Проверка доступа к MySQL...
rem LegionForge MySQL administrator: admin@legionforge.ru / legionforge.
rem Try it first so an already provisioned portable server needs no manual prompt.
> "%TMP_DIR%\mysql_legionforge.cnf" echo [client]
>> "%TMP_DIR%\mysql_legionforge.cnf" echo user=admin@legionforge.ru
>> "%TMP_DIR%\mysql_legionforge.cnf" echo password=legionforge
>> "%TMP_DIR%\mysql_legionforge.cnf" echo host=127.0.0.1
>> "%TMP_DIR%\mysql_legionforge.cnf" echo port=3306
>> "%TMP_DIR%\mysql_legionforge.cnf" echo protocol=tcp
"%MYSQL%" --defaults-extra-file="%TMP_DIR%\mysql_legionforge.cnf" -e "SELECT 1" >nul 2>&1
if not errorlevel 1 (
    copy /Y "%TMP_DIR%\mysql_legionforge.cnf" "%MYSQL_CNF%" >nul
    echo  [OK] Учётная запись MySQL: admin@legionforge.ru.
    goto :AUTH_OK
)
if exist "%MYSQL_CNF%" goto :TRY_SAVED
goto :ASK_PASS
:TRY_SAVED
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SELECT 1" >nul 2>&1
if not errorlevel 1 goto :AUTH_OK
echo  [!] Сохранённый доступ не сработал.
:ASK_PASS
echo      Введите пароль от учётной записи root вашего MySQL.
echo      Если пароля нет - просто нажмите Enter.
set /p "MYSQL_PASS=  Пароль root: "
(
  echo [client]
  echo user=root
  echo password=%MYSQL_PASS%
  echo host=127.0.0.1
  echo port=3306
  echo protocol=tcp
) > "%MYSQL_CNF%"
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SELECT 1" >nul 2>&1
if not errorlevel 1 goto :AUTH_OK
echo  [ОШИБКА] Не удалось подключиться к MySQL с введённым паролем.
goto :FAIL
:AUTH_OK
echo  [OK] Доступ к MySQL есть.

rem ---- 4b. Бинарники: если их нет - соберём сервер из core\ ----
echo.
echo  [*] Проверка бинарников: worldserver, bnetserver
if exist "%SERVER_DIR%\worldserver.exe" if exist "%SERVER_DIR%\bnetserver.exe" goto :BINARIES_OK
echo  [*] Бинарники нет - запускаю автоматическую сборку из core\.
echo      CMake, Boost, OpenSSL и MySQL скачаются сами; сборка долгая.
call "%ROOT%\build_server.bat" /auto
if errorlevel 1 goto :FAIL
if not exist "%SERVER_DIR%\worldserver.exe" goto :FAIL
:BINARIES_OK
echo  [OK] Бинарники сервера на месте.

rem ---- 5. Базы и учётная запись LegionForge ----
echo.
echo  [*] Подготовка баз и учётной записи admin@legionforge.ru...
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "CREATE DATABASE IF NOT EXISTS auth CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS characters CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS world CHARACTER SET utf8mb4; CREATE DATABASE IF NOT EXISTS hotfixes CHARACTER SET utf8mb4; ALTER USER IF EXISTS 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'legionforge'; CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'legionforge'; ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'legionforge'; CREATE USER IF NOT EXISTS 'admin@legionforge.ru'@'localhost' IDENTIFIED WITH mysql_native_password BY 'legionforge'; CREATE USER IF NOT EXISTS 'admin@legionforge.ru'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'legionforge'; CREATE USER IF NOT EXISTS 'admin@legionforge.ru'@'%%' IDENTIFIED WITH mysql_native_password BY 'legionforge'; ALTER USER 'admin@legionforge.ru'@'localhost' IDENTIFIED WITH mysql_native_password BY 'legionforge'; ALTER USER 'admin@legionforge.ru'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY 'legionforge'; ALTER USER 'admin@legionforge.ru'@'%%' IDENTIFIED WITH mysql_native_password BY 'legionforge'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION; GRANT ALL PRIVILEGES ON *.* TO 'admin@legionforge.ru'@'localhost' WITH GRANT OPTION; GRANT ALL PRIVILEGES ON *.* TO 'admin@legionforge.ru'@'127.0.0.1' WITH GRANT OPTION; GRANT ALL PRIVILEGES ON *.* TO 'admin@legionforge.ru'@'%%' WITH GRANT OPTION; FLUSH PRIVILEGES;"
if errorlevel 1 (
    echo  [ОШИБКА] Не удалось создать/обновить учётную запись admin@legionforge.ru.
    goto :FAIL
)
rem Switch the rest of installation to the required exact administrator login.
> "%MYSQL_CNF%" echo [client]
>> "%MYSQL_CNF%" echo user=admin@legionforge.ru
>> "%MYSQL_CNF%" echo password=legionforge
>> "%MYSQL_CNF%" echo host=127.0.0.1
>> "%MYSQL_CNF%" echo port=3306
>> "%MYSQL_CNF%" echo protocol=tcp
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -e "SELECT 1" >nul 2>&1
if errorlevel 1 (
    echo  [ОШИБКА] Не удалось войти под учётной записью MySQL admin@legionforge.ru.
    goto :FAIL
)
:DB_OK
echo  [OK] Базы auth, characters, world, hotfixes готовы.

rem ---- 6. Импорт баз (только в пустые - существующие данные не трогаем) ----
echo.
echo  [*] Проверка баз данных - импорт только в пустые...
call :IMPORT_IF_EMPTY auth "%SQL_DIR%\base\legion_auth.sql"
if errorlevel 1 goto :FAIL
call :IMPORT_IF_EMPTY characters "%SQL_DIR%\base\legion_characters.sql"
if errorlevel 1 goto :FAIL
call :IMPORT_WORLD_IF_EMPTY
if errorlevel 1 goto :FAIL

rem ---- 7. Патчи LegionForge (без ботов) ----
echo.
echo  [*] Патчи LegionForge: имя мира, союзные расы 27-30,
echo      расы клиента 12-21, мини-боссы, предметы, свитки обликов...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SQL_DIR%\apply_custom.ps1" -Root "%ROOT%" -CnfPath "%MYSQL_CNF%" -MysqlExe "%MYSQL%"
if not errorlevel 1 goto :PATCH_OK
echo  [ОШИБКА] Патчи не применились полностью - см. сообщения выше.
goto :FAIL
:PATCH_OK

rem ---- 8. Игровые данные (dbc, maps, vmaps, mmaps) ----
echo.
echo  [*] Проверка игровых данных в server\data...
if exist "%SERVER_DIR%\data\dbc\enUS\ChrRaces.db2" goto :DATA_OK
echo      Данных нет - ищем data в прежних установках LegionForge...
if exist "%ROOT%\data\dbc\enUS\ChrRaces.db2" goto :COPY_LOCAL_DATA
if exist "%ROOT%\client_data\dbc\enUS\ChrRaces.db2" goto :COPY_CLIENT_DATA
if exist "%ROOT%\..\LegionForge\server\data\dbc\enUS\ChrRaces.db2" goto :COPY_DATA
if exist "D:\LegionForge\server\data\dbc\enUS\ChrRaces.db2" goto :COPY_DATA_D
echo  [ОШИБКА] Не найдены игровые данные data.
echo      Положите извлечённые server\data из прежней установки LegionForge
echo      в %SERVER_DIR%\data и повторите setup.bat.
echo      Данные: dbc, maps, vmaps, mmaps (клиент WoW 7.3.5).
goto :FAIL
:COPY_LOCAL_DATA
xcopy "%ROOT%\data\*" "%SERVER_DIR%\data\" /E /I /Y /Q >nul
if exist "%SERVER_DIR%\data\dbc\enUS\ChrRaces.db2" goto :DATA_OK
echo  [ОШИБКА] Копирование data не удалось.
goto :FAIL
:COPY_CLIENT_DATA
xcopy "%ROOT%\client_data\*" "%SERVER_DIR%\data\" /E /I /Y /Q >nul
if exist "%SERVER_DIR%\data\dbc\enUS\ChrRaces.db2" goto :DATA_OK
echo  [ОШИБКА] Копирование data не удалось.
goto :FAIL
:COPY_DATA
xcopy "%ROOT%\..\LegionForge\server\data\*" "%SERVER_DIR%\data\" /E /I /Y /Q >nul
if exist "%SERVER_DIR%\data\dbc\enUS\ChrRaces.db2" goto :DATA_OK
echo  [ОШИБКА] Копирование data не удалось.
goto :FAIL
:COPY_DATA_D
xcopy "D:\LegionForge\server\data\*" "%SERVER_DIR%\data\" /E /I /Y /Q >nul
if exist "%SERVER_DIR%\data\dbc\enUS\ChrRaces.db2" goto :DATA_OK
echo  [ОШИБКА] Копирование data не удалось.
goto :FAIL
:DATA_OK
echo  [OK] Игровые данные на месте.

echo.
echo  =========================================================
echo   Установка завершена. Запуск: play.bat
echo  =========================================================
echo.
echo   Если вход в мир: создайте аккаунт и выдайте GM-права
echo   в консоли bnetserver или выполните create_admin.bat:
echo       account create admin@legionforge.ru legionforge
echo       account set gmlevel admin@legionforge.ru 3 -1
echo.
pause
exit /b 0

:IMPORT_WORLD_IF_EMPTY
set "WC="
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='world'" > "%TMP_DIR%\wc.txt" 2>nul
set /p WC=<"%TMP_DIR%\wc.txt"
if not "%WC%"=="0" goto :WORLD_KEEP
set "HC="
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='hotfixes'" > "%TMP_DIR%\hc.txt" 2>nul
set /p HC=<"%TMP_DIR%\hc.txt"
if not "%HC%"=="0" goto :WORLD_KEEP
echo      - world и hotfixes пусты: распаковываю sql\base\LegionForge-DB.7z во временную папку...
set "SZ="
if exist "%TOOLS_DIR%\7zip\7zr.exe" set "SZ=%TOOLS_DIR%\7zip\7zr.exe"
if not defined SZ if exist "C:\Program Files\7-Zip\7z.exe" set "SZ=C:\Program Files\7-Zip\7z.exe"
if not defined SZ for /f "delims=" %%P in ('where 7z.exe 2^>nul') do if not defined SZ set "SZ=%%P"
if defined SZ goto :EXTRACT_DB
echo  [ОШИБКА] Нет 7-Zip для распаковки sql\base\LegionForge-DB.7z.
echo      Скачайте 7-Zip из интернета и повторите, либо распакуйте
echo      legion_world.sql в базу world и legion_hotfixes.sql в базу hotfixes вручную.
exit /b 1
:EXTRACT_DB
"%SZ%" e -y -bso0 -bsp0 -o"%TMP_DIR%" "%SQL_DIR%\base\LegionForge-DB.7z" legion_world.sql legion_hotfixes.sql
if errorlevel 1 exit /b 1
echo      - импорт legion_world.sql...
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M world < "%TMP_DIR%\legion_world.sql"
if errorlevel 1 exit /b 1
echo      - импорт legion_hotfixes.sql...
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M hotfixes < "%TMP_DIR%\legion_hotfixes.sql"
if errorlevel 1 exit /b 1
del /q "%TMP_DIR%\legion_world.sql" "%TMP_DIR%\legion_hotfixes.sql" >nul 2>&1
exit /b 0
:WORLD_KEEP
echo      - world и hotfixes уже содержат таблицы - импорт пропущен, данные сохранены.
exit /b 0

:IMPORT_IF_EMPTY
set "LF_TABLES="
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='%~1'" > "%TMP_DIR%\lf_count.txt" 2>nul
set /p LF_TABLES=<"%TMP_DIR%\lf_count.txt"
if not "%LF_TABLES%"=="0" goto :KEEP_DB
echo      - импорт %~nx2 в пустую базу %~1...
"%MYSQL%" --defaults-extra-file="%MYSQL_CNF%" --max_allowed_packet=512M %~1 < %2
if errorlevel 1 exit /b 1
exit /b 0
:KEEP_DB
echo      - база %~1 уже содержит таблицы: %LF_TABLES% - пропуск, данные сохранены.
exit /b 0

:FAIL
echo.
echo  [ОШИБКА] Установка не завершена. Разберитесь с причиной и повторите setup.bat.
echo.
pause
exit /b 1
