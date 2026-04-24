# shellcheck shell=bash
#
# projectup — common library
#
# Logging, prompts, utilities, and user-config loader. Sourced by the
# dispatcher (bin/projectup) before delegating to a framework handler.

# ────────────────────────────────────────────────────────────────
#  Colores
# ────────────────────────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

# ────────────────────────────────────────────────────────────────
#  Usuario real (por si corren con sudo)
# ────────────────────────────────────────────────────────────────
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)
REAL_HOME="${REAL_HOME:-$HOME}"

# ────────────────────────────────────────────────────────────────
#  Logging
# ────────────────────────────────────────────────────────────────
_ts() { date '+%Y-%m-%d %H:%M:%S'; }

projectup_init_log() {
    # $1=project_root — setea LOG_FILE y lo trunca
    PROJECT_ROOT="$1"
    LOG_FILE="$PROJECT_ROOT/setup-error.log"
    : > "$LOG_FILE"
}

log_step()    { printf "\n${BOLD}${BLUE}━━━ %s ━━━${NC}\n" "$1"; }
log_info()    { printf "${CYAN}ℹ️   %s${NC}\n" "$1"; }
log_success() { printf "${GREEN}✅  %s${NC}\n" "$1"; }
log_warn()    { printf "${YELLOW}⚠️   %s${NC}\n" "$1"; [ -n "${LOG_FILE:-}" ] && echo "[$(_ts)] WARN: $1" >> "$LOG_FILE"; }
log_error()   { printf "${RED}❌  %s${NC}\n" "$1"; [ -n "${LOG_FILE:-}" ] && echo "[$(_ts)] ERROR: $1" >> "$LOG_FILE"; }
log_debug()   { printf "${DIM}    %s${NC}\n" "$1"; }

run_silent() {
    # Corre un comando y guarda salida en el log solo si falla.
    local desc="$1"; shift
    local output exit_code
    output=$("$@" 2>&1)
    exit_code=$?
    if [ $exit_code -ne 0 ] && [ -n "${LOG_FILE:-}" ]; then
        {
            echo "[$(_ts)] FAIL ($exit_code): $desc"
            echo "    CMD: $*"
            echo "$output" | sed 's/^/    /'
            echo ""
        } >> "$LOG_FILE"
    fi
    return $exit_code
}

# ────────────────────────────────────────────────────────────────
#  Utilidades
# ────────────────────────────────────────────────────────────────
have_cmd() { command -v "$1" >/dev/null 2>&1; }

env_get() {
    local key="$1" file="$2"
    [ -f "$file" ] || return 1
    local line
    line=$(grep -E "^${key}=" "$file" | tail -n1) || return 1
    [ -z "$line" ] && return 1
    local val="${line#*=}"
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"
    printf '%s' "$val"
}

env_set() {
    local key="$1" val="$2" file="$3"
    if grep -qE "^${key}=" "$file"; then
        local esc
        esc=$(printf '%s' "$val" | sed -e 's/[\/&|]/\\&/g')
        sed -i -E "s|^${key}=.*|${key}=${esc}|" "$file"
    else
        printf '%s=%s\n' "$key" "$val" >> "$file"
    fi
}

ask() {
    local prompt="$1" default="${2:-}" answer
    if [ -n "$default" ]; then
        read -r -p "$(printf "${MAGENTA}❓  %s [${default}]: ${NC}" "$prompt")" answer
        printf '%s' "${answer:-$default}"
    else
        read -r -p "$(printf "${MAGENTA}❓  %s: ${NC}" "$prompt")" answer
        printf '%s' "$answer"
    fi
}

ask_yn() {
    local prompt="$1" default="${2:-n}" answer
    local hint="[y/N]"; [ "$default" = "y" ] && hint="[Y/n]"
    read -r -p "$(printf "${MAGENTA}❓  %s %s: ${NC}" "$prompt" "$hint")" answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[YySs]$ ]]
}

# ────────────────────────────────────────────────────────────────
#  Package management (Debian/Ubuntu por ahora)
# ────────────────────────────────────────────────────────────────
ensure_pkg() {
    local pkg="$1"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        return 0
    fi
    log_info "Instalando $pkg..."
    run_silent "apt install $pkg" sudo apt-get install -y "$pkg"
}

ensure_ondrej_ppa() {
    if ! grep -rqE "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
        log_info "Agregando PPA ondrej/php..."
        run_silent "add-apt-repository ondrej/php" sudo add-apt-repository -y ppa:ondrej/php \
            || { log_error "No pude agregar el PPA ondrej/php."; return 1; }
        run_silent "apt update" sudo apt-get update -y \
            || { log_error "Falló apt update."; return 1; }
    fi
}

# ────────────────────────────────────────────────────────────────
#  Config loader
# ────────────────────────────────────────────────────────────────
projectup_load_config() {
    # Orden de precedencia:
    #   1. $PROJECTUP_CONFIG (env var) si está seteada
    #   2. ~/.config/projectup/projectup.conf
    #   3. Defaults inline acá abajo
    local config_file="${PROJECTUP_CONFIG:-$REAL_HOME/.config/projectup/projectup.conf}"
    if [ -f "$config_file" ]; then
        # shellcheck disable=SC1090
        . "$config_file"
    fi

    # ── Defaults (solo se aplican si la config no los definió) ──
    MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
    MYSQL_PORT="${MYSQL_PORT:-3306}"
    MYSQL_USER="${MYSQL_USER:-root}"
    MYSQL_PASS="${MYSQL_PASS:-}"

    PGSQL_HOST="${PGSQL_HOST:-127.0.0.1}"
    PGSQL_PORT="${PGSQL_PORT:-5432}"
    PGSQL_USER="${PGSQL_USER:-postgres}"
    PGSQL_PASS="${PGSQL_PASS:-postgres}"

    CERT_DIR="${CERT_DIR:-$REAL_HOME/certificados}"
    WEB_GROUP="${WEB_GROUP:-www-data}"
    NGINX_SITES_AVAILABLE="${NGINX_SITES_AVAILABLE:-/etc/nginx/sites-available}"
    NGINX_SITES_ENABLED="${NGINX_SITES_ENABLED:-/etc/nginx/sites-enabled}"

    # WIN_HOSTS_PATH: en WSL default es el hosts de Windows; en Linux puro vacío
    if [ -z "${WIN_HOSTS_PATH+x}" ]; then
        if [ -f /mnt/c/Windows/System32/drivers/etc/hosts ]; then
            WIN_HOSTS_PATH=/mnt/c/Windows/System32/drivers/etc/hosts
        else
            WIN_HOSTS_PATH=""
        fi
    fi

    export MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASS
    export PGSQL_HOST PGSQL_PORT PGSQL_USER PGSQL_PASS
    export CERT_DIR WEB_GROUP NGINX_SITES_AVAILABLE NGINX_SITES_ENABLED WIN_HOSTS_PATH
}

projectup_summary() {
    # Imprime el resumen final con contador de warnings/errores del log.
    if [ -n "${LOG_FILE:-}" ] && [ -s "$LOG_FILE" ]; then
        local warn_count err_count
        warn_count=$(grep -E "^\[.*\] WARN:" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ')
        err_count=$(grep -E "^\[.*\] (ERROR|FAIL|HOSTS_WRITE_FAIL):" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ')
        warn_count=${warn_count:-0}
        err_count=${err_count:-0}
        if [ "$err_count" -gt 0 ] || [ "$warn_count" -gt 0 ]; then
            printf "\n${YELLOW}⚠️   Hubo %d errores y %d warnings. Revisá: %s${NC}\n" \
                "$err_count" "$warn_count" "$LOG_FILE"
        fi
    elif [ -n "${LOG_FILE:-}" ]; then
        rm -f "$LOG_FILE"
    fi
}

trap 'printf "\n"; log_warn "Interrumpido por el usuario"; exit 130' INT
