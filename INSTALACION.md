🇬🇧 [Read this in English](INSTALLATION.en.md)

# Documentación técnica — The Field House

Este documento explica en detalle cómo funciona cada parte del programa, y cómo instalarlo/configurarlo manualmente si preferís no usar `install.sh`.

## Estructura del repositorio

```
field-house/
├── bin/
│   └── change_wallpaper.sh           # Motor Linux/XFCE
├── windows/
│   ├── engine/
│   │   ├── FieldHouseEngine.cs        # Motor Windows 10/11 (C#, compilado en la instalación)
│   │   └── Build-Engine.ps1           # Compila FieldHouseEngine.cs con csc.exe
│   ├── Install.ps1                    # Instalador Windows
│   ├── Install.cmd                    # Atajo: corre Install.ps1 con el bypass de política ya resuelto
│   ├── Uninstall.ps1                  # Desinstalador Windows
│   └── Uninstall.cmd                  # Atajo: corre Uninstall.ps1 con el bypass de política ya resuelto
├── tests/
│   └── change_wallpaper.bats         # Tests unitarios del motor Linux (bats)
├── fondos/                           # Las 9 imágenes de fondo (comunes a ambas plataformas)
├── systemd/
│   ├── field-house.service           # Servicio que ejecuta el motor Linux
│   ├── field-house.timer             # Timer que lo dispara cada hora
│   └── field-house-login.service     # Servicio que corre al iniciar sesión
├── .github/workflows/
│   └── shellcheck.yml                # CI: lint + tests unitarios + smoke tests, Linux y Windows
├── .gitattributes                    # Fuerza LF (Unix) en scripts y workflows
├── CHANGELOG.md                      # Registro de cambios por versión
├── install.sh                        # Instalador interactivo (Linux)
├── uninstall.sh                      # Desinstalador (Linux)
├── README.md / README.en.md
├── INSTALACION.md / INSTALLATION.en.md
├── CONTRIBUTING.md
└── LICENSE
```

## Dónde queda instalado (convención XDG)

El instalador no mezcla programa, configuración y datos del usuario en una sola carpeta — sigue la [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html), la misma convención que usan la mayoría de las apps modernas de Linux instaladas por el usuario (sin sudo):

| Qué | Dónde | Por qué ahí |
|---|---|---|
| Programa + imágenes | `~/.local/share/field-house/` | `XDG_DATA_HOME`: datos de la app que no edita el usuario a mano |
| Configuración | `~/.config/field-house/config.conf` | `XDG_CONFIG_HOME`: lo único que el usuario edita |
| Logs | `~/.local/state/field-house/log.txt` | `XDG_STATE_HOME`: datos que cambian con el uso pero no son "documentos" |
| Servicios systemd | `~/.config/systemd/user/` | Ruta estándar para servicios de usuario (no de sistema) |

Ninguna de estas rutas necesita `sudo`: todo vive dentro del `$HOME` del usuario.

## Instalación manual (sin `install.sh`)

Si preferís no correr el instalador, podés armar todo a mano:

```bash
# 1. Programa e imágenes
mkdir -p ~/.local/share/field-house/bin
mkdir -p ~/.local/share/field-house/fondos
cp bin/change_wallpaper.sh ~/.local/share/field-house/bin/
chmod +x ~/.local/share/field-house/bin/change_wallpaper.sh
cp fondos/*.jpg ~/.local/share/field-house/fondos/

# 2. Configuración
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

# 3. Servicios de systemd
mkdir -p ~/.config/systemd/user
cp systemd/*.service systemd/*.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now field-house.timer
systemctl --user enable field-house-login.service
```

Reemplazá `CIUDAD="CanuelasAR"` por la tuya (sin espacios ni tildes; podés probar qué reconoce wttr.in con `curl "https://wttr.in/TuCiudad?format=%C"`). Acordate: los valores que faltan en un `config.conf` viejo se cubren con los valores por defecto del script, así que agregar variables nuevas no rompe instalaciones existentes.

## Reinstalar / actualizar

Para actualizar a una versión nueva, simplemente corré `./install.sh` de nuevo sobre el repo clonado. El instalador **detecta si ya hay una instalación previa** (programa, configuración, logs o unidades de systemd) y, tras el prompt de confirmación, la reinstala de una de estas dos formas:

- **Por defecto: con resguardo.** El programa, las imágenes (incluidas las que hayas personalizado), la configuración y los logs actuales se **mueven** (`mv`) a una copia con sufijo `.bak.FECHAHORA` en el mismo lugar donde estaban, antes de instalar la versión nueva. No se borra nada de forma irreversible — el resumen final del instalador te muestra la ruta exacta de cada copia, para que recuperes lo que necesites a mano o borres la copia vos mismo cuando ya no la necesites.
- **Con `./install.sh --no-backup`: sin resguardo.** Borra directamente la instalación previa (programa, imágenes personalizadas incluidas, configuración y logs) sin dejar copia. Usalo si estás iterando rápido en desarrollo y no querés acumular backups, o si ya resguardaste vos mismo lo que te importaba.

En ambos casos se eliminan (nunca se resguardan) las unidades de systemd previas — son punteros de una línea a rutas fijas, no datos del usuario, y se regeneran solas en la instalación nueva.

La alternativa para desinstalar por completo (sin volver a instalar) es `uninstall.sh`, que también pregunta si querés guardar configuración y logs.

Otras banderas de `install.sh`:

```bash
./install.sh --help       # ayuda
./install.sh --version    # versión del instalador
```

## Cómo funciona cada parte

### Franjas horarias

El script usa bloques de horario para decidir qué fondo toca. Hay dos modos, elegibles en la instalación (`MODO_HORARIOS`):

- **Fijo** (por defecto, el comportamiento original): horarios constantes del reloj, siempre iguales sin importar la época del año:

  - Amanecer: `06:00` → `10:00`
  - Medio día: `10:00` → `15:00`
  - Atardecer: `15:00` → `20:00`
  - Noche: `20:00` → `06:00` (día siguiente)

- **Automático** (`MODO_HORARIOS="auto"`): las franjas se calculan según la salida y puesta **real** del sol en tu ciudad (ver sección siguiente).

En ambos modos los límites se pueden ajustar desde `config.conf`: en modo fijo, las variables `HORA_INICIO_AMANECER`, `HORA_INICIO_MEDIODIA`, `HORA_INICIO_ATARDECER`, `HORA_INICIO_NOCHE` son las que mandan; en modo auto funcionan como respaldo cuando la consulta del sol falla.

> **¿Por qué horas fijas y no el amanecer/atardecer real del día?** Porque dan el resultado más predecible: siempre sabés qué fondo vas a ver a determinada hora, sin que se corra con las estaciones. Es la opción por defecto; si preferís seguirlo a las estaciones, elegí el modo automático en la instalación.

#### Modo automático (MODO_HORARIOS="auto")

En cada ejecución (con caché diaria, para no molestar a la API), se consulta `wttr.in/CIUDAD?format=j1` y se extraen la salida (`sunrise`) y la puesta (`sunset`) del sol del día:

- **Amanecer** = hora de salida real del sol.
- **Atardecer** = hora de puesta real del sol.
- **Mediodía** = punto medio exacto entre salida y puesta.
- **Noche** = puesta del sol + 2 horas (cuando ya oscureció del todo).

El resultado se guarda en `~/.local/state/field-house/horarios-sol.cache` y se reutiliza durante el día (se vuelve a consultar al cambiar la fecha). Si la consulta falla (sin internet, ciudad inválida), el script avisa en el log y usa los horarios fijos de `config.conf`.

> ⚠️ **Zona horaria.** El cálculo asume que el reloj de tu equipo está en la misma zona horaria que `CIUDAD` (el caso normal: ponés la ciudad donde vivís). Si la ciudad tuviera otra zona horaria que la de tu reloj, las franjas no coincidirían con el fondo esperado; en ese caso usá el modo fijo o ajustá la zona horaria del sistema.

### Clima

En cada ejecución se consulta `wttr.in/TU_CIUDAD?format=%C` (solo la condición climática, sin datos adicionales). La consulta usa un timeout corto (`--connect-timeout 2 --max-time 6`): no espera más de 6 segundos en total, y no se cuelga en DNS. El clima nublado y la lluvia se manejan como condiciones aparte y usan imágenes distintas:

- **Nublado** (`overcast`, `cloudy`), se reemplaza el fondo "base" de la franja por la versión nublada:
  - Amanecer o mediodía nublado → `nublado-dia.jpg`
  - Atardecer nublado → `nublado-dia.jpg` (aún hay luz de día; no hay versión propia de atardecer)
  - Noche nublada → `nublado-noche.jpg`
- **Lluvia** (`rain`, `drizzle`, `shower`, `thunder`, `mist`, `fog`), se reemplaza por la versión lluviosa:
  - Amanecer o mediodía lluvioso → `lluvia-dia.jpg`
  - Atardecer lluvioso → `lluvia-atardecer.jpg`
  - Noche lluviosa → `lluvia-noche.jpg`

Si falla la consulta (sin internet, timeout superado, ciudad inválida), se usa el fondo base de la franja sin intentar lluvia ni nublado, y queda registrado en el log.

**Caché de clima:** como la consulta es una llamada de red, el resultado se guarda en `~/.local/state/field-house/clima.cache` y se reutiliza durante `TTL_CACHE_CLIMA` segundos (10 minutos por defecto). Esto evita consultas redundantes cuando el timer horario y el servicio de login disparan casi en el mismo momento — algo que, a su vez, respeta el servicio gratuito de wttr.in.

**Reintento al iniciar sesión:** al arrancar la PC la red (en particular el WiFi) puede tardar en estar lista, a veces más que la espera inicial de `ESPERA_INICIAL_SEGUNDOS`. Por eso, en la ejecución de login (flag `--reboot`), si la consulta falla se aplica ya el fondo base de la franja y se reintenta el clima cada `ESPERA_REINTENTO_CLIMA` segundos (60s por defecto) hasta `REINTENTOS_CLIMA_INICIAL` veces (3 por defecto). Si un reintento tiene éxito, el fondo pasa al de clima con la transición normal; si se agotan, queda el fondo base hasta el próximo disparo horario. En las ejecuciones normales (timer horario) no hay reintento: un fallo se deja para la próxima hora.

### Transición de fundido

Si `imagemagick` está instalado, el script no cambia el fondo de golpe: genera una serie de imágenes intermedias mezclando la imagen anterior con la nueva en proporciones crecientes (`PASOS_TRANSICION`, 15 por defecto) y las va aplicando con una pequeña pausa entre cada una (`PAUSA_ENTRE_PASOS`, 0.15s), dando un efecto de fundido de ~2 segundos en total. Sin ImageMagick, o con `PASOS_TRANSICION=0`, el cambio es directo.

Los frames se generan en un directorio temporal seguro (`mktemp`) que se limpia solo al terminar — incluso si el script se interrumpe con Ctrl+C o se corta la sesión. Cada frame se verifica antes de aplicarse: si la generación de una imagen intermedia fallara (por ejemplo una imagen de origen corrupta), se anota en el log y se continúa con la siguiente en lugar de dejar un fondo roto en silencio.

### Ejecución automática con systemd

El proyecto usa **systemd user timers** en vez de `cron`, por varias razones prácticas:

- No hay que editar `crontab -e` a mano (el instalador hace `systemctl --user enable`).
- Se puede consultar el estado con `systemctl --user status field-house.timer` — cron no tiene esto.
- Los logs de ejecución (además del `log.txt` propio del script) quedan disponibles con `journalctl --user -u field-house.service`.
- `Persistent=true` en el timer significa que si la sesión estuvo apagada/suspendida en el momento en que debía dispararse, systemd lo ejecuta apenas puede — no hay que esperar a la próxima hora en punto. Este es el reemplazo directo de lo que en `cron` se resolvía con una entrada `@reboot`.

Hay tres archivos de systemd:

| Archivo | Qué hace |
|---|---|
| `field-house.service` | Define cómo correr el script (`ExecStart`) |
| `field-house.timer` | Dispara ese servicio cada hora (`OnCalendar=hourly`), con `Persistent=true` |
| `field-house-login.service` | Corre el script una vez al iniciar sesión gráfica, con el flag `--reboot` |

`field-house-login.service` existe además del `Persistent=true` del timer porque ese último corre "apenas es posible" tras el arranque, que puede ser antes de que XFCE termine de inicializar `xfconf`. El flag `--reboot` le agrega una espera (`ESPERA_INICIAL_SEGUNDOS`, 15s por defecto) para evitar ese problema, y además activa el reintento de clima del arranque por si la red todavía no está lista (ver sección Clima).

### Verificación de imágenes

Al arrancar, el script valida que las 9 imágenes de fondo existan en `CARPETA_FONDOS`. Si falta alguna, no aplica ningún cambio y lo deja registrado en el log — así te enterás de un nombre de archivo mal escrito o un reemplazo incompleto apenas corre el script, en vez de descubrirlo recién cuando le toque el turno a esa franja o clima puntual.

### Multi-monitor

El script recorre todas las propiedades `last-image` de xfconf (una por monitor/workspace) y las actualiza a todas, así que si tenés más de un monitor o varios espacios de trabajo, todos quedan sincronizados. La lista de propiedades se obtiene **una sola vez** por ejecución y se reutiliza en los pasos de la transición, evitando decenas de llamadas a `xfconf-query`.

## Validaciones y comportamiento robusto

El objetivo de diseño es **degradar con elegancia pero fallar con claridad**: el script sobrevive sin red, sin ImageMagick o sin una sesión XFCE lista, pero cuando algo está mal configurado lo anuncia bien y temprano, en vez de producir fondos raros o fallos silenciosos.

- **Dependencias verificadas al inicio.** Antes de tocar nada, se comprueba que existan `curl`, `xfconf-query` (solo en ejecución real, no en `--dry-run`), `awk`, `grep`, `tr`, `seq`, `head` y `cut`. Si falta alguna, el script termina de inmediato con un mensaje en el log. ImageMagick (`convert`/`identify`) es opcional: solo genera un aviso.
- **Configuración validada.** Tras cargar `config.conf` se validan: `CIUDAD` (solo letras/números y `. , _ -`, para no romper la URL de wttr.in), `MODO_HORARIOS` (`fijo` o `auto`), las `HORA_INICIO_*` (formato `HH:MM` válido), `PASOS_TRANSICION`, `PAUSA_ENTRE_PASOS` y los valores numéricos restantes, además de que `CARPETA_FONDOS` sea un directorio. Un valor inválido detiene la ejecución con un mensaje que dice qué variable está mal y cómo corregirla.
- **Temporales seguros y limpios.** Los frames de la transición van a un directorio de `mktemp` (permisos privados), y un `trap` lo elimina al salir — normal o interrumpidamente. Si el proceso se caía a mitad en versiones viejas, quedaban carpetas huérfanas en `/tmp`; eso ya no pasa.
- **Sin fallos silenciosos en xfconf.** Si alguna propiedad `last-image` falla al asignarse, se acumulan y se registran en el log (con las propiedades que fallaron). Si no hay ninguna propiedad `last-image` (perfil XFCE recién creado), se avisa explícitamente.
- **Log rotado.** Cada línea es una ejecución (24/día), por lo que crece poco, pero aún así el log se rota a `log.txt.1` cuando supera `MAX_LOG_BYTES` (1 MiB por defecto), conservando solo la copia más reciente.
- **`--dry-run` para diagnóstico.** `change_wallpaper.sh --dry-run` (opcionalmente con `--reboot`) imprime la franja, el clima y el fondo que se aplicaría **sin** tocar xfconf, sin escribir logs ni estado, y sin esperas ni lock. Sirve para probar la lógica de clima/franjas en cualquier máquina, y es lo primero que pedimos en un reporte de problema.

## Tests y CI

El proyecto tiene dos capas de verificación automática, una por plataforma, corriendo en paralelo en cada push/PR (`.github/workflows/shellcheck.yml`, job `shellcheck` para Linux y job `powershell-checks` para Windows):

### Linux

| Paso | Qué valida |
|---|---|
| `shellcheck` | Estilo y errores comunes de bash en los 3 scripts |
| `bash -n` | Sintaxis (sin ejecutar) |
| `bats tests/change_wallpaper.bats` | Tests unitarios de funciones puras: conversión de horas, `validar_configuracion`, y la lógica de decisión de franja horaria + clima |
| Smoke test modo fijo | `--dry-run` con config mínima |
| Smoke test modo auto | `--dry-run` con `MODO_HORARIOS=auto` contra wttr.in real (conectividad del runner) |
| Smoke test config completa | `--dry-run` con todas las variables nuevas explícitas en `config.conf` |
| Smoke test config inválida | Confirma que una `CIUDAD` inválida hace fallar el script (exit != 0) |

Para correr los tests unitarios en tu máquina antes de un PR:

```bash
sudo apt install bats   # o: npm install -g bats
bats tests/change_wallpaper.bats
```

La suite usa un guard (`FIELD_HOUSE_SOURCE_ONLY`) que le indica a `bin/change_wallpaper.sh` que, al hacer `source`, defina las funciones y termine ahí — sin tomar el lock, sin tocar red, sin leer `config.conf` real. Así los tests ejercitan las funciones tal como están en producción (una sola fuente de verdad), sin una copia paralela del código que pueda desincronizarse. La única excepción es la lógica de decisión de franja+clima, que vive en el cuerpo principal del script (no en una función con nombre): para esa parte, `tests/change_wallpaper.bats` mantiene una copia deliberada y comentada (`decidir_fondo_test`), documentada al final del archivo — extraerla a una función real (`decidir_fondo()`) es una mejora pendiente que eliminaría esa duplicación.

### Windows

| Paso | Qué valida |
|---|---|
| Parseo AST | Sintaxis de `Install.ps1` y `Uninstall.ps1` sin ejecutarlos (`[Parser]::ParseFile`) |
| `PSScriptAnalyzer` | Lint sobre `Install.ps1`, `Uninstall.ps1` y `Build-Engine.ps1` (severidad `Warning`/`Error`; se excluye `PSAvoidUsingWriteHost` a propósito, ver el comentario en el workflow) |
| Compilación del motor | `csc.exe` compila `FieldHouseEngine.cs` en el runner (mismo paso que hace `Install.ps1`); un error de compilación falla el job |
| Smoke test modo fijo | `FieldHouseEngine.exe --dry-run` con config mínima, más `--version` y `--help` |
| Smoke test modo auto | `FieldHouseEngine.exe --dry-run` con `ModoHorarios: "auto"` contra wttr.in real |
| Smoke test config inválida | Confirma que una `Ciudad` inválida hace fallar el ejecutable |

Para correr el lint localmente antes de un PR:

```powershell
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path windows\ -Recurse -Severity Warning,Error -ExcludeRule PSAvoidUsingWriteHost
```

Para compilar el motor localmente y correr los smoke tests a mano:

```powershell
.\windows\engine\Build-Engine.ps1 -RutaCsharp .\windows\engine\FieldHouseEngine.cs -RutaExeSalida .\FieldHouseEngine.exe
.\FieldHouseEngine.exe --dry-run
.\FieldHouseEngine.exe --version
.\FieldHouseEngine.exe --help
```

> Nota sobre el origen de este CI: el código PowerShell del proyecto fue desarrollado y revisado manualmente sin acceso a un entorno con PowerShell real (ver el detalle en `CHANGELOG.md`, versión 1.2.0), lo cual permitió detectar y corregir 6 problemas reales durante la revisión, pero sin la garantía de un linter ejecutándose de verdad. Este job de CI cierra esa brecha desde la próxima corrida en adelante. El motor Windows se migró después de PowerShell a C# (compilado con `csc.exe` en tiempo de instalación) para eliminar el parpadeo de consola que `-WindowStyle Hidden` no lograba suprimir de forma confiable en la Tarea Programada; el job de CI se actualizó en el mismo cambio para compilar y ejercitar el `.exe` resultante en vez del `.ps1` anterior.

## Windows: diferencias respecto a Linux

La versión Windows (`windows/engine/FieldHouseEngine.cs`, `Install.ps1`, `Uninstall.ps1`) replica la misma lógica de negocio que la versión Linux — franjas horarias, modo `auto` según el sol, clima con caché y reintentos, validación de configuración, rotación de log — con los mismos nombres conceptuales (las claves de `config.json` son PascalCase de las mismas variables de `config.conf`: `Ciudad` ↔ `CIUDAD`, `ModoHorarios` ↔ `MODO_HORARIOS`, etc.). Todo lo de las secciones "Franjas horarias", "Clima" y "Validaciones y comportamiento robusto" de más arriba aplica igual en Windows; acá se documenta solo lo que **cambia** por ser una plataforma distinta.

A diferencia de Linux (donde el motor es un script bash interpretado por `bash` en cada ejecución), en Windows el motor **se compila una sola vez, durante la instalación**: `Install.ps1` invoca `windows\engine\Build-Engine.ps1`, que a su vez llama a `csc.exe` (el compilador de C# de .NET Framework, incluido de fábrica en Windows 10/11 — no hace falta instalar el SDK de .NET ni Visual Studio) para generar `%LOCALAPPDATA%\FieldHouse\bin\FieldHouseEngine.exe`. De ahí en más, tanto las Tareas Programadas como una invocación manual ejecutan ese binario directo; no vuelve a compilarse hasta la próxima instalación o reinstalación.

| Concepto | Linux | Windows |
|---|---|---|
| Motor | `bin/change_wallpaper.sh` (bash, interpretado en cada ejecución) | `FieldHouseEngine.exe` (C#, compilado una vez en la instalación) |
| Aplicar el fondo | `xfconf-query` (propiedades `last-image` de XFCE) | `SystemParametersInfo` (Win32, vía P/Invoke) — aplica a todos los monitores de una vez, sin iterar |
| Ejecución periódica | Timer de `systemd` (usuario) | Tarea Programada `FieldHouseWallpaper` (disparador horario), ejecuta el `.exe` directo |
| Ejecución al iniciar sesión | `field-house-login.service` (`--reboot`) | Tarea Programada `FieldHouseWallpaperLogin` (disparador `AtLogOn`), ejecuta el `.exe` con `--reboot` |
| Lock anti-concurrencia | `flock` sobre un archivo | `System.Threading.Mutex` con nombre de sesión |
| Configuración | `~/.config/field-house/config.conf` (shell vars) | `%APPDATA%\FieldHouse\config.json` (JSON) |
| Reconfiguración guiada | — (editar `config.conf` a mano) | `FieldHouseEngine.exe --config` (modo interactivo por consola) |
| Programa e imágenes | `~/.local/share/field-house/` | `%LOCALAPPDATA%\FieldHouse\` |
| Logs y caché | `~/.local/state/field-house/` (separado por XDG) | `%LOCALAPPDATA%\FieldHouse\state\` (Windows no separa esto tan estrictamente) |
| Consultas HTTP | `curl` | `HttpWebRequest` (clima y horarios del sol, ambos vía wttr.in) |
| Parseo JSON | — (config.conf es texto plano, no JSON) | Parser JSON propio (`MiniJson`, sin dependencias externas — ver nota abajo) |
| Transición de fundido | Sí, con ImageMagick (opcional) | No disponible; el cambio es directo |
| Formatos de imagen aceptados | JPG (los que trae el proyecto) | JPG (soportado nativamente por `SystemParametersInfo` desde Windows 7) |
| Ventana de consola en ejecución automática | No aplica (no hay concepto de consola en un servicio de `systemd`) | Ninguna: el `.exe` se compila como `/target:winexe`, así que la Tarea Programada no dibuja ninguna ventana |

> **¿Por qué un parser JSON propio (`MiniJson`) en vez de `System.Text.Json`?** `System.Text.Json` recién viene incluido de fábrica desde .NET Framework 4.7.2; en versiones anteriores requeriría instalar el paquete NuGet correspondiente. Como el proyecto compila con una sola invocación a `csc.exe` (sin `dotnet restore` ni gestión de paquetes NuGet), se optó por un parser/escritor JSON minimalista de un solo archivo, suficiente para el formato plano que usa `config.json` y para la respuesta de wttr.in.

### Política de ejecución de PowerShell

Windows bloquea por defecto la ejecución de scripts `.ps1` (`Restricted`). Esto afecta a `Install.ps1` **y** a `Uninstall.ps1` (los únicos `.ps1` que quedan en el proyecto Windows): el programa instalado en sí es un `.exe` nativo, así que no depende de la política de ejecución de PowerShell para correr — el bloqueo solo aparece al invocar estos dos scripts de gestión.

La forma más simple de evitarlo es usar `Install.cmd` y `Uninstall.cmd` en vez de los `.ps1` directo: son atajos de una línea que invocan al `.ps1` correspondiente con `-ExecutionPolicy Bypass` acotado a esa única ejecución, así que no hace falta escribir nada extra ni tocar tu política de ejecución. Se pueden correr desde una consola o con doble clic desde el Explorador de archivos. Cualquier argumento que le pases al `.cmd` se reenvía tal cual al `.ps1` (por ejemplo, `Install.cmd -NoBackup`).

Si preferís correr los `.ps1` directo (por scripting, CI, o simplemente porque ya tenés la costumbre), usá:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1
powershell -ExecutionPolicy Bypass -File .\Uninstall.ps1
```

O, si preferís no repetir el prefijo en cada script que corras (de este proyecto o de cualquier otro), podés levantar la política para tu usuario de forma permanente:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

`RemoteSigned` permite correr scripts locales sin firmar (como los de este proyecto) pero sigue exigiendo firma digital para scripts descargados de internet — es la opción recomendada para desarrollo en general, más segura que `Bypass`/`Unrestricted` aplicados de forma persistente.

### Tareas Programadas

`Install.ps1` registra dos tareas con `Register-ScheduledTask` (no usa un archivo `.xml` estático, para no tener que sustituir rutas de usuario dentro de una plantilla):

| Tarea | Disparador | Ejecuta | Equivalente Linux |
|---|---|---|---|
| `FieldHouseWallpaper` | Cada 1 hora, indefinidamente | `FieldHouseEngine.exe` (sin argumentos) | `field-house.timer` |
| `FieldHouseWallpaperLogin` | Al iniciar sesión (`AtLogOn`) | `FieldHouseEngine.exe --reboot` | `field-house-login.service` |

Ambas corren con el principal `Interactive` del usuario actual (no piden ni guardan contraseña) y ejecutan el `.exe` directo — a diferencia de versiones anteriores del proyecto, ya no invocan `powershell.exe` ni ningún intérprete de por medio.

```powershell
# Ver el estado
Get-ScheduledTask -TaskName 'FieldHouseWallpaper', 'FieldHouseWallpaperLogin'

# Ver el historial de ejecuciones (Visor de Eventos, vía PowerShell)
Get-ScheduledTaskInfo -TaskName 'FieldHouseWallpaper'

# Forzar un disparo manual de la tarea (en vez de correr el .exe directo)
Start-ScheduledTask -TaskName 'FieldHouseWallpaper'
```


## Solución de problemas (Linux)

**El timer no corre / `systemctl --user status` da error:**
Confirmá que el bus de sesión de usuario esté activo: `systemctl --user status` sin argumentos no debería fallar. En algunas instalaciones mínimas puede hacer falta `loginctl enable-linger $USER` para que los servicios de usuario sigan corriendo aunque no haya sesión gráfica abierta (no debería ser necesario en un uso normal de escritorio).

**El fondo no cambia aunque el script corre bien a mano:**
Los servicios de systemd de usuario deberían heredar `DISPLAY` y `DBUS_SESSION_BUS_ADDRESS` de la sesión gráfica, pero por las dudas el script y los `.service` los fuerzan explícitamente. Si tu sesión no es la `:0`, ajustá la variable `Environment=DISPLAY=:0` en los archivos `.service` (en `~/.config/systemd/user/`) y corré `systemctl --user daemon-reload`.

**El clima no se detecta bien:**
Probá `curl "https://wttr.in/TuCiudad?format=%C"` directamente en la terminal para ver qué texto exacto devuelve, y ajustá la lista de palabras clave en `bin/change_wallpaper.sh` (nublado: `overcast|cloudy`; lluvia: `rain|drizzle|shower|thunder|mist|fog`) si tu clima devuelve una palabra distinta. Recordá que el resultado se reutiliza 10 minutos por el caché (`TTL_CACHE_CLIMA`); si cambiás la ciudad o querés verificar un cambio, podés borrar `~/.local/state/field-house/clima.cache` y correr el script de nuevo.

**El log dice `AVISO: no se pudo obtener la salida/puesta del sol`:**
Pasa con `MODO_HORARIOS="auto"` cuando la consulta a wttr.in (formato `j1`) falla o tu ciudad no la resuelve. No es grave: el script usa los horarios fijos de `config.conf` para esa corrida y lo intenta de nuevo en la próxima. Verificá internet o probá `curl "https://wttr.in/TuCiudad?format=j1"`.

**Quiero pasar de horarios fijos a automáticos (o al revés):**
Editá `MODO_HORARIOS` en `~/.config/field-house/config.conf` (`"fijo"` o `"auto"`) y corré `~/.local/share/field-house/bin/change_wallpaper.sh` (o esperá el próximo disparo del timer).

**El log dice `ERROR: CIUDAD inválida` (o `HORA_INICIO_... inválida`):**
El script valida la configuración antes de aplicar nada. Editá el valor indicado en `~/.config/field-house/config.conf` con el formato que pide el mensaje (ciudad sin espacios ni tildes; horas en `HH:MM` de 24 hs) y corré el script de nuevo.

**El log dice `ERROR: faltan comandos requeridos`:**
Hace falta un binario del sistema. El mensaje lista cuáles. `curl` (u otro desde la lista) se instala con `sudo apt install <paquete>`.

**El log dice `AVISO: no se encontró ninguna propiedad 'last-image'`:**
El script no ve propiedades de fondo en xfconf. Esto pasa si la sesión gráfica no está lista (¿se corrió a mano sin una sesión XFCE abierta?), o con un perfil de XFCE recién creado. Corré `xfconf-query -c xfce4-desktop -l` para ver si existen; si no, creá un fondo desde el menú de XFCE una vez.

**El log dice que fallaron propiedad(es) `last-image` al aplicar:**
El script intentó aplicar el fondo pero una o más propiedades rechazaron el valor (suele ser un permiso de sesión o DISPLAY). Revisá la lista de propiedades que aparece en el mensaje y verificá que la sesión gráfica esté activa.

**Quiero ver qué fondo se va a aplicar sin esperar a la próxima hora ni ensuciar el log:**
`~/.local/share/field-house/bin/change_wallpaper.sh --dry-run`. Imprime la franja, el clima y el fondo elegido sin tocar nada.

**El log crece mucho (o quiero limitar su tamaño):**
Cada ejecución agrega una línea, así que es difícil que sea un problema, pero si querés limitarlo editá `MAX_LOG_BYTES` en `config.conf` (bytes; al superarlo el log rota a `log.txt.1`).

**Al prender la compu no hay internet todavía y el fondo arranca sin clima:**
Es normal: la red puede tardar en levantarse. En la ejecución de login el script aplica el fondo base y reintenta el clima cada `ESPERA_REINTENTO_CLIMA` segundos (60s) hasta `REINTENTOS_CLIMA_INICIAL` veces (3). Si con eso no alcanza (tu WiFi tarda más de ~3 minutos o no hay red), el fondo se corrige solo en el próximo disparo horario. Podés subir ambos valores en `config.conf` si tu conexión es especialmente lenta.

**El log dice que faltan imágenes:**
Revisá que los 9 archivos estén en `~/.local/share/field-house/fondos/` con los nombres exactos de la tabla del README (todos en minúscula, con guion medio, extensión `.jpg`).

**La transición no se ve, cambia de golpe:**
Confirmá que `imagemagick` esté instalado (`convert -version` no debería dar error). También revisá que `PASOS_TRANSICION` en `config.conf` no esté en `0`.

**Al prender la compu el fondo queda desactualizado un rato:**
Confirmá que `field-house-login.service` esté habilitado: `systemctl --user is-enabled field-house-login.service` debería decir `enabled`. Si el problema persiste, puede que 15 segundos de espera no alcancen en tu equipo; subí `ESPERA_INICIAL_SEGUNDOS` en `config.conf`.

**Quiero que revise más seguido (o menos):**
Editá `OnCalendar=hourly` en `~/.config/systemd/user/field-house.timer`, por ejemplo a `OnCalendar=*:0/30` para cada 30 minutos. Después corré `systemctl --user daemon-reload && systemctl --user restart field-house.timer`.

**La ubicación detectada automáticamente durante la instalación no era la correcta:**
El instalador usa geolocalización por IP, que puede desviarse varios kilómetros según tu proveedor de internet. Simplemente editá `CIUDAD` en `~/.config/field-house/config.conf` con el valor correcto.

## Solución de problemas (Windows)

**`Install.ps1` o `Uninstall.ps1` no corren, PowerShell muestra un error de política de ejecución:**
Es el bloqueo por defecto de Windows para scripts `.ps1` (no es un problema del proyecto). Lo más simple es usar `Install.cmd` / `Uninstall.cmd` en vez del `.ps1` directo — ya traen el bypass resuelto. Si preferís correr el `.ps1` a mano: `powershell -ExecutionPolicy Bypass -File .\Install.ps1` (o `.\Uninstall.ps1`, según cuál estés corriendo). Ninguna de las dos formas cambia tu política de ejecución de forma permanente.

**`Install.ps1` falla en el paso "2/4 - Instalando archivos" con un error de `csc.exe`:**
El instalador compila el motor (`FieldHouseEngine.exe`) con `csc.exe`, el compilador de C# incluido de fábrica en Windows 10/11 como parte de .NET Framework. Si no se encuentra en ninguna de las dos rutas esperadas (`%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` o su variante de 32 bits), probablemente sea una edición de Windows recortada, o una política de la organización que removió ese componente. Podés verificar si está presente con: `Test-Path "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"`. Si falta, .NET Framework 4.x suele poder reinstalarse desde Configuración → Aplicaciones → Características opcionales.

**Las tareas no corren / `Get-ScheduledTask` no las muestra:**
Confirmá que el registro haya funcionado sin errores durante la instalación (revisá la salida de `Install.ps1`). Si necesitás reintentar sin reinstalar todo, podés registrar las tareas a mano copiando el bloque `Register-ScheduledTask` de `Install.ps1` en una consola de PowerShell.

**El fondo no cambia aunque el motor corre bien a mano:**
Ejecutá `& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe"` directamente y confirmá que no tire error. Si corre bien a mano pero no vía tarea programada, revisá en el Programador de tareas (`taskschd.msc`) la pestaña "Historial" de `FieldHouseWallpaper` — ahí Windows registra si la tarea se disparó y con qué código de salida.

**El clima no se detecta bien:**
Probá `Invoke-WebRequest "https://wttr.in/TuCiudad?format=%C"` en PowerShell y mirá `.Content` para ver el texto exacto que devuelve. Los mismos criterios de palabras clave que en Linux aplican (nublado: `overcast|cloudy`; lluvia: `rain|drizzle|shower|thunder|mist|fog`), ajustables en `windows/engine/FieldHouseEngine.cs` (método `ClimaCoincide`, requiere recompilar con `Build-Engine.ps1` tras el cambio). El caché de clima vive en `%LOCALAPPDATA%\FieldHouse\state\clima.cache.json`; borralo si necesitás forzar una consulta nueva.

**El log dice `AVISO: no se pudo obtener la salida/puesta del sol`:**
Mismo caso que en Linux: pasa con `"ModoHorarios": "auto"` cuando la consulta a wttr.in falla o tu ciudad no la resuelve. El motor usa los horarios fijos de `config.json` para esa corrida.

**El log dice `ERROR: Ciudad inválida` (o `HoraInicio... inválida`):**
Corré `& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe" --config` para reconfigurar paso a paso con validación en el momento, o editá el campo correspondiente a mano en `%APPDATA%\FieldHouse\config.json` con el formato que pide el mensaje (ciudad sin espacios ni tildes; horas en `HH:MM` de 24 hs) y volvé a correr el motor.

**Quiero ver qué fondo se va a aplicar sin esperar a la próxima hora:**
`& "$env:LOCALAPPDATA\FieldHouse\bin\FieldHouseEngine.exe" --dry-run`. Imprime la franja, el clima y el fondo elegido sin tocar nada, sin escribir logs.

**Al prender la compu no hay internet todavía y el fondo arranca sin clima:**
Igual que en Linux: la tarea de inicio de sesión reintenta el clima según `EsperaReintentoClima`/`ReintentosClimaInicial` en `config.json`, aplicando mientras tanto el fondo base. Se corrige solo en el próximo disparo horario si la red tarda más que eso.

**El fondo cambia pero se ve "estirado" o con bordas negras:**
Es la configuración de ajuste de imagen de Windows (Configuración → Personalización → Fondo → "Ajuste de imagen"), no algo que controle este proyecto. Las 9 imágenes son 16:9; para que se vean bien en monitores de otra proporción, elegí "Rellenar" o "Ajustar" en esa configuración de Windows (se aplica una sola vez, no hace falta repetirlo).

**La ubicación detectada automáticamente durante la instalación no era la correcta:**
Igual que en Linux: es geolocalización por IP, puede desviarse. Corré `--config` para corregirla paso a paso, o editá `Ciudad` a mano en `%APPDATA%\FieldHouse\config.json`.

**Quiero desinstalar y no encuentro `Uninstall.ps1`:**
Está en la misma carpeta `windows\` del repositorio que clonaste — si borraste esa carpeta, podés eliminar las tareas a mano con `Unregister-ScheduledTask -TaskName 'FieldHouseWallpaper','FieldHouseWallpaperLogin' -Confirm:$false` y después borrar `%LOCALAPPDATA%\FieldHouse` y `%APPDATA%\FieldHouse`.
