#!/bin/bash
# ============================================================================
# The Field House — Live Wallpaper
# cambiar_fondo.sh
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
# para probar.
#
# Uso:
#   cambiar_fondo.sh            ejecución normal (la usa el timer de systemd)
#   cambiar_fondo.sh --reboot   ejecución al iniciar sesión (agrega una
#                                espera inicial, ver ESPERA_INICIAL_SEGUNDOS)
#
# Requiere: curl, xfconf-query (XFCE). Opcional: convert (ImageMagick) para
# la transición suave entre fondos; si no está instalado, el cambio de
# fondo es directo, sin fundido.
# ============================================================================

set -u

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

mkdir -p "$STATE_DIR"

# Cierra la puerta a que el timer y el servicio de login corran el script a
# la vez (pasa al arrancar) y se pisen recetas de transición. El lock se
# libera solo cuando el script termina.
exec 9>"$STATE_DIR/lock"
flock 9

# ----------------------------------------------------------------------------
# FUNCIONES
# ----------------------------------------------------------------------------

# log <mensaje>
# Agrega una línea con fecha/hora al archivo de log.
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG"
}

# hora_a_minutos <HH:MM>
# Convierte una hora en formato HH:MM a minutos desde medianoche (entero).
hora_a_minutos() {
    local hora="$1"
    echo "$hora" | awk -F: '{print $1*60+$2}'
}

# aplicar_fondo <ruta_imagen>
# Asigna la imagen indicada como fondo de pantalla en todas las propiedades
# "last-image" de xfconf (una por monitor/workspace), sin transición.
aplicar_fondo() {
    local imagen="$1"
    for prop in $(xfconf-query -c xfce4-desktop -l | grep 'last-image$'); do
        xfconf-query -c xfce4-desktop -p "$prop" -s "$imagen"
    done
}

# obtener_fondo_actual
# Devuelve la ruta de la imagen actualmente configurada como fondo,
# tomando la primera propiedad "last-image" que encuentre.
obtener_fondo_actual() {
    local prop
    prop=$(xfconf-query -c xfce4-desktop -l | grep 'last-image$' | head -n 1)
    if [ -n "$prop" ]; then
        xfconf-query -c xfce4-desktop -p "$prop"
    fi
}

# transicionar_fondo <imagen_destino>
# Hace un fundido gradual desde el fondo actual hacia <imagen_destino>,
# generando PASOS_TRANSICION imágenes intermedias con ImageMagick. Si no
# hay ImageMagick, no hay fondo previo válido, o PASOS_TRANSICION es 0,
# aplica el cambio directo sin efecto.
transicionar_fondo() {
    local destino="$1"
    local origen
    origen=$(obtener_fondo_actual)

    if ! command -v convert >/dev/null 2>&1 \
        || [ -z "$origen" ] \
        || [ ! -f "$origen" ] \
        || [ "$origen" = "$destino" ] \
        || [ "$PASOS_TRANSICION" -le 0 ]; then
        aplicar_fondo "$destino"
        return
    fi

    local tmp_transicion="/tmp/field-house-transicion-$$"
    mkdir -p "$tmp_transicion"

    local i porcentaje frame
    for i in $(seq 1 "$PASOS_TRANSICION"); do
        porcentaje=$((100 * i / PASOS_TRANSICION))
        frame="$tmp_transicion/paso_$(printf '%02d' "$i").jpg"

        convert "$origen" \( "$destino" -resize "$(identify -format '%wx%h' "$origen" 2>/dev/null)!" \) \
            -compose blend -define compose:args="$porcentaje" -composite \
            "$frame" 2>/dev/null

        aplicar_fondo "$frame"
        sleep "$PAUSA_ENTRE_PASOS"
    done

    aplicar_fondo "$destino"
    rm -rf "$tmp_transicion"
}

# consultar_clima
# Consulta wttr.in una sola vez y devuelve la condición en minúscula
# (cadena vacía si no se pudo obtener, por ejemplo sin internet).
consultar_clima() {
    curl -s -m 8 "https://wttr.in/${CIUDAD}?format=%C" | tr '[:upper:]' '[:lower:]'
}

# ----------------------------------------------------------------------------
# 0) Cargar configuración
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
: "${HORA_INICIO_AMANECER:=06:00}"
: "${HORA_INICIO_MEDIODIA:=10:00}"
: "${HORA_INICIO_ATARDECER:=15:00}"
: "${HORA_INICIO_NOCHE:=20:00}"
: "${PASOS_TRANSICION:=15}"
: "${PAUSA_ENTRE_PASOS:=0.15}"
: "${ESPERA_INICIAL_SEGUNDOS:=15}"
: "${REINTENTOS_CLIMA_INICIAL:=3}"
: "${ESPERA_REINTENTO_CLIMA:=60}"

FONDO_AMANECER="$CARPETA_FONDOS/amanecer.jpg"
FONDO_MEDIODIA="$CARPETA_FONDOS/mediodia.jpg"
FONDO_ATARDECER="$CARPETA_FONDOS/tarde.jpg"
FONDO_NOCHE="$CARPETA_FONDOS/noche.jpg"
FONDO_NUBLADO_DIA="$CARPETA_FONDOS/nublado-dia.jpg"
FONDO_NUBLADO_NOCHE="$CARPETA_FONDOS/nublado-noche.jpg"
FONDO_LLUVIA_DIA="$CARPETA_FONDOS/lluvia-dia.jpg"
FONDO_LLUVIA_ATARDECER="$CARPETA_FONDOS/lluvia-atardecer.jpg"
FONDO_LLUVIA_NOCHE="$CARPETA_FONDOS/lluvia-noche.jpg"

if [ -z "$CIUDAD" ]; then
    log "ERROR: no hay ciudad configurada en $CONFIG_FILE. Corré install.sh de nuevo o editá CIUDAD manualmente."
    exit 1
fi

# ----------------------------------------------------------------------------
# 0.1) Espera inicial (solo si se invoca con --reboot)
# ----------------------------------------------------------------------------
# Al iniciar sesión, el escritorio XFCE puede tardar unos segundos en estar
# listo; sin esta espera, xfconf-query podría fallar. Solo se aplica con el
# flag --reboot para no demorar las ejecuciones periódicas normales.

if [ "${1:-}" = "--reboot" ]; then
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

MIN_AMANECER=$(hora_a_minutos "$HORA_INICIO_AMANECER")
MIN_MEDIODIA=$(hora_a_minutos "$HORA_INICIO_MEDIODIA")
MIN_ATARDECER=$(hora_a_minutos "$HORA_INICIO_ATARDECER")
MIN_NOCHE=$(hora_a_minutos "$HORA_INICIO_NOCHE")

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
if [ "${1:-}" = "--reboot" ]; then
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
    log "No se pudo consultar el clima, se usa fondo base ($MOMENTO)"
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
