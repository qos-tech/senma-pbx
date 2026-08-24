# ADR-0001 — Docker-first development environment

## Status
Accepted.

## Context
MAG PBX inherits a legacy installation model from SNEP that assumes a specific Debian host,
system packages, filesystem layout and telephony services.

## Decision
Development becomes Docker-first before broad application modernization begins.
MariaDB is retained during bootstrap to reduce simultaneous change.
Asterisk is deliberately excluded from the first minimal topology until web/database dependencies are understood.

## Consequences
Positive:
- reproducible local environment
- easier Claude Code validation
- isolated legacy dependencies
- easier CI later

Negative:
- legacy filesystem assumptions may require compatibility shims
- telephony integration is incomplete until an Asterisk service is added
