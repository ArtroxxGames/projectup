# shellcheck shell=bash
#
# projectup — Laravel framework handler
#
# Entry point: laravel_setup
#
# Hace todo lo necesario para dejar un proyecto Laravel corriendo en local:
#   - Detecta PHP requerido y lo instala (con extensiones) si falta
#   - composer install (si corresponde)
#   - Node + npm/pnpm/yarn/bun install + build de assets (Vite)
#   - .env + base de datos (MySQL, PostgreSQL o SQLite)
#   - Certificados SSL con mkcert
#   - Nginx site + hosts de Windows (si es WSL)
#   - Permisos de storage/bootstrap
#   - Migraciones y seeders (opcionales)
#   - optimize:clear final
#
# Variables de config (vienen de projectup_load_config):
#   MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASS
#   PGSQL_HOST, PGSQL_PORT, PGSQL_USER, PGSQL_PASS
#   CERT_DIR, WEB_GROUP
#   NGINX_SITES_AVAILABLE, NGINX_SITES_ENABLED
#   WIN_HOSTS_PATH

# ════════════════════════════════════════════════════════════════════
#  Detección de PHP
# ════════════════════════════════════════════════════════════════════

_laravel_detect_min_php() {
    local ver=""
    if [ -f composer.json ]; then
        ver=$(grep -E '"php"[[:space:]]*:' composer.json | head -n1 \
            | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    fi
    printf '%s' "${ver:-8.3}"
}

_laravel_php_bin_version() {
    "$1" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null
}

_laravel_pick_best_php() {
    local min="$1" best_ver="" best_bin="" ver
    local candidates=(/usr/bin/php /usr/bin/php[0-9].[0-9] /usr/bin/php[0-9].[0-9][0-9] /usr/local/bin/php[0-9].[0-9])
    for bin in "${candidates[@]}"; do
        [ -x "$bin" ] || continue
        ver=$(_laravel_php_bin_version "$bin")
        [ -z "$ver" ] && continue
        if [ "$(printf '%s\n%s\n' "$min" "$ver" | sort -V | head -n1)" = "$min" ]; then
            if [ -z "$best_ver" ] || [ "$(printf '%s\n%s\n' "$best_ver" "$ver" | sort -V | tail -n1)" = "$ver" ]; then
                best_ver="$ver"
                best_bin="$bin"
            fi
        fi
    done
    [ -n "$best_ver" ] && printf '%s|%s' "$best_ver" "$best_bin"
}

# ════════════════════════════════════════════════════════════════════
#  Base de datos
# ════════════════════════════════════════════════════════════════════

_laravel_test_mysql() {
    local db="${1:-}"
    if [ -n "$db" ]; then
        MYSQL_PWD="$MYSQL_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "USE \`$db\`;" >/dev/null 2>/dev/null
    else
        MYSQL_PWD="$MYSQL_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SELECT 1;" >/dev/null 2>/dev/null
    fi
}

_laravel_test_pgsql() {
    local db="${1:-postgres}"
    PGPASSWORD="$PGSQL_PASS" psql -h "$PGSQL_HOST" -p "$PGSQL_PORT" -U "$PGSQL_USER" -d "$db" -c '\q' >/dev/null 2>/dev/null
}

_laravel_ensure_mysql_db() {
    local db="$1"
    if _laravel_test_mysql "$db"; then
        log_success "DB MySQL '$db' existe y es accesible"
        return 0
    fi
    log_info "Creando DB MySQL '$db'..."
    if MYSQL_PWD="$MYSQL_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" \
         -e "CREATE DATABASE IF NOT EXISTS \`$db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>>"$LOG_FILE"; then
        log_success "DB MySQL '$db' creada"
    else
        log_error "No pude crear la DB MySQL '$db'"
        return 1
    fi
}

_laravel_ensure_pgsql_db() {
    local db="$1"
    if _laravel_test_pgsql "$db"; then
        log_success "DB PostgreSQL '$db' existe y es accesible"
        return 0
    fi
    log_info "Creando DB PostgreSQL '$db'..."
    if PGPASSWORD="$PGSQL_PASS" psql -h "$PGSQL_HOST" -p "$PGSQL_PORT" -U "$PGSQL_USER" -d postgres \
         -c "CREATE DATABASE \"$db\";" >/dev/null 2>>"$LOG_FILE"; then
        log_success "DB PostgreSQL '$db' creada"
    else
        log_error "No pude crear la DB PostgreSQL '$db'"
        return 1
    fi
}

_laravel_ensure_sqlite_file() {
    local db_val="$1" db_path=""

    if [ "$db_val" = ":memory:" ]; then
        log_info "SQLite in-memory — no hay archivo que crear"
        ensure_pkg "php${PHP_VER}-sqlite3" || log_warn "No pude instalar php${PHP_VER}-sqlite3"
        return 0
    fi

    if [ -f "$db_val" ]; then
        db_path=$(realpath "$db_val")
    elif [ -f "$PROJECT_ROOT/$db_val" ]; then
        db_path="$PROJECT_ROOT/$db_val"
    else
        case "$db_val" in
            /*)              db_path="$db_val" ;;
            */*)             db_path="$PROJECT_ROOT/$db_val" ;;
            *.sqlite|*.db)   db_path="$PROJECT_ROOT/database/$db_val" ;;
            *)               db_path="$PROJECT_ROOT/database/${db_val}.sqlite" ;;
        esac
    fi

    mkdir -p "$(dirname "$db_path")"
    if [ ! -f "$db_path" ]; then
        if touch "$db_path" 2>>"$LOG_FILE"; then
            log_success "SQLite creado: $db_path"
        else
            log_error "No pude crear el archivo sqlite en $db_path"
            return 1
        fi
    else
        log_success "SQLite existe: $db_path"
    fi
    if [ "$db_val" != "$db_path" ]; then
        env_set "DB_DATABASE" "$db_path" "$ENV_FILE"
        log_info "DB_DATABASE actualizado a path absoluto en .env"
    fi
    ensure_pkg "php${PHP_VER}-sqlite3" || log_warn "No pude instalar php${PHP_VER}-sqlite3"
}

_laravel_configure_env() {
    local driver="$1" db="$2" file="$3"
    env_set "DB_CONNECTION" "$driver" "$file"
    env_set "DB_DATABASE"   "$db"     "$file"
    if [ "$driver" = "mysql" ]; then
        env_set "DB_HOST"     "$MYSQL_HOST" "$file"
        env_set "DB_PORT"     "$MYSQL_PORT" "$file"
        env_set "DB_USERNAME" "$MYSQL_USER" "$file"
        env_set "DB_PASSWORD" "$MYSQL_PASS" "$file"
        ensure_pkg "php${PHP_VER}-mysql" || log_warn "No pude instalar php${PHP_VER}-mysql"
    else
        env_set "DB_HOST"     "$PGSQL_HOST" "$file"
        env_set "DB_PORT"     "$PGSQL_PORT" "$file"
        env_set "DB_USERNAME" "$PGSQL_USER" "$file"
        env_set "DB_PASSWORD" "$PGSQL_PASS" "$file"
        ensure_pkg "php${PHP_VER}-pgsql" || log_warn "No pude instalar php${PHP_VER}-pgsql"
    fi
}

# ════════════════════════════════════════════════════════════════════
#  Composer
# ════════════════════════════════════════════════════════════════════

_laravel_run_composer_install() {
    if [ -z "${COMPOSER_BIN:-}" ]; then
        log_error "Composer no disponible, no puedo instalar dependencias"
        return 1
    fi
    log_info "Instalando dependencias de Composer (puede tardar)..."
    if "$PHP_BIN" "$COMPOSER_BIN" install --no-interaction --prefer-dist 2>>"$LOG_FILE"; then
        log_success "Dependencias instaladas"
    else
        log_error "Falló composer install. Revisá $LOG_FILE"
        return 1
    fi
}

# ════════════════════════════════════════════════════════════════════
#  Entry point
# ════════════════════════════════════════════════════════════════════

laravel_setup() {
    # ── Pre-checks ──
    log_step "Verificando proyecto Laravel"
    if [ ! -f "composer.json" ] || [ ! -f "artisan" ]; then
        log_error "Esto no parece un proyecto Laravel (falta composer.json o artisan)."
        return 1
    fi

    projectup_init_log "$PWD"
    PROJECT_ROOT="$PWD"
    local project_name
    project_name=$(basename "$PROJECT_ROOT")

    log_success "Proyecto detectado: $project_name"
    log_debug "Ruta: $PROJECT_ROOT"
    log_debug "Log de errores: $LOG_FILE"

    if [ -n "${SUDO_USER:-}" ]; then
        log_warn "Estás corriendo con sudo (usuario real: $REAL_USER)."
        log_warn "No hace falta — projectup pide sudo solo donde lo necesita."
    fi

    # ── PHP ──
    log_step "Detectando versión de PHP requerida"
    local php_min
    php_min=$(_laravel_detect_min_php)
    log_info "PHP mínimo requerido por el proyecto: $php_min"

    local picked
    picked=$(_laravel_pick_best_php "$php_min")
    if [ -n "$picked" ]; then
        PHP_VER="${picked%|*}"
        PHP_BIN="${picked#*|}"
        log_success "Usando PHP $PHP_VER (en $PHP_BIN, satisface ≥ $php_min)"
    else
        PHP_VER="$php_min"
        PHP_BIN="php${PHP_VER}"
        log_warn "No hay ninguna PHP ≥ $php_min instalada. Voy a instalar PHP $PHP_VER."
        ensure_pkg software-properties-common || true
        ensure_ondrej_ppa || { log_error "No puedo continuar sin el PPA."; return 1; }
        ensure_pkg "php${PHP_VER}-cli" || { log_error "No pude instalar php${PHP_VER}-cli"; return 1; }
    fi

    if ! have_cmd "$PHP_BIN" && ! [ -x "$PHP_BIN" ]; then
        log_error "PHP $PHP_VER no está disponible después de intentar instalarlo."
        return 1
    fi
    log_success "PHP $PHP_VER: $("$PHP_BIN" -v 2>/dev/null | head -n1)"

    log_info "Verificando extensiones de PHP..."
    local required_exts=(fpm mbstring xml curl zip bcmath gd intl sqlite3 tokenizer)
    local missing_exts=()
    for ext in "${required_exts[@]}"; do
        if [ "$ext" = "fpm" ]; then
            dpkg -s "php${PHP_VER}-fpm" >/dev/null 2>&1 || missing_exts+=("$ext")
        else
            "$PHP_BIN" -m 2>/dev/null | grep -iq "^${ext}$" || missing_exts+=("$ext")
        fi
    done
    if [ ${#missing_exts[@]} -gt 0 ]; then
        log_warn "Faltan extensiones: ${missing_exts[*]}"
        for ext in "${missing_exts[@]}"; do
            ensure_pkg "php${PHP_VER}-${ext}" || log_warn "No pude instalar php${PHP_VER}-${ext}"
        done
    else
        log_success "Todas las extensiones base están presentes"
    fi

    if ! systemctl is-active --quiet "php${PHP_VER}-fpm" 2>/dev/null \
       && ! service "php${PHP_VER}-fpm" status >/dev/null 2>&1; then
        run_silent "start php-fpm" sudo service "php${PHP_VER}-fpm" start \
            || log_warn "No pude iniciar php${PHP_VER}-fpm"
    fi

    # ── Composer ──
    log_step "Composer y dependencias PHP"
    if ! have_cmd composer; then
        log_warn "Composer no está instalado. Instalando..."
        local tmp_composer
        tmp_composer=$(mktemp)
        if curl -sS https://getcomposer.org/installer -o "$tmp_composer" 2>>"$LOG_FILE"; then
            sudo "$PHP_BIN" "$tmp_composer" --install-dir=/usr/local/bin --filename=composer >>"$LOG_FILE" 2>&1 \
                && log_success "Composer instalado" \
                || log_error "Falló la instalación de Composer"
            rm -f "$tmp_composer"
        else
            log_error "No pude descargar el instalador de Composer"
        fi
    fi
    COMPOSER_BIN=$(command -v composer || echo "")

    if [ -d "vendor" ]; then
        if "$PHP_BIN" -r "require '$PROJECT_ROOT/vendor/autoload.php';" >/dev/null 2>>"$LOG_FILE"; then
            log_info "vendor/ existe y es compatible con PHP $PHP_VER — salteando composer install"
        else
            log_warn "vendor/ existe pero no carga con PHP $PHP_VER (compilado con otra versión)"
            if ask_yn "¿Reinstalo las dependencias con composer install?" "y"; then
                _laravel_run_composer_install || true
            else
                log_warn "Continuando con vendor/ incompatible — artisan probablemente falle"
            fi
        fi
    else
        _laravel_run_composer_install || true
    fi

    # ── Dominio ──
    log_step "Dominio del proyecto"
    local subdomain
    subdomain=$(ask "Nombre para la URL (se le agrega .test)" "$project_name")
    subdomain=$(echo "$subdomain" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    local domain="${subdomain}.test"
    log_success "Dominio: https://$domain"

    # ── .env + DB ──
    log_step "Base de datos y .env"
    have_cmd mysql || ensure_pkg mysql-client || log_warn "No se pudo instalar mysql-client"
    have_cmd psql  || ensure_pkg postgresql-client || log_warn "No se pudo instalar postgresql-client"

    ENV_FILE="$PROJECT_ROOT/.env"
    local db_driver="" db_name=""

    if [ -f "$ENV_FILE" ]; then
        log_info ".env existente detectado — validando..."
        db_driver=$(env_get DB_CONNECTION "$ENV_FILE" || echo "")
        db_name=$(env_get DB_DATABASE "$ENV_FILE" || echo "")
        local cur_host cur_port cur_user cur_pass
        cur_host=$(env_get DB_HOST "$ENV_FILE" || echo "")
        cur_port=$(env_get DB_PORT "$ENV_FILE" || echo "")
        cur_user=$(env_get DB_USERNAME "$ENV_FILE" || echo "")
        cur_pass=$(env_get DB_PASSWORD "$ENV_FILE" || echo "")
        log_debug "DB_CONNECTION=$db_driver DB_DATABASE=$db_name"
        [ "$db_driver" = "postgresql" ] && db_driver="pgsql"

        if [ -z "$db_driver" ] || [ -z "$db_name" ]; then
            log_warn ".env sin DB_CONNECTION o DB_DATABASE. Lo reconfiguro."
            db_driver=""
        else
            case "$db_driver" in
                mysql)
                    local mismatch=0
                    [ "$cur_host" = "$MYSQL_HOST" ] || mismatch=1
                    [ "$cur_port" = "$MYSQL_PORT" ] || mismatch=1
                    [ "$cur_user" = "$MYSQL_USER" ] || mismatch=1
                    [ "$cur_pass" = "$MYSQL_PASS" ] || mismatch=1
                    if [ $mismatch -eq 1 ]; then
                        log_warn "Credenciales MySQL del .env no coinciden con tu config (esperado: $MYSQL_USER@$MYSQL_HOST:$MYSQL_PORT)"
                        if ask_yn "¿Corregirlas automáticamente?" "y"; then
                            _laravel_configure_env "mysql" "$db_name" "$ENV_FILE"
                            log_success "Credenciales MySQL corregidas en .env"
                        fi
                    fi
                    ensure_pkg "php${PHP_VER}-mysql" || log_warn "No pude instalar php${PHP_VER}-mysql"
                    if ! _laravel_test_mysql; then
                        log_error "No puedo conectar a MySQL en $MYSQL_HOST:$MYSQL_PORT como $MYSQL_USER"
                    else
                        _laravel_ensure_mysql_db "$db_name" || true
                    fi
                    ;;
                pgsql)
                    local mismatch=0
                    [ "$cur_host" = "$PGSQL_HOST" ] || mismatch=1
                    [ "$cur_port" = "$PGSQL_PORT" ] || mismatch=1
                    [ "$cur_user" = "$PGSQL_USER" ] || mismatch=1
                    [ "$cur_pass" = "$PGSQL_PASS" ] || mismatch=1
                    if [ $mismatch -eq 1 ]; then
                        log_warn "Credenciales PostgreSQL del .env no coinciden con tu config (esperado: $PGSQL_USER@$PGSQL_HOST:$PGSQL_PORT)"
                        if ask_yn "¿Corregirlas automáticamente?" "y"; then
                            _laravel_configure_env "pgsql" "$db_name" "$ENV_FILE"
                            log_success "Credenciales PostgreSQL corregidas en .env"
                        fi
                    fi
                    ensure_pkg "php${PHP_VER}-pgsql" || log_warn "No pude instalar php${PHP_VER}-pgsql"
                    if ! _laravel_test_pgsql postgres; then
                        log_error "No puedo conectar a PostgreSQL en $PGSQL_HOST:$PGSQL_PORT como $PGSQL_USER"
                    else
                        _laravel_ensure_pgsql_db "$db_name" || true
                    fi
                    ;;
                sqlite)
                    _laravel_ensure_sqlite_file "$db_name" || true
                    ;;
                *)
                    log_warn "DB_CONNECTION='$db_driver' no reconocido. Reconfigurando."
                    db_driver=""
                    ;;
            esac
        fi
    fi

    if [ ! -f "$ENV_FILE" ] || [ -z "$db_driver" ]; then
        if [ ! -f "$ENV_FILE" ]; then
            if [ -f "$PROJECT_ROOT/.env.example" ]; then
                cp "$PROJECT_ROOT/.env.example" "$ENV_FILE"
                log_success ".env creado a partir de .env.example"
            else
                : > "$ENV_FILE"
                log_warn "No había .env.example — creé un .env vacío"
            fi
        fi

        echo ""
        printf "${BOLD}Motor de base de datos:${NC}\n"
        printf "  1) MySQL       (%s:%s, %s)\n" "$MYSQL_HOST" "$MYSQL_PORT" "$MYSQL_USER"
        printf "  2) PostgreSQL  (%s:%s, %s)\n" "$PGSQL_HOST" "$PGSQL_PORT" "$PGSQL_USER"
        printf "  3) SQLite      (archivo local)\n"
        local choice
        choice=$(ask "Elegí opción" "1")
        case "$choice" in
            2|pgsql|postgres|postgresql) db_driver="pgsql" ;;
            3|sqlite)                    db_driver="sqlite" ;;
            *)                           db_driver="mysql" ;;
        esac

        db_name=$(ask "Nombre de la base de datos" "$project_name")

        if [ "$db_driver" = "sqlite" ]; then
            env_set "DB_CONNECTION" "sqlite" "$ENV_FILE"
            env_set "DB_DATABASE"   "$db_name" "$ENV_FILE"
            _laravel_ensure_sqlite_file "$db_name"
        else
            _laravel_configure_env "$db_driver" "$db_name" "$ENV_FILE"
        fi
        env_set "APP_URL" "https://$domain" "$ENV_FILE"

        case "$db_driver" in
            mysql)
                _laravel_test_mysql && _laravel_ensure_mysql_db "$db_name" \
                    || log_error "No puedo conectar a MySQL en $MYSQL_HOST:$MYSQL_PORT"
                ;;
            pgsql)
                _laravel_test_pgsql postgres && _laravel_ensure_pgsql_db "$db_name" \
                    || log_error "No puedo conectar a PostgreSQL en $PGSQL_HOST:$PGSQL_PORT"
                ;;
        esac
    fi

    env_set "APP_URL" "https://$domain" "$ENV_FILE"
    if [ -z "$(env_get APP_KEY "$ENV_FILE" 2>/dev/null || echo "")" ]; then
        log_info "Generando APP_KEY..."
        "$PHP_BIN" artisan key:generate --force >>"$LOG_FILE" 2>&1 \
            && log_success "APP_KEY generado" \
            || log_error "Falló key:generate"
    fi

    # ── Node.js ──
    if [ -f "package.json" ]; then
        log_step "Node.js y dependencias de frontend"

        local node_ver=""
        if [ -f ".nvmrc" ]; then
            node_ver=$(tr -d 'v \r\n' < .nvmrc)
            log_info "Versión de Node (.nvmrc): $node_ver"
        else
            node_ver=$(grep -A3 '"engines"[[:space:]]*:' package.json \
                | grep -E '"node"[[:space:]]*:' | head -n1 \
                | grep -oE '[0-9]+(\.[0-9]+){0,2}' | head -n1)
            [ -n "$node_ver" ] && log_info "Versión de Node (engines.node): $node_ver"
        fi
        [ -z "$node_ver" ] && log_info "Sin versión específica — uso el default de nvm"

        export NVM_DIR="${NVM_DIR:-$REAL_HOME/.nvm}"
        local nvm_available=0
        if [ -s "$NVM_DIR/nvm.sh" ]; then
            # shellcheck disable=SC1091
            \. "$NVM_DIR/nvm.sh" 2>>"$LOG_FILE"
            type nvm >/dev/null 2>&1 && nvm_available=1
        fi

        if [ $nvm_available -eq 0 ]; then
            log_warn "nvm no está disponible en $NVM_DIR. Salteando versionado de Node."
            have_cmd node || log_error "Tampoco hay 'node' en PATH — no puedo instalar dependencias de frontend."
        else
            if [ -n "$node_ver" ]; then
                if ! nvm ls "$node_ver" >/dev/null 2>&1; then
                    log_info "Instalando Node $node_ver con nvm (puede tardar)..."
                    nvm install "$node_ver" >>"$LOG_FILE" 2>&1 || log_warn "Falló nvm install $node_ver"
                fi
                nvm use "$node_ver" >/dev/null 2>>"$LOG_FILE" || log_warn "Falló nvm use $node_ver"
            else
                nvm use default >/dev/null 2>&1 || nvm use node >/dev/null 2>&1 || true
            fi
        fi

        have_cmd node && log_success "Node: $(node --version) (npm $(npm --version 2>/dev/null || echo '?'))"

        local pkg_mgr="npm"
        if [ -f "pnpm-lock.yaml" ]; then pkg_mgr="pnpm"
        elif [ -f "yarn.lock" ]; then pkg_mgr="yarn"
        elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then pkg_mgr="bun"
        fi
        log_info "Package manager detectado: $pkg_mgr"

        if ! have_cmd "$pkg_mgr"; then
            case "$pkg_mgr" in
                pnpm|yarn)
                    log_info "Instalando $pkg_mgr vía corepack..."
                    corepack enable >>"$LOG_FILE" 2>&1 \
                        && corepack prepare "${pkg_mgr}@latest" --activate >>"$LOG_FILE" 2>&1 \
                        || log_warn "Falló corepack"
                    have_cmd "$pkg_mgr" || npm install -g "$pkg_mgr" >>"$LOG_FILE" 2>&1 \
                        || log_error "No pude instalar $pkg_mgr"
                    ;;
                bun)
                    log_info "Instalando bun vía npm..."
                    npm install -g bun >>"$LOG_FILE" 2>&1 || log_error "No pude instalar bun"
                    ;;
            esac
        fi

        if [ -d "node_modules" ]; then
            log_info "node_modules/ ya existe — salteando install"
        else
            if have_cmd "$pkg_mgr"; then
                log_info "Instalando dependencias con $pkg_mgr install (puede tardar)..."
                "$pkg_mgr" install 2>>"$LOG_FILE" \
                    && log_success "Dependencias de Node instaladas" \
                    || log_error "Falló $pkg_mgr install — revisá $LOG_FILE"
            fi
        fi

        if grep -qE '"build"[[:space:]]*:' package.json 2>/dev/null && have_cmd "$pkg_mgr"; then
            if ask_yn "¿Corro '$pkg_mgr run build' para compilar los assets?" "y"; then
                log_info "Compilando assets (puede tardar)..."
                "$pkg_mgr" run build 2>>"$LOG_FILE" \
                    && log_success "Assets compilados (public/build/manifest.json listo)" \
                    || log_error "Falló $pkg_mgr run build — revisá $LOG_FILE"
            else
                log_warn "Salteando build. Si Laravel usa Vite, abrir la web va a tirar ViteManifestNotFoundException."
            fi
        fi
    else
        log_debug "Sin package.json — proyecto sin frontend Node"
    fi

    # ── Certificados SSL ──
    log_step "Certificados SSL"
    if ! have_cmd mkcert; then
        log_warn "mkcert no está instalado. Instalando..."
        ensure_pkg libnss3-tools || true
        if ensure_pkg mkcert; then
            mkcert -install >>"$LOG_FILE" 2>&1 || log_warn "Falló mkcert -install"
        else
            log_error "No pude instalar mkcert."
        fi
    fi
    if have_cmd mkcert; then
        mkdir -p "$CERT_DIR"
        if [ -f "$CERT_DIR/$domain.pem" ] && [ -f "$CERT_DIR/$domain-key.pem" ]; then
            log_info "Certificados ya existen para $domain"
        else
            log_info "Generando certificados para $domain..."
            (cd "$CERT_DIR" && mkcert "$domain" >>"$LOG_FILE" 2>&1) \
                && log_success "Certificados generados en $CERT_DIR" \
                || log_error "Falló la generación de certificados"
        fi
    fi

    # ── Nginx ──
    log_step "Configurando Nginx"
    have_cmd nginx || ensure_pkg nginx || log_error "No pude instalar nginx"
    local nginx_conf="$NGINX_SITES_AVAILABLE/$project_name"

    sudo tee "$nginx_conf" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl;
    listen [::]:443 ssl;

    ssl_certificate     $CERT_DIR/$domain.pem;
    ssl_certificate_key $CERT_DIR/$domain-key.pem;

    server_name $domain;
    root $PROJECT_ROOT/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_log  /var/log/nginx/${project_name}_error.log;
    access_log /var/log/nginx/${project_name}_access.log;

    error_page 404 /index.php;

    location ~ \.php\$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VER}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

    sudo rm -f "$NGINX_SITES_ENABLED/$project_name"
    sudo ln -s "$nginx_conf" "$NGINX_SITES_ENABLED/$project_name"

    if run_silent "nginx -t" sudo nginx -t; then
        run_silent "nginx reload" sudo service nginx reload \
            && log_success "Nginx recargado con el nuevo site" \
            || { run_silent "nginx restart" sudo service nginx restart \
                && log_success "Nginx reiniciado" \
                || log_error "Falló el reinicio de Nginx"; }
    else
        log_error "Config de Nginx inválida — revisá $LOG_FILE"
    fi

    # ── Hosts de Windows (solo si WIN_HOSTS_PATH está seteado) ──
    if [ -n "$WIN_HOSTS_PATH" ]; then
        log_step "Hosts (Windows via WSL)"
        local host_line="127.0.0.1 $domain"
        if [ ! -f "$WIN_HOSTS_PATH" ]; then
            log_warn "No encuentro $WIN_HOSTS_PATH — agregá manualmente: $host_line"
        elif grep -qE "^\s*127\.0\.0\.1\s+${domain}(\s|$)" "$WIN_HOSTS_PATH" 2>/dev/null; then
            log_info "Entrada '$domain' ya existe en el hosts"
        else
            if printf '\n%s\n' "$host_line" >> "$WIN_HOSTS_PATH" 2>>"$LOG_FILE"; then
                log_success "Agregado '$host_line' al hosts"
            else
                log_warn "No pude escribir en $WIN_HOSTS_PATH (necesitás correr WSL como admin de Windows, o editá manualmente)."
                log_warn "Línea a agregar: $host_line"
                echo "[$(_ts)] HOSTS_WRITE_FAIL: $host_line en $WIN_HOSTS_PATH" >> "$LOG_FILE"
            fi
        fi
    fi

    # ── Permisos ──
    log_step "Permisos de storage y bootstrap/cache"
    sudo chown -R "$REAL_USER":"$WEB_GROUP" storage bootstrap/cache 2>>"$LOG_FILE" \
        || log_warn "No pude cambiar dueño de storage/bootstrap"
    sudo chmod -R ug+rwX storage bootstrap/cache 2>>"$LOG_FILE" \
        || log_warn "No pude cambiar permisos de storage/bootstrap"
    sudo find storage bootstrap/cache -type d -exec chmod g+s {} \; 2>/dev/null || true
    log_success "Permisos OK (owner=$REAL_USER, group=$WEB_GROUP)"

    log_info "Limpiando cachés livianos (config/route/view/event)..."
    for cmd in config:clear route:clear view:clear event:clear; do
        "$PHP_BIN" artisan $cmd >>"$LOG_FILE" 2>&1 || log_warn "Falló artisan $cmd"
    done

    # ── Migraciones ──
    log_step "Migraciones"
    if ask_yn "¿Corro las migraciones? (artisan migrate)" "n"; then
        log_info "Corriendo php artisan migrate..."
        "$PHP_BIN" artisan migrate --force 2>&1 | tee -a "$LOG_FILE" \
            && log_success "Migraciones completadas" \
            || log_error "Falló artisan migrate — revisá $LOG_FILE"
    else
        log_info "Salteando migraciones (podés correrlas después: $PHP_BIN artisan migrate)"
    fi

    log_step "Seeders"
    if ask_yn "¿Corro los seeders? (artisan db:seed)" "n"; then
        log_info "Corriendo php artisan db:seed..."
        "$PHP_BIN" artisan db:seed --force 2>&1 | tee -a "$LOG_FILE" \
            && log_success "Seeders completados" \
            || log_warn "Falló db:seed (causa típica: seeders no idempotentes con ::create() en vez de ::firstOrCreate())."
    else
        log_info "Salteando seeders"
    fi

    # ── optimize:clear final ──
    log_step "Optimización final"
    log_info "Corriendo optimize:clear..."
    "$PHP_BIN" artisan optimize:clear >>"$LOG_FILE" 2>&1 \
        && log_success "optimize:clear OK" \
        || log_warn "Falló optimize:clear (si CACHE_STORE=database, necesita la tabla 'cache')"

    # ── Resumen ──
    log_step "Listo"
    printf "${GREEN}${BOLD}✨  Proyecto configurado${NC}\n"
    printf "    ${BOLD}URL:${NC}      https://%s\n" "$domain"
    printf "    ${BOLD}PHP:${NC}      %s\n" "$PHP_VER"
    printf "    ${BOLD}DB:${NC}       %s → %s\n" "$db_driver" "$db_name"
    printf "    ${BOLD}Nginx:${NC}    %s\n" "$nginx_conf"
    printf "    ${BOLD}Certs:${NC}    %s/%s.pem\n" "$CERT_DIR" "$domain"

    projectup_summary
    return 0
}
