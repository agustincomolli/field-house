#!/bin/bash
# ============================================================================
# The Field House — Live Wallpaper
# uninstall.sh — desinstalador
#
# Detiene y quita los servicios de systemd, y borra los archivos instalados
# por install.sh. Pregunta antes de borrar la configuración y los logs, por
# si el usuario quiere conservarlos para una reinstalación futura.
# ============================================================================

set -Eeuo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}!${NC} $1"; }

DATOS_APP="${XDG_DATA_HOME:-$HOME/.local/share}/field-house"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/field-house"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/field-house"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo
echo "====================================================================="
echo "       THE FIELD HOUSE — DESINSTALADOR"
echo "====================================================================="
echo
read -rp "¿Confirmás que querés desinstalar The Field House? [s/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^([sS]|[yY])$ ]]; then
    echo "Cancelado."
    exit 0
fi

echo
info "Deteniendo y deshabilitando servicios de systemd..."

systemctl --user disable --now field-house.timer 2>/dev/null || true
systemctl --user disable field-house-login.service 2>/dev/null || true

rm -f "$SYSTEMD_USER_DIR/field-house.service"
rm -f "$SYSTEMD_USER_DIR/field-house.timer"
rm -f "$SYSTEMD_USER_DIR/field-house-login.service"

systemctl --user daemon-reload

success "Servicios de systemd removidos."

info "Eliminando programa e imágenes..."
rm -rf "$DATOS_APP"
success "Borrado: $DATOS_APP"

echo
read -rp "¿Borrar también la configuración y los logs ($CONFIG_DIR y $STATE_DIR)? [s/N]: " CONFIRM_CONFIG
if [[ "$CONFIRM_CONFIG" =~ ^([sS]|[yY])$ ]]; then
    rm -rf "$CONFIG_DIR"
    rm -rf "$STATE_DIR"
    success "Configuración y logs borrados."
else
    warning "Se conservaron $CONFIG_DIR y $STATE_DIR. Si reinstalás más adelante, tu ciudad y franjas horarias van a seguir ahí."
fi

echo
echo "====================================================================="
echo -e "${GREEN}         THE FIELD HOUSE — DESINSTALACIÓN COMPLETADA${NC}"
echo "====================================================================="
echo
