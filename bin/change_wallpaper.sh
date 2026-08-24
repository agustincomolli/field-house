#!/bin/bash
# ============================================================================
# The Field House — Live Wallpaper
# change_wallpaper.sh — motor de la app
# Versión: 1.2.0
#
# Cambia el fondo de pantalla en XFCE (Linux Mint y derivados) según franjas
# horarias FIJAS del reloj, y según el clima actual (lluvia/nublado) en
# amanecer, mediodía, atardecer o noche.
#
# Este script es el "motor" de la app. La configuración (ciudad, franjas
# horarias, transición) vive en un archivo aparte que se carga acá abajo,
# para que el usuario no tenga que tocar este archivo directamente.
#
# Se ejecuta automáticamente vía systemd (ver los archivos .service/.timer
# en systemd/, instalados por install.sh). También se puede correr a mano
# para probar o diagnosticar.
#
# Uso:
#   change_wallpaper.sh            ejecución normal (la usa el timer de systemd)
#   change_wallpaper.sh --reboot   ejecución al iniciar sesión (agrega una
#                                espera inicial y reintentos de clima, ver
#                                ESPERA_INICIAL_SEGUNDOS/REINTENTOS_CLIMA_INICIAL)
#   change_wallpaper.sh --dry-run  muestra qué fondo se aplicaría sin tocar
#                                xfconf ni los archivos de estado/red
#   change_wallpaper.sh --version  muestra la versión
#   change_wallpaper.sh --help     muestra la ayuda completa
#
# Requiere: curl, xfconf-query (XFCE), awk, grep, tr, seq, head y cut.
# Opcional: convert/identify (ImageMagick) para la transición de fundido;
# si no están instalados, el cambio de fondo es directo, sin fundido.
# ============================================================================

set -u

VERSION="1.2.0"

# ----------------------------------------------------------------------------
# RUTAS (convención XDG Base Directory)
# ----------------------------------------------------------------------------

# Datos de la app (imágenes, instaladas junto con el programa). No deberían
# editarse a mano; si el usuario quiere sus propias imágenes, las reemplaza
# acá o cambia CARPETA_FONDOS en el archivo de configuración.
DATOS_APP="${XDG_DATA_HOME:-$HOME/.local/share}/field-house"

# Configuración editable por el usuario (ciudad, franjas horarias, etc).
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/field-house"
CONFIG_FILE="$CONFIG_DIR/config.conf"

# Estado/logs de la app.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/field-house"
LOG="$STATE_DIR/log.txt"
CACHE_CLIMA="$STATE_DIR/clima.cache"
CACHE_HORARIOS="$STATE_DIR/horarios-sol.cache"

# ----------------------------------------------------------------------------
# PARÁMETROS DE LÍNEA DE COMANDO
# ----------------------------------------------------------------------------

# mostrar_ayuda
# Imprime la descripción del script y sus opciones. Se define antes del
# parseo de argumentos: en bash una función solo existe cuando su definición
# ya se ejecutó, y el parseo llama a esta función.
mostrar_ayuda() {
    cat <<EOF
The Field House — Live Wallpaper v$VERSION

Cambia el fondo de pantalla XFCE según la franja horaria (amanecer, mediodía,
atardecer, noche) y el clima actual (nublado/lluvia) de tu ciudad.

Uso:
  change_wallpaper.sh [opciones]

Opciones:
  (sin opciones)  Ejecución normal. La usa el timer de systemd.
  --reboot        Ejecución de inicio de sesión: espera ESPERA_INICIAL_SEGUNDOS
                  y, si la red no está lista, reintenta el clima hasta
                  REINTENTOS_CLIMA_INICIAL veces cada ESPERA_REINTENTO_CLIMA s.
  --dry-run       Simula la ejecución: muestra qué fondo se aplicaría sin tocar
                  xfconf, sin escribir logs ni estado, y sin esperas. Puede
                  combinarse con --reboot.
  --version       Muestra la versión del programa.
  --help, -h      Muestra esta ayuda.

La configuración (ciudad, horarios, transición) se lee de:
  $CONFIG_FILE

Los logs se escriben en:
  $LOG
EOF
}

ARG_REBOOT="no"
MODO_DRY="no"

for arg in "$@"; do
    case "$arg" in
        --reboot) ARG_REBOOT="si" ;;
        --dry-run) MODO_DRY="si" ;;
        --version)
            echo "The Field House — Live Wallpaper v$VERSION"
            exit 0
            ;;
        --help|-h)
            mostrar_ayuda
            exit 0
            ;;
        *)
            echo "ERROR: opción desconocida: $arg" >&2
            mostrar_ayuda >&2
            exit 1
            ;;
    esac
done

# ----------------------------------------------------------------------------
# LIMPIEZA AL SALIR
# ----------------------------------------------------------------------------
# Se registra lo más temprano posible para que cualquier salida (normal, o
# interrumpida con Ctrl+C/SIGTERM) borre los temporales de la transición.

TMP_TRANSICION=""

limpiar() {
    if [ -n "$TMP_TRANSICION" ] && [ "$MODO_DRY" = "no" ]; then
        rm -rf "$TMP_TRANSICION"
    fi
}

trap limpiar EXIT INT TERM

# ----------------------------------------------------------------------------
# FUNCIONES
# ----------------------------------------------------------------------------

# log <mensaje>
# Agrega una línea con fecha/hora al archivo de log, rotándolo antes si hace
# falta. En modo --dry-run escribe a la salida estándar en vez del archivo.
log() {
    rotar_log
    if [ "$MODO_DRY" = "si" ]; then
        echo "[dry-run] $1"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"
    fi
}

# rotar_log
# Si el log supera MAX_LOG_BYTES (1 MiB por defecto), lo rota a log.txt.1
# conservando solamente la copia más reciente. El crecimiento real es mínimo
# (una línea por ejecución), pero esto evita que un log descuidado crezca
# indefinidamente en el $HOME del usuario.
rotar_log() {
    [ "$MODO_DRY" = "si" ] && return 0
    [ -f "$LOG" ] || return 0
    local tamano
    tamano=$(wc -c < "$LOG" 2>/dev/null || echo 0)
    # Usa ya el valor del config por defecto por si se llama antes de cargarlo
    # (rotar_log se invoca desde log, que también usa validar_dependencias).
    if [ "$tamano" -ge "${MAX_LOG_BYTES:-1048576}" ]; then
        mv -f "$LOG" "$LOG.1" 2>/dev/null || true
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Log superó ${MAX_LOG_BYTES:-1048576} bytes; se rotó a $LOG.1" >> "$LOG"
    fi
}

# hora_a_minutos <HH:MM>
# Convierte una hora en formato HH:MM a minutos desde medianoche (entero).
hora_a_minutos() {
    local hora="$1"
    echo "$hora" | awk -F: '{print $1*60+$2}'
}

# hora_12_a_minutos <"HH:MM AM|PM">
# Convierte una hora en formato 12 horas (con AM/PM, como la manda wttr.in en
# su formato j1: "07:32 AM", "06:25 PM") a minutos desde medianoche.
hora_12_a_minutos() {
    echo "$1" | awk -F'[ :]' '{
        h = $1; m = $2;
        if ($3 == "PM" && h != 12) h += 12;
        if ($3 == "AM" && h == 12) h = 0;
        print h * 60 + m
    }'
}

# min_a_hora <minutos>
# Convierte minutos desde medianoche a formato HH:MM (solo para mensajes).
# Normaliza el valor al rango [0, 1440) antes de formatear: MIN_NOCHE puede
# superar 1440 cuando el atardecer real (en MODO_HORARIOS=auto) ocurre
# después de las 22:00 y se le suman 2 horas (por ejemplo sunset 22:50 ->
# 1490 min). Sin esta normalización el mensaje mostraría algo como "24:50"
# en vez de la hora real del día siguiente ("00:50"). Esto es solo para que
# el log sea legible: las comparaciones de franja horaria del script usan
# los minutos crudos (sin normalizar) y ya son correctas en ese caso, porque
# la franja "noche" es siempre la que queda por descarte (rama else).
min_a_hora() {
    local min=$(( $1 % 1440 ))
    [ "$min" -lt 0 ] && min=$(( min + 1440 ))
    printf '%02d:%02d' "$(( min / 60 ))" "$(( min % 60 ))"
}

# consultar_horarios_sol
# Consulta la salida y puesta del sol en CIUDAD usando wttr.in (formato j1,
# el mismo servicio que ya se usa para el clima; no hace falta otra API ni
# coordenadas). Devuelve cuatro enteros separados por espacios:
#   amanecer mediodía atardecer noche  (minutos desde medianoche)
# siendo: amanecer = salida real del sol, atardecer = puesta real, mediodía =
# el punto medio entre ambas, y noche = puesta + 2 horas.
# El resultado se guarda en un caché diario (horarios-sol.cache) y se reutiliza
# durante el día, para no consultar la API a cada ejecución horaria. Devuelve
# vacío si no se pudo obtener (sin internet, ciudad inválida): el llamador usa
# entonces los horarios fijos de config.conf.
consultar_horarios_sol() {
    local fecha_hoy sun risa puesta hora_am hora_ha pm mn

    fecha_hoy=$(date +%F)

    if [ -f "$CACHE_HORARIOS" ]; then
        local c_am c_me c_at c_no
        c_am=$(grep '^AMANECER=' "$CACHE_HORARIOS" 2>/dev/null | cut -d= -f2)
        c_me=$(grep '^MEDIODIA=' "$CACHE_HORARIOS" 2>/dev/null | cut -d= -f2)
        c_at=$(grep '^ATARDECER=' "$CACHE_HORARIOS" 2>/dev/null | cut -d= -f2)
        c_no=$(grep '^NOCHE=' "$CACHE_HORARIOS" 2>/dev/null | cut -d= -f2)
        if [ "$(grep '^FECHA=' "$CACHE_HORARIOS" 2>/dev/null | cut -d= -f2)" = "$fecha_hoy" ] \
            && [ -n "$c_am" ] && [ -n "$c_me" ] && [ -n "$c_at" ] && [ -n "$c_no" ]; then
            echo "$c_am $c_me $c_at $c_no"
            return 0
        fi
    fi

    sun=$(curl -s --connect-timeout 2 --max-time 6 "https://wttr.in/${CIUDAD}?format=j1" 2>/dev/null)
    risa=$(printf '%s' "$sun" | grep -oE '"sunrise": *"[0-9]{1,2}:[0-9]{2} [AP]M"' | head -n 1 | grep -oE '[0-9]{1,2}:[0-9]{2} [AP]M')
    puesta=$(printf '%s' "$sun" | grep -oE '"sunset": *"[0-9]{1,2}:[0-9]{2} [AP]M"' | head -n 1 | grep -oE '[0-9]{1,2}:[0-9]{2} [AP]M')

    if [ -z "$risa" ] || [ -z "$puesta" ]; then
        echo ""
        return 1
    fi

    hora_am=$(hora_12_a_minutos "$risa")
    hora_ha=$(hora_12_a_minutos "$puesta")
    pm=$(( (hora_am + hora_ha) / 2 ))
    mn=$(( hora_ha + 120 ))

    if [ "$MODO_DRY" = "no" ]; then
        {
            echo "FECHA=$fecha_hoy"
            echo "AMANECER=$hora_am"
            echo "MEDIODIA=$pm"
            echo "ATARDECER=$hora_ha"
            echo "NOCHE=$mn"
        } > "$CACHE_HORARIOS" 2>/dev/null || \
            log "AVISO: no se pudo guardar el caché de horarios del sol en $CACHE_HORARIOS."
    fi

    echo "$hora_am $pm $hora_ha $mn"
}

# validar_dependencias
# Verifica que los comandos requeridos existan ANTES de empezar a trabajar, en
# vez de fallar a mitad de ejecución. Las herramientas opcionales de la
# transición (ImageMagick) solo generan un aviso: el resto del script degrada
# con elegancia a cambio directo. En --dry-run no se exigen xfconf-query ni
# flock: la simulación justamente permite diagnosticar sin una sesión XFCE
# real (flock bloquea el lock anti-concurrencia y xfconf-query es XFCE).
validar_dependencias() {
    local requeridas=(awk grep tr seq head cut)
    [ "$MODO_DRY" = "no" ] && requeridas+=(xfconf-query flock)
    local opcionales=(convert identify)
    local faltando=()
    local cmd

    for cmd in "${requeridas[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            faltando+=("$cmd")
        fi
    done

    if [ "${#faltando[@]}" -gt 0 ]; then
        log "ERROR: faltan comandos requeridos: ${faltando[*]}. Instalálos (por ejemplo: sudo apt install curl) o corré la app desde una instalación completa."
        exit 1
    fi

    for cmd in "${opcionales[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "AVISO: no se encontró '$cmd' (ImageMagick). La transición de fundido no está disponible; el cambio de fondo será directo."
        fi
    done
}

# validar_configuracion
# Valida los valores cargados desde config.conf. Un valor inválido detiene la
# ejecución con un mensaje claro en el log, porque aplicaría fondos erróneos
# o rompería las consultas de clima en silencio.
validar_configuracion() {
    local var valor

    if ! [[ "$CIUDAD" =~ ^[A-Za-z0-9.,_-]+$ ]]; then
        log "ERROR: CIUDAD inválida ('$CIUDAD'). Debe contener solo letras y números (sin espacios ni tildes), opcionalmente . , _ o -. Ej: CanuelasAR, LondonGB, ParisFR."
        exit 1
    fi

    if ! [[ "$MODO_HORARIOS" =~ ^(fijo|auto)$ ]]; then
        log "ERROR: MODO_HORARIOS inválido ('$MODO_HORARIOS'). Debe ser 'fijo' (horarios hardcodeados en config.conf) o 'auto' (según la salida/puesta del sol)."
        exit 1
    fi

    for var in HORA_INICIO_AMANECER HORA_INICIO_MEDIODIA HORA_INICIO_ATARDECER HORA_INICIO_NOCHE; do
        valor="${!var}"
        if ! [[ "$valor" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
            log "ERROR: $var inválida ('$valor'). Debe estar en formato HH:MM de 24 horas. Ej: 06:00"
            exit 1
        fi
    done

    if ! [[ "$PASOS_TRANSICION" =~ ^[0-9]+$ ]]; then
        log "ERROR: PASOS_TRANSICION inválido ('$PASOS_TRANSICION'). Debe ser un entero >= 0 (0 desactiva la transición)."
        exit 1
    fi

    if ! [[ "$PAUSA_ENTRE_PASOS" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        log "ERROR: PAUSA_ENTRE_PASOS inválida ('$PAUSA_ENTRE_PASOS'). Debe ser un número, por ejemplo 0.15."
        exit 1
    fi

    if ! [[ "$ESPERA_INICIAL_SEGUNDOS" =~ ^[0-9]+$ ]]; then
        log "ERROR: ESPERA_INICIAL_SEGUNDOS inválida ('$ESPERA_INICIAL_SEGUNDOS'). Debe ser un entero >= 0."
        exit 1
    fi

    if ! [[ "$REINTENTOS_CLIMA_INICIAL" =~ ^[0-9]+$ ]]; then
        log "ERROR: REINTENTOS_CLIMA_INICIAL inválido ('$REINTENTOS_CLIMA_INICIAL'). Debe ser un entero >= 0."
        exit 1
    fi

    if ! [[ "$ESPERA_REINTENTO_CLIMA" =~ ^[0-9]+$ ]]; then
        log "ERROR: ESPERA_REINTENTO_CLIMA inválida ('$ESPERA_REINTENTO_CLIMA'). Debe ser un entero >= 0."
        exit 1
    fi

    if ! [[ "$TTL_CACHE_CLIMA" =~ ^[0-9]+$ ]]; then
        log "ERROR: TTL_CACHE_CLIMA inválido ('$TTL_CACHE_CLIMA'). Debe ser un entero >= 0 (0 desactiva la caché)."
        exit 1
    fi

    if ! [[ "$MAX_LOG_BYTES" =~ ^[0-9]+$ ]]; then
        log "ERROR: MAX_LOG_BYTES inválido ('$MAX_LOG_BYTES'). Debe ser un entero >= 0."
        exit 1
    fi

    if [ ! -d "$CARPETA_FONDOS" ]; then
        log "ERROR: CARPETA_FONDOS no es un directorio válido ('$CARPETA_FONDOS'). Revisá el valor en $CONFIG_FILE."
        exit 1
    fi
}

# obtener_props_fondo
# Devuelve todas las propiedades "last-image" de xfconf (una por monitor y/o
# workspace). Vacío si no hay ninguna (perfil XFCE recién creado, por ejemplo).
obtener_props_fondo() {
    xfconf-query -c xfce4-desktop -l 2>/dev/null | grep 'last-image$'
}

# obtener_fondo_actual
# Devuelve la ruta de la imagen actualmente configurada como fondo, tomando
# la primera propiedad "last-image" que encuentre. Vacío si no hay ninguna.
obtener_fondo_actual() {
    local prop
    if [ "$MODO_DRY" = "si" ]; then
        return 0
    fi
    prop=$(obtener_props_fondo | head -n 1)
    if [ -n "$prop" ]; then
        xfconf-query -c xfce4-desktop -p "$prop" 2>/dev/null
    fi
}

# aplicar_fondo <imagen> [<props>]
# Asigna <imagen> en todas las propiedades "last-image" de xfconf. Si se pasa
# <props> (lista ya obtenida) se reutiliza, para no relanzar xfconf-query en
# cada uno de los pasos de la transición. Registra en el log las propiedades
# que fallaron, en lugar de fracasar en silencio.
aplicar_fondo() {
    local imagen="$1"
    local props="${2:-}"
    local n_fallos=0
    local msj=""
    local prop

    if [ -z "$props" ]; then
        props=$(obtener_props_fondo)
    fi

    if [ "$MODO_DRY" = "si" ]; then
        log "DRY-RUN: se aplicaría '$imagen' como fondo de pantalla."
        return 0
    fi

    if [ -z "$props" ]; then
        log "AVISO: no se encontró ninguna propiedad 'last-image' en xfce4-desktop. (¿Está corriendo el escritorio XFCE de esta sesión?)"
        return 1
    fi

    while IFS= read -r prop; do
        [ -z "$prop" ] && continue
        if ! xfconf-query -c xfce4-desktop -p "$prop" -s "$imagen" 2>/dev/null; then
            [ -n "$msj" ] && msj="$msj, "
            msj="$msj$prop"
            n_fallos=$((n_fallos + 1))
        fi
    done <<< "$props"

    if [ "$n_fallos" -gt 0 ]; then
        log "AVISO: fallaron $n_fallos propiedad(es) 'last-image' al aplicar '$imagen': $msj"
        return 1
    fi
    return 0
}

# transicionar_fondo <imagen_destino>
# Hace un fundido gradual desde el fondo actual hacia <imagen_destino>,
# generando PASOS_TRANSICION frames intermedios con ImageMagick en un
# directorio temporal seguro (mktemp). Si no hay ImageMagick, no hay fondo
# previo válido, no hay propiedades last-image, o PASOS_TRANSICION es 0,
# aplica el cambio directo. Cada frame se verifica antes de aplicarse, para
# no setear nunca un archivo inexistente como fondo.
transicionar_fondo() {
    local destino="$1"
    local origen props tamanio

    if [ "$MODO_DRY" = "si" ]; then
        if command -v convert >/dev/null 2>&1 && [ "$PASOS_TRANSICION" -gt 0 ]; then
            log "DRY-RUN: habría un fundido de $PASOS_TRANSICION pasos hacia '$destino' (si hay fondo previo válido)."
        fi
        aplicar_fondo "$destino"
        return 0
    fi

    origen=$(obtener_fondo_actual)

    if ! command -v convert >/dev/null 2>&1 \
        || [ -z "$origen" ] \
        || [ ! -f "$origen" ] \
        || [ "$origen" = "$destino" ] \
        || [ "$PASOS_TRANSICION" -le 0 ]; then
        aplicar_fondo "$destino"
        return 0
    fi

    # Se obtienen las propiedades UNA vez y se reutilizan en todos los frames.
    props=$(obtener_props_fondo)
    if [ -z "$props" ]; then
        log "AVISO: no hay propiedades last-image; se aplica el fondo sin fundido."
        aplicar_fondo "$destino"
        return 0
    fi

    tamanio=$(identify -format '%wx%h' "$origen" 2>/dev/null || true)
    if [ -z "$tamanio" ]; then
        log "AVISO: no se pudo determinar el tamaño de '$origen' (identify devolvió vacío); se aplica el cambio directo."
        aplicar_fondo "$destino" "$props"
        return 0
    fi

    TMP_TRANSICION=$(mktemp -d "${TMPDIR:-/tmp}/field-house.XXXXXX") || {
        log "ERROR: no se pudo crear un directorio temporal para la transición; se aplica el cambio directo."
        aplicar_fondo "$destino" "$props"
        return 0
    }

    local i porcentaje frame
    for i in $(seq 1 "$PASOS_TRANSICION"); do
        porcentaje=$((100 * i / PASOS_TRANSICION))
        frame="$TMP_TRANSICION/paso_$(printf '%02d' "$i").jpg"

        if ! convert "$origen" \( "$destino" -resize "${tamanio}!" \) \
                -compose blend -define "compose:args=${porcentaje}" -composite \
                "$frame" 2>/dev/null; then
            log "AVISO: falló la generación del frame $i del fundido; se continúa con el próximo."
            continue
        fi
        if [ ! -f "$frame" ]; then
            log "AVISO: el frame $i no quedó generado; se continúa con el próximo."
            continue
        fi

        aplicar_fondo "$frame" "$props"
        sleep "$PAUSA_ENTRE_PASOS"
    done

    aplicar_fondo "$destino" "$props"
    rm -rf "$TMP_TRANSICION"
    TMP_TRANSICION=""
}

# consultar_clima
# Consulta wttr.in UNA vez (con timeout corto de conexión) y devuelve la
# condición en minúscula. Devuelve cadena vacía si la consulta falla o si la
# respuesta no es una condición real (sin internet, ciudad inválida, etc).
# Para no molestar a la API con consultas redundantes (por ejemplo, cuando el
# timer horario y el login disparan casi en el mismo momento), se guarda el
# resultado en un caché por TTL_CACHE_CLIMA segundos.
consultar_clima() {
    local ahora timestamp_cached respuesta pared

    if [ -f "$CACHE_CLIMA" ]; then
        timestamp_cached=$(grep '^TS=' "$CACHE_CLIMA" 2>/dev/null | cut -d= -f2)
        if [ "$MODO_DRY" = "no" ] && [ -n "$timestamp_cached" ]; then
            ahora=$(date +%s)
            if [ $((ahora - timestamp_cached)) -lt "$TTL_CACHE_CLIMA" ]; then
                grep '^CLIMA=' "$CACHE_CLIMA" 2>/dev/null | cut -d= -f2
                return 0
            fi
        fi
    fi

    respuesta=$(curl -s --connect-timeout 2 --max-time 6 "https://wttr.in/${CIUDAD}?format=%C" 2>/dev/null)
    pared=$(printf '%s' "$respuesta" | tr '[:upper:]' '[:lower:]')

    # wttr.in devuelve texto legible ("patchy rain possible", "overcast"...).
    # Respuestas vacías, o de error (ciudad desconocida, HTML, etc), cuentan
    # como fallo para no aplicar un fondo raro.
    if [ -z "$pared" ] || echo "$pared" | grep -qE "unknown|error|sorry|page not found"; then
        echo ""
        return 1
    fi

    if [ "$MODO_DRY" = "no" ]; then
        ahora=$(date +%s)
        { echo "TS=$ahora"; echo "CLIMA=$pared"; } > "$CACHE_CLIMA" 2>/dev/null || \
            log "AVISO: no se pudo guardar el caché de clima en $CACHE_CLIMA."
    fi

    echo "$pared"
}

# ----------------------------------------------------------------------------
# GUARD DE TESTING
# ----------------------------------------------------------------------------
# Si FIELD_HOUSE_SOURCE_ONLY está seteada (cualquier valor no vacío), el
# script termina acá, justo después de definir todas las funciones y ANTES
# de tocar lock/red/xfconf/filesystem de estado. Esto permite a la suite de
# tests (tests/change_wallpaper.bats) hacer `source` del script real para
# probar las funciones puras (hora_a_minutos, min_a_hora, validar_configuracion,
# la lógica de decisión de nublado/lluvia, etc.) sin disparar ningún efecto
# secundario del cuerpo principal. No afecta la ejecución normal: en
# producción esta variable nunca se define.
if [ -n "${FIELD_HOUSE_SOURCE_ONLY:-}" ]; then
    # shellcheck disable=SC2317
    # SC2317 (unreachable) es un falso positivo acá: shellcheck no puede
    # saber que `return` sí es alcanzable cuando el script se invoca con
    # `source` (el caso real de uso de este guard, desde tests/*.bats).
    return 0 2>/dev/null || exit 0
fi

# ----------------------------------------------------------------------------
# 0) Preparar estado (lock anti-concurrencia, solo en ejecución real)
# ----------------------------------------------------------------------------
# Cierra la puerta a que el timer y el servicio de login corran el script a
# la vez (pasa al arrancar) y se pisen recetas de transición. El lock se
# libera solo cuando el script termina. En --dry-run no se crea estado ni se
# toma el lock: la simulación no debe dejar rastro.

if [ "$MODO_DRY" = "no" ]; then
    mkdir -p "$STATE_DIR"
fi

# Se valida después de crear el directorio de estado (los errores se escriben
# al log) pero ANTES de tomar el lock: así una dependencia faltante sale
# limpia, sin intentos fallidos de flock ni ruido en la terminal.
validar_dependencias

# ----------------------------------------------------------------------------
# 0) Lock anti-concurrencia (solo en ejecución real)
# ----------------------------------------------------------------------------
# Cierra la puerta a que el timer y el servicio de login corran el script a
# la vez (pasa al arrancar) y se pisen recetas de transición. El lock se
# libera solo cuando el script termina. En --dry-run no se toma el lock: la
# simulación no debe tocar estado.

if [ "$MODO_DRY" = "no" ]; then
    exec 9>"$STATE_DIR/lock"
    flock 9
fi

# ----------------------------------------------------------------------------
# 0.1) Cargar configuración
# ----------------------------------------------------------------------------

if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: no se encontró el archivo de configuración en $CONFIG_FILE. ¿Corriste install.sh?"
    exit 1
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Valores por defecto por si el archivo de config es viejo y le faltan
# variables nuevas (evita que un update rompa una instalación existente).
: "${CARPETA_FONDOS:=$DATOS_APP/fondos}"
: "${CIUDAD:=}"
: "${MODO_HORARIOS:=fijo}"
: "${HORA_INICIO_AMANECER:=06:00}"
: "${HORA_INICIO_MEDIODIA:=10:00}"
: "${HORA_INICIO_ATARDECER:=15:00}"
: "${HORA_INICIO_NOCHE:=20:00}"
: "${PASOS_TRANSICION:=15}"
: "${PAUSA_ENTRE_PASOS:=0.15}"
: "${ESPERA_INICIAL_SEGUNDOS:=15}"
: "${REINTENTOS_CLIMA_INICIAL:=3}"
: "${ESPERA_REINTENTO_CLIMA:=60}"
: "${TTL_CACHE_CLIMA:=600}"
: "${MAX_LOG_BYTES:=1048576}"

if [ -z "$CIUDAD" ]; then
    log "ERROR: no hay ciudad configurada en $CONFIG_FILE. Corré install.sh de nuevo o editá CIUDAD manualmente."
    exit 1
fi

validar_configuracion

FONDO_AMANECER="$CARPETA_FONDOS/amanecer.jpg"
FONDO_MEDIODIA="$CARPETA_FONDOS/mediodia.jpg"
FONDO_ATARDECER="$CARPETA_FONDOS/tarde.jpg"
FONDO_NOCHE="$CARPETA_FONDOS/noche.jpg"
FONDO_NUBLADO_DIA="$CARPETA_FONDOS/nublado-dia.jpg"
FONDO_NUBLADO_NOCHE="$CARPETA_FONDOS/nublado-noche.jpg"
FONDO_LLUVIA_DIA="$CARPETA_FONDOS/lluvia-dia.jpg"
FONDO_LLUVIA_ATARDECER="$CARPETA_FONDOS/lluvia-atardecer.jpg"
FONDO_LLUVIA_NOCHE="$CARPETA_FONDOS/lluvia-noche.jpg"

# ----------------------------------------------------------------------------
# 0.2) Espera inicial (solo si se invoca con --reboot)
# ----------------------------------------------------------------------------
# Al iniciar sesión, el escritorio XFCE puede tardar unos segundos en estar
# listo; sin esta espera, xfconf-query podría fallar. Solo se aplica con el
# flag --reboot para no demorar las ejecuciones periódicas normales. En
# --dry-run se omite (no hay XFCE real involucrado).

if [ "$ARG_REBOOT" = "si" ] && [ "$MODO_DRY" = "no" ]; then
    sleep "$ESPERA_INICIAL_SEGUNDOS"
fi

# ----------------------------------------------------------------------------
# 1) Verificar que todas las imágenes de fondo existen
# ----------------------------------------------------------------------------

FALTANTES=()
for f in "$FONDO_AMANECER" "$FONDO_MEDIODIA" "$FONDO_ATARDECER" "$FONDO_NOCHE" \
         "$FONDO_NUBLADO_DIA" "$FONDO_NUBLADO_NOCHE" \
         "$FONDO_LLUVIA_DIA" "$FONDO_LLUVIA_ATARDECER" "$FONDO_LLUVIA_NOCHE"; do
    [ -f "$f" ] || FALTANTES+=("$f")
done

if [ "${#FALTANTES[@]}" -gt 0 ]; then
    log "ERROR: faltan ${#FALTANTES[@]} imagen(es) de fondo: ${FALTANTES[*]}"
    exit 1
fi

# ----------------------------------------------------------------------------
# 2) Determinar la franja horaria actual (horas fijas)
# ----------------------------------------------------------------------------

AHORA_MIN=$(( $(date +%H)*60 + $(date +%M) ))

# Horarios de las franjas. Por defecto (MODO_HORARIOS=fijo) son fijos, desde
# config.conf. En modo auto se calculan según la salida/puesta real del sol
# en CIUDAD; si ese cálculo falla (sin internet, por ejemplo), se degrada a
# los horarios fijos, que funcionan además como valores de respaldo.
MIN_AMANECER=$(hora_a_minutos "$HORA_INICIO_AMANECER")
MIN_MEDIODIA=$(hora_a_minutos "$HORA_INICIO_MEDIODIA")
MIN_ATARDECER=$(hora_a_minutos "$HORA_INICIO_ATARDECER")
MIN_NOCHE=$(hora_a_minutos "$HORA_INICIO_NOCHE")

if [ "$MODO_HORARIOS" = "auto" ]; then
    horarios_sol=$(consultar_horarios_sol)
    if [ -n "$horarios_sol" ]; then
        read -r MIN_AMANECER MIN_MEDIODIA MIN_ATARDECER MIN_NOCHE <<< "$horarios_sol"
        log "Horarios según el sol: amanecer $(min_a_hora "$MIN_AMANECER"), mediodía $(min_a_hora "$MIN_MEDIODIA"), atardecer $(min_a_hora "$MIN_ATARDECER"), noche $(min_a_hora "$MIN_NOCHE")"
    else
        log "AVISO: no se pudo obtener la salida/puesta del sol; se usan los horarios fijos de config.conf."
    fi
fi

# FRANJA_CLIMA indica qué fondo de nublado/lluvia corresponde según la
# franja: "dia" (amanecer o mediodía), "atardecer" o "noche".
if [ "$AHORA_MIN" -ge "$MIN_AMANECER" ] && [ "$AHORA_MIN" -lt "$MIN_MEDIODIA" ]; then
    FONDO="$FONDO_AMANECER"
    MOMENTO="amanecer"
    FRANJA_CLIMA="dia"
elif [ "$AHORA_MIN" -ge "$MIN_MEDIODIA" ] && [ "$AHORA_MIN" -lt "$MIN_ATARDECER" ]; then
    FONDO="$FONDO_MEDIODIA"
    MOMENTO="mediodia"
    FRANJA_CLIMA="dia"
elif [ "$AHORA_MIN" -ge "$MIN_ATARDECER" ] && [ "$AHORA_MIN" -lt "$MIN_NOCHE" ]; then
    FONDO="$FONDO_ATARDECER"
    MOMENTO="atardecer"
    FRANJA_CLIMA="atardecer"
else
    FONDO="$FONDO_NOCHE"
    MOMENTO="noche"
    FRANJA_CLIMA="noche"
fi

# ----------------------------------------------------------------------------
# 3) Consultar el clima actual y, si está nublado o llueve, usar el fondo
#    correspondiente a la franja (día, atardecer o noche). El "nublado" y la
#    "lluvia" son condiciones distintas y usan imágenes distintas; durante el
#    atardecer nublado se usa la imagen "nublado-dia" (aún hay luz de día).
#
#    Al iniciar sesión (--reboot) la red puede estar todavía levantándose
#    (por ejemplo un WiFi que tarda en conectarse), así que si la consulta
#    falla se aplica ya el fondo base de la franja y se reintenta cada
#    ESPERA_REINTENTO_CLIMA segundos, hasta REINTENTOS_CLIMA_INICIAL veces.
# ----------------------------------------------------------------------------
# DISPLAY y DBUS son necesarios porque systemd/cron pueden correr esto sin
# que las variables de la sesión gráfica estén heredadas.

export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

CLIMA=""
if [ "$ARG_REBOOT" = "si" ] && [ "$MODO_DRY" = "no" ]; then
    intento=1
    while [ "$intento" -le "$REINTENTOS_CLIMA_INICIAL" ]; do
        CLIMA=$(consultar_clima)
        [ -n "$CLIMA" ] && break
        if [ "$intento" -lt "$REINTENTOS_CLIMA_INICIAL" ]; then
            log "Sin internet todavía (intento $intento/$REINTENTOS_CLIMA_INICIAL), se aplica el fondo base y se reintenta en ${ESPERA_REINTENTO_CLIMA}s."
            transicionar_fondo "$FONDO"
            sleep "$ESPERA_REINTENTO_CLIMA"
        fi
        intento=$((intento + 1))
    done
else
    CLIMA=$(consultar_clima)
fi

if [ -z "$CLIMA" ]; then
    log "No se pudo consultar el clima, se usa el fondo base ($MOMENTO)"
elif echo "$CLIMA" | grep -qE "overcast|cloudy"; then
    case "$FRANJA_CLIMA" in
        dia|atardecer)
            FONDO="$FONDO_NUBLADO_DIA"
            MOMENTO="nublado de día ($CLIMA)"
            ;;
        noche)
            FONDO="$FONDO_NUBLADO_NOCHE"
            MOMENTO="nublado de noche ($CLIMA)"
            ;;
    esac
elif echo "$CLIMA" | grep -qE "rain|drizzle|shower|thunder|mist|fog"; then
    case "$FRANJA_CLIMA" in
        dia)
            FONDO="$FONDO_LLUVIA_DIA"
            MOMENTO="lluvia de día ($CLIMA)"
            ;;
        atardecer)
            FONDO="$FONDO_LLUVIA_ATARDECER"
            MOMENTO="lluvia de atardecer ($CLIMA)"
            ;;
        noche)
            FONDO="$FONDO_LLUVIA_NOCHE"
            MOMENTO="lluvia de noche ($CLIMA)"
            ;;
    esac
fi

# ----------------------------------------------------------------------------
# 4) Aplicar el fondo elegido (con transición si es posible)
# ----------------------------------------------------------------------------

transicionar_fondo "$FONDO"

log "Fondo aplicado: $MOMENTO -> $FONDO"