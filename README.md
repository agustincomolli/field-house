🇬🇧 [Read this in English](README.en.md)

# The Field House — Live Wallpaper

Cambia automáticamente el fondo de pantalla de **XFCE** (Linux Mint XFCE, Xubuntu, y derivados) según la hora del día y el clima actual — amanecer, mediodía, atardecer o noche, cada uno con su propia versión lluviosa/nublada.

## Características

- 🕐 **Franjas horarias fijas y configurables**: amanecer, mediodía, atardecer y noche, con los horarios que vos definas (**o automáticas según la salida/puesta del sol**, elegible durante la instalación).
- 🌧️ **Clima en tiempo real**: si está nublado o lloviendo, usa una imagen distinta según el momento del día (día, atardecer o noche).
- 🎨 **Transición de fundido** entre un fondo y el siguiente (opcional, requiere ImageMagick).
- 📍 **Detección automática de ubicación** durante la instalación, con confirmación del usuario.
- ⚙️ **Instalación sin sudo**, todo en las rutas estándar de tu usuario (XDG Base Directory).
- 🔁 **Ejecución automática con systemd** (timer por hora + corrección al iniciar sesión), sin tocar `crontab` a mano.
- 🖥️ **Multi-monitor**: actualiza el fondo en todos los monitores y espacios de trabajo.
- 🛡️ **Robusto por diseño**: valida la configuración y las dependencias al arrancar, falla con mensajes claros en vez de hacerlo en silencio, usa temporales seguros con limpieza automática, limita la consulta de clima con caché, y rota el log para que nunca crezca sin control.
- 🔎 **Diagnóstico**: `--dry-run` muestra qué fondo se aplicaría sin tocar nada, ideal para probar o reportar problemas.

## Instalación

Requisitos: Linux Mint XFCE (o cualquier distro con XFCE) con `systemd`, `curl`, y `xfconf-query` (viene con XFCE).

```bash
git clone https://github.com/agustincomolli/field-house.git
cd field-house
chmod +x ./install.sh
./install.sh
```

El instalador va a:
1. Detectar tu ubicación automáticamente (por IP) y pedirte que la confirmes, o que la ingreses a mano si preferís.
2. Preguntarte si querés horarios **fijos** (p. ej. amanecer 06:00 → noche 20:00, siempre iguales) o **automáticos** según la salida y puesta real del sol en tu ciudad.
3. Copiar el programa y las imágenes a `~/.local/share/field-house`.
4. Generar tu configuración en `~/.config/field-house/config.conf`.
5. Habilitar los timers de `systemd` para que el fondo se actualice solo.

> ℹ️ **Reinstalar resguarda lo anterior por defecto.** Si ya tenés una instalación previa, `install.sh` la detecta y, tras confirmar, mueve el programa, las imágenes (incluidas las personalizadas), la configuración y los logs a una copia `.bak.FECHAHORA` antes de instalar la versión nueva. Usá `./install.sh --no-backup` si preferís borrarla directamente sin resguardo. Más detalle en [INSTALACION.md](INSTALACION.md#reinstalar--actualizar).

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
~/.local/share/field-house/bin/change_wallpaper.sh

# Simular sin tocar nada (qué fondo se aplicaría ahora)
~/.local/share/field-house/bin/change_wallpaper.sh --dry-run

# Ver la ayuda completa (opciones, rutas)
~/.local/share/field-house/bin/change_wallpaper.sh --help

# Ver la versión
~/.local/share/field-house/bin/change_wallpaper.sh --version

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

Si querés reemplazar las 9 imágenes incluidas por las tuyas, tienen que ir en `~/.local/share/field-house/fondos/` con estos nombres exactos:

| Archivo | Momento |
|---|---|
| `amanecer.jpg` | Amanecer |
| `mediodia.jpg` | Medio día |
| `tarde.jpg` | Atardecer |
| `noche.jpg` | Noche |
| `nublado-dia.jpg` | Amanecer o mediodía nublado |
| `nublado-noche.jpg` | Noche nublada |
| `lluvia-dia.jpg` | Amanecer o mediodía lluvioso |
| `lluvia-atardecer.jpg` | Atardecer lluvioso |
| `lluvia-noche.jpg` | Noche lluviosa |

> Nota: el atardecer nublado usa `nublado-dia.jpg` (aún hay luz de día); no existe una versión "nublado" propia del atardecer.

## Documentación técnica

Ver [INSTALACION.md](INSTALACION.md) para el detalle de cómo funciona cada parte (franjas horarias, systemd, transición, troubleshooting) y para instrucciones de instalación manual sin `install.sh`.

## Contribuir

Ver [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencia

MIT. Ver [LICENSE](LICENSE).
