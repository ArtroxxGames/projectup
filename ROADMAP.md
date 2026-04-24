# ROADMAP

Plan de evolución de projectup. La idea central es tener una **alternativa
open-source y cross-platform a Laragon** — instalás el binario, corrés
`projectup init` una vez para setear el entorno, y después solo clonás
proyectos y corrés `projectup` sin pensar en configuraciones.

## Visión

```
┌──────────────────────────────────────────────────────────────────┐
│  Usuario final (dev)                                             │
│                                                                  │
│  $ projectup init     → setea el entorno entero                  │
│  $ projectup doctor   → diagnostica qué falta                    │
│  $ projectup          → levanta el proyecto actual               │
└──────────────────────────────────────────────────────────────────┘
```

## Fase 1 — v0.1.x (actual)

- [x] Estructura modular `bin/ + lib/frameworks/`
- [x] Dispatcher con subcomandos + auto-detección por `cwd`
- [x] Handler Laravel completo (PHP, Composer, Node, DB, Nginx, SSL, hosts)
- [x] Config externa en `~/.config/projectup/projectup.conf`
- [x] Installer / uninstaller one-liner via `curl`
- [ ] Tests básicos con shellcheck + bats (pendiente)

## Fase 2 — v0.2.x — `projectup init`

El subcomando `init` debería preparar todo el entorno de desarrollo desde cero:

- [ ] Detectar distro (Debian/Ubuntu/Fedora/Arch/etc.) y adaptar el package manager
- [ ] Instalar y configurar:
  - [ ] **Nginx** con defaults sanos
  - [ ] **MySQL** / MariaDB (con prompt para user/pass)
  - [ ] **PostgreSQL** (con prompt para user/pass/puerto)
  - [ ] **Redis** (opcional)
  - [ ] **PHP** (última estable + extensiones comunes)
  - [ ] **Composer** global
  - [ ] **nvm** + última LTS de Node
  - [ ] **mkcert** + CA local instalada
- [ ] Generar el `~/.config/projectup/projectup.conf` con las credenciales
  reales elegidas
- [ ] Wizard interactivo — preguntar qué servicios querés y saltear los
  que no necesites

## Fase 3 — v0.3.x — Más frameworks

- [ ] **Symfony** (composer.json + bin/console + config/bundles.php)
- [ ] **Next.js / Nuxt / SvelteKit** (package.json + framework config)
- [ ] **Rails** (Gemfile + config/application.rb)
- [ ] **Django** (manage.py + settings.py)
- [ ] **WordPress** (`wp-config.php`)

Cada framework en su propio archivo `lib/frameworks/<name>.sh` exportando
una función `<name>_setup()`. Reusar helpers de `common.sh` (DB, nginx, SSL).

## Fase 4 — v0.4.x — Cross-platform

- [ ] **macOS**: detectar Homebrew, usar `brew` en vez de `apt`
- [ ] **Arch/Fedora**: detectar `pacman`/`dnf` y adaptar `ensure_pkg`
- [ ] Abstraer el package manager detrás de una interfaz común en
  `lib/pkg/<backend>.sh`

## Fase 5 — v0.5.x — Calidad de vida

- [ ] `projectup doctor` — chequea qué falta y te dice cómo arreglarlo
- [ ] `projectup remove <proyecto>` — saca un site de Nginx + hosts + cert
- [ ] `projectup list` — lista todos los sites configurados por projectup
- [ ] `projectup update` — actualiza projectup a la última versión
- [ ] Autocompletado para bash/zsh/fish
- [ ] CI con GitHub Actions (shellcheck + tests bats)
- [ ] Release automático con tags + changelog generado

## Fase 6 — v1.0.0

- [ ] Documentación completa (README con screencasts)
- [ ] Ejemplos por framework
- [ ] Cobertura de tests decente
- [ ] Primer release estable anunciado a la comunidad

---

## Non-goals (cosas que **no** vamos a hacer)

- No ser un gestor de contenedores (Docker/Podman hacen eso mejor).
- No reemplazar a Laravel Valet / Herd en Mac — son opciones válidas allá;
  projectup apunta al caso "quiero Linux nativo / WSL sin drama".
- No manejar deployments productivos. Esto es una herramienta de dev local.
