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

This builds the application image, starts the `app`, `db`, and `asterisk`
containers, and initializes the database schema on first run. Once all three
containers report healthy (`make ps`), the application is reachable at
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
make asterisk-cli # open the Asterisk remote console (asterisk -rvvv)
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

As of TASK-0005 (Asterisk container bootstrap), all flows including `queues`
are expected to genuinely pass — `queues` previously reported as a known
limitation (no Asterisk service, missing config file) until the `asterisk`
container and shared `/etc/asterisk/snep` config were introduced. See
`docs/tasks/0003-http-smoke-harness.md` and
`docs/tasks/0005-asterisk-container-bootstrap.md`.

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
- A dedicated `asterisk` container (Asterisk 22 LTS, compiled from source —
  see `docker/asterisk.Dockerfile`) joined the topology in TASK-0005. AMI is
  reachable at `asterisk:5038` (container-to-container only, not published to
  the host) and `/etc/asterisk/snep` is shared read-only with `app`. This is a
  minimal runtime-boundary bootstrap, not a functional PBX yet — PJSIP,
  trunks, call routing, AGI runtime, and full ODBC realtime integration are
  all still deferred. See `docs/tasks/0005-asterisk-container-bootstrap.md`
  for exactly what is and isn't wired up.
- Full implementation notes, PHP 8.4 compatibility fixes applied, and known
  remaining gaps are recorded in `docs/tasks/0001-docker-bootstrap.md`.
