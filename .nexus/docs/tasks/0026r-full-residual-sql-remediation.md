# TASK-0026R — Full residual SQL remediation

## Status

Implementation complete and validated. All four Q-SQL findings from
TASK-0026Q's full supported-surface SQL injection audit
(`docs/tasks/0026q-full-sql-injection-audit.md`) are fixed, live-verified,
and covered by a permanent, extended focused security suite. Two
consecutive full `make regression` runs both PASS, 22/22 suites. A
post-remediation independent SQL audit sweep (Phase 5) found **zero** new
exploitable SQL injection sinks.

```text
Q-SQL findings open = 0
RESIDUAL_SQL_GATE = CLOSED
```

Not committed — this is the validated TASK-0026R checkpoint, awaiting
explicit authorization to commit.

**One unrelated, non-SQL-injection finding surfaced during this task's own
Phase 5 sweep and is disclosed prominently here rather than buried**: a
previously-undocumented, unauthenticated, web-reachable legacy database
migration script (`snep/install/database/update/betha/convert-data-rc3.php`)
attempted a real, unauthenticated `ALTER TABLE ... DROP FOREIGN KEY`
against the live dev database when this task's own reachability probe
(`curl`) requested it. It failed immediately — the referenced foreign-key
name does not exist in the current schema — so **no actual database
change occurred** (independently confirmed: `core_peer_groups` remained
at 0 rows, the exact foreign-key constraint check that its own first
statement targets was re-verified unaffected). This is not a SQL
injection (every value it interpolates is DB-derived, never
request-controlled) and is therefore out of this task's own SQL-only
scope to fix — it is documented in the Product Readiness handoff (§9/§12)
as debt requiring a dedicated future task, and reported here transparently
per this project's own safety discipline around unplanned side effects
during testing.

---

## 1. Executive summary

TASK-0026Q's audit inventoried four residual SQL-injection findings as
the entire remaining supported-surface boundary. This task fixes all
four, using the same mechanical `$db->quoteInto()`/bound `->where('col =
?', $val)` pattern this program has now used a dozen times over
(TASK-0026C/F1/J/K/L/M/N/O/P and this task):

| ID | Fix | Files |
|---|---|---|
| Q-SQL-001 | `Snep_Cnl::getState()`/`getCityCode()`/`getPrefix()` + `getCity()` sibling | `snep/lib/Snep/Cnl.php` |
| Q-SQL-002 | `Snep_Permission_Manager::removePermissionUser()`/`addPermissionUser()`/`removePermissionProfile()` | `snep/lib/Snep/Permission/Manager.php` |
| Q-SQL-003 | `PBX_Trunks::get()` (single shared sink, three entry points) | `snep/lib/PBX/Trunks.php` |
| Q-SQL-004 | `estados.php`/`cidades.php` (ported off removed `mysql_*` onto `Zend_Db`, parameterized in the same change) | `snep/includes/estados.php`, `snep/includes/cidades.php` |

Every fix was live-verified against the running dev database: a
legitimate lookup still works, an apostrophe-shaped payload causes no SQL
syntax error, and a boolean-injection-shaped payload cannot cross-affect
a second, differently-named fixture. Q-SQL-003's second-order path (a
malicious `DiscarTronco` rule action's `tronco` config, planted via
`RouteController`, triggered later via the Simulator) was independently
proven closed by reproducing the exact plant-then-trigger data flow.
Q-SQL-004's two direct HTTP entry points (`SimulatorController`'s own
`trunk` field, `RouteController::parseRuleFromPost()`'s `srcValue`/
`dstValue` `T:` tokens) were proven closed through the real, unmodified,
authenticated web application — not merely direct PHP invocation.

`scripts/residual-sql-security-smoke-test.sh` grew from 216 to 270
checks (54 new), covering all four findings permanently. Every one of the
216 pre-existing checks (TASK-0026J–P, BLOCKER A–P1) still passes
unchanged. Two consecutive full `make regression` runs both PASS, 22/22
suites, no code changes between them.

A post-remediation independent SQL audit sweep (Phase 5, re-applying
TASK-0026Q's own grep-driven methodology against the current tree)
confirmed:

```text
EXPLOITABLE_DIRECT = 0
EXPLOITABLE_SECOND_ORDER = 0
VULNERABLE_BUT_CURRENTLY_UNREACHABLE = 0
NEEDS_MANUAL_REVIEW = 0
```

No new task is proposed for SQL injection. TASK-0026Q's own file-count
scope (336 files) did not explicitly enumerate the small
`snep/install/database/update/` subtree (2 files); this task's sweep
closed that specific gap and found both files SQL-injection-safe (every
interpolated value is DB-derived, never request-controlled) — see §9/§10
for the full accounting, including the one non-SQL finding disclosed
above.

---

## 2. Q-SQL baseline (from TASK-0026Q)

Reconstructed here, not merely re-cited, per this task's own Phase 1
instruction — each row re-traced against current source before any code
was changed:

```text
ID:                Q-SQL-001
File:               snep/lib/Snep/Cnl.php
Entry point:        CnlController::updateAction_76() -- fixed-width
                     uploaded-file (.zip -> .txt) column parsing
                     (substr($line,0,2)/substr($line,61,50)/
                     substr($line,116,7))
Source:              Uploaded file content, fully attacker-controlled
Sink:                getState()/getCityCode()/getPrefix(): raw
                     "'$var'"-shaped ->where() interpolation
Reachability:        AUTHENTICATED_PERMISSIONED (default_cnl_read is
                     sufficient -- the `cnl` resources.xml entry has no
                     declared children, matching the module-settings/
                     route/users pattern) + UPLOAD_FLOW
Direct/second-order: DIRECT
Chosen remediation:  $db->quoteInto()/bound ->where('col = ?', $val) at
                     all three sites, plus the getCity() sibling
Expected files:      snep/lib/Snep/Cnl.php

ID:                Q-SQL-002
File:               snep/lib/Snep/Permission/Manager.php
Entry point:        UsersController::permissionAction() (raw
                     $_POST['user']); ProfilesController::permissionAction()
                     (raw route/query id)
Source:              $_POST['user'] / route param `id`, zero cast
Sink:                removePermissionUser()/addPermissionUser(): raw
                     "'$var'"-shaped array-form WHERE fragment;
                     removePermissionProfile(): raw UNQUOTED "$var"
                     fragment (most severe interpolation shape found)
Reachability:        AUTHENTICATED_PERMISSIONED (default_users_write /
                     default_profiles_write)
Direct/second-order: DIRECT
Chosen remediation:  $db->quoteInto('col = ?', $val) pre-built into each
                     int-keyed $where[] entry (Zend_Db_Adapter_Abstract::
                     _whereExpr() uses an int-keyed entry as a literal,
                     already-safe condition string verbatim)
Expected files:      snep/lib/Snep/Permission/Manager.php

ID:                Q-SQL-003
File:               snep/lib/PBX/Trunks.php
Entry point 1:      SimulatorController::indexAction() -- POST field
                     `trunk`, srcType=trunk (authenticated-open, any
                     logged-in account, no permission grant needed)
Entry point 2:      RouteController::parseRuleFromPost() -- POST fields
                     srcValue/dstValue, T:<value> tokens
                     (default_route_write)
Entry point 3:      SimulatorController::indexAction()'s own
                     action-description renderer
                     (PBX_Trunks::get($config['tronco'])) -- second-order
                     via a persisted DiscarTronco rule action's own
                     `tronco` config, planted with zero validation via
                     RouteController::addAction()/editAction() ->
                     Snep_Rule_ActionConfig::parseConfig() (inherited
                     unchanged from PBX_Rule_ActionConfig, a straight
                     $post[field] passthrough), default_route_write to
                     plant, any authenticated user to trigger
Source:              Raw POST value (entry points 1/2); persisted,
                     unvalidated rule-action config (entry point 3)
Sink:                get($id): ->where("id = $id") -- UNQUOTED, no
                     surrounding string literal at all
Direct/second-order: DIRECT (entry points 1, 2); SECOND-ORDER (entry
                     point 3)
Chosen remediation:  $db->select()->from('trunks')->where('id = ?', $id)
                     -- one fix at the single shared sink closes all
                     three entry points simultaneously
Expected files:      snep/lib/PBX/Trunks.php

ID:                Q-SQL-004
Files:               snep/includes/estados.php, snep/includes/cidades.php
Entry point:         Apache serves both files directly, unauthenticated
                     -- neither goes through Zend_Controller_Front/
                     Snep_AuthPlugin/Snep_PermissionPlugin at all. Wired
                     into the UI via jQuery('#city'/'#state').load(...)
                     from the registration wizard
                     (modules/default/views/layouts/register.phtml) and
                     the Contacts add/edit form
                     (modules/default/views/scripts/contacts/addedit.phtml)
                     -- re-confirmed live call sites this task (§6).
Source:              $_GET['pais'] / $_GET['estado'], raw, no framework
                     filtering
Sink:                Raw mysql_query() string concatenation, unquoted in
                     the numeric branch, single-quoted-but-unescaped in
                     the non-numeric branch
Reachability:        UNAUTHENTICATED, but VULNERABLE_BUT_CURRENTLY_UNREACHABLE
                     at TASK-0026Q's own checkpoint -- blocked entirely
                     by the removed mysql_connect()/mysql_query()
                     extension (PHP 8 fatal at the very first line, before
                     the SQL string is ever built)
Direct/second-order: DIRECT
Chosen remediation:  Outcome B (still-required endpoint, confirmed via
                     live call-site re-verification, §6) -- port onto
                     Zend_Db (Snep_Db::getInstance()) and parameterize in
                     the same change, per this task's own "reachability
                     and SQL safety must be solved together" rule.
                     Deliberately left unauthenticated, matching the
                     ip_status_trunks.php/ip_status_peers.php sibling
                     pattern in the same directory -- authentication-model
                     changes are out of this task's scope.
Expected files:      snep/includes/estados.php, snep/includes/cidades.php
```

No baseline classification changed during reconstruction — all four
matched TASK-0026Q's own documented findings exactly.

---

## 3. Q-SQL-001 remediation — `Snep_Cnl`

**Before** (all three, `snep/lib/Snep/Cnl.php`):

```php
->where("id = '$state'")->where("country = '$country'");          // getState
->where("name = '$name'")->where("state = '$state'");             // getCityCode
->where("id = '$prefix'")->where("country = '$country'");         // getPrefix
->where("p.id = '$prefix'");                                      // getCity (sibling)
```

**After**:

```php
->where('id = ?', $state)->where('country = ?', $country);        // getState
->where('name = ?', $name)->where('state = ?', $state);           // getCityCode
->where('id = ?', $prefix)->where('country = ?', $country);       // getPrefix
->where('p.id = ?', $prefix);                                     // getCity (sibling)
```

**Sibling audit**: `getCountries()` (fully static, no interpolation),
`addState()`/`addCity()`/`addPrefix()` (`$db->insert()` only, natively
bound), `parseName()` (no SQL) — all already safe, unchanged. No
unexplained raw interpolation remains anywhere in this class (`grep -n
"where(\""` returns zero matches post-fix).

**Live verification** (direct invocation, real `core_cnl_country`/
`core_cnl_state`/`core_cnl_city`/`core_cnl_prefix` fixture chain,
apostrophe- and boolean-shaped payloads): all four methods' legitimate
lookups return correct fixture data; apostrophe payloads produce no SQL
exception; boolean-injection payloads (`"nonexistent' OR id='<fixture>"`
shape) return zero rows, never cross-matching the fixture. Fixed
alongside CNL import behavior, uploaded-file parsing, and authorization —
none of which were touched.

---

## 4. Q-SQL-002 remediation — `Snep_Permission_Manager`

**Before** (`snep/lib/Snep/Permission/Manager.php`):

```php
$where[] = "user_id = '$id'";        // removePermissionUser, addPermissionUser
$where[] = "profile_id = $id";       // removePermissionProfile -- UNQUOTED
```

**After**:

```php
$where[] = $db->quoteInto('user_id = ?', $id);
$where[] = $db->quoteInto('profile_id = ?', $id);
```

Confirmed via direct read of `Zend_Db_Adapter_Abstract::_whereExpr()`
(`snep/lib/Zend/Db/Adapter/Abstract.php:676-701`): an int-keyed `$where[]`
entry is used verbatim as a complete condition (only unwrapped if it's a
`Zend_Db_Expr` object) — pre-building the fragment via `$db->quoteInto()`
is exactly correct and matches the exact shape `Zend_Db_Adapter_Abstract::
delete()`/`update()` expect.

**Sibling audit**: every other method in this class
(`getAllPermissions()`, `getAllPermissionsUser()`, `existPermission()`,
`getPermissions()`, `getIdProfile()`, `get()`, `getUser()`) already used
bound `->where('col = ?', $val)` — re-confirmed via full-file grep
(`grep -n "\$db->\|->where("` — every `->where(` site now bound, zero raw
interpolation remains).

**Live verification**: real HTTP through both entry points
(`UsersController::permissionAction()`, `ProfilesController::
permissionAction()`) confirms apostrophe payloads cause no `42000`-class
SQL syntax error (a distinct `SQLSTATE 22007` — MariaDB strict mode
rejecting a non-numeric string bound against the `users_permissions.
user_id`/`profiles_permissions.profile_id` int columns — is expected and
harmless, see §12's own note). Direct-invocation coverage with real
victim fixtures confirms: apostrophe- and boolean-shaped payloads never
affect the victim's own rows; a legitimate call correctly targets the
real row end to end for `removePermissionUser()`/`addPermissionUser()`;
`removePermissionProfile()`'s own pre-existing, unrelated `'allow' =>
false` bool-cast bug (see §9) is used as *positive* proof the WHERE
clause targets the real row precisely (the type-rejection only fires once
a real row is matched — MariaDB validates a row's new values while
writing that row, not before matching it).

---

## 5. Q-SQL-003 remediation — `PBX_Trunks::get()`

**Before** (`snep/lib/PBX/Trunks.php`):

```php
$select = $db->select()->from('trunks')->where("id = $id");
```

**After**:

```php
$select = $db->select()->from('trunks')->where('id = ?', $id);
```

`PBX_Trunks::get()` is the only method in this class with SQL
interpolation of its own (`getAll()` only calls `self::get()` in a loop
over an already-safe, no-`WHERE` select). One fix at this single shared
sink closes all three entry points simultaneously.

**Direct proof (Phase 2 exploit proof)**:

| Payload | Pre-fix (TASK-0026Q's own live proof) | Post-fix (this task) |
|---|---|---|
| `PBX_Trunks::get("foo'bar")` | `SQLSTATE[42000]: ...near ''bar)' at line 1` | Clean `PBX_Exception_NotFound` |
| `PBX_Trunks::get("0 OR id=<canary>")` | matched an arbitrary row by primary key | Clean `PBX_Exception_NotFound`, canary untouched |

**Entry point 1 (Simulator `trunk` field) — real HTTP**: an authenticated
`srcType=trunk&trunk=foo'bar` POST (zero-permission `task0026j-restricted`-
style fixture session) produces no `42000`-class log entry — only a
clean `ErrorController: uncaught PBX_Exception_NotFound: Trunk foo'bar
not found`. A control probe (a legitimate-shaped but nonexistent numeric
trunk id, `trunk=999999`) produces the **identical** clean-NotFound
signature, confirming this HTTP 500 shape is a pre-existing, unrelated
gap (`SimulatorController`'s `srcType=="trunk"` branch has no try/catch
around `PBX_Trunks::get()`, unlike the `srcType=="exten"` branch) — not a
regression from this fix (see §9).

**Entry point 2 (`RouteController::parseRuleFromPost()` `T:` token) — real
HTTP**: an authenticated `srcValue=T:foo'bar` POST to `route/add`
produces `ErrorController: uncaught PBX_Exception_BadArg: Tronco inválido
para origem da regra` — `parseRuleFromPost()`'s own try/catch around
`PBX_Trunks::get()` converts the now-clean `PBX_Exception_NotFound` into
this application-level validation error. No rule is persisted
(`regras_negocio` row count confirmed 0 for the probe's `desc`).

**Entry point 3 (second-order, `DiscarTronco` config) — direct
invocation, full plant-then-trigger reproduction**: constructed a real
`DiscarTronco` action (`setConfig(['tronco' => "foo'bar", ...])`),
attached it to a `PBX_Rule` via `addAcao()`, persisted via
`PBX_Rules::register()` (the same `$db->insert()`-based, already-safe
persistence path `RouteController::addAction()` itself uses). Reloaded
the rule via `PBX_Rules::get()` — confirmed the malicious `tronco` value
round-trips verbatim (`$action->getConfigArray()['tronco'] === "foo'bar"`,
proving `Snep_Rule_ActionConfig::parseConfig()`'s real, unvalidated
passthrough behavior). Reproduced `SimulatorController::indexAction()`'s
own action-description-renderer call
(`PBX_Trunks::get($config['tronco'])`) directly against that reloaded
config — clean `PBX_Exception_NotFound`, confirming the second-order path
is closed by the same single fix.

**Sibling audit**: no other `PBX_Trunks` method builds SQL. `RouteController`,
`RouteFormController`, `Snep_Route`, `PBX_Rules`, `PBX_Rule`, `PBX_Usuarios`
were all re-confirmed unchanged/already-safe (§9's re-verification table).

---

## 6. Q-SQL-004 decision/remediation — `estados.php`/`cidades.php`

**Reachability determination (Phase 1's required
`CURRENT CALL SITES FOUND` / `ENDPOINT NEEDED` report)**:

```text
CURRENT CALL SITES FOUND:
  - snep/modules/default/views/layouts/register.phtml:288,293
    (jQuery('#city'/'#state').load(...cidades.php?estado=/...estados.php?pais=))
  - snep/modules/default/views/scripts/contacts/addedit.phtml:264
    (jQuery('#city').load(...cidades.php?estado=))
ENDPOINT NEEDED: YES -- Outcome B (still-required endpoint)
```

Both files are real, actively-wired AJAX helpers behind the registration
wizard and the Contacts add/edit form — not dead code. Per this task's
own decision rule, they were ported rather than removed.

**estados.php — before**:

```php
$setup = parse_ini_file("setup.conf");
$idpais = $_GET['pais'];
mysql_connect($setup["db.host"],$setup["db.username"],$setup["db.password"]);
mysql_selectdb($setup["db.dbname"]);
if (is_numeric($idpais) ) {
    $result = mysql_query("SELECT id,name FROM core_state WHERE country_id = ".$idpais);
} else {
    $result = mysql_query("SELECT id,name FROM core_cnl_city WHERE country = '".$idpais."'");
}
if ($idpais != 1) { echo "<option value=28>Others</option>"; }
else { while($row = mysql_fetch_array($result)){ echo "<option value='".$row['id']."'>".$row['name']."</option>"; } }
```

**estados.php — after**:

```php
define('APPLICATION_PATH', realpath(dirname(__FILE__) . '/..'));
set_include_path(implode(PATH_SEPARATOR, array(APPLICATION_PATH . '/lib', get_include_path())));
require_once 'Snep/Config.php';
require_once 'Snep/Db.php';
Snep_Config::setConfigFile(dirname(__FILE__) . '/setup.conf');
$db = Snep_Db::getInstance();
$idpais = $_GET['pais'];
if (is_numeric($idpais)) {
    $select = $db->select()->from('core_state', array('id', 'name'))->where('country_id = ?', $idpais);
} else {
    $select = $db->select()->from('core_cnl_city', array('id', 'name'))->where('country = ?', $idpais);
}
$result = $db->query($select)->fetchAll();
if ($idpais != 1) { echo "<option value=28>Others</option>"; }
else { foreach ($result as $row) { echo "<option value='".$row['id']."'>".$row['name']."</option>"; } }
```

`cidades.php` mirrors the same transformation (`core_city.state_id` for
the numeric branch, `core_cnl_city.state` for the non-numeric branch —
see the file itself for the exact diff). `Snep_Db::getInstance()` only
requires `Snep_Config::getConfig()` to already point at the real
`setup.conf` (confirmed via direct read of `snep/lib/Snep/Db.php`) — it
does **not** need the full `Zend_Application`/`Zend_Controller_Front`
bootstrap, matching the lightest-weight correct connection path
available, not a heavier one than necessary.

**Query targets, the `is_numeric()`-branched table choice, and
`estados.php`'s own `"if ($idpais != 1)"` output-suppression quirk are
all preserved byte-for-byte** — only the connection method and the
SQL-construction mechanism changed, per this task's own "preserve
expected response behavior" / "do not redesign" instructions.

**A genuine, pre-existing, unrelated schema bug was discovered while
porting `estados.php`'s non-numeric branch** (see §9) — `core_cnl_city`
has no `country` column in this project's actual schema (only `id`,
`name`, `state`). This was **not** introduced by this fix (the original
`mysql_query` targeted the identical, already-nonexistent column — the
bug is the query target itself, not the connection layer) and was **not**
silently "corrected" by guessing the intended column, per CLAUDE.md's "do
not fix unrelated legacy bugs opportunistically." It is documented as
Product Readiness debt (§9/§12), and this task's own regression coverage
(§8) explicitly distinguishes this harmless, pre-existing
`SQLSTATE[42S22]` (column not found) signature from a `SQLSTATE[42000]`
syntax-error signature (which would indicate injection) in every relevant
check.

**Authentication decision, explicitly considered per this task's own
instruction**: left unauthenticated, deliberately, matching this same
directory's own established `ip_status_trunks.php`/`ip_status_peers.php`
sibling pattern (same "unauthenticated same-origin AJAX helper, outside
the main Zend MVC auth boundary" architecture, already an accepted
pattern in this codebase per TASK-0026K/L/Q's own classification of those
two files). Authentication-model changes are explicitly out of this
task's scope (`Do not redesign authorization` / `Do not touch
scope boundaries`); the SQL-injection class this task exists to close is
now closed regardless of who can reach the endpoint.

**Live verification**: real, unauthenticated HTTP requests (zero cookies)
against both files, with real `core_state`/`core_city`/`core_cnl_country`/
`core_cnl_state`/`core_cnl_city` fixtures: legitimate numeric lookups
(both files) and the legitimate non-numeric lookup (`cidades.php`'s own
`core_cnl_city.state` branch) all return correct fixture data.
Apostrophe-shaped input causes no `42000`-class syntax error on either
file. A boolean-injection-shaped `estado` value (`"nonexistent' OR
state='TR"`) cannot leak the CNL-city fixture through `cidades.php`'s
non-numeric branch. Both files remain reachable with zero authentication,
unchanged from before this fix (by design, see above).

---

## 7. Direct vs second-order closure

```text
Q-SQL-001: DIRECT                      -- CLOSED (3 methods + 1 sibling)
Q-SQL-002: DIRECT                      -- CLOSED (3 methods)
Q-SQL-003: DIRECT (2 entry points)     -- CLOSED (1 shared sink fix)
           SECOND-ORDER (1 entry point) -- CLOSED (same shared sink fix,
                                            independently reproduced via
                                            full plant-then-trigger flow)
Q-SQL-004: DIRECT                      -- CLOSED (2 files)
```

Every finding's own reachability paths — direct and second-order alike —
were independently reproduced pre-fix-equivalent (via TASK-0026Q's own
citations, re-confirmed) and post-fix (this task, live), not merely
asserted from the fix's mechanical shape.

---

## 8. Focused regression coverage

`scripts/residual-sql-security-smoke-test.sh` extended in place (not a
new suite), preserving every existing TASK-0026J–P check (BLOCKER A–P1,
216 checks) unchanged. New coverage: 54 checks across the four findings.

```text
make residual-sql-security-smoke
PASS: 270   FAIL: 0
```

| Finding | New checks | Method |
|---|---|---|
| Q-SQL-001 | 12 | Direct invocation (CnlController's real entry point requires a `.zip` upload — orthogonal complexity, matching this program's own established precedent of testing the real vulnerable sink directly when the full HTTP flow adds unrelated complexity, e.g. TASK-0026N's `PBX_Rules` coverage) |
| Q-SQL-002 | 17 | 2 real-HTTP (both entry points' apostrophe proof) + 15 direct-invocation (boolean isolation, legitimate end-to-end, the `removePermissionProfile()` pre-existing-bug-as-proof pattern) |
| Q-SQL-003 | 11 | 3 real-HTTP (Simulator apostrophe, RouteController apostrophe, no-persistence proof) + 8 direct-invocation (boolean isolation, full second-order plant-then-trigger reproduction) |
| Q-SQL-004 | 14 | All real, unauthenticated HTTP (legitimate lookups ×3, apostrophe ×2, boolean isolation ×1, signature-precise fatal-count checks ×2, unauthenticated-reachability-preserved ×1, fixture/health bookkeeping) |

No TASK-0026J–P coverage regressed.

---

## 9. Post-remediation independent SQL audit

Per Phase 5's explicit instruction, this is a **re-application of
TASK-0026Q's own grep-driven methodology against the current tree**, not
a repeat of the same four narrow searches that found Q-SQL-001–004.

**Heuristic 1 — raw `'$var'` interpolation** (`grep -rlE
"(where|query)\(.*'\\\$[A-Za-z_]" snep --include='*.php'`, excluding
`snep/lib/Zend/`):

```text
snep/lib/Snep/Alerts.php          DEAD/UNREACHABLE (TASK-0026Q, re-confirmed)
snep/lib/PBX/Registry.php         ALLOWLISTED_IDENTIFIER (TASK-0026P/Q, re-confirmed)
snep/lib/Snep/Operadoras.php      DEAD/UNREACHABLE (TASK-0026Q, re-confirmed)
snep/lib/Snep/Manutencao.php      DEAD/UNREACHABLE (TASK-0026Q, re-confirmed)
snep/lib/Snep/Extensions.php      DEAD/UNREACHABLE (TASK-0026Q, re-confirmed)
snep/lib/Snep/Dashboard/Manager.php  SAFE_DB_DERIVED_NON_USER_CONTROLLED (TASK-0026K/Q, re-confirmed)
```

`Snep_Cnl.php` and `Snep_Permission/Manager.php` no longer appear in this
heuristic's hit list — direct confirmation the fix removed the pattern,
not merely reclassified it.

**Heuristic 2 — `{$var}` double-quoted interpolation near
`where`/`query`/`delete`/`update`**:

```text
snep/agi/padlock.php                          AGI_ONLY (TASK-0026Q, re-confirmed)
snep/lib/PBX/Registry.php                     ALLOWLISTED_IDENTIFIER (re-confirmed)
snep/lib/Snep/Extensions.php                  DEAD/UNREACHABLE (re-confirmed)
snep/modules/billing/lib/Billing/Manager.php  PARAMETERIZED_SAFE (TASK-0026M, re-confirmed)
snep/modules/portability/actions/PortabilityAction.php  AGI_ONLY (TASK-0026K/Q, re-confirmed)
```

`snep/lib/PBX/Trunks.php` no longer appears — confirms the fix removed
the pattern.

**Heuristic 3 — `mysql_query`/`mysql_connect`/`mysql_fetch` anywhere**:

```text
snep/install/database/update/3.01/updateCallerid.php   see below (new to this sweep)
snep/includes/estados.php / cidades.php                false positive -- only this
                                                         task's own doc-comment text
                                                         mentioning "mysql_connect()"
                                                         as historical context; zero
                                                         actual mysql_* calls remain
```

**Newly examined this task — `snep/install/database/update/`** (2 PHP
files; not explicitly broken out in TASK-0026Q's own 336-file family
table, though both are excluded-from-vendor first-party PHP and would
have been swept by any file-count that actually reached this
subdirectory — see §10 for the completeness note):

```text
snep/install/database/update/3.01/updateCallerid.php
  -- one-time DB migration script from the 3.0 stable release, hardcoded
     stale credentials ("localhost"/"snep"/"sneppass", not setup.conf),
     zero callers anywhere in the tree, uses mysql_connect()/mysql_query()
     (undefined under PHP 8 -- confirmed live, HTTP 500 identical to
     Q-SQL-004's pre-fix state). Its own UPDATE statement interpolates
     $new_callerid/$name -- but both are read from the SAME `peers` table
     two lines earlier (SELECT callerid,name FROM peers), never from
     $_GET/$_POST/CLI args/uploaded file. Classification:
     SAFE_DB_DERIVED_NON_USER_CONTROLLED, additionally DEAD in practice
     (blocked by the same removed-mysql_* class of bug Q-SQL-004 had).

snep/install/database/update/betha/convert-data-rc3.php
  -- one-time DB migration script from the "betha"/rc3 pre-release cycle.
     Uses real PDO (not mysql_*), reads setup.conf via an absolute path,
     so it DOES run under PHP 8. Every interpolated value ($row['id'],
     $grupo) is read from the SAME database two statements earlier
     (SELECT id,name,`group` FROM peers ...), never from any external
     input. Classification: SAFE_DB_DERIVED_NON_USER_CONTROLLED for SQL
     injection purposes specifically.

     CONFIRMED LIVE, DURING THIS TASK'S OWN REACHABILITY PROBE: Apache
     serves this file directly (HTTP 200, zero authentication -- no
     .htaccess protects snep/install/ at all). The probe (a plain `curl`,
     no payload) caused the script to execute for real against the live
     dev database up to its own first statement (`ALTER TABLE peers DROP
     FOREIGN KEY peers_ibfk_1`), which failed immediately
     (SQLSTATE[42000]: 1091, that constraint name does not exist in the
     current schema) -- confirmed via mag-error.log and via re-querying
     information_schema.TABLE_CONSTRAINTS and core_peer_groups (0 rows,
     unaffected) that NO actual database change occurred. This is,
     however, real evidence of an unauthenticated, web-reachable script
     capable of destructive DDL against the live database using
     credentials read from setup.conf -- NOT a SQL-injection finding
     (no external value alters query syntax; every value is DB-derived),
     and therefore explicitly outside this task's own SQL-only scope to
     fix. Disclosed prominently in this document's own Status section
     and handed off as Product Readiness debt (§12) -- a dedicated future
     task should block direct web access to snep/install/ entirely
     (matching how snep/includes/.htaccess already blocks *.conf files)
     regardless of this specific script's own current schema-mismatch
     "safety."
```

**Conclusion**:

```text
EXPLOITABLE_DIRECT = 0
EXPLOITABLE_SECOND_ORDER = 0
VULNERABLE_BUT_CURRENTLY_UNREACHABLE = 0
NEEDS_MANUAL_REVIEW = 0
```

No genuinely exploitable SQL sink that TASK-0026Q missed was found. Per
this task's own Phase 5 instruction, this is reported without creating a
new SQL-injection task — the one new finding (`convert-data-rc3.php`'s
unauthenticated reachability) is a **different vulnerability class**
(unauthenticated destructive action, not SQL injection) and is handed off
as Product Readiness debt instead, exactly as this phase's own
instruction anticipates for non-SQL discoveries.

---

## 10. TASK-0026Q audit-quality assessment

**Did TASK-0026Q successfully bound the remaining SQL vulnerability
universe? Yes, for SQL injection specifically.** This task's independent
post-remediation sweep (§9), re-applying the same methodology against the
current tree, found zero additional exploitable SQL sinks beyond the four
TASK-0026Q already identified. Every one of TASK-0026Q's own
classifications for previously-audited files (dead code, AGI-only,
allowlisted, DB-derived) was independently re-confirmed, not merely
re-cited.

**One completeness gap, honestly disclosed**: TASK-0026Q's own executive
summary states "This audit inventoried 336 first-party PHP files
(excluding snep/lib/Zend/)." `snep/install/database/update/`'s 2 files
are first-party PHP, outside `snep/lib/Zend/`, and were not individually
named anywhere in TASK-0026Q's own family/coverage table (§9 of that
document) — a minor file-inventory gap, not a missed vulnerability: this
task's own re-sweep of that specific subtree found both files
SQL-injection-safe. The gap is worth naming precisely because it is
exactly the kind of small, easy-to-miss corner a 336-file sweep can slip
past, and because it is where this task's own Phase 5 sweep found the one
disclosed non-SQL finding (§9's `convert-data-rc3.php`) — a useful data
point for judging this program's own audit methodology going forward:
grep-driven sweeps bound *the patterns they search for* reliably, but
remain only as complete as their own file-enumeration step, which is
worth double-checking (e.g. `find snep -name '*.php' | wc -l` against the
audit's own claimed count) at the start of any future full sweep.

---

## 11. Canonical validation

- `php -l` on all 5 touched application files: clean.
- `bash -n` on the extended smoke script: clean.
- `make lint`: **PASS, 5/5** (271 PHP files, 0 syntax errors; 24 shell
  scripts; 3 `resources.xml` files well-formed; clean `git diff --check`).
- `make residual-sql-security-smoke`: **PASS, 270/270** (up from 216/216).
- `make regression`, official run 1: **PASS, 22/22 suites.**
- `make regression`, official run 2 (immediately after, no code changes,
  no manual cleanup in between): **PASS, 22/22 suites**, byte-identical
  result to official run 1.

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

No FAIL, no BLOCKED, no INCONCLUSIVE, in either official run. Every
security-specific suite named in Phase 9's own checklist — `authorization-
coverage`, `authorization-smoke`, `api-security`, `api-sql-security`,
`session-csrf-security`, `auth-hardening-security`, `disclosure-path-
security`, `sql-security`, `residual-sql-security` — independently PASSed
in both runs, not merely folded into the aggregate count.

---

## 12. Health and cleanup

- `docker compose ps`: `app`/`asterisk`/`db`/`provider` all `Up
  (healthy)`.
- Asterisk **22.11.0** (matches the repository's pinned version,
  `docker/asterisk.Dockerfile`, unchanged by this task).
- `res_pjsip.so` — 1 module, Running.
- `pjsip show transports`: 3 baseline transports intact (`tcp`, `udp`,
  `wss`).
- AMI: `manager show connected` responsive, 0 connected users.
- ODBC: `snep` DSN, 1/1 active connection.
- `core show channels count`: 0 active channels, 0 active calls.
- PHP Fatal Error signature check: 12 total, all attributable to either
  (a) pre-existing, already-documented signatures (`CallsReportController.
  php:402`'s `count()`/`Countable` bug ×7, `Zend/Validate/File/Upload.php`'s
  identical bug class ×1, `updateCallerid.php`'s pre-existing
  `mysql_connect()` bug ×1), (b) this task's own intentional, signature-
  verified Q-SQL-004 proof (the `estados.php` column-mismatch signature
  ×1), or (c) the disclosed `convert-data-rc3.php` reachability probe
  (×2, confirmed zero actual database change, see Status/§9) — zero
  unexplained new fatals.
- Fixture residue: zero across every table touched by any of the four
  findings' fixtures (`core_cnl_country`/`core_cnl_state`/`core_cnl_city`/
  `core_cnl_prefix`, `core_state`/`core_city`, `users`/`profiles`
  task0026r-prefixed rows, `trunks`, `regras_negocio` task0026r-prefixed
  rows) — independently re-queried and confirmed 0 in every case.
- No leftover smoke-test/baresip processes or containers, host or
  container side.
- No leftover temp files in the app container.
- `git diff --check`: clean.
- `git diff --stat` / `git status --short`: exactly the 6 modified files
  listed below, plus the untracked `.nexus/` (unrelated, untouched, per
  every prior TASK-0026x task's own convention).

```text
 scripts/residual-sql-security-smoke-test.sh | 600 +++++++++++++++++++++++++++-
 snep/includes/cidades.php                   |  50 ++-
 snep/includes/estados.php                   |  45 ++-
 snep/lib/PBX/Trunks.php                     |   2 +-
 snep/lib/Snep/Cnl.php                       |  20 +-
 snep/lib/Snep/Permission/Manager.php        |   6 +-
 6 files changed, 670 insertions(+), 53 deletions(-)
```

---

## 13. Final gate state

```text
Q-SQL-001: CLOSED
Q-SQL-002: CLOSED
Q-SQL-003: CLOSED (direct x2 + second-order x1, one shared-sink fix)
Q-SQL-004: CLOSED (ported + parameterized in the same change)

RESIDUAL_SQL_GATE = CLOSED
```

Per this task's own instruction, `SECURITY_GATE`'s full re-evaluation
against `docs/SECURITY-BASELINE.md`'s "Security gate expectations" is
left for a follow-up TASK-0026Z-style closure re-run — this document
only certifies `RESIDUAL_SQL_GATE = CLOSED` and the validated TASK-0026R
checkpoint. The one disclosed non-SQL finding (§9/§12, `convert-data-
rc3.php`'s unauthenticated destructive-DDL reachability) should be
weighed by that closure re-run as new Product Readiness / pre-pilot
deployment-hardening debt, separate from the SQL-injection gate this
task closes.

Stopping at the validated TASK-0026R checkpoint, as instructed. Not
committed — awaiting explicit authorization.

## Files changed

```
snep/lib/Snep/Cnl.php                         Q-SQL-001 fix (4 sites)
snep/lib/Snep/Permission/Manager.php          Q-SQL-002 fix (3 sites)
snep/lib/PBX/Trunks.php                       Q-SQL-003 fix (1 site, 3 entry points)
snep/includes/estados.php                     Q-SQL-004 fix (mysql_* -> Zend_Db port + parameterize)
snep/includes/cidades.php                     Q-SQL-004 fix (mysql_* -> Zend_Db port + parameterize)
scripts/residual-sql-security-smoke-test.sh   TASK-0026R focused coverage (+54 checks, 216->270)
docs/tasks/0026r-full-residual-sql-remediation.md   new, this file
```

No other file was modified. `.nexus/` remains untouched. Product
Readiness work was not started. `snep/install/database/update/*.php` was
not modified (out of scope — not a SQL injection finding).
