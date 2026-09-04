# docker-bootstrap

## Shared policy
Before acting, read and follow `../senma-engineering-rules/SKILL.md`.

## Purpose
A focused utility skill for converting legacy host assumptions into an explicit, reproducible Docker Compose bootstrap environment.

Use this for initial/containerization/bootstrap work. For ongoing container lifecycle, readiness, networking, volume, permission, or image engineering, prefer `senma-docker-platform-engineer`.

## Method
1. Discover runtime dependencies from source, installation scripts, and actual environment behavior.
2. Prefer compatibility over modernization during bootstrap.
3. Containerize one dependency boundary at a time.
4. Add meaningful health/readiness checks.
5. Add deterministic initialization.
6. Expose routine operations through `make` where appropriate.
7. Start the environment and verify the real application response.
8. Record legacy host assumptions as explicit follow-up debt.

## Scope boundary
Do not opportunistically redesign SQL, replace the database engine, migrate SIP to PJSIP, rewrite frontend behavior, or perform broad PHP cleanup while bootstrapping containers.

## Handoff
Once the environment exists and the task becomes ongoing platform engineering rather than bootstrap, hand off to `senma-docker-platform-engineer`.
