# TASK-0021 — Explicit Asterisk restart control

## Status

**Investigation only — not implemented.** No runtime code, views,
Docker configuration, AMI permissions, or tests were modified during
this phase. Every finding below comes from reading the current
committed code (`HEAD` = `518cded`, "fix: make PJSIP transport runtime
state explicit") and from live experiments against the running `make
dev` environment: real PHP scripts using the actual `PBX_Asterisk_AMI`
class over the real AMI TCP channel (port 5038, **not** the
`asterisk -rx` CLI/manager UNIX socket used throughout TASK-0018/0019/
0020), a genuine PJSIP call established through two `baresip` test
containers and hung up deliberately mid-test, and direct log/CLI
inspection throughout. All test fixtures (extensions 1002/1003,
baresip containers) were created and removed through SENMA's own real
HTTP flows; the environment was verified clean afterward (`pjsip show
transports` shows exactly `udp`/`tcp`, 0 active channels, no leftover
containers). Stopping here — awaiting approval before any
implementation.

Goal: design the smallest safe administrative mechanism for an
**explicit, operator-initiated** Asterisk restart, primarily to apply
transport changes TASK-0020 proved cannot be hot-reloaded. This is
**not** automatic restart after save.

---

## 1. Restart mechanisms in this Asterisk 22.10.1 build

Tested live via AMI `Command()` (the same primitive
`Snep_Pjsip*Conf::reload()` already uses for `module reload
res_pjsip.so`):

| Command | Mechanism | AMI `Command()` behavior observed |
|---|---|---|
| `core restart now` | Immediate restart, does not wait for anything | Returns in ~26ms–1.1s with an **empty array** (no `Response:` line at all — the connection is torn down before a framed AMI response can be read) |
| `core restart gracefully` | Waits for active calls to end before actually restarting | Returns only after PHP's `default_socket_timeout` (60s) elapses, then also an **empty array** — but for a completely different reason (see §4) |
| `core restart when convenient` | Not tested live (would require an even longer-lived call than the test window used) | Documented Asterisk CLI behavior: restarts as soon as no calls are active, but — unlike `gracefully` — does **not** stop new calls from being accepted while waiting. Not independently verified in this environment; treat as unverified for implementation purposes. |
| A dedicated AMI restart action | Searched via `manager show commands` (already done in TASK-0020) | **Does not exist.** Restart, like the transport `reload`, must go through the generic `Command` action with a CLI string. There is no structured `Restart` AMI action analogous to `Reload`. |

**Critical, previously-unverified finding this task establishes:** every
prior restart test in TASK-0020 used the Asterisk CLI/manager UNIX
socket (`docker compose exec asterisk asterisk -rx "..."`), not the
AMI TCP protocol the actual web application uses. The two channels
behave differently enough (see §4) that CLI-socket-only testing would
have produced a materially wrong implementation plan.

---

## 2. Active-call detection

No existing helper exists in `SystemstatusController.php` or
`AsteriskInfo.php` beyond raw `Command()` calls — confirmed by reading
both files in full. `core show channels count` (already used by
`call-smoke-test.sh` and by the live tests in this investigation)
returns a small, fixed 3-line text block:

```
N active channels
N active calls
N calls processed
```

This is the same primitive `call-smoke-test.sh` already parses
reliably. `AsteriskInfo::status_asterisk()` and `CloudNotice()` show
the codebase's existing pattern for wrapping a raw `Command()` call in
a small parsing helper — a new `getActiveCallCount()`-style method
follows that exact precedent, not a new architecture. `CoreStatus`/
`Status` AMI actions were not tested; the CLI-text approach is
sufficient, deterministic, and already proven, so there is no reason
to introduce a second mechanism.

---

## 3 & 4. Registration/session/AMI/ODBC impact, and graceful restart with a real active call

This is the centerpiece live test of this investigation. A genuine
call was established (`PJSIP/1002` → `PJSIP/1003`, both real
extensions provisioned through `ExtensionsController::addAction()`,
both registered via real `baresip` containers, confirmed `Up`/bridged
via `core show channels verbose`), then `core restart gracefully` was
issued over the **real AMI channel** from a PHP script using
`PBX_Asterisk_AMI::getInstance()`.

**Observed timeline:**

1. `Command("core restart gracefully")` issued.
2. Within ~5 seconds, **every** CLI/AMI command — not just call-related
   ones — began failing with `Command 'core show channels count'
   cannot be run during shutdown`. This included `channel request
   hangup all`, which also returned the identical "cannot be run
   during shutdown" error.
3. This lockout persisted for the entire observation window (85+
   seconds) while the call remained bridged and active. There is
   **no CLI or AMI command that can cancel a pending graceful
   restart**, and no CLI/AMI command that can force-hangup a call to
   unblock it, once the restart has been issued and the lockout has
   begun. The only way to unblock it was to end the call from the
   **SIP client side** (a `baresip` `ctrl_tcp` hangup, external to
   Asterisk entirely).
4. The instant the call ended, `/var/log/asterisk/full` logged:
   ```
   Some modules could not be unloaded, switching to fast shutdown
   Preparing for Asterisk restart...
   Asterisk is now restarting...
   Asterisk Ready.
   ```
   i.e. even a "successful" graceful restart can silently fall back to
   a **fast shutdown** path if a module won't unload cleanly — this is
   a real, observed nuance, not a hypothetical.
5. The AMI `Command()` call in the PHP script itself did not return
   until **61.021 seconds** had elapsed — not because Asterisk took 61
   seconds, but because `Asterisk_AMI::wait_response()`
   (`snep/lib/Asterisk/AMI.php`) calls a blocking `fgets($this->socket,
   4096)` with no explicit timeout, so it silently inherited PHP's
   `default_socket_timeout` ini setting (60s default). The eventual
   return value was an **empty array**, identical in shape to the
   immediate-restart case, but for an entirely different underlying
   reason (a genuine protocol timeout vs. an abrupt EOF).

**Implication:** the existing `Command()`/`wait_response()`
implementation is unconditionally unsafe to call synchronously from a
web request for `core restart gracefully`. A request thread would
block for up to 60 seconds (or longer, since nothing in the current
code enforces that ceiling as a hard maximum — it is only a default)
per attempt, with **no way to know whether that's because a call is
still active or because something else hung**, and with PJSIP/registrations remaining apparently normal to the outside world (the call itself kept flowing) while the entire administrative surface is invisible.

**Recovery evidence (separate immediate-restart test, §5):** endpoint
re-registration (`pjsip show endpoint 1002` → `Avail`) and ODBC
(`odbc show all` → `Number of active connections: 1 (out of 1)`) were
both already fully recovered by the first check, taken ~46 seconds
after the restart command was issued. The process-level recovery
itself (channels dropped → CLI usable again) took roughly 2 seconds
(see §5); the wider ~46-second figure is only an upper bound from an
imprecise poll interval, not evidence that registration recovery
itself is slow.

---

## 5. Immediate restart with a real active call

A fresh call was established the same way, confirmed `Up`, then `core
restart now` was issued over AMI while polling `core show channels
count` at 0.3s intervals. Exact observed sequence (relative
timestamps):

| t (s) | Observation |
|---|---|
| 0.0 | `2 active channels, 1 active call` — call still up |
| ~1.3 | `Command 'core show channels count' cannot be run during shutdown` |
| ~1.9 | `Unable to connect to remote asterisk (does /var/run/asterisk/asterisk.ctl exist?)` — the CLI/manager UNIX socket file itself briefly disappears during the `exec()` transition |
| ~2.2 | `No such command 'core show channels count'` — new process is up, but PJSIP/core CLI commands are not yet registered (modules still loading) |
| ~2.4 | `0 active channels` — fully recovered, call is gone |

The AMI `Command("core restart now")` call itself returned in **1.1
seconds** this time (vs. ~26ms in an earlier no-call test from before
this session), still well within normal web-request latency, still an
**empty array**, still with no exception.

**This confirms unambiguously: `core restart now` drops every active
call, with zero warning, zero grace period, in about 2 seconds
end-to-end.** It does not distinguish an idle system from one mid-call.

**A genuinely useful, non-obvious finding for the readiness probe
(§12/§13):** recovery from `core restart now` passes through *three*
distinct transient failure shapes before becoming healthy again, not
one:
1. "cannot be run during shutdown" (old process still alive, tearing
   down)
2. connection/socket-file-missing (`asterisk.ctl` gap during the
   `exec()` replace)
3. "no such command" (new process alive, modules not yet loaded)

A naive readiness probe that only checks "does the AMI TCP port
accept a connection" would report false-healthy during state 3 non-PJSIP-related failures could be misread as success. Any real implementation must treat all three as "not ready yet," not as errors.

---

## 6. Recommended restart operation

**Expose `graceful` as the only routine, single-click action.**
`immediate` should be a clearly separated, explicitly-labeled "advanced/
danger" option — not because it is unreliable (it is in fact fast and
deterministic), but because its failure mode is silent call-dropping,
which is exactly the kind of accidental-click harm item 9 warns
against. Do **not** expose `when convenient` — it was not independently
verified in this environment (§1) and its documented semantic (allows
new calls while waiting) does not obviously help the operator's actual
goal (apply a transport change), only adds an unverified third state.

However, §4 also surfaces a real cost of exposing `graceful` casually:
once issued with an active call, the entire admin surface (CLI and
AMI) locks out for as long as that call lasts, with **no cancel path**.
The confirmation UX (§9) must make this explicit, not just warn about
the drop.

---

## 7. Privilege boundary re-confirmation

No change needed. `docker/asterisk-config/manager.conf`'s AMI user
already has both `read` and `write` including the `system` and
`command` classes — the classes that govern `Command` actions like
`core restart now`/`gracefully`. No Docker socket, no `privileged`, no
`cap_add` exist anywhere in `compose.yaml` (re-confirmed this session).
`asterisk` still runs as PID 1 via `exec "$@"` in
`docker/asterisk-entrypoint.sh`. **No AMI permission or Docker
configuration change is needed or proposed.**

---

## 8. Restart service architecture

Following the existing static-manager convention already established
by `Snep_PjsipTransports_Manager` (TASK-0018/0020), propose a new
`Snep_Asterisk_Operations` class in `snep/lib/Snep/Asterisk/Operations.php`
with a narrow, evidence-shaped interface:

- `getActiveCallCount(): int` — wraps `core show channels count`,
  parses the `N active calls` line (§2).
- `restartGracefully(): void` — issues `core restart gracefully` over
  AMI. Given §4's blocking-`fgets` finding, this **must** explicitly
  set a short socket read timeout (e.g. via `stream_set_timeout()` on
  the underlying socket, which the current `Asterisk_AMI` class exposes
  no hook for — a small, targeted change to that class, or a
  purpose-built short-lived connection, would be needed) so the issuing
  HTTP request does not block for up to a minute. The **empty-array
  response must be treated as "command likely accepted," never as
  failure or success** — actual completion is determined only by the
  separate readiness probe (§12), polled asynchronously, not by this
  call's return value.
- `restartNow(): void` — same AMI call shape as above; the immediate
  case already returns in ~1-1.1s so the timeout risk is much smaller,
  but the same "empty array is not an error" contract applies for
  consistency.
- `isHealthy(): bool` / `getRestartStatus(): string` — the readiness
  probe (§12), callable repeatedly and independently of the restart
  call itself.

The controller layer should call only this service, never issue raw
`Command("core restart ...")` strings itself — mirroring how
`PjsipTransportsController` never talks to `PBX_Asterisk_AMI` directly
for reload, always through `Snep_PjsipTransportConf`/`Manager`. This is
a narrow, single-class addition, not an AMI architecture refactor.

---

## 9. Restart confirmation UX

Must show, before any restart is issued:
- Current active-call count (`getActiveCallCount()`), refreshed at
  confirmation-render time, not cached.
- Which restart type will run (`graceful` by default, `immediate` only
  behind a distinct, harder-to-reach control — see §6).
- If active calls > 0: an explicit warning that graceful restart will
  **wait indefinitely for those calls to end, during which the entire
  Asterisk admin interface (including this one) will be unresponsive
  and the restart cannot be cancelled** (§4) — this is a materially
  different and more specific warning than a generic "calls will be
  interrupted" message, and directly reflects what was observed live.
- If active calls = 0: both graceful and immediate behave
  indistinguishably fast (~2s) and the warning can be much lighter —
  brief disconnect of registrations/ODBC/AMI expected.
- A single explicit confirmation action (e.g. type-to-confirm or a
  second click), never a bare link — ties into §10.

---

## 10. CSRF / authorization audit

**Zero CSRF protection exists anywhere in this codebase** — confirmed
via `grep -rln "csrf\|Csrf\|CSRF" snep/` returning nothing outside the
vendored Zend library. This is a pre-existing condition across the
*entire* application, not something introduced or specific to this
task. A restart action is unusually dangerous to leave
link-triggerable (a bare `<a href>`/GET request could be embedded
anywhere and silently drop every call in the building), so the
smallest safe fix scoped to just this feature:

- The restart action **must** be a POST-only route (already the
  general convention for mutating actions in this app, e.g.
  `extensions/remove` in `call-smoke-test.sh`'s own fixture cleanup).
- Require the same authenticated-admin session/ACL check every other
  `write` sub-resource in `resources.xml` already uses (see §15) — no
  new auth mechanism.
- Add a minimal, single-purpose CSRF token scoped to *only* this form
  (e.g. a `Zend_Form`-style hidden token checked server-side on this
  one controller action), rather than a global CSRF middleware/rewrite.
  This satisfies the task's explicit instruction not to turn this into
  an application-wide CSRF redesign while still closing the one-click
  drive-by risk this specific action introduces.

---

## 11. Restart status lifecycle

Given §4/§5's evidence, a real lifecycle needs at least these distinct
states, and must **never claim success from command acceptance alone**
(the AMI `Command()` return value, empty or not, proves only that the
socket write succeeded):

1. **REQUESTED** — operator confirmed, `Command()` call in flight.
2. **ACCEPTED** — `Command()` returned (any response, including empty)
   without a connection-level exception. Does **not** mean Asterisk is
   restarting yet (graceful may still be waiting on calls, §4).
3. **WAITING FOR CALLS** (graceful only) — inferred by the readiness
   probe (§12) observing the "cannot be run during shutdown" CLI state
   while the previously-known active-call count was > 0. Since no
   command works during this window, this state can only be inferred,
   not directly queried — see §17.
4. **DOWN** — probe detects the transient failure states from §5
   (connection refused / socket missing / "no such command").
5. **BACK** — AMI connection succeeds and a basic command (e.g. `core
   show version`) returns real data.
6. **HEALTHY** — the full readiness probe (§12) passes.
7. **TIMED OUT** — BACK/HEALTHY not reached within the evidence-based
   timeout (§13).

---

## 12. Recovery verification / readiness probe

Minimum reliable probe, in order, each step gating the next:
1. Fresh AMI connection succeeds (a **new** connection — §11 of the
   background notes already established `PBX_Asterisk_AMI::getInstance()`
   is request-scoped, so a polling loop must always open its own new
   connection, never assume it can reuse the restart-issuing one, which
   is expected to become unusable per §1/§4/§5).
2. `core show version` (or equivalent) returns real text, not "cannot
   be run during shutdown" / "no such command" / connection error.
3. `pjsip show transports` returns the expected transport list — this
   is also exactly what TASK-0020's `getRuntimeTransportNames()`
   already parses, so the same helper can double as part of this
   probe.
4. `odbc show all` reports the expected active connection (already
   proven fast to recover, §3/§4).
5. Previously-registered endpoints show `Avail` again (best-effort;
   registration timing depends on the SIP client's own re-REGISTER
   interval, which SENMA does not control, so this should inform
   messaging — "registrations may take up to their configured expiry to
   reappear" — rather than block the HEALTHY state).

Steps 1–4 are the minimum for declaring "Asterisk is back and PJSIP is
usable"; step 5 is informational only, not blocking, since a slow
client-side re-registration is not an Asterisk-side failure.

---

## 13. Timeout recommendation

Measured this session, both with **zero pre-existing state to wait
on** (immediate case, §5): total process-level recovery (call dropped
→ CLI usable again) was **~2.4 seconds**. `core show version`/`pjsip
show transports`/`odbc show all` were all confirmed working well
within that same window in prior TASK-0020 restart-recovery testing
(single `core restart now`, no active calls) — full application-level
health was reached in under 5 seconds in every previously-recorded
case, and endpoint re-registration was confirmed complete within a
~46-second (loose) upper bound this session.

Recommended: poll every 1s starting immediately after `ACCEPTED`; treat
the probe as **TIMED OUT** if HEALTHY (§12 steps 1-4) is not reached
within **30 seconds** for the immediate-restart path — comfortably
above the ~2.4s observed with margin for a slower CI/production host,
well short of a minute so an operator isn't left staring at a spinner.
For the **graceful** path, no fixed timeout is meaningful for the
"waiting for calls" phase (§4 showed this is bounded only by how long
calls run, potentially indefinitely) — the UI must distinguish
"waiting for N active calls to finish" (not a failure, no timeout)
from "restart accepted, now recovering" (the same 30s ceiling applies
once the call-count reaches zero and the actual restart begins).

---

## 14. Transport integration

Not re-tested end-to-end this session (would have required repeating a
TASK-0020-style rename/restart-required fixture, which is redundant
with TASK-0020's own already-committed, already-passing evidence), but
directly confirmed by construction: `PjsipTransportsController::indexAction()`'s
`runtime_state` is computed fresh on every page load via
`getRuntimeTransportNames()` (a live `pjsip show transports` call), with
**no persisted flag anywhere** (TASK-0020's explicit, approved
design). Since this session's live restarts (§5) were confirmed to
fully restore `pjsip show transports` output to the expected state, a
transport list page loaded after a completed restart will **naturally**
recompute `active` for every previously `restart_required` row, with
zero additional code needed to "clear" anything. This is a direct,
structural consequence of TASK-0020's derived-state design, not a new
finding requiring fresh proof.

---

## 15. UI placement

Candidate homes, from the actual `resources.xml` groups (re-confirmed
this session):
- `status` group (contains `inspector` = System Status) — natural home
  for an operational action; administrators already look here for
  Asterisk health.
- `pjsip` group (currently only `pjsip-transports`) — could host a
  link/button, but a restart is not PJSIP-specific in principle (it
  affects the whole PBX), so putting the *action itself* here would
  misrepresent its scope.
- A new dedicated resource (e.g. `asterisk-restart` under `status`) —
  cleanest single-responsibility option.

**Recommendation:** one central action living under the `status` group
(alongside System Status), with the PJSIP Transports list page linking
to it (e.g. its existing "Restart required" flash message/badge could
link there) rather than duplicating a restart button on the transports
page itself. This satisfies the task's explicit preference for one
central action over duplicated buttons.

---

## 16. Audit trail

`Snep_Audit_Manager::saveLog($action, $table, $registerid, $description)`
(`snep/lib/Snep/Audit/Manager.php`) is the existing, reusable,
DB-backed (`logs_users` table) mechanism already used by
`PjsipTransportsController` and every other CRUD controller — it
already captures `datetime`, `ip` (`$_SERVER['REMOTE_ADDR']`), `user`
(`Zend_Auth::getInstance()->getIdentity()`), `action`, and
`description`. A restart action should call this with a description
encoding restart mode, active-call count at request time, and outcome
(e.g. `"restart gracefully requested, 2 active calls, result: healthy"`).
No new logging subsystem needed.

---

## 17. Failure handling

Directly informed by §4/§5's transient-state evidence:
- **AMI unavailable before request** — `PBX_Asterisk_AMI::getInstance()`
  already throws `Asterisk_Exception_CantConnect`; the controller must
  catch this and report "cannot reach Asterisk," not attempt the
  restart.
- **Restart command rejected** — not observed in this environment (both
  `now` and `gracefully` were always accepted), but the empty-array
  response is indistinguishable from many other conditions (§1) — the
  implementation cannot rely on the immediate response to detect
  rejection at all; it must rely entirely on the readiness probe (§12)
  timing out.
- **Asterisk does not return within timeout** — report **TIMED OUT**
  (§11), never "success," and surface the last-known probe failure
  reason (e.g. "still cannot connect" vs. "connects but PJSIP shows no
  transports").
- **AMI returns but PJSIP not healthy** — the probe's step 3 (§12)
  catches this; report a distinct "Asterisk is back but PJSIP is not
  responding as expected" state rather than collapsing it into either
  full success or full timeout.
- **ODBC not reconnected** — same treatment, probe step 4.
- In every case: **the UI must never say "restart completed
  successfully" unless all of §12 steps 1-4 pass.**

---

## 18. Testing strategy — `make restart-smoke`

Per the explicit preference already stated in the task instructions, a
**separate** `make restart-smoke` target, never run implicitly from
`make smoke` — mirroring how `transport-smoke-test.sh` already warns
in its own header that it performs a real restart, but going further
here since *every* case in this suite restarts Asterisk. Proposed
coverage, directly derived from this session's live findings:
- Zero-call `core restart now`: recovery completes within the §13
  budget (30s), `pjsip show transports`/`odbc show all`/`core show
  version` all healthy afterward.
- Zero-call `core restart gracefully`: behaves indistinguishably from
  immediate when no calls are active (not independently re-verified
  this session but directly implied by §4's mechanism — the "waiting"
  state only begins when `getActiveCallCount() > 0`).
- Active-call `core restart gracefully`: reproduce this session's exact
  fixture (real extensions + baresip + ctrl_tcp dial), confirm the
  restart does **not** proceed while the call lasts, confirm CLI
  lockout, then end the call and confirm recovery — this is the
  hardest and most valuable case to keep automated, since it is the
  one most likely to regress silently.
- Active-call `core restart now`: confirm the call is dropped and full
  recovery still completes within budget.
- Transport-mismatch recovery: create a TASK-0020-style
  `restart_required` transport row, run the new restart action, confirm
  the transport list naturally shows `active` afterward with no manual
  intervention (§14).
- Existing `call-smoke`/`trunk-smoke`/`transport-smoke` suites must
  remain green when run *after* `restart-smoke` in the same
  environment.

---

## 19. Regression requirements

To be preserved: `make smoke` = 16/0/0, `make call-smoke` = 18/18,
`make trunk-smoke` = 23/23, `make transport-smoke` = 63/63. Confirmed
this session: the environment was fully restored to this exact
baseline after all live restart testing (0 active channels, exactly 2
default transports `udp`/`tcp`, no leftover containers or extension
fixtures) — implementation-phase validation should re-run all four
suites as the closing regression step, per existing project convention.

---

## 20. Stop conditions encountered

None of the seven listed stop conditions were triggered:
- No Docker socket or host privileges were needed for any test
  performed (§7).
- Existing AMI credentials fully supported every operation tested
  (`system`/`command` classes already granted).
- Active-call detection (`core show channels count`) was reliable and
  deterministic every time it was queried outside the shutdown-lockout
  window.
- Graceful restart's behavior, while more operationally involved than
  expected (indefinite wait, full lockout, no cancel path), was
  **fully predictable and reproducible** — not "unpredictable" in the
  sense the stop condition means.
- No new authorization redesign is required (§10's scoped fix is
  sufficient).
- Restart completion **can** be detected reliably via the layered
  probe in §12 — it is more involved than a single check, but not
  undetectable.
- No new unrelated PHP 8.4 blocker appeared.

---

## 21. Explicitly deferred

Automatic restart after transport save; restart scheduling; graceful
drain orchestration (beyond what `core restart gracefully` already
does natively); HA/failover; rolling restart; Docker socket exposure;
service-manager integration; cluster coordination; certificate/TLS
work; CDR timezone correction; broad auth/CSRF redesign beyond the
single scoped form token in §10; PostgreSQL.

---

## 22. Proposed implementation scope (for a future approved
implementation phase — not started)

- New `snep/lib/Snep/Asterisk/Operations.php` (`Snep_Asterisk_Operations`,
  §8): `getActiveCallCount()`, `restartGracefully()`, `restartNow()`,
  readiness-probe methods per §12.
- A small, targeted fix to `snep/lib/Asterisk/AMI.php` and/or a
  purpose-built short connection for restart calls specifically, so a
  `gracefully` call issued while calls are active cannot block a web
  request for up to 60 seconds (§4/§8) — likely an explicit
  `stream_set_timeout()` on the socket before issuing a restart
  `Command()`, scoped to restart calls only, not a general AMI-timeout
  refactor.
- A new controller action (module/controller name TBD at
  implementation time) under the `status` resource group (§15), POST-only,
  with the scoped CSRF token (§10) and existing ACL/session check.
- A new confirmation view per §9.
- `resources.xml`: one new resource entry under the existing `status`
  group.
- `PjsipTransportsController`/`index.phtml`: link the existing
  "Restart required" messaging to the new central action (§15) — no
  duplicate button, no change to the already-approved TASK-0020
  runtime-state logic itself.
- `Snep_Audit_Manager` call added to the new controller action (§16) —
  no changes to `Snep_Audit_Manager` itself.
- New `scripts/restart-smoke-test.sh` and a `restart-smoke` Makefile
  target (§18), kept entirely separate from `make smoke`.
- Documentation update to this file's own "implementation" section
  once approved and built.

---

## Answers

1. **Which restart mode should SENMA expose?** `graceful` as the
   single routine action; `immediate` as a separate, harder-to-reach
   "advanced" option — never the only choice, never the default.
2. **Should immediate restart be exposed at all?** Yes, but gated
   behind an explicit secondary control distinct from the primary
   graceful action, with UX copy that reflects §5's evidence (drops
   every call in ~2 seconds, no warning from Asterisk itself).
3. **What happens when active calls exist?** For `graceful`: the
   restart is accepted immediately but does not actually occur until
   every active call ends; during that wait, the entire Asterisk
   admin/CLI/AMI surface is unresponsive and the restart cannot be
   cancelled (§4) — the confirmation UX must say this explicitly, not
   just "calls will be dropped." For `immediate`: calls are dropped
   immediately, no wait.
4. **How does SENMA know restart actually completed?** Only via the
   layered readiness probe in §12 (fresh AMI connection → `core show
   version` → `pjsip show transports` → `odbc show all`), polled from a
   background/async check, never from the restart `Command()` call's
   own return value (§1/§4/§5 all show that value is an uninformative
   empty array regardless of outcome).
5. **Where should the UI action live?** One central action under the
   existing `status` resource group, alongside System Status; the
   PJSIP Transports page links to it rather than duplicating a button
   (§15).
6. **What exact application files should implementation change?** See
   §22's list — one new service class, one small targeted AMI-timeout
   fix, one new controller action + view, one `resources.xml` entry,
   a link added to the existing transports view, one new smoke-test
   script + Makefile target. No schema changes, no changes to
   TASK-0020's already-approved runtime-state derivation logic.
7. **What must remain explicitly out of scope?** Everything in §21 —
   most importantly, no automatic restart, no Docker socket, no
   general CSRF/auth redesign, and no attempt to make `core restart
   gracefully` itself cancellable or boundable (that would require
   changes inside Asterisk, not SENMA).

STOP after this investigation report. Do not implement until
explicitly approved.
