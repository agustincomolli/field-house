🇬🇧 [Read this in English](README.en.md)

# The Field House — Live Wallpaper

Cambia automáticamente el fondo de pantalla — de **Linux** (XFCE, GNOME, Cinnamon, MATE, KDE Plasma) o de **Windows 10/11** — según la hora del día y el clima actual: amanecer, mediodía, atardecer o noche, cada uno con su propia versión lluviosa/nublada.

- [🐧 Instalación en Linux](#instalación-linux)
- [🪟 Instalación en Windows](#instalación-windows)

## Características

- 🐧🪟 **Linux (XFCE, GNOME, Cinnamon, MATE, KDE Plasma) y Windows 10/11**: mismo comportamiento, mismas imágenes, cada uno con su instalador nativo. El escritorio Linux se detecta automáticamente en cada ejecución, sin configuración.
- 🕐 **Franjas horarias fijas y configurables**: amanecer, mediodía, atardecer y noche, con los horarios que vos definas (**o automáticas según la salida/puesta del sol**, elegible durante la instalación).
- 🌧️ **Clima en tiempo real**: si está nublado o lloviendo, usa una imagen distinta según el momento del día (día, atardecer o noche).
- 🎨 **Transición de fundido** entre un fondo y el siguiente (solo Linux, opcional, requiere ImageMagick).
- 📍 **Ubicación totalmente automática**: se detecta por IP en cada arranque, sin que el usuario configure nada; si en algún momento no hay red, se usa la última ubicación conocida.
- ⚙️ **Instalación sin privilegios de administrador**, todo en las rutas estándar de tu usuario (XDG Base Directory en Linux, `%LOCALAPPDATA%`/`%APPDATA%` en Windows).
- 🔁 **Ejecución automática** (timer de systemd en Linux, Tareas Programadas en Windows) por hora + corrección al iniciar sesión, sin configurarlo a mano.
- 🖥️ **Multi-monitor**: actualiza el fondo en todos los monitores y espacios de trabajo.
- 🛡️ **Robusto por diseño**: valida la configuración y las dependencias al arrancar, falla con mensajes claros en vez de hacerlo en silencio, usa temporales seguros con limpieza automática, limita la consulta de clima con caché, y rota el log para que nunca crezca sin control.
- 🔎 **Diagnóstico**: el modo simulación (`--dry-run`) muestra qué fondo se aplicaría sin tocar nada, ideal para probar o reportar problemas.

## Instalación (Linux)

Requisitos: `systemd`, `curl`, y el comando que corresponda a tu escritorio: `xfconf-query` (XFCE), `gsettings` (GNOME, Cinnamon, MATE) o `qdbus`/`qdbus6` (KDE Plasma). El escritorio se detecta solo; no hace falta indicarlo.

```bash
git clone https://github.com/agustincomolli/field-house.git
cd field-house
chmod +x ./install.sh
./install.sh
```

El instalador va a:

1. Preguntarte si querés horarios **fijos** (p. ej. amanecer 06:00 → noche 20:00, siempre iguales) o **automáticos** según la salida y puesta real del sol en tu ubicación (detectada automáticamente por IP en cada ejecución, sin que tengas que configurar nada).
2. Copiar el programa y las imágenes a `~/.local/share/field-house`.
3. Generar tu configuración en `~/.config/field-house/config.conf`.
4. Habilitar los timers de `systemd` para que el fondo se actualice solo.

> ℹ️ **Reinstalar resguarda lo anterior por defecto.** Si ya tenés una instalación previa, `install.sh` la detecta y, tras confirmar, mueve el programa, las imágenes (incluidas las personalizadas), la configuración y los logs a una copia `.bak.FECHAHORA` antes de instalar la versión nueva. Usá `./install.sh --no-backup` si preferís borrarla directamente sin resguardo. Más detalle en [INSTALACION.md](INSTALACION.md#reinstalar--actualizar).

ImageMagick es opcional, solo hace falta si querés la transición de fundido entre fondos:

```bash
sudo apt install imagemagick
```

### Uso (Linux)

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

# Editar los horarios de las franjas (la ubicación no se edita: es automática)
nano ~/.config/field-house/config.conf
```

Después de editar la configuración no hace falta reiniciar nada: el próximo disparo del timer (o la próxima vez que inicies sesión) ya usa los valores nuevos.

### Desinstalar (Linux)

```bash
./uninstall.sh
```

Te va a preguntar si querés conservar tu configuración y logs por si reinstalás más adelante.

## Instalación (Windows)

Requisitos: Windows 10 o Windows 11. No requiere permisos de administrador: todo se instala en tu carpeta de usuario. El instalador se corre con PowerShell (viene de fábrica), pero el programa que queda instalado y corriendo todo el tiempo es un **ejecutable nativo en C#** (`FieldHouseEngine.exe`), no un script de PowerShell — arranca en milisegundos y la Tarea Programada lo ejecuta sin abrir ninguna ventana de consola.

```powershell
git clone https://github.com/agustincomolli/field-house.git
cd field-house\windows
.\Install.cmd
```

> `Install.cmd` es un atajo que corre `Install.ps1` con el bypass de política de ejecución de PowerShell ya resuelto — no hace falta escribir nada extra ni tocar tu configuración de PowerShell. También podés hacerle doble clic desde el Explorador de archivos. Si preferís correr el `.ps1` directo (por ejemplo para pasarle `-NoBackup` u otros flags), usá: `powershell -ExecutionPolicy Bypass -File .\Install.ps1`. El mismo bloqueo (y la misma solución) aplica más adelante al desinstalar.

El instalador va a:

1. Preguntarte si querés horarios **fijos** o **automáticos** según la salida y puesta real del sol en tu ubicación (detectada automáticamente por IP en cada ejecución, mismo comportamiento que en Linux).
2. Compilar el motor (`FieldHouseEngine.exe`) con `csc.exe` — el compilador de C# incluido de fábrica en Windows 10/11, sin instalar nada adicional — y copiar el programa y las imágenes a `%LOCALAPPDATA%\FieldHouse`.
3. Generar tu configuración en `%APPDATA%\FieldHouse\config.json`.
4. Registrar dos Tareas Programadas: una que corre cada hora, y otra que corre al iniciar sesión.

> ℹ️ **Reinstalar resguarda lo anterior por defecto.** Igual que en Linux: si ya tenés una instalación previa, `Install.ps1` la detecta y, tras confirmar, mueve el programa, las imágenes personalizadas y la configuración a una copia `.bak.FECHAHORA` antes de instalar la nueva. Usá `.\Install.cmd -NoBackup` (o `powershell -ExecutionPolicy Bypass -File .\Install.ps1 -NoBackup`) si preferís borrarla directamente sin resguardo.

> La versión Windows no tiene transición de fundido entre fondos (esa característica depende de ImageMagick, que no se instala en esta plataforma): el cambio de fondo es directo.

### Uso (Windows)

```powershell
# Ver el estado de las tareas
Get-ScheduledTask -TaskName 'FieldHouseWallpaper', 'FieldHouseWallpaperLogin'

# Forzar una actualización ahora mismo
& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe"

# Simular sin tocar nada (qué fondo se aplicaría ahora)
& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe" --dry-run

# Ver la ayuda completa
& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe" --help

# Reconfigurar modo de horarios y franjas horarias, paso a paso
& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe" --config

# Ver el log
Get-Content "$env:LOCALAPPDATA\FieldHouse\state\log.txt" -Tail 20 -Wait

# Editar los horarios de las franjas a mano (alternativa a --config; la
# ubicación no se edita: es automática)
notepad "$env:APPDATA\FieldHouse\config.json"
```

### Desinstalar (Windows)

```powershell
.\Uninstall.cmd
```

> Igual que con la instalación, `Uninstall.cmd` corre `Uninstall.ps1` sin que tengas que lidiar con la política de ejecución de PowerShell. Podés hacerle doble clic o correrlo desde una consola.

Te va a preguntar si querés conservar tu configuración por si reinstalás más adelante.

## Usar tus propias imágenes

Si querés reemplazar las 9 imágenes incluidas por las tuyas, tienen que ir en la carpeta `fondos` de tu instalación, con estos nombres exactos:

- **Linux**: `~/.local/share/field-house/fondos/`
- **Windows**: `%LOCALAPPDATA%\FieldHouse\fondos\`

| Archivo                | Momento                      |
| ---------------------- | ---------------------------- |
| `amanecer.jpg`         | Amanecer                     |
| `mediodia.jpg`         | Medio día                    |
| `tarde.jpg`            | Atardecer                    |
| `noche.jpg`            | Noche                        |
| `nublado-dia.jpg`      | Amanecer o mediodía nublado  |
| `nublado-noche.jpg`    | Noche nublada                |
| `lluvia-dia.jpg`       | Amanecer o mediodía lluvioso |
| `lluvia-atardecer.jpg` | Atardecer lluvioso           |
| `lluvia-noche.jpg`     | Noche lluviosa               |

> Nota: el atardecer nublado usa `nublado-dia.jpg` (aún hay luz de día); no existe una versión "nublado" propia del atardecer.

## Documentación técnica

Ver [INSTALACION.md](INSTALACION.md) para el detalle de cómo funciona cada parte (franjas horarias, systemd, transición, troubleshooting) y para instrucciones de instalación manual sin `install.sh`.

## Contribuir

Ver [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencia

MIT. Ver [LICENSE](LICENSE).
