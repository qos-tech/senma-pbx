# TASK-0026C — SQL boundary hardening (F7–F11)

## Status

Implementation complete and validated. Two consecutive full `make
regression` passes both PASS. Not committed.

## Scope

TASK-0026 (the pre-pilot security audit) recorded five raw-SQL findings in
root-cause group B: F7 (Extensions), F8 (Users/Profiles), F9 (Trunks), F10
(CSV import), F11 (Data Export). This task remediates exactly those five,
using the current tree as authoritative rather than the audit's historical
line numbers. It does not touch: F6 (unauthenticated login SQLi, a separate
pre-auth boundary), shell/command injection (TASK-0026D), PJSIP config
injection (TASK-0026E), F16's authorization gap on the export action (an
authorization-model fix, not a SQL-trust-boundary fix), or any unrelated raw
SQL outside these five boundaries.

## 1. Finding inventory (verified against current code)

| Finding | Entry point | User-controlled value | Sink | Auth required | Status before this task |
|---|---|---|---|---|---|
| F7 | `ExtensionsController::execAdd`/`removeAction`/`multiremoveAction` | extension form fields, `id` | raw `SELECT`/`INSERT`/`UPDATE`/`DELETE` string interpolation | extensions-write | confirmed exploitable |
| F8 | `ProfilesController::addAction`/`editAction` (`duallistbox_profile[]`), `UsersController::editAction` (`id`) | POST array values, route `id` | raw `UPDATE`/`DELETE` WHERE strings in `Snep_Users_Manager`/`Snep_Profiles_Manager` | profiles-write or users-write | confirmed exploitable |
| F9 | `TrunksController::editAction` (mass-assigned `name`) | trunk `name` field (mass-assignable beyond the legitimate UI) | raw `SELECT`/`UPDATE` string interpolation of a stored, attacker-chosen `name` | trunk-write | confirmed exploitable |
| F10 | `Snep_CsvIE::import()` | CSV cell contents | raw `INSERT IGNORE` value-tuple concatenation | none confirmed reachable (see [F10](#4-f10--csv-import-boundary)) | present in code, reachability unconfirmed by the original audit |
| F11 | `ExportDataController::exportAction` | `group`, `coluns[]` keys, `orderby[]` | raw table/column/`ORDER BY` identifier concatenation | any authenticated user (F16's separate authz gap) | confirmed exploitable |

All five were reproduced against the current tree exactly as described by
the audit; none had already been fixed or become unreachable in the
interim.

## 2. F7 — Extensions boundary

**Current call path:** `ExtensionsController::execAdd()` validated exten
uniqueness via `$db->query("SELECT * from peers where name = '$exten'")`,
then built the entire ~20-field peers `INSERT`/`UPDATE` by interpolating
form values directly into a hand-written SQL string. `removeAction()` and
`multiremoveAction()` used the same raw-`SELECT` pattern to look up the
peer before deleting.

**Fix (`snep/modules/default/controllers/ExtensionsController.php`,
`execAdd` now at line 565):** the uniqueness check reuses
`Snep_Extensions_Manager::getPeer($exten)` (line 572, already
parameterized) instead of a duplicate raw query. The INSERT/UPDATE is now
a `$peerData` associative array passed to `$db->insert("peers", $peerData)`
/ `$db->update("peers", $peerData, $db->quoteInto('id = ?', $idExten))`,
binding every value through PDO positional parameters. `removeAction()`
(line 870) and `multiremoveAction()` (line 1031) now go through
`Snep_Extensions_Manager::getPeer()` as well. Values that were previously
built as SQL-syntax strings (e.g. `NULL` literals) are now plain PHP
`null`/`int`, which PDO binds correctly.

**Sibling occurrences (`snep/lib/Snep/Extensions/Manager.php`):**
`getValidationRules($id)` (69), `remove($id)` (109), `removeVoicemail($id)`
(129), `disable($id)` (186), `enable($id)` (201) all built raw
`"... = '$id'"` WHERE clauses; all five now use
`$db->quoteInto('col = ?', $id)` or `where('col = ?', $id)`. Same root
cause, same functional boundary — in scope.

**Classification:** confirmed exploitable, fixed.

## 3. F8 — Users/Profiles boundary

**Current call path:** `Snep_Users_Manager::addProfileByName($data)`
(the mass-privilege-escalation sink) built
`` $where = "`users`.`name` = '{$cond}'" `` from each entry of the raw
`duallistbox_profile[]` POST array and ran `$db->update("users", ..., $where)`
per entry — an attacker-supplied `' OR '1'='1` entry reassigns every user's
`profile_id` in one request. `Snep_Users_Manager::edit($user)` built
`"id = '{$user['id']}'"` from the route's raw `id`. `removePermission($id)`
built a raw `DELETE ... WHERE user_id = '$id'`.

**Fix (`snep/lib/Snep/Users/Manager.php`):** `remove` (75),
`removeRecovery` (95), `removePermission` (115), `addProfile` (136),
`edit` (188), `addProfileByName` (209), `removeProfileByName` (240),
`removeQueuesPermission` (308) — all eight converted to
`$db->quoteInto('col = ?', $val)` WHERE strings. `duallistbox_profile[]`
entries are now bound as data; a value shaped like `' OR '1'='1` matches
zero real usernames instead of every row.

**Sibling occurrences (`snep/lib/Snep/Profiles/Manager.php`):** `remove`
(79), `removePermission` (99), `edit` (138), `migration` (156) had the
same raw-WHERE-string pattern; all four converted identically. Same
functional boundary — in scope.

**Classification:** confirmed exploitable (both the mass-privesc path and
the unbounded `edit`/`removePermission` paths), fixed.

## 4. F9 — Trunks boundary

**Current call path:** `TrunksController::preparePost()` merges the whole
POST body into `$trunk_data` before filtering; because `name` is present
in both `$trunk_fields` and `$ip_fields`, an attacker can override the
auto-generated trunk name via a POST field the legitimate UI never
exposes. The write itself was already a parameterized `$db->insert()`, but
`editAction()`'s subsequent read-back
(`$db->query("select * from peers where name='{$trunk['name']}'")`) and two
further raw `$db->update()` calls (one keyed on the route's raw `id`, one
keyed on the just-submitted, attacker-controlled `name`) interpolated that
stored value directly, so simply viewing the trunk's own edit page after
planting a malicious name triggers second-order injection.

**Fix (`snep/modules/default/controllers/TrunksController.php`,
`editAction` at line 344):** the peers read-back now uses
`$db->select()->from('peers')->where('name = ?', $trunk['name'])`. The two
`$db->update()` calls now bind their WHERE clauses via
`$db->quoteInto('id = ?', $idTrunk)` and
`$db->quoteInto('name = ?', $trunk_data['trunk']['name']) . " AND peer_type = 'T'"`
respectively. The mass-assignable `name` field itself was left settable
(narrowing that is a separate, non-SQL design question, not part of this
trust-boundary fix) — the fix guarantees whatever value lands there can
only ever be compared as data, never alter query syntax.

**Sibling occurrences (`snep/lib/Snep/Trunks/Manager.php`):** `getRules($id)`
(123), `remove($id)` (143), `removePeers($name)` (163), `enable($id)`
(246) had the same raw-WHERE pattern; all four converted. Same functional
boundary — in scope.

**Reviewed and left alone:** `getTrunkLog($id)` (line 192) contains a dead,
unused `$sql = "SELECT  from  trunks where id='$id'";` local (the method
immediately builds and executes a separate, already-safe
`$db->select()->where('trunks.id = ?', $id)` on the next lines — `$sql` is
never passed to `query()`). This is CLAUDE.md's own previously-documented
`getTrunkLog()` debt (the backtick-wrapped
`` `call-limit as call_limit` `` array literal a few lines below, a
PHP shell-exec-operator curiosity on a static string, not user input).
Confirmed not user-controlled and not a live sink; left untouched as
pre-existing, already-tracked debt outside this task's scope.

**Classification:** confirmed exploitable, fixed.

## 5. F10 — CSV import boundary

**Current call path:** `Snep_CsvIE::import($f, $columns, $table)` (line
241) buffered each CSV row as a preformatted SQL value-tuple string
(`"('" . implode("','", $data) . "')"`) with no escaping beyond a narrow
backslash-quote unescape, then executed a single concatenated
`INSERT IGNORE INTO $table(...) VALUES <tuples>`.

**Reachability:** re-confirmed via
`grep -rln "new Snep_CsvIE" snep/` and `grep -rn "->import(" snep/` — the
only instantiation is `ExportDataController.php:195`, and that instance is
used solely to call `exportResult()` (already-safe COUNT query); nothing
in the current tree calls `Snep_CsvIE::import()`. It has no live HTTP
entry point today.

**Fix (`snep/lib/Snep/CsvIE.php`, `import` at line 241):** the row buffer
now holds `array_values($data)` (plain values, not a preformatted SQL
fragment); the flush logic builds a parameterized
`INSERT IGNORE INTO <table> (<cols>) VALUES (?,?),(?,?),...` and passes a
flat bind array to `$db->query()`, preserving the original batch-of-10
flush size and `INSERT IGNORE` semantics exactly.

**Classification:** confirmed unreachable via any current UI/HTTP path,
but the vulnerable code and pattern are real and were explicitly in this
task's assigned scope (F10), so it was fixed rather than left as
theoretical debt.

**Also reviewed, left unfixed:** `Snep_CsvIE::export($select)` (line 115)
independently rebuilds the exact same raw-identifier-injection shape as
F11 (`"SELECT " . $_SESSION['exportData']['coluns'] . " FROM " . ...`)
directly from `$_SESSION['exportData']`, bypassing the parameter it
declares. Re-confirmed unreachable: `grep -rn "->export(" snep/` returns
no call sites anywhere in the tree; `ExportDataController.php` only ever
calls `exportResult()` on its `Snep_CsvIE` instance. The method also
references `$this->_helper`, `$this->view`, `$this->renderScript()`, and
an undefined `$table` — none of which exist on this plain (non-Controller)
class, so even if it were ever wired up it would fatal immediately after
the query. Confirmed dead code; documented here as debt for a future
cleanup task (delete it, or bring it in line with F11's allowlist if it is
ever revived) rather than fixed now, per "do not mechanically replace all
string-built SQL" and "do not fix unrelated legacy bugs opportunistically."

## 6. F11 — Data Export boundary

**Current call path:** `ExportDataController::exportAction()` stored
`group`/`coluns[]`/`orderby[]` straight from the POST body into
`$_SESSION['exportData']` with no server-side check against the fixed
`$tables` allowlist that `indexAction()` uses only to populate its HTML
`<select>` options. A follow-up `download=1` request built
`"SELECT " . $coluns . " FROM " . $table . " ORDER BY " . $order` from
that session data — table name, column list, and ORDER BY clause are all
raw string concatenation in structural (identifier) SQL positions, where
`quoteInto()`/parameter binding does not apply.

**Fix (`snep/modules/default/controllers/ExportDataController.php`):**
added a private `getExportTables()` (line 87) — a hardcoded
table→allowed-columns array mirroring `indexAction()`'s existing per-table
arrays. `exportAction()` (line 100) now validates, in both the
initial-submission branch and the download branch, before any SQL is
built: `group` must be a key of `getExportTables()`; every requested
column key must appear in that table's allowed-column list (columns
outside the allowlist, e.g. `users.password`, are silently dropped, never
selected); `orderby` must likewise be one of the allowed columns for that
table (falling back to the table's first allowed column otherwise). The
download branch now uses
`$db->select()->from($table, $selectedColumns)->order($orderColumn)`
instead of string concatenation.

**Deliberately not fixed here:** the fact that `export`/`download` are
reachable by *any* authenticated user regardless of the `export-data`
permission (F16's `Snep_PermissionPlugin` gap) is an authorization-model
issue, not a SQL-trust-boundary issue — TASK-0026C only removes the
ability for a submitted identifier to alter query *structure*; it does
not change who may reach the action. Left for the authorization work that
owns F16.

**Classification:** confirmed exploitable (both the arbitrary-table read
and the column/ORDER BY injection), fixed at the SQL-identifier level.

## 7. Files changed

```
Makefile                                              (+ sql-security-smoke target)
scripts/regression.sh                                 (+ sql-security suite, ordered after preauth-security)
scripts/sql-security-smoke-test.sh                     new — Phase 5 focused harness
.gitattributes                                         new — disables git diff --check whitespace rule for CsvIE.php only
snep/modules/default/controllers/ExtensionsController.php   F7
snep/lib/Snep/Extensions/Manager.php                          F7 siblings
snep/lib/Snep/Users/Manager.php                               F8
snep/lib/Snep/Profiles/Manager.php                            F8 siblings
snep/modules/default/controllers/TrunksController.php   F9
snep/lib/Snep/Trunks/Manager.php                              F9 siblings
snep/lib/Snep/CsvIE.php                                       F10
snep/modules/default/controllers/ExportDataController.php   F11
```

`snep/lib/Snep/CsvIE.php` is a native-CRLF file untouched since the
original SNEP import; `.gitattributes` marks it `-whitespace` so
`git diff --check` does not flag its pre-existing line endings — an
earlier `eol=crlf` attempt was rejected because it made git treat the
whole file as changed (blob/attribute EOL disagreement); this file's two
one-line semantic edits are otherwise minimal.

## 8. Security test coverage — `scripts/sql-security-smoke-test.sh`

Built on `scripts/lib/harness.sh` (TASK-0027): PASS/FAIL/BLOCKED/
INCONCLUSIVE classification, signal-safe idempotent cleanup, fixture
ownership. Registered as `make sql-security-smoke` and as the
`sql-security` stage in `make regression`, immediately after
`preauth-security` and before `authorization-coverage`.

Preflight: confirms zero-permission users are still denied on
extensions/users/profiles/trunks/export-data (authorization boundary
intact, unaffected by these fixes — Phase 6).

Per finding: a normal valid request through the real UI; a SQL-shaped
canary/target pair proving boolean-injection-style input has no effect
(counts and untouched-fixture checks, not just "no crash"); a
SQL-shaped value stored and read back byte-for-byte as literal data; a
legitimate follow-up action (delete, reassignment) still working; cleanup
of every fixture in dependency-safe (most-recently-created-first) order.

- **F7:** create/canary extensions via the real HTTP flow; a
  `callerid` containing `' OR '1'='1` is stored and read back verbatim; a
  boolean-injection-shaped delete `id` deletes nothing; a legitimate
  delete still works.
- **F8:** two real users created via the UI; a
  `duallistbox_profile[]=' OR '1'='1` submission to `ProfilesController`
  (via a profile created directly through `Snep_Profiles_Manager::add()`
  to route around an unrelated pre-existing PHP 8.4 fatal in
  `ProfilesController::addAction()`, documented below) reassigns neither
  user's profile; a legitimate profile assignment by real name still
  works.
- **F9:** create/canary trunks via the UI; a mass-assigned
  `name=' OR '1'='1` is stored and read back verbatim on the edit page
  with no crash and the canary trunk untouched; boolean-injection-shaped
  remove fields delete nothing; a legitimate delete still works. A
  preflight-and-cleanup-time sweep removes any orphaned `peer_type='T'`
  row left by an unrelated, pre-existing `editAction()` rename-sync bug
  (documented below) via the supported `extensions/remove` HTTP path —
  never raw SQL.
- **F10:** direct exercise of `Snep_CsvIE::import()` (no HTTP entry point
  exists) against a throwaway table, dropped at cleanup; a quote-bearing
  cell is stored verbatim with no syntax break.
- **F11:** a legitimate `users` export and download both work; a
  SQL-shaped table name produces no crash and no query; a request for a
  non-allowlisted column (`users.password`) never appears in the CSV.

Multiple isolated runs and the runs embedded in full `make regression`
passes have reached 25/25 PASS.

## 9. Pre-existing bugs discovered, deliberately not fixed

Per CLAUDE.md's "do not fix unrelated legacy bugs opportunistically" —
each is documented here as debt rather than patched:

- **`ProfilesController::addAction()`** fatals under PHP 8.4
  (`count(): Argument #1 ($value) must be of type Countable|array, false
  given`) because `Snep_Profiles_Manager::getName()` returns `false` for
  any brand-new profile name and `count(false)` is a `TypeError` under
  PHP 8+. Same bug class TASK-0023 already fixed for
  `UsersController::addAction()`, never extended here. The F8 test routes
  around it by creating its fixture profile directly via
  `Snep_Profiles_Manager::add()` and exercising the real vulnerable sink
  through `editAction()` instead.
- **`TrunksController::editAction()`'s peers-rename-sync logic** locates
  the peers row to update using the *newly submitted* (possibly renamed)
  `trunks.name` rather than the trunk's prior name, so renaming a trunk
  desyncs its peers row, which is then orphaned once the trunk is
  deleted. Pre-existing, unrelated to injection (the query is already
  parameterized after this task's fix — the bug is which value it looks
  up, not how). The harness carries a sweep as a safety net rather than
  the product code being changed.
- **`Snep_CsvIE::export()`** — dead code, see [F10](#5-f11--data-export-boundary).
- **`ExportDataController`/`Snep_Csv`** emit an unrelated
  "Undefined variable"/`foreach() on null` warning when exporting a table
  with zero rows (observed against the dev seed's empty `queues` table);
  pre-existing, not a SQL-boundary defect, not fixed.

## Validation

- `php -l` on every touched file: clean.
- `make lint`: PASS.
- `make sql-security-smoke` (isolated): PASS, 25/25, across multiple runs.
- `make regression`, first full run after remediation: `lint`,
  `preauth-security`, `sql-security`, `authorization-coverage`,
  `authorization-smoke`, `http-smoke`, `transport-smoke`, `restart-smoke`,
  `external-failure-smoke`, `external-content-smoke` all PASS.
  `call-smoke` and `trunk-smoke` FAILed, both on the same single
  assertion shape ("SENMA reporting path can read it"), both traced to
  the same root cause: `call-smoke-test.sh`/`trunk-smoke-test.sh` (both
  TASK-0027 code, untouched by this task) compute their CDR report
  date-range filter from the Asterisk container's **local** `date`
  (`America/Sao_Paulo`, UTC-3), while `cdr.calldate` is stored in UTC.
  The two clocks only disagree on the calendar day during the last three
  hours of the local day (21:00–23:59 `-03`), which is exactly when this
  run executed — confirmed live: container `date` read
  `2026-08-29 22:12:03 -03` while the run's own new CDR row stored
  `calldate=2026-08-30 01:06:02`. This is a pre-existing, deterministic,
  wall-clock-window bug in TASK-0027-owned test scripts, unrelated to any
  SQL-boundary code changed here; per CLAUDE.md it is documented rather
  than fixed in this task, and per the user's explicit choice the
  regression pair was re-run after waiting for local midnight to pass
  rather than patching call-smoke/trunk-smoke's date logic.
- `make regression`, second full run (after local midnight passed, so the
  local-day/UTC-day divergence window was closed): all 12 suites PASS,
  including `call-smoke` and `trunk-smoke` — confirming the first run's
  failures were exactly the timing window described above and not a code
  regression.
- `make regression`, third full run (immediately following, to confirm
  repeatability): all 12 suites PASS again, byte-for-byte the same result.
- Post-regression health checks: `app`/`asterisk`/`db`/`provider`
  containers all `Up`/`healthy`; `res_pjsip.so` loaded and `Running`;
  the 3 baseline PJSIP transports (`tcp`, `udp`, `wss`) intact; ODBC DSN
  `snep` active with its expected connection; 0 active channels; 0 new
  PHP Fatal Errors since baseline; no `task0026c_csvie_test` table, no
  `peer_type='T'` orphans, no `task00%`-named throwaway users/profiles
  remain (the persistent `task0026a-restricted`/`task0026c-restricted`
  dev-only fixture users are an intentional, pre-existing reusable-fixture
  pattern shared with `authorization-smoke-test.sh`, not residue); no
  smoke-test/baresip processes left running.
- `git diff --check`: clean (no whitespace/EOL errors).
- `git status --short` / `git diff --stat`: exactly the 10 modified files
  and 3 new files listed in [Files changed](#7-files-changed) — no
  incidental or out-of-scope changes.
- Full diff review: every changed line is either a raw-SQL-to-
  parameterized-binding conversion, the finite allowlist added for F11,
  or an explanatory comment; no unrelated refactoring, renaming, or
  behavior change found.
