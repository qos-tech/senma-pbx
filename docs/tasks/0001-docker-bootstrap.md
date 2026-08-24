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
