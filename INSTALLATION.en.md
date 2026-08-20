🇪🇸 [Leer esto en español](INSTALACION.md)

# Technical documentation — The Field House

This document explains in detail how each part of the program works, and how to install/configure it manually if you'd rather not use `install.sh`.

## Repository structure

```
field-house/
├── bin/
│   └── change_wallpaper.sh           # Linux/XFCE engine
├── windows/
│   ├── Change-Wallpaper.ps1          # Windows 10/11 engine
│   ├── Install.ps1                   # Windows installer
│   └── Uninstall.ps1                 # Windows uninstaller
├── fondos/                           # The 9 wallpaper images (shared by both platforms)
├── systemd/
│   ├── field-house.service           # Service that runs the Linux engine
│   ├── field-house.timer             # Timer that triggers it hourly
│   └── field-house-login.service     # Service that runs at login
├── .github/workflows/
│   └── shellcheck.yml                # CI: lints the bash scripts on every push
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
CIUDAD="CanuelasAR"
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

Replace `CIUDAD="CanuelasAR"` with your own city (no spaces or accents; you can test what wttr.in recognizes with `curl "https://wttr.in/YourCity?format=%C"`). Note that missing values in an older `config.conf` fall back to the script's defaults, so adding new variables doesn't break existing installs.

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

> Note: the config keys themselves (`CARPETA_FONDOS`, `CIUDAD`, `HORA_INICIO_AMANECER`, etc.) stay in Spanish, since they're read directly by the script. Only the documentation is translated.

## How each part works

### Time slots

The script uses time blocks to decide which wallpaper applies. There are two modes, chosen during installation (`MODO_HORARIOS`):

- **Fixed** (default, the original behavior): constant clock-time blocks, always the same regardless of the season:

  - Sunrise: `06:00` → `10:00`
  - Midday: `10:00` → `15:00`
  - Sunset: `15:00` → `20:00`
  - Night: `20:00` → `06:00` (next day)

- **Automatic** (`MODO_HORARIOS="auto"`): the slots are computed from the *actual* sunrise/sunset in your city (see the next subsection).

In both modes the boundaries can be adjusted in `config.conf`: in fixed mode the `HORA_INICIO_AMANECER`, `HORA_INICIO_MEDIODIA`, `HORA_INICIO_ATARDECER`, `HORA_INICIO_NOCHE` variables are the ones that matter; in auto mode they act as fallback when the sun query fails.

> **Why fixed hours instead of the real sunrise/sunset for the day?** Because they give the most predictable result: you always know which wallpaper you'll see at a given hour, without it drifting with the seasons. It's the default option; if you'd rather follow the seasons, choose automatic mode during installation.

#### Automatic mode (MODO_HORARIOS="auto")

On each run (with a daily cache, to be gentle to the API), the script queries `wttr.in/CITY?format=j1` and extracts the day's `sunrise` and `sunset`:

- **Sunrise** = actual sunrise time.
- **Sunset** = actual sunset time.
- **Midday** = the exact midpoint between sunrise and sunset.
- **Night** = sunset + 2 hours (once it's fully dark).

The result is saved to `~/.local/state/field-house/horarios-sol.cache` and reused throughout the day (requeried when the date changes). If the query fails (no internet, invalid city), the script logs a notice and falls back to the fixed times in `config.conf`.

> ⚠️ **Time zone.** The calculation assumes your machine's clock is in the same time zone as `CIUDAD` (the normal case: you set the city where you live). If the city were in a different time zone than your clock, the slots wouldn't match the expected wallpaper; in that case use fixed mode or adjust the system time zone.

### Weather

On every run, the script queries `wttr.in/YOUR_CITY?format=%C` (just the weather condition, no extra data). The query uses a short timeout (`--connect-timeout 2 --max-time 6`): it never waits longer than 6 seconds total, and doesn't hang on DNS. Overcast weather and rain are handled as separate conditions and use different images:

- **Overcast** (`overcast`, `cloudy`), the "base" wallpaper for the current time slot is replaced with the matching overcast wallpaper:
  - Overcast sunrise or midday → `nublado-dia.jpg`
  - Overcast sunset → `nublado-dia.jpg` (there's still daylight; there's no separate sunset version)
  - Overcast night → `nublado-noche.jpg`
- **Rain** (`rain`, `drizzle`, `shower`, `thunder`, `mist`, `fog`), replaced with the matching rainy wallpaper:
  - Rainy sunrise or midday → `lluvia-dia.jpg`
  - Rainy sunset → `lluvia-atardecer.jpg`
  - Rainy night → `lluvia-noche.jpg`

If the query fails (no internet, timeout exceeded, invalid city), the base wallpaper for the time slot is used without attempting rain or overcast, and it's logged.

**Weather cache:** since the query is a network call, the result is saved to `~/.local/state/field-house/clima.cache` and reused for `TTL_CACHE_CLIMA` seconds (10 minutes by default). This avoids redundant queries when the hourly timer and the login service fire almost at the same time — which, in turn, is respectful of the free wttr.in service.

**Retry at login:** when the computer boots, the network (especially Wi-Fi) can take a while to come up, sometimes longer than the initial wait from `ESPERA_INICIAL_SEGUNDOS`. So, on the login run (`--reboot` flag), if the query fails the base wallpaper for the time slot is applied right away and the weather is retried every `ESPERA_REINTENTO_CLIMA` seconds (60s by default) up to `REINTENTOS_CLIMA_INICIAL` times (3 by default). If a retry succeeds, the wallpaper crossfades to the weather version; if they run out, the base wallpaper stays until the next hourly trigger. Regular runs (the hourly timer) don't retry: a failure is left for the next hour.

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

`field-house-login.service` exists in addition to the timer's `Persistent=true` because the latter runs "as soon as possible" after boot, which can be before XFCE finishes initializing `xfconf`. The `--reboot` flag adds a delay (`ESPERA_INICIAL_SEGUNDOS`, 15s by default) to avoid that issue, and it also enables the boot-time weather retry in case the network isn't ready yet (see the Weather section).

### Image verification

On startup, the script checks that all 9 wallpaper images exist in `CARPETA_FONDOS`. If any is missing, it doesn't apply any change and logs it — so you find out about a misspelled filename or an incomplete replacement as soon as the script runs, instead of discovering it only when that particular time slot or weather condition comes up.

### Multi-monitor

The script loops through every `last-image` xfconf property (one per monitor/workspace) and updates all of them, so if you have more than one monitor or several workspaces, they all stay in sync. The property list is fetched **once** per run and reused across the transition steps, avoiding dozens of `xfconf-query` calls.

## Validation and robustness

The design goal is to **degrade gracefully but fail clearly**: the script survives without network, without ImageMagick, or without a ready XFCE session, but when something is misconfigured it announces it clearly and early, instead of producing weird wallpapers or silent failures.

- **Dependencies checked at startup.** Before anything else, it verifies that `curl`, `xfconf-query` (only for real runs, not `--dry-run`), `awk`, `grep`, `tr`, `seq`, `head`, and `cut` exist. If any is missing, the script exits immediately with a logged message. ImageMagick (`convert`/`identify`) is optional: it only produces a notice.
- **Validated configuration.** After loading `config.conf` it validates: `CIUDAD` (letters/numbers and `. , _ -` only, so the wttr.in URL doesn't break), `MODO_HORARIOS` (`fijo` or `auto`), the `HORA_INICIO_*` values (`HH:MM` format), `PASOS_TRANSICION`, `PAUSA_ENTRE_PASOS`, the remaining numeric values, and that `CARPETA_FONDOS` is a directory. An invalid value stops the run with a message saying exactly which variable is wrong and how to fix it.
- **Safe, self-cleaning temp files.** The transition frames go to a `mktemp` directory (private permissions), and a `trap` removes it on exit — normal or interrupted. Old versions could leave orphan directories in `/tmp` if the script died halfway; that no longer happens.
- **No silent xfconf failures.** If any `last-image` property fails to be set, failures are accumulated and logged (with the affected property names). If there are no `last-image` properties at all (fresh XFCE profile), it's reported explicitly.
- **Rotated log.** Each line is a single run (24/day), so it grows slowly, but the log is still rotated to `log.txt.1` once it exceeds `MAX_LOG_BYTES` (1 MiB by default), keeping only the most recent copy.
- **`--dry-run` for diagnostics.** `change_wallpaper.sh --dry-run` (optionally with `--reboot`) prints the time slot, weather, and wallpaper that would be applied **without** touching xfconf, without writing logs or state, and without waits or the lock. It's useful for testing the time/weather logic on any machine, and it's the first thing we ask for in a bug report.

## Windows: differences from Linux

The Windows version (`windows/Change-Wallpaper.ps1`, `Install.ps1`, `Uninstall.ps1`) replicates the same business logic as the Linux version — time slots, `auto` mode based on the sun, weather with caching and retries, configuration validation, log rotation — with the same conceptual names (`config.json` keys are the PascalCase form of the same `config.conf` variables: `Ciudad` ↔ `CIUDAD`, `ModoHorarios` ↔ `MODO_HORARIOS`, etc.). Everything in the "Time slots", "Weather", and "Validation and robustness" sections above applies equally on Windows; this section documents only what **differs** because it's a different platform.

| Concept | Linux | Windows |
|---|---|---|
| Applying the wallpaper | `xfconf-query` (XFCE `last-image` properties) | `SystemParametersInfo` (Win32, via P/Invoke) — applies to all monitors at once, no iteration needed |
| Periodic execution | `systemd` user timer | Scheduled Task `FieldHouseWallpaper` (hourly trigger) |
| Login execution | `field-house-login.service` (`--reboot`) | Scheduled Task `FieldHouseWallpaperLogin` (`AtLogOn` trigger, with `-Reboot`) |
| Anti-concurrency lock | `flock` on a file | `System.Threading.Mutex` with a session-scoped name |
| Configuration | `~/.config/field-house/config.conf` (shell vars) | `%APPDATA%\FieldHouse\config.json` (JSON) |
| Program and images | `~/.local/share/field-house/` | `%LOCALAPPDATA%\FieldHouse\` |
| Logs and cache | `~/.local/state/field-house/` (separated per XDG) | `%LOCALAPPDATA%\FieldHouse\state\` (Windows doesn't separate this as strictly) |
| HTTP queries | `curl` | `Invoke-WebRequest` (weather, plain text) / `Invoke-RestMethod` (sun schedule and geolocation, JSON) |
| Crossfade transition | Yes, with ImageMagick (optional) | Not available; the change is instant |
| Accepted image formats | JPG (the ones bundled with the project) | JPG (natively supported by `SystemParametersInfo` since Windows 7) |

### PowerShell execution policy

Windows blocks `.ps1` script execution by default (`Restricted`). Instead of asking you to change that policy globally and permanently with `Set-ExecutionPolicy`, both `Install.ps1` and the Scheduled Tasks it installs invoke the interpreter with `-ExecutionPolicy Bypass` scoped **to that single invocation**: your system-wide execution policy is never touched. If running `.\Install.ps1` directly gets blocked, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
```

### Scheduled Tasks

`Install.ps1` registers two tasks with `Register-ScheduledTask` (it doesn't use a static `.xml` file, to avoid having to substitute user paths inside a template):

| Task | Trigger | Linux equivalent |
|---|---|---|
| `FieldHouseWallpaper` | Every 1 hour, indefinitely | `field-house.timer` |
| `FieldHouseWallpaperLogin` | At logon (`AtLogOn`), with `-Reboot` | `field-house-login.service` |

Both run under the `Interactive` principal of the current user (no password requested or stored) and use the same PowerShell executable (`powershell.exe` or `pwsh.exe`) that ran `Install.ps1`.

```powershell
# Check status
Get-ScheduledTask -TaskName 'FieldHouseWallpaper', 'FieldHouseWallpaperLogin'

# Check run history
Get-ScheduledTaskInfo -TaskName 'FieldHouseWallpaper'

# Force a manual trigger (instead of running the script directly)
Start-ScheduledTask -TaskName 'FieldHouseWallpaper'
```

## Troubleshooting (Linux)

**The timer doesn't run / `systemctl --user status` errors out:**
Confirm the user session bus is active: `systemctl --user status` with no arguments shouldn't fail. On some minimal installs you might need `loginctl enable-linger $USER` so user services keep running even without a graphical session open (shouldn't be necessary for normal desktop use).

**The wallpaper doesn't change even though the script runs fine manually:**
systemd user services should inherit `DISPLAY` and `DBUS_SESSION_BUS_ADDRESS` from the graphical session, but just in case, the script and the `.service` files set them explicitly. If your session isn't `:0`, adjust the `Environment=DISPLAY=:0` line in the `.service` files (in `~/.config/systemd/user/`) and run `systemctl --user daemon-reload`.

**Weather isn't detected correctly:**
Try `curl "https://wttr.in/YourCity?format=%C"` directly in the terminal to see the exact text it returns, and adjust the keyword lists in `bin/change_wallpaper.sh` (overcast: `overcast|cloudy`; rain: `rain|drizzle|shower|thunder|mist|fog`) if your weather returns a different word. Remember the result is cached for 10 minutes (`TTL_CACHE_CLIMA`); if you change your city or want to verify a change, delete `~/.local/state/field-house/clima.cache` and run the script again.

**The log says `AVISO: no se pudo obtener la salida/puesta del sol`:**
Happens with `MODO_HORARIOS="auto"` when the wttr.in query (`j1` format) fails or your city doesn't resolve. Not serious: the script uses the fixed times from `config.conf` for that run and tries again next time. Check your internet or try `curl "https://wttr.in/YourCity?format=j1"`.

**I want to switch from fixed hours to automatic (or back):**
Edit `MODO_HORARIOS` in `~/.config/field-house/config.conf` (`"fijo"` or `"auto"`) and run `~/.local/share/field-house/bin/change_wallpaper.sh` (or wait for the next timer trigger).

**The log says `ERROR: CIUDAD inválida` (or `HORA_INICIO_... inválida`):**
The script validates the configuration before applying anything. Edit the value named in the message in `~/.config/field-house/config.conf` with the required format (city with no spaces or accents; times as `HH:MM` in 24-hour format) and run the script again.

**The log says `ERROR: faltan comandos requeridos`:**
A system binary is missing. The message lists which ones. Install `curl` (or whichever is missing, e.g. with `sudo apt install <package>`).

**The log says `AVISO: no se encontró ninguna propiedad 'last-image'`:**
The script can't see any wallpaper properties in xfconf. This happens when the graphical session isn't ready yet (ran by hand without an XFCE session open?), or with a freshly created XFCE profile. Run `xfconf-query -c xfce4-desktop -l` to check whether they exist; if not, set a wallpaper from the XFCE menu once.

**The log says some `last-image` properties failed to be set:**
The script tried to apply the wallpaper but one or more properties rejected the value (usually a session/permission issue or DISPLAY). Check the property list in the message and make sure the graphical session is active.

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

**The location automatically detected during install wasn't correct:**
The installer uses IP-based geolocation, which can be off by several kilometers depending on your internet provider. Just edit `CIUDAD` in `~/.config/field-house/config.conf` with the right value.

## Troubleshooting (Windows)

**`Install.ps1` won't run, PowerShell shows an execution-policy error:**
That's Windows's default block for `.ps1` scripts (not a bug in the project). Run this instead: `powershell -ExecutionPolicy Bypass -File .\Install.ps1`. This doesn't change your execution policy permanently, only for that one run.

**The tasks don't run / `Get-ScheduledTask` doesn't show them:**
Confirm the registration succeeded without errors during install (check `Install.ps1`'s output). If you need to retry without reinstalling everything, you can register the tasks by hand by copying the `Register-ScheduledTask` block from `Install.ps1` into a PowerShell console.

**The wallpaper doesn't change even though the script runs fine manually:**
Run `& "$env:LOCALAPPDATA\FieldHouse\bin\Change-Wallpaper.ps1"` directly and confirm it doesn't error out. If it works by hand but not via the scheduled task, check the "History" tab of `FieldHouseWallpaper` in Task Scheduler (`taskschd.msc`) — that's where Windows logs whether the task fired and its exit code.

**Weather isn't detected correctly:**
Try `Invoke-WebRequest "https://wttr.in/YourCity?format=%C"` in PowerShell and check `.Content` for the exact text it returns. The same keyword criteria as on Linux apply (overcast: `overcast|cloudy`; rain: `rain|drizzle|shower|thunder|mist|fog`), adjustable in `windows/Change-Wallpaper.ps1`. The weather cache lives at `%LOCALAPPDATA%\FieldHouse\state\clima.cache.json`; delete it if you need to force a fresh query.

**The log says `AVISO: no se pudo obtener la salida/puesta del sol`:**
Same as on Linux: happens with `"ModoHorarios": "auto"` when the wttr.in query fails or your city doesn't resolve. The script uses the fixed times from `config.json` for that run.

**The log says `ERROR: Ciudad inválida` (or `HoraInicio... inválida`):**
Edit the relevant field in `%APPDATA%\FieldHouse\config.json` with the format the message asks for (city with no spaces or accents; times as `HH:MM` in 24-hour format) and run the script again.

**I want to see which wallpaper would be applied without waiting for the next hour:**
`& "$env:LOCALAPPDATA\FieldHouse\bin\Change-Wallpaper.ps1" -DryRun`. It prints the time slot, weather, and chosen wallpaper without touching anything, without writing logs.

**There's no internet yet when the computer turns on, so the wallpaper starts without weather:**
Same as on Linux: the login task retries the weather according to `EsperaReintentoClima`/`ReintentosClimaInicial` in `config.json`, applying the base wallpaper in the meantime. It corrects itself on the next hourly trigger if the network takes longer than that.

**The wallpaper changes but looks "stretched" or has black borders:**
That's Windows's image-fit setting (Settings → Personalization → Background → "Choose a fit"), not something this project controls. The 9 images are 16:9; for them to look right on a monitor with a different aspect ratio, choose "Fill" or "Fit" in that Windows setting (it's a one-time setting, no need to repeat it).

**The location automatically detected during install wasn't correct:**
Same as on Linux: it's IP-based geolocation, it can be off. Edit `Ciudad` in `%APPDATA%\FieldHouse\config.json` with the right value.

**I want to uninstall and can't find `Uninstall.ps1`:**
It's in the same `windows\` folder of the repository you cloned — if you deleted that folder, you can remove the tasks by hand with `Unregister-ScheduledTask -TaskName 'FieldHouseWallpaper','FieldHouseWallpaperLogin' -Confirm:$false` and then delete `%LOCALAPPDATA%\FieldHouse` and `%APPDATA%\FieldHouse`.
