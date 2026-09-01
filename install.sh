#!/bin/bash
# ============================================================================
# The Field House — Live Wallpaper
# install.sh — instalador
#
# Instala la app en el sistema del usuario (sin sudo, todo en rutas XDG del
# usuario actual) y deja los timers de systemd habilitados y corriendo. La
# ubicación geográfica no se pregunta en la instalación: se detecta sola,
# por IP, en cada ejecución del programa (ver bin/change_wallpaper.sh).
#
# Uso:
#   ./install.sh                instalación normal (resguarda una instalación
#                                 previa si existe, ver --no-backup)
#   ./install.sh --no-backup    si hay una instalación previa, la borra
#                                 directamente en vez de resguardarla con
#                                 mv a *.bak.FECHAHORA. Perdés cualquier
#                                 imagen o configuración personalizada que
#                                 no hayas resguardado vos mismo antes.
#   ./install.sh --help         muestra esta ayuda
#   ./install.sh --version      muestra la versión del instalador
# ============================================================================

set -Eeuo pipefail

ORIGEN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(tr -d '[:space:]' < "$ORIGEN/VERSION")"

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
# Parseo de argumentos
# ----------------------------------------------------------------------------

SIN_BACKUP="no"

for arg in "$@"; do
    case "$arg" in
        --no-backup)
            SIN_BACKUP="si"
            ;;
        --help|-h)
            echo "The Field House — Live Wallpaper v$VERSION — instalador"
            echo
            echo "Uso:"
            echo "  ./install.sh                Instalación normal. Si hay una instalación"
            echo "                                previa, la resguarda con mv a *.bak.FECHAHORA"
            echo "                                antes de instalar la nueva."
            echo "  ./install.sh --no-backup    Si hay una instalación previa, la borra"
            echo "                                directamente en vez de resguardarla. Perdés"
            echo "                                cualquier imagen o configuración personalizada"
            echo "                                que no hayas resguardado vos mismo antes."
            echo "  ./install.sh --help         Muestra esta ayuda."
            echo "  ./install.sh --version      Muestra la versión del instalador."
            exit 0
            ;;
        --version|-v)
            echo "The Field House — Live Wallpaper v$VERSION — instalador"
            exit 0
            ;;
        *)
            error "Argumento desconocido: $arg"
            echo "Probá: ./install.sh --help"
            exit 1
            ;;
    esac
done



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

echo
echo "====================================================================="
echo "       THE FIELD HOUSE — LIVE WALLPAPER — INSTALADOR  (v$VERSION)"
echo "====================================================================="
echo
echo "Este programa cambia el fondo de pantalla de XFCE automáticamente"
echo "según la hora del día y el clima de tu ubicación (detectada automáticamente)."
echo
echo "Se va a instalar en:"
echo "  Programa e imágenes : $DATOS_APP"
echo "  Configuración        : $CONFIG_DIR"
echo "  Logs                 : $STATE_DIR"
echo
# ----------------------------------------------------------------------------
# Detección de instalación previa
# ----------------------------------------------------------------------------
# Reinstalar NO borra sin resguardo: si ya existe una instalación anterior
# (directorios o unidades de systemd), se la MUEVE a *.bak.FECHAHORA en la
# misma ubicación antes de instalar la nueva. Así, si el usuario tenía
# imágenes personalizadas en fondos/, quedan recuperables incluso si
# confirmó la reinstalación sin darse cuenta de que eso las iba a reemplazar.

HAY_INSTALACION_PREVIA="no"
if [ -d "$DATOS_APP" ] || [ -d "$CONFIG_DIR" ] || [ -d "$STATE_DIR" ] \
    || compgen -G "$SYSTEMD_USER_DIR/field-house*.service" >/dev/null \
    || compgen -G "$SYSTEMD_USER_DIR/field-house*.timer" >/dev/null; then
    HAY_INSTALACION_PREVIA="si"
fi

if [ "$HAY_INSTALACION_PREVIA" = "si" ]; then
    echo
    warning "Se detectó una instalación previa de The Field House."
    if [ "$SIN_BACKUP" = "si" ]; then
        echo "  Corriste el instalador con --no-backup: el programa, las imágenes"
        echo "  (incluidas las que hayas personalizado), la configuración y los"
        echo "  logs actuales se van a BORRAR de forma DEFINITIVA antes de instalar"
        echo "  la versión nueva. No hay forma de recuperarlos después de esto."
        echo
        read -rp "¿Reinstalar borrando la instalación anterior sin resguardo? [s/N]: " CONFIRM_REINSTALL
    else
        echo "  Antes de instalar la versión nueva, el programa, las imágenes"
        echo "  (incluidas las que hayas personalizado), la configuración y los"
        echo "  logs actuales se van a MOVER a una copia de resguardo con sufijo"
        echo "  '.bak.FECHAHORA' en el mismo lugar donde están ahora. No se borra"
        echo "  nada de forma irreversible; podés recuperarlos a mano después, o"
        echo "  borrar la copia vos mismo cuando ya no la necesites. (Usá"
        echo "  --no-backup si preferís borrar directamente sin resguardo.)"
        echo
        read -rp "¿Reinstalar? Se resguardará la instalación anterior. [s/N]: " CONFIRM_REINSTALL
    fi
    if [[ ! "$CONFIRM_REINSTALL" =~ ^([sS]|[yY])$ ]]; then
        echo "Instalación cancelada."
        exit 0
    fi
else
    read -rp "¿Continuar? [S/n]: " CONFIRM_INSTALL
    if [[ ! "$CONFIRM_INSTALL" =~ ^([sS]|[yY]|)$ ]]; then
        echo "Instalación cancelada."
        exit 0
    fi
fi

if [ "$HAY_INSTALACION_PREVIA" = "si" ]; then
    systemctl --user disable --now field-house.timer 2>/dev/null || true
    systemctl --user disable --now field-house-login.service 2>/dev/null || true
    # Se borran (no se resguardan) las unidades de systemd: son punteros de
    # una línea a rutas fijas, no datos del usuario; se regeneran solas al
    # instalar. Se incluye el patrón field-house* completo, no solo las
    # actuales, por si una versión vieja dejó alguna con otro nombre.
    rm -f "$SYSTEMD_USER_DIR"/field-house*.service "$SYSTEMD_USER_DIR"/field-house*.timer
    systemctl --user daemon-reload

    if [ "$SIN_BACKUP" = "si" ]; then
        info "Eliminando la instalación previa (sin resguardo)..."
        rm -rf "$DATOS_APP" "$CONFIG_DIR" "$STATE_DIR"
        success "Instalación previa eliminada. Continuando con una instalación limpia."
    else
        info "Resguardando la instalación previa..."
        SUFIJO_BAK=".bak.$(date +%Y%m%d%H%M%S)"

        for dir in "$DATOS_APP" "$CONFIG_DIR" "$STATE_DIR"; do
            if [ -d "$dir" ]; then
                mv "$dir" "${dir}${SUFIJO_BAK}"
            fi
        done

        success "Instalación previa resguardada con el sufijo '$SUFIJO_BAK' junto a cada carpeta original."
    fi
fi

# ----------------------------------------------------------------------------
# Modo de horarios (fijo por defecto; auto según la salida/puesta del sol)
# ----------------------------------------------------------------------------
# "fijo" usa siempre los horarios de config.conf (comportamiento original).
# "auto" calcula las franjas a partir de la salida y puesta real del sol de
# la ubicación detectada automáticamente, con los horarios fijos como
# respaldo si la consulta falla.

echo
info "Modo de horarios..."
echo "  - 'fijo':  horarios fijos (amanecer 06:00, mediodía 10:00, atardecer 15:00, noche 20:00),"
echo "             siempre iguales, sin importar la estación del año."
echo "  - 'auto':  franjas según la salida y puesta real del sol en tu ubicación (mediodía ="
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
info "1/3 - Instalando archivos..."

mkdir -p "$DATOS_APP/bin" "$DATOS_APP/fondos" "$CONFIG_DIR" "$STATE_DIR" "$SYSTEMD_USER_DIR"

cp "$ORIGEN/bin/change_wallpaper.sh" "$DATOS_APP/bin/change_wallpaper.sh"
chmod +x "$DATOS_APP/bin/change_wallpaper.sh"
cp "$ORIGEN/VERSION" "$DATOS_APP/VERSION"

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
info "2/3 - Generando configuración..."

# No hay backup de la configuración anterior: la instalación es de fábrica.
# (La limpieza del paso 0 ya borró lo viejo; la reinstalación no conserva nada.)

cat << EOF > "$CONFIG_FILE"
# Configuración de The Field House.
# Podés editar estos valores en cualquier momento; se aplican en la
# próxima ejecución (no hace falta reinstalar ni reiniciar la sesión).
#
# La ubicación geográfica NO se configura acá: se detecta automáticamente
# por IP en cada ejecución con --reboot (ver obtener_ubicacion() en
# bin/change_wallpaper.sh). Se cachea en el estado de la app y esa ubicación
# se sigue usando si en algún momento no hay red disponible para redetectarla.

# Carpeta donde están las imágenes de fondo.
CARPETA_FONDOS="$DATOS_APP/fondos"

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
# darle tiempo a XFCE (y a la red) a estar listos.
ESPERA_INICIAL_SEGUNDOS=15

# Al iniciar sesión, si la red todavía no está lista (WiFi lentos, etc.),
# se aplica el fondo base de la franja y se reintenta la geolocalización y
# el clima cada ESPERA_REINTENTO_CLIMA segundos, hasta REINTENTOS_CLIMA_INICIAL
# veces.
REINTENTOS_CLIMA_INICIAL=3
ESPERA_REINTENTO_CLIMA=60

# Caché del clima: durante cuántos segundos se reutiliza la última consulta
# a la API meteorológica antes de volver a consultar (evita llamadas
# redundantes cuando el timer horario y el login disparan casi en el mismo
# momento).
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
info "3/3 - Configurando ejecución automática (systemd)..."

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
if "$DATOS_APP/bin/change_wallpaper.sh"; then
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
echo "  ✓ Ubicación     : detección automática por IP en cada arranque"
echo "  ✓ Horarios      : $MODO_HORARIOS"
echo
if [ "$HAY_INSTALACION_PREVIA" = "si" ]; then
    if [ "$SIN_BACKUP" = "si" ]; then
        echo "  ℹ Se eliminó la instalación anterior sin resguardo (--no-backup)."
    else
        echo "  ℹ Instalación anterior resguardada con el sufijo '$SUFIJO_BAK'"
        echo "    junto a cada carpeta original (por ejemplo:"
        echo "    ${DATOS_APP}${SUFIJO_BAK}). Podés recuperar de ahí tus imágenes"
        echo "    personalizadas si las tenías, o borrar esas copias cuando ya no"
        echo "    las necesites."
    fi
    echo
fi
echo "El fondo se va a actualizar solo cada hora, y también al iniciar sesión."
echo
echo "Comandos útiles:"
echo
echo "  Ver estado del timer:"
echo "    systemctl --user status field-house.timer"
echo
echo "  Ejecutar manualmente ahora:"
echo "    $DATOS_APP/bin/change_wallpaper.sh"
echo
echo "  Simular sin tocar nada (qué fondo se aplicaría):"
echo "    $DATOS_APP/bin/change_wallpaper.sh --dry-run"
echo
echo "  Ver la ayuda completa:"
echo "    $DATOS_APP/bin/change_wallpaper.sh --help"
echo
echo "  Ver el log:"
echo "    tail -f $STATE_DIR/log.txt"
echo
echo "  Editar configuración (franjas horarias, transición):"
echo "    nano $CONFIG_FILE"
echo
echo "  Desinstalar:"
echo "    ./uninstall.sh"
echo
echo "====================================================================="
echo
