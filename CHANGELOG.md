# Changelog de The Field House

Todas las versiones notables de este proyecto se documentan acá.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/), y las versiones siguen [SemVer](https://semver.org/lang/es/) (MAJOR.MINOR.PATCH).

## [1.3.4](https://github.com/agustincomolli/field-house/compare/v1.3.3...v1.3.4) (2026-08-26)


### Bug Fixes

* new windows project with c# ([d2a8f59](https://github.com/agustincomolli/field-house/commit/d2a8f59079d1ba217d0e43cffde67ff9710df416))

## [1.3.2](https://github.com/agustincomolli/field-house/compare/v1.3.1...v1.3.2) (2026-08-24)


### Bug Fixes

* images ([265f893](https://github.com/agustincomolli/field-house/commit/265f893e6ad2bfa9917891537e2babc6df8a8d87))

## [1.3.1](https://github.com/agustincomolli/field-house/compare/v1.3.0...v1.3.1) (2026-08-24)


### Bug Fixes

* capture PowerShell smoke test exit codes ([2a11d32](https://github.com/agustincomolli/field-house/commit/2a11d3220686f74867de2588f515b19fec40a983))
* correct release workflow YAML ([e8b7be1](https://github.com/agustincomolli/field-house/commit/e8b7be151095f42c34a97f220313523b36387969))
* format automatic schedule times ([e6f4c10](https://github.com/agustincomolli/field-house/commit/e6f4c106028fd27742b69a6884c3df9c4c064169))
* handle expected PowerShell validation failure ([715029a](https://github.com/agustincomolli/field-house/commit/715029ad6821b65336b06d008ee1afbb187829cb))
* handle single PowerShell pipeline results ([e4b7c97](https://github.com/agustincomolli/field-house/commit/e4b7c97b833e632d8f2ca53ed9b00a8b0596b40c))
* make release workflow YAML explicit ([3722ad0](https://github.com/agustincomolli/field-house/commit/3722ad088108ed1f772827cbbcab9f8569738772))

## [1.3.0] — 2026-08-19

> Nota de versionado: esta versión solo agrega infraestructura de testing y CI (sin cambios de comportamiento para el usuario final), así que el número que devuelven `--version`/`-Version` en los scripts se mantiene en `1.2.0` — no hubo un cambio funcional que ameritara tocarlo. El `1.3.0` de este changelog versiona el estado del *repositorio*, no necesariamente cada binario individual.

### Agregado
- **`tests/change_wallpaper.bats`**: suite de tests unitarios (bats-core)
  para las funciones puras del motor Linux — `hora_a_minutos`,
  `min_a_hora` (incluido el caso límite de v1.2.0 con minutos >= 1440),
  `validar_configuracion` (casos válidos e inválidos para cada variable), y
  la lógica de decisión de franja horaria + clima (documentada con una
  copia deliberada dentro del propio archivo de tests, ya que esa lógica
  vive en el cuerpo principal del script, no en una función con nombre).
  42 tests, sin dependencia de red ni de una sesión XFCE real.
- **Guard `FIELD_HOUSE_SOURCE_ONLY`** en `bin/change_wallpaper.sh`: si esta
  variable de entorno está seteada, el script define todas sus funciones y
  termina ahí (sin tomar el lock, sin tocar red ni xfconf), permitiendo que
  la suite de tests haga `source` del archivo real en vez de mantener una
  copia paralela del código. No afecta la ejecución normal: en producción
  esta variable nunca se define.
- **CI para PowerShell** (`.github/workflows/shellcheck.yml`, job nuevo
  `powershell-checks`, corre en `windows-latest` en paralelo al job de
  Linux): parseo de sintaxis (AST) de los 3 scripts, `PSScriptAnalyzer`
  (severidad `Warning`/`Error`, con `PSAvoidUsingWriteHost` excluida a
  propósito), y los mismos cuatro smoke tests que ya existían para Linux
  (modo fijo, modo auto contra wttr.in real, configuración inválida) más
  `-Version`/`-Help`, adaptados a PowerShell. Esto cierra la brecha
  documentada en v1.2.0: el código Windows había sido revisado a mano, sin
  un linter real ejecutándose, porque no había entorno con PowerShell
  disponible durante su desarrollo.
- **CI para Linux ampliado**: nuevo paso `bats tests/change_wallpaper.bats`
  en el job `shellcheck`, entre la validación de sintaxis y los smoke
  tests existentes.

## [1.2.0] — 2026-08-18

### Agregado
- **Soporte para Windows 10 y 11**, en `windows/`: `Change-Wallpaper.ps1`
  (motor, equivalente funcional de `bin/change_wallpaper.sh`),
  `Install.ps1` y `Uninstall.ps1`. Usa `SystemParametersInfo` (Win32, vía
  P/Invoke) para aplicar el fondo, `Invoke-RestMethod`/`Invoke-WebRequest`
  para las consultas a wttr.in, y Tareas Programadas (una horaria y otra en
  el inicio de sesión) en vez de systemd. Replica la misma lógica de
  franjas horarias, modo `auto` según el sol, clima con caché, reintentos
  en `-Reboot`, rotación de log y validación de configuración que la
  versión Linux — mismos nombres de propiedad en `config.json` que las
  variables de `config.conf`, para que la documentación de "Cómo funciona"
  sea común a ambas plataformas. No incluye la transición de fundido entre
  fondos (que en Linux depende de ImageMagick): el cambio es directo.
  Revisado a mano en detalle (no hay entorno con PowerShell disponible en
  este momento para correr un linter automatizado como `PSScriptAnalyzer`
  contra el código): se corrigieron durante la revisión, antes de la
  primera publicación, un clonado inválido de `PSCustomObject`
  (`.PSObject.Copy()` no existe; se reconstruye el objeto a mano), un
  mutex con prefijo `Global\` que puede requerir privilegios elevados
  (se cambió a un mutex de sesión, suficiente para coordinar ejecuciones
  del mismo usuario), una referencia insegura a `$script:Config` bajo
  `Set-StrictMode` en la primera ejecución sin `config.json` (rotación de
  log), el uso de `Invoke-RestMethod` para una respuesta de texto plano
  (se cambió a `Invoke-WebRequest` + `.Content`, que no intenta interpretar
  el cuerpo), y un `RepetitionDuration` de `[TimeSpan]::MaxValue` en la
  tarea programada que puede exceder el límite real del Programador de
  tareas de Windows. **Recomendamos probar esta primera versión con
  atención en Windows real** y reportar cualquier problema — ver
  "Contribuir" para cómo correr `PSScriptAnalyzer` manualmente hasta que
  haya CI dedicado para PowerShell.
- **`install.sh --no-backup`**: opción para reinstalar borrando directamente
  una instalación previa (sin el `mv` a `.bak.FECHAHORA` que ahora es el
  comportamiento por defecto). Útil para iterar rápido en desarrollo, o
  cuando el usuario ya resguardó lo que le importaba por su cuenta.
- **`install.sh --help` / `install.sh --version`**: banderas de ayuda y
  versión, en línea con las que ya tenía `bin/change_wallpaper.sh`.

### Cambiado
- **`bin/cambiar_fondo.sh` renombrado a `bin/change_wallpaper.sh`** (nombre del
  archivo únicamente; las variables internas del script y los nombres de
  archivo de imágenes siguen en español). Actualizado en todas las
  referencias: `install.sh`, `uninstall.sh`, los `.service` de systemd, el CI
  y toda la documentación (ES/EN).
- Imágenes de `fondos/` recomprimidas: el set completo pasó de ~7 MB a
  ~2.2 MB, con tamaños homogéneos entre sí (antes iban de ~520 KB a ~1.7 MB
  según el archivo; ahora todas están en el rango ~120–380 KB).

### Corregido
- `install.sh`/`uninstall.sh`: el prompt de confirmación de reinstalación no
  mencionaba explícitamente la pérdida de imágenes personalizadas en la
  misma línea que se confirma; ahora el mensaje de advertencia y la pregunta
  de confirmación están unificados en un solo bloque inequívoco.
- `install.sh`: ya no borra una instalación previa sin resguardo por
  defecto. Antes de eliminar `$DATOS_APP`/`$CONFIG_DIR`/`$STATE_DIR`
  existentes, los mueve a `*.bak.FECHAHORA` en la misma ubicación; el
  mensaje final indica dónde quedó el resguardo. Este resguardo se puede
  saltear explícitamente con `--no-backup` (ver "Agregado" arriba).
- `install.sh`: el parseo de `--no-backup`/`--help`/`--version`/argumentos
  desconocidos estaba ubicado antes de la definición de las funciones de
  color (`info`/`success`/`warning`/`error`), así que un argumento
  desconocido fallaba con `command not found` (exit 127) en vez de mostrar
  el mensaje de error esperado (exit 1). Se reordenó el archivo para que las
  funciones de color se definan primero.
- `bin/change_wallpaper.sh`: `min_a_hora()` normaliza minutos >= 1440 antes
  de formatear (`MIN_NOCHE` podía superar las 24 hs cuando el atardecer real,
  en `MODO_HORARIOS=auto`, ocurre después de las 22:00, produciendo mensajes
  de log como "24:50" en vez de una hora válida del día siguiente).
- `.github/workflows/shellcheck.yml`: el smoke test ahora corre dos veces —
  una con `MODO_HORARIOS=fijo` (como antes) y otra con `MODO_HORARIOS=auto`
  contra una ciudad conocida, más un tercer caso con las variables nuevas
  (`MODO_HORARIOS`, `TTL_CACHE_CLIMA`, `MAX_LOG_BYTES`) explícitas en el
  `config.conf` de prueba. Antes solo se ejercitaba el modo fijo con los
  valores por defecto, dejando sin cobertura automatizada el camino feliz
  del modo automático y la validación de esas tres variables.

## [1.1.0] — 2026-08-17

### Agregado
- Modo de horarios **`MODO_HORARIOS`** (`fijo` por defecto, o `auto`):
  - `fijo`: comportamiento original (horarios hardcodeados en `config.conf`).
  - `auto`: las franjas se calculan según la salida/puesta **real** del sol en
    la ciudad (`wttr.in?format=j1`, sin APIs extra): amanecer = salida,
    atardecer = puesta, mediodía = punto medio, noche = puesta + 2 hs.
    Consulta con caché diaria (`horarios-sol.cache`) y **fallback a los
    horarios fijos** (con aviso en el log) si la consulta falla.
  - El instalador pregunta el modo durante la instalación (default `fijo`).
- Banderas de línea de comandos nuevas en `cambiar_fondo.sh`:
  - `--dry-run`: simula la ejecución (franja, clima y fondo elegido) sin tocar
    xfconf, sin escribir logs ni estado, y sin esperas ni lock. Sirve para
    diagnosticar en cualquier máquina, con o sin sesión XFCE.
  - `--version`: muestra la versión del programa.
  - `--help` / `-h`: muestra la ayuda completa (opciones, rutas de config y log).
- Validación de configuración al arrancar: `CIUDAD` (solo letras/números y
  `. , _ -`), `MODO_HORARIOS` (`fijo`/`auto`), `HORA_INICIO_*` (formato
  `HH:MM`), `PASOS_TRANSICION`,
  `PAUSA_ENTRE_PASOS`, valores numéricos restantes y que `CARPETA_FONDOS` sea
  un directorio. Un valor inválido detiene la ejecución con un mensaje claro.
- Verificación de dependencias al inicio (`curl`, `xfconf-query`, `awk`,
  `grep`, `tr`, `seq`, `head`, `cut`), con aviso para ImageMagick opcional.
- Caché de clima en `~/.local/state/field-house/clima.cache` (TTL por defecto
  10 minutos, `TTL_CACHE_CLIMA`) para no repetir consultas a wttr.in cuando el
  timer y el login disparan casi a la vez.
- Rotación de log: al superar `MAX_LOG_BYTES` (1 MiB por defecto) se rota a
  `log.txt.1` conservando solo la copia más reciente.
- En `install.sh`:
  - **Reinstalar = instalación de fábrica**: si detecta una instalación previa
    (directorios o unidades systemd), la borra por completo antes de instalar
    y no conserva NADA (ni siquiera `config.conf.bak`, que dejó de generarse).
  - Pregunta el modo de horarios (`fijo`/`auto`) durante la instalación.
  - Validación de la ciudad detectada con el mismo criterio que el script,
    verificación de que las 9 imágenes quedaran copiadas, y las variables
    nuevas (`MODO_HORARIOS`, `TTL_CACHE_CLIMA`, `MAX_LOG_BYTES`) en la
    plantilla de `config.conf`.
  - `systemctl --user reset-failed` de las unidades antes de habilitarlas,
    para limpiar estados "failed" arrastrados de instalaciones viejas.
- `.gitattributes` que fuerza LF (`eol=lf`) en scripts y workflows, para que
  el checkout en Windows no reinyecte CRLF (rompe heredocs y shellcheck).
- `CHANGELOG.md`.

### Corregido
- La transición de fundido podía setear como fondo un frame inexistente si
  `convert`/`identify` fallaba (todo quedaba tapado por `2>/dev/null`). Ahora
  cada frame se verifica antes de aplicarse y el fallo se registra en el log.
- Los temporales de la transición usaban `/tmp/...-$$` (PID predecible) y
  quedaban huérfanos si el proceso se interrumpía. Ahora se usa `mktemp -d` con
  permisos privados y un `trap` de limpieza en EXIT/INT/TERM.
- `curl` de clima: timeout total 6 s con `--connect-timeout 2` (antes 8 s sin
  `--connect-timeout`, podía colgarse en DNS). Respuestas de error de wttr.in
  (ciudad inválida, HTML) ahora cuentan como fallo en vez de producir fondos
  raros.
- `aplicar_fondo` consultaba la lista de propiedades `last-image` en cada paso
  de la transición y fallaba en silencio. Ahora la obtiene una sola vez por
  ejecución, avisa si no hay ninguna, y registra las propiedades que fallaron.

### Cambiado
- `install.sh` y `uninstall.sh` muestran la versión en su banner.
- Documentación actualizada (README, INSTALACION, contribución) con las
  nuevas opciones, la sección de validaciones y troubleshooting ampliado.
- CI: el workflow de shellcheck ahora también valida sintaxis con `bash -n`.

## [1.0.0] — base inicial

Versión original del proyecto: franjas horarias fijas, clima de wttr.in,
transición opcional con ImageMagick, lock anti-concurrencia con `flock`,
instalador sin sudo en rutas XDG y ejecución automática con timers de systemd.

[1.1.0]: https://github.com/agustincomolli/field-house/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/agustincomolli/field-house/tree/v1.0.0
