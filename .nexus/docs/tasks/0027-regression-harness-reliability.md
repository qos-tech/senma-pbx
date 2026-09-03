# TASK-0027 — Regression harness reliability

## 1. Why this task exists

TASK-0026B's own validation exposed reliability problems in the harness
layer itself, not the product: stale fixtures blocking later runs,
interrupted runs leaving state behind, suites completing their
operational flow but never printing a final summary, cleanup inferred
from HTTP 200 alone, assertions depending on translated UI text, cleanup
that doesn't respect resource dependencies, and no single trustworthy
serial release-regression gate. TASK-0027 is a harness-reliability task,
not a product feature or security-remediation task -- no TASK-0026C+
finding was touched.

## 2. Harness inventory (as found, before modification)

| Suite | Makefile target | Script | Fixtures | Cleanup | Known issues found |
|---|---|---|---|---|---|
| lint | *(missing)* | — | — | — | did not exist |
| preauth-security | `preauth-security-smoke` | `preauth-security-smoke-test.sh` | none (mutates/restores `setup.conf`) | `trap ... EXIT`, unconditional | `set -euo pipefail` could abort before the final summary line |
| authorization-coverage | *(missing, invoked only from authorization-smoke)* | `authorization-coverage-check.sh` | none (static, read-only) | n/a | none (already deterministic) |
| authorization-smoke | `authorization-smoke` | `authorization-smoke-test.sh` | 1 reusable DB user (`task0026a-restricted`) | inline DB reset + `rm` tmpdir | `set -euo pipefail`; `permission_page()` matched translated "You do not have permission" text |
| http smoke | `smoke` | `smoke-test.sh` | reuses seeded `admin` | `trap ... EXIT` (temp files) | FATAL paths used raw `exit 1`, no BLOCKED concept |
| call-smoke | `call-smoke` | `call-smoke-test.sh` | 2 extensions + 2 baresip containers | `trap cleanup EXIT` | TASK-0026A: "runner disconnected after hangup, not retried" (unreproduced when run directly — see §4) |
| trunk-smoke | `trunk-smoke` | `trunk-smoke-test.sh` + `trunk-smoke-route.php` | 1 trunk, 1 extension, 2 routes, 1 baresip container | `trap cleanup EXIT` | **stale-fixture recovery bug** (route→trunk dependency, §5); `delete_trunk` hardcoded `name="1"` |
| transport-smoke | `transport-smoke` | `transport-smoke-test.sh` | up to 6 transports, 2 extensions, 2 trunks | 3 chained `trap 'x; y; z' EXIT` | none in the cleanup logic itself; a genuine transient Asterisk-CLI flake was observed (§4) |
| restart-smoke | `restart-smoke` | `restart-smoke-test.sh` | 2 extensions, 2 DB users | 2 chained `trap 'x; y' EXIT` | **no stale-fixture recovery at all** (hard `stop()`, §5); stale `Objects found: 2` assertion; retry added for a real post-restart timing race |
| external-failure-smoke | `external-failure-smoke` | `external-failure-smoke-test.sh` | none (config-value backup/restore + local router) | `trap ... EXIT` | none found |
| external-content-smoke | `external-content-smoke` | `external-content-smoke-test.sh` | none (config-value backup/restore + local router) | `trap ... EXIT` | none found |

Every stateful script used `set -uo pipefail` (no `-e`) **except**
`authorization-smoke-test.sh` and `preauth-security-smoke-test.sh`,
which used `set -euo pipefail` — the one concrete instance of "`set -e`
can bypass the final summary" the task asked to look for.

## 3. Standard result classification

Implemented once, in `scripts/lib/harness.sh`, sourced by every
stateful script:

| State | Exit code | Meaning |
|---|---|---|
| PASS | 0 | behavior verified, required cleanup completed |
| FAIL | 1 | product behavior did not meet expectations, **or** required cleanup failed |
| BLOCKED | 2 | environment/fixture/dependency/precondition problem — could not validly execute |
| INCONCLUSIVE | 3 | interrupted, or exited before its own designed completion point |

`scripts/regression.sh` maps these back to their names for the final
matrix and never treats a nonzero exit as PASS. `smoke-test.sh` keeps
its own established PASS/FAIL/EXPECTED_LIMITATION per-flow bookkeeping
(a real third state worth preserving) and bridges its final tally into
one `harness_ok`/`harness_bad` call so the overall classification is
still correct. `authorization-coverage-check.sh` is a stateless static
check and needs no lifecycle wiring — its native 0/1 already fits.

## 4. Cleanup / finalization contract

- `harness_install_traps` (called first, before any fixture exists)
  installs `trap harness_finalize EXIT` plus `INT`/`TERM` traps that
  attempt cleanup and finalize before re-raising.
- `harness_register_cleanup "<description>" "<command>"` (required) /
  `harness_register_best_effort_cleanup` (best-effort, e.g. disposable
  baresip containers or temp files) — registered **immediately after
  each fixture is confirmed created**, run in **LIFO** order at
  finalize. Because every dependent fixture in this codebase is created
  *after* the object it references (a route is created after its
  trunk; a UX-part extension after its transport), plain
  creation-order registration + LIFO execution reproduces
  dependency-correct cleanup order automatically, with no special-casing.
- A required cleanup failure downgrades an otherwise-PASS run to FAIL
  (`_HARNESS_CLEANUP_FAILED`) — never silently PASS.
- `harness_blocked "<reason>"` and `harness_complete` are the two
  designed exit points; anything else (an unset-variable abort, an
  uncaught error) falls through to the `EXIT` trap and is classified
  INCONCLUSIVE, never PASS, unless a FAIL was already recorded.
- Trap recursion is avoided: `harness_finalize` clears all three traps
  and sets a `_HARNESS_FINALIZED` guard before doing anything else.

**Real bug found and fixed during this task's own implementation**: in
an early version of `restart-smoke-test.sh`, a *separate*
`harness_register_best_effort_cleanup` for the admin session cookiejar
was registered *before* the main fixture-cleanup registration. LIFO
execution order therefore deleted the cookiejar **before** `cleanup()`
tried to use it to authenticate the extension-delete HTTP calls — every
delete silently rendered the (unauthenticated) login page at HTTP 200
instead of returning 302, and cleanup was correctly reported FAIL. Fixed
by removing the redundant registration (the main `cleanup()` function
already owned that file's lifecycle). Verified by full re-run (§8). This
is exactly the "cleanup inferred from HTTP 200 alone" failure mode named
in TASK-0027's own motivation — reproduced by the harness-building work
itself, not by the product.

## 5. Fixture ownership and dependency-aware cleanup

Every fixture is identified by a unique marker (fixed secret/callerid/
description string per suite) captured into its real persisted ID
immediately after creation — never broad pattern deletion.

**Trunk-smoke stale-fixture recovery (the scenario TASK-0027 named
explicitly)**: the dependency graph is `outbound route → trunk`,
`inbound route → trunk AND extension` (confirmed by reading
`TrunksController::removeAction()`/`ExtensionsController::removeAction()`,
both of which query `Snep_*_Manager::getValidation()` and refuse
deletion while a route still references the object). The *old*
preflight checked for a stale trunk first and called `stop()`
immediately — it never even looked for the dependent route fixtures,
so a trunk left behind by any interrupted run permanently blocked every
later run. Fixed: stale-fixture discovery/removal now runs
dependency-first — outbound route, then inbound route (both via the
already-existing `PBX_Rules::delete()` path,
`scripts/trunk-smoke-route.php`), *then* the trunk, *then* the
extension — mirroring the order the normal-path cleanup already used
correctly.

This was **not a hypothetical fix**: the very first live run of the
rebuilt `trunk-smoke-test.sh` (§8) found a genuine leftover trunk
(id=58, name="1") + route (id=24) + extension (1099) sitting in the dev
database from a prior interrupted run, recovered from it automatically,
and completed a clean PASS. A second, deliberate `SIGKILL` mid-run (to
simulate an unrecoverable crash, not just a graceful interrupt) left a
trunk/route/extension/stray-container behind; the very next run
recovered from that too, with a full PASS. No raw SQL DELETE was used
anywhere in either recovery path.

**`delete_trunk` name-derivation bug** (Phase 6): the harness's own
`delete_trunk()` hardcoded the trunk's `name` field to the literal
`"1"`. `TrunksController::removeAction()` deletes the matching `peers`
row using whatever `name` the POST sends, **not** a DB lookup by id —
any run where the auto-generated trunk name wasn't literally `"1"`
silently left the `peers` row behind after an apparently-successful
cleanup. Fixed to look up the real persisted `name` from `trunks` right
after creation and pass that captured value to every subsequent delete
call, matching the pattern `transport-smoke-test.sh`'s own
`delete_trunk_fixture()` already used correctly. This is a harness-side
fix only — `TrunksController` itself was not touched (see §9 for why
that controller behavior is flagged as separate product debt, not
remediated here).

**Restart-smoke had no recovery logic at all** for its own extension
fixtures (a hard `stop()`, no secret-marker check). Live-confirmed: a
genuine leftover extension (1096, secret `task0021-fixture-a`) was
found in the dev database from an earlier run. Fixed to use the same
secret-marker recovery pattern `call-smoke-test.sh`/`trunk-smoke-test.sh`
already established.

## 6. Supported cleanup paths / product debt discovered, not fixed

Per this task's own instruction, no product controller was modified.
Debt discovered and intentionally left alone:

- `TrunksController::removeAction()` deletes the `peers` row using the
  client-POSTed `name` field rather than deriving it from the trunk id
  server-side — already flagged by TASK-0026's audit (F9 root-cause
  area, mass-assignable `name`). The harness now always sends the
  correct value; the controller's own trust of client input is
  unchanged.
- `UsersController::addAction()`/`Snep_Users_Manager::add()` fatal
  under PHP 8.4/strict SQL — already documented in TASK-0022 §8.
  `restart-smoke-test.sh`'s authorization fixtures still use direct SQL
  for this one reusable dev-only pair of users, exactly as TASK-0022
  justified, and `authz_cleanup()` reverses it the same way.
- `snep/lib/Zend/Validate/Isbn.php` uses `$str{$i}` curly-brace string
  offsets, removed in PHP 8.0 — a genuine, pre-existing syntax error in
  a **vendored** Zend Framework 1 file (confirmed via `php -l` while
  building `scripts/lint.sh`). CLAUDE.md's own "Current operating rule"
  explicitly defers "curly-brace migration" to a future, separately
  authorized task, so `lint.sh` scopes its `php -l` sweep to the
  project's own maintained code and excludes `snep/lib/Zend/` and
  `snep/lib/linfo/` (also third-party, Linfo (c) 2010-2015 Joseph
  Gillotti) by path, rather than papering over the finding — both are
  named explicitly in the script's own comment.
- A restart-readiness/config-reload timing gap: a config-reload-
  dependent action (`ExtensionsController::removeAction()` →
  `Snep_PjsipConf::loadConfFromDb()` → AMI `module reload res_pjsip.so`)
  was observed, twice, to fail immediately after
  `Snep_Asterisk_Operations::getRestartState()` had already reported
  `RUNNING` (uptime as low as 37s). This is TASK-0021's own
  restart-readiness signal, a product/telephony concern out of this
  task's scope — mitigated at the harness level with a bounded 3×2s
  retry in `restart-smoke-test.sh`'s own cleanup (harmless if never
  needed, and it never masks a genuinely persistent failure since 3
  attempts still fail loudly).

## 7. Language-independent assertions

`authorization-smoke-test.sh`'s `permission_page()` helper re-fetched
`/permission/error` and matched `PermissionController`'s translated
"You do not have permission…" text (English/pt-BR alternates).
Replaced with `redirects_to_permission_error()`, which checks the
*original* denied request's own `Location:` header —
`PermissionPlugin::preDispatch()` always calls
`gotoSimpleAndExit("error", "permission", "default")` on denial, so the
redirect target itself is a stable, language-independent, and *more
precise* signal (it proves this specific request was denied, not merely
that visiting the error page independently renders expected content).
Two redundant checks that combined a status code with a negated
translated-text match were simplified to the status-code check alone,
since the 302→`permission/error` signature already fully distinguishes
denial from success. "SNEP - Login" (used elsewhere in this suite and
in `smoke-test.sh`) was checked against `login.phtml` and confirmed to
be a static, untranslated `<title>` tag — left as-is, a valid structural
marker.

## 8. Call-smoke finalization (Phase 8)

TASK-0026A recorded: *"runner disconnected after successful fixture
provisioning, registration, call establishment and hangup; not
retried."* Running the rebuilt `call-smoke-test.sh` directly, twice,
end to end (29s and 36s wall-clock) produced a full summary and correct
exit code both times — the failure was not reproduced. This was very
likely the invoking session/tool disconnecting, not a control-flow
defect in the script (29-36s total runtime rules out a naive 2-minute
timeout theory, but any external disconnect of the invoking shell would
explain "reached hangup, then nothing" without a script-side cause).

Hardened as defense-in-depth regardless, matching this phase's
contract: `harness_install_traps` (SIGINT/SIGTERM now always attempt
cleanup and print a classified summary before exiting, not just EXIT);
every host-side `docker build`/`docker run` call that could hang forever
is now wrapped in `harness_timeout` (see next paragraph) so no single
step can block the whole run indefinitely.

**Portability bug found while adding those timeouts**: the host these
scripts run on is macOS's stock `/bin/bash`, which does **not** ship
GNU coreutils `timeout` — the first attempt to wrap `docker build`/
`docker run` in `timeout N ...` failed immediately with `timeout:
command not found`, correctly classified BLOCKED (zero fixtures
created, clean exit) rather than silently hanging or corrupting state.
Fixed with `harness_timeout()`, a portable job-control-based
reimplementation in `scripts/lib/harness.sh` (background the command,
race a `sleep N; kill` watchdog, `wait`). Commands that already run
*inside* a Debian container via `docker exec`/`sh -c "..."` keep using
the real `timeout` binary there (that container has coreutils) —
only host-side wrapping needed the portable version.

## 9. Aggregate regression order (`make regression` / `scripts/regression.sh`)

```
lint → preauth-security → authorization-coverage → authorization-smoke
→ http-smoke → call-smoke → trunk-smoke → transport-smoke → restart-smoke
→ external-failure-smoke → external-content-smoke
```

Suites run strictly serially, never in parallel — confirmed necessary,
not merely cautious: running `external-content-smoke-test.sh` while
`restart-smoke-test.sh` was mid-restart (an accident during this task's
own validation, not intentional) produced a spurious HTTP 500 on
`systemstatus` with zero product defect behind it, because Asterisk was
genuinely unavailable for that instant. `scripts/regression.sh` never
skips a suite regardless of an earlier suite's outcome (every suite
re-validates its own preconditions independently), and treats any
nonzero exit — FAIL, BLOCKED, or INCONCLUSIVE alike — as non-green in
the final aggregate.

## 10. Exact files changed

New:
- `scripts/lib/harness.sh` — shared classification/cleanup/signal library
- `scripts/lint.sh`, `scripts/regression.sh`
- `scripts/preauth-security-smoke-test.sh` (TASK-0026B, pre-existing
  uncommitted work at task start; rebuilt onto the harness lib here)
- `docs/tasks/0027-regression-harness-reliability.md` (this file)

Modified (harness/lifecycle rebuild onto `scripts/lib/harness.sh`,
plus the specific fixes named above):
- `scripts/smoke-test.sh`
- `scripts/authorization-smoke-test.sh`
- `scripts/call-smoke-test.sh`
- `scripts/trunk-smoke-test.sh`
- `scripts/transport-smoke-test.sh`
- `scripts/restart-smoke-test.sh`
- `scripts/external-failure-smoke-test.sh`
- `scripts/external-content-smoke-test.sh`
- `Makefile` — added `authorization-coverage`, `lint`, `regression` targets

Not modified: `scripts/authorization-coverage-check.sh` (already
deterministic, stateless, no fixture lifecycle to fix),
`scripts/trunk-smoke-route.php`, and no product PHP controller/model
file.

## 11. Validation results

Individual suites, run live against the dev Docker environment,
in isolation, after each fix:

| Suite | Result | Notes |
|---|---|---|
| lint | PASS | 265 project PHP files (Zend/linfo vendor dirs excluded, see §6), 13 shell scripts, 3 resources.xml, clean `git diff --check` |
| authorization-coverage | PASS | full controller/action inventory |
| authorization-smoke | PASS | 17 checks, Location-header assertions verified on both the denied and restored-after-restart cases |
| preauth-security | PASS | 10 checks |
| call-smoke | PASS (×2) | 18 checks each run; finalization proof, see §8 |
| trunk-smoke | PASS (×3) | organic stale-fixture recovery, then a deliberate SIGKILL-recovery proof, then a clean run; 23 checks each time |
| transport-smoke | BLOCKED then PASS | first attempt hit a transient `res_pjsip.so not Running` Asterisk-CLI flake (zero fixtures created, clean exit — the classification worked exactly as designed); the very next attempt passed with all 63 checks (includes a real controlled Asterisk restart) |
| restart-smoke | FAIL → FAIL → PASS (×2 more) | see §4/§5/§6 for the three distinct real issues found and fixed across these runs; final two runs both fully PASS (37 checks each) |
| external-failure-smoke | PASS | 27 checks |
| external-content-smoke | FAIL (parallel-run artifact) → PASS | see §9; PASS in isolation, 14 checks |

## 12. First full `make regression` result

Two genuine timing-related flakes surfaced only under `make
regression`'s back-to-back conditions (never seen running any suite
standalone) and are recorded here rather than hidden:

- **Run attempt 1** (before the fixes in this section existed):
  `transport-smoke` reported BLOCKED — `module show like res_pjsip.so`
  transiently returned no "Running" match immediately after
  `trunk-smoke`'s own trunk-deletion-triggered PJSIP reload. Zero
  fixtures were created before the BLOCKED classification fired, and
  cleanup ran cleanly — exactly the intended behavior, just with a
  precondition check that wasn't yet resilient to this class of race.
- **Run attempt 2** (after adding `harness_retry` to the module-state
  checks): all 11 suites PASSed except `call-smoke`, which FAILed —
  `pjsip show endpoint 1003` transiently reported "not found"
  immediately after its own reload, while `pjsip show aor 1003`
  (checked moments later, same reload) already succeeded. Cleanup ran
  cleanly; no fixture was left behind.

Both are the same underlying phenomenon: a PJSIP module reload is not
atomic from the perspective of a query issued via a freshly-spawned
`docker compose exec`, and `make regression`'s serial-but-back-to-back
suite execution has no settling gap between suites. Fixed by extending
the same bounded `harness_retry` (5 attempts, 1-2s apart) to
`call-smoke-test.sh`'s and `trunk-smoke-test.sh`'s post-reload
`pjsip show endpoint`/`pjsip show aor` checks, matching the pattern
already applied to the module-Running preconditions. This is a bounded
retry on a *check*, not a weakened assertion — a genuinely failed
reload still fails after all attempts are exhausted.

**Official first full run** (after both fixes, from a verified-clean
environment): **PASS** — all 11 suites PASS.

```
SUITE                          RESULT
----------------------------------------------------------------
lint                           PASS
preauth-security               PASS
authorization-coverage         PASS
authorization-smoke            PASS
http-smoke                     PASS
call-smoke                     PASS
trunk-smoke                    PASS
transport-smoke                PASS
restart-smoke                  PASS
external-failure-smoke         PASS
external-content-smoke         PASS
----------------------------------------------------------------
REGRESSION                     PASS
```

## 13. Second consecutive `make regression` result

Run back-to-back against the same environment, with no manual cleanup
between runs: **PASS** — all 11 suites PASS again, identical matrix to
§12.

## 14. Residual fixture / environment health checks

Checked immediately after both full-suite runs:

- `peers`: no rows for any smoke extension (1002/1003/1094/1096-1099).
- `trunks`: empty.
- `regras_negocio`: no rows matching any suite's fixture `desc` marker.
- `pjsip_transports`: exactly the 3 baseline seeded rows (`tcp`, `udp`,
  `wss`) — no leftover test transport.
- `users`: only `admin` and the one deliberately-persistent
  `task0026a-restricted` reusable dev fixture (by design, see §5) — no
  other leftover user.
- No stray `senma-*`/baresip Docker containers.
- `core show channels count`: 0 active channels, 0 active calls.
- `pjsip show transports`: `Objects found: 3` (tcp/udp/wss, as expected).
- `odbc show all`: 1 active connection (healthy).
- `app`/`asterisk`/`db`/`provider` containers all report `healthy`.
- `grep -c "Fatal error" mag-error.log`: 0 before and 0 after both runs
  — no new PHP Fatal Errors were introduced.

## 15. Scope discipline

No TASK-0026C/D/E finding was remediated. No product controller/model
file was modified. No SQL/shell/PJSIP-config injection finding was
touched. The only non-test-harness files this task's diff should show
are `Makefile` (new targets) and this documentation file.
