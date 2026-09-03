# TASK-0027A — Timezone-safe CDR regression assertions

## Status

Implementation complete and validated, including the regression-gate
reliability gap closed after the first validation pass (see
[Remediation](#remediation--bash-32-harness-crash-and-container-settling-race)
below). Two consecutive full `make regression` passes both PASS, with no
BLOCKED/INCONCLUSIVE and no code changes between them. Not committed.

## Background

TASK-0026C's own canonical `make regression` run exposed a deterministic
defect in the TASK-0027 regression harness, not in TASK-0026C's SQL
remediation: `call-smoke-test.sh` and `trunk-smoke-test.sh` each finish
with a "SENMA reporting path can read it" check that calls the
`CallsReport` API for "today" and asserts the CDR the test itself just
produced comes back. During roughly the last three hours of each local
day this check fails, because "today" and the calendar day the CDR is
actually stored under disagree. This task makes those three checks
timezone-safe and independent of the wall-clock hour, without touching
TASK-0026C's application code or starting TASK-0026D.

## Phase 1 — The timestamp contract, as found

1. **Timezone of the shell/containers running the harness**: `app`,
   `asterisk`, and `db` all report `TZ=America/Sao_Paulo` (`-03`) via
   both their `date` command and (confirmed on the Asterisk daemon
   itself via `/proc/1/environ`) their actual process environment.
   `call-smoke-test.sh`/`trunk-smoke-test.sh` computed `$TODAY` from
   this local `-03` day.
2. **Timezone represented by stored `calldate`**: `cdr.calldate` is a
   plain `DATETIME` column (MySQL applies no timezone conversion to
   `DATETIME`, unlike `TIMESTAMP` — it stores exactly the string it is
   given). Empirically, every CDR row's `calldate` is consistently ~3
   hours *ahead* of the containers' local `-03` wall clock, i.e. it
   matches UTC. Confirmed two ways: live `NOW()`/`UTC_TIMESTAMP()`
   cross-reference against container `date`, and multiple real CDR rows
   compared against known call-placement times across this session. The
   offset is stable, consistent, and fully explained by a single fixed
   3-hour shift — not corrupt or non-reproducible data — so it is
   treated here as a known fact to build around, not as "the CDR itself
   is stored incorrectly" in the sense that would require stopping this
   task (see [Deferred](#deferred-not-in-scope-here) below for the
   separate question this raises).
3. **Timezone used by the SQL date comparison**:
   `CallsReportService.php` (`snep/modules/default/api/actions/CallsReportService.php:42-43,302`)
   does no timezone conversion at all — it concatenates
   `$_GET['start_date'] . " " . $_GET['start_hour']` and compares that
   raw string directly against `calldate`. The web UI's
   `CallsReportController` is the same: `Snep_Reports::fmt_date()`
   (`snep/lib/Snep/Reports.php:90-109`) only reformats `dd/mm/yyyy` to
   `yyyy-MM-dd` via `Zend_Date`, it never touches timezone. Whatever
   string a caller sends is compared byte-for-byte against `calldate`'s
   own (UTC) values — the API has no opinion on timezone; entirely the
   caller's responsibility.
4. **Exact failure mechanism**: both scripts built the report request
   from `TODAY 00:00:00` through `TODAY 23:59:59` using the *local*
   calendar day. Since `calldate` is UTC (local + 3h), a call placed in
   the last three hours of the local day (21:00–23:59 `-03`) gets a
   `calldate` on the *next* UTC calendar day, entirely outside that
   day-bounded request — a pure calendar-day-predicate bug.

## Phase 2 — The fix: a call-anchored window, not a calendar day

Both failing checks already fetch the exact CDR row they care about
*before* querying the report (`CDR_ROW=$(db_query "... ORDER BY calldate
... LIMIT 1")`), so `$CDR_CALLDATE` (or `$CDR_IN_CALLDATE`) is already
known and already correct by the time the report check runs. Rather than
asking "what day is it locally" and hoping it agrees with `calldate`'s
own timezone, the fix asks the report for a tight window built by
offsetting the CDR's *own already-known calldate value* — sidestepping
the local/UTC question entirely, since no assumption about which
timezone `calldate` is in is ever needed: whatever it is, offsetting
that exact value and formatting with the same tool stays self-consistent.

`scripts/lib/harness.sh` gains one new shared function,
`harness_cdr_report_window <calldate> [margin_minutes]` (default margin:
5 minutes), which sets `HARNESS_REPORT_START_DATE`/`_START_HOUR`/
`_END_DATE`/`_END_HOUR` to `[calldate - margin, calldate + margin]`. Each
of the three call sites (`call-smoke-test.sh`'s outbound check,
`trunk-smoke-test.sh`'s outbound and inbound checks) now calls this
instead of computing `$TODAY`, and builds the `CallsReport` request from
those four values instead of a full-day range.

**Old query behavior:** `start_date=$TODAY&start_hour=00:00:00&end_date=$TODAY&end_hour=23:59:59`
— a full local calendar day, built from "now," wrong whenever `calldate`'s
own day disagrees with the local day.

**New query behavior:** `start_date=<calldate-5min date>&start_hour=<calldate-5min time>&end_date=<calldate+5min date>&end_hour=<calldate+5min time>`
— a 10-minute window built from the CDR's own confirmed timestamp, never
from "now." `CallsReportService.php`'s plain `calldate >= '...' AND
calldate <= '...'` string-range comparison spans a real midnight boundary
correctly on its own (lexicographic `YYYY-MM-DD HH:MM:SS` string
comparison sorts correctly across a day boundary), so no special-casing
is needed on either side even when the window itself straddles midnight.
Selectivity is unaffected: the actual assertion is still the exact
`uniqueid` match already present in both scripts; the window's only job
is to make the report's own date-range filtering find the right rows at
all, and a 10-minute window anchored on the call's own timestamp remains
far too narrow for an unrelated historical CDR to coincidentally land
inside it.

A real GNU `date` parsing pitfall was found and worked around while
building this: `date -d "<timestamp> -5 minutes"` silently mis-parses the
leading `-5` as a UTC-5 timezone marker instead of a relative offset,
producing a wildly wrong result with **no error** (confirmed live —
e.g. `2026-06-15 14:30:00 -5 minutes` came back as `2026-06-15
16:31:00`, not `14:25:00`). The unambiguous natural-language forms `"N
minutes ago"` / `"N minutes"` (no leading sign) are used instead, and
were verified correct across a normal daytime value and both directions
of a real midnight crossing (see Phase 4). An empty/missing `calldate` is
explicitly rejected before ever reaching `date -d`, because GNU `date`
silently treats a blank `-d` string as "now" rather than failing — which
would otherwise turn a caller's missing-CDR bug into a bogus-but-valid
window instead of a clear failure.

`$COMPOSE exec -T asterisk date -d ...` is used (not the host shell's own
`date`) for the same reason the pre-existing `$TODAY` code already did:
the host may be running the non-GNU BSD `date`, which lacks `-d`
entirely; the `asterisk` container is Debian-based with GNU coreutils.

## Phase 3 — Shared implementation

`call-smoke-test.sh` and `trunk-smoke-test.sh` had identical
window-computation logic (differing only in which CDR row and which API
query parameters they used it for). The smallest reusable piece — the
window calculation itself — was consolidated into
`harness_cdr_report_window()` in the already-shared `scripts/lib/harness.sh`
(both scripts already source it, matching existing small-utility
functions there like `harness_timeout`/`harness_retry`/
`harness_require_containers`). The three call sites keep their own
query-building and PASS/FAIL assertions, since those differ (outbound
`src=` vs. inbound `dst=` parameters, different CDR variable names) — no
unrelated smoke behavior was refactored.

## Phase 4 — Deterministic proof

`harness_cdr_report_window()` never reads "now" — given the same
`calldate` string it always produces the same window, so the boundary
logic can be exercised with fixed, hand-picked values at any time of day,
without waiting for the real clock to cross the affected window.

New script: `scripts/cdr-window-selftest.sh` (wired into `make
cdr-window-selftest` and into `make regression`, immediately before
`call-smoke`). It asserts exact expected `[start_date start_hour,
end_date end_hour]` output for:

1. **Normal daytime** (`2026-06-15 14:30:00`, margin 5) → both ends stay
   on the same calendar day.
2. **Immediately before local midnight** (`2026-08-29 23:58:00`, margin
   5) → the `+margin` end correctly rolls to the next calendar day.
3. **Immediately after local midnight** (`2026-08-30 00:02:00`, margin
   5) → the `-margin` start correctly rolls back to the previous day.
4. **A real local/UTC calendar-day divergence value** — the actual UTC
   `calldate` this investigation recorded for a call placed at local
   22:06:02 `-03` on 2026-08-29 (`2026-08-30 01:06:02` UTC). The old
   `$TODAY`-based code, computed from the local day (2026-08-29), would
   have missed this row entirely; the new function needs no notion of
   "local" or "UTC" at all to get it right, since it only ever offsets
   `calldate`'s own value.
5. **Empty `calldate` fails closed** — proves the function returns
   failure rather than GNU `date`'s silent "now" fallback.

Run standalone: `bash scripts/cdr-window-selftest.sh` — **PASS, 6/6**,
reproduced via `make cdr-window-selftest` as well. The production
call-smoke/trunk-smoke flows still use the real, live `$CDR_CALLDATE`
value fetched from the database — nothing about the real code path was
mocked or bypassed; only this standalone self-test exercises the pure
window-calculation function directly with fixed inputs. No system or
container clock was modified anywhere in this task.

## Files changed

```
scripts/lib/harness.sh                new harness_cdr_report_window() function;
                                       bash-3.2-safe harness_print_summary;
                                       bounded retry in harness_require_containers
scripts/call-smoke-test.sh            outbound report check uses the new window
scripts/trunk-smoke-test.sh           outbound + inbound report checks use the new window
scripts/cdr-window-selftest.sh        new — Phase 4 deterministic self-test (CDR window)
scripts/harness-lib-selftest.sh       new — deterministic self-test for harness.sh's own
                                       state machine (bash 3.2 fix + retry fix)
Makefile                              + cdr-window-selftest, + harness-lib-selftest targets
scripts/regression.sh                 + harness-lib-selftest (after lint) and
                                       + cdr-window-selftest (before call-smoke) suites
```

No application/product code was touched. No TASK-0026C file was modified.

## Phase 5 (first pass) — Canonical validation surfaced a gate-reliability gap

- `make lint`: **PASS** (5/5; 15 shell scripts at this point).
- `make cdr-window-selftest`: **PASS, 6/6** (see Phase 4).
- `make call-smoke`: **PASS, 18/18**, run at a normal daytime hour
  (13:2x `-03`); `SENMA reporting path can read it` passed using the new
  calldate-anchored window (`calldate=2026-08-30 16:22:22` — itself
  further evidence of the UTC-storage finding, since local time was
  ~13:22 `-03`).
- `make trunk-smoke`: **PASS, 23/23** — both the outbound and inbound
  "SENMA reporting path can read it" checks passed using the new window.
- `make regression`, first run: 12/13 suites PASS; `trunk-smoke` FAILed,
  but not on anything CDR/timezone-related — it failed at its very first
  step, `BLOCKED: one or more of [app asterisk db provider] not Up`,
  immediately (same second) after `call-smoke` finished, then crashed
  with `harness.sh: line 121: _HARNESS_ROWS[@]: unbound variable` while
  printing its summary. An immediate re-run with no code changes produced
  a clean 13/13 PASS. Rather than accept "it passes on retry" as the
  final answer, both causes below were root-caused and fixed, since a
  release gate that occasionally needs a manual re-run is itself a
  reliability defect in the gate.

## Remediation — Bash 3.2 harness crash and container-settling race

**1. Bash 3.2 empty-array crash (real code defect, fixed).**
`harness_print_summary`'s row loop, `for r in "${_HARNESS_ROWS[@]}"`,
runs under `set -u` in every caller. Bash <4.4 (macOS ships bash 3.2.57,
confirmed via `bash --version` on this project's actual host shell)
treats `"${arr[@]}"` on a *truly empty* array as an unbound-variable
error rather than iterating zero times — reproduced directly:
`bash -c 'set -u; arr=(); for r in "${arr[@]}"; do :; done'` fails with
`arr[@]: unbound variable` on this host. This fires whenever
`harness_finalize` is reached before a single `harness_ok`/`harness_bad`
call has run — exactly what happens when the very first check
(`harness_require_containers`) is the one that fails and calls
`harness_blocked` directly. `${#_HARNESS_ROWS[@]}` (a length check, not
an element expansion) is safe on an empty array even in bash 3.2;
confirmed live (`echo "${#arr[@]}"` returns `0` cleanly under the same
`set -u`). Fix: guard the loop with `if [ "${#_HARNESS_ROWS[@]}" -gt 0 ]; then ... fi`
(`scripts/lib/harness.sh`, `harness_print_summary`). This was the only
`"${arr[@]}"` element-expansion in the file — `harness_run_cleanup`'s own
use of `${#_HARNESS_CLEANUP_DESCS[@]}` was already a safe length check,
and its `while` loop never iterates when that count is 0.

**2. Container-settling race (real code defect, fixed — not merely
documented).** `harness_require_containers` did a single, non-retried
`docker compose ps <svc> | grep -q Up` check per service. The observed
failure was a genuinely transient race: `call-smoke`'s own cleanup
(removing baresip fixtures, regenerating and reloading PJSIP config) left
`docker compose ps` transiently reporting a container not yet "Up" for
`trunk-smoke`'s very next, immediate check one second later — the exact
same class of transient-check race `harness_retry`'s existing doc comment
in `lib/harness.sh` already describes and that `call-smoke-test.sh`/
`trunk-smoke-test.sh`/`transport-smoke-test.sh` already retry around for
their own PJSIP-module-readiness checks (`harness_retry 5 2 -- ...`), just
never previously applied to this specific check. This is a genuine gap in
the *aggregate runner's* readiness condition (the suite could still start
before its dependency was actually settled), not something existing
bounded logic already covered — so per this task's instruction it was
fixed rather than merely documented. Fix: `harness_require_containers`
now wraps its per-service check in the same `harness_retry 5 2 -- ...`
bound already used elsewhere (up to 8s worst case, no new timing
mechanism introduced, no arbitrary sleep, no assertion weakened) via a
small `_harness_container_up` predicate.

**Focused self-test:** `scripts/harness-lib-selftest.sh` (new; wired into
`make harness-lib-selftest` and into `make regression`, right after
`lint`, since it proves the shared state machine every later suite
depends on). A pure, self-contained check (fakes `$COMPOSE`, needs no
real Docker containers), in the same accepted PASS(0)/FAIL(1)-only
variant of the shared vocabulary `authorization-coverage-check.sh` already
uses. Asserts, each in an isolated child bash process under this
project's actual bash 3.2:

1. `harness_blocked` with zero rows recorded does not crash (exit 2, BLOCKED).
2. `harness_complete` with zero rows recorded does not crash (exit 0, PASS).
3. `harness_complete` with one real row renders it correctly (exit 0, PASS).
4. A mix of passing and failing rows still classifies FAIL correctly (exit 1).
5. A script that exits without calling `harness_complete`/`harness_blocked`
   still finalizes via the EXIT trap and classifies INCONCLUSIVE, not a
   crash (exit 3) — the same empty-row path as case 1, different cause.
6. `harness_require_containers` still PASSes immediately when a
   container genuinely is up (retry must not mask or delay the healthy
   case).
7. `harness_require_containers` still BLOCKS — boundedly, not
   infinitely — when a container never comes up.

Result: **PASS, 7/7**, confirming empty-row summaries no longer crash,
non-empty summaries render correctly, and PASS/FAIL/BLOCKED/INCONCLUSIVE
classification is unchanged in every case, alongside the two new
container-retry behaviors.

## Phase 5 (final) — Canonical validation after remediation

- `make lint`: **PASS, 5/5** (16 shell scripts, up from 15 —
  `harness-lib-selftest.sh` now included in the `bash -n` sweep).
- `make harness-lib-selftest`: **PASS, 7/7** (see above).
- `make regression`, first consecutive run: **14/14 PASS** — `lint`,
  `harness-lib-selftest`, `preauth-security`, `sql-security`,
  `authorization-coverage`, `authorization-smoke`, `http-smoke`,
  `cdr-window-selftest`, `call-smoke`, `trunk-smoke`, `transport-smoke`,
  `restart-smoke`, `external-failure-smoke`, `external-content-smoke`.
  No BLOCKED, no INCONCLUSIVE.
- `make regression`, second consecutive run, no code changes and no
  manual cleanup in between: **14/14 PASS**, byte-for-byte the same
  suite list and result as the first.
- Cleanup/health after the second run: `app`/`asterisk`/`db`/`provider`
  all `Up`/`healthy`; `res_pjsip.so` loaded and `Running`; AMI responsive
  (`manager show connected` answers cleanly); the 3 baseline PJSIP
  transports (`tcp`, `udp`, `wss`) intact; ODBC DSN `snep` connected; 0
  active channels; 0 new PHP Fatal Errors; no throwaway smoke fixtures or
  `task0026c_csvie_test`-style tables remain (the persistent
  `task0026a-restricted`/`task0026c-restricted` dev-only fixture users
  are the same pre-existing, intentional reusable-fixture pattern
  documented in TASK-0026C, not residue); no smoke/baresip processes left
  running.
- `git diff --check`: clean.
- `git status --short`: exactly the files in
  [Files changed](#files-changed) plus the two new self-test scripts and
  this document, layered on the still-uncommitted TASK-0026C changes —
  no unrelated or unexpected paths, no TASK-0026C application file
  touched.

## Deferred — not in scope here

- **Why Asterisk writes `calldate` in UTC at all.** `cdr.conf` does not
  set `usegmtime` (default: local time), and the Asterisk daemon's own
  process environment has `TZ=America/Sao_Paulo` — by Asterisk's
  documented defaults, `calldate` would be expected to land in local
  `-03` time, not UTC. This investigation did not need to determine
  *why* the CDR backend (`cdr_adaptive_odbc`, aliased `start => calldate`
  per `cdr_adaptive_odbc.conf`) ends up writing UTC instead, only that it
  reliably does — establishing the *why* is a separate, real
  investigation (Asterisk/CDR-backend configuration, not a regression
  harness question) left for a dedicated future task if it matters.
- **The same divergence likely affects the human-facing reporting UI.**
  `CallsReportController`'s own date handling has the identical
  zero-timezone-conversion shape as the API service (`Snep_Reports::fmt_date()`
  only reformats, never converts). If a real operator runs a "today"
  report in the last three hours of the local day, they would plausibly
  see the same missing-recent-calls symptom this harness bug caught.
  This is a genuine, separate, application-facing question — worth its
  own investigation and task — not addressed here, since TASK-0027A's
  scope is the regression harness's own assertions, not reporting
  behavior.

## TASK-0026C impact

None. No file under `snep/` was modified in this task; TASK-0026C's
application-code diff is untouched. TASK-0026C's own checkpoint report
stands; this task only replaces the timezone-fragile *assertion* two
TASK-0027 smoke scripts used to prove a call landed in the CDR reporting
path.
