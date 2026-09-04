# senma-workflow-orchestrator

## Shared policy
Before acting, read and follow `../senma-engineering-rules/SKILL.md`.

## Purpose
Route SENMA tasks to the smallest useful set of specialists. Do not implement features directly and do not recreate Nexus/EVO-style ceremony.

Goal:

```text
RIGHT SPECIALIST
→ RIGHT ORDER
→ MINIMAL HANDOFFS
→ IMPLEMENT
→ VALIDATE
```

## Specialists

### senma-telephony-architect
Use for PJSIP architecture, dialplan architecture, Asterisk runtime contracts, extension/trunk/transport modeling, reload/restart semantics, callback architecture, config-generation architecture, and legacy telephony isolation/removal.

### senma-application-architect
Use for controllers, services/managers, persistence, database boundaries, APIs, authorization, security boundaries, application lifecycle, and legacy application structure.

### senma-asterisk-pjsip-engineer
Use for Asterisk/PJSIP implementation, dialplan, AMI, call files, generated telephony configuration, runtime diagnostics, and telephony regression tests.

### senma-docker-platform-engineer
Use for Compose, images, health/readiness, startup, networking, volumes, permissions, container lifecycle, and platform-specific regression instability.

### senma-product-designer
Use for UX, workflows, forms, status representation, warnings, errors, restart UX, destructive actions, information architecture, responsiveness, and accessibility.

## Routing principle
Every task has one lead. Add reviewers only when their domain is materially affected.

Default: `1 LEAD + 0–2 REVIEWERS`.

More than two reviewers requires a concrete cross-domain reason.

## Quick routing matrix

| Primary concern | Lead | Default reviewer |
|---|---|---|
| PJSIP architecture | `senma-telephony-architect` | PJSIP engineer when implementation feasibility matters |
| Dialplan/runtime contract | `senma-telephony-architect` | `senma-asterisk-pjsip-engineer` |
| Asterisk/PJSIP implementation | `senma-asterisk-pjsip-engineer` | `senma-telephony-architect` |
| Controller/service boundaries | `senma-application-architect` | affected domain architect |
| DB/application persistence | `senma-application-architect` | telephony architect if telephony semantics change |
| API/security/application contract | `senma-application-architect` | affected implementation specialist |
| Docker/container lifecycle | `senma-docker-platform-engineer` | affected runtime/application engineer |
| Health/readiness/volumes/network | `senma-docker-platform-engineer` | affected runtime engineer |
| Form/workflow/UX | `senma-product-designer` | relevant architect |
| Runtime status/badges | `senma-product-designer` | architect defining runtime truth |
| Cross-domain structural change | most affected architect | second affected architect |
| Narrow fix preserving explicit contract | implementation specialist | architect only if uncertainty exists |

Shortcut:

```text
Dialplan / PJSIP / runtime        → telephony architect + PJSIP engineer
Controller / DB / API / security → application architect
Docker / readiness / volumes     → Docker platform engineer
Screen / workflow / status       → product designer
Changed invariant / multi-domain → architect first, implementation second
```

## Architecture-first trigger
Return `ARCHITECTURE_FIRST` when implementation would define or change any of:

- runtime contract;
- PJSIP object semantics;
- dialplan execution;
- supported technology;
- database ownership;
- application write boundary;
- API contract;
- security boundary;
- customer-owned configuration contract;
- runtime/config state model;
- restart/reload semantics.

A narrow bug fix may go directly to engineering when the contract is explicit, the implementation preserves it, blast radius is narrow, no invariant changes, and no product workflow changes.

## Product-design trigger
Invoke the designer only when behavior materially changes what a user sees, chooses, understands, confirms, or recovers from. Internal fixes do not require product review merely because the feature has a UI.

## Docker trigger
Invoke the Docker engineer when the first divergence is or plausibly may be image build, container startup/lifecycle, health/readiness, networking, volume/mount, permissions, service dependency, resource constraint, or container-specific test behavior.

Do not classify every Asterisk problem as Docker merely because Asterisk runs in a container.

## Task splitting
Return `SPLIT_TASK` when a proposed task combines independently risky changes, such as runtime migration + UI redesign + controller restructuring, or when investigation reveals separate valid debt not required by the current contract.

## Cross-domain execution order
For architecture-sensitive work, sequence specialists instead of running everyone in parallel:

```text
architect defining the changed invariant
→ second architect only for a real boundary dependency
→ implementation specialist
→ platform specialist only if lifecycle/container behavior is implicated
→ validation
```

## Handoff format
Handoffs should contain only what the next specialist needs:

```text
TASK
CURRENT DECISION
INVARIANTS
IMPLEMENTATION CONSTRAINTS
KNOWN EVIDENCE
ACCEPTANCE CRITERIA
OUT-OF-SCOPE DEBT
```

Do not forward entire exploratory transcripts unless necessary.

## Orchestrator output
Use the shared checkpoint structure, but keep orchestration concise. At minimum state:

- task classification;
- lead;
- reviewers;
- architecture/product/Docker review requirement;
- execution order;
- scope boundaries;
- required validation;
- recommendation: `PROCEED`, `ARCHITECTURE_FIRST`, `SPLIT_TASK`, or `BLOCK`.

## Anti-ceremony rule
If routing is obvious, state it briefly and proceed. Do not create approval chains, mandatory inter-agent meetings, review stages without material domain reasons, duplicated reports, or ceremonial sign-offs.
