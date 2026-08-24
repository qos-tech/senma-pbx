# MAG PBX

MAG PBX is a modernized fork of SNEP 3.07. See `CLAUDE.md` for the full project
guide, phase boundaries, and development principles.

## Prerequisites

- Docker
- Docker Compose v2 (`docker compose version`)

No PHP, MariaDB, or Asterisk installation is required on the host — the
application, its PHP runtime, and its database all run in containers.

## Quickstart

```bash
git clone <repo>
cd mag-pbx
cp .env.example .env
make dev
```

This builds the application image, starts the `app` and `db` containers, and
initializes the database schema on first run. Once both containers report
healthy (`make ps`), the application is reachable at
`http://localhost:8080/` (or whatever `MAG_HTTP_PORT` is set to in `.env`).

## Common commands

```bash
make dev        # doctor + up: the standard first-run / day-to-day command
make up          # build and start containers
make down        # stop and remove containers (keeps volumes/data)
make restart     # restart running containers
make logs        # follow container logs
make ps          # show container status
make shell       # open a shell in the app container
make db-shell    # open a MariaDB shell against the db container
make smoke       # run the HTTP smoke test suite (starts the env if needed)
make doctor      # check local prerequisites (docker, .env, compose config)
make reset       # DESTRUCTIVE: remove containers and volumes (asks to confirm)
```

## HTTP smoke tests

`make smoke` runs `scripts/smoke-test.sh` — a plain bash + curl regression
suite (no test framework) that exercises the 10 core admin flows (login,
dashboard, extensions, trunks, routes, groups, queues, reports, settings,
logout), checks logout actually invalidates the session, and confirms
`includes/setup.conf`/`setup.conf.dist` stay inaccessible over HTTP. It logs
in with the seeded `admin` account (password reset to a fixed dev-only
value each run, directly in the dev database — never touching `.env` or
real credentials) and diffs the app container's fatal-error log
before/after to catch regressions a bare HTTP-status check would miss.

One flow (`queues`) is expected to report as a known limitation, not a
failure: this Docker topology deliberately has no Asterisk service yet, so
`queues` 500s on a missing Asterisk config file. The suite asserts that
*specific* failure signature — if `queues` ever fails any other way, that's
reported as a real regression. See `docs/tasks/0003-http-smoke-harness.md`.

## Notes on the current Docker bootstrap milestone

- The application source lives in `snep/` and is bind-mounted into the `app`
  container at `/var/www/html/snep` (the legacy application hardcodes this
  path in several places, so it's preserved rather than remapped — see
  `docs/tasks/0001-legacy-runtime-audit.md`).
- `snep/includes/setup.conf` (DB credentials, filesystem paths, etc.) is
  generated from `snep/includes/setup.conf.dist` and your `.env` values the
  first time the `app` container starts, and is gitignored from then on —
  see `docker/entrypoint.sh`. Delete it (or `make reset`) to regenerate it.
  Any settings the app itself writes back into this file persist across
  restarts.
- Database schema/seed data is loaded once, automatically, the first time
  the `db` container initializes an empty data volume — see
  `docker/db-init/00-import-snep-schema.sh` for exactly what is (and isn't)
  imported, and why.
- Asterisk is deliberately not part of this topology yet (see
  `docs/decisions/0001-development-environment.md`); features that depend on
  it (AMI/AGI, call recording, etc.) are expected to be unavailable for now.
- Full implementation notes, PHP 8.4 compatibility fixes applied, and known
  remaining gaps are recorded in `docs/tasks/0001-docker-bootstrap.md`.
