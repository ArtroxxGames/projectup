# projectup

[![shellcheck](https://github.com/ArtroxxGames/projectup/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/ArtroxxGames/projectup/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/github/license/ArtroxxGames/projectup?color=blue)](LICENSE)
[![Latest tag](https://img.shields.io/github/v/tag/ArtroxxGames/projectup?label=version)](https://github.com/ArtroxxGames/projectup/releases)
[![Stars](https://img.shields.io/github/stars/ArtroxxGames/projectup?style=social)](https://github.com/ArtroxxGames/projectup/stargazers)

> Laragon-style dev environment para Linux y WSL. Open-source, gratis, hackeable.

`projectup` es un CLI que te configura automáticamente un proyecto PHP/Laravel
(y próximamente otros frameworks) en tu entorno local de desarrollo: detecta
la versión de PHP requerida, instala lo que falte, configura Nginx con HTTPS,
valida la base de datos, compila los assets de frontend, y te deja la URL
`https://mi-proyecto.test` lista para abrir en el navegador.

Si venís de Windows con Laragon y estás armando un entorno de desarrollo en
WSL o Linux puro — esto es para vos.

---

## Instalación

```bash
curl -fsSL https://raw.githubusercontent.com/ArtroxxGames/projectup/main/install.sh | bash
```

Esto:

1. Clona el repo en `/usr/local/share/projectup`
2. Crea un symlink en `/usr/local/bin/projectup` (queda en tu `$PATH`)
3. Crea tu config en `~/.config/projectup/projectup.conf`

Después, revisá la config y ajustala a tu entorno:

```bash
$EDITOR ~/.config/projectup/projectup.conf
```

## Uso

Desde la raíz de un proyecto Laravel:

```bash
projectup
```

El CLI **auto-detecta** el framework mirando los archivos del proyecto
(ej: `composer.json` + `artisan` → Laravel). Podés forzar el handler:

```bash
projectup laravel
```

Otros comandos:

```bash
projectup --help     # ayuda
projectup --version  # versión
```

## Qué hace cuando lo corrés en un proyecto Laravel

1. **Detecta PHP** requerido por `composer.json` y usa la versión instalada
   más alta que satisfaga la constraint (`^8.2` = 8.2 o superior). Si no
   tenés ninguna que sirva, la instala con el PPA `ondrej/php` junto con
   todas las extensiones que Laravel necesita.
2. **Verifica `vendor/`**: si existe y no carga con la PHP elegida (porque
   fue compilado con otra versión), te ofrece reinstalar con Composer.
3. **Node.js + Vite**: detecta la versión desde `.nvmrc` o `engines.node`,
   la instala con `nvm` si falta, detecta el package manager por lockfile
   (npm/pnpm/yarn/bun), instala dependencias y compila los assets con
   `run build` (para evitar `ViteManifestNotFoundException`).
4. **Pregunta el subdominio** y le concatena `.test`.
5. **`.env` y base de datos**: si no hay `.env`, lo crea desde `.env.example`
   y te pregunta el motor (MySQL / PostgreSQL / SQLite). Si ya existe,
   valida que las credenciales coincidan con tu entorno, hace una conexión
   real, y crea la DB si no existe. Para SQLite, resuelve el path
   inteligentemente y toca el archivo si hace falta.
6. **Certificados SSL** con `mkcert` (HTTPS local trusted).
7. **Nginx**: escribe el site en `sites-available`, hace symlink en
   `sites-enabled`, valida la config y recarga.
8. **Hosts de Windows** (solo WSL): intenta agregar
   `127.0.0.1 tuproyecto.test` a `C:\Windows\System32\drivers\etc\hosts`.
   Si falla por permisos, te avisa y seguís.
9. **Permisos** de `storage/` y `bootstrap/cache` (chown a tu usuario +
   grupo webserver + setgid).
10. **Pregunta por migraciones** y **seeders** (separados). Después corre
    `optimize:clear` al final.
11. **Log de errores** en `./setup-error.log` si algo falla.

## Configuración

El archivo `~/.config/projectup/projectup.conf` define tu entorno:

```bash
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASS=

PGSQL_HOST=127.0.0.1
PGSQL_PORT=5432
PGSQL_USER=postgres
PGSQL_PASS=postgres

CERT_DIR="$HOME/certificados"
WEB_GROUP=www-data

# Solo WSL — vacío en Linux puro
WIN_HOSTS_PATH=/mnt/c/Windows/System32/drivers/etc/hosts
```

Ver [`config/projectup.conf.example`](config/projectup.conf.example) con los
defaults comentados.

## Pre-requisitos del entorno

projectup asume que ya tenés instalados en el sistema:

- **Nginx**
- **MySQL** y/o **PostgreSQL** (con las credenciales que pongas en la config)
- **nvm** (para detección de Node)
- **mkcert** (si no está, lo intenta instalar vía apt)

> 💡 En una futura versión, `projectup init` va a instalar y configurar todo
> el entorno por vos. Ver [ROADMAP.md](ROADMAP.md).

### WSL: hosts de Windows

Para que `projectup` pueda escribir en el hosts de Windows desde WSL, abrí
tu terminal WSL **como administrador de Windows** (click derecho → "Run as
administrator"). Si no, el dominio lo tenés que agregar vos manualmente a
`C:\Windows\System32\drivers\etc\hosts`.

## Frameworks soportados

| Framework | Status |
|---|---|
| Laravel | ✅ v0.1 |
| Symfony | 📋 v0.3 |
| Next.js | 📋 v0.3 |
| Nuxt    | 📋 v0.3 |
| Rails   | 📋 v0.3 |
| Django  | 📋 v0.3 |

Ver [ROADMAP.md](ROADMAP.md) para el plan completo.

## Desinstalar

```bash
curl -fsSL https://raw.githubusercontent.com/ArtroxxGames/projectup/main/uninstall.sh | bash
```

Preserva tu config en `~/.config/projectup/`. Para borrar eso también:

```bash
curl -fsSL https://raw.githubusercontent.com/ArtroxxGames/projectup/main/uninstall.sh | bash -s -- --purge
```

## Contribuir

Pull requests bienvenidos. Sugerencias de arquitectura:

- Cada framework handler vive en `lib/frameworks/<name>.sh` y exporta una
  función `<name>_setup`.
- Helpers compartidos (logging, prompts, package management, config) van en
  `lib/common.sh`.
- La detección por cwd va en `lib/detect.sh`.
- Nada de credenciales hardcodeadas — todo vía config.

Para desarrollo local:

```bash
git clone https://github.com/ArtroxxGames/projectup.git
cd projectup
./bin/projectup --help
```

## Licencia

[MIT](LICENSE) — hacé lo que quieras con esto.

## Autor

[@ArtroxxGames](https://github.com/ArtroxxGames) — con mucha paciencia y
varios iteraciones de debugging sobre un WSL.
