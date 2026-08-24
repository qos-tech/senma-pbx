# MAG PBX — Claude Code Project Guide

## Mission

MAG PBX is a modernized fork of SNEP 3.07.

The first milestone is not a rewrite. The first milestone is:

> A fresh clone of the repository must be able to start a reproducible local development environment with Docker.

Target developer workflow:

```bash
git clone <repo>
cd mag-pbx
make dev
```

The result must be a usable MAG/SNEP development environment with clear logs and deterministic dependencies.

## Current modernization targets

- Product name: MAG PBX
- Origin: fork of SNEP 3.07
- License: GPL-3.0-or-later for inherited/derived code
- Primary development environment: Docker
- Target operating system for production later: Debian 14
- Target PHP: PHP 8.4+
- Target Asterisk: Asterisk 22 LTS
- Target SIP stack: PJSIP
- Current database: preserve MariaDB/MySQL compatibility during the first migration phase
- Future database candidate: PostgreSQL
- Do not migrate databases during the Docker bootstrap milestone

## Development principles

1. Preserve existing behavior before modernizing it.
2. Prefer small, reviewable changes over broad rewrites.
3. Do not mix Docker bootstrap, PHP modernization, PJSIP migration and database migration in the same change.
4. Never remove original copyright or licensing notices from inherited files.
5. Mark materially modified inherited files according to GPL requirements.
6. Do not introduce new runtime dependencies without documenting why they are needed.
7. Prefer official Debian, PHP, MariaDB and Asterisk packages/images where they satisfy the milestone.
8. If Asterisk must be compiled, isolate the build in Docker and pin the exact version.
9. Configuration and secrets must come from environment variables or mounted development config, never hardcoded credentials.
10. Changes must leave the repository in a state another developer can reproduce.

## Phase boundaries

### Phase 0 — Repository baseline
- Preserve the original SNEP code and history.
- Establish MAG naming, licensing notes and development documentation.

### Phase 1 — Docker bootstrap
Goal: run the existing application reproducibly.

Allowed:
- Dockerfile(s)
- compose.yaml
- Makefile
- development environment variables
- Apache/PHP runtime configuration
- MariaDB container
- migration/import scripts
- filesystem permission fixes required for containers
- health checks
- developer documentation

Avoid unless absolutely required to boot:
- application refactors
- PHP 8 compatibility rewrites
- Asterisk dialplan rewrites
- chan_sip → PJSIP conversion
- database schema redesign

### Phase 2 — PHP modernization
Goal: make the application compatible with PHP 8.4+ while preserving behavior.

### Phase 3 — Asterisk 22 compatibility
Goal: make the legacy telephony behavior run with Asterisk 22.

### Phase 4 — PJSIP
Goal: remove chan_sip assumptions and implement native PJSIP provisioning.

### Phase 5 — Architecture modernization
Goal: progressively isolate telephony, persistence and web concerns.

### Phase 6 — PostgreSQL evaluation/migration
Only begin after database access is sufficiently isolated.

## Required commands

Treat the Makefile as the public developer interface.

Expected commands:

```bash
make dev
make up
make down
make restart
make logs
make ps
make shell
make db-shell
make test
make lint
make doctor
make reset
```

If a command is not implemented yet, add it as part of the relevant task rather than teaching developers one-off docker commands.

## Docker rules

- Prefer Docker Compose v2.
- Use named volumes for persistent development data.
- Keep application source bind-mounted for fast iteration unless this creates an unavoidable compatibility problem.
- Add health checks to stateful/runtime services where practical.
- Use explicit service names.
- Do not use `latest` tags.
- Pin major/minor versions at minimum; pin exact versions for Asterisk builds.
- Do not place real credentials in committed `.env` files.
- Commit `.env.example`, not `.env`.
- Container entrypoints must be idempotent.
- Database initialization must be safe to run more than once or clearly guarded.
- Do not silently mutate developer host configuration.

## Validation rule

Before claiming a Docker task is complete, run the closest applicable checks:

```bash
docker compose config
make doctor
make up
make ps
```

Then validate the actual application endpoint and inspect container health/logs.

If tests exist:

```bash
make test
```

If linting exists:

```bash
make lint
```

Do not claim success from a successful image build alone.

## Git discipline

Use focused branches such as:

```text
chore/docker-bootstrap
fix/docker-permissions
chore/php-runtime
refactor/php84-compat
feat/pjsip-extensions
feat/pjsip-trunks
```

Keep commits conceptually narrow.

Do not rewrite unrelated legacy code while solving infrastructure tasks.

## Working with legacy code

Before changing an unfamiliar area:

1. Trace how it is currently used.
2. Identify configuration files, SQL, shell calls and Asterisk dependencies.
3. Note implicit filesystem/permission assumptions.
4. Add the smallest compatibility change needed.
5. Preserve behavior.
6. Record architectural debt separately instead of fixing everything opportunistically.

## Documentation

Significant architectural decisions go in:

```text
docs/decisions/
```

Active implementation tasks go in:

```text
docs/tasks/
```

When a task exposes a future problem outside its scope, record it instead of expanding the current task.

## Definition of Done — Docker bootstrap

The Docker milestone is complete when a developer on a clean machine with Docker can:

```bash
git clone <repo>
cd mag-pbx
cp .env.example .env
make dev
```

and obtain:

- application container running
- database container healthy
- application reachable from the host
- database initialized
- persistent data stored in named volumes
- logs available through `make logs`
- shell available through `make shell`
- teardown through `make down`
- destructive reset clearly separated behind `make reset`
- documented prerequisites and startup procedure
- no manually installed PHP/MariaDB/Asterisk requirement on the host
