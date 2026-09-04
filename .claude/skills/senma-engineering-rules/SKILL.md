# senma-engineering-rules

## Purpose
Shared engineering policy for every SENMA PBX specialist and task.

All SENMA skills must follow this file. Domain skills should add only domain-specific rules and must not redefine these policies unless a task explicitly requires a stricter rule.

## Engineering model
SENMA is modernized incrementally. Prefer changes that are small, isolated, evidence-driven, reversible, regression-covered, and compatible with validated production behavior.

Avoid broad rewrites, opportunistic refactors, unrelated cleanup, blind search-and-replace migrations, and architecture changes driven only by historical assumptions.

## Evidence over assumption
When sources conflict, prefer current observable evidence in this order unless a domain skill defines a more specific hierarchy:

1. reproducible runtime behavior;
2. generated/runtime configuration actually consumed;
3. current production code path;
4. current persistent state;
5. regression evidence;
6. current task documentation;
7. historical documentation;
8. comments and assumptions.

Runtime evidence may invalidate historical assumptions. Never force implementation to reproduce a disproven invariant.

## Scope protection
Every discovered issue must be classified as either:

- `REQUIRED_FOR_CURRENT_TASK`
- `FOLLOW_UP_DEBT`

Only the first belongs in the current implementation. If a required change materially expands blast radius or risk, return `SPLIT_TASK` instead of silently broadening scope.

## Refactoring policy
Refactor only when directly required for correctness, security, or task-required testability. Do not restructure unrelated code because it is old, awkward, or already being touched.

## Security preservation
Previously closed security behavior is part of the architecture. Never weaken authorization, authentication, CSRF protection, input validation, SQL parameterization, shell escaping, path validation, output encoding, or fixture ownership controls merely to make a feature or test pass.

Historical/legacy test rows may be created through test-only paths when required to prove compatibility or security boundaries. Production write restrictions must remain intact.

## Architecture direction
Current SENMA direction includes:

- Asterisk 22;
- PJSIP-only supported telephony runtime;
- no `chan_sip` reintroduction;
- explicit application boundaries;
- explicit container readiness;
- runtime/application coherence;
- preservation of customer-owned configuration;
- legacy read compatibility isolated from supported writes where required.

A specialist must not silently reverse an established architecture decision. Escalate to the appropriate architect when a task appears to require that.

## Customer-owned state
Classify mutable state before changing it:

- `APPLICATION_GENERATED`
- `RUNTIME_GENERATED`
- `FIRST_BOOT_SEED`
- `CUSTOMER_OWNED`
- `PERSISTENT_DATA`
- `TEMPORARY`
- `TEST_ONLY`
- `HISTORICAL`
- `UNKNOWN`

Never delete or overwrite `UNKNOWN`. A file seeded only on first boot and preserved afterward should normally be treated as customer-owned.

## Failure behavior
Explicit failure is preferable to silently broken behavior. Do not accept flows where the application reports success but generates a state the runtime cannot execute.

## Timing and readiness
Do not use arbitrary sleeps as the default fix for asynchronous behavior. Prefer an observable condition, bounded polling, explicit timeout, and diagnostic failure output.

Keep these states distinct when relevant: `started`, `running`, `ready`, `applied`, `converged`, `active`.

## Test philosophy
Tests must prove the intended contract, not merely exit zero. Before changing a failing test, classify the failure as one of:

- `REAL_PRODUCT_BUG`
- `WRONG_TEST_ASSUMPTION`
- `HARNESS_BUG`
- `PLATFORM_BUG`
- `RUNTIME_RACE`
- `STALE_FIXTURE`
- `UNRELATED_PRE_EXISTING_FAILURE`

Never weaken an assertion solely to make a gate green.

### Fixture ownership
Automated stale cleanup requires multi-field ownership proof. Never delete production-like state based only on a name match. Ambiguous collisions must block.

### Interrupted runs
Assume SIGTERM, SIGINT, SIGKILL, OOM, container teardown, and host restart can interrupt tests. Trap cleanup alone is not sufficient for every failure mode.

## Canonical validation
Repository gates are:

```bash
make lint
make regression
```

For significant runtime, application, telephony, or platform changes, final validation should normally be:

```bash
make lint
make regression
make regression
git diff --check
git status --short
```

Two consecutive full regression passes are the preferred final gate. Specialized runtime evidence may also be required by the domain skill.

Never report `PASS` for a command that was blocked, partial, skipped, or failed. Use precise states: `PASS`, `FAIL`, `BLOCKED`, `PARTIAL`, `NOT_RUN`.

## Git policy
Never commit automatically.

Before proposing a commit:

```bash
git status --short
git diff --check
git diff --stat
```

Stage explicit task paths. Do not use `git add .` on a dirty tree. Do not include pre-existing modifications, unrelated docs, temporary diagnostics, local tooling, or unrelated skills in the task commit.

A commit should represent one coherent task outcome.

## Documentation policy
Task documentation records evidence and decisions. Do not rewrite historical documents just to make them match new behavior. When new evidence invalidates an old assumption, document the correction in the current task and update canonical architecture docs only when appropriate.

## Shared checkpoint format
All SENMA specialists use this top-level structure:

### TASK
Task identifier and objective.

### LEAD
Specialist responsible for the current phase.

### REVIEWERS
Only specialists materially involved.

### SCOPE
What was examined or changed, plus explicit out-of-scope boundaries.

### FINDINGS
Evidence discovered. Separate runtime fact from inference.

### ROOT CAUSE / DECISION
Use `ROOT CAUSE` for defects and `DECISION` for architecture/design work.

### CHANGES
Exact files and behavior changed. Classify as `PRODUCTION`, `TEST`, `DOCUMENTATION`, `PLATFORM`, or `DESIGN` where useful.

### VALIDATION
Relevant runtime evidence, target tests, lint, regression runs, diff-check, and git status.

### REMAINING DEBT
Only genuine out-of-scope debt. Do not hide unresolved blockers here.

### RECOMMENDATION
Use the domain-appropriate decision, such as `PROCEED`, `APPROVE`, `APPROVE_WITH_CONSTRAINTS`, `APPROVE_WITH_CHANGES`, `SPLIT_TASK`, `REDESIGN_REQUIRED`, or `BLOCK`.

### PROPOSED COMMIT
Narrow commit message after validated implementation. Architecture/design-only reviews may return `N/A`.

## Final rule
The goal is not process compliance for its own sake. The goal is correct architecture, the smallest safe change, observable proof, and preserved regression coverage.
