🇪🇸 [Leer esto en español](INSTALACION.md)

# Technical documentation — The Field House

This document explains in detail how each part of the program works, and how to install/configure it manually if you'd rather not use `install.sh`.

## Repository structure

```
field-house/
├── bin/
│   └── cambiar_fondo.sh              # The script that does the work
├── fondos/                           # The 9 wallpaper images
├── systemd/
│   ├── field-house.service           # Service that runs the script
│   ├── field-house.timer             # Timer that triggers it hourly
│   └── field-house-login.service     # Service that runs at login
├── .github/workflows/
│   └── shellcheck.yml                # CI: lints the scripts on every push
├── install.sh                        # Interactive installer
├── uninstall.sh                      # Uninstaller
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
cp bin/cambiar_fondo.sh ~/.local/share/field-house/bin/
chmod +x ~/.local/share/field-house/bin/cambiar_fondo.sh
cp fondos/*.jpg ~/.local/share/field-house/fondos/

# 2. Configuration
mkdir -p ~/.config/field-house
cat << 'EOF' > ~/.config/field-house/config.conf
CARPETA_FONDOS="$HOME/.local/share/field-house/fondos"
CIUDAD="CanuelasAR"
HORA_INICIO_AMANECER="06:00"
HORA_INICIO_MEDIODIA="10:00"
HORA_INICIO_ATARDECER="15:00"
HORA_INICIO_NOCHE="20:00"
PASOS_TRANSICION=15
PAUSA_ENTRE_PASOS="0.15"
ESPERA_INICIAL_SEGUNDOS=15
REINTENTOS_CLIMA_INICIAL=3
ESPERA_REINTENTO_CLIMA=60
EOF

# 3. systemd services
mkdir -p ~/.config/systemd/user
cp systemd/*.service systemd/*.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now field-house.timer
systemctl --user enable field-house-login.service
```

Replace `CIUDAD="CanuelasAR"` with your own city (no spaces or accents; you can test what wttr.in recognizes with `curl "https://wttr.in/YourCity?format=%C"`).

> Note: the config keys themselves (`CARPETA_FONDOS`, `CIUDAD`, `HORA_INICIO_AMANECER`, etc.) stay in Spanish, since they're read directly by the script. Only the documentation is translated.

## How each part works

### Fixed time slots

The script uses fixed clock-time blocks, always the same regardless of the season (unlike an earlier version of this project that calculated real sunrise/sunset times — this was simplified on purpose, see below):

- Sunrise: `06:00` → `10:00`
- Midday: `10:00` → `15:00`
- Sunset: `15:00` → `20:00`
- Night: `20:00` → `06:00` (next day)

Edited in `config.conf`, variables `HORA_INICIO_AMANECER`, `HORA_INICIO_MEDIODIA`, `HORA_INICIO_ATARDECER`, `HORA_INICIO_NOCHE`.

> **Why fixed hours instead of the real sunrise/sunset for the day?** Because it simplifies the script considerably (no extra query to a solar schedule API) and gives a more predictable result: you always know which wallpaper you'll see at a given hour, without it drifting with the seasons.

### Weather

On every run, the script queries `wttr.in/YOUR_CITY?format=%C` (just the weather condition, no extra data). Overcast weather and rain are handled as separate conditions and use different images:

- **Overcast** (`overcast`, `cloudy`), the "base" wallpaper for the current time slot is replaced with the matching overcast wallpaper:
  - Overcast sunrise or midday → `nublado-dia.jpg`
  - Overcast sunset → `nublado-dia.jpg` (there's still daylight; there's no separate sunset version)
  - Overcast night → `nublado-noche.jpg`
- **Rain** (`rain`, `drizzle`, `shower`, `thunder`, `mist`, `fog`), replaced with the matching rainy wallpaper:
  - Rainy sunrise or midday → `lluvia-dia.jpg`
  - Rainy sunset → `lluvia-atardecer.jpg`
  - Rainy night → `lluvia-noche.jpg`

If the query fails (no internet, 8-second timeout exceeded), the base wallpaper for the time slot is used without attempting rain or overcast, and it's logged.

**Retry at login:** when the computer boots, the network (especially Wi-Fi) can take a while to come up, sometimes longer than the initial wait from `ESPERA_INICIAL_SEGUNDOS`. So, on the login run (`--reboot` flag), if the query fails the base wallpaper for the time slot is applied right away and the weather is retried every `ESPERA_REINTENTO_CLIMA` seconds (60s by default) up to `REINTENTOS_CLIMA_INICIAL` times (3 by default). If a retry succeeds, the wallpaper crossfades to the weather version; if they run out, the base wallpaper stays until the next hourly trigger. Regular runs (the hourly timer) don't retry: a failure is left for the next hour.

### Crossfade transition

If `imagemagick` is installed, the script doesn't switch wallpapers abruptly: it generates a series of intermediate images blending the previous wallpaper with the new one in increasing proportions (`PASOS_TRANSICION`, 15 by default) and applies them one by one with a short pause between each (`PAUSA_ENTRE_PASOS`, 0.15s), giving a crossfade effect of about ~2 seconds total. Without ImageMagick, or with `PASOS_TRANSICION=0`, the change is instant.

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

The script loops through every `last-image` xfconf property (one per monitor/workspace) and updates all of them, so if you have more than one monitor or several workspaces, they all stay in sync.

## Troubleshooting

**The timer doesn't run / `systemctl --user status` errors out:**
Confirm the user session bus is active: `systemctl --user status` with no arguments shouldn't fail. On some minimal installs you might need `loginctl enable-linger $USER` so user services keep running even without a graphical session open (shouldn't be necessary for normal desktop use).

**The wallpaper doesn't change even though the script runs fine manually:**
systemd user services should inherit `DISPLAY` and `DBUS_SESSION_BUS_ADDRESS` from the graphical session, but just in case, the script and the `.service` files set them explicitly. If your session isn't `:0`, adjust the `Environment=DISPLAY=:0` line in the `.service` files (in `~/.config/systemd/user/`) and run `systemctl --user daemon-reload`.

**Weather isn't detected correctly:**
Try `curl "https://wttr.in/YourCity?format=%C"` directly in the terminal to see the exact text it returns, and adjust the keyword lists in `bin/cambiar_fondo.sh` (overcast: `overcast|cloudy`; rain: `rain|drizzle|shower|thunder|mist|fog`) if your weather returns a different word.

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
