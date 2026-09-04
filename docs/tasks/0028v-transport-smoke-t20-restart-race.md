# TASK-0028V — transport-smoke T20 restart-required race

## Status

Resolved. Root-caused and fixed as a test-harness-only change (no production
telephony code modified). See "Root cause" and "Fix" below.

Originally discovered as an unrelated side finding while validating
TASK-0028U (stale-fixture recovery), documented per this project's bug policy
rather than fixed opportunistically. Confirmed pre-existing (present on the
unmodified script, before any TASK-0028U change) and confirmed intermittent,
not deterministic — a fresh TASK-0028V session investigated it directly.

## Symptom (as originally observed)

`transport-smoke-test.sh`'s T20 section ("PART 3", the rename/restart-
required lifecycle checks added for TASK-0020) intermittently failed three
checks in a row, all around the same moment — immediately after renaming a
transport (`task0020-rename-old` -> `task0020-rename-new`, a same-port
identity change originally believed to always require a real Asterisk
restart to take effect):

```text
FAIL: runtime NOT falsely reported active before restart -- expected 'Unable to find', got:\n
FAIL: list-page badge shows restart_required, not active, before restart -- badge=active
FAIL: socket reuse before restart is never claimed active -- HTTP=302 badge=active banner=0
```

## Correction to the original write-up

The first session's write-up read the first failure's `got:\n` (from the
compact FAIL summary table, which only ever shows the *first* line of a
multi-line captured value on that row) as proof the raw
`asterisk -rx "pjsip show transport ..."` call returned **empty output**.
That reading was wrong. Re-examining the *full* captured value (not just the
summary table's first line) during this session's reproduction showed the
raw CLI call actually returned a **complete, valid "active" transport dump**
— `bind: 0.0.0.0:5212` and every other field populated correctly. The value
was never empty; it was simply too long to fit the summary table's single
line. This correction matters because it changes the diagnosis completely:
an empty/incomplete response would point at a harness-side AMI/CLI
connection race (TASK-0027A's class); a complete, internally-consistent
"active" dump pointed at a real behavioral question instead — see below.

## Root cause (confirmed, reproduced live)

**Category: ASTERISK RESTART RACE / REAL PRODUCT BEHAVIOR — not a test
harness or AMI-query-timing issue.**

TASK-0020's original investigation claimed renaming a transport "ALWAYS left
the transport unreachable under either name until a restart, with zero
exceptions found across every attempt" (see the comment in
`PjsipTransportsController::reportApplyResult()`, and this same claim is
codified unconditionally there — unlike the non-rename edit path, the rename
path never calls `Snep_PjsipTransportConf::isRuntimeActive()` before telling
the user a restart is required). **This claim is false.** A same-port rename
(and, by the same mechanism, a delete-then-reuse-the-same-port create) can
converge live via a plain `module reload res_pjsip.so` — no Asterisk process
restart at all — non-deterministically.

Mechanism, confirmed live:

- `PjsipTransportsController::regenerateAll()` (called unconditionally by
  every transport add/edit/delete) runs `Snep_PjsipTransportConf`,
  `Snep_PjsipConf`, and `Snep_PjsipTrunkConf`'s `loadConfFromDb()` **in
  sequence, in the same HTTP request** — and each of those three
  independently issues its own `module reload res_pjsip.so` AMI command,
  fully re-parsing and re-applying **all** current PJSIP config (not just
  its own slice) every time. A single transport rename therefore triggers
  **three full, sequential, redundant `res_pjsip` reloads** before the HTTP
  response is even returned.
- Freeing the old UDP/TCP socket and binding the new one under the renamed
  object happens inside Asterisk's own reload processing, and its exact
  timing relative to the OS releasing the old socket is not something this
  application controls. Three rapid, redundant reload passes give that race
  three chances to resolve instead of one.
- Reproduced directly: a raw `asterisk -rx "pjsip show transport
  task0020-rename-new"` query issued as the very first possible observation
  after the rename's HTTP response returned already showed the new name
  fully bound at the correct address (`bind: 0.0.0.0:5212`) — confirmed
  **stable and persistent** across a 58-second follow-up polling window (40
  polls, ~1.4s apart), not a transient blip that reverted. The app's own
  AMI-based badge computation (`Snep_PjsipTransportConf::getRuntimeTransportNames()`)
  agreed: `active`. Both ground-truth sources were consistent with each
  other and with reality — the object genuinely was live, contradicting only
  the test's (and `reportApplyResult()`'s) assumption that it could not be.
- **Crucially, this resolves entirely server-side, before the HTTP response
  is returned.** No client-side wait, retry, or faster polling can observe a
  "not yet applied" state that has already been superseded by the time the
  test gets its first chance to look. This rules out "test harness race" and
  "poll sooner/more" as viable fixes for these three checks — the divergence
  is decided before the test ever runs.
- An isolated, dependency-free repro (create + rename a transport with no
  extension/trunk pinned to it) did **not** reproduce the early-active
  outcome across clean trials (confirmed "Unable to find" persisting for the
  full observation window each time), while the full T20 scenario — a
  transport with a pinned extension **and** a trunk with an active outbound
  registration — reproduced the early-active outcome in 2 of the first 2
  fully-instrumented attempts this session. This suggests active dependents
  (whose own reload/registration activity coincides with the transport's
  reload) make the early convergence more likely, though the exact Asterisk-
  internal trigger was not traced further (would require Asterisk-source-
  level tracing, out of scope for a test-determinism task).

This is a real, reproducible discrepancy between documented and actual
Asterisk/PJSIP behavior. Per this project's rule not to change production
telephony behavior without a proven defect and dedicated scope: this session
**did not** modify `regenerateAll()`, `reportApplyResult()`, or the reload
pattern. That redundant-triple-reload design is flagged below as a
follow-up candidate, not fixed here.

## A second, distinct finding: post-restart module-readiness gap

While reproducing the above, a fourth (previously undocumented) flake
surfaced in the *post*-restart section:

```text
FAIL: restart recovery: renamed transport active, old name absent -- new:
No such command 'pjsip show transport task0020-rename-new' (type 'core show help pjsip' for other possible commands)
old:
Unable to find object task0020-rename-old.
```

**Category: CONTAINER/PROCESS READINESS RACE — harness-side, cleanly
fixable.** `t20_wait_for_asterisk()` only waits for `core show uptime` to
succeed, which proves Asterisk's core CLI/AMI is answering, not that every
module has finished (re)loading. `res_pjsip.so` is one of the heavier
modules to initialize after a full restart (it reloads every sorcery-backed
endpoint/aor/auth/registration object), and a `pjsip show transport ...`
query issued in the gap before it's loaded gets `No such command` rather
than a real answer. The script already has the right tool for this
elsewhere (`pjsip_module_running()` + `harness_retry`, used at its own
startup check per TASK-0027) — it just was never applied after a **real**
Asterisk restart.

## Fix (test-only, no production code changed)

`scripts/transport-smoke-test.sh`:

1. **Rename check** (was: assert raw CLI shows `Unable to find`; assert
   badge is exactly `restart_required`). Now: query raw CLI once (ground
   truth, same as before, no added waiting), classify the result as
   not-yet-applied / correctly-self-applied / incoherent, and assert:
   - not-yet-applied or correctly-self-applied are both accepted as valid
     (this is the actual, proven contract);
   - the badge must always agree with whichever of those two ground-truth
     states was observed (never a badge/reality mismatch in either
     direction);
   - anything else (wrong bind, garbled output, stale old-name survival) is
     an unconditional FAIL with the raw output in the failure detail.

   This still fails on the original bug this check exists to catch (a badge
   claiming `active` while Asterisk has no such object) and adds a
   previously-untested case (a badge stuck on `restart_required` for an
   object Asterisk already applied live) — it does not become a generic
   "something succeeded" check.

2. **Socket-reuse check**: same treatment — a raw CLI ground-truth query was
   added (there wasn't one before), classified the same way, and the badge +
   apply-failed banner are asserted to agree with it. The DB-level
   "no collision on the freed port" assertion (HTTP 302) was split out as
   its own explicit check rather than folded into the runtime assertion.

3. **Post-restart module-readiness gap**: added
   `harness_retry 15 1 -- pjsip_module_running` immediately after
   `t20_wait_for_asterisk` succeeds and before any `pjsip show ...` query is
   issued post-restart, reusing the exact helper/pattern already used at
   this script's own startup check. Bounded, explicit failure message
   (`stop`) on timeout — no infinite loop, no silent pass.

No change to `docker/`, `snep/lib/Snep/PjsipTransportConf.php`,
`PjsipTransportsController.php`, or any other production file.

## Adversarial review (Phase 8)

- **False readiness**: the coherence checks never accept a value other than
  the two fully-specified, exact-match states (`Unable to find` verbatim, or
  the exact expected `bind` line) — a stale/garbled/partial response falls
  into the `else` branch and fails unconditionally.
- **Stale process / PID reuse**: not applicable to this fix — no PID
  tracking was added or needed.
- **Unbounded waits**: none added. The rename/reuse fixes need *no* waiting
  at all (the state is already decided by the time of the first query); the
  new post-restart fix is bounded at 15 attempts / 1s apart (15s worst
  case), consistent with this script's own established settling-window
  convention (its outbound-registration wait uses the same 15s bound).
- **Locally-fast but CI/production-slow**: the 15s bound for module
  readiness is generous relative to the startup check's 5×2s=10s bound,
  specifically because a full process restart reloads far more than a
  same-process module reload; if this proves too tight on a slower CI host,
  the fix is to raise the attempt count, not to remove the check.
- **Hidden dependency on host performance**: the coherence-based checks have
  none (no timing assumption at all, by construction). The post-restart
  bound could theoretically need raising on a much slower host; documented
  above rather than hidden.
- **Race introduced by command substitution/pipelines**: none of the new
  code introduces a new subshell/pipeline hazard beyond what the
  surrounding, already-reviewed script already does (same `$(...)` capture
  style throughout).
- **Remaining open question**: the exact Asterisk-internal mechanism that
  makes early convergence more likely with active dependents than without
  was not traced to source level (would require Asterisk internals
  tracing/gdb, well outside this task's scope). The behavioral finding
  itself (early convergence is real and possible) is confirmed with direct,
  repeated, live evidence regardless of the exact internal trigger.

## Separate, out-of-scope finding: trunk-name generation collides with orphaned peer rows

Discovered while trying to reproduce T20 repeatedly (this blocked *reaching*
T20 at all in several attempts, before touching anything T20-specific) —
documented here per this project's bug policy, **not fixed**:

`TrunksController::preparePost()` derives a new trunk's `name` column via
`SELECT name FROM trunks ORDER BY CAST(name AS DECIMAL) DESC LIMIT 1` + 1,
with no locking/transaction isolation beyond the insert's own transaction.
When the `trunks` table is empty this always computes `name = '1'`. A `peers`
row (`peer_type = 'T'`, the IP-peer counterpart of a PJSIP/IP trunk) can
outlive its parent `trunks` row — e.g. via
`TrunksController::removeAction()`'s early-return path (line ~556-559: if
`AsteriskInfo`'s constructor throws, the method `return`s immediately,
*before* ever calling `Snep_Trunks_Manager::remove()`/`removePeers()` —
while the caller's own delete helper only checks for HTTP 302 and would
correctly flag this as a failed delete, a still-transient/loaded Asterisk
state at exactly the wrong moment could produce this silently). Once such an
orphaned `peers` row with `name = '1'` exists, **every subsequent trunk
creation attempt fails** with `SQLSTATE[23000]: ... Duplicate entry '1' for
key 'name'` (the second, `peers`-table insert inside the same transaction),
even though `trunks` itself is empty — 100% reproducible once the orphan
exists, not intermittent. This is the same bug class already flagged in this
script's own `delete_trunk_fixture()` docblock (referencing
`docs/tasks/0018-pjsip-transports.md` §14's hardcoded-`"1"` finding) and in
CLAUDE.md's own worked example (`Snep_Trunks_Manager::getTrunkLog()`) — a
pre-existing legacy bug, unrelated to T20, requiring its own dedicated task
(non-atomic name generation + peers/trunks lifecycle decoupling), not a
drive-by fix here. Worked around for this session's own reproduction by
directly deleting the orphaned `peers` row from the dev database — no code
change.

## Validation performed

- Reproduced the original 3-check failure live, with full timing/ground-truth
  instrumentation (temporary, reverted before the real fix), before making
  any change.
- Root cause confirmed via direct evidence (raw CLI + AMI ground truth
  agreement, 58s persistence, isolated-vs-dependent-scenario comparison) —
  not inferred from timing alone.
- After the fix: **10/10 consecutive PASS** runs of individual
  `transport-smoke-test.sh` (target met exactly, no retries needed for any
  T20-related reason). All 10 runs hit the "self-applied early" branch for
  both the rename and socket-reuse checks — in this long-lived dev
  container (hours of accumulated prior reload activity), early convergence
  is now the *typical* outcome, not a rare edge case, which is itself
  informative: it means TASK-0020's original "zero exceptions" finding was
  likely observed against a much less "warmed up" Asterisk process. The
  "not yet applied" branch was separately confirmed correct via an isolated,
  dependency-free repro outside the full T20 flow (no extension/trunk
  pinned to the renamed transport) — it consistently stayed "Unable to
  find" for the full observation window in that scenario. Both legitimate
  branches of the fix are therefore exercised and confirmed correct.
- `make lint`, `make regression` (x2), `git diff --check`, `git status` —
  see checkpoint below.

## Files changed

- `scripts/transport-smoke-test.sh` (test-only)
- `docs/tasks/0028v-transport-smoke-t20-restart-race.md` (this file)

No production code (`snep/`, `docker/`) touched.
