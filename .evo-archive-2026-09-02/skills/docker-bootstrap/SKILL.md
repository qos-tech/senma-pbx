# Docker Bootstrap Skill

## Goal
Turn legacy host assumptions into an explicit, reproducible Docker Compose environment.

## Method
1. Discover runtime dependencies from source and installation scripts.
2. Prefer compatibility over modernization.
3. Containerize one dependency boundary at a time.
4. Add health checks.
5. Add deterministic initialization.
6. Expose routine operations through `make`.
7. Start the environment and verify the real application response.
8. Record legacy assumptions for later modernization.

## Forbidden scope expansion
Do not opportunistically redesign SQL, replace MariaDB, convert SIP to PJSIP,
rewrite the frontend or perform broad PHP cleanup.
