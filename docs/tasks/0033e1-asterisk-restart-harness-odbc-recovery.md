# TASK-0033E1 — Asterisk Restart Harness ODBC Recovery

Status: implemented and validated. Lead: `senma-telephony-architect`.
Reviewer: `senma-docker-platform-engineer`. `senma-application-architect`
not invoked -- the fix is entirely test-harness-side and touches no
production application/controller/persistence code.

Scope: **TEST HARNESS ONLY**, per this task's own explicit boundary. No
production startup, Docker healthcheck, dialplan, CDR configuration, or
ODBC configuration was changed. `git diff --stat` for this task touches
exactly `scripts/lib/harness.sh` plus nine smoke-test scripts, nothing
else.

---

## ROOT CAUSE

TASK-0033E (docs/tasks/0033e-readiness-contract-hardening.md, REMAINING
DEBT item 5) documented that `res_odbc.so` makes exactly one connection
attempt during Asterisk's own module-load sequence and does **not**
auto-reconnect afterward, and attributed the resulting post-restart ODBC
leak to four specific pre-existing suites (`wss-platform-smoke`,
`tls-cert-management-smoke`, `transport-shared-runtime-ux-smoke`,
`restart-smoke`) that restart Asterisk mid-run.

Live re-investigation in this task (Phase 1), per this project's
evidence-over-assumption rule, **reproduced the leak and found a more
precise root cause than originally attributed**:

- `docker compose up -d --force-recreate <service(s)>` and
  `docker compose start <service>` both go through Compose's
  create/start path, which **does** honor
  `depends_on: db: condition: service_healthy` (the gate TASK-0033E
  added) -- live-confirmed, 100% of trials, ODBC reconnects cleanly
  every time, including when `asterisk` is recreated together with
  `app`/`db` in the same invocation.
- The plain `docker compose restart` subcommand (bare, restarting every
  service, or naming `asterisk` alongside `db`) does **not** re-evaluate
  any dependency condition -- it simply bounces already-existing
  containers. This races `res_odbc.so`'s one-shot connect attempt
  against `db` not yet accepting connections -- live-confirmed, 100% of
  trials (`Number of active connections: 0`, `Last fail connection
  attempt: ...` in `odbc show all`; `Error SQLConnect=-1 errno=2002
  [unixODBC][ma-3.1.15]Can't connect to server on 'db'` in
  `/var/log/asterisk/full`).
- A process-level restart (`asterisk -rx "core restart now"`, or the
  real HTTP restart endpoint's `core restart gracefully`/`core restart
  now` via AMI) never interrupts the container/network/db connection
  path at all and self-heals reliably on its own.

**The four suites TASK-0033E named are not, in isolation, the suites
that leave ODBC broken** -- each restarts/recreates only `asterisk`
(never naming `db` on a bare `restart`), or restarts Asterisk only at
the process level, and each was live-verified (including running the
actual suite script, not a simulation) to self-heal correctly under the
`asterisk -> db` `depends_on` gate TASK-0033E already added. The suite
that actually reproduces the leak inside `make regression` is
**`readiness-smoke-test.sh`** (added *by* TASK-0033E itself), whose own
step 6 does a bare, full-stack `docker compose restart` -- exactly the
subcommand that skips the dependency gate. `secret-rotation-smoke-test.sh`
(a separate, non-`make regression` destructive target) has the same
defect at its own step 17 (`$COMPOSE restart app asterisk db`).

This correction does not change the fix's shape -- the task still
builds one shared, suite-agnostic recovery contract and applies it
everywhere Asterisk restarts mid-suite, per Phase 3's own instruction
not to special-case four scripts. It changes which suites the recovery
step actually *engages* on versus merely *confirms* an already-healthy
state.

Classification: `TEST_HARNESS_STATE_LEAK`, confirmed not a production
defect (Phase 17: no production file was touched to fix it).

---

## AFFECTED SUITES / RESTART PATTERNS

Full matrix from Phase 2's broad search (`grep` across every
`scripts/*.sh` for `restart`/`force-recreate`/`stop`+`start`/CLI-level
restart), not limited to the four originally named:

| Suite | Restart mechanism | Names `db` too? | ODBC self-heals (live-tested)? | Shared helper applied |
|---|---|---|---|---|
| `readiness-smoke-test.sh` | `$COMPOSE restart` (bare, all services) | yes (implicitly, all) | **No -- confirmed broken, 100% of trials** | Yes -- real recovery |
| `secret-rotation-smoke-test.sh` | `$COMPOSE restart app asterisk db` | yes (explicit) | **No -- confirmed broken, 100% of trials** | Yes -- real recovery |
| `wss-platform-smoke-test.sh` | `$COMPOSE restart asterisk` then `up -d --force-recreate asterisk` | no | Yes | Yes -- defensive verification |
| `tls-cert-management-smoke-test.sh` | `$COMPOSE restart asterisk` | no | Yes | Yes -- defensive verification |
| `transport-shared-runtime-ux-smoke-test.sh` | `$COMPOSE stop asterisk` + `$COMPOSE start asterisk` | no | Yes | Yes -- defensive verification |
| `restart-smoke-test.sh` | Real HTTP restart endpoint -> AMI `core restart gracefully`/`core restart now` (process-level, container never touched) | no | Yes | Yes -- replaces suite's own ad hoc `odbc show all` grep |
| `pjsip-runtime-status-smoke-test.sh` | `$COMPOSE stop asterisk` + `$COMPOSE start asterisk` | no | Yes | Yes -- defensive verification |
| `transport-smoke-test.sh` | `asterisk -rx "core restart now"` (process-level) | no | Yes | Yes -- defensive verification |
| `backup-restore-dr-smoke-test.sh` | `up -d --force-recreate app asterisk db` (grouped recreate) | yes (grouped, create path) | Yes | Yes -- defensive verification |

"Defensive verification" means: this suite's own restart mechanism was
live-confirmed, including by running the actual suite, to self-heal
under the current `depends_on` contract, but the suite now asserts the
ODBC/CDR-ready invariant explicitly via the shared helper anyway (Phase
12's suite-isolation contract), so its own pass/fail result does not
silently depend on that self-healing behavior continuing to hold if
Compose/Docker semantics ever change. "Real recovery" means the helper's
reload path was live-confirmed to actually engage and repair a genuinely
broken state during this task's validation.

No other suite in `scripts/` restarts/recreates the `asterisk` container
or process; this list is exhaustive as of this task.

---

## ODBC RECOVERY CONTRACT

`harness_require_odbc_ready [dsn]` (default DSN `snep`, the only DSN
`res_odbc.conf` declares in this project): parses `odbc show all` for
the named DSN's own `Number of active connections: N` line and requires
`N > 0`. Deliberately does **not** treat "module loaded" as sufficient
(Phase 9) -- `res_odbc.so` reports `Running` even with zero live
connections, which is exactly the leak this task fixes.

Recovery: `module reload res_odbc.so` (live-confirmed to restore the
DSN's live connection on its own; TASK-0033E1's investigation showed a
single reload is normally sufficient once `db` is genuinely reachable).

---

## CDR RECOVERY CONTRACT

`harness_require_cdr_ready`: `module show like cdr_adaptive_odbc.so`
reports `Running`. A cheap module-state check, not a real CDR write, per
Phase 10's own instruction to avoid a real call inside every helper
invocation. Recovery: `module reload cdr_adaptive_odbc.so`, issued right
after the `res_odbc.so` reload (live log evidence: at cold/broken load,
`cdr_adaptive_odbc.c` logs `WARNING: No such connection 'snep' ... Check
res_odbc.conf` when `res_odbc` failed to connect -- reloading
`cdr_adaptive_odbc.so` after `res_odbc.so` has a confirmed live
connection re-binds it correctly).

Real-call CDR proof (Phase 14, required in validation rather than inside
the helper): already covered by existing suites exercised in both
regression runs below -- `call-smoke-test.sh`/`trunk-smoke-test.sh`
(real `Dial(PJSIP/...)` -> CDR row -> report readback) and
`backup-restore-dr-smoke-test.sh` ("post-restore call produced a NEW CDR
row", live-confirmed right after its own `--force-recreate` + the new
ODBC/CDR-ready check).

---

## SHARED HARNESS HELPER

Added to `scripts/lib/harness.sh` (naming follows Phase 3's own
suggested shape exactly):

- `harness_asterisk_cli_ready` / `harness_pjsip_ready` -- predicates.
- `harness_wait_asterisk_ready [attempts] [delay]` -- bounded wait for
  CLI then `res_pjsip.so` Running. Centralizes (for the new post-restart
  contract only; existing call sites were not refactored, out of scope)
  the same precondition many suites already re-implemented locally.
- `harness_odbc_active_connections <dsn>` -- prints the live connection
  count for one DSN section of `odbc show all`.
- `harness_require_odbc_ready [dsn]` / `harness_require_cdr_ready` --
  the two readiness predicates above.
- `harness_restore_asterisk_post_restart [dsn]` -- the one shared
  recovery contract every affected suite now calls:
  1. bounded wait for `db`'s container to be Up (`_harness_container_up`,
     an existing, credential-independent primitive -- see FAILURE
     SEMANTICS below for why this is deliberately *not* Compose's own
     `db` health status);
  2. if ODBC+CDR are already ready, return immediately (the common,
     self-healing case);
  3. otherwise `module reload res_odbc.so` then `module reload
     cdr_adaptive_odbc.so`, re-check, bounded retry up to 5 attempts
     (widened from an initial 3 during this task's own validation --
     see BOUNDED RETRY below);
  4. return 1 (never silently 0) if still not ready after all attempts.

Every affected suite calls `harness_wait_asterisk_ready &&
harness_restore_asterisk_post_restart` immediately after its own
restart/recreate operation, then classifies the result with
`harness_ok`/`harness_bad` (never silently swallowed) exactly like every
other check in that suite.

### Why `db` Up, not `db` Compose-healthy

The helper's DB-readiness precondition (Phase 6: "must not reload ODBC
while the DB is still unavailable") was initially implemented as
"`db` reports Compose `healthy`". Live validation against
`secret-rotation-smoke-test.sh` (whose own step 17 restarts `db`
immediately after rotating its credentials) exposed a false-negative:
`docker/healthcheck-db.sh` authenticates using
`MARIADB_ROOT_PASSWORD`/`MARIADB_PASSWORD`, which are baked into the
`db` container's own environment at container-*creation* time. A
non-recreating `restart` does not re-read `.env`, so right after a live
secret rotation, `db`'s own Docker health status can report `unhealthy`
against stale credentials even though the database itself -- and
Asterisk's own already-current `res_odbc.conf` -- are both genuinely
reachable and correct. Gating on Compose health produced a spurious
`FAIL` in exactly that (real, reproduced) scenario. The helper now
checks only that the `db` container is **Up** (the same primitive
`harness_require_containers` already uses), leaving the actual,
unambiguous readiness test to the reload-and-recheck loop itself, which
depends on nothing but the real ODBC connection outcome.

### Bounded retry

5 outer reload attempts (each followed by a bounded 5x2s recheck), not
3: live validation showed the reload-then-recheck sequence recovers on
the very first attempt in the overwhelming majority of trials, but one
observed trial under host load needed a second pass before succeeding.
Widening the bound costs nothing in the common fast-success path (each
attempt returns as soon as the check passes) while giving real headroom
for that outlier, rather than a narrower bound that could flake under
contention. No fixed `sleep N` was introduced anywhere in this
implementation -- every wait is a bounded, observable-condition retry
(`harness_retry`, already established in this codebase).

---

## FAILURE SEMANTICS

`harness_restore_asterisk_post_restart` returns non-zero on any
unrecovered failure. Every call site treats this as `harness_bad`
(occasionally `stop`/`bad` local wrappers around the same function),
never a silently-ignored return value -- the enclosing suite's overall
exit code becomes `FAIL` (1), which `scripts/regression.sh` already
surfaces per-suite in its final matrix without halting the rest of the
run (existing, unchanged behavior). The failure message is explicit:
*"Asterisk restarted successfully but ODBC/CDR runtime did not
recover"* -- distinguishing this class from a restart that itself failed
to converge.

---

## SEQUENTIAL-SUITE PROOF

The two full `make regression` runs below constitute the sequential-suite
proof for the previously-broken restart class: `readiness-smoke-test.sh`
runs near the end of the suite order and performs the bare, full-stack
`docker compose restart` that TASK-0033E1 confirmed breaks ODBC. Run 1
ended with `readiness-smoke` PASS (its own new step 7 repaired the
state before the suite exited). Run 2 started immediately afterward,
**with no `make down`/`make up` and no manual repair**, and its own
early suites (`call-smoke`, `trunk-smoke`, `dialplan-legacy-closure` --
all genuinely CDR-dependent) passed cleanly. This is the direct
before/after proof: without this task's fix, TASK-0033E's own validation
notes record exactly this handoff failing; with it, it does not.

Individually, before the combined regression runs, every one of the nine
affected suites was also run standalone (each from a stack freshly
reset to healthy) and passed with the new ODBC/CDR check reporting PASS,
covering every distinct restart mechanism in the matrix above at least
once in isolation.

---

## FULL-REGRESSION PROOF

Both runs performed strictly back-to-back, same stack, no `make down`/
`make up`/manual ODBC reload/manual Asterisk repair between them:

- **Run 1**: 35/36 suites PASS. One suite, `pjsip-lifecycle-smoke`,
  reported `BLOCKED` (`res_pjsip.so/chan_pjsip.so not both Running
  (checked 5 times over 8s)`) immediately after `pjsip-external-trunk-smoke`.
  This is a pre-existing, already-documented flake class unrelated to
  this task: `scripts/lib/harness.sh`'s own `harness_retry` doc comment
  (predating this task, TASK-0027) explicitly describes "querying
  `asterisk -rx 'module show like res_pjsip.so'` via a fresh `docker
  compose exec` immediately after another suite's own PJSIP config
  write/reload can transiently see incomplete output while that reload
  is still in-flight." Neither `pjsip-lifecycle-smoke-test.sh` nor
  `pjsip-external-trunk-smoke-test.sh` was touched by this task.
  `readiness-smoke`, `restart-smoke`, `wss-platform-smoke`,
  `tls-cert-management-smoke`, `transport-shared-runtime-ux-smoke`,
  `transport-smoke`, and `pjsip-runtime-status-smoke` -- every suite
  this task modified -- all reported PASS in this same run.
- **Run 2**: **36/36 suites PASS**, including `pjsip-lifecycle-smoke`
  (confirming run 1's blip was transient and unrelated) and every
  CDR-dependent suite immediately after inheriting run 1's post-restart
  state with zero manual repair.

`git diff --check`: PASS, no whitespace errors.
`git status --short`: only this task's own files touched (see CHANGES
below) -- confirmed clean before and after both regression runs.

---

## REMAINING DEBT

1. **`pjsip-lifecycle-smoke`'s PJSIP-reload race** (see FULL-REGRESSION
   PROOF above) -- pre-existing, unrelated to ODBC/CDR, already
   documented in this codebase's own `harness_retry` comments since
   TASK-0027. `FOLLOW_UP_DEBT`: widen that suite's own initial PJSIP
   readiness check bound (currently 5 attempts/8s, narrower than the
   10-15 attempts other suites use for the identical check) if it
   recurs.
2. **`secret-rotation-smoke-test.sh` is not safe to run twice in
   immediate succession without a stack reset.** Discovered during this
   task's own validation (not a regression this task introduced): its
   internal "declared original value" bookkeeping and the `db`
   container's baked-in healthcheck credentials can drift out of sync
   with reality if a second destructive run starts before the first
   run's containers have fully re-converged. `make rotate-secrets
   --force` reconciles it. `FOLLOW_UP_DEBT`, since this suite is already
   documented as a standalone, deliberately-run-once destructive target
   (not part of `make regression`), not a `make regression`-facing
   defect.
3. **`harness_wait_asterisk_ready` was added as a new, separate
   primitive rather than refactoring the ~7 existing local
   `pjsip_modules_running`-style re-implementations onto it.** Deliberate
   (Phase 3 scoped this task to the restart/recovery contract, not a
   broad harness refactor) -- `FOLLOW_UP_DEBT` if a future task wants to
   de-duplicate those.
4. **No new dedicated regression suite was added** (Phase 18's own
   permission: "If the existing restart suites themselves give
   sufficient deterministic coverage, avoid creating redundant tests").
   `readiness-smoke-test.sh`'s own step 6+7 already performs the exact
   sequence a dedicated suite would (full-stack restart -> shared
   helper recovery -> verify), and the two-consecutive-`make regression`
   proof above already exercises the real before/after handoff a
   synthetic single-suite test could only simulate. Adding a separate
   `asterisk-restart-odbc-recovery-smoke-test.sh` would duplicate this
   coverage without new signal.
