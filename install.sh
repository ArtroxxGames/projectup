#!/bin/bash
#
# projectup — Installer
#
# Instalación:
#   curl -fsSL https://raw.githubusercontent.com/ArtroxxGames/projectup/main/install.sh | bash
#
# Qué hace:
#   1. Verifica prerequisitos (bash, git, sudo, curl)
#   2. Clona el repo a /usr/local/share/projectup
#   3. Crea symlink /usr/local/bin/projectup → share/projectup/bin/projectup
#   4. Crea $HOME/.config/projectup/projectup.conf desde el template (si no existe)
#
# Uninstall: curl -fsSL .../uninstall.sh | bash

set -euo pipefail

REPO_URL="https://github.com/ArtroxxGames/projectup.git"
BRANCH="${PROJECTUP_BRANCH:-main}"
INSTALL_DIR="/usr/local/share/projectup"
BIN_LINK="/usr/local/bin/projectup"
USER_CONFIG_DIR="$HOME/.config/projectup"
USER_CONFIG="$USER_CONFIG_DIR/projectup.conf"

# Colores (sin depender de common.sh — el repo todavía no está clonado)
C_RED=$'\033[0;31m'
C_GREEN=$'\033[0;32m'
C_YELLOW=$'\033[1;33m'
C_CYAN=$'\033[0;36m'
C_BOLD=$'\033[1m'
C_NC=$'\033[0m'

info()    { printf "${C_CYAN}ℹ️   %s${C_NC}\n" "$1"; }
success() { printf "${C_GREEN}✅  %s${C_NC}\n" "$1"; }
warn()    { printf "${C_YELLOW}⚠️   %s${C_NC}\n" "$1"; }
die()     { printf "${C_RED}❌  %s${C_NC}\n" "$1" >&2; exit 1; }

# ────────────────────────────────────────────────────────────────
#  1. Sanity checks
# ────────────────────────────────────────────────────────────────
printf "${C_BOLD}projectup installer${C_NC}\n"
printf "───────────────────────\n\n"

case "$(uname -s)" in
    Linux) ;;
    Darwin) die "macOS todavía no está soportado. Ver ROADMAP.md." ;;
    *)      die "OS no soportado: $(uname -s)" ;;
esac

for cmd in bash git sudo curl; do
    command -v "$cmd" >/dev/null 2>&1 || die "Falta '$cmd' en el sistema. Instalalo primero."
done

# ────────────────────────────────────────────────────────────────
#  2. Clonar o actualizar el repo
# ────────────────────────────────────────────────────────────────
if [ -d "$INSTALL_DIR/.git" ]; then
    info "projectup ya está instalado en $INSTALL_DIR — actualizando..."
    sudo git -C "$INSTALL_DIR" fetch --quiet origin "$BRANCH"
    sudo git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH" >/dev/null
    success "Actualizado a la última versión de '$BRANCH'"
else
    info "Clonando projectup en $INSTALL_DIR (requiere sudo)..."
    sudo mkdir -p "$(dirname "$INSTALL_DIR")"
    sudo git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
    success "Repo clonado"
fi

sudo chmod +x "$INSTALL_DIR/bin/projectup"

# ────────────────────────────────────────────────────────────────
#  3. Symlink en PATH
# ────────────────────────────────────────────────────────────────
if [ -L "$BIN_LINK" ] || [ -e "$BIN_LINK" ]; then
    sudo rm -f "$BIN_LINK"
fi
sudo ln -s "$INSTALL_DIR/bin/projectup" "$BIN_LINK"
success "Symlink creado: $BIN_LINK → $INSTALL_DIR/bin/projectup"

# ────────────────────────────────────────────────────────────────
#  4. Config de usuario
# ────────────────────────────────────────────────────────────────
mkdir -p "$USER_CONFIG_DIR"
if [ -f "$USER_CONFIG" ]; then
    info "Tu config existente se mantiene: $USER_CONFIG"
else
    cp "$INSTALL_DIR/config/projectup.conf.example" "$USER_CONFIG"
    success "Config creada con defaults: $USER_CONFIG"
fi

# ────────────────────────────────────────────────────────────────
#  5. Listo
# ────────────────────────────────────────────────────────────────
VER=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "?")
printf "\n${C_GREEN}${C_BOLD}✨  projectup %s instalado${C_NC}\n\n" "$VER"
printf "${C_BOLD}Próximos pasos:${C_NC}\n"
printf "  1. Revisá tu config:   ${C_CYAN}%s${C_NC}\n" "$USER_CONFIG"
printf "  2. Abrí un proyecto:   ${C_CYAN}cd ~/projects/mi-laravel${C_NC}\n"
printf "  3. Corré projectup:    ${C_CYAN}projectup${C_NC}  (auto-detecta el framework)\n"
printf "     o explícito:        ${C_CYAN}projectup laravel${C_NC}\n\n"
printf "Docs: ${C_CYAN}https://github.com/ArtroxxGames/projectup${C_NC}\n"
