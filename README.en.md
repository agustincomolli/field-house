🇪🇸 [Leer esto en español](README.md)

# The Field House — Live Wallpaper

Automatically changes your desktop wallpaper — on **XFCE** (Linux Mint XFCE, Xubuntu, and derivatives) or on **Windows 10/11** — based on the time of day and the current weather: sunrise, midday, sunset, or night, each with its own rainy/overcast version.

- [🐧 Linux / XFCE installation](#installation-linux)
- [🪟 Windows installation](#installation-windows)

## Features

- 🐧🪟 **Linux (XFCE) and Windows 10/11**: same behavior, same images, each with its own native installer.
- 🕐 **Fixed, configurable time slots**: sunrise, midday, sunset, and night, with whatever schedule you define (**or automatic, based on actual sunrise/sunset**, chosen during installation).
- 🌧️ **Real-time weather**: if it's overcast or raining, uses a different image depending on the time of day (daytime, sunset, or night).
- 🎨 **Crossfade transition** between one wallpaper and the next (Linux only, optional, requires ImageMagick).
- 📍 **Automatic location detection** during installation, with user confirmation.
- ⚙️ **No admin/sudo installation**, everything lives in your user's standard directories (XDG Base Directory on Linux, `%LOCALAPPDATA%`/`%APPDATA%` on Windows).
- 🔁 **Automatic execution** (systemd timer on Linux, Scheduled Tasks on Windows), hourly + login correction, no manual setup.
- 🖥️ **Multi-monitor**: updates the wallpaper on every monitor and workspace.
- 🛡️ **Robust by design**: validates configuration and dependencies at startup, fails with clear messages instead of silently, uses secure temp files with automatic cleanup, rate-limits weather queries with a cache, and rotates the log so it never grows unbounded.
- 🔎 **Diagnostics**: simulation mode (`--dry-run` / `-DryRun`) shows which wallpaper would be applied without touching anything, great for testing or reporting issues.

## Installation (Linux)

Requirements: Linux Mint XFCE (or any XFCE-based distro) with `systemd`, `curl`, and `xfconf-query` (bundled with XFCE).

```bash
git clone https://github.com/agustincomolli/field-house.git
cd field-house
chmod +x ./install.sh
./install.sh
```

The installer will:

1. Automatically detect your location (by IP) and ask you to confirm it, or let you type it manually if you prefer.
2. Ask whether you want **fixed** times (e.g. sunrise 06:00 → night 20:00, always the same) or **automatic** times based on the actual sunrise/sunset in your city.
3. Copy the program and images to `~/.local/share/field-house`.
4. Generate your configuration at `~/.config/field-house/config.conf`.
5. Enable the `systemd` timers so the wallpaper updates on its own.

> ℹ️ **Reinstalling backs up the previous install by default.** If you already have a previous install, `install.sh` detects it and, after confirming, moves the program, images (customized ones included), configuration, and logs to a `.bak.TIMESTAMP` copy before installing the new version. Use `./install.sh --no-backup` if you'd rather delete it directly without a backup. More detail in [INSTALLATION.en.md](INSTALLATION.en.md#reinstalling--updating).

ImageMagick is optional, only needed if you want the crossfade transition between wallpapers:

```bash
sudo apt install imagemagick
```

### Usage (Linux)

Once installed, there's nothing else to do — the wallpaper updates on its own every hour, and also gets corrected as soon as you log in (in case the computer was off during a time-slot change).

```bash
# Check the timer's status
systemctl --user status field-house.timer

# Force an update right now
~/.local/share/field-house/bin/change_wallpaper.sh

# Simulate without touching anything (which wallpaper would be applied)
~/.local/share/field-house/bin/change_wallpaper.sh --dry-run

# Full help (options, paths)
~/.local/share/field-house/bin/change_wallpaper.sh --help

# Show version
~/.local/share/field-house/bin/change_wallpaper.sh --version

# View the log
tail -f ~/.local/state/field-house/log.txt

# Edit your city or the time-slot schedule
nano ~/.config/field-house/config.conf
```

After editing the configuration there's no need to restart anything: the next timer trigger (or your next login) already picks up the new values.

### Uninstalling (Linux)

```bash
./uninstall.sh
```

It will ask whether you want to keep your configuration and logs in case you reinstall later.

## Installation (Windows)

Requirements: Windows 10 or Windows 11, with PowerShell (bundled with both — nothing extra to install). No administrator privileges required: everything installs into your user folder.

```powershell
git clone https://github.com/agustincomolli/field-house.git
cd field-house\windows
.\Install.ps1
```

> If PowerShell blocks the script with an execution-policy message, run this instead: `powershell -ExecutionPolicy Bypass -File .\Install.ps1`. The installer doesn't change your global execution policy — the Scheduled Task it creates invokes the engine with the bypass scoped to that single run, so you don't need to touch `Set-ExecutionPolicy` permanently.

The installer will:

1. Automatically detect your location (by IP) and ask you to confirm it, or let you type it manually if you prefer.
2. Ask whether you want **fixed** times or **automatic** times based on the actual sunrise/sunset in your city (same options as on Linux).
3. Copy the program and images to `%LOCALAPPDATA%\FieldHouse`.
4. Generate your configuration at `%APPDATA%\FieldHouse\config.json`.
5. Register two Scheduled Tasks: one that runs hourly, and one that runs at login.

> ℹ️ **Reinstalling backs up the previous install by default.** Same as on Linux: if you already have a previous install, `Install.ps1` detects it and, after confirming, moves the program, customized images, and configuration to a `.bak.TIMESTAMP` copy before installing the new one. Use `.\Install.ps1 -NoBackup` if you'd rather delete it directly without a backup.

> The Windows version has no crossfade transition between wallpapers (that feature depends on ImageMagick, which isn't installed on this platform): the wallpaper change is instant.

### Usage (Windows)

```powershell
# Check the tasks' status
Get-ScheduledTask -TaskName 'FieldHouseWallpaper', 'FieldHouseWallpaperLogin'

# Force an update right now
& "$env:LOCALAPPDATA\FieldHouse\bin\Change-Wallpaper.ps1"

# Simulate without touching anything (which wallpaper would be applied)
& "$env:LOCALAPPDATA\FieldHouse\bin\Change-Wallpaper.ps1" -DryRun

# Full help
& "$env:LOCALAPPDATA\FieldHouse\bin\Change-Wallpaper.ps1" -Help

# View the log
Get-Content "$env:LOCALAPPDATA\FieldHouse\state\log.txt" -Tail 20 -Wait

# Edit your city or the time-slot schedule
notepad "$env:APPDATA\FieldHouse\config.json"
```

### Uninstalling (Windows)

```powershell
.\Uninstall.ps1
```

It will ask whether you want to keep your configuration in case you reinstall later.

## Using your own images

If you want to replace the 9 included images with your own, they need to go in the `fondos` folder of your install, with these exact names:

- **Linux**: `~/.local/share/field-house/fondos/`
- **Windows**: `%LOCALAPPDATA%\FieldHouse\fondos\`

| File                   | Moment                     |
| ---------------------- | -------------------------- |
| `amanecer.jpg`         | Sunrise                    |
| `mediodia.jpg`         | Midday                     |
| `tarde.jpg`            | Sunset                     |
| `noche.jpg`            | Night                      |
| `nublado-dia.jpg`      | Overcast sunrise or midday |
| `nublado-noche.jpg`    | Overcast night             |
| `lluvia-dia.jpg`       | Rainy sunrise or midday    |
| `lluvia-atardecer.jpg` | Rainy sunset               |
| `lluvia-noche.jpg`     | Rainy night                |

> Note: an overcast sunset uses `nublado-dia.jpg` (there's still daylight); there's no separate "overcast" image for sunset.

> Note: the filenames themselves stay in Spanish on both platforms (folder `fondos`, files like `amanecer.jpg`), since they're read directly by the engine. Only the documentation is translated.

## Technical documentation

See [INSTALACION.md](INSTALACION.md) (Spanish) or [INSTALLATION.en.md](INSTALLATION.en.md) (English) for details on how each part works (time slots, systemd, transition, troubleshooting), and for manual installation instructions without `install.sh`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (Spanish; open an issue in English if you'd prefer, it'll be answered in English too).

## License

MIT. See [LICENSE](LICENSE).
