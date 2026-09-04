# legacy-audit

## Shared policy
Before acting, read and follow `../senma-engineering-rules/SKILL.md`.

## Purpose
A focused utility skill for evidence-based discovery of inherited/legacy subsystems before migration or removal.

Use it to map unknown behavior. Domain-specific architectural decisions still belong to the relevant SENMA architect.

## Audit questions
For each inherited subsystem, determine:

- what calls it;
- what files/config it reads or writes;
- what database tables/fields it touches;
- what shell commands it executes;
- what Asterisk interfaces/technologies it assumes;
- what filesystem ownership/permissions it requires;
- whether behavior is application logic, telephony runtime logic, platform/install logic, customer-owned customization, or test-only behavior;
- whether it is reachable in the current supported product.

## Classification
Classify findings as appropriate:

- `LIVE_SUPPORTED`
- `LIVE_COMPATIBILITY`
- `BROKEN_BUT_REACHABLE`
- `WRITE_CAPABLE_BUT_UNREACHABLE`
- `CUSTOMER_OWNED`
- `DEAD`
- `HISTORICAL_ONLY`
- `UNKNOWN`

Do not recommend deletion of `UNKNOWN`.

## Output
Produce concise findings with concrete file paths/call paths, runtime evidence where available, migration implications, and the specialist that should own the next decision.
