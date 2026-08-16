🇪🇸 [Leer esto en español](README.md)

# The Field House — Live Wallpaper

Automatically changes your **XFCE** desktop wallpaper (Linux Mint XFCE, Xubuntu, and derivatives) based on the time of day and the current weather — sunrise, midday, sunset, or night, each with its own rainy/overcast version.

## Features

- 🕐 **Fixed, configurable time slots**: sunrise, midday, sunset, and night, with whatever schedule you define.
- 🌧️ **Real-time weather**: if it's raining or overcast, uses a different image depending on the time of day (daytime, sunset, or night).
- 🎨 **Crossfade transition** between one wallpaper and the next (optional, requires ImageMagick).
- 📍 **Automatic location detection** during installation, with user confirmation.
- ⚙️ **No-sudo installation**, everything lives in your user's standard directories (XDG Base Directory).
- 🔁 **Automatic execution via systemd** (hourly timer + login correction), no manual `crontab` editing.
- 🖥️ **Multi-monitor**: updates the wallpaper on every monitor and workspace.

## Installation

Requirements: Linux Mint XFCE (or any XFCE-based distro) with `systemd`, `curl`, and `xfconf-query` (bundled with XFCE).

```bash
git clone https://github.com/YOUR_USERNAME/field-house.git
cd field-house
./install.sh
```

The installer will:
1. Automatically detect your location (by IP) and ask you to confirm it, or let you type it manually if you prefer.
2. Copy the program and images to `~/.local/share/field-house`.
3. Generate your configuration at `~/.config/field-house/config.conf`.
4. Enable the `systemd` timers so the wallpaper updates on its own.

ImageMagick is optional, only needed if you want the crossfade transition between wallpapers:

```bash
sudo apt install imagemagick
```

## Usage

Once installed, there's nothing else to do — the wallpaper updates on its own every hour, and also gets corrected as soon as you log in (in case the computer was off during a time-slot change).

```bash
# Check the timer's status
systemctl --user status field-house.timer

# Force an update right now
~/.local/share/field-house/bin/cambiar_fondo.sh

# View the log
tail -f ~/.local/state/field-house/log.txt

# Edit your city or the time-slot schedule
nano ~/.config/field-house/config.conf
```

After editing the configuration there's no need to restart anything: the next timer trigger (or your next login) already picks up the new values.

## Uninstalling

```bash
./uninstall.sh
```

It will ask whether you want to keep your configuration and logs in case you reinstall later.

## Using your own images

If you want to replace the 7 included images with your own, they need to go in `~/.local/share/field-house/fondos/` with these exact names:

| File | Moment |
|---|---|
| `amanecer.jpg` | Sunrise |
| `mediodia.jpg` | Midday |
| `tarde.jpg` | Sunset |
| `noche.jpg` | Night |
| `lluvia-dia.jpg` | Overcast/rainy sunrise or midday |
| `lluvia-atardecer.jpg` | Overcast/rainy sunset |
| `lluvia-noche.jpg` | Overcast/rainy night |

> Note: the folder is named `fondos` (Spanish for "wallpapers") and the filenames themselves stay in Spanish, since they're read directly by the script and by `config.conf`. Only the documentation is translated.

## Technical documentation

See [INSTALACION.md](INSTALACION.md) (Spanish) or [INSTALLATION.en.md](INSTALLATION.en.md) (English) for details on how each part works (time slots, systemd, transition, troubleshooting), and for manual installation instructions without `install.sh`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (Spanish; open an issue in English if you'd prefer, it'll be answered in English too).

## License

MIT. See [LICENSE](LICENSE).
