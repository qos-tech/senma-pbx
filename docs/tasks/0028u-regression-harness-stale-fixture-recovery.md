# TASK-0028U — Regression harness stale-fixture recovery

## Status

Implementation complete and validated for both named blockers. `sql-security`
and `transport-smoke` each PASS individually, and PASS together inside a real
full `make regression` run. Two-consecutive-full-`make regression`-PASS could
**not** be certified in this task: a third, pre-existing, unrelated flake in
`transport-smoke-test.sh`'s T20 section was discovered during validation and,
per user decision, is left as documented tech debt rather than fixed here —
see [TASK-0028V](0028v-transport-smoke-t20-restart-race.md). Not committed.

## Background

After TASK-0028T, `make regression` was BLOCKED by two unrelated stale
fixtures left behind by interrupted prior runs:

- `sql-security-smoke-test.sh`: extension `1085` already present in `peers`.
- `transport-smoke-test.sh`: transport `sercomtel-smoke` already present in
  `pjsip_transports`.

Both suites already refused to overwrite an existing row on sight (a
deliberate, correct safety property — see TASK-0027) but had no way to tell
"this is my own leftover fixture from a run that got interrupted" apart from
"this is unrelated/real data that happens to share an identifier". This task
adds that distinction.

## Phase 1 — Root cause

Both scripts are built on `scripts/lib/harness.sh` (TASK-0027), which installs
`trap ... EXIT INT TERM` via `harness_install_traps` so a normal exit, `Ctrl-C`,
or `SIGTERM` all run registered cleanup before the process exits. That trap
**cannot** run for `SIGKILL`, a host crash, or the whole `asterisk`/`app`/`db`
Docker topology being torn down out from under the script mid-run (`docker
compose down` from another terminal, a host reboot, an OOM kill, etc.) — none
of those give the shell a chance to execute any trap. Confirmed live for both
suites this task, by actually reproducing the interruption rather than
assuming it:

```text
start sql-security-smoke-test.sh
-> extension 1085 created (F7 fixture), then extension 1084 (canary)
-> kill -9 <pid>                        # bypasses the EXIT/INT/TERM trap entirely
-> next run: peers row for '1085'/'1084' still present, secret still
   'task0026c-sql-f7'/'task0026c-sql-f7-canary'
```

```text
start transport-smoke-test.sh
-> transport 'sercomtel-smoke' created via the real HTTP flow
-> kill -9 <pid>
-> next run: pjsip_transports row for 'sercomtel-smoke' still present,
   protocol/bind/domain/signaling fields still exactly this suite's own
   fixture shape
```

Neither script's preflight distinguished this from "some other/real row
happens to have this identifier" — both immediately called `harness_blocked`
("refusing to overwrite... remove it manually first") on any pre-existing row
with a matching identifier, regardless of the row's actual contents. That is
correct as a *default* (never delete on identifier alone) but had no recovery
path at all for the one case it's actually safe to auto-clean: the suite's own
leftover fixture.

## Phase 2 — Ownership proof used

`transport-smoke-test.sh` already had exactly this pattern for its own
`REF_EXT` fixture (extension `1098`, added in an earlier task): before
blocking, it checks whether `peers.canal = 'PJSIP/<ext>'` **and**
`peers.secret` starts with the suite's own `FIXTURE_MARKER`. Only if both hold
is the row treated as owned and cleaned via the real HTTP delete flow; a name
match with anything else present blocks exactly as before. This task extends
the same evidence style to the two newly-reported blockers, using each
script's own deterministic per-fixture identity rather than a bare
name/number match:

- **`sql-security-smoke-test.sh` / extension `1085` (and canary `1084`)**:
  `peers.canal = 'PJSIP/<ext>'` **and** `peers.secret` equals this script's own
  exact, deterministic per-fixture secret (`EXT_F7_SECRET` /
  `EXT_F7_CANARY_SECRET`, e.g. `task0026c-sql-f7`) — an exact match, not just a
  prefix, since both values are already known precisely. `secret` is never
  rewritten by the script's own SQLi edit test (that test only ever rewrites
  `callerid`), so it survives an interruption at any point after fixture
  creation. Two independent fields (`canal`, `secret`) both matching a value
  only this suite would ever write is the "unique test marker" + "exact
  fixture shape" evidence the task calls for.
- **`transport-smoke-test.sh` / transport `sercomtel-smoke`**:
  `pjsip_transports` has no free-text marker/comment column, and its `name`
  *is* the identifier being collision-checked — using it alone as ownership
  proof would be exactly the "matching identifier is not ownership" anti-
  pattern the task warns against. Instead, ownership requires **six**
  independent fields to all match this suite's own known fixture values
  verbatim: `protocol='udp'`, `bind_address`, `bind_port`, `domain`,
  `external_signaling_address`, `external_signaling_port`, plus `is_seed=0`
  (a real seeded transport is never `is_seed=0`). `external_media_address` is
  deliberately **excluded** from this check — it's the one field the suite's
  own edit-transport test (check 6) legitimately rewrites mid-run, so
  requiring it to match would make recovery fail for a run interrupted after
  that edit. Every field that *is* checked is never mutated by any other
  check in the script. Before deleting, the preflight also confirms no
  `peers`/`trunks` row currently has `transport_id` pointing at the stale
  transport (the FK is `ON DELETE RESTRICT`) — if one does, it blocks rather
  than guessing whether that dependent is also safe to touch, since its own
  ownership was never independently verified.

Both checks were validated against a deliberately planted **non-owned**
collision (Phase 5) to confirm the negative case still blocks correctly.

## Phase 3 — Implementation

Files changed:

- `scripts/sql-security-smoke-test.sh` — `create_extension`/`delete_extension`
  moved above the F7 preflight block (needed so the preflight can call
  `delete_extension` for recovery); the preflight loop over
  `EXT_F7`/`EXT_F7_CANARY` now checks ownership (canal + exact secret) before
  blocking, and removes the row via `delete_extension` (the same
  `extensions/remove` HTTP flow already used by every other cleanup in this
  script) when owned.
- `scripts/transport-smoke-test.sh` — the transport preflight check now reads
  the existing row's `protocol`/`bind_address`/`bind_port`/`domain`/
  `external_signaling_address`/`external_signaling_port`/`is_seed`, compares
  all seven against the suite's own known fixture constants, checks for
  unproven dependents, and removes the row via `delete_transport` (the real
  `pjsip-transports/remove` HTTP flow) when owned and unreferenced.

No production/application code was touched — both fixes are entirely inside
the test-harness scripts. No telephony behavior changed. TASK-0026 was not
reopened.

Cleanup in both cases reuses the same HTTP `removeAction()` flow every other
fixture teardown in these scripts already uses (never a raw `DELETE`), so it
regenerates PJSIP config and reloads exactly like a normal run's own cleanup
does — no new regeneration/reload mechanism was introduced.

## Phase 4 — Interrupted-run resilience (verified live, not simulated)

Both suites were driven through the full cycle live against the real `make
dev` Docker environment:

```text
start suite -> fixture created -> kill -9 (bypasses trap) -> next run
-> stale, test-owned fixture detected via ownership proof -> cleaned via
   the real HTTP delete flow -> suite proceeds -> PASS
```

`sql-security-smoke-test.sh`: killed right after the F7 canary fixture
(extension `1084`) was created; next run logged `extension 1085 is a leftover
sql-security fixture from an interrupted prior run ... removing via HTTP
before re-creating` (and the same for `1084`), then ran to a full PASS
(25/25).

`transport-smoke-test.sh`: killed right after `transport created`; next run
logged `transport 'sercomtel-smoke' (id=...) is a leftover transport-smoke
fixture (... all match this suite's own known fixture shape, unreferenced) --
removing via HTTP before re-creating`, then ran to a full PASS.

## Phase 5 — Validation

- `make lint`: PASS (containers healthy, `php -l` 271 files/0 errors, `bash
  -n` 30 scripts, XML well-formedness, `git diff --check`).
- `sql-security-smoke-test.sh` run individually: **PASS** (25/25), stale
  extension `1085` recovered automatically, no manual intervention.
- `transport-smoke-test.sh` run individually: **PASS** (63/63 the first time;
  see the unrelated flake noted below for why a later individual run showed
  3 FAILs unrelated to this task's fixes), stale transport `sercomtel-smoke`
  recovered automatically.
- **Negative-case safety checks** (a row present with the *same identifier*
  but a *different* shape/content, simulating real/unrelated data):
  - Planted a `peers` row for `1085` with an unrelated secret
    (`some-real-users-own-password`): `sql-security-smoke-test.sh` exited 2
    (BLOCKED), and the planted row was left completely untouched. Manually
    removed afterward.
  - Planted a `pjsip_transports` row named `sercomtel-smoke` with a different
    domain/port/is_seed shape: `transport-smoke-test.sh` exited 2 (BLOCKED),
    and the planted row was left completely untouched. Manually removed
    afterward.
- `git diff --check`: clean (exit 0).
- `make regression` — full suite, two runs:
  - **Run 1**: `sql-security` PASS, `transport-smoke` **FAIL** — but the
    failure is the three T20 checks documented in TASK-0028V, unrelated to
    stale fixtures (no "already exists"/collision message at all in the log
    for this run — the preflight found a clean DB and created its fixture
    normally). Every other suite PASS. Overall: FAIL.
  - **Run 2**: every suite PASS, including `transport-smoke`. Overall:
    **PASS**.
  - This demonstrates the T20 issue is an intermittent, pre-existing race
    (same code, two different outcomes) rather than a regression introduced
    by this task, and that both target fixes hold up correctly inside a real
    full regression sequence. Two-consecutive-PASS could not be certified
    because of that separate, documented issue — see TASK-0028V. Chasing a
    lucky pair of green runs to satisfy the letter of the acceptance
    criterion while the underlying flake remains was deliberately avoided, as
    it would misrepresent the gate's actual reliability.

## Acceptance criteria

- [x] stale extension 1085 no longer blocks `sql-security`
- [x] stale `sercomtel-smoke` no longer blocks `transport-smoke`
- [x] only provably test-owned fixtures are auto-cleaned (verified negative
      case for both)
- [x] unknown collisions still BLOCK (verified for both)
- [x] no production behavior changed (test-harness-only diff)
- [x] target suites PASS individually
- [x] `make lint` PASS
- [ ] `make regression` PASS twice consecutively — blocked by the separate,
      pre-existing TASK-0028V flake, not by anything in this task's scope
- [x] `git diff --check` clean

## Deferred / not in scope here

See [TASK-0028V](0028v-transport-smoke-t20-restart-race.md): an intermittent
race in `transport-smoke-test.sh`'s T20 "restart-required" section, discovered
during this task's own validation, confirmed present on the unmodified
pre-task script (via `git stash`), and confirmed intermittent (failed in
regression run 1, passed in run 2 with identical code). Left undone per
explicit user decision, in keeping with this task's "narrowly scoped to the
two named blockers" instruction and the project's own bug policy of not
fixing unrelated issues opportunistically.

Also noted but not touched: `transport-smoke-test.sh`'s `EXISTING_TRUNK`
preflight check (a trunk with a matching `callerid`) still blocks
unconditionally with no ownership-proof recovery path, unlike the transport
and `REF_EXT` checks next to it. This is the same latent gap class this task
closed for the other two fixtures, but no trunk fixture was reported stuck and
none was observed stuck during this task's validation, so it was left alone
rather than fixed opportunistically. Worth folding into a future stale-fixture
task if a stuck trunk fixture is ever actually reported.
