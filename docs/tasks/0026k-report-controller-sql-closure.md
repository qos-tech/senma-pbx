# TASK-0026K — Report controller SQL boundary closure

## Status

Implementation complete and validated for the two assigned blockers.
Focused smoke suite (27/27), `make lint`, and two consecutive full `make
regression` runs (22/22 suites each) all PASS. Not committed — this is
the validated TASK-0026K checkpoint, awaiting explicit authorization to
commit.

**This task's own Phase 9 final static closure sweep found two
additional, unremediated, confirmed-exploitable instances of the same
root-cause SQL-injection class in `PickupGroupsController.php` /
`Snep_PickupGroups_Manager.php` and `QueuesController.php` /
`Snep_Queues_Manager.php` — files entirely outside this task's assigned
scope (`RankingReportController.php` and `ServicesReportController.php`
only). Per this task's own governing instructions, no code was changed
to fix them — they are documented here and handed off as evidence for a
required follow-up task, not auto-created.**

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE remains NO-GO
```

## Scope

Closes exactly the two report-controller SQL-injection findings
TASK-0026J's own Phase 8 sibling sweep discovered but explicitly left
unfixed (`docs/tasks/0026j-residual-sql-boundary-closure.md`, "Security
handoff" section):

- **BLOCKER C** — `RankingReportController::getData()`'s report-filter
  SQL construction (date range, `clausulepeer`) — the MVC twin of the
  already-hardened API `RankingReportService.php` (TASK-0026F1).
- **BLOCKER D** — `ServicesReportController::getData()`'s report-filter
  SQL construction (date range, `clausulepeer`) — the MVC twin of the
  already-hardened API `ServicesReportService.php` (TASK-0026F1).

Does not touch: report redesign, report UX, CDR timezone semantics
(TASK-0027A), chan_sip/iax2 removal, or any Product Readiness bug
unrelated to these two boundaries — all explicitly out of scope per this
task's own instructions. The two new sinks discovered by this task's own
Phase 9 sweep (`PickupGroupsController.php`, `QueuesController.php`) are
likewise **not** fixed here — see "Phase 9" below for why, and the
handoff section for what a follow-up task should do.

## Phase 1 — Blocker reconstruction

### BLOCKER C — `RankingReportController.php`

- **Entry point**: `viewAction()` (POST-gated via `indexAction()`'s
  `getPost()` check) → `getData($filter)`, where
  `$filter = $this->_request->getParams()` (the full GET+POST+route
  merge, `RankingReportController.php:90`).
- **Request-controlled parameters reaching SQL**:
  - `period` → `Snep_Reports::fmt_date()` reformats only the **date**
    half of each boundary via `Zend_Date`; the **time** half (the raw
    second whitespace-delimited token of each side) is never validated
    and was interpolated directly inside the
    `( calldate >= '$start_date' AND calldate <= '$end_date')` string's
    own quote boundary (pre-fix line 212).
  - `clausulepeer`/`clausule` — meant to be exclusively server-derived
    from `Snep_Binds_Manager::getBond($user['id'])` (only set when
    `$user['id'] != '1'` and a Binds row exists), but `$filter` is the
    raw, unfiltered request; whenever a user has no Binds row (the
    common case) or is the superuser (who skips the Binds lookup
    entirely), a directly-submitted `clausulepeer` value reaches the
    `src IN (...)`/`dst IN (...)` list unmodified (pre-fix line 167).
- **Safe by pre-existing design, unchanged**: `showsource`/`showdestiny`
  (PHP-side `array_chunk()` size arguments, never concatenated into
  SQL), `type`/`replace` (control-flow flags only).
- **Required authorization**: `default_ranking-report_read` (per
  `Snep_PermissionPlugin::$readActions['default_ranking-report'] =
  array('view')`) plus a valid session (this is a same-origin POST but
  the route carries no CSRF-protected mutation, matching the read-only
  nature of a report view — consistent with `CallsReportController`'s
  own boundary).
- **Sibling methods using the same pattern**: none — `getData()` is the
  only SQL-construction method in this controller. The `replace`
  branch's `select_contacts`/`select_peers` queries (line ~445-449) are
  fully static literal SQL, byte-for-byte identical to the already-
  classified `STATIC_SAFE` fragments in `CallsReportController.php`
  (TASK-0026J §Phase 4).
- **Pre-existing, unrelated bug discovered while reconstructing this
  boundary**: `getData()` references `$config->ambiente->prefix_inout`
  (line 179) but never assigns `$config` anywhere in that method scope —
  an undefined-variable warning followed by a "read property on null"
  warning under PHP 8.4, confirmed live during this task's own A/B
  testing. `strlen(null)` still evaluates to `0`, so execution continues
  past this block harmlessly; not fixed here per CLAUDE.md's "do not fix
  unrelated legacy bugs opportunistically" (documented in the Product
  Readiness handoff below).
- **Exploitability**: identical pattern to the already-fixed
  `CallsReportController.php` (TASK-0026J) and its already-fixed API
  sibling `RankingReportService.php` (TASK-0026F1). Confirmed live
  during this task's own A/B verification (Phase 5).

### BLOCKER D — `ServicesReportController.php`

- **Entry point**: same pattern — `indexAction()` → (POST) →
  `viewAction()` → `getData($filter)`,
  `$filter = $this->_request->getParams()`
  (`ServicesReportController.php:97`).
- **Request-controlled parameters reaching SQL**:
  - `period` → `$fromDay`/`$tillDay`, same `fmt_date()` time-half
    boundary issue as BLOCKER C, interpolated directly inside
    `WHERE ( date >= '$fromDay' AND date <= '$tillDay') ` against
    `services_log` (pre-fix line 273).
  - `clausulepeer`/`clausule` — identical unguarded pattern as BLOCKER C,
    reaching the `peer IN (...)`/`peer NOT IN (...)` list (pre-fix line
    174).
- **Safe by pre-existing design, unchanged**: `group_select` (routed
  through `Snep_ExtensionsGroups_Manager::getExtensionsGroup()`, already
  parameterized, plus an `is_numeric()` filter on each returned peer name
  before concatenation) and `exten_select` (`is_numeric()`-filtered
  per comma-separated token before concatenation) — matching
  TASK-0026F1's identical classification (`PARAMETERIZED_SAFE`/
  `STATIC_SAFE`) of the byte-for-byte same patterns in the API sibling
  `ServicesReportService.php`. The `DND`/`SIGAME`/`LOCK`/`SPY`/`REDIAL`/
  `WHOAMI`/`REC`/`RECPLAY` service flags only ever push one of 8 fixed
  PHP string literals — `STATIC_SAFE`, unchanged.
- **Required authorization**: `default_services-report_read`.
- **Sibling methods**: none — `getData()` is the only SQL-construction
  method in this controller.
- **Pre-existing, unrelated bug discovered while reconstructing this
  boundary**: `snep/modules/default/views/scripts/services-report/index.phtml`'s
  `<form>` `action` attribute targets a nonexistent `new-report`
  controller (`$this->url(array("controller" => "new-report", ...))`) —
  confirmed via `grep -rn "new-report|NewReport"` across the tree: zero
  matches anywhere else. This is a template copy/paste bug that would
  make the real HTML form 404/misroute on submit through a browser, but
  it does **not** narrow this boundary's exploitability: the controller's
  real POST entry point (`/index.php/default/services-report`, handled
  by `indexAction()`'s `getPost()` → `viewAction()` dispatch, exactly
  like `CallsReportController`/`RankingReportController`) still works
  when POSTed to directly, which is how this task's own focused suite
  and safe-reproduction proof both reach it. Documented as Product
  Readiness debt below, not fixed here.
- **Exploitability**: identical pattern to `CallsReportController.php`
  (TASK-0026J) and its already-fixed API sibling
  `ServicesReportService.php` (TASK-0026F1). Confirmed live during this
  task's own A/B verification (Phase 5).

## Phase 2/3 — Fixes implemented

Mechanical, minimal-diff `$db->quote()` substitution at each vulnerable
interpolation point, preserving every existing string template,
operator, and IN-list structure exactly — the identical approach
TASK-0026C/F1/J already established three times over, not a new pattern.

**`RankingReportController.php`** (`getData()`):

```php
// clausulepeer IN-list (before)
foreach ($clausulepeer as $key => $value) {
    $where_binds .= $value . ",";
}
// (after)
foreach ($clausulepeer as $key => $value) {
    $where_binds .= $db->quote($value) . ",";
}

// date range (before)
$select .= " ( calldate >= '$start_date' AND calldate <= '$end_date')";
// (after)
$select .= " ( calldate >= " . $db->quote($start_date) . " AND calldate <= " . $db->quote($end_date) . ")";
```

**`ServicesReportController.php`** (`getData()`) — identical shape:

```php
// clausulepeer IN-list (before)
foreach ($clausulepeer as $key => $value) {
    $where_binds .= $value . ",";
}
// (after)
foreach ($clausulepeer as $key => $value) {
    $where_binds .= $db->quote($value) . ",";
}

// date range (before)
$select .= " WHERE ( date >= '$fromDay' AND date <= '$tillDay') ";
// (after)
$select .= " WHERE ( date >= " . $db->quote($fromDay) . " AND date <= " . $db->quote($tillDay) . ") ";
```

`$db` is already in scope at both interpolation points in both files
(assigned earlier in `getData()`, before either block executes) — no
new variable, no new dependency. `$where_exceptions` and other
server-only-derived fragments were not touched (out of scope, not
request-controlled).

## Phase 4 — Semantic reference

`RankingReportService.php`/`ServicesReportService.php` (TASK-0026F1)
were read as a semantic reference. The MVC controllers' request
semantics matched their API twins closely enough (same `clausulepeer`/
date-range shape) that the same `$db->quote()` substitution pattern
applied directly — no divergent MVC-specific behavior required a
different approach.

## Phase 5 — Safe reproduction

For both controllers, this task temporarily reverted the fix (`git
stash`) against the live dev stack, confirmed genuine pre-fix breakage,
restored the fix, and confirmed containment — all through the real,
authenticated HTTP flow, never a direct DB connection, using only
harmless, non-destructive, boolean/syntax-difference payloads. No
password/hash/schema extraction was attempted at any point.

| Payload | Pre-fix (reverted) | Post-fix (restored) |
|---|---|---|
| Ranking, `clausulepeer=1' OR '1'='1` | `SQLSTATE[42000]... near ''' OR '1'='1) OR dst IN (1' OR '1'='1))...'` | HTTP 200, no SQL error |
| Ranking, `period=...00:00' - ...` (apostrophe in time half) | `SQLSTATE[42000]... near ':00' AND calldate <= '2030-12-31 23:59:59')...'` | HTTP 200, no SQL error |
| Services, `clausulepeer=1' OR '1'='1` | `SQLSTATE[42000]... near ''' OR '1'='1))' at line 1` | HTTP 200, no SQL error |
| Services, `period=...00:00' - ...` (apostrophe in time half) | `SQLSTATE[42000]... near ':00' AND date <= '2030-12-31 23:59:59')' at line 1` | HTTP 200, no SQL error |

This directly answers Phase 5's question — **can user-controlled input
alter SQL semantics? No, after this fix; yes, before it** — for all four
confirmed sinks, matching TASK-0026J's own established proof style. A
legitimate request to both endpoints was also confirmed to render HTTP
200 post-fix with no SQL error.

## Phase 6 — Focused security suite

Extended (not duplicated) `scripts/residual-sql-security-smoke-test.sh` /
`make residual-sql-security-smoke`, per this task's own explicit Phase 6
instruction. Added a `report_check()` helper (simpler than BLOCKER B's
`calls_report_check()` — confirmed neither `RankingReportController.php`
nor `ServicesReportController.php` carries `CallsReportController.php`'s
known `count($stmt)`/PHP 8.4 crash, so PASS here means a fully clean
response, zero fatal/syntax-error log entries, not "only the known bug
fired") plus two new sections:

- **BLOCKER C (RankingReportController)**: a legitimate report request
  reaches the DB layer cleanly; an always-false SQL-shaped `clausulepeer`
  (`0' AND '1'='2`) and an always-true one (`1' OR '1'='1`) both become
  inert literal data, never SQL syntax; an apostrophe embedded in the
  raw, unvalidated time half of `period` causes no SQL error.
- **BLOCKER D (ServicesReportController)**: the identical four checks
  against the `services-report` endpoint.

Also extended the preflight authorization-boundary loop to cover
`/index.php/default/ranking-report` and `/index.php/default/services-report`
(zero-permission user denied, HTTP 302 + `permission/error`) and the
admin permission-grant step to include
`default_ranking-report_read`/`default_services-report_read` alongside
the existing `trunks_write`/`calls-report_read` grants. Every existing
TASK-0026J check (BLOCKER A/B) was preserved unchanged.

**Result: PASS, 27/27** (up from 17/17). Cleanup ran cleanly — trunk
fixtures removed, orphaned peers rows swept, restricted-user permissions
reset to baseline, no fixture residue.

## Phase 7 — Sibling sweep (report controllers)

All three main web report controllers
(`{Calls,Ranking,Services}ReportController.php`, the complete set —
confirmed via `ls snep/modules/default/controllers/ | grep -i report`,
no fourth report controller exists) were swept for every
`$db->query(`/`->where(`/`->update(`/`->insert(`/`->delete(` site:

| File | Site | Classification |
|---|---|---|
| `CallsReportController.php` | `getselect()` main SELECT (line 384/401) | `PARAMETERIZED_SAFE` — fixed by TASK-0026J, unchanged this task |
| `CallsReportController.php` | `select_contacts`/`select_peers` (line 439/443) | `STATIC_SAFE` — fully literal SQL |
| `CallsReportController.php` | `getSynthetic()`'s `SELECT * FROM ccustos` (line 707) | `STATIC_SAFE` — fully literal SQL |
| `RankingReportController.php` | `getData()` main SELECT (line 212/239) | `PARAMETERIZED_SAFE` — fixed by this task |
| `RankingReportController.php` | `select_contacts`/`select_peers` (line 446/449) | `STATIC_SAFE` — fully literal SQL |
| `ServicesReportController.php` | `getData()` main SELECT (line 281/294) | `PARAMETERIZED_SAFE` — fixed by this task |

No `ALLOWLISTED_IDENTIFIER` or `DEAD/UNREACHABLE` sites exist in any of
the three files. **No unexplained equivalent sink found among the report
controller siblings** — this specific sweep (Phase 7's own scope: report
controllers only) is clean.

## Phase 8 — Regression integration

`make residual-sql-security-smoke` now covers TASK-0026J (BLOCKER A/B)
+ TASK-0026K (BLOCKER C/D) in one suite, registered in `make regression`
exactly where TASK-0026J placed it (immediately after `sql-security`).
No new regression target was required.

- `make residual-sql-security-smoke`: **PASS, 27/27**.
- `make lint`: **PASS, 5/5** (271 PHP files, 0 syntax errors; 24 shell
  scripts; 3 `resources.xml` files well-formed; clean `git diff --check`).
- `make regression`, first full run (official): **PASS, 22/22 suites**.
  Two earlier full-run attempts hit transient, previously-documented
  environmental flakes unrelated to any file this task touched —
  `restart-smoke` BLOCKED (PJSIP-module-reload-settling race, TASK-0026Z
  PR-06), `call-smoke` FAILed twice on the exact
  `could not find UA for 1003` baresip registration race TASK-0026J's own
  document names verbatim, and `external-failure-smoke` FAILed on a
  `systemstatus` timeout-bound check exceeding its window under the heavy
  back-to-back load of this task's own extensive manual verification.
  Each was independently re-run in isolation and passed cleanly
  (`restart-smoke` 37/37, `call-smoke` 18/18, `external-failure-smoke`
  27/27), confirming none was a regression from this task's changes. Per
  this project's own established precedent (TASK-0026D §Validation,
  TASK-0026J §Phase 9), a subsequent clean full run stands as the
  official first run.
- `make regression`, second consecutive run (no code changes, no manual
  cleanup in between): **PASS, 22/22 suites**, byte-identical result to
  the first official run.

```text
SUITE                          RESULT
----------------------------------------------------------------
lint                           PASS
harness-lib-selftest           PASS
preauth-security               PASS
sql-security                   PASS
residual-sql-security          PASS
shell-security                 PASS
pjsip-config-security          PASS
api-security                   PASS
api-sql-security               PASS
session-csrf-security          PASS
auth-hardening-security        PASS
disclosure-path-security       PASS
authorization-coverage         PASS
authorization-smoke            PASS
http-smoke                     PASS
cdr-window-selftest            PASS
call-smoke                     PASS
trunk-smoke                    PASS
transport-smoke                PASS
restart-smoke                  PASS
external-failure-smoke         PASS
external-content-smoke         PASS
----------------------------------------------------------------
REGRESSION                     PASS
```

No FAIL, no BLOCKED, no INCONCLUSIVE, in either official run. No product
code was modified between the two runs, and no manual cleanup was
performed.

## Phase 9 — Final static closure sweep

A repository-wide sweep for `request-controlled value → raw SQL
concatenation → DB execution`, broader than Phase 7's report-controller-
only scope, per this task's own explicit instruction. Every file
containing a `$db->query(`/`mysql_query(`/`->where(` call and an
adjacent SQL keyword was enumerated (77 files touch `$db->query(` at
all; 47 also contain a literal SQL keyword) and triaged.

**Already-covered, re-confirmed unchanged**: `ExtensionsController.php`/
`Snep/Extensions/Manager.php` (F7), `TrunksController.php`/
`Snep/Trunks/Manager.php` (F9), `Snep_InterfaceConf.php` (TASK-0026J
BLOCKER A), `{Calls,Ranking,Services}ReportController.php` (Phase 7,
above), `Snep/CsvIE.php` (F10), `ExportDataController.php` (F11),
`Snep/Users/Manager.php`/`Snep/Profiles/Manager.php` (F8),
`PjsipTrunkConf.php`/`PjsipConf.php`/`PjsipTransportConf.php`
(TASK-0026E), and all five standalone API report/CSV/contacts services
(TASK-0026F1) — no site in any of these reclassified.

**Confirmed `STATIC_SAFE` (no user input reaches SQL)**:
`snep/includes/ip_status_trunks.php`/`ip_status_peers.php` (the `$like`
value is a hardcoded literal, `'SIP%'`/peer_type filter, never
request-derived, despite being reachable as a same-origin AJAX
endpoint), `ContactGroupsController.php`'s `$sql` at line 76 (fully
literal), `Snep_Dashboard_Manager.php:51` (keyed on `$_SESSION[id_user]`,
a session value set at login, not directly request-controlled — same
trust boundary this program has consistently applied to Binds-derived
`clausulepeer`).

**Confirmed exploitable, NEW, outside this task's assigned scope**:

1. **`Snep_PickupGroups_Manager::get($id)`**
   (`snep/lib/Snep/PickupGroups/Manager.php:62-72`) —
   `->where("cod_grupo = '$id'")`, raw string interpolation, zero
   quoting. Called from `PickupGroupsController::editAction()`
   (`snep/modules/default/controllers/PickupGroupsController.php:136-137`)
   with `$id = $this->_request->getParam('id')` — a raw route/query
   parameter, no cast, no validation — and from `removeAction()`
   (line 237/242) with `$_POST['id']` directly. Requires
   `default_pickup-groups_write` (the only permission level this
   resource exposes per `resources.xml`'s nested `<resource
   id="write">`). **Confirmed live** during this task's own Phase 9
   verification: an authenticated GET to
   `/index.php/default/pickup-groups/edit/id/foo%27bar` (a lone,
   deliberately unbalanced apostrophe — a harmless syntax-difference
   probe, no data extraction attempted) produced a genuine
   `SQLSTATE[42000]: Syntax error ... near 'bar')' at line 1`. Sibling
   method `Snep_PickupGroups_Manager::getFilter($field, $query)`
   (line 132-141) has the identical unguarded pattern in an
   **identifier** position (`->where("$field like '%$query%'")`,
   matching F11's class) but zero call sites anywhere in the tree
   (`grep -rn "getFilter"` — only its own definition) —
   `DEAD/UNREACHABLE`, not currently exploitable via any HTTP path but
   real, vulnerable code.
2. **`Snep_Queues_Manager::getValidation($id)`**
   (`snep/lib/Snep/Queues/Manager.php:354-360`) — raw
   `"... AND rconf.value = '$id' ..."` string interpolation. Called
   from `QueuesController::removeAction()`
   (`snep/modules/default/controllers/QueuesController.php:283,313`)
   with `$id = $this->_request->getParam('id')`, same unvalidated-route-
   parameter shape as above. Requires `default_queues_write`.
   **Confirmed live**: an authenticated GET to
   `/index.php/default/queues/remove/id/foo%27bar` produced a genuine
   `SQLSTATE[42000]: Syntax error ... near 'bar' AND (rconf.key =
   'queue'))' at line 1`. Sibling method `Snep_Queues_Manager::get($name)`
   (line 48-60, also called from `removeAction()`) is already safe —
   `->where("queues.name = ?", $name)`, `PARAMETERIZED_SAFE`.

Both are the exact same root-cause class TASK-0026C fixed for
Extensions/Users/Profiles/Trunks (F7-F9) and this task's own two
blockers fixed for report filters — an unescaped `'$var'` value inside a
`WHERE` clause, driven by a raw, uncast, unvalidated route/query
parameter — in two controllers/managers that were never in scope for
TASK-0026C (whose F7-F11 inventory was Extensions/Users/Profiles/
Trunks/CSV/Export only) or any subsequent 0026x task. Both are gated by
the same permission-plugin/CSRF authorization model as every other
controller this program has audited, reachable by any account holding
the ordinary, commonly-granted `write` permission for that resource —
not a privileged or unusual grant. Neither was touched by this task;
fixing them is outside `RankingReportController.php`/
`ServicesReportController.php`'s assigned scope and not this task's call
to make unilaterally, per CLAUDE.md's "do not fix unrelated legacy bugs
opportunistically" / "do not mix migration phases."

**Also noted, deliberately out of this sweep's "supported surface"
classification**: `PortabilityAction.php:142/167`
(`snep/modules/portability/actions/PortabilityAction.php`) interpolates
`$request->destino` (a dialed-number field) raw into
`WHERE phone like '%{$this->destino}'` and an `$db->update()` WHERE
string — a real, vulnerable pattern, but `PortabilityAction extends
PBX_Rule_Action`, invoked only via
`execute($asterisk, PBX_Asterisk_AGI_Request $request)` from the
AGI/dialplan call-processing pipeline (confirmed: `PBX_Dialplan_Verbose`,
the class backing the authenticated web `SimulatorController`, contains
no `execute()`/action-dispatch call at all — the Simulator only traces
rule *matching*, it never invokes a matched rule's action side effects).
Reaching this sink requires a live call through Asterisk hitting a
specifically configured "Portability" rule action plus an active SNEP
registration — a fundamentally different, telephony-only attack surface
this security program has never included in "supported surface" (no
TASK-0026A-Z/F1/I/J document has ever covered `snep/agi/*.php` or any
`PBX_Rule_Action`/`PBX_Rule_Plugin` class). The same raw-interpolation
pattern also exists in `PBX_Rule_Plugin_Broker.php`,
`Snep_Rule_Plugin_TimeLimit_OldController.php`, and
`DiscarTronco.php` (all `$trunkId`/`$ownerid`/`$queryId` values computed
internally from trunk/queue configuration during call processing, not
sourced from any HTTP request) — same dialplan-only surface, same
classification. Documented here as real code, not silently dropped, but
**not** counted toward this Phase's exploitable-supported-surface
conclusion, consistent with this program's established scope boundary.
A dedicated future task should evaluate whether the telephony/AGI
surface belongs in this program's threat model at all before touching
any of these.

**Conclusion**: the SQL blocker class this task was chartered to help
exhaust (raw request-controlled value → unescaped SQL string → database
execution, on the supported HTTP web-app surface) is **not** exhausted
repository-wide. Two new, confirmed-exploitable, supported-surface
instances were found outside this task's assigned scope.

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE remains NO-GO
```

Per this task's own governing instructions ("If another clearly
exploitable supported-surface SQL injection is found: STOP. Do not
automatically create another task."), **no new task was created**. This
finding is handed off as evidence only.

## Phase 10 — Health and cleanup

- `docker compose ps`: `app`/`asterisk`/`db`/`provider` all `Up
  (healthy)`.
- Asterisk 22.10.1; `res_pjsip.so` — 1 module, Running.
- `pjsip show transports`: 3 baseline transports intact (`tcp`, `udp`,
  `wss`).
- AMI: `manager show connected` responsive, 0 connected users.
- ODBC: `snep` DSN, 1/1 active connection.
- `core show channels count`: 0 active channels, 0 active calls.
- PHP Fatal Error signature check: only the one known, pre-existing
  `count(): Argument #1 ($value) must be of type Countable|array` class
  (`CallsReportController.php:402`, TASK-0026J's own documented Product
  Readiness item) present anywhere in the log — zero fatals attributable
  to this task's own changes, zero `SQLSTATE`/syntax-error-shaped fatals
  anywhere in the post-validation log.
- Fixture residue: zero (`trunks` table empty, zero `task0026`-named or
  injected-name `peers` rows, `pjsip_transports` exactly the 3 baseline
  rows). No leftover baresip/smoke-test containers or processes, host or
  container side.
- `git diff --check`: clean.
- `git diff --stat` / `git status --short`: exactly the 3 modified files
  listed below — no scope creep, no `PickupGroupsController.php`/
  `Snep_PickupGroups_Manager.php`/`QueuesController.php`/
  `Snep_Queues_Manager.php` touched.

## Product Readiness handoff (not fixed here)

- **`RankingReportController::getData()`'s undefined `$config`**
  (Phase 1) — `$prefix_inout = $config->ambiente->prefix_inout;` reads
  an undefined variable; harmless under this environment's actual
  `prefix_inout` value (`strlen(null)` returns `0`, so the guarded block
  never executes) but emits two PHP warnings on every call. A one-line
  `$config = Zend_Registry::get('config');` (matching the pattern already
  present in `indexAction()`) would resolve this; left undone per this
  task's own scope boundary.
- **`services-report/index.phtml`'s `new-report` form-action typo**
  (Phase 1) — the rendered HTML form posts to a controller that does not
  exist anywhere in the tree. Does not affect this task's own SQL-fix
  verification (which posts directly to the real controller action), but
  means the feature's real browser-driven form currently cannot submit
  successfully at all. A one-line template fix
  (`"controller" => "services-report"`) would resolve this.
- **`Snep_PickupGroups_Manager::get($id)`/`Snep_Queues_Manager::getValidation($id)`
  SQL injection** (Phase 9) — **security debt, not merely Product
  Readiness** — see the next section.

## Security handoff — why `SECURITY_GATE remains NO-GO`

Per Phase 9's explicit instruction, this task stops here rather than
silently expanding its own scope. The two originally assigned blockers
are closed, verified, and regression-covered. However:

```text
known SQL injection = 0 in supported surfaces   NOT SATISFIED
```

`Snep_PickupGroups_Manager::get($id)` (reachable via
`PickupGroupsController::editAction()`/`removeAction()`) and
`Snep_Queues_Manager::getValidation($id)` (reachable via
`QueuesController::removeAction()`) both carry the exact same
unescaped-`'$id'`-in-WHERE-clause defect this task and TASK-0026C/J just
closed three times over in different controllers — both reachable via
the same permission-plugin/CSRF authorization model, gated by an
ordinary `write` permission grant, neither touched by this task.

**Recommended next task** (not opened automatically, per Phase 9): close
these two sinks using the exact same `$db->quoteInto()`/`(int)` cast
pattern this task and TASK-0026C/F1/J already established four times
over, plus a small extension of `residual-sql-security-smoke-test.sh`
(or a new focused suite) covering both. While auditing those two
controllers, also decide `Snep_PickupGroups_Manager::getFilter()`'s
disposition (currently dead code with the same vulnerable pattern —
fix alongside `get()` for consistency, or remove if genuinely
unreachable and unneeded). Separately, and only as a follow-on
decision (not blocking this SQL-specific gate): evaluate whether
`PortabilityAction.php`/`PBX_Rule_Plugin_Broker.php`/
`Snep_Rule_Plugin_TimeLimit_OldController.php`'s dialplan/AGI-surface
raw SQL belongs in this security program's scope at all, given it has
never been included to date.

## Files changed

```
scripts/residual-sql-security-smoke-test.sh                  BLOCKER C/D focused coverage (+10 checks)
snep/modules/default/controllers/RankingReportController.php   BLOCKER C fix
snep/modules/default/controllers/ServicesReportController.php  BLOCKER D fix
```

`PickupGroupsController.php`, `Snep_PickupGroups_Manager.php`,
`QueuesController.php`, `Snep_Queues_Manager.php`,
`docs/tasks/0026z-security-audit-closure.md`, and every other prior
TASK-0026x file are untouched. Product Readiness work was not started.
