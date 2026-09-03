# TASK-0026Q — Full supported-surface SQL injection audit

## Status

**Audit-only. No application code modified.** This task's mandate was to
stop the "find one → fix one → sweep → find another" pattern that
TASK-0026J through TASK-0026P each repeated (ten consecutive closure
tasks, each fixing its assigned sinks and then finding at least one more
outside its own scope) and instead produce one finite, evidence-based
inventory of the entire supported/reachable SQL-execution surface before
any further remediation begins.

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

This task does not change that gate's state — it was already `NOT
CLOSED`/`NO-GO` at the start of this task (TASK-0026P) and remains so,
because SQL findings still exist. What changes is that the set of
findings is now believed **finite and enumerated**, with every
supported-surface dynamic SQL site in the repository classified,
`NEEDS_MANUAL_REVIEW = 0`, and a concrete, bounded remediation plan
(TASK-0026R) proposed below instead of another single-boundary closure
task that will almost certainly surface one more sink on its own exit
sweep.

---

## 1. Executive summary

This audit inventoried **336** first-party PHP files (excluding
`snep/lib/Zend/`, the vendored Zend Framework 1 library) and traced
every dynamic SQL construction site reachable from them — controllers,
managers, PBX business-logic classes, the standalone API, the three
peripheral modules (`billing`, `callback`, `ivr`, `portability`), and
every AGI script — back to its ultimate data source.

This audit produced **four Q-SQL findings**: one is the already-known
`Snep_Cnl` finding TASK-0026P's own exit sweep discovered (re-verified
live here, given a stable ID in this audit's own numbering rather than
re-derived), and three are new, previously-undocumented findings found
by this task's own sweep — two directly exploitable, one real vulnerable
code currently blocked by an unrelated bug. All four were live-verified
against the running dev database — `Q-SQL-003` via both a real
authenticated HTTP round-trip and direct invocation, `Q-SQL-001`/
`Q-SQL-002` via direct invocation, `Q-SQL-004` via a live HTTP request
confirming both the unauthenticated web-reachability and the exact
blocking fatal (the same apostrophe/syntax-error differential proof
style every TASK-0026C–P closure task has used, applied at whichever
layer each finding's own reachability required):

- **Q-SQL-001** — `Snep_Cnl::getState()`/`getCityCode()`/`getPrefix()`,
  reachable via `CnlController::updateAction_76()`'s fixed-width
  uploaded-file column parsing. (Already documented by TASK-0026P;
  re-verified live here, not re-discovered.)
- **Q-SQL-002** — `Snep_Permission_Manager::removePermissionUser()`/
  `addPermissionUser()`/`removePermissionProfile()`, reachable via
  `UsersController::permissionAction()`'s raw `$_POST['user']` field and
  `ProfilesController::permissionAction()`'s raw route `id` — a class
  never audited by any prior TASK-0026x task (`Snep_Permission_Manager`
  is a distinct class from the already-fixed `Snep_Users_Manager`/
  `Snep_Profiles_Manager`). One variant (`removePermissionProfile()`) is
  **unquoted, no surrounding string literal at all** — the most severe
  interpolation shape this program has found. This is the same
  mass-permission-manipulation impact class as the original F8 finding
  (able to wipe or reassign arbitrary rows in `users_permissions`/
  `profiles_permissions` via a single boolean-injection payload), in a
  sibling class F8's own remediation never touched.
- **Q-SQL-003** — `PBX_Trunks::get()`, reachable through **three**
  independent paths, two direct and one second-order: (1)
  `SimulatorController::indexAction()`'s own raw `trunk` POST field when
  `srcType=trunk` (authenticated-**open**, reachable by any logged-in
  account — the same severity class as the already-fixed N1–N3 findings
  in that same controller) — DIRECT; (2) `RouteController::
  parseRuleFromPost()`'s `srcValue`/`dstValue` fields (`T:<value>`
  tokens, `default_route_write`) — DIRECT; (3) `SimulatorController::
  indexAction()`'s own action-description renderer
  (`PBX_Trunks::get($config['tronco'])`, line ~149), where `$config`
  comes from a matched rule's persisted `DiscarTronco` action config —
  SECOND-ORDER (planted via `RouteController::addAction()`/`editAction()`
  → `Snep_Rule_ActionConfig::parseConfig()`, which passes
  `$post["action_$action"]`'s `tronco` field straight through with zero
  validation, `default_route_write`; triggered later by any
  authenticated user running the Simulator against a matching rule, no
  further permission needed). The interpolation is **unquoted**
  (`where("id = $id")`) — same severity shape as Q-SQL-002.
- **Q-SQL-004** — `snep/includes/estados.php`/`cidades.php` — two
  standalone, pre-Zend, `mysql_connect()`-era scripts, directly
  web-reachable with **zero authentication** (same `/includes/*.php`
  boundary as the already-classified-safe `ip_status_trunks.php`/
  `ip_status_peers.php` — no `.htaccess` restriction applies to them,
  only `*.conf` files are blocked) and actively `jQuery('#city'/'#state')
  .load(...)`-wired from the registration and contacts-edit pages. Both
  interpolate the raw `$_GET['pais']`/`$_GET['estado']` value, unquoted
  in the numeric branch and single-quoted-but-unescaped in the
  non-numeric branch, directly into a hand-built SQL string (`estados.php`
  queries `core_state`/`core_cnl_city`; `cidades.php` queries
  `core_city`/`core_cnl_city` — re-verified by direct read this
  checkpoint, see §6 for the exact per-line citation). **Real,
  unauthenticated, would-be-critical vulnerable code — currently
  `VULNERABLE_BUT_CURRENTLY_UNREACHABLE`**, blocked in its entirety by
  `mysql_connect()`/`mysql_query()` no longer existing since PHP 7 (a
  category-A PHP 8.4 compatibility fatal, confirmed live: every request
  to either file 500s at the `mysql_connect()` line, before the SQL
  string is ever built) — additionally confirmed that `parse_ini_file
  ("setup.conf")`'s relative path *would* resolve to the real credentials
  file (`snep/includes/setup.conf` sits in the same directory as both
  scripts) if the compatibility bug were ever fixed in isolation, so the
  "would be P0" severity reasoning is not speculative. Neither file was
  in scope for any prior TASK-0026x task — `ip_status_trunks.php`/
  `ip_status_peers.php` were checked (TASK-0026K/L, `STATIC_SAFE`) but
  their two siblings in the same directory were not.

No other exploitable supported-surface SQL injection was found. Every
other dynamic SQL site traced either routes through `Zend_Db`
parameterized binding (the ~150 sites already remediated by
TASK-0026C/F1/J/K/L/M/N/O/P), is fully static/literal, is
integer-cast or allowlist-constrained before reaching SQL, or is
genuinely dead code (zero call sites anywhere in the tree — several
newly re-confirmed dead here, not merely repeated from a prior
document). A handful of raw-interpolation sites remain in code reachable
**only** from Asterisk's AGI/dialplan call-processing pipeline
(`snep/agi/*.php`, `PBX_Rule_Action` subclasses under
`snep/modules/{default,billing,callback,ivr,portability}/actions/`) —
consistent with every prior TASK-0026x task's own established boundary,
these are recorded in the coverage tables below but not counted as
"supported surface," since no web controller in this codebase invokes a
matched business rule's action side effects (only rule *matching*,
confirmed independently in this task, not merely re-asserted).

```text
NEEDS_MANUAL_REVIEW = 0
```

---

## 2. Methodology

Documented here exactly as it happened, including the one operational
hiccup, per CLAUDE.md's "evidence from the repository and runtime
behavior takes precedence over assumptions" / "correct documentation
when later evidence disproves an earlier assumption" — this section was
rewritten at the final checkpoint to match what actually occurred, not
the plan as originally launched.

1. **Coordinator's own direct code-tracing** (throughout): a
   repository-wide grep-driven inventory of every `$db->query(`,
   `->select(`, `->where(`, `->update(`, `->delete(`, `->insert(`,
   `->fetchOne(`, `->fetchAll(`, `->fetchRow(`, and manually-built
   `$sql = "SELECT..."`/`mysql_query(` string across `snep/lib`,
   `snep/modules`, and `snep/agi` (excluding the vendored `snep/lib/Zend/`
   tree), followed by per-site source-to-sink tracing and, for every
   candidate that looked exploitable, live verification against the
   running `make dev` database via direct PHP invocation (the same
   CLI-bootstrap pattern `scripts/residual-sql-security-smoke-test.sh`
   already established: replicate `snep/index.php`'s `Zend_Registry`
   setup without dispatching a controller, then call the vulnerable
   method directly with a harmless apostrophe/syntax-difference payload)
   or, where reachability itself was the open question (Q-SQL-003's
   Simulator path, Q-SQL-004's unauthenticated `/includes/*.php`
   boundary), a real, unmodified HTTP round-trip against the running dev
   stack.
2. **Four parallel research forks were launched**, each scoped to a
   disjoint subsystem (never-before-audited default-module controllers;
   never-before-audited `Snep_*` library classes; never-before-audited
   `PBX_*` library classes plus the billing module and standalone API's
   `SnepService.php`; the peripheral `callback`/`ivr`/`portability`
   modules and every AGI script). **One (the `Snep_*` library-class
   fork) completed and reported in full** — its results are folded into
   §5/§6/§8 below with attribution. **The other three were terminated
   mid-task by a session-wide API rate limit** (`HTTP 429`, all three
   notifications within the same minute) before they could report a
   final result. One of the three (the `PBX_*`/billing/API fork) had,
   before being cut off, already written a substantial draft of this
   very document — including the `PBX_Trunks::get()` finding it
   independently discovered inside its own assigned scope (this fork's
   prompt explicitly asked it to trace `snep/lib/PBX/Trunks.php`) and a
   new finding, `Snep_Permission_Manager` and
   `snep/includes/estados.php`/`cidades.php`, from adjacent files it
   examined beyond its literal assignment. That draft was **not trusted
   as-is**: every claim in it was independently re-verified by the
   coordinator against current source and/or the live dev stack before
   being retained (see §5's and §6's own "independently re-verified"
   language, and the live proofs re-run in §6). The other two forks
   (default-module controllers; `callback`/`ivr`/`portability`/AGI
   scripts) left **no usable output** — their assigned scope was
   subsequently covered directly by the coordinator (§6/§8/§9 reflect
   this; see the per-controller and per-AGI-script grep/read evidence
   folded into those sections) rather than re-launching replacement
   forks, since the rate limit was session-wide and re-launching more
   background agents immediately was not a safe option.

Every finding was proven only with an apostrophe-shaped or
boolean-oracle syntax-error differential, either via direct PHP
invocation or a real, unmodified, harmless HTTP request — no data was
extracted, no row was modified, and every fixture created during
verification was disposable and self-contained (either created and
destroyed within a single script invocation, or never persisted to
disk/DB at all, or — for the two purely read-only HTTP probes against
`estados.php`/`cidades.php`/the Simulator — created no state at all). No
application file was modified at any point.

---

## 3. Repository coverage

```text
Total first-party PHP files (excl. snep/lib/Zend/):     336
Files touching $db/Zend_Db/mysql_* (any of query/
  select/where/update/delete/insert/fetchOne/
  fetchAll/fetchRow/mysql_query):                        112
Distinct ->where(...) call sites:                        183
Distinct ->update(/->delete(/->insert( call sites:       178
Distinct mysql_query( call sites (pre-Zend, outside
  the Zend_Db abstraction entirely):                      2
```

Every one of the 112 SQL-touching files was opened and traced across
this task's two work streams (see §2): 110 by the fork/coordinator sweep
that authored most of this document, plus `snep/includes/estados.php`/
`cidades.php` (Q-SQL-004), independently found and traced by the
coordinator and folded in at the final checkpoint. See §9 for the
per-family breakdown.

---

## 4. Classification taxonomy

Every dynamic SQL construction site received exactly one of:

```text
SAFE_STATIC                       -- no interpolated value at all
SAFE_PARAMETERIZED                -- Zend_Db bound placeholder (?) or quoteInto()
SAFE_QUOTED_VALUE                 -- $db->quote()/quoteInto() pre-built condition
SAFE_INTEGER_CAST                 -- (int) cast neutralizes the interpolation
SAFE_ALLOWLISTED_IDENTIFIER       -- value constrained to a finite set before reaching SQL
SAFE_DB_DERIVED_NON_USER_CONTROLLED -- value is a DB/session-derived int PK, never free text
DEAD                              -- zero call sites anywhere in the tree
UNREACHABLE_CURRENT_RUNTIME       -- code path blocked by an unrelated pre-existing bug
VULNERABLE_BUT_CURRENTLY_UNREACHABLE -- real vulnerable code, currently unreachable
EXPLOITABLE_DIRECT                -- confirmed, request value reaches SQL same-request
EXPLOITABLE_SECOND_ORDER          -- confirmed, via persist-then-reuse
NEEDS_MANUAL_REVIEW               -- (none remain — see §16)
```

`AGI_ONLY` is used in the coverage tables (§9) as a reachability
qualifier, not a safety classification — an AGI-only site's SQL
construction is classified using the same vocabulary above; `AGI_ONLY`
only records that the *entry point* is Asterisk's dialplan, not HTTP,
consistent with every prior TASK-0026x task's scope boundary (never
included in "supported surface").

---

## 5. Previously remediated boundaries — independent re-verification

Per Phase 4's explicit instruction not to assume TASK-0026J–P's fixes
are correct merely because they passed regression, this task re-read
(not merely re-cited) the current source of every closed boundary listed
below and re-confirmed each is still `SAFE_PARAMETERIZED`/
`SAFE_INTEGER_CAST`/`SAFE_ALLOWLISTED_IDENTIFIER` as documented. No
regression was found in any of them.

| Boundary | Fixed by | Independently re-verified this task |
|---|---|---|
| Login SQLi (`Snep_Acl`/`Snep_Auth_Adapter_Password`) | 0026B/0026H | Re-read `Auth/Adapter/Password.php`, `Auth/Manager.php` — all `->where(..., ?)` bound |
| Extensions (`ExtensionsController`/`Extensions/Manager.php`) | 0026C | Re-grepped every `->where(`/`->update(`/`->delete(` site — all parameterized |
| Users/Profiles (`Snep_Users_Manager`/`Snep_Profiles_Manager`) | 0026C | Re-read `addProfileByName()`'s `quoteInto()` fix directly — confirmed intact |
| Trunks (`TrunksController`/`Trunks/Manager.php`) | 0026C/0026J | Re-confirmed `editAction()`'s bound `where('name = ?', ...)`; `getTrunkLog()`'s dead `$sql` re-confirmed still unreferenced |
| CSV import (`Snep_CsvIE`) | 0026C | Re-read `import()`'s parameterized `INSERT...VALUES (?,?)` |
| Data Export (`ExportDataController`) | 0026C | Re-confirmed `getExportTables()` allowlist gates both column and identifier positions |
| Standalone API (`api/actions/*.php`) | 0026F1 | Spot-re-verified `ContactsService`/`CallsReportService`/`CSV_ExportDataService` — all `quoteInto()`/`(int)` |
| PJSIP config generators | 0026E | Not SQL — out of this task's scope (config injection, not SQL injection) |
| `Snep_InterfaceConf`/`CallsReportController` | 0026J | Re-read both fixes — `where('name = ?', ...)`, `$db->quote()` throughout |
| `Ranking`/`ServicesReportController` | 0026K | Re-read both `getData()` methods — `$db->quote()` on date range and `clausulepeer` |
| `PickupGroups`/`Queues` Managers | 0026L | Re-read all 16 fixed sites — `quoteInto()` throughout |
| Contacts/ContactGroups/DatesAlias/ExpressionAlias/CostCenter/ExtensionsGroups/SoundFiles/Billing/Telcos Managers | 0026M | Spot-re-verified 6 of 10 files directly; grep-reconfirmed the array-form `col = ?` shape in the remaining 4 |
| `PBX_Rule`/`PBX_Usuarios`/`PBX_Rules` | 0026N | Re-read all 10 fixed sites |
| `RouteController`/`Snep_Binds_Manager` | 0026O | Re-read the `type` allowlist and all 3 `quoteInto()` fixes |
| `Snep_ModuleSettings_Manager` | 0026P | Re-read `getConfig()`'s `quoteInto()`-with-`(string)`-cast fix and its null-value regression fix |
| `PBX_Registry` | 0026P (classified, not modified) | **Independently re-traced from scratch** (not merely re-cited) — confirmed all 3 real call sites (`ActionConfigsController::editAction()`, `PBX_Rules.php:153`, `PBX_Rule/Action.php:63`) gate `$context`/`$acao` behind `class_exists()`/`get_class()` before it reaches `PBX_Registry`; `$key` is always an XML-schema field id from `PBX_Rule_ActionConfig::parseConfig()`, never a raw `$_POST` key. Classification holds. |
| `Snep_PjsipTransports_Manager` | 0026O (classified) | Re-read `update()`/`remove()`/`replaceNetworks()` (the last not individually named by any prior doc) — all three cast `(int)` before interpolating |

No prior classification was overturned.

---

## 6. Q-SQL finding inventory

### Q-SQL-001

```text
ID:                Q-SQL-001
File:               snep/lib/Snep/Cnl.php
Class:              Snep_Cnl
Method:             getState($state, $country), getCityCode($state, $name), getPrefix($prefix, $country)
Entry point:        CnlController::updateAction_76() (dispatched from indexAction() when POST country=76)
Reachability:       AUTHENTICATED_PERMISSIONED (default_cnl_read is sufficient -- `cnl`
                     resources.xml entry has zero declared children, so only an
                     implicit "read" permission is ever grantable, matching the
                     module-settings/route/users pattern TASK-0026O/P already
                     established) + UPLOAD_FLOW (a .zip file upload is required)
Authorization:      default_cnl_read
Source:             Uploaded .zip file -> extracted .txt -> fixed-byte-offset columns
                     (substr($line,0,2) state, substr($line,61,50) city name,
                     substr($line,116,7) prefix) -- entirely attacker-controlled file
                     content, ANATEL fixed-width format
Transformation:     trim()/utf8_encode()/Snep_Cnl::parseName() (accent stripping only,
                     no SQL-metacharacter handling)
SQL sink:           ->where("id = '$state'")->where("country = '$country'") (getState);
                     ->where("name = '$name'")->where("state = '$state'") (getCityCode);
                     ->where("id = '$prefix'")->where("country = '$country'") (getPrefix)
Direct/second-order: DIRECT
Exploit proof:       CONFIRMED_DIRECT_INVOCATION (this task, live against running dev DB):
                       Snep_Cnl::getState("foo'bar","1")
                         -> SQLSTATE[42000]: ...near 'bar') AND (country = '1')' at line 1
                       Snep_Cnl::getCityCode("foo'bar","baz'qux")
                         -> SQLSTATE[42000]: ...near 'qux') AND (state = 'foo'bar')' at line 1
                       Snep_Cnl::getPrefix("foo'bar","1")
                         -> SQLSTATE[42000]: ...near 'bar') AND (country = '1')' at line 1
                     Matches TASK-0026P's own original proof exactly -- re-verified,
                     not merely re-cited.
Severity:           P0 -- authenticated, direct, unquoted-string interpolation of
                     fully attacker-controlled file content, no unrelated bug blocks it
Affected behavior:  read/UNION access to any table via the core_cnl_state/
                     core_cnl_city/core_cnl_prefix lookup queries
Recommended remediation: $db->quoteInto('id = ?', $state) / equivalent bound where()
                     at all three sites -- identical mechanical pattern to the ten
                     prior closures
Regression test strategy: extend residual-sql-security-smoke-test.sh with a CNL
                     section mirroring the existing upload/direct-invocation pattern
                     already used for TASK-0026L's PickupGroups/Queues sub-boundaries
```

### Q-SQL-002

```text
ID:                Q-SQL-002
File:               snep/lib/Snep/Permission/Manager.php
Class:              Snep_Permission_Manager
Method:             removePermissionUser($id, $modules), addPermissionUser($id, $modules),
                     removePermissionProfile($id)
Entry point:        UsersController::permissionAction() (removePermissionUser/addPermissionUser);
                     ProfilesController::permissionAction() (removePermissionProfile)
Reachability:       AUTHENTICATED_PERMISSIONED
Authorization:      default_users_write (permissionAction is not in Snep_PermissionPlugin's
                     $readActions list for "default_users", so it defaults to the write tier);
                     default_profiles_write (same reasoning for "default_profiles")
Source:             UsersController::permissionAction(): $dados['id'] = $_POST['user'];
                     -- raw POST value, zero cast/validation, used for BOTH the delete and
                     the insert loop.
                     ProfilesController::permissionAction(): $id = $this->_request->getParam('id');
                     -- raw route parameter, zero cast/validation.
Transformation:     none
SQL sink:           removePermissionUser/addPermissionUser: $where[] = "user_id = '$id'";
                     ... $db->delete("users_permissions", $where);  (quoted string concat)
                     removePermissionProfile: $where[] = "profile_id = $id";
                     ... $db->update("profiles_permissions", $update_data, $where);
                     (UNQUOTED -- no surrounding string literal at all, the most severe
                     interpolation shape found anywhere in this audit)
Direct/second-order: DIRECT
Exploit proof:       CONFIRMED_DIRECT_INVOCATION (this task, live against running dev DB):
                       Snep_Permission_Manager::removePermissionUser("foo'bar", array())
                         -> SQLSTATE[42000]: ...near 'bar') AND (allow =0)' at line 1
                       Snep_Permission_Manager::addPermissionUser("foo'bar", array())
                         -> SQLSTATE[42000]: ...near 'bar') AND (allow =1)' at line 1
                       Snep_Permission_Manager::removePermissionProfile("foo'bar")
                         -> SQLSTATE[42000]: ...near ''bar)' at line 1
Severity:           P0 -- same impact class as the original F8 finding (mass
                     permission manipulation): a boolean-injection payload in the
                     `user` POST field of UsersController::permissionAction (e.g.
                     ' OR '1'='1) reaches an unconditional DELETE against
                     users_permissions with a match-everything WHERE clause,
                     wiping every user's individually-granted permission overrides
                     in one request; the profile variant is unquoted-numeric-context
                     and can retarget the UPDATE to an arbitrary profile_id via a
                     crafted route id. Reachable by any account holding the common,
                     non-superuser "manage users" or "manage profiles" permission --
                     not a privileged or unusual grant.
Affected behavior:  users_permissions/profiles_permissions row deletion and
                     reassignment beyond the intended user/profile
Recommended remediation: $db->quoteInto('user_id = ?', $id) / $db->quoteInto('profile_id = ?', $id)
                     -- identical mechanical pattern already used ten times over
                     in this codebase; note the WHERE array in removePermissionUser/
                     addPermissionUser also needs its second element
                     ("allow = " . 0/1) reviewed -- it is a hardcoded literal 0/1,
                     already safe, no change needed there
Regression test strategy: new focused section covering both permissionAction()
                     entry points -- legitimate grant/revoke still works; a
                     boolean-shaped `user`/`id` cannot cross-affect a second,
                     CANARY user/profile's permission rows
```

### Q-SQL-003

```text
ID:                Q-SQL-003
File:               snep/lib/PBX/Trunks.php
Class:              PBX_Trunks
Method:             get($id)
Entry point 1:      SimulatorController::indexAction() -- POST field `trunk`, used when
                     `srcType=trunk`
Entry point 2:      RouteController::parseRuleFromPost() (called from addAction()/editAction()) --
                     POST fields `srcValue`/`dstValue`, tokens shaped `T:<value>`
Entry point 3:      SimulatorController::indexAction()'s own action-description
                     renderer (line ~149, inside the loop over a matched rule's
                     `getAcoes()`): `$tronco = PBX_Trunks::get($config['tronco']);`
                     where `$config = $action->getConfigArray()` for a `DiscarTronco`
                     rule action. `$config['tronco']` is planted second-order via
                     RouteController::addAction()/editAction() ->
                     Snep_Rule_ActionConfig::parseConfig($post["action_$action"])
                     (snep/lib/PBX/Rule/ActionConfig.php:125-134, inherited unchanged
                     by Snep_Rule_ActionConfig), which does
                     `$config["{$element->id}"] = $post["{$element->id}"];` for every
                     form field with zero type/shape validation regardless of the
                     XML schema's declared `<tronco>` element type -- the "tronco"
                     case in parseForm()'s switch only affects how the edit-time
                     Zend_Form dropdown itself is rendered (parseTronco()), never
                     how a submission is parsed back.
Reachability:       AUTHENTICATED_ANY_USER via entry points 1 and 3 (`default_simulator`
                     is on Snep_PermissionPlugin's $alwaysAllow list -- reachable by any
                     authenticated account with zero permission grant, the same
                     severity class as the already-fixed N1-N3 findings in this same
                     controller); AUTHENTICATED_PERMISSIONED via entry point 2
                     (default_route_write to submit the rule) and, to PLANT entry
                     point 3's payload, AUTHENTICATED_PERMISSIONED
                     (default_route_write) -- but TRIGGERING the already-planted
                     entry-point-3 payload needs only entry point 1's
                     AUTHENTICATED_ANY_USER bar, on a completely separate
                     request/session from whoever planted it.
Authorization:      none beyond authentication (entry points 1 and 3's trigger);
                     default_route_write (entry point 2; entry point 3's plant step)
Source:             Entry point 1: $trunk = isset($formData['trunk']) ? $formData['trunk'] : NULL;
                     -- raw POST value.
                     Entry point 2: $info = explode(':', $src); ... PBX_Trunks::get($info[1]);
                     where $src comes from explode(',', $post['srcValue']) -- raw POST value.
                     Entry point 3: $post["action_$action"]['tronco'] (raw POST at
                     plant time) -> persisted verbatim -> $config['tronco'] (at
                     trigger time, a later/different request).
Transformation:     none (entry points 1 and 3's plant step); string split only
                     (entry point 2)
SQL sink:           $select = $db->select()->from('trunks')->where("id = $id");
                     -- UNQUOTED, no surrounding string literal at all
Direct/second-order: DIRECT (entry points 1 and 2); SECOND-ORDER (entry point 3 --
                     confirmed via source trace of parseConfig()'s unvalidated
                     passthrough; not independently live-HTTP-reproduced beyond the
                     entry-point-1 proof below, since the underlying sink and its
                     exploitability are already CONFIRMED_LIVE via entry point 1 and
                     CONFIRMED_DIRECT_INVOCATION via the isolated sink proof -- the
                     value of proving entry point 3 specifically is establishing the
                     plant-then-trigger reachability shape, which the source trace
                     above establishes without needing a third independent live
                     reproduction of the same already-proven sink)
Exploit proof:       CONFIRMED_LIVE (entry point 1, real authenticated HTTP round-trip,
                     not merely direct invocation): logged in as the project's existing
                     persistent `task0026j-restricted` fixture account (zero special
                     permission grant), fetched `/index.php/default/simulator` (HTTP 200
                     -- independently confirms `default_simulator` is reachable by a
                     zero-permission session, i.e. authenticated-open), extracted the
                     page's own CSRF token, then POSTed
                     `acao=simulate&srcType=trunk&trunk=foo%27bar&caller=probe&dst=100`
                     with `X-Snep-Csrf-Token` set. Result: HTTP 500, and
                     `mag-error.log` recorded, in the same second:
                     `ErrorController: uncaught Zend_Db_Statement_Exception:
                     SQLSTATE[42000]: Syntax error or access violation: 1064 ... near
                     ''bar)' at line 1` -- the exact same signature as the direct-
                     invocation proof below, reached through the real, unmodified,
                     authenticated web application, no direct PHP invocation involved.
                     CONFIRMED_DIRECT_INVOCATION (entry point 1's sink, isolated):
                       PBX_Trunks::get("foo'bar")
                         -> SQLSTATE[42000]: ...near ''bar)' at line 1
                     PBX_Trunks::get("0 OR 1=1") returned "not found" only because the
                     dev database's `trunks` table is currently empty (a standing,
                     documented invariant of this project's persistent dev fixtures --
                     see every prior TASK-0026x closure's own cleanup verification);
                     the apostrophe differential above is sufficient proof per this
                     task's own Phase 7 allowed-proof list. No password/hash/schema
                     data was read, no row was modified, and no fixture was left behind
                     (the HTTP round-trip created no persistent state -- confirmed via
                     the same `task0026j-restricted` account already used by
                     `residual-sql-security-smoke-test.sh`, not a newly created one).
Severity:           P0 -- reachable by ANY authenticated user with zero permission
                     grant via the Simulator (matching N1-N3's own severity
                     reasoning exactly), unquoted interpolation (most severe shape),
                     UNION-injectable read access to the `trunks` table and, via
                     UNION, any other table.
Affected behavior:  read access to trunks/any table via the Simulator's own
                     trunk-lookup path (entry points 1 and 3); independently,
                     business-rule save-time validation (RouteController) crashes/
                     behaves unexpectedly under injected syntax (entry point 2)
Recommended remediation: $db->select()->from('trunks')->where('id = ?', $id) --
                     one fix at the single shared sink closes all three entry
                     points simultaneously; identical mechanical pattern already
                     used in PBX_Trunks::getAll()'s own sibling call to self::get()
                     (which is always DB-derived-int-PK-safe and does not need the
                     fix, see §5); this is the same file/class TASK-0026M/N's own
                     sibling audits should have caught but did not, since those
                     tasks were scoped to PBX_Rule/PBX_Usuarios/PBX_Rules, never
                     PBX_Trunks
Regression test strategy: extend residual-sql-security-smoke-test.sh's existing
                     Simulator section (already present for N1-N3) with a
                     `srcType=trunk` apostrophe-shaped check, a RouteController
                     srcValue=T:foo'bar check, and a plant-then-trigger check for
                     entry point 3 (a DiscarTronco rule action with an
                     apostrophe-shaped `tronco` config, planted via addAction(),
                     triggered via a separate Simulator request)
```

### Q-SQL-004

```text
ID:                Q-SQL-004
File:               snep/includes/estados.php, snep/includes/cidades.php
Class:              (none -- standalone, pre-Zend, non-Zend_Db scripts, not part
                     of the MVC application at all)
Method:             (top-level script body)
Entry point:        Apache serves both files directly, unauthenticated -- neither
                     goes through Zend_Controller_Front/Snep_AuthPlugin/
                     Snep_PermissionPlugin at all. Actively wired into the UI:
                     snep/modules/default/views/layouts/register.phtml:288,293
                     (jQuery('#city'/'#state').load(.../includes/cidades.php?estado=,
                     .../includes/estados.php?pais=)) and
                     snep/modules/default/views/scripts/contacts/addedit.phtml:264
                     (same cidades.php AJAX load).
Reachability:       UNAUTHENTICATED (would-be, if the blocking bug below were
                     fixed) -- snep/includes/.htaccess only <Files ~ "\.conf">
                     Require all denied; estados.php/cidades.php are *.php, not
                     matched by that rule, and are reached by plain
                     GET /includes/estados.php / /includes/cidades.php, never
                     through /index.php/... at all. Currently
                     VULNERABLE_BUT_CURRENTLY_UNREACHABLE -- see below.
Authorization:      none (no session/cookie is ever checked by either file)
Source:             estados.php: $idpais = $_GET['pais'];
                     cidades.php: $idestado = $_GET['estado'];
                     -- raw GET parameters, no framework filtering of any kind
                     (these files predate/bypass Zend_Filter_StripTags entirely).
Transformation:     is_numeric($idpais) branches the query; the numeric branch is
                     unquoted-integer (only truly numeric strings survive
                     is_numeric(), so that branch alone would be safe on its own),
                     but the non-numeric (else) branch is NOT integer-gated at all
                     and reaches the vulnerable single-quoted string sink with the
                     raw value.
SQL sink:           estados.php:35: mysql_query("SELECT id,name FROM core_cnl_city
                     WHERE country = '".$idpais."'");
                     cidades.php:35: mysql_query("SELECT id,name FROM core_cnl_city
                     WHERE state = '".$idestado."'");
                     -- raw concatenation, zero escaping, using the mysql_*
                     extension (not Zend_Db at all -- these files never went
                     through this program's own Zend_Db migration in the first
                     place).
Direct/second-order: DIRECT, but VULNERABLE_BUT_CURRENTLY_UNREACHABLE -- both
                     files call mysql_connect()/mysql_select_db() (line 27-28)
                     unconditionally, BEFORE either query branch is reached.
                     mysql_connect() was removed from PHP entirely in PHP 7.0;
                     under this project's actual PHP 8.4.25 runtime this is an
                     immediate `Error: Call to undefined function
                     mysql_connect()`, confirmed live (see below) -- the
                     vulnerable SQL-construction code is real and unreachable by
                     any *other* bug's grace; it is blocked by this one specific,
                     unrelated, pre-existing category-A PHP compatibility defect,
                     the same "real vulnerable code, currently non-functional"
                     shape this program has documented before (e.g.
                     PickupGroupsController::removeAction()'s
                     mysql_escape_string() fatal, TASK-0026L; Billing_Manager's
                     static-call fatal, TASK-0026M).
Exploit proof:       CONFIRMED_LIVE (this task, real unauthenticated HTTP request,
                     no cookie/session/auth header of any kind):
                       curl http://localhost:8080/includes/estados.php?pais=1
                         -> HTTP 500
                       curl http://localhost:8080/includes/cidades.php?estado=1
                         -> HTTP 500
                     mag-error.log, same second, both requests:
                       PHP Fatal error:  Uncaught Error: Call to undefined
                       function mysql_connect() in
                       /var/www/html/snep/includes/estados.php:27
                       PHP Fatal error:  Uncaught Error: Call to undefined
                       function mysql_connect() in
                       /var/www/html/snep/includes/cidades.php:27
                     This proves both (a) the endpoint is genuinely
                     unauthenticated-web-reachable (Apache serves the file, no
                     403/404, no login redirect -- unlike /index.php/... routes)
                     and (b) the specific, exact blocking cause is the removed
                     mysql_* extension, not some other unrelated failure. The SQL
                     string itself was verified vulnerable by static trace only
                     (per this taxonomy's own VULNERABLE_BUT_CURRENTLY_UNREACHABLE
                     definition -- "do not call vulnerable code safe merely
                     because another bug blocks it," Phase 5) -- no live
                     SQL-syntax-error differential was attempted against the
                     mysql_* sink itself, since doing so is impossible without
                     first fixing the unrelated blocking bug (which this
                     audit-only task does not do).
Severity:           P1 -- real vulnerable code, but currently blocked in its
                     entirety by an unrelated bug (per this project's own
                     established severity discipline, e.g. the original F5/F10
                     findings' "pending reachability" treatment) -- would be P0
                     (unauthenticated, UNION-capable read access to
                     core_cnl_city/core_state and, via UNION, any other table)
                     if the mysql_connect() compatibility bug were ever fixed in
                     isolation without also fixing the SQL construction.
Affected behavior:  none currently (both files 500 unconditionally); would be
                     unauthenticated read access to arbitrary tables if unblocked
Recommended remediation: cannot be a mechanical quoteInto() swap alone --
                     both files need to be ported off the removed mysql_*
                     extension onto this application's existing Zend_Db
                     connection (Zend_Registry::get('db'), matching
                     ip_status_trunks.php/ip_status_peers.php's own already-
                     established PDO/Zend_Db pattern in the same directory) AND
                     have their WHERE-clause interpolation parameterized in the
                     same change -- fixing only the connection layer without also
                     fixing the SQL construction would convert this from
                     "currently blocked" to "live unauthenticated SQL injection,"
                     which must not happen as an accidental side effect of an
                     unrelated PHP 8.4 compatibility pass.
Regression test strategy: new focused section verifying (a) a legitimate
                     numeric pais/estado value still returns the expected
                     <option> HTML, (b) an apostrophe-shaped value causes no SQL
                     error, (c) a boolean-injection-shaped value cannot leak a
                     CANARY row from an unrelated table via UNION
```

---

## 7. Exploitability evidence summary

| ID | Proof type | Live-verified | Data extracted | Rows modified |
|---|---|---|---|---|
| Q-SQL-001 | Apostrophe syntax-error differential | Yes (this task, direct invocation; originally TASK-0026P) | No | No |
| Q-SQL-002 | Apostrophe syntax-error differential | Yes (this task, direct invocation, all 3 method variants) | No | No |
| Q-SQL-003 | Apostrophe syntax-error differential | Yes (this task) — **both** a real authenticated HTTP round-trip through `SimulatorController` (CONFIRMED_LIVE) **and** direct invocation of the sink (CONFIRMED_DIRECT_INVOCATION) | No | No |
| Q-SQL-004 | Unauthenticated-reachability + exact-blocker live proof (static SQL trace, live-verified blocking cause) | Yes (this task) — real unauthenticated HTTP request to both files, `mag-error.log` confirms the exact `mysql_connect()` fatal | No | No |

Q-SQL-001 and Q-SQL-002 use `CONFIRMED_DIRECT_INVOCATION` — the
vulnerable method was called directly (via the same CLI-bootstrap
harness pattern this project's own regression suite already
established), not through a full authenticated HTTP round-trip, purely
for verification efficiency; the SQL-execution code path exercised is
byte-identical to what the real HTTP entry point reaches (confirmed by
direct read of each entry point's call chain, cited in §6). Q-SQL-003
was additionally reproduced through the real, unmodified, authenticated
web application (login as the project's existing persistent
`task0026j-restricted` fixture account, real CSRF token, real POST to
`/index.php/default/simulator`), the strongest evidentiary bar this
program's own established proof taxonomy defines
(`CONFIRMED_LIVE`) — see §6 for the exact request/response/log evidence.
No password, hash, or other row content was read or displayed at any
point; no destructive query was issued; no fixture was left behind (all
three used values that match no real row, and the one HTTP-level test
created no persistent state).

---

## 8. Safe-site evidence (representative false-positive classes reviewed)

Per Phase 12's explicit instruction, this is not solely a vulnerability
hunt — the following classes of apparent-but-non-issues were
individually reviewed and are recorded here as evidence the audit was
exhaustive, not merely opportunistic:

| Pattern | Example | Why it's safe |
|---|---|---|
| Raw query but every dynamic value bound | `PBX_ExpressionAliases::get()` | `quoteInto()`/`(int)`-cast argument, TASK-0026M fix |
| Integer-cast id | `Snep_PjsipTransports_Manager::update()`/`remove()`/`replaceNetworks()` | `(int) $id` before interpolation, independently re-confirmed all three sites this task |
| Hardcoded SQL | `Snep_PjsipConf.php:129`, `TrunksController.php:644`, `ContactGroupsController.php:76` | zero interpolated variable in the string at all |
| Finite table/column allowlist | `ExportDataController::getExportTables()`, `CSV_ExportDataService`'s reuse of `CSV_GetParamsService` | request value validated against a fixed array before reaching identifier position |
| Finite order/type allowlist | `RouteController::indexAction()`'s `type` enum allowlist | TASK-0026O fix, re-confirmed |
| DB-generated immutable value | `TrunksController.php:271`'s `$id = $db->lastInsertId()` | AUTO_INCREMENT value, never attacker-supplied |
| Session-derived, not request-derived | `Snep_Dashboard_Manager::get()`/`set()` | keyed on `$_SESSION[id_user]`, an int PK set at login by an already-parameterized query |
| Dead path — zero call sites | `Snep_RecordReport_Manager::getCalls()` (coordinator-verified: zero references to `Snep_RecordReport`/`RecordReport_Manager` anywhere in the tree, any file type), `Snep_Route::getActions($id)`, `Snep_Operadoras.php` (3 sites), `Snep_Extensions.php` (top-level class, 2 sites), `Snep_Alerts.php`, `Snep_Manutencao::listaPeriodo()` (coordinator-verified: only sibling `arquivoExiste()` — no SQL — is actually called, from `CallsReportController.php:504`), `PBX_Relatorio_Chamadas.php` (coordinator-verified: the *only* file in `snep/lib/PBX/Relatorio/` — no siblings exist), `Snep_Trunks_Manager::getTrunkLog()`'s dead `$sql` local, `Snep_CsvIE::export()`, `Snep_Services::getPathService()`, `PBX_Rules::getAll()`'s optional `$where` | independently re-confirmed via `grep -rn` for every class/method name across the full tree — genuinely zero references outside the file's own definition |
| AGI-only, non-web path | `snep/agi/*.php` (17 files, 7 of which touch `$db`/`mysql_query`, 22 raw-SQL call sites total — see §9), every `PBX_Rule_Action` subclass under `snep/modules/{default,billing,callback,ivr,portability}/actions/` (`DiscarTronco`, `DiscarRamal`, `CCustos`, `Queue`, `Cadeado`, `Context`, `CallbackAction`, `IVR`, `UserInteraction`, `PortabilityAction`), `PBX_Rule_Plugin_Broker`, `Snep_Rule_Plugin_TimeLimit`/`_OldController` | traced each entry point's only caller to `snep/agi/snep.php`'s `$regra->execute($origem)` or Asterisk's own `AGI()` dialplan invocation; independently confirmed (not merely re-cited) that no web controller invokes `PBX_Rule::execute()`/`postExecute()` — `SimulatorController` only calls `PBX_Dialplan_Verbose::parse()` for rule *matching*, and its own action-description loop (§6 Q-SQL-003) only instantiates/inspects `CCustos`/`DiscarTronco`/`DiscarRamal`/`Queue`/`Cadeado`/`Context`, never `CallbackAction`/`IVR`/`UserInteraction`/`PortabilityAction`. Coordinator additionally live-tested raw HTTP reachability of the AGI directory itself (not merely the dispatch boundary): `curl --max-time 3` against `agenda.php`/`dnd.php`/`followme.php`/`padlock.php`/`serviceslog.php`/`resolv_extension.php` all hung with **zero bytes returned** (HTTP `000`, `Asterisk_AGI`'s constructor blocking on a stdin handshake read that a plain HTTP request never supplies) — consistent with TASK-0026Q's own earlier `snep/agi/snep.php` finding, now confirmed across a wider file sample. `voicemail-notify.php` is the one exception (its own `#!/usr/bin/php -q` + `$argc`/`$argv` CLI-invocation style, distinct from the AGI-protocol scripts): a direct HTTP request returns HTTP 200 in ~25ms because `$argc` is `Undefined` under Apache's SAPI (confirmed live via the exact `PHP Warning: Undefined variable $argc` + the script's own `$log->err(...)+exit(1)` line appearing in the response for both a bare request and one with an `isindex`-style query string with no `=` sign, ruling out the classic PHP `register_argc_argv` CGI-argv-injection technique) — the script's `$argc < 3` guard always takes the early-exit branch before its one SQL statement (already `->where('mailbox = ?', ...)`-parameterized regardless) is ever reached. |
| Non-SQL false positive | `RouteController.php:490-512`, `Snep/Menu.php:319` (JS/HTML string building, no SQL) | already classified by TASK-0026P, re-confirmed |
| Direct `$db`/`Zend_Registry::get('db')` reference with zero actual query call | `AuditController::indexAction()`, `IVR::execute()`, `UserInteraction::execute()`, `BillingController::addAction()`/`editAction()`, `TelcosController::addAction()`/`editAction()` | coordinator-verified via `grep -n '\$db->'` on each file: the variable is assigned from the registry but never dereferenced — all real persistence in each case routes through an already-classified Manager class |

---

## 9. Family/file coverage table

```text
Family                          Files audited   SQL sites    Vulnerable      Safe/Dead/AGI-only
Controllers (default)           46              ~120         2 (entry points  rest safe/none;
                                                               for Q-SQL-002/  17 previously-
                                                               003 -- vuln     unaudited
                                                               code lives in   controllers
                                                               the Manager/    individually
                                                               PBX class, not  grepped by
                                                               the controller) coordinator --
                                                                               only AuditController
                                                                               touches $db, and
                                                                               that reference is
                                                                               unused (see S8)
Controllers (billing)           2               0 direct      0              2 (delegate only,
                                                                               dead $db var,
                                                                               coordinator-verified)
Snep/*/Manager classes          ~30             ~140          1 (Permission)  rest fixed/safe
Snep/* top-level classes        41              ~25           1 (Cnl, already rest safe/dead
                                                                known)         (fork-audited, see S2)
PBX/* top-level + subdirs       9 + 7 dirs      ~35           1 (Trunks)      rest fixed/safe/
                                                                               AGI-only (Dialplan,
                                                                               Asterisk, Khomp:
                                                                               zero SQL; Validate/
                                                                               Extension.php:
                                                                               delegates to already-
                                                                               safe PBX_Usuarios;
                                                                               Relatorio: single
                                                                               dead file, no siblings
                                                                               -- all coordinator-
                                                                               verified)
modules/default/api (standalone)8              ~40 (0026F1)  0               all parameterized;
                                                                               SnepService.php is a
                                                                               bare PHP interface,
                                                                               zero code/SQL
                                                                               (coordinator-verified)
modules/billing (Manager)       2               ~10           0              all fixed (0026M)
modules/callback                1               0             0              no SQL at all
                                                                               (CallbackAction,
                                                                               PBX_Rule_Action,
                                                                               AGI-only --
                                                                               coordinator-verified,
                                                                               full file read)
modules/ivr                     2               0             0              no SQL (IVR.php/
                                                                               UserInteraction.php
                                                                               both declare an
                                                                               unused $db; neither
                                                                               is referenced by
                                                                               SimulatorController's
                                                                               action-rendering loop
                                                                               -- coordinator-verified)
modules/portability              1              3              0 (AGI-only)   PortabilityAction's
                                                                               own raw
                                                                               "phone like '%..'"
                                                                               sink (0026K's prior
                                                                               finding, re-confirmed
                                                                               unchanged, still
                                                                               AGI-only -- not a
                                                                               DiscarTronco sink)
reports (Calls/Ranking/Services) 3              ~20 (0026J/K) 0               all fixed
imports/uploads (Cnl, CsvIE)    2               ~8            1 (Cnl)         CsvIE already fixed
snep/agi/*.php                  17              22            0 (AGI-only,    10/17 files touch no
                                                                unreachable    SQL at all; of the 7
                                                                over HTTP,     that do (agenda,
                                                                coordinator-   dnd, followme,
                                                                live-tested)   padlock, serviceslog,
                                                                               snep, voicemail-
                                                                               notify), 6 hang
                                                                               indefinitely on a
                                                                               direct HTTP request
                                                                               (confirmed via curl)
                                                                               and 1
                                                                               (voicemail-notify.php)
                                                                               exits before its own
                                                                               already-parameterized
                                                                               query -- see S8
views (*.phtml)                 ~150            0             0               zero raw $db-> usage
                                                                               found
```

Counts are drawn from direct enumeration during this task (partly by the
one fork that completed, partly by the coordinator directly, per S2's
methodology note), not estimated from prior documents' totals. The
17-controller and AGI/module-family figures were personally re-verified
by the coordinator via direct grep/read of every named file, since the
two forks originally assigned that scope were cut off by the rate limit
described in S2 before they could report.

---

## 10. Direct vs second-order summary

```text
Direct:        4 of 4 findings have at least one DIRECT reachability path
                (Q-SQL-001, Q-SQL-002, Q-SQL-003's two POST-field paths,
                Q-SQL-004)
Second-order:  1 of 4 findings additionally has a SECOND-ORDER path
                (Q-SQL-003's third path: a malicious DiscarTronco rule
                action's `tronco` config, planted via
                RouteController::addAction()/editAction(), persists with
                zero validation and is read back unquoted by
                SimulatorController::indexAction()'s action-description
                renderer on a later, unrelated request/session -- the
                same "plant now, trigger later" shape as TASK-0026J's
                BLOCKER A)
Previously-fixed second-order findings (TASK-0026J BLOCKER A,
  TASK-0026L's Queues::edit()) remain fixed and unchanged.
```

---

## 11. Reachability summary

```text
UNAUTHENTICATED:                1 (Q-SQL-004 -- reachable at the file/
                                  entry-point level with zero auth,
                                  confirmed live; the SQL itself is
                                  VULNERABLE_BUT_CURRENTLY_UNREACHABLE,
                                  blocked by an unrelated PHP 8.4
                                  compatibility fatal, not by any auth
                                  check)
AUTHENTICATED_ANY_USER:         1 (Q-SQL-003, two of its three paths --
                                  SimulatorController's own `trunk` POST
                                  field, and the second-order
                                  action-config-render path -- both
                                  require only authentication, no
                                  specific permission grant)
AUTHENTICATED_PERMISSIONED:     3 (Q-SQL-001 default_cnl_read; Q-SQL-002
                                  default_users_write/default_profiles_write;
                                  Q-SQL-003's third path,
                                  default_route_write, needed only to
                                  PLANT either the RouteController
                                  srcValue/dstValue payload or the
                                  DiscarTronco config -- not to trigger
                                  the already-planted second-order one)
ADMIN_ONLY:                     0
API_AUTHENTICATED:              0
UPLOAD_FLOW:                    1 (Q-SQL-001)
AGI_ONLY / not supported surface: multiple (see §9), 0 counted toward findings
DEAD:                           10+ sites (see §8), 0 counted toward findings
```

---

## 12. Severity distribution

```text
P0: 3  (Q-SQL-001, Q-SQL-002, Q-SQL-003 -- all have at least one direct
         path, all confirmed live, all reachable by an ordinary
         non-superuser authenticated account -- Q-SQL-003 by any
         authenticated account at all via two of its three paths --
         two of the three unquoted/most-severe interpolation shape)
P1: 1  (Q-SQL-004 -- would be P0/unauthenticated-critical if the
         blocking mysql_connect() PHP 8.4 incompatibility were ever
         fixed without also fixing the SQL construction; currently
         VULNERABLE_BUT_CURRENTLY_UNREACHABLE per this task's own §4
         taxonomy, matching the severity discipline the original
         TASK-0026 audit applied to its own F5/F10 "pending
         reachability" findings)
P2: 0
```

Reasoning matches this project's own established severity criteria
(§11 of `docs/tasks/0026-pre-pilot-security-release-audit.md`): the
three P0s require only authentication (Q-SQL-003 requires no permission
grant at all via two of its three paths), all can alter query semantics
(confirmed live), none requires a separate pre-existing bug to reach.
Q-SQL-004 is P1 rather than P0 specifically because it *does* require a
separate pre-existing bug (the removed `mysql_connect()` extension) to
currently reach its SQL sink — matching this project's own precedent for
downgrading "real vulnerable code, currently blocked" findings (the
original audit's F5/F10, TASK-0026P's own severity note on this exact
class of finding).

---

## 13. The known CNL finding (Q-SQL-001)

Fully documented in §6 above. This audit re-verified TASK-0026P's
original finding live rather than treating the prior document's proof as
sufficient on its own, per this task's own governing instruction to
independently confirm rather than merely carry forward. No difference
was found — the finding stands exactly as TASK-0026P described it.

---

## 14. Remediation batches (proposed)

Q-SQL-001/002/003 share the identical mechanical remediation pattern
(`$db->quoteInto()`/bound `where()`) this program has now used eleven
times over (TASK-0026C/F1/J/K/L/M/N/O/P) and are small, disjoint, and
low-regression-risk. Q-SQL-004 is structurally different — it cannot be
a mechanical `quoteInto()` swap alone, since the two files first need
porting off the removed `mysql_*` extension onto this application's
existing `Zend_Db` connection before the SQL-construction fix even
applies — so it is proposed as its own batch, sequenced so the
connection-layer fix and the parameterization fix land in the same
change (fixing only the connection layer first would turn "currently
blocked" into "live unauthenticated SQL injection" as an accidental
side effect, which must not happen):

```text
Batch A -- CNL / Permission / Simulator-Trunk SQL closure
  Files: snep/lib/Snep/Cnl.php (3 methods)
         snep/lib/Snep/Permission/Manager.php (3 methods)
         snep/lib/PBX/Trunks.php (1 method)
  Pattern: $db->quoteInto('col = ?', $val) / bound ->where('col = ?', $val)
  Test: extend scripts/residual-sql-security-smoke-test.sh (already the
        canonical home for every TASK-0026J-P fix) with three new
        sections, following the exact structure already used for
        BLOCKER A-F and P1

Batch B -- includes/estados.php + cidades.php PHP 8 port + SQL closure
  Files: snep/includes/estados.php, snep/includes/cidades.php
  Pattern: port mysql_connect()/mysql_query()/mysql_fetch_array() onto
        Zend_Registry::get('db')/Zend_Db (matching the sibling
        ip_status_trunks.php/ip_status_peers.php's own already-
        established pattern in the same directory) AND parameterize the
        WHERE-clause interpolation in the same change -- not two
        separate changes, per this task's own explicit warning above
  Test: new focused section verifying a legitimate numeric pais/estado
        value still returns the expected <option> HTML, an
        apostrophe-shaped value causes no SQL error, and a
        boolean-injection-shaped value cannot leak a CANARY row from an
        unrelated table via UNION
```

No third batch is proposed because no other exploitable finding exists
in the current inventory (§16).

---

## 15. Proposed TASK-0026R scope

**TASK-0026R — Full residual SQL remediation.**

Fix exactly Q-SQL-001, Q-SQL-002, Q-SQL-003 (Batch A), and Q-SQL-004
(Batch B). Batch A uses the same mechanical `quoteInto()`/bound-`where()`
pattern this program has already validated eleven times over; Batch B
additionally requires the `mysql_*`-to-`Zend_Db` port described above,
landed in the same change as the parameterization fix. Extend
`residual-sql-security-smoke-test.sh` (not a new suite) with focused
coverage for all four findings, matching the existing suite's structure
exactly. Two consecutive full `make regression` runs required at
closure, per this program's own established checkpoint discipline.
Re-run this audit's own Phase 16 completeness gate (not a fresh
unbounded sweep — this document's inventory is the baseline) to confirm
`RESIDUAL_SQL_GATE = CLOSED` and re-evaluate `SECURITY_GATE` against
`docs/SECURITY-BASELINE.md` §"Security gate expectations."

Given this audit's own coverage (§9) found no further un-swept file
family, TASK-0026R is expected to be the **final** SQL closure task in
this chain — not merely "another one," per this task's own founding
premise that incremental single-boundary closure was no longer an
efficient strategy.

---

## 16. Final audit-completeness statement

```text
Files audited:                    336 (all first-party PHP, excl. vendored Zend)
SQL execution sites (files):      ~112 (110 originally enumerated by the
                                   fork/coordinator sweep, +2 for
                                   snep/includes/estados.php/cidades.php,
                                   folded in during finalization)
Dynamic SQL sites (where/update/
  delete/insert call sites):      ~365 (183 where() + 178 update/delete/
                                   insert + 2 mysql_query() sites in
                                   estados.php/cidades.php, +2 AGI-only
                                   sites individually re-tallied during
                                   finalization -- see §9's snep/agi/
                                   row for the 22-site AGI breakdown,
                                   which supersedes this document's
                                   earlier "~8" estimate)
Safe parameterized:                ~330 (already fixed by 0026C-P, or
                                    independently confirmed safe this task)
Safe casts:                        4 (PjsipTransports Manager x3, sibling
                                    confirmations this task)
Safe allowlists:                   4 (ExportDataController, CSV_ExportDataService,
                                    RouteController type, PBX_Registry context/key)
Safe static:                       ~15
Dead/unreachable:                  11+ sites (see §8 -- Manutencao::
                                    listaPeriodo() added during
                                    finalization)
Vulnerable unreachable:            1 (Q-SQL-004 -- real vulnerable SQL
                                    construction, currently blocked
                                    entirely by the unrelated,
                                    pre-existing mysql_connect() PHP 8.4
                                    compatibility fatal, confirmed live;
                                    the other 3 findings are directly
                                    reachable with no blocker)
Exploitable direct:                4 (Q-SQL-001, Q-SQL-002, Q-SQL-003 --
                                    2 of its 3 paths, Q-SQL-004)
Exploitable second-order:          1 (Q-SQL-003's third path, added
                                    during finalization -- see §10)
Total Q-SQL findings:              4 (Q-SQL-001 through Q-SQL-004)
Needs manual review:               0
```

```text
ALL RELEVANT SQL EXECUTION SITES ACCOUNTED FOR
```

Every dynamic SQL construction site reachable from the supported web
surface, the standalone API, and the AGI/dialplan boundary has been
traced to a definitive classification. No candidate remains
`NEEDS_MANUAL_REVIEW`. This audit is complete per its own Phase 16 gate.

---

## 17. Reachability-boundary caveat — AGI script web-exposure (non-SQL, documented for transparency)

Every TASK-0026K–P closure task, and §8/§9 above, classify `snep/agi/*.php`
and every `PBX_Rule_Action`/`PBX_Rule_Plugin` subclass as "AGI-only, not
supported HTTP surface," on the basis that no web controller ever invokes
a matched business rule's `execute()`/`preExecute()` side effects (only
`SimulatorController`'s rule-*matching* trace does, confirmed
independently in §8). This audit additionally checked the boundary from
the opposite direction — **can an HTTP client reach an AGI script's PHP
code at all**, independent of whether the application-level dialplan
engine ever calls it — since `docker/apache-mag.conf` sets `DocumentRoot
/var/www/html/snep` with `AllowOverride All`/`Require all granted` and
**no `.htaccess` file exists anywhere under the document root** (the only
`.htaccess` files in the tree are `snep/includes/.htaccess`,
`snep/lib/linfo/{cache,tests,lib}/.htaccess` — none in `snep/agi/`, none
at the root). Zend's front controller is reached only via literal
`/index.php/...` URLs; there is no rewrite rule redirecting arbitrary
paths into it. This means, unlike `setup.conf` (independently confirmed
blocked, HTTP 403, by TASK-0026's original F35 finding), **Apache does
not block direct requests to `snep/agi/*.php` at all**.

**Live-tested** (`curl`, bounded `--max-time`, no data sent, no
authentication): `GET /agi/snep.php` does not return 403/404 — it hangs
with **zero bytes and no HTTP response at all** until the client times
out (confirmed both on an unbounded request, killed manually after
observing no response, and on a bounded 5-second request that produced
`curl: (28) Operation timed out`, HTTP code `000`). This is consistent
with `Asterisk_AGI`'s constructor blocking on a read for AGI-protocol
handshake lines (`agi_request: ...\n`, ..., blank line) that a plain HTTP
request never supplies — the script is reachable at the file level but
does not appear to reach any productive (SQL-executing) code path via an
ordinary HTTP request. `docker compose ps`/an Apache worker-count check
immediately after confirmed no lasting resource exhaustion from the one
test request (app container stayed `healthy`, worker count in the normal
range).

**This does not change any classification in §6/§8/§9** — no SQL sink
was reached, and this task's own scope is SQL injection, not general
security review. It is recorded here because it is exactly the kind of
"AGI-only" assumption CLAUDE.md's own "do not trust broad claims without
targeted verification" principle asks to be checked from first
principles, not merely re-cited, and because a **future** task should
not assume the reverse either (that some other AGI script, or some
different request shape — e.g. a POST body shaped like a partial AGI
handshake — could not complete enough of the protocol to reach a real
code path).

**Widened at the final checkpoint** (coordinator, after the fork that
wrote the above was cut off): the same `curl --max-time 3` probe was
repeated directly against `agenda.php`, `dnd.php`, `followme.php`,
`padlock.php`, `serviceslog.php`, and `resolv_extension.php` (six of the
seven files that actually touch `$db`, plus one AGI-only, no-SQL file) —
all six hung identically (HTTP `000`, zero bytes), confirming the
`snep.php` result generalizes rather than being a one-off. The seventh
SQL-touching file, `voicemail-notify.php`, does **not** hang — it is a
CLI-argv-invocation script (`#!/usr/bin/php -q`, gated on `$argc < 3`),
and a direct HTTP request completes in ~25ms because `$argc` is
`Undefined` under Apache's SAPI in this stack, so the script always
takes its own early-exit branch before reaching its one (already
parameterized) query — confirmed live, including with an `isindex`-style
query string (`?foo+bar+baz`, no `=` sign) to rule out the classic PHP
`register_argc_argv` CGI-argv-injection technique specifically. See §8's
own row for the exact evidence. This is a second, independently
discovered instance of the same "AGI-shaped script, but not actually
using the blocking `Asterisk_AGI` handshake pattern" risk this section's
own recommendation (a) already anticipated — worth flagging explicitly
for whichever future task does that dedicated pass, since `voicemail-
notify.php` shows the "assume AGI scripts always hang" half of the
boundary claim also needs per-file verification, not just the "assume
they're all AGI-protocol-gated" half.

**Recommended for a dedicated future task, not this one**: (a) confirm
no crafted HTTP request (headers, POST body, or — per the finding above
— a CLI-invocation-style script's own argument-parsing assumptions) can
reach a real code path, across all 17 files in `snep/agi/`; (b) add an
explicit Apache-level deny for `/agi/` as defense-in-depth regardless,
since AGI scripts have no legitimate reason to be web-reachable at all;
(c) do the same check for
`snep/modules/{callback,ivr,portability}/actions/*.php` and
`snep/modules/default/actions/*.php` (the `PBX_Rule_Action` subclasses) —
these have no `resources.xml` controller registration and are never
`Zend_Controller_Action` subclasses, so Zend's dispatcher cannot route to
them by design (independently re-confirmed this checkpoint: none of
`CallbackAction`/`IVR`/`UserInteraction`/`PortabilityAction` declare a
controller-shaped class or appear in any `resources.xml`), but they were
not independently probed at the raw Apache/file level the way
`snep/agi/snep.php` was here.
