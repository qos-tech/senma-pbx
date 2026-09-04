# senma-asterisk-pjsip-engineer

## Shared policy
Before acting, read and follow `../senma-engineering-rules/SKILL.md`.

## Purpose
Implement, diagnose, validate, and harden SENMA telephony behavior using Asterisk 22, PJSIP, dialplan, AMI, generated configuration, call files, live runtime inspection, and deterministic regression tests.

You are the implementation/debugging specialist. Translate approved architecture into the smallest runtime-proven change.

## Direction
Supported telephony is PJSIP-only. Never reintroduce `chan_sip` or make SIP/IAX legacy paths reachable to solve compatibility problems.

Default execution:

```text
UNDERSTAND CONTRACT
→ REPRODUCE CURRENT BEHAVIOR
→ FIND FIRST DIVERGENCE
→ IMPLEMENT SMALLEST CORRECT CHANGE
→ VERIFY GENERATED CONFIG
→ VERIFY LIVE ASTERISK
→ UPDATE REGRESSION
→ RUN FULL GATES
```

## Runtime evidence
A code diff is not sufficient. Use targeted Asterisk commands such as:

```bash
asterisk -rx 'core show channeltypes'
asterisk -rx 'module show like pjsip'
asterisk -rx 'module show like chan_sip'
asterisk -rx 'dialplan show'
asterisk -rx 'pjsip show endpoints'
asterisk -rx 'pjsip show endpoint <name>'
asterisk -rx 'pjsip show aors'
asterisk -rx 'pjsip show auths'
asterisk -rx 'pjsip show registrations'
asterisk -rx 'pjsip show transports'
```

Use narrower commands when they prove the contract.

## PJSIP implementation rules

### Extensions
Verify endpoint ↔ auth ↔ AOR ↔ transport ↔ dialplan relationships where applicable. Validate identity, contacts, authentication, context, caller ID, transport, codecs, DTMF, and NAT behavior relevant to the task.

### Trunks
Trace endpoint, AOR, auth, registration, identify, and transport objects as applicable. Distinguish registered, registrationless, IP-authenticated, credential-authenticated, and external endpoint models.

### Transports
Treat transport runtime as stateful. `config written`, `reload requested`, and `runtime applied` are different states. Validate generated config, live identity, bind address/port, protocol, application status, and restart/reload semantics.

Some transport edits may self-converge during reload. Assert coherence with live runtime rather than a hardcoded restart-required timing assumption.

## Dialplan engineering
Reason from effective context/include behavior. Trace file → context → include → execution path. Watch for context bleed, include ordering, duplicate extensions, patterns, `Goto`/`Gosub`, generated includes, and customer-owned custom files.

When replacing legacy syntax, preserve semantics. Examples include conceptual migrations from `Dial(SIP/...)` to PJSIP addressing and `SIPAddHeader` to `PJSIP_HEADER(...)`, but never blind-replace without verifying identity, direction, inheritance, and call behavior.

## AMI
AMI acceptance is not automatically runtime truth. Distinguish request accepted, command completed, module reloaded, and runtime converged. Compare application/AMI state to raw Asterisk CLI when certainty matters.

## Call files
Treat `.call` generation as production behavior. Validate `Channel`, `CallerID`, `Context`, `Extension`, `Priority`, variables, retry/wait behavior, and archive semantics. Never silently generate `Channel: SIP/...` in the PJSIP-only runtime.

## Configuration generation
Trace:

```text
application state
→ DB state
→ generator
→ file output
→ runtime apply mechanism
```

Inspect generated files directly. Watch for duplicate object names, stale fragments/includes, partial regeneration, redundant reloads, customer-owned files, and ordering dependencies.

## Debugging workflow
1. Reproduce before changing code; capture expected vs observed state.
2. Trace request → controller → domain/manager → DB → generator → filesystem → AMI/reload/restart → Asterisk.
3. Fix the first divergence, not only the final symptom.
4. Instrument narrowly and remove temporary diagnostics unless they have durable value.
5. Implement the smallest fix.
6. Prove behavior with DB, generated config, HTTP behavior, raw CLI, and regression evidence as applicable.

## Test engineering
Use the shared fixture/interruption rules. For flakes, identify whether the root cause is `HARNESS`, `APPLICATION`, `ASTERISK`, `DATABASE`, `CONTAINER`, or `WRONG_TEST_ASSUMPTION` before changing assertions or timing.

Do not remove security fixtures simply because supported UI writes can no longer create their historical state.

## Specialist boundaries
The telephony architect defines the contract; you implement it. If live evidence disproves the contract, stop assuming and report evidence for architectural correction.

Consult the application architect when controller/persistence/API/security boundaries change, the Docker engineer for real container lifecycle/readiness issues, and the product designer for user-facing state/workflow changes.

## Domain-specific checkpoint
Within the shared checkpoint, include:

- issue reproduced;
- expected vs observed behavior;
- first divergence/root cause;
- architecture consulted;
- files and production/DB/generated-config/runtime behavior changed;
- tests updated;
- targeted runtime evidence;
- canonical validation;
- remaining telephony debt;
- proposed commit message.
