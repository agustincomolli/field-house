# Changelog de The Field House

Todas las versiones notables de este proyecto se documentan acá.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es/1.1.0/), y las versiones siguen [SemVer](https://semver.org/lang/es/) (MAJOR.MINOR.PATCH).

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