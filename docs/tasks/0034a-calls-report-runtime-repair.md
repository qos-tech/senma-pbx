# TASK-0034A — Calls Report Runtime Repair

## LEAD

senma-application-architect

## REVIEWER

senma-product-designer (error/empty-state handling, Phase 11/17)

senma-telephony-architect was not invoked: report semantics turned out to
depend only on `cdr`/`ccustos`/`core_peer_groups`/`peers` relational
structure already fully documented in existing schema and prior task
docs, not on any telephony/CDR interpretation question that changes
query meaning.

## SCOPE

`CallsReportController` (`snep/modules/default/controllers/CallsReportController.php`),
its two view scripts (`calls-report/synthetic.phtml`,
`calls-report/analytic.phtml`), a new focused regression suite
(`scripts/calls-report-smoke-test.sh`), and this task's own documentation.
`RankingReportController`/`ServicesReportController` were reviewed for
shared-code involvement and confirmed unaffected — not modified.

---

## ORIGINAL FAILURE CHAIN

Reproduced live through the supported HTTP/admin workflow before any
edit (Phase 1), logged in as the superuser (`admin`), a valid synthetic
report request:

```
POST /index.php/default/calls-report
report_type=synthetic
period=01/01/2000 00:00 - 31/12/2030 23:59
selectContactGroupSrc=0&selectContactSrc=0&selectSrc=0
```

Result: HTTP 500, empty response body (Apache `display_errors=Off`, so
nothing is disclosed to the client — see DISCLOSURE PROOF). App log:

```
PHP Warning:  Undefined array key "admin" in CallsReportController.php on line 81
PHP Warning:  Trying to access array offset on null in CallsReportController.php on line 81
PHP Warning:  Undefined variable $exceptions in CallsReportController.php on line 172
PHP Fatal error:  Uncaught TypeError: count(): Argument #1 ($value) must be of type Countable|array, null given in CallsReportController.php:172
```

This is the true first-hit fatal for the superuser path (not the
`count($stmt)` line TASK-0034 documented as the first layer — that
statement is never reached for the superuser, because execution already
fatals earlier at line 172; see UNDEFINED VARIABLE below). Fixing that
in isolation exposes the second, independent fatal
(`count($stmt)`, then-line 402), and — for requests that omit
`selectSrc`/`selectDst` — a third, real SQL syntax error. All three are
described below and were fixed together, then re-verified against the
original reproduction request (now HTTP 200, correct rendered content).

---

## PHP8 FATAL — root cause 1: `count($exceptions)` on an unset variable

**Classification: REQUIRED_BUT_INCOMPATIBLE.**

`getselect()` only ever assigns `$exceptions` (from
`Snep_Binds_Manager::getBondException()`) inside
`if ($user['id'] != '1') { ... }` — the per-user Binds-restriction
lookup, which the superuser (`id == '1'`) deliberately skips (superusers
are exempt from Binds restrictions by design; this exemption itself is
correct and unchanged). `$exceptions` is then read unconditionally
several lines later (`count($exceptions) > 0`, three call sites) for
every user including the superuser. Pre-PHP8, the undefined variable
coerced to `null`; `count(null)` returned `0` with a suppressed warning.
PHP 8 raises `TypeError` instead.

This is not dead code and not obsolete — the exception-count check is
real, current, load-bearing logic for restricted users. The fix
initializes `$exceptions = array()` once, immediately before the
`if ($user['id'] != '1')` block, reproducing the exact pre-PHP8 semantics
(superuser: no exceptions) and leaving every other user's path — which
still overwrites it with the real Binds lookup result — completely
unchanged.

---

## UNDEFINED VARIABLE — root cause 2: dead `$cont = count($stmt)`

**Classification: DEAD.**

`$cont` is assigned once (`$cont = count($stmt)`, `$stmt` being the
`Zend_Db_Statement_Pdo` `$db->query($select)` returns) and never read
anywhere in the file (confirmed by exhaustive grep before removal).
`count()` on a `Zend_Db_Statement_Pdo` object — not `Countable`/`array`
— fatals unconditionally under PHP 8, independent of what the query
itself returned. Removed outright rather than "fixed" (e.g.
`->rowCount()`) precisely because the value was never consumed —
replacing it with a working call would have added new, unexercised
surface for no behavioral reason.

A third, closely related fatal of the exact same class was found and
fixed during PHASE 11 (empty-result) testing: `getAnalytic()` computed
`$totals['totals'] = count($result_data)` where `$result_data` is only
ever assigned inside a `foreach ($row as ...)` loop — an empty (valid)
result set left it undefined, fatal under PHP 8. `getSynthetic()` never
hit this because it only ever `foreach()`es `$result_data` (a silent
no-op on `null`), never `count()`s it. Fixed by initializing
`$result_data = array()` before the loop, mirroring the `$exceptions`
fix's own reasoning.

A fourth instance, found during PHASE 7/8 (parameterization/injection)
review: `costs_center` is submitted as `costs_center[]` (a real
multi-select, always an array in normal browser use), but a request
that sends a bare `costs_center=<value>` instead — confirmed live —
leaves it a plain string; `count()` on it fatals the same way. Fixed
with an `is_array()` guard alongside the existing `!empty()` check.

---

## INTENDED REPORT SEMANTICS

Reconstructed from the current form (`calls-report/index.phtml`),
`indexAction()`'s own field wiring, and the existing schema — not
guessed:

The Calls Report reads `cdr` (Asterisk's call detail record table),
optionally joined to `ccustos` (cost-center tags, by `accountcode`) and,
when the Billing module is present, `rated_calls` (computed price, by
`userfield`). It supports: a required date/time range; an inclusive
disposition filter (Answered/No Answer/Busy/Failed — checkboxes present
in the request are *included*, matching this report's own pre-existing,
unchanged inversion logic: `disposition != 'X'` is ANDed in for every
box *not* checked); source/destination filtering by contact, contact
group, extension group ("Source/Destination Group" — the `core_peer_groups`
join), or a free-text extension/number list with equal/contains
matching; a minimum/maximum call duration; and a cost-center tag filter.
Two renderings: **synthetic** (aggregate totals, day-by-day breakdown,
tag breakdown) and **analytic** (one row per call, optionally replacing
raw numbers with contact/CallerID names and/or a recording link).

---

## SQL ROOT CAUSE — root cause 3: `getExtensionsGroup(null)`

**Classification: BROKEN_REACHABLE (defensive-robustness gap, not a
normal-UI defect).**

`Snep_ExtensionsGroups_Manager::getExtensionsGroup($id)` builds a
`Zend_Db_Select` with `->where('core_peer_groups.group_id = ?', $id)`.
Reproduced live: calling it with `$id = null` throws
`Zend_Db_Statement_Exception: SQLSTATE[42000]: Syntax error ... near
'?) AND (peers.id = core_peer_groups.peer_id)'` — the bound parameter
is never substituted at all when `$id` is `null`.

`getselect()` reached this with `null` whenever `$filter['selectSrc']`/
`$filter['selectDst']` was absent from the request: `if
($filter['selectSrc'] != "0")` had no `isset()` guard (unlike the
sibling `selectContactGroupSrc`/`selectContactDst` checks a few lines
above, which do), and PHP's loose comparison makes `undefined != "0"`
**true** — the "a group IS selected" branch ran with a `null` group id.

**This is not reachable through the real form in normal use**: the
`<select name="selectSrc">`/`<select name="selectDst">` elements are
unconditionally rendered (`count($this->groups) > 0` is always true —
`indexAction()` always `array_unshift()`s a `('id'=>'0','name'=>'')`
sentinel row first), and their own `onChange` handlers only
enable/disable the *sibling* free-text field, never remove the
`<select>` itself — so a real browser submission always sends `0` (or a
real group id) for both. It's reachable via a malformed/direct request
(confirmed live), which the task's own security-verification mandate
(Phase 7/8) requires closing regardless of UI reachability. Fixed with
`isset()` guards mirroring the established sibling pattern, plus an
`(int)` cast for consistency with the same numeric-domain convention
already used for `selectContactGroupSrc`/`selectContactDst`
(TASK-0026J).

---

## JOIN MODEL

Every join in `getselect()`'s own query, and in the one helper it now
correctly reaches (`getExtensionsGroup()`), documented for cardinality:

| Left | Right | Key | Cardinality | Why correct |
|---|---|---|---|---|
| `cdr` | `ccustos` | `accountcode = ccustos.codigo` | many-to-**one-or-zero** | `ccustos.codigo` is the table's `PRIMARY KEY` (confirmed in `schema.sql`) — cannot duplicate a `cdr` row |
| `cdr` | `rated_calls` (only if `Billing_Manager` exists — confirmed `class_exists("Billing_Manager")` is `true` in this environment) | `userfield = rated_calls.userfield` | many-to-**many, unconstrained** | `rated_calls.userfield` carries **no** `UNIQUE`/index constraint (only `id` is a key — confirmed in `snep/modules/billing/install/schema.sql`); more than one `rated_calls` row per `userfield` would duplicate the matching `cdr` row. **Currently inert**: `rated_calls` has 0 rows in this environment (confirmed live), so no duplication currently occurs, and the Billing module's write paths are separately documented (0026k) as not fully wired. Classified `REMAINING DEBT` below — out of this task's scope (Billing/CDR schema redesign is explicitly excluded), not fixed. |
| `core_peer_groups` | `peers` | `core_peer_groups.peer_id = peers.id` (in `getExtensionsGroup()`) | many-to-**one** per row | Each `core_peer_groups` row names exactly one peer; returns one row per group member, no fan-out |

No join in the report's own query construction was found to duplicate
rows for any exercised scenario (see DUPLICATE-ROW PROOF).

---

## PARAMETERIZATION

Inspected every request-derived value `getselect()` uses to build SQL:

| Field | Mechanism | Status |
|---|---|---|
| `period` (date range) | `Snep_Reports::fmt_date()` → `$db->quote()` on both boundaries (TASK-0026J) | Bound value; unchanged |
| `selectContactGroupSrc`/`Dst`, `selectContactSrc`/`Dst` | `(int)` cast | Unchanged, already safe |
| `selectSrc`/`selectDst` | Was raw, unguarded; passed through a real `Zend_Db_Select` bound parameter (`?`) to `getExtensionsGroup()` | **Fixed this task**: `isset()` + `(int)` cast — closes both the crash and hardens the already-parameterized call site |
| `groupSrc`/`groupDst` (free-text extension list) | `$db->quote()` per token (TASK-0026J) | Unchanged, already safe |
| `duration_init`/`duration_end` | `(int)` cast (TASK-0026J) | Unchanged, already safe |
| `costs_center[]` | `$db->quote()` per element | Unchanged, already safe; **fixed this task**: `is_array()` guard against a type-confusion fatal, no SQL-safety change |
| `order_src`/`order_dst` | Compared with `==`, never concatenated into SQL | Safe by construction |

No request-derived value reaches SQL as a raw, unparameterized fragment
anywhere in the reviewed code path.

---

## AUTHORIZATION

Proved live, all three states, via `scripts/calls-report-smoke-test.sh`:

- **Unauthenticated**: request forwarded to the login form (HTTP 200,
  login content only — `Snep_AuthPlugin`'s internal-forward pattern,
  same as every other controller in this app); zero report content
  present.
- **Authenticated, zero permissions**: HTTP 302 to `/permission/error`.
- **Authenticated, explicit `default_calls-report_read` grant,
  non-superuser**: full access, including a real report request that
  exercises the `Snep_Binds_Manager::getBond()`/`getBondException()`
  code path the `$exceptions` fix touches — confirmed unaffected (same
  aggregate totals as the superuser, since this test user has no Binds
  restriction row).

No authorization model change was made or was needed.

---

## DATE/WINDOW CONTRACT

Verified live: same-day, multi-day, and month-boundary ranges all
render correctly; `from > to` is accepted as submitted (existing,
unchanged `Snep_Reports::fmt_date()` behavior — not redesigned, per this
task's own instruction). Empty/garbage `period` throws a
`Zend_Date_Exception`, **caught by Zend's existing front-controller
error handler** (not a raw PHP fatal) — a generic "Internal Error -
SNEP" page, HTTP 500, with the exception message/stack trace and every
internal identifier confirmed absent from the response body. This exact
path is not reachable through the supported UI (the date field is
`readonly`, populated only by the JS date-range picker) — reachable only
via a malformed/direct request, and already fails safely. Not
redesigned, per Phase 10's own instruction.

---

## REAL CDR PROOF

`scripts/calls-report-smoke-test.sh` places one real call (dedicated
fixture extensions, distinct from `call-smoke`'s own 1002/1003, reusing
the identical `ExtensionsController::addAction()` + baresip mechanism
TASK-0011 established), confirms the real `cdr` row
(`uniqueid`/`disposition=ANSWERED`/real `duration`/`billsec`), then
verifies the **web** Calls Report (not the already-proven standalone
API) returns exactly that call: `groupSrc=<extension>` scopes the query
to this fixture's own traffic (see DUPLICATE-ROW PROOF for why this
scoping is required), a tight report window anchored on the call's own
`calldate` (`harness_cdr_report_window`, the same TASK-0027A-hardened
helper `call-smoke-test.sh` uses) contains it, and the extension number
and an "Answered" disposition are confirmed present in the analytic
report's rendered HTML.

---

## AGGREGATION CORRECTNESS

Confirmed non-empty, correctly-populated synthetic totals for the exact
known-call window (see DUPLICATE-ROW PROOF for the exact-count=1 proof,
which is the stronger aggregation assertion: totals['totals'] reflects
precisely the one real answered call, not an approximation).

---

## DUPLICATE-ROW PROOF

One real CDR row → exactly one counted report row, proven via
`totals['totals']` (`synthetic.phtml`'s own Status-Call summary
table — the first `<label class="label label-info">` in the document,
extracted unambiguously to avoid colliding with the Type-Call and
Tag-breakdown tables' own reuse of the same Bootstrap label classes).

**A real methodological finding surfaced here during validation**: an
early version of this proof queried the report **without** any
source-extension filter, and observed `totals['totals']=2` during a live
`make regression` run — not a product defect, but this suite's own
report request counting *every* call in the shared time window,
including `call-smoke`'s own concurrently-placed, unrelated call, which
landed inside the same tight window. Fixed by adding
`groupSrc=<extension>` (this report's own existing, already-hardened
free-text filter) to scope the count to this fixture's own traffic —
now the proof is immune to whatever else a shared regression run happens
to be doing concurrently. Also added a pre-call `DELETE FROM cdr WHERE
src=... AND dst=...` scoped to this disposable fixture's own extension
pair (never real customer call history), closing a second, narrower
version of the same collision risk across quick repeated manual runs of
this suite alone.

---

## INJECTION PROOF

Every user-controlled report parameter tested with representative
malicious payloads (`'`, `--`, `OR 1=1`, `UNION SELECT`, a non-array
`costs_center`, and the fixed `selectSrc`/`selectDst`-omitted request
itself): `groupSrc`/`groupDst` (apostrophe, `UNION SELECT` against
`users`), `selectSrc`/`selectDst` (SQL-shaped values), `duration_init`
(`; DROP TABLE cdr; --`), `costs_center[]`. Every case: HTTP 200, zero
new PHP fatals, no `SQLSTATE`/syntax-error text in the response. The
`UNION SELECT username,password FROM users` attempt was independently
re-verified by grepping the response for the live admin password hash's
own prefix — absent. `cdr` row count confirmed unchanged after the
`DROP TABLE` attempt. Re-verified by the canonical `sql-security`/
`residual-sql-security`/`api-sql-security` regression suites (see
SECURITY SUITES below) — all PASS on the final release candidate.

---

## DISCLOSURE PROOF

Confirmed for both failure classes this task's own fixes touch:

- **PHP fatal** (pre-fix, and any hypothetical future regression of the
  same class): `display_errors=Off` at the Apache/PHP layer — the
  response body is empty (0 bytes) on a fatal, not a stack trace. No
  disclosure risk from the crash itself, though a blank page is a poor
  user experience (see REMAINING DEBT).
- **Caught exception** (garbage `period`): generic "Internal Error -
  SNEP" page; response body confirmed to contain none of
  `Zend_Date`/`Exception`/`Stack trace`/`CallsReportController.php`.
- **SQL injection attempts**: no `SQLSTATE`/"syntax error" text ever
  appeared in a response body across the full injection-proof matrix.

---

## HTML ESCAPING

Two pre-existing unescaped-output sites found during this task's own
Phase 16 review (not present before, since the report never rendered
successfully enough to reach them — this task's own fix is what makes
them reachable for the first time, so leaving them open would have
introduced a live XSS regression as a side effect of the repair):

- `synthetic.phtml`'s Tag/cost-center breakdown echoed
  `$value['name']` (built from `cdr.accountcode` concatenated with the
  admin-entered `ccustos.nome` field) with no escaping.
- `analytic.phtml` echoed `$callsList['src_name']`/`['dst_name']`
  (admin-entered `contacts_names.name`/`peers.callerid`, when "Replace
  number by contact name" is enabled) with no escaping.

Both fixed with `$this->escape(...)` — this codebase's own established
`Zend_View_Abstract::escape()` convention (confirmed via
`pjsip-transports/addedit.phtml` and documented in TASK-0025). Live
XSS proof: a `ccustos` row named `<script>alert(document.domain)</script>`,
tagged to a real call's `accountcode`, renders as the escaped
`&lt;script&gt;...&lt;/script&gt;` — zero raw `<script>` tags in the
response — confirmed both manually and by
`scripts/calls-report-smoke-test.sh`'s own escaping check.

---

## UNAFFECTED REPORTS

`RankingReportController`/`ServicesReportController` reviewed: neither
contains `count($result_data)`/`count($stmt)`/`count($exceptions)`-shaped
code, neither references `core_peer_groups`/`getExtensionsGroup()`, and
neither file was touched. Both confirmed live (HTTP 200) before and
after this task's changes, and by
`scripts/calls-report-smoke-test.sh`'s own final checks.

---

## RELEASE IMPACT — TASK-0034 CH-1 disposition

**CH-1 is CLOSED.** Calls Report (synthetic and analytic) is
reclassified from *broken/release-blocking* to **PILOT_SUPPORTED**,
proven end-to-end with real CDR data, correct aggregation, no
duplication, intact authorization, intact injection resistance, and
newly-closed output-escaping gaps — see VALIDATION below for the full
gate evidence. TASK-0034's pilot-scope table and release decision should
be updated accordingly (see docs/tasks/0034-release-readiness-production-pilot-gate.md).

---

## REMAINING DEBT

1. **`rated_calls.userfield` has no uniqueness constraint** (Billing
   module). Currently inert (0 rows in this environment; the module's
   own write paths are separately documented elsewhere as not fully
   wired) — a real, latent duplicate-row risk *if* the Billing module is
   ever populated with more than one price row per call. `POST_PILOT` /
   out of this task's scope (CDR/Billing schema redesign is explicitly
   excluded); flag for whoever completes Billing module wiring.
2. **A PHP fatal produces a blank page, not a friendly error.** Confirmed
   safe (no disclosure) but poor UX. Only reachable via a malformed
   request now that this task's fixes close every currently-known
   trigger reachable from the real UI — `LOW` per the design-debt
   taxonomy (silent failure without a misleading "success" state, not
   a blocker). Not fixed here — would require deciding a general
   report-error UX contract beyond this task's narrow-fix mandate.
3. **No server-side sort/pagination parameter exists at all** for this
   report (`ORDER BY calldate, userfield` is hardcoded; any
   sort/pagination is client-side, out of this task's scope). Not a
   gap relative to Phase 15's own request — there is nothing to
   allowlist.

---

## CHANGES

**PRODUCTION**:
- `snep/modules/default/controllers/CallsReportController.php` — four
  narrow PHP8-compatibility/robustness fixes (see PHP8 FATAL /
  UNDEFINED VARIABLE / SQL ROOT CAUSE above); no SQL/query semantics
  changed for any already-working input.
- `snep/modules/default/views/scripts/calls-report/synthetic.phtml`,
  `analytic.phtml` — two output-escaping fixes (see HTML ESCAPING).

**TEST**:
- `scripts/calls-report-smoke-test.sh` (new) — 30-check focused
  regression suite, wired into `scripts/regression.sh` and
  `make calls-report-smoke`.
- `scripts/residual-sql-security-smoke-test.sh` — `calls_report_check()`
  updated to accept the now-normal clean signature (no fatal at all) as
  PASS, alongside the historical pre-fix crash signature (defense
  against a future regression of the same bug class), never weakening
  the actual SQL-error/disclosure assertion itself.
- `Makefile`, `scripts/regression.sh` — wired the new suite in,
  immediately after `call-smoke` (the closest sibling). A `trunk-smoke`
  outbound-registration timeout was observed twice while this suite ran
  adjacent to it; moving the suite elsewhere in the order did **not**
  clear it on a third, otherwise-clean run (see VALIDATION), disproving
  the adjacency theory — reverted to the natural placement. Classified
  as an independent, host-load-sensitive flake (see VALIDATION), not
  caused by this task.

**DOCUMENTATION**: this document.

---

## VALIDATION

- `make lint` — PASS.
- `make regression`, run 1 of 2 — **PASS, 37/37**, including the new
  `calls-report-smoke` suite (30/30 internal checks) and
  `residual-sql-security` (its `CallsReportController` boundary checks
  now pass on the clean, no-fatal signature).
- `make regression`, run 2 of 2 — **PASS, 37/37**, same stack, no reset
  or manual repair between the two runs.
- `make doctor` — 0 FAIL.
- `make secrets-check` — `OVERALL: MATCH`.
- `make migrate-check` — `SCHEMA_CURRENT`.
- `make reconcile-check` — `IN_SYNC`.
- `git diff --check` — clean.
- `git status --short` — only this task's own files (see CHANGES).

**Process note on regression-run reliability during this task**: several
earlier regression attempts (not counted above) hit transient,
independent PJSIP-reload/registration timing races
(`trunk-smoke`/`transport-smoke`) unrelated to any file this task
touched — reproduced with `calls-report-smoke` both adjacent to and far
from `trunk-smoke` in the suite order (ruling out adjacency), and
independently confirmed by running `trunk-smoke` alone against the same
stack immediately after a full regression pass (clean 25/25). The host
was concurrently running multiple unrelated heavy Docker workloads
throughout this session, with measured free memory in the tens of
megabytes at the time of the flakiest runs — consistent with genuine
host-load contention, not a product or test-suite defect. This class of
flake (a fresh `docker compose exec` transiently seeing incomplete
PJSIP state immediately after another suite's own reload) is already
documented in `docs/tasks/0027-regression-harness-reliability.md` and
`docs/tasks/0033e1-asterisk-restart-harness-odbc-recovery.md`; this task
adds no new instance of it.
