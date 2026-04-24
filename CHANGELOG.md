# Changelog

Todas las entradas relevantes de cada versión. Formato basado en
[Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y versionado
siguiendo [SemVer](https://semver.org/lang/es/).

## [Unreleased]

## [0.1.0] - 2026-04-24

### Added

- Primera release pública.
- Dispatcher `projectup` con subcomandos (`laravel`) y auto-detección por cwd.
- Handler para **Laravel**:
  - Detección automática de versión mínima de PHP desde `composer.json`
    (respeta `^` y `>=` como "mínimo, no exacto") y elige el PHP instalado
    más alto que satisfaga la restricción.
  - Instalación automática de PHP (vía PPA `ondrej/php`) y sus extensiones
    si faltan.
  - Verificación de compatibilidad de `vendor/` con la versión de PHP elegida
    y opción de reinstalar dependencias.
  - Instalación de Composer si falta.
  - `.env`: validación + creación con drivers **MySQL**, **PostgreSQL** y
    **SQLite**; comparación de credenciales contra la config del entorno;
    test de conexión real; creación automática de la DB si no existe.
  - Resolución inteligente del path de SQLite (respeta archivos existentes,
    resuelve relativos a la convención `database/*.sqlite`, actualiza el
    `.env` con path absoluto).
  - Integración con **nvm**: detección de versión desde `.nvmrc` o
    `engines.node`, instalación si falta, `nvm use`.
  - Detección de package manager (pnpm / yarn / bun / npm) vía lockfile,
    instalación automática del PM si falta (corepack).
  - Build de assets con `run build` (Vite) para generar `public/build/manifest.json`.
  - Generación de certificados SSL con **mkcert**.
  - Configuración de **Nginx** con sites-available + symlink + reload.
  - Escritura del dominio `.test` en el hosts de Windows vía
    `/mnt/c/Windows/System32/drivers/etc/hosts` (opt-in por config).
  - Permisos de Laravel: `chown $USER:www-data` + `chmod ug+rwX` + `setgid`
    en directorios de `storage/` y `bootstrap/cache`.
  - Migraciones y seeders separados, ejecutables bajo confirmación.
  - Log de errores estructurado en `setup-error.log` del proyecto.
- **Instalador** (`install.sh`) one-liner vía `curl`.
- **Desinstalador** (`uninstall.sh`) con flag `--purge` para borrar config.
- Configuración externalizada en `~/.config/projectup/projectup.conf`.

[Unreleased]: https://github.com/ArtroxxGames/projectup/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ArtroxxGames/projectup/releases/tag/v0.1.0
