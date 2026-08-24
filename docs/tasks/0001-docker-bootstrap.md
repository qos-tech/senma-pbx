# TASK-0001 — Docker bootstrap

## Objective
Make a clean clone of MAG PBX start locally through Docker Compose.

## Scope
- application container
- MariaDB container
- `.env.example`
- health checks
- persistent database volume
- Makefile developer interface
- application bootstrap/import procedure
- documentation

## Explicitly out of scope
- PostgreSQL
- PJSIP
- Asterisk modernization
- broad PHP refactoring
- frontend redesign
- production deployment

## Acceptance criteria
1. `cp .env.example .env`
2. `make dev`
3. `make ps` reports required containers running/healthy.
4. The application is reachable at the configured HTTP port.
5. Database initialization completes deterministically.
6. Restarting containers preserves development data.
7. `make logs` shows useful runtime logs.
8. `make shell` opens an application shell.
9. `make reset` is destructive only after explicit confirmation.
10. README documents required host prerequisites.

## Investigation checklist
Before changing application code, locate:
- current document root
- expected writable directories
- required Apache modules
- required PHP extensions
- database configuration file(s)
- SQL schema/bootstrap scripts
- cron/background dependencies
- hard-coded `/var/www/html/snep` paths
- hard-coded hostnames/IPs
- shell calls requiring sudo/root
- Asterisk files expected to exist even for web startup

(Answered in `docs/tasks/0001-legacy-runtime-audit.md`.)

## Status: implemented and validated

`cp .env.example .env && make dev` reaches a healthy `db`, a healthy `app`,
and a rendered SNEP login page at `http://localhost:8080/`, with
deterministic first-run DB initialization. Validated with:
`docker compose config`, `make doctor`, `make up`/`make dev` (cold start,
reset from a truly clean `.env`-less state), `make ps`, `make restart`,
`make down` + `make up` (data/config persistence), `make shell`,
`make db-shell`, direct HTTP requests against the login page and static
assets, and container log inspection (`docker compose logs app|db`).

## Key decisions and why

1. **Container path stays `/var/www/html/snep`, not `/var/www/html/mag`.**
   The legacy code hardcodes this path at *runtime*, not just install-time
   (`includes/setup.conf`'s `path.base`, `DocsController.php`), so remapping
   it would mean patching application code. The scaffold's original
   `./:/var/www/html/mag` bind mount was also mounting the whole repo (not
   `snep/`) as the document root, which would never have served the app at
   all. Fixed to `./snep:/var/www/html/snep` in `compose.yaml`, matching
   `docker/app.Dockerfile`'s `WORKDIR` and `docker/apache-mag.conf`'s
   `DocumentRoot`/`Directory`.

2. **`snep/includes/setup.conf` is generated at entrypoint, not committed.**
   The original file was tracked in git with default dev credentials and a
   hardcoded `127.0.0.1` DB host, which can't reach the separate `db`
   container. It's renamed to `snep/includes/setup.conf.dist` (tracked,
   unchanged content) and gitignored at its original path.
   `docker/entrypoint.sh` copies the `.dist` file to `includes/setup.conf`
   and substitutes `db.host`/`db.username`/`db.password`/`db.dbname` from
   `.env` **only if the file doesn't already exist** — idempotent, so
   settings the running app writes back into this file (e.g. via
   `ParametersController`) survive restarts, and the host's git tree is
   never mutated by the running container. `chown`/`chmod` keep it writable
   by `www-data`, since the app itself writes to it.

3. **`.htaccess` modernized to Apache 2.4 native syntax, not
   `mod_access_compat`.** `snep/includes/.htaccess` used Apache 2.2
   `Order`/`Deny` syntax to block direct HTTP access to `*.conf` files —
   without `mod_access_compat` (not enabled in the base image),
   Apache 2.4+ doesn't honor it, which would silently expose
   `setup.conf`'s DB credentials over HTTP. Rewritten to `Require all
   denied` (same effect, Apache 2.4-native, no extra module). The pattern
   was also widened from `\.conf$` to `\.conf` (no anchor) because the new
   `setup.conf.dist` file (`.dist` suffix) wouldn't otherwise match — caught
   by testing `GET /includes/setup.conf.dist` directly (was serving 200
   before the fix).

4. **`database.sql`'s `CREATE DATABASE`/`GRANT` is not executed.** Superseded
   by the official `mariadb` image's own `MARIADB_DATABASE`/`MARIADB_USER`/
   `MARIADB_PASSWORD` provisioning (already used in `compose.yaml`), and the
   grant is scoped to `'snep'@'localhost'`, which the `app` container
   (a different host on the network) could never use anyway.

5. **`modules/loguser/install/schema.sql` is not imported — it doesn't
   exist in this checkout.** Investigated per the audit's flag: traced the
   only class that would need it (`Snep_LogUser` / `Snep_Audit_Manager`,
   both in `lib/Snep/`, both writing to a `logs_users` table) and confirmed
   `logs_users` is already created by the core `schema.sql`
   (`install/database/schema.sql:829`). The `loguser` module directory was
   evidently folded into core at some point after `INSTALL_GUIDE.md` was
   last updated; nothing is missing functionally.

6. **`install/database/core-cnl.sql` and
   `modules/portability/install/routes.sql` are not imported (new finding,
   not in the original audit).** `core-cnl.sql` inserts into
   `core_cnl_state`, `core_cnl_prefix`, and `core_cnl_city`, none of which
   have a `CREATE TABLE` anywhere in this checkout (only
   `install/database/update/3.01/` and `3.06/` create them, and
   `INSTALL_GUIDE.md`'s own fresh-install steps never run that update
   chain either). `routes.sql` inserts into `regras_negocio`, which has the
   identical problem. Importing either as-is aborts the init script
   partway through, breaking the "deterministic initialization"
   requirement. Both are reference/lookup data (CNL country/state/city
   lookups, portability routing rules), not required for the web UI to
   boot. Excluded and documented; reconstructing the missing DDL (likely by
   replaying the `update/3.01`–`3.07` chain) is follow-up work, not part of
   this milestone.

7. **DB import chain, final:** `schema.sql` → `system_data.sql` →
   `modules/billing/install/schema.sql`, run once via
   `docker/db-init/00-import-snep-schema.sh` (mounted into
   `/docker-entrypoint-initdb.d/`, which MariaDB only executes against a
   fresh/empty data volume — this is what makes init "safe to run more than
   once"). Imports use `--init-command="SET SESSION sql_mode='';"` because
   these dumps were authored against MySQL 5.x's lenient default sql_mode
   (`system_data.sql`'s admin-user seed row omits a value for a `NOT NULL
   dashboard text` column, which MariaDB 10.11's default
   `STRICT_TRANS_TABLES` rejects outright). MariaDB's `mysql` client has no
   `--sql-mode` flag, hence `--init-command` instead.

8. **`/var/log/snep/` is created in the image, not bind-mounted.**
   `setup.conf`'s `path.log` points there; it doesn't exist inside the
   container by default and isn't part of the `snep/` bind mount, so
   `Zend_Log` fatals on the very first request. Created via `RUN mkdir -p
   /var/log/snep && chown www-data:www-data /var/log/snep` in the
   Dockerfile — container-local, ephemeral, not treated as durable data (the
   app's own recordings/config under `snep/` are what's bind-mounted and
   persisted).

9. **`display_errors` is off; errors go to `docker compose logs app`
   instead.** With PHP 8.4, several vendored ZF1 files emit `E_DEPRECATED`
   notices during bootstrap (before the app's own
   `error_reporting(E_ERROR|E_WARNING|E_PARSE)` call takes effect). With
   `display_errors On` (the base image default), those notices are echoed
   directly into the HTTP response body *before* the app's own output —
   which broke a later `header()`-based redirect ("headers already sent"),
   silently downgrading a working page into a blank 200 response. This is a
   behavior regression introduced by the runtime upgrade, not present on
   the original PHP 5.x deployment, so turning it off restores original
   behavior rather than just being a style preference. `docker/php-mag.ini`
   sets `display_errors = Off`, `log_errors = On`,
   `error_log = /dev/stderr`, so PHP errors/warnings/fatals are visible via
   `make logs` instead.

10. **`sox` added to the app image.** Required by the sound-upload and
    music-on-hold controllers (`SoundFilesController.php`,
    `MusicOnHoldController.php`); flagged by the audit, wasn't installed.

11. **Added a `healthcheck` to the `app` service** (`curl -f
    http://localhost/`), matching the existing `db` healthcheck, so `make
    ps` can report both containers' real health rather than just `db`'s.

## Minimal PHP 8.4 compatibility fixes applied

All are one-line, behavior-preserving fixes to code paths that fatal on
PHP 8.4 during a normal login-page request. Each is marked in place with a
short comment pointing back to this document. None constitute the broader
ZF1-on-PHP8 modernization that's explicitly out of scope for this phase —
see "Known remaining gaps" below for what wasn't touched.

| File | Fix |
|---|---|
| `snep/lib/Zend/Registry.php` | `offsetExists()` called `array_key_exists($index, $this)` on the registry object itself — valid in old PHP as a workaround for a long-fixed PHP bug (ZF-960), a `TypeError` in PHP 8 (`array_key_exists()` requires a real array). Changed to `parent::offsetExists($index)`. |
| `snep/lib/Zend/Cache/Backend.php` (×2) | `each()` (removed in PHP 8.0) used to iterate constructor options and `setDirectives()`. Replaced with equivalent `foreach` loops. |
| `snep/lib/Zend/Cache/Core.php` | Same `each()` pattern in the constructor. Replaced with `foreach`. |
| `snep/modules/ivr/actions/UserInteraction.php` | A `break;` outside any loop/switch — silently ignored with a warning in PHP 5, a fatal compile error since PHP 7. Removed (it was already a no-op). |

## Known remaining gaps (not blockers for this milestone)

- **CNL and portability reference/lookup data is not seeded** (see decision
  #6 above) — features relying on `core_cnl_*` city/state/prefix lookups or
  `regras_negocio` portability rules will not have data until a follow-up
  task reconstructs or sources the missing table definitions.
- **`each()` remains in ~130 other vendored ZF1 files** and curly-brace
  string/array-offset syntax (`$var{0}`, removed in PHP 8.0) remains in 14
  files (`lib/Zend/Json/Decoder.php` and `Encoder.php` are the ones most
  likely to be hit, since JSON is common in AJAX-driven admin screens).
  These were deliberately **not** preemptively patched — only the ones
  actually hit on the login-page boot path were fixed, per this task's
  "minimal fixes to boot" scope. Any admin feature that exercises an
  unpatched path will still fatal; each will need the same one-line
  treatment when it's actually exercised, or a proper ZF1-on-PHP8
  compatibility pass in Phase 2.
- **`snep/lib/Zend/View/Helper/HeadLink.php:393`** emits a non-fatal
  `compact(): Undefined variable $extras` warning on every request. Cosmetic
  (goes to `make logs`, not the browser), left as-is.
- **Login was not exercise-tested end-to-end** (credentials for the seeded
  admin user are an unknown legacy hash) — verified up to a correctly
  rendered, correctly styled login page with a live session cookie and DB
  connectivity, which satisfies this milestone's "reachable web interface"
  criterion, but the authenticated app (dashboard, etc.) is unverified.
- **AMI/AGI/Asterisk-dependent features are unavailable**, by design — see
  ADR-0001. `setup.conf`'s `ip_sock`/`user_sock`/`pass_sock` are left at
  their original defaults (`127.0.0.1`), not templated, since there's no
  Asterisk service in this topology yet.
