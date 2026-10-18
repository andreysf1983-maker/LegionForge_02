# LEGIONFORGE 7.3.5.26124

**Дата сборки: 2026-10-18.** Сервер World of Warcraft **Legion 7.3.5, билд клиента 26124**,
настроенный под кастомный клиент (новые расы из BfA и новее: харанир, драктир-визаж, сломленные,
вульпера, врайкул, дворфы Чёрного Железа, култирасцы, таунка, маг'хары, зандалары, тонкий человек).

## Быстрый старт (3 шага)

1. Распакуйте архив (например, в `D:\LegionForge`) и запустите **`UNBLOCK.bat`** —
   снимает «Mark of the Web» с всех файлов (иначе Windows блокирует PowerShell-скрипты).
2. Запустите **`setup.bat` ОТ ИМЕНИ АДМИНИСТРАТОРА** — сервер самодостаточен:
   скачает в `tools\` портативные MySQL 8.0, 7-Zip, CMake, Boost, OpenSSL; при
   отсутствии exe соберёт `worldserver`/`bnetserver` из `core\`; создаст базы
   `auth/characters/world/hotfixes` и учётную запись `admin@legionforge.ru / legionforge`;
   импортирует дампы **только в пустые базы** (ваши данные не затираются); применит
   патчи LegionForge.
3. Запустите **`play.bat`** — MySQL → bnetserver (1119) → worldserver (8085/8086) → клиент.

Вход в игру: `admin@legionforge.ru` / `legionforge`
(или создайте свой аккаунт: `create_account.bat`, админ: `create_admin.bat`).

## Самодостаточность: ничего ставить вручную не нужно

| Что нужно | Откуда берётся |
|---|---|
| MySQL 8.0.46 (fallback 8.0.45/44) | portable zip с cdn.mysql.com в `tools\mysql`, инициализация и запуск — сами |
| 7-Zip | `7zr.exe` с 7-zip.org в `tools\7zip` |
| CMake 4.2.1 | portable zip с GitHub Kitware в `tools\cmake` |
| Boost 1.87.0 / OpenSSL 3.5.9 LTS Full | официальные prebuilt-пакеты в `tools\boost_1_87_0` / `tools\openssl` |
| Компилятор MSVC | Visual Studio 2022 Build Tools через официальный bootstrapper Microsoft (нужен администратор; единственный системный шаг) |
| Программы сервера | собираются из `core\` автоматически (`build_server.bat`), exe кладутся в `server\` |
| Базы данных | `sql\base` (auth/characters) + `LegionForge-DB.7z` (world/hotfixes), импорт только в пустые базы |
| Кастомные патчи | `sql\apply_custom.ps1` (расы клиента 12–21/33, союзные расы, мини-боссы, свитки обликов, улучшение предметов) |

Скачанные архивы лежат в `tools\downloads` (повторно не загружаются).
**Всё временное — только в `tools\setup_tmp`; в корне сервера временных папок нет.**
**Файл подключения к MySQL — `tools\mysql.cnf`.**

## Точки входа (bat)

| Файл | Назначение |
|---|---|
| `UNBLOCK.bat` | снять блокировку Windows с файлов после распаковки архива (первым делом) |
| `setup.bat` | установка: MySQL, базы, сборка, патчи, данные |
| `play.bat` | запуск всего: MySQL → bnet → world → клиент WoW-64.exe |
| `stop_server.bat` | корректная остановка (мирный shutdown, InnoDB-safe; системный MySQL не трогает) |
| `server_status.bat` | порты 1119/8085/8086/3306, процессы, сводка по базам |
| `create_admin.bat` | аккаунт администратора `admin@legionforge.ru` (gm 3) |
| `create_account.bat` | создание игрового аккаунта (интерактивно или по параметрам) |
| `build_server.bat` | сборка сервера из `core\` (вызывается и из setup.bat) |
| `server\LAUNCH.bat` | запуск сервера из папки `server\` |
| `server\start_mysql.bat` | поднимает только портативный MySQL |

## Что важно знать

* **Вход в мир** требует, чтобы клиент открыл второе соединение на порт **8086**;
  `play.bat` ждёт готовности именно по 8086. Если вход обрывается — нужны последние
  100 строк `server\logs\Server.log` (или `Logs\Server.log`) и окно worldserver.
* **Расы 38–44** в клиентском ChrRaces.db2 — вражеские модели без CharSections,
  персонажа ими создать нельзя; играбельные кастомные расы — **12–21 и 33**
  (патч `sql\custom\105_legionforge_client_races_real_ids.sql` + `111_...`).
* **Модель хараниров (раса 12):** в присланном дампе DB2 у неё display ID
  116539/116687, которых нет в CreatureDisplayInfo.db2, — точную модель даёт
  только оригинальный модельный хотфикс клиента; серверной SQL-заменой это не лечится.
* Файлы клиента (`WoW.exe`, `WoW-64.exe`) сервером не патчатся и не переписываются.
  Клиент берёт адрес сервера из `WTF\UWow.wtf`: `SET portal "127.0.0.1"`.

## Структура

```
LegionForge\
├─ core\        — исходники ядра LegionForge (CMake, C++14, VS2022)
├─ server\      — конфиги, сертификаты, DLL; сюда собираются exe и папка data
├─ sql\         — base (дампы), custom (патчи), updates (схемы), apply_custom.ps1
├─ scripts\     — bootstrap_tools.ps1, build_server.ps1, учётные записи, статус
├─ tools\       — создаётся установкой: mysql, cmake, boost, openssl, 7zip, downloads
│  ├─ mysql.cnf — файл подключения к MySQL (создаёт setup.bat)
│  └─ setup_tmp\— все временные файлы установки
├─ UNBLOCK.bat / setup.bat / play.bat / stop_server.bat
├─ server_status.bat / create_admin.bat / create_account.bat / build_server.bat
└─ README.md
```

## Учётные данные MySQL

Для портативной базы установщик задаёт именно:

* MySQL administrator/root: **`admin@legionforge.ru`**
* пароль: **`legionforge`**
* встроенная учётка `root@localhost` тоже получает пароль `legionforge`.

Worldserver и bnetserver подключаются к MySQL под `admin@legionforge.ru / legionforge`.
Если порт 3306 уже обслуживает другой MySQL с неизвестным паролем root, setup.bat
один раз спросит существующий пароль администратора, создаст/обновит требуемую
учётку и запишет её в `tools\mysql.cnf`; игровые базы при этом не очищаются.

## Актуальные инструменты сборки (сборка 2026-10-18)

CMake 4.2.1, Boost 1.87.0 (официальный `archives.boost.io`, точный размер и SHA-256),
OpenSSL 3.5.9 LTS Full и MySQL 8.0.46 portable (fallback 8.0.45/44). Legacy CMake-модули
FindBoost/FindOpenSSL адаптированы под эти версии; Boost принудительно ищется в
module-mode, совместимом с этим ядром.

Исправления в этой сборке:
* `setup_tmp` больше не создаётся в корне сервера — всё временное лежит в `tools\setup_tmp`;
* `mysql.cnf` лежит в `tools\mysql.cnf`;
* полный ребрендинг LEGIONFORGE (имя мира в базе, MOTD, все скрипты, даты 2026-10-18);
* `Legion_Proyect-DB.7z` переименован в `LegionForge-DB.7z`;
* bat-файлы перекодированы в UTF-8 (chcp 65001) — читаются без «кракозябр»;
* перенесены утилиты старого сервера: `create_admin.bat`, `create_account.bat`,
  `server_status.bat`, `UNBLOCK.bat`, `server\LAUNCH.bat`, `server\start_mysql.bat`;
* `stop_server.bat` теперь останавливает MySQL корректно (mysqladmin shutdown),
  трогая только портативную копию из `tools\mysql`.

## Честный статус кастомных рас

Новые расы вашего клиента — 12–21 и 33 — в ядре этой сборки не поддержаны полностью:
`MAX_RACES` в `SharedDefines.h` заканчивается на 30/31, маски рас 32-битные
(раса 33 требует 64 бит). SQL-патчи `105`/`111` данные подготавливают, но ядро
строки `playercreateinfo` с `race >= MAX_RACES` отбрасывает при старте. Это правка
6–8 файлов C++, которую нужно проверять компиляцией MSVC — непроверенный код
в архив не кладётся. Союзные расы Legion 27–30 (`sql\custom\48`, `49`) в ядре работают.
