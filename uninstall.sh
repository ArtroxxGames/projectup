#!/bin/bash
#
# projectup — Uninstaller
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/ArtroxxGames/projectup/main/uninstall.sh | bash
#
# Por default preserva tu config en ~/.config/projectup/. Para borrarla también:
#   curl -fsSL .../uninstall.sh | bash -s -- --purge

set -euo pipefail

INSTALL_DIR="/usr/local/share/projectup"
BIN_LINK="/usr/local/bin/projectup"
USER_CONFIG_DIR="$HOME/.config/projectup"

C_GREEN=$'\033[0;32m'
C_YELLOW=$'\033[1;33m'
C_CYAN=$'\033[0;36m'
C_NC=$'\033[0m'

info()    { printf "${C_CYAN}ℹ️   %s${C_NC}\n" "$1"; }
success() { printf "${C_GREEN}✅  %s${C_NC}\n" "$1"; }
warn()    { printf "${C_YELLOW}⚠️   %s${C_NC}\n" "$1"; }

PURGE=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
    esac
done

if [ -L "$BIN_LINK" ] || [ -e "$BIN_LINK" ]; then
    info "Removiendo symlink $BIN_LINK..."
    sudo rm -f "$BIN_LINK"
fi

if [ -d "$INSTALL_DIR" ]; then
    info "Removiendo $INSTALL_DIR..."
    sudo rm -rf "$INSTALL_DIR"
fi

if [ $PURGE -eq 1 ] && [ -d "$USER_CONFIG_DIR" ]; then
    info "Removiendo config de usuario $USER_CONFIG_DIR..."
    rm -rf "$USER_CONFIG_DIR"
else
    [ -d "$USER_CONFIG_DIR" ] && warn "Tu config en $USER_CONFIG_DIR se preserva. Usá --purge para removerla."
fi

success "projectup desinstalado."
