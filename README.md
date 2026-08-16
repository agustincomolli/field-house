🇬🇧 [Read this in English](README.en.md)

# The Field House — Live Wallpaper

Cambia automáticamente el fondo de pantalla de **XFCE** (Linux Mint XFCE, Xubuntu, y derivados) según la hora del día y el clima actual — amanecer, mediodía, atardecer o noche, cada uno con su propia versión lluviosa/nublada.

## Características

- 🕐 **Franjas horarias fijas y configurables**: amanecer, mediodía, atardecer y noche, con los horarios que vos definas.
- 🌧️ **Clima en tiempo real**: si está lloviendo o nublado, usa una imagen distinta según el momento del día (día, atardecer o noche).
- 🎨 **Transición de fundido** entre un fondo y el siguiente (opcional, requiere ImageMagick).
- 📍 **Detección automática de ubicación** durante la instalación, con confirmación del usuario.
- ⚙️ **Instalación sin sudo**, todo en las rutas estándar de tu usuario (XDG Base Directory).
- 🔁 **Ejecución automática con systemd** (timer por hora + corrección al iniciar sesión), sin tocar `crontab` a mano.
- 🖥️ **Multi-monitor**: actualiza el fondo en todos los monitores y espacios de trabajo.

## Instalación

Requisitos: Linux Mint XFCE (o cualquier distro con XFCE) con `systemd`, `curl`, y `xfconf-query` (viene con XFCE).

```bash
git clone https://github.com/TU_USUARIO/field-house.git
cd field-house
./install.sh
```

El instalador va a:
1. Detectar tu ubicación automáticamente (por IP) y pedirte que la confirmes, o que la ingreses a mano si preferís.
2. Copiar el programa y las imágenes a `~/.local/share/field-house`.
3. Generar tu configuración en `~/.config/field-house/config.conf`.
4. Habilitar los timers de `systemd` para que el fondo se actualice solo.

ImageMagick es opcional, solo hace falta si querés la transición de fundido entre fondos:

```bash
sudo apt install imagemagick
```

## Uso

Una vez instalado, no hay que hacer nada más — el fondo se actualiza solo cada hora, y también se corrige apenas iniciás sesión (por si la compu estuvo apagada durante un cambio de franja).

```bash
# Ver el estado del timer
systemctl --user status field-house.timer

# Forzar una actualización ahora mismo
~/.local/share/field-house/bin/cambiar_fondo.sh

# Ver el log
tail -f ~/.local/state/field-house/log.txt

# Editar tu ciudad o los horarios de las franjas
nano ~/.config/field-house/config.conf
```

Después de editar la configuración no hace falta reiniciar nada: el próximo disparo del timer (o la próxima vez que inicies sesión) ya usa los valores nuevos.

## Desinstalar

```bash
./uninstall.sh
```

Te va a preguntar si querés conservar tu configuración y logs por si reinstalás más adelante.

## Usar tus propias imágenes

Si querés reemplazar las 7 imágenes incluidas por las tuyas, tienen que ir en `~/.local/share/field-house/fondos/` con estos nombres exactos:

| Archivo | Momento |
|---|---|
| `amanecer.jpg` | Amanecer |
| `mediodia.jpg` | Medio día |
| `tarde.jpg` | Atardecer |
| `noche.jpg` | Noche |
| `lluvia-dia.jpg` | Amanecer o mediodía nublado/lluvioso |
| `lluvia-atardecer.jpg` | Atardecer nublado/lluvioso |
| `lluvia-noche.jpg` | Noche nublada/lluviosa |

## Documentación técnica

Ver [INSTALACION.md](INSTALACION.md) para el detalle de cómo funciona cada parte (franjas horarias, systemd, transición, troubleshooting) y para instrucciones de instalación manual sin `install.sh`.

## Contribuir

Ver [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencia

MIT. Ver [LICENSE](LICENSE).
