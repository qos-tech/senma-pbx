# TASK-0026F1 — Standalone API SQL boundary hardening

## Status

Implemented and validated. `make api-sql-security-smoke`, `make lint`,
and `make regression` (two consecutive full runs) all PASS. Not
committed — this is the validated TASK-0026F1 checkpoint, awaiting
explicit authorization to commit.

## Scope

TASK-0026F's own reconnaissance discovered that most of the standalone
API's service implementations
(`snep/modules/default/api/actions/*.php`) build SQL by direct string
concatenation of `$_GET` values, with no parameterization — a
SQL-injection class of finding distinct from and unrelated to F17-A/
F17-B (documented in `docs/tasks/0026f-standalone-api-hardening.md`
section 5). This task remediates that finding, re-tracing every service
file against current code rather than trusting the earlier summary.

This is a narrowly scoped follow-up: it does not reopen TASK-0026C's
application-wide SQL audit (the main MVC controllers), does not touch
TASK-0026F's authentication/dispatch boundary, and does not fix SQL
outside `snep/modules/default/api/actions/` except where a shared
helper (`Snep_ExtensionsGroups_Manager::getExtensionsGroup()`) is a
direct sink reached from this boundary — and that helper turned out to
already be safe (see below), so nothing outside the API directory was
modified.

## 1. Complete SQL sink inventory (re-verified against current code)

No `INSERT`/`UPDATE`/`DELETE` exists anywhere in `api/actions/` — every
sink is a read-only `$db->query($select)`.

| Service | Parameter(s) | Sink | Status |
|---|---|---|---|
| ContactsService | `phone`/`callerid` | `WHERE ... LIKE '%{$phone}'` | CONFIRMED_UNSAFE → fixed |
| ContactsService | `name` | `WHERE name LIKE '%{$_GET['name']}'` | CONFIRMED_UNSAFE → fixed (+ pre-existing ambiguous-column crash, see §3) |
| CSV_ExportDataService | `table`,`fields`,`order` | `SELECT $fields FROM $table ORDER BY $order` | CONFIRMED_UNSAFE, IDENTIFIER_ALLOWLIST_REQUIRED → fixed |
| CallsReportService | `start_date/hour`,`end_date/hour` | `calldate >= '$x' AND <= '$y'` (×2 queries) | CONFIRMED_UNSAFE → fixed |
| CallsReportService | `contactGroupSrcId`,`contactSrcId`,`contactGroupDstId`,`contactDstId` | unquoted `cn.group/id = $x` | CONFIRMED_UNSAFE → fixed |
| CallsReportService | `src`,`order_src`,`dst`,`order_dst` | unquoted `=`/`LIKE`, single + comma-list | CONFIRMED_UNSAFE → fixed |
| CallsReportService | `time_call_init`,`time_call_end` | unquoted `duration >=/<=` | CONFIRMED_UNSAFE → fixed |
| CallsReportService | `cost_center` | unquoted `accountcode LIKE 'x%'` OR-chain | CONFIRMED_UNSAFE → fixed (one `else` branch is DEAD/UNREACHABLE — `count(explode(...))` is never 0, left as-is) |
| CallsReportService | `exceptions`,`clausulepeer`/`clausule` | unquoted IN-lists | CONFIRMED_UNSAFE → fixed |
| CallsReportService | `limit` | `LIMIT $limit` | CONFIRMED_UNSAFE → fixed via `(int)` cast (a numeric-literal position, not a bindable/quotable value) |
| CallsReportService | `groupsrc`/`groupdst` | `Snep_ExtensionsGroups_Manager::getExtensionsGroup()` (`where('core_peer_groups.group_id = ?', $id)`) + `is_numeric()` filter before concatenation | PARAMETERIZED_SAFE — no change |
| CallsReportService | `report_type`,`rate`,`replace`,`status_*` | flags only, never concatenated into SQL | STATIC_SAFE — no change |
| RankingReportService | `start_date/hour`,`end_date/hour` | same pattern | CONFIRMED_UNSAFE → fixed |
| RankingReportService | `clausulepeer`/`clausule` | unquoted IN-list | CONFIRMED_UNSAFE → fixed |
| RankingReportService | `showsource`,`showdestiny`,`type`,`replace` | `array_chunk()` size / PHP-side flags, no SQL | NO_SQL / STATIC_SAFE — no change |
| ServicesReportService | `start_date/hour`,`end_date/hour` | same pattern | CONFIRMED_UNSAFE → fixed |
| ServicesReportService | `clausulepeer`/`clausule` | unquoted IN-list | CONFIRMED_UNSAFE → fixed |
| ServicesReportService | `group_select` | `getExtensionsGroup()` (safe) + `is_numeric()` filter | PARAMETERIZED_SAFE — no change |
| ServicesReportService | `exten_select` | `is_numeric()`-filtered before concatenation (only digit-only strings survive — no SQL metacharacter can pass) | STATIC_SAFE — no change |
| ServicesReportService | `DND`/`SIGAME`/`LOCK`/`SPY`/`REDIAL`/`WHOAMI`/`REC`/`RECPLAY` | presence flags; only 8 fixed PHP string literals are ever pushed, request only toggles inclusion | STATIC_SAFE — no change |
| CSV_GetParamsService | `option`,`table` | pure static PHP arrays; no `$db` variable exists in this class at all | NO_SQL — no change |
| CallsReportService/RankingReportService (`$select_contacts`,`$select_peers`) | — | 100% static literal SQL strings, no interpolation | STATIC_SAFE — no change |
| CallsReportService, ServicesReportService | — | raw `$select`/`$selectcont`/`$selectcount` echoed back in the JSON response on every call | separate info-disclosure quirk, **not fixed** (see §5) |

Every request→SQL path was traced as:
`HTTP request → index.php dispatcher (TASK-0026F registry, unchanged) →
service class → $_GET parameter → SQL string construction →
$db->query()`. No sink required expanding this task outside
`api/actions/` — `Snep_ExtensionsGroups_Manager::getExtensionsGroup()`
was checked (it is the one shared helper reached from this boundary,
via `groupsrc`/`groupdst`/`group_select`) and found already
parameterized (`snep/lib/Snep/ExtensionsGroups/Manager.php:94-106`), so
it required no change.

## 2. Reproduction (safe, boolean-difference, no data extraction)

For every CONFIRMED_UNSAFE sink, live testing against the running dev
stack (through the real, authenticated standalone API — never a direct
DB connection) compared:

- a normal valid request,
- an ordinary nonexistent value,
- an always-false SQL-shaped value (`x' AND '1'='2`),
- an always-true SQL-shaped value (`x' OR '1'='1`),
- a plain apostrophe-containing value (`O'Brien`).

**ContactsService** — a disposable contact fixture
(`task0026f1-contact`, phone `5599990000`) was inserted so an
always-true condition would have something concrete to return if the
fix failed. Pre-fix behavior (verified before editing): plaintext value
→ correct match; always-true SQL-shaped value → returned the fixture
regardless of the search term (confirmed exploitable). Post-fix:
always-true value returns `{"status":"empty",...}` — same as a
genuinely nonexistent value — the fixture is never reachable through
injected syntax, only through its real phone/name value.

**CSV_ExportDataService** — pre-fix, `table`/`fields`/`order` accepted
any string; post-fix, an unregistered or SQL-shaped `table` value
returns a controlled error before any query is built, a non-allowlisted
column (tested with `users.password`) is silently dropped from the
SELECT list even when explicitly requested, and a SQL-shaped `order`
value (`id; DROP TABLE users`) falls back to the first selected column
instead of reaching the query — verified the `users` table was
unaffected (row count unchanged) after this exact payload.

**CallsReportService/RankingReportService/ServicesReportService** —
verified live that every confirmed sink (`start_date`, `src`, `dst`,
`limit`, `contactSrcId`, `contactGroupSrcId`, `cost_center`,
`exceptions`, `clausulepeer`, `time_call_init`) accepts an injection
payload and returns `{"status":"ok","data":[]...}` (or `"empty"`) with
no SQL syntax error, and directly inspected the reflected `select` text
in `CallsReportService`'s own response to confirm the payload was
present as a backslash-escaped string literal (e.g.
`calldate >= '2020-01-01\' OR \'1\'=\'1 00:00'`), not as executable SQL
syntax — i.e., the fix is not just "didn't crash," it demonstrably
neutralizes the injection. `users`/`cdr`/`services_log` table row
counts and existence were confirmed unchanged after every payload.

## 3. Fixes implemented

**Mechanical approach**: minimal-diff `$db->quoteInto('<fragment with one ?>', $value)` /
`$db->quote($value)` substitution at each vulnerable interpolation
point, preserving every existing string template, operator, join
structure, and OR-chain/`substr()` accumulation trick exactly as it was
— the same approach TASK-0026C used for the main app's controllers, not
a new pattern. No shared helper class was introduced (Phase 8): the
duplicated *vulnerability* pattern (date range, `clausulepeer` IN-list)
across 3 files is fixed identically at each site using Zend_Db's own
existing `quoteInto()`/`quote()` — introducing a new cross-cutting class
for a one-line-per-site fix would have added more architectural surface
than it removed. `LIMIT`/`duration`/contact-id comparisons use `(int)`
casts instead of quoting, since a numeric-literal SQL position cannot
take a quoted string.

**ContactsService.php**: both the `phone`/`callerid` and `name` LIKE
searches now cross into SQL via `quoteInto()`. **Also discovered and
minimally fixed**: the `name` search's bare, unqualified `name` column
reference is ambiguous once joined against `contacts_group` (which also
has a `name` column) — confirmed this is a pre-existing bug independent
of SQL-shaping (an ordinary `name=John` request already crashed with
`SQLSTATE[23000] ... Column 'name' in WHERE is ambiguous` before this
task touched the file). This is on the exact line being rewritten for
the injection fix and blocked validating that fix at all, so it was
resolved with a one-token qualification (`contacts_names.name`, matching
what the `SELECT` list already does two lines above) — isolated to that
token, documented here, not a broader fix of unrelated debt. A minimal
guard (`if ($select === null) return {"status":"empty",...}`) was also
added for the pre-existing missing-parameter crash (Phase 3's own
explicit allowance: required to safely validate the rewrite when
neither `phone`/`callerid` nor `name` is supplied).

**CSV_ExportDataService.php**: `table`/`fields`/`order` are identifier
positions, not value positions — parameter binding does not apply.
Reuses `CSV_GetParamsService::getAllTables()`/`::getFieldsTable($table)`
(already public static methods, already the de facto "what is
exportable" contract real API clients use via `service=CSV_GetParams`
to discover valid values) as the allowlist, rather than
`ExportDataController::getExportTables()` — that method is `private`,
lives in the main MVC bootstrap (a different, architecturally separate
context per TASK-0026F's own findings), and its column set already
diverges slightly from `CSV_GetParamsService`'s (e.g. `peers` columns
differ). Reaching into it would require making it non-private and
`require_once`-ing a main-app controller file from the standalone API,
which is more invasive than reusing the sibling service that already
serves exactly this contract. This is the "two independent allowlists"
case Phase 4 anticipated — documented here rather than forcing a
divergent reuse. `fields` are validated via `array_intersect()` against
the table's allowed columns (mirrors
`ExportDataController::exportAction()`'s own established pattern
exactly); `order` falls back to the first selected field if not itself
a valid column. The query now uses `$db->select()->from($table,
$fields)->order($col)` instead of string concatenation. As a direct
consequence of requiring a valid `table`/`fields` pair before any SQL is
built, the pre-existing PHP 8.4 crash (`$this->view->translate()` on an
always-null `$view` property) is resolved as a side effect — not a
separately targeted fix, but unavoidable since the crash and the SQL
fix lived in the same three lines of guard logic.

**CallsReportService.php / RankingReportService.php /
ServicesReportService.php**: every confirmed sink listed in the table
above now crosses into SQL via `quoteInto()`/`quote()`/`(int)` casts.
The `src`/`dst` OR-chain and `substr(...,3)`-based prefix-stripping
trick, the `exceptions`/`clausulepeer` IN-list assembly, and the overall
WHERE-clause composition order are all unchanged — only the value
substitution mechanism changed. `Snep_ExtensionsGroups_Manager`-routed
parameters (`groupsrc`/`groupdst`/`group_select`) and `is_numeric()`-
filtered parameters (`exten_select`) were left untouched — already safe.

## 4. Focused security smoke — `scripts/api-sql-security-smoke-test.sh`

34 checks, `make api-sql-security-smoke` → PASS. Built on
`scripts/lib/harness.sh`, authenticates through the real, secured
TASK-0026F dispatcher (`curl -u`) — never bypasses it, never queries the
database directly for the actual proofs. Uses a dedicated, persistent
`task0026f1-restricted` fixture user (password reset to baseline every
run, matching the `task0026a/c/d/e/f-restricted` convention already
established by every prior focused-security suite in this project) and
a disposable `task0026f1-contact` fixture (created and removed every
run via `harness_register_cleanup`) so the always-true injection proofs
have something concrete to fail to reach.

Covers, for every confirmed-unsafe sink: (1) a legitimate request works,
(2) an ordinary invalid/nonexistent value behaves normally, (3/4)
always-false/always-true SQL-shaped input cannot alter query semantics,
(5) apostrophe-containing values cause no syntax error, (6) no
unintended rows/data become reachable (the disposable contact fixture,
the real `users`/`cdr`/`services_log` tables), (7) no PHP Fatal Error is
introduced, (8) fixtures are cleaned. Also proves Phase 11's
authentication-preservation requirement: an unauthenticated request to
a protected service is still rejected (401), and an authenticated
malicious-looking request cannot alter SQL syntax on the
already-safe/no-SQL services either (`CSV_GetParams` regression guard).

## 5. Deliberately not fixed (documented technical debt)

- **Raw `select`/`selectcont`/`selectcount` SQL text echoed back in the
  JSON response** (`CallsReportService.php`, `ServicesReportService.php`)
  on every call. Once properly parameterized, this text no longer
  enables injection (any attacker-supplied value now appears
  backslash-escaped as literal data, confirmed in §2), so it is no
  longer a SQL-trust-boundary issue — but it remains a mild internal
  implementation-detail disclosure (table/column names, query shape)
  to any authenticated caller. Out of scope for a SQL-injection
  remediation task; flagged as a candidate for a future
  response-hygiene pass.
- **`CallsReportService.php`'s dead `cost_center` `else` branch**
  (`count($cost_centers) > 0` is always true after `explode()`, so the
  `else` — which still concatenates `$cost_centers` raw — can never
  execute). Confirmed unreachable, left as-is; noted here per Phase 12's
  "document any raw SQL that remains and why it is safe."
- **ContactsService's pre-existing missing-parameter crash** — resolved
  incidentally in `CSV_ExportDataService.php` and mitigated (not fully
  "fixed" as a general-purpose feature) in `ContactsService.php` via the
  minimal guards described in §3, exactly per Phase 3/Phase 9's own
  allowance; not a general product-readiness pass over these classes.
- **`Snep_Services::getPathService()`** — still confirmed dead code
  (zero call sites), still not removed, per TASK-0026F's own prior
  documentation.
- **CallsReportService's other pre-existing quirks** (the commented-out
  `GROUP BY` line, the `$cont` reassignment noted in TASK-0009, the
  `if($_GET['rate'])`/`if($_GET['redirect'])` missing-`isset()` warnings)
  — untouched, unrelated to the SQL-injection boundary.

None of these are session/cookie/CSRF work, password-hashing
modernization, rate limiting, API redesign, or authorization-model
changes — all remain out of scope per this task's explicit boundaries,
and TASK-0026G was not started.

## 6. Validation

- `php -l` on all 5 touched files: no syntax errors.
- `make api-sql-security-smoke`: PASS (34/34).
- `make lint`: PASS (5/5), 20 shell scripts (up from 19 — includes the
  new suite).
- `make regression`: PASS (18/18 suites, including the new
  `api-sql-security` suite ordered right after `api-security`), run
  twice consecutively with no code changes or manual cleanup between
  runs — both fully green. `call-smoke`/`trunk-smoke` (which exercise
  `CallsReportService` through their own real HTTP flows) passed
  unchanged in both runs, confirming the TASK-0027A CDR timezone
  semantics were not touched.

## 7. Health and cleanup

- `app`, `db`, `asterisk`, `provider` containers: all healthy.
- Asterisk 22.10.1, `res_pjsip.so` loaded and running, 3 PJSIP
  transports (tcp/udp/wss), AMI responsive (`manager show connected`
  returns cleanly), ODBC DSN `snep` with 1/1 active connection.
- 0 active channels, 0 active calls at the end of validation.
- The single Fatal Error present in the log at the end of validation is
  the pre-existing, already-documented TASK-0026D `CnlController`/
  `Zend_File_Transfer_Adapter_Http::receive()` PHP 8.4 incompatibility
  (triggered by `shell-security-smoke-test.sh`'s own CNL-upload check,
  part of the regression suite) — unrelated to this task, not newly
  introduced.
- All ad hoc manual-verification artifacts (the first `task0026f1-contact`
  fixture used before the automated suite existed) were deleted from the
  database — confirmed via direct query, zero residue.
- The `task0026f1-restricted` fixture user remains in the dev database —
  this is the suite's own intentional, persistent fixture (matching
  `task0026a/c/d/e/f-restricted`'s established pattern), not leftover ad
  hoc residue. The suite's own `task0026f1-contact` fixture is created
  and removed fresh every run via `harness_register_cleanup`.
- `git diff --check`: clean (no whitespace errors).
- `git diff --stat` / `git status --short`: changes scoped exactly to
  the 5 service files listed in §1, `Makefile`, `scripts/regression.sh`,
  and the new `scripts/api-sql-security-smoke-test.sh`. No scope creep.

## Deferred — not in scope here

- TASK-0026G: session/cookie/CSRF hardening.
- Password-hashing modernization.
- Login rate limiting; default-credential removal.
- Main API redesign / REST modernization / token auth.
- Per-service authorization (RBAC) inside the standalone API.
- The response-hygiene items in §5 (raw SQL echoed back in JSON
  responses; the dead `cost_center` branch).
- `Snep_Services::getPathService()` dead code removal.
