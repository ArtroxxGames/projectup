# shellcheck shell=bash
#
# projectup — framework detection
#
# Imprime el nombre del framework detectado en el cwd, o nada si no reconoce.
# En v1 solo Laravel; a medida que agreguemos soporte, extendemos acá.

detect_framework() {
    # Laravel: composer.json + artisan
    if [ -f composer.json ] && [ -f artisan ]; then
        printf 'laravel'
        return 0
    fi

    # Futuros (placeholder, devuelven vacío hoy):
    # Symfony: composer.json + bin/console + config/bundles.php
    # Next.js: package.json + next.config.{js,mjs,ts}
    # Nuxt:    package.json + nuxt.config.{js,ts}
    # Rails:   Gemfile + config/application.rb
    # Django:  manage.py + settings.py en algún lado

    return 1
}
