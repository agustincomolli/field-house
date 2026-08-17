#!/bin/bash
# ============================================================================
# The Field House — Live Wallpaper
# install.sh — instalador
#
# Instala la app en el sistema del usuario (sin sudo, todo en rutas XDG del
# usuario actual), detecta la ubicación automáticamente para sugerirla como
# ciudad, y deja los timers de systemd habilitados y corriendo.
#
# Uso:
#   ./install.sh
# ============================================================================

set -Eeuo pipefail

VERSION="1.1.0"

# ----------------------------------------------------------------------------
# Colores (mismo estilo que setup.sh, para consistencia visual)
# ----------------------------------------------------------------------------
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}!${NC} $1"; }
error()   { echo -e "${RED}✗${NC} $1"; }

# ----------------------------------------------------------------------------
# Comprobaciones previas
# ----------------------------------------------------------------------------

if [[ "${EUID}" -eq 0 ]]; then
    error "No ejecutes este instalador como root/sudo."
    echo "Se instala completamente en tu carpeta de usuario. Ejecutá: ./install.sh"
    exit 1
fi

if ! command -v xfconf-query >/dev/null 2>&1; then
    error "No se encontró xfconf-query. Este programa es para entornos XFCE (Linux Mint XFCE, Xubuntu, etc)."
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1 || ! systemctl --user status >/dev/null 2>&1; then
    error "No se encontró systemd de usuario funcionando. Este instalador lo necesita para programar la ejecución automática."
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    error "Falta curl. Instalalo con: sudo apt install curl"
    exit 1
fi

# ----------------------------------------------------------------------------
# Rutas de instalación (XDG Base Directory)
# ----------------------------------------------------------------------------

DATOS_APP="${XDG_DATA_HOME:-$HOME/.local/share}/field-house"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/field-house"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/field-house"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
CONFIG_FILE="$CONFIG_DIR/config.conf"

# Carpeta donde está este instalador (para copiar bin/, fondos/, systemd/).
ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "====================================================================="
echo "       THE FIELD HOUSE — LIVE WALLPAPER — INSTALADOR  (v$VERSION)"
echo "====================================================================="
echo
echo "Este programa cambia el fondo de pantalla de XFCE automáticamente"
echo "según la hora del día y el clima de tu ciudad."
echo
echo "Se va a instalar en:"
echo "  Programa e imágenes : $DATOS_APP"
echo "  Configuración        : $CONFIG_DIR"
echo "  Logs                 : $STATE_DIR"
echo
# ----------------------------------------------------------------------------
# Detección de instalación previa
# ----------------------------------------------------------------------------
# Reinstalar es equivalente a una instalación de fábrica: si ya existe una
# instalación anterior (directorios o unidades de systemd), se borra por
# completo antes de copiar la nueva, para que no quede NADA de la versión
# vieja. El prompt "¿Continuar?" de abajo sirve de confirmación.

HAY_INSTALACION_PREVIA="no"
if [ -d "$DATOS_APP" ] || [ -d "$CONFIG_DIR" ] || [ -d "$STATE_DIR" ] \
    || compgen -G "$SYSTEMD_USER_DIR/field-house*.service" >/dev/null \
    || compgen -G "$SYSTEMD_USER_DIR/field-house*.timer" >/dev/null; then
    HAY_INSTALACION_PREVIA="si"
fi

if [ "$HAY_INSTALACION_PREVIA" = "si" ]; then
    warning "Se detectó una instalación previa de The Field House."
    warning "Reinstalar deja todo de fábrica: se borran el programa, las imágenes"
    warning "(incluidas las que hayas personalizado), la configuración y los logs."
fi

read -rp "¿Continuar? [S/n]: " CONFIRM_INSTALL
if [[ ! "$CONFIRM_INSTALL" =~ ^([sS]|[yY]|)$ ]]; then
    echo "Instalación cancelada."
    exit 0
fi

if [ "$HAY_INSTALACION_PREVIA" = "si" ]; then
    info "Eliminando la instalación previa..."
    systemctl --user disable --now field-house.timer 2>/dev/null || true
    systemctl --user disable --now field-house-login.service 2>/dev/null || true
    # Se borran TODAS las unidades de campo field-house*, no solo las actuales:
    # si una versión vieja dejó alguna con otro nombre, no debe sobrevivir.
    rm -f "$SYSTEMD_USER_DIR"/field-house*.service "$SYSTEMD_USER_DIR"/field-house*.timer
    systemctl --user daemon-reload
    rm -rf "$DATOS_APP" "$CONFIG_DIR" "$STATE_DIR"
    success "Instalación previa eliminada. Continuando con una instalación limpia."
fi

# ----------------------------------------------------------------------------
# 1) Detección automática de ubicación
# ----------------------------------------------------------------------------
# Se usa ip-api.com (HTTP, gratuito, sin API key para uso no comercial y
# volumen bajo) para resolver ciudad + país a partir de la IP pública.
# Si falla, o el usuario no está conforme, se le pide que la escriba a mano.

echo
info "1/4 - Detectando tu ubicación automáticamente..."

CIUDAD_DETECTADA=""
CIUDAD_LEGIBLE=""

RESPUESTA_GEO=$(curl -s -m 8 "http://ip-api.com/json/?fields=status,city,countryCode" || true)

if echo "$RESPUESTA_GEO" | grep -q '"status":"success"'; then
    CITY=$(echo "$RESPUESTA_GEO" | grep -oP '"city":"\K[^"]+' || true)
    COUNTRY=$(echo "$RESPUESTA_GEO" | grep -oP '"countryCode":"\K[^"]+' || true)

    if [[ -n "$CITY" && -n "$COUNTRY" ]]; then
        # wttr.in espera el nombre de ciudad sin espacios, pegado al código
        # de país funciona bien como desambiguador (igual que "CanuelasAR").
        CIUDAD_DETECTADA="${CITY// /}${COUNTRY}"
        CIUDAD_LEGIBLE="$CITY, $COUNTRY"
    fi
fi

if [[ -n "$CIUDAD_DETECTADA" ]]; then
    success "Ubicación detectada: $CIUDAD_LEGIBLE"
    echo
    echo "Se va a usar como ciudad para consultar el clima: $CIUDAD_DETECTADA"
    read -rp "¿Es correcta? [S/n]: " CONFIRM_CIUDAD

    if [[ ! "$CONFIRM_CIUDAD" =~ ^([sS]|[yY]|)$ ]]; then
        CIUDAD_DETECTADA=""
    fi
else
    warning "No se pudo detectar la ubicación automáticamente (sin internet o el servicio no respondió)."
fi

if [[ -z "$CIUDAD_DETECTADA" ]]; then
    echo
    echo "Ingresá tu ciudad manualmente, sin espacios ni tildes, seguida del"
    echo "código de país si tu ciudad tiene nombres repetidos en el mundo"
    echo "(por ejemplo: CanuelasAR, LondonGB, ParisFR)."
    echo
    echo "Podés probar qué te devuelve wttr.in para un nombre antes de"
    echo "confirmarlo, abriendo en otra terminal:"
    echo '  curl "https://wttr.in/TuCiudad?format=%C"'
    echo
    read -rp "Ciudad: " CIUDAD_DETECTADA

    while [[ -z "$CIUDAD_DETECTADA" ]]; do
        warning "No puede quedar vacío."
        read -rp "Ciudad: " CIUDAD_DETECTADA
    done
fi

# Misma validación que aplica cambiar_fondo.sh en el arranque: si el nombre
# tuviera caracteres que rompen la URL de wttr.in, nadie se enteraría hasta
# ver un fondo raro. Mejor fallar acá, con el valor a la vista.
if [[ ! "$CIUDAD_DETECTADA" =~ ^[A-Za-z0-9.,_-]+$ ]]; then
    error "Ciudad inválida: '$CIUDAD_DETECTADA'. Solo letras y números (sin espacios ni tildes), opcionalmente . , _ o -. Ej: CanuelasAR, LondonGB."
    exit 1
fi

success "Ciudad configurada: $CIUDAD_DETECTADA"

# ----------------------------------------------------------------------------
# Modo de horarios (fijo por defecto; auto según la salida/puesta del sol)
# ----------------------------------------------------------------------------
# "fijo" usa siempre los horarios de config.conf (comportamiento original).
# "auto" calcula las franjas a partir de la salida y puesta real del sol de
# la ciudad, con los horarios fijos como respaldo si la consulta falla.

echo
info "Modo de horarios..."
echo "  - 'fijo':  horarios fijos (amanecer 06:00, mediodía 10:00, atardecer 15:00, noche 20:00),"
echo "             siempre iguales, sin importar la estación del año."
echo "  - 'auto':  franjas según la salida y puesta real del sol en tu ciudad (mediodía ="
echo "             punto medio, noche = puesta + 2 hs). Requiere internet para calcularlas."
MODO_HORARIOS=""
read -rp "¿Cuál querés? [fijo/auto] (default: fijo): " MODO_HORARIOS
if [[ -z "$MODO_HORARIOS" ]]; then
    MODO_HORARIOS="fijo"
fi
if [[ "$MODO_HORARIOS" != "fijo" && "$MODO_HORARIOS" != "auto" ]]; then
    error "Modo inválido: '$MODO_HORARIOS'. Debe ser 'fijo' o 'auto'."
    exit 1
fi
success "Horarios: $MODO_HORARIOS"

# ----------------------------------------------------------------------------
# 2) Copiar programa e imágenes
# ----------------------------------------------------------------------------

echo
info "2/4 - Instalando archivos..."

mkdir -p "$DATOS_APP/bin" "$DATOS_APP/fondos" "$CONFIG_DIR" "$STATE_DIR" "$SYSTEMD_USER_DIR"

cp "$ORIGEN/bin/cambiar_fondo.sh" "$DATOS_APP/bin/cambiar_fondo.sh"
chmod +x "$DATOS_APP/bin/cambiar_fondo.sh"

cp "$ORIGEN"/fondos/*.jpg "$DATOS_APP/fondos/"

# Verificación: si el cp falló parcialmente (por ejemplo un .jpg ilegible), el
# script de fondo se quejaría de imágenes faltantes recién al correr. Mejor
# avisarlo acá, mientras la instalación está fresca.
FONDOS_COPIADOS=$(find "$DATOS_APP/fondos" -maxdepth 1 -name '*.jpg' 2>/dev/null | wc -l || true)
if [ "$FONDOS_COPIADOS" -ne 9 ]; then
    error "La copia de imágenes no quedó completa: se encontraron $FONDOS_COPIADOS de 9 archivos .jpg. Revisá la carpeta 'fondos/' del repositorio."
    exit 1
fi

success "Programa instalado en $DATOS_APP"

# ----------------------------------------------------------------------------
# 3) Generar archivo de configuración
# ----------------------------------------------------------------------------

echo
info "3/4 - Generando configuración..."

# No hay backup de la configuración anterior: la instalación es de fábrica.
# (La limpieza del paso 0 ya borró lo viejo; la reinstalación no conserva nada.)

cat << EOF > "$CONFIG_FILE"
# Configuración de The Field House.
# Podés editar estos valores en cualquier momento; se aplican en la
# próxima ejecución (no hace falta reinstalar ni reiniciar la sesión).

# Carpeta donde están las imágenes de fondo.
CARPETA_FONDOS="$DATOS_APP/fondos"

# Ciudad para consultar el clima en wttr.in (sin espacios ni tildes).
CIUDAD="$CIUDAD_DETECTADA"

# Modo de horarios: "fijo" (usa los HORA_INICIO_* de acá abajo, siempre los
# mismos) o "auto" (calcula amanecer/mediodía/atardecer/noche según la salida
# y puesta real del sol; si la consulta falla, usa los fijos de acá abajo).
MODO_HORARIOS="$MODO_HORARIOS"

# Franjas horarias fijas (formato HH:MM, 24hs). Son las que se usan tal cual
# en modo fijo, y el respaldo en modo auto cuando no se puede consultar el sol.
HORA_INICIO_AMANECER="06:00"
HORA_INICIO_MEDIODIA="10:00"
HORA_INICIO_ATARDECER="15:00"
HORA_INICIO_NOCHE="20:00"

# Transición de fundido entre fondos (requiere imagemagick instalado).
# PASOS_TRANSICION=0 desactiva la transición (cambio directo).
PASOS_TRANSICION=15
PAUSA_ENTRE_PASOS="0.15"

# Espera en segundos antes de aplicar el fondo al iniciar sesión, para
# darle tiempo a XFCE a estar listo.
ESPERA_INICIAL_SEGUNDOS=15

# Al iniciar sesión, si la red todavía no está lista (WiFi lentos, etc.),
# se aplica el fondo base de la franja y se reintenta el clima cada
# ESPERA_REINTENTO_CLIMA segundos, hasta REINTENTOS_CLIMA_INICIAL veces.
REINTENTOS_CLIMA_INICIAL=3
ESPERA_REINTENTO_CLIMA=60

# Caché del clima: durante cuántos segundos se reutiliza la última consulta
# a wttr.in antes de volver a consultar (evita llamadas redundantes cuando
# el timer horario y el login disparan casi en el mismo momento).
TTL_CACHE_CLIMA=600

# Tamaño máximo del log en bytes antes de rotarlo a log.txt.1 (1 MiB).
MAX_LOG_BYTES=1048576
EOF

success "Configuración guardada en $CONFIG_FILE"

if ! command -v convert >/dev/null 2>&1; then
    warning "No se encontró ImageMagick (comando 'convert'). La app va a funcionar igual, pero sin la transición de fundido entre fondos."
    warning "Para tenerla, instalá: sudo apt install imagemagick"
fi

# ----------------------------------------------------------------------------
# 4) Instalar y habilitar los servicios de systemd (usuario)
# ----------------------------------------------------------------------------

echo
info "4/4 - Configurando ejecución automática (systemd)..."

# Los archivos .service apuntan a %h (HOME del usuario), así que se copian
# tal cual, sin necesidad de reemplazar rutas.
cp "$ORIGEN/systemd/field-house.service" "$SYSTEMD_USER_DIR/"
cp "$ORIGEN/systemd/field-house.timer" "$SYSTEMD_USER_DIR/"
cp "$ORIGEN/systemd/field-house-login.service" "$SYSTEMD_USER_DIR/"

systemctl --user daemon-reload

# Limpiar unidades que hayan quedado en estado "failed" de corridas previas,
# para que el estado refleje solo la instalación nueva.
systemctl --user reset-failed field-house.service field-house.timer field-house-login.service 2>/dev/null || true

# Timer que corre cada hora.
systemctl --user enable --now field-house.timer

# Servicio que corre una vez al iniciar sesión gráfica.
systemctl --user enable field-house-login.service

success "Servicios de systemd instalados y habilitados."

# Primera ejecución inmediata, para que el fondo quede aplicado ya mismo
# en vez de esperar a la próxima hora en punto.
info "Aplicando el primer fondo..."
if "$DATOS_APP/bin/cambiar_fondo.sh"; then
    success "Fondo aplicado correctamente."
else
    warning "La primera ejecución falló. Revisá el log en $STATE_DIR/log.txt"
fi

# ----------------------------------------------------------------------------
# Resumen final
# ----------------------------------------------------------------------------

echo
echo "====================================================================="
echo -e "${GREEN}         THE FIELD HOUSE — INSTALACIÓN COMPLETADA${NC}"
echo "====================================================================="
echo
echo "  ✓ Programa      : $DATOS_APP"
echo "  ✓ Configuración : $CONFIG_FILE"
echo "  ✓ Logs          : $STATE_DIR/log.txt"
echo "  ✓ Ciudad        : $CIUDAD_DETECTADA"
echo "  ✓ Horarios      : $MODO_HORARIOS"
echo
echo "El fondo se va a actualizar solo cada hora, y también al iniciar sesión."
echo
echo "Comandos útiles:"
echo
echo "  Ver estado del timer:"
echo "    systemctl --user status field-house.timer"
echo
echo "  Ejecutar manualmente ahora:"
echo "    $DATOS_APP/bin/cambiar_fondo.sh"
echo
echo "  Simular sin tocar nada (qué fondo se aplicaría):"
echo "    $DATOS_APP/bin/cambiar_fondo.sh --dry-run"
echo
echo "  Ver la ayuda completa:"
echo "    $DATOS_APP/bin/cambiar_fondo.sh --help"
echo
echo "  Ver el log:"
echo "    tail -f $STATE_DIR/log.txt"
echo
echo "  Editar configuración (ciudad, franjas horarias):"
echo "    nano $CONFIG_FILE"
echo
echo "  Desinstalar:"
echo "    ./uninstall.sh"
echo
echo "====================================================================="
echo
