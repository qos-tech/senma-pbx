# Bootstrap Docker

Work only on TASK-0001.

1. Read `CLAUDE.md`.
2. Read `docs/tasks/0001-docker-bootstrap.md`.
3. Audit runtime requirements before changing application code.
4. Update Docker/Compose/Makefile/bootstrap files as needed.
5. Preserve MariaDB compatibility.
6. Do not begin PJSIP, PostgreSQL or broad PHP modernization.
7. Validate with:
   - `docker compose config`
   - `make doctor`
   - `make up`
   - `make ps`
   - application HTTP request
   - relevant container logs
8. Summarize remaining blockers precisely.
