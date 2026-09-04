🇪🇸 [Leer esto en español](INSTALACION.md)

# Technical documentation — The Field House

This document explains in detail how each part of the program works, and how to install/configure it manually if you'd rather not use `install.sh`.

## Repository structure

```
field-house/
├── bin/
│   └── change_wallpaper.sh           # Linux engine (multi-desktop)
├── windows/
│   ├── engine/
│   │   ├── FieldHouseEngine.cs        # Windows 10/11 engine (C#, compiled at install time)
│   │   └── Build-Engine.ps1           # Compiles FieldHouseEngine.cs with csc.exe
│   ├── Install.ps1                    # Windows installer
│   ├── Install.cmd                    # Shortcut: runs Install.ps1 with the policy bypass already handled
│   ├── Uninstall.ps1                  # Windows uninstaller
│   └── Uninstall.cmd                  # Shortcut: runs Uninstall.ps1 with the policy bypass already handled
├── tests/
│   └── change_wallpaper.bats         # Unit tests for the Linux engine (bats)
├── fondos/                           # The 9 wallpaper images (shared by both platforms)
├── systemd/
│   ├── field-house.service           # Service that runs the Linux engine
│   ├── field-house.timer             # Timer that triggers it hourly
│   └── field-house-login.service     # Service that runs at login
├── .github/workflows/
│   └── shellcheck.yml                # CI: lint + unit tests + smoke tests, Linux and Windows
├── .gitattributes                    # Forces LF (Unix) in scripts and workflows
├── CHANGELOG.md                      # Version-by-version changelog
├── install.sh                        # Interactive installer (Linux)
├── uninstall.sh                      # Uninstaller (Linux)
├── README.md / README.en.md
├── INSTALACION.md / INSTALLATION.en.md
├── CONTRIBUTING.md
└── LICENSE
```

## Where it gets installed (XDG convention)

The installer doesn't mix the program, configuration, and user data into a single folder — it follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html), the same convention used by most modern Linux apps installed by the user (no sudo):

| What | Where | Why there |
|---|---|---|
| Program + images | `~/.local/share/field-house/` | `XDG_DATA_HOME`: app data the user doesn't edit by hand |
| Configuration | `~/.config/field-house/config.conf` | `XDG_CONFIG_HOME`: the only thing the user edits |
| Logs | `~/.local/state/field-house/log.txt` | `XDG_STATE_HOME`: data that changes with use but isn't a "document" |
| systemd services | `~/.config/systemd/user/` | Standard path for user services (not system-wide) |

None of these paths need `sudo`: everything lives inside the user's `$HOME`.

## Manual installation (without `install.sh`)

If you'd rather not run the installer, you can set everything up by hand:

```bash
# 1. Program and images
mkdir -p ~/.local/share/field-house/bin
mkdir -p ~/.local/share/field-house/fondos
cp bin/change_wallpaper.sh ~/.local/share/field-house/bin/
chmod +x ~/.local/share/field-house/bin/change_wallpaper.sh
cp fondos/*.jpg ~/.local/share/field-house/fondos/

# 2. Configuration
mkdir -p ~/.config/field-house
cat << 'EOF' > ~/.config/field-house/config.conf
CARPETA_FONDOS="$HOME/.local/share/field-house/fondos"
MODO_HORARIOS="fijo"
HORA_INICIO_AMANECER="06:00"
HORA_INICIO_MEDIODIA="10:00"
HORA_INICIO_ATARDECER="15:00"
HORA_INICIO_NOCHE="20:00"
PASOS_TRANSICION=15
PAUSA_ENTRE_PASOS="0.15"
ESPERA_INICIAL_SEGUNDOS=15
REINTENTOS_CLIMA_INICIAL=3
ESPERA_REINTENTO_CLIMA=60
TTL_CACHE_CLIMA=600
MAX_LOG_BYTES=1048576
EOF

# 3. systemd services
mkdir -p ~/.config/systemd/user
cp systemd/*.service systemd/*.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now field-house.timer
systemctl --user enable field-house-login.service
```

Location isn't configured here: it's detected automatically by IP on every run (see the "Location" section below). Note that missing values in an older `config.conf` fall back to the script's defaults, so adding new variables doesn't break existing installs.

## Reinstalling / updating

To update to a new version, just run `./install.sh` again on the cloned repo. The installer **detects whether a previous install exists** (program, configuration, logs, or systemd units) and, after the confirmation prompt, reinstalls in one of two ways:

- **By default: with backup.** The program, images (including any you customized), configuration, and current logs get **moved** (`mv`) to a copy with a `.bak.TIMESTAMP` suffix in the same location, before installing the new version. Nothing is deleted irreversibly — the installer's final summary shows the exact path of each backup, so you can recover what you need by hand, or delete the backup yourself once you no longer need it.
- **With `./install.sh --no-backup`: no backup.** Deletes the previous install directly (program, customized images included, configuration, and logs) without keeping a copy. Use this if you're iterating fast during development and don't want backups piling up, or if you already backed up what mattered to you yourself.

In both cases, previous systemd units are always deleted (never backed up) — they're one-line pointers to fixed paths, not user data, and they get regenerated on the new install.

If you'd rather uninstall entirely (without reinstalling), use `uninstall.sh`, which also asks whether you want to keep configuration and logs.

Other `install.sh` flags:

```bash
./install.sh --help       # help
./install.sh --version    # installer version
```

> Note: the config keys themselves (`CARPETA_FONDOS`, `MODO_HORARIOS`, `HORA_INICIO_AMANECER`, etc.) stay in Spanish, since they're read directly by the script. Only the documentation is translated.

## How each part works

### Time slots

The script uses time blocks to decide which wallpaper applies. There are two modes, chosen during installation (`MODO_HORARIOS`):

- **Fixed** (default, the original behavior): constant clock-time blocks, always the same regardless of the season:

  - Sunrise: `06:00` → `10:00`
  - Midday: `10:00` → `15:00`
  - Sunset: `15:00` → `20:00`
  - Night: `20:00` → `06:00` (next day)

- **Automatic** (`MODO_HORARIOS="auto"`): the slots are computed from the *actual* sunrise/sunset at your location, detected automatically (see the next subsection).

In both modes the boundaries can be adjusted in `config.conf`: in fixed mode the `HORA_INICIO_AMANECER`, `HORA_INICIO_MEDIODIA`, `HORA_INICIO_ATARDECER`, `HORA_INICIO_NOCHE` variables are the ones that matter; in auto mode they act as fallback when the sun query fails.

> **Why fixed hours instead of the real sunrise/sunset for the day?** Because they give the most predictable result: you always know which wallpaper you'll see at a given hour, without it drifting with the seasons. It's the default option; if you'd rather follow the seasons, choose automatic mode during installation.

#### Automatic mode (MODO_HORARIOS="auto")

On each run (with a daily cache, to be gentle to the API), the script queries MET Norway's official **Sunrise 3.0** API (`api.met.no/weatherapi/sunrise/3.0/sun`) with the detected location's coordinates, and extracts the day's `sunrise` and `sunset`:

- **Sunrise** = actual sunrise time.
- **Sunset** = actual sunset time.
- **Midday** = the exact midpoint between sunrise and sunset.
- **Night** = sunset + 2 hours (once it's fully dark).

The result is saved to `~/.local/state/field-house/horarios-sol.cache` and reused throughout the day (requeried when the date changes). If the query fails (no internet, no location available), the script logs a notice and falls back to the fixed times in `config.conf`.

> ⚠️ **Time zone.** The calculation assumes your machine's clock is in the same time zone as your actual location (the normal case). The API returns the time already adjusted to the queried location's time zone, so if you travel and your clock doesn't update along with the detected location, the slots might not match the expected wallpaper; in that case use fixed mode or adjust the system time zone.

### Location

Location isn't configured: it's detected automatically by IP on every run, using the free `ip-api.com` API. There's no installation step that asks for it, and no field in `config.conf` to edit it.

- **Refreshed on every `--reboot`** (login), with the same retry mechanism as the weather query (see below): if the network isn't ready yet, it retries every `ESPERA_REINTENTO_CLIMA` seconds up to `REINTENTOS_CLIMA_INICIAL` times.
- **The result is cached in `~/.local/state/field-house/ubicacion.cache`, with no time-based expiration.** This is different from the weather and sun-schedule caches (which expire by TTL or by day): here, if `ip-api.com` doesn't respond, the last known location keeps being used regardless of its age, instead of ending up with no location at all. The reasoning is that a laptop doesn't typically change city from one day to the next, so a location from a few days ago is still far more useful than none. The cache only updates when the query actually succeeds.
- **Location is only unavailable** if there was never a successful geolocation (fresh install, no prior cache) and the current query also fails — typically, a freshly done install with no internet connection yet. In that case, that run uses fixed times and no weather is available, same as with any other network failure; it resolves itself as soon as there's connectivity.

### Weather

On every run, the script queries MET Norway's official **Locationforecast 2.0 (compact)** API (`api.met.no/weatherapi/locationforecast/2.0/compact`) with the detected location's coordinates, and extracts the `symbol_code` of the nearest forecast (`next_1_hours`, falling back to `next_6_hours`). The query uses a short timeout (`--connect-timeout 2 --max-time 6`): it never waits longer than 6 seconds total, and doesn't hang on DNS. Overcast weather and rain are handled as separate conditions and use different images:

- **Overcast** (`cloudy`, `fair`, `partlycloudy`), the "base" wallpaper for the current time slot is replaced with the matching overcast wallpaper:
  - Overcast sunrise or midday → `nublado-dia.jpg`
  - Overcast sunset → `nublado-dia.jpg` (there's still daylight; there's no separate sunset version)
  - Overcast night → `nublado-noche.jpg`
- **Rain** (`rain`, `sleet`, `snow`, `thunder`, `fog`), replaced with the matching rainy wallpaper:
  - Rainy sunrise or midday → `lluvia-dia.jpg`
  - Rainy sunset → `lluvia-atardecer.jpg`
  - Rainy night → `lluvia-noche.jpg`

If the query fails (no internet, timeout exceeded, no location available), the base wallpaper for the time slot is used without attempting rain or overcast, and it's logged.

**Weather cache:** since the query is a network call, the result is saved to `~/.local/state/field-house/clima.cache` and reused for `TTL_CACHE_CLIMA` seconds (10 minutes by default). This avoids redundant queries when the hourly timer and the login service fire almost at the same time — which, in turn, respects met.no's fair-use policy.

**Retry at login:** when the computer boots, the network (especially Wi-Fi) can take a while to come up, sometimes longer than the initial wait from `ESPERA_INICIAL_SEGUNDOS`. So, on the login run (`--reboot` flag), if geolocation or the weather query fail, the base wallpaper for the time slot is applied right away and retried every `ESPERA_REINTENTO_CLIMA` seconds (60s by default) up to `REINTENTOS_CLIMA_INICIAL` times (3 by default) — the same retry mechanism covers both queries, since both depend on the network being ready. If a retry succeeds, the wallpaper crossfades to the weather version; if they run out, the base wallpaper stays until the next hourly trigger. Regular runs (the hourly timer) don't retry: a failure is left for the next hour.

### Crossfade transition

If `imagemagick` is installed, the script doesn't switch wallpapers abruptly: it generates a series of intermediate images blending the previous wallpaper with the new one in increasing proportions (`PASOS_TRANSICION`, 15 by default) and applies them one by one with a short pause between each (`PAUSA_ENTRE_PASOS`, 0.15s), giving a crossfade effect of about ~2 seconds total. Without ImageMagick, or with `PASOS_TRANSICION=0`, the change is instant.

The frames are generated in a secure temp directory (`mktemp`) that cleans itself up when the script finishes — even if it's interrupted with Ctrl+C or the session is cut. Each frame is verified before being applied: if generating an intermediate image fails (e.g. a corrupt source image), it's logged and the script moves on to the next one instead of silently leaving a broken wallpaper.

### Automatic execution with systemd

The project uses **systemd user timers** instead of `cron`, for several practical reasons:

- No need to hand-edit `crontab -e` (the installer runs `systemctl --user enable`).
- You can check its status with `systemctl --user status field-house.timer` — cron has no equivalent.
- Execution logs (besides the script's own `log.txt`) are available via `journalctl --user -u field-house.service`.
- `Persistent=true` on the timer means that if the session was off/suspended at the moment it was supposed to fire, systemd runs it as soon as it can — no need to wait for the next hour on the clock. This is the direct replacement for what `cron` would solve with an `@reboot` entry.

There are three systemd files:

| File | What it does |
|---|---|
| `field-house.service` | Defines how to run the script (`ExecStart`) |
| `field-house.timer` | Triggers that service every hour (`OnCalendar=hourly`), with `Persistent=true` |
| `field-house-login.service` | Runs the script once at graphical login, with the `--reboot` flag |

`field-house-login.service` exists in addition to the timer's `Persistent=true` because the latter runs "as soon as possible" after boot, which can be before the desktop environment finishes initializing (whichever config subsystem applies: `xfconf` on XFCE, the D-Bus session bus for `gsettings`/`qdbus` on the others). The `--reboot` flag adds a delay (`ESPERA_INICIAL_SEGUNDOS`, 15s by default) to avoid that issue, and it also enables the boot-time location/weather retry in case the network isn't ready yet (see the Weather section).

### Image verification

On startup, the script checks that all 9 wallpaper images exist in `CARPETA_FONDOS`. If any is missing, it doesn't apply any change and logs it — so you find out about a misspelled filename or an incomplete replacement as soon as the script runs, instead of discovering it only when that particular time slot or weather condition comes up.

### Supported desktops

The desktop environment is auto-detected (`detectar_escritorio()`, via `$XDG_CURRENT_DESKTOP` with `$DESKTOP_SESSION` as fallback) on every run; there's no installation step or config field to choose it by hand.

| Desktop | Mechanism to apply the wallpaper |
|---|---|
| XFCE | `xfconf-query` (`last-image` properties) |
| GNOME, Unity, Budgie | `gsettings set org.gnome.desktop.background` |
| Cinnamon | `gsettings set org.cinnamon.desktop.background` |
| MATE | `gsettings set org.mate.background` |
| KDE Plasma | D-Bus script to `plasmashell` (`qdbus6` or `qdbus`) |

If the current desktop isn't recognized, the script logs it and doesn't apply any wallpaper (everything else — time slots, weather, logging — keeps working). The crossfade transition (ImageMagick) is only implemented for XFCE for now: on the other desktops the wallpaper change is direct, no animation (same as on Windows).

### Multi-monitor

On XFCE, the script loops through every `last-image` xfconf property (one per monitor/workspace) and updates all of them, so if you have more than one monitor or several workspaces, they all stay in sync. The property list is fetched **once** per run and reused across the transition steps, avoiding dozens of `xfconf-query` calls. On GNOME/Cinnamon/MATE/KDE, a single background property applies to every monitor at once (nothing to loop over).

## Validation and robustness

The design goal is to **degrade gracefully but fail clearly**: the script survives without network, without ImageMagick, or without a ready graphical session, but when something is misconfigured it announces it clearly and early, instead of producing weird wallpapers or silent failures.

- **Dependencies checked at startup.** Before anything else, it verifies that `curl`, `awk`, `grep`, `tr`, `seq`, `head`, `cut`, and whichever wallpaper command matches the detected desktop — `xfconf-query`, `gsettings`, or `qdbus`/`qdbus6` — exist (only for real runs, not `--dry-run`). If any is missing, the script exits immediately with a logged message. ImageMagick (`convert`/`identify`) is optional: it only produces a notice.
- **Validated configuration.** After loading `config.conf` it validates: `MODO_HORARIOS` (`fijo` or `auto`), the `HORA_INICIO_*` values (`HH:MM` format), `PASOS_TRANSICION`, `PAUSA_ENTRE_PASOS`, the remaining numeric values, and that `CARPETA_FONDOS` is a directory. An invalid value stops the run with a message saying exactly which variable is wrong and how to fix it.
- **Safe, self-cleaning temp files.** The transition frames go to a `mktemp` directory (private permissions), and a `trap` removes it on exit — normal or interrupted. Old versions could leave orphan directories in `/tmp` if the script died halfway; that no longer happens.
- **No silent failures when applying the wallpaper.** On XFCE, if any `last-image` property fails to be set, failures are accumulated and logged (with the affected property names); if there are no `last-image` properties at all (fresh profile), it's reported explicitly. On the other desktops, a failed `gsettings`/`qdbus` call is also logged with detail.
- **Rotated log.** Each line is a single run (24/day), so it grows slowly, but the log is still rotated to `log.txt.1` once it exceeds `MAX_LOG_BYTES` (1 MiB by default), keeping only the most recent copy.
- **`--dry-run` for diagnostics.** `change_wallpaper.sh --dry-run` (optionally with `--reboot`) prints the time slot, weather, and wallpaper that would be applied **without** touching the real desktop, without writing logs or state, and without waits or the lock. It's useful for testing the time/weather logic on any machine — even without a graphical session — and it's the first thing we ask for in a bug report.

## Tests and CI

The project has two layers of automated verification, one per platform, running in parallel on every push/PR (`.github/workflows/shellcheck.yml`, job `shellcheck` for Linux and job `powershell-checks` for Windows):

### Linux

| Step | What it validates |
|---|---|
| `shellcheck` | Bash style and common errors across the 3 scripts |
| `bash -n` | Syntax (without executing) |
| `bats tests/change_wallpaper.bats` | Unit tests for pure functions: time conversion, `validar_configuracion`, and the time-slot + weather decision logic |
| Fixed-mode smoke test | `--dry-run` with minimal config |
| Auto-mode smoke test | `--dry-run` with `MODO_HORARIOS=auto` against the real met.no/ip-api.com APIs (runner connectivity) |
| Full-config smoke test | `--dry-run` with every new variable explicit in `config.conf` |
| Invalid-config smoke test | Confirms an invalid `MODO_HORARIOS` makes the script fail (exit != 0) |

To run the unit tests on your machine before a PR:

```bash
sudo apt install bats   # or: npm install -g bats
bats tests/change_wallpaper.bats
```

The suite uses a guard (`FIELD_HOUSE_SOURCE_ONLY`) that tells `bin/change_wallpaper.sh` that, when sourced, it should define its functions and stop right there — without taking the lock, without touching the network, without reading a real `config.conf`. This way the tests exercise the functions exactly as they exist in production (a single source of truth), instead of a parallel copy of the code that could drift out of sync. The one exception is the time-slot + weather decision logic, which lives in the script's main body (not in a named function): for that part, `tests/change_wallpaper.bats` keeps a deliberate, commented copy (`decidir_fondo_test`), documented at the end of the file — extracting it into a real function (`decidir_fondo()`) is a pending improvement that would remove that duplication.

### Windows

| Step | What it validates |
|---|---|
| AST parsing | Syntax of `Install.ps1` and `Uninstall.ps1` without running them (`[Parser]::ParseFile`) |
| `PSScriptAnalyzer` | Lint over `Install.ps1`, `Uninstall.ps1`, and `Build-Engine.ps1` (`Warning`/`Error` severity; `PSAvoidUsingWriteHost` is excluded on purpose, see the comment in the workflow) |
| Engine compilation | `csc.exe` compiles `FieldHouseEngine.cs` on the runner (same step `Install.ps1` performs); a compilation error fails the job |
| Fixed-mode smoke test | `FieldHouseEngine.exe --dry-run` with minimal config, plus `--version` and `--help` |
| Auto-mode smoke test | `FieldHouseEngine.exe --dry-run` with `ModoHorarios: "auto"` against the real met.no/ip-api.com APIs |
| Invalid-config smoke test | Confirms an invalid `ModoHorarios` makes the executable fail |

To run the lint locally before a PR:

```powershell
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path windows\ -Recurse -Severity Warning,Error -ExcludeRule PSAvoidUsingWriteHost
```

To compile the engine locally and run the smoke tests by hand:

```powershell
.\windows\engine\Build-Engine.ps1 -RutaCsharp .\windows\engine\FieldHouseEngine.cs -RutaExeSalida .\FieldHouseEngine.exe
.\FieldHouseEngine.exe --dry-run
.\FieldHouseEngine.exe --version
.\FieldHouseEngine.exe --help
```

> Note on where this CI comes from: the project's PowerShell code was written and manually reviewed without access to a real PowerShell environment (see the detail in `CHANGELOG.md`, version 1.2.0), which allowed 6 real issues to be caught and fixed during review, but without the guarantee of an actual linter run. This CI job closes that gap starting from the next run onward. The Windows engine was later migrated from PowerShell to C# (compiled with `csc.exe` at install time) to eliminate the console flicker that `-WindowStyle Hidden` couldn't reliably suppress in the Scheduled Task; the CI job was updated in the same change to compile and exercise the resulting `.exe` instead of the previous `.ps1`.

## Windows: differences from Linux

The Windows version (`windows/engine/FieldHouseEngine.cs`, `Install.ps1`, `Uninstall.ps1`) replicates the same business logic as the Linux version — time slots, `auto` mode based on the sun, auto-detected location, weather with caching and retries, configuration validation, log rotation — with the same conceptual names (`config.json` keys are the PascalCase form of the same `config.conf` variables: `ModoHorarios` ↔ `MODO_HORARIOS`, `TtlCacheClima` ↔ `TTL_CACHE_CLIMA`, etc.). Everything in the "Location", "Time slots", "Weather", and "Validation and robustness" sections above applies equally on Windows; this section documents only what **differs** because it's a different platform.

Unlike Linux (where the engine is a bash script interpreted by `bash` on every run), on Windows the engine **is compiled once, at install time**: `Install.ps1` calls `windows\engine\Build-Engine.ps1`, which in turn calls `csc.exe` (the C# compiler bundled with .NET Framework in Windows 10/11 — no need to install the .NET SDK or Visual Studio) to produce `%LOCALAPPDATA%\FieldHouse\bin\FieldHouseEngine.exe`. From then on, both the Scheduled Tasks and a manual invocation run that binary directly; it isn't recompiled again until the next install or reinstall.

| Concept | Linux | Windows |
|---|---|---|
| Engine | `bin/change_wallpaper.sh` (bash, interpreted on every run) | `FieldHouseEngine.exe` (C#, compiled once at install time) |
| Applying the wallpaper | `xfconf-query`, `gsettings`, or `qdbus`/`qdbus6`, depending on the detected desktop | `SystemParametersInfo` (Win32, via P/Invoke) — applies to all monitors at once, no iteration needed |
| Periodic execution | `systemd` user timer | Scheduled Task `FieldHouseWallpaper` (hourly trigger), runs the `.exe` directly |
| Login execution | `field-house-login.service` (`--reboot`) | Scheduled Task `FieldHouseWallpaperLogin` (`AtLogOn` trigger), runs the `.exe` with `--reboot` |
| Anti-concurrency lock | `flock` on a file | `System.Threading.Mutex` with a session-scoped name |
| Configuration | `~/.config/field-house/config.conf` (shell vars) | `%APPDATA%\FieldHouse\config.json` (JSON) |
| Guided reconfiguration | — (edit `config.conf` by hand) | `FieldHouseEngine.exe --config` (interactive console mode) |
| Program and images | `~/.local/share/field-house/` | `%LOCALAPPDATA%\FieldHouse\` |
| Logs and cache | `~/.local/state/field-house/` (separated per XDG) | `%LOCALAPPDATA%\FieldHouse\state\` (Windows doesn't separate this as strictly) |
| HTTP queries | `curl` | `HttpWebRequest` (met.no for weather and sun schedule, ip-api.com for location) |
| JSON parsing | — (config.conf is plain text, not JSON) | Custom JSON parser (`MiniJson`, no external dependencies — see note below) |
| Crossfade transition | Yes, with ImageMagick (optional) | Not available; the change is instant |
| Accepted image formats | JPG (the ones bundled with the project) | JPG (natively supported by `SystemParametersInfo` since Windows 7) |
| Console window during automatic runs | Not applicable (no console concept in a `systemd` service) | None: the `.exe` is compiled as `/target:winexe`, so the Scheduled Task never draws any window |

> **Why a custom JSON parser (`MiniJson`) instead of `System.Text.Json`?** `System.Text.Json` only comes bundled by default starting with .NET Framework 4.7.2; on earlier versions it would require installing the matching NuGet package. Since the project compiles with a single `csc.exe` invocation (no `dotnet restore`, no NuGet package management), a minimal single-file JSON parser/writer was used instead — enough for the flat format `config.json` uses and for the met.no/ip-api.com API responses.

### PowerShell execution policy

Windows blocks `.ps1` script execution by default (`Restricted`). This affects `Install.ps1` **and** `Uninstall.ps1` (the only `.ps1` files left in the Windows project): the installed program itself is a native `.exe`, so it doesn't depend on PowerShell's execution policy to run — the block only shows up when invoking these two management scripts.

The simplest way to avoid it is to use `Install.cmd` and `Uninstall.cmd` instead of the `.ps1` files directly: they're one-line shortcuts that invoke the matching `.ps1` with `-ExecutionPolicy Bypass` scoped to that single run, so there's nothing extra to type and no need to touch your execution policy. They can be run from a console or double-clicked from File Explorer. Any argument you pass to the `.cmd` is forwarded as-is to the `.ps1` (e.g. `Install.cmd -NoBackup`).

If you'd rather run the `.ps1` files directly (scripting, CI, or you're just used to it), use:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

Or, if you'd rather not repeat the prefix for every script you run (from this project or any other), you can raise the policy for your user permanently:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

`RemoteSigned` lets you run local unsigned scripts (like this project's) while still requiring a digital signature for scripts downloaded from the internet — it's the generally recommended option for development, safer than a persistent `Bypass`/`Unrestricted`.

### Scheduled Tasks

`Install.ps1` registers two tasks with `Register-ScheduledTask` (it doesn't use a static `.xml` file, to avoid having to substitute user paths inside a template):

| Task | Trigger | Runs | Linux equivalent |
|---|---|---|---|
| `FieldHouseWallpaper` | Every 1 hour, indefinitely | `FieldHouseEngine.exe` (no arguments) | `field-house.timer` |
| `FieldHouseWallpaperLogin` | At logon (`AtLogOn`) | `FieldHouseEngine.exe --reboot` | `field-house-login.service` |

Both run under the `Interactive` principal of the current user (no password requested or stored) and run the `.exe` directly — unlike earlier versions of the project, they no longer invoke `powershell.exe` or any interpreter in between.

```powershell
# Check status
Get-ScheduledTask -TaskName 'FieldHouseWallpaper', 'FieldHouseWallpaperLogin'

# Check run history
Get-ScheduledTaskInfo -TaskName 'FieldHouseWallpaper'

# Force a manual trigger (instead of running the .exe directly)
Start-ScheduledTask -TaskName 'FieldHouseWallpaper'
```

## Troubleshooting (Linux)

**The timer doesn't run / `systemctl --user status` errors out:**
Confirm the user session bus is active: `systemctl --user status` with no arguments shouldn't fail. On some minimal installs you might need `loginctl enable-linger $USER` so user services keep running even without a graphical session open (shouldn't be necessary for normal desktop use).

**The wallpaper doesn't change even though the script runs fine manually:**
systemd user services should inherit `DISPLAY` and `DBUS_SESSION_BUS_ADDRESS` from the graphical session, but just in case, the script and the `.service` files set them explicitly. If your session isn't `:0`, adjust the `Environment=DISPLAY=:0` line in the `.service` files (in `~/.config/systemd/user/`) and run `systemctl --user daemon-reload`.

**Weather isn't detected correctly:**
Try `curl "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=YOUR_LAT&lon=YOUR_LON" -H "User-Agent: test"` directly in the terminal (with your actual coordinates, visible in `~/.local/state/field-house/ubicacion.cache`) to see the `symbol_code` it returns, and adjust the keyword lists in `bin/change_wallpaper.sh` (overcast: `cloudy|fair|partlycloudy`; rain: `rain|sleet|snow|thunder|fog`) if your weather returns a different symbol. Remember the result is cached for 10 minutes (`TTL_CACHE_CLIMA`); if you want to verify a change, delete `~/.local/state/field-house/clima.cache` and run the script again.

**The log says `AVISO: no se pudo obtener la salida/puesta del sol`:**
Happens with `MODO_HORARIOS="auto"` when the met.no Sunrise 3.0 API query fails or no location is available. Not serious: the script uses the fixed times from `config.conf` for that run and tries again next time. Check your internet or try `curl "https://api.met.no/weatherapi/sunrise/3.0/sun?lat=YOUR_LAT&lon=YOUR_LON&date=$(date +%F)" -H "User-Agent: test"` with your actual coordinates.

**I want to switch from fixed hours to automatic (or back):**
Edit `MODO_HORARIOS` in `~/.config/field-house/config.conf` (`"fijo"` or `"auto"`) and run `~/.local/share/field-house/bin/change_wallpaper.sh` (or wait for the next timer trigger).

**The log says `ERROR: MODO_HORARIOS inválido` (or `HORA_INICIO_... inválida`):**
The script validates the configuration before applying anything. Edit the value named in the message in `~/.config/field-house/config.conf` with the required format (`MODO_HORARIOS` must be `fijo` or `auto`; times as `HH:MM` in 24-hour format) and run the script again.

**The log says `ERROR: faltan comandos requeridos`:**
A system binary is missing. The message lists which ones. Install `curl` (or whichever is missing, e.g. with `sudo apt install <package>`).

**The log says `AVISO: no se encontró ninguna propiedad 'last-image'` (XFCE only):**
The script can't see any wallpaper properties in xfconf. This happens when the graphical session isn't ready yet (ran by hand without an XFCE session open?), or with a freshly created XFCE profile. Run `xfconf-query -c xfce4-desktop -l` to check whether they exist; if not, set a wallpaper from the XFCE menu once.

**The log says some `last-image` properties failed to be set (XFCE), or that `gsettings`/`qdbus` failed (GNOME/Cinnamon/MATE/KDE):**
The script tried to apply the wallpaper but the matching command rejected the value (usually a session/permission issue, or `DISPLAY`/`DBUS_SESSION_BUS_ADDRESS` not resolving correctly). Check the detail in the message and make sure the graphical session is active.

**The log says `AVISO: no se reconoció el entorno de escritorio`:**
`$XDG_CURRENT_DESKTOP` (or `$DESKTOP_SESSION` as fallback) doesn't match any of the supported desktops: XFCE, GNOME, Cinnamon, MATE, KDE Plasma. Run `echo $XDG_CURRENT_DESKTOP` in a terminal from that graphical session to see what value your desktop reports; if you think it should be recognized (e.g. a variant or fork of a supported one), open an issue with that value.

**I want to see which wallpaper would be applied without waiting for the next hour or dirtying the log:**
`~/.local/share/field-house/bin/change_wallpaper.sh --dry-run`. It prints the time slot, weather, and chosen wallpaper without touching anything.

**The log grows too much (or I want to cap its size):**
Each run adds one line, so it's hard for this to be a problem, but if you want to cap it, edit `MAX_LOG_BYTES` in `config.conf` (in bytes; once exceeded, the log rotates to `log.txt.1`).

**There's no internet yet when the computer turns on, so the wallpaper starts without weather:**
That's expected: the network can take a moment to come up. On the login run the script applies the base wallpaper and retries the weather every `ESPERA_REINTENTO_CLIMA` seconds (60s) up to `REINTENTOS_CLIMA_INICIAL` times (3). If that isn't enough (your Wi-Fi takes more than ~3 minutes, or there's no network at all), the wallpaper corrects itself on the next hourly trigger. You can raise both values in `config.conf` if your connection is especially slow.

**The log says images are missing:**
Check that all 9 files are in `~/.local/share/field-house/fondos/` with the exact names from the README's table (all lowercase, hyphen-separated, `.jpg` extension).

**The transition isn't visible, it just snaps:**
Confirm `imagemagick` is installed (`convert -version` shouldn't error out). Also check that `PASOS_TRANSICION` in `config.conf` isn't `0`.

**The wallpaper is stale for a while after turning the computer on:**
Confirm `field-house-login.service` is enabled: `systemctl --user is-enabled field-house-login.service` should say `enabled`. If it still happens, 15 seconds might not be enough on your machine; increase `ESPERA_INICIAL_SEGUNDOS` in `config.conf`.

**I want it to check more often (or less):**
Edit `OnCalendar=hourly` in `~/.config/systemd/user/field-house.timer`, for example to `OnCalendar=*:0/30` for every 30 minutes. Then run `systemctl --user daemon-reload && systemctl --user restart field-house.timer`.

**The automatically detected location isn't correct:**
Location is detected via IP geolocation (`ip-api.com`), which can be off by several kilometers depending on your internet provider — this is normal, especially if your ISP assigns the IP from another city. There's no way to correct it by hand (there's no location field in `config.conf`: it's always auto-detected). If it noticeably affects automatic time mode or the weather, use `MODO_HORARIOS="fijo"` in the meantime.

## Troubleshooting (Windows)

**`Install.ps1` or `Uninstall.ps1` won't run, PowerShell shows an execution-policy error:**
That's Windows's default block for `.ps1` scripts (not a bug in the project). The simplest fix is to use `Install.cmd` / `Uninstall.cmd` instead of the `.ps1` directly — they already have the bypass built in. If you'd rather run the `.ps1` by hand: `powershell -ExecutionPolicy Bypass -File .\Install.ps1` (or `.\Uninstall.ps1`, whichever you're running). Neither approach changes your execution policy permanently.

**`Install.ps1` fails at the "1/3 - Installing files" step with a `csc.exe` error:**
The installer compiles the engine (`FieldHouseEngine.exe`) with `csc.exe`, the C# compiler bundled with Windows 10/11 as part of .NET Framework. If it isn't found at either expected path (`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` or its 32-bit variant), it's likely a trimmed-down Windows edition, or an organizational policy that removed that component. You can check whether it's present with: `Test-Path "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"`. If it's missing, .NET Framework 4.x can usually be reinstalled from Settings → Apps → Optional features.

**The tasks don't run / `Get-ScheduledTask` doesn't show them:**
Confirm the registration succeeded without errors during install (check `Install.ps1`'s output). If you need to retry without reinstalling everything, you can register the tasks by hand by copying the `Register-ScheduledTask` block from `Install.ps1` into a PowerShell console.

**The wallpaper doesn't change even though the engine runs fine manually:**
Run `& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe"` directly and confirm it doesn't error out. If it works by hand but not via the scheduled task, check the "History" tab of `FieldHouseWallpaper` in Task Scheduler (`taskschd.msc`) — that's where Windows logs whether the task fired and its exit code.

**Weather isn't detected correctly:**
Try `Invoke-WebRequest "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=YOUR_LAT&lon=YOUR_LON" -Headers @{"User-Agent"="test"}` in PowerShell (with your actual coordinates, visible in `%LOCALAPPDATA%\FieldHouse\state\ubicacion.cache.json`) and check `.Content` for the `symbol_code` it returns. The same keyword criteria as on Linux apply (overcast: `cloudy|fair|partlycloudy`; rain: `rain|sleet|snow|thunder|fog`), adjustable in `windows/engine/FieldHouseEngine.cs` (the `ClimaCoincide` method, requires recompiling with `Build-Engine.ps1` after the change). The weather cache lives at `%LOCALAPPDATA%\FieldHouse\state\clima.cache.json`; delete it if you need to force a fresh query.

**The log says `AVISO: no se pudo obtener la salida/puesta del sol`:**
Same as on Linux: happens with `"ModoHorarios": "auto"` when the met.no Sunrise 3.0 API query fails or no location is available. The engine uses the fixed times from `config.json` for that run.

**The log says `ERROR: ModoHorarios inválido` (or `HoraInicio... inválida`):**
Run `& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe" --config` to reconfigure step by step with validation as you go, or edit the relevant field by hand in `%APPDATA%\FieldHouse\config.json` with the format the message asks for (`ModoHorarios` must be `"fijo"` or `"auto"`; times as `HH:MM` in 24-hour format) and run the engine again.

**I want to see which wallpaper would be applied without waiting for the next hour:**
`& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe" --dry-run`. It prints the time slot, weather, and chosen wallpaper without touching anything, without writing logs.

**There's no internet yet when the computer turns on, so the wallpaper starts without weather:**
Same as on Linux: the login task retries the weather according to `EsperaReintentoClima`/`ReintentosClimaInicial` in `config.json`, applying the base wallpaper in the meantime. It corrects itself on the next hourly trigger if the network takes longer than that.

**The wallpaper changes but looks "stretched" or has black borders:**
That's Windows's image-fit setting (Settings → Personalization → Background → "Choose a fit"), not something this project controls. The 9 images are 16:9; for them to look right on a monitor with a different aspect ratio, choose "Fill" or "Fit" in that Windows setting (it's a one-time setting, no need to repeat it).

**The automatically detected location isn't correct:**
Same as on Linux: it's IP-based geolocation (`ip-api.com`), it can be off by several kilometers depending on your internet provider. There's no way to correct it by hand (there's no location field in `config.json`: it's always auto-detected, on every run). If it's noticeably off, use `"ModoHorarios": "fijo"` in the meantime.

**I want to uninstall and can't find `Uninstall.ps1`:**
It's in the same `windows\` folder of the repository you cloned — if you deleted that folder, you can remove the tasks by hand with `Unregister-ScheduledTask -TaskName 'FieldHouseWallpaper','FieldHouseWallpaperLogin' -Confirm:$false` and then delete `%LOCALAPPDATA%\FieldHouse` and `%APPDATA%\FieldHouse`.
