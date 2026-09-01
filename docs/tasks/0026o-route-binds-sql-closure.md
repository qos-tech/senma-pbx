# TASK-0026O — Route List and User Binds SQL Boundary Closure

## Status

Implementation complete and validated for both confirmed TASK-0026N
residual sinks (route list, user binds), plus the one sibling method in
`Snep_Binds_Manager` sharing the exact same raw-interpolation root cause
(3 sites fixed across 2 files). Focused smoke suite (196/196, up from
171/171), `make lint`, and two consecutive full `make regression` runs
(22/22 suites each) all PASS.

An unrelated infrastructure blocker (the pinned Asterisk 22.10.1 source
tarball no longer exists on `downloads.asterisk.org`) was discovered
while bringing up the validation environment and fixed as its own
narrowly-scoped change (bumped to 22.11.0), with explicit user
authorization before touching it. See "Unrelated infrastructure fix"
below.

**This task's own Phase 7 final supported-surface SQL sweep found a
further, confirmed-exploitable, unremediated instance of the same
root-cause SQL-injection class entirely outside this task's assigned
scope (`RouteController`/`Snep_Binds_Manager` only) — in
`Snep_ModuleSettings_Manager::getConfig()`, reachable via
`ModuleSettingsController::indexAction()`'s POST field-name parsing. Per
CLAUDE.md's "do not fix unrelated legacy bugs opportunistically" and this
task's own governing instructions, no code was changed to fix it — it is
documented here and handed off as evidence for a required follow-up
task, not auto-created.**

Not committed — this is the validated TASK-0026O checkpoint, awaiting
explicit authorization to commit.

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

## Scope

Closes the two confirmed SQL-injection sinks TASK-0026N's own Phase 8
final sweep discovered but explicitly left unfixed
(`docs/tasks/0026n-pbx-rule-sql-closure.md`, "Security handoff"):

- **O1** — `RouteController::indexAction()`'s own inline SQL
  (`snep/modules/default/controllers/RouteController.php`).
- **O2/O3** — `Snep_Binds_Manager::removeBond()`/`removeBondException()`
  (`snep/lib/Snep/Binds/Manager.php`).

Per this task's own explicit Phase 3/6 instructions ("audit all sibling
SQL methods in `Snep_Binds_Manager`... if clearly equivalent sibling
sinks are found, fix them here"), this task also fixes:

- `Snep_Binds_Manager::removeBondByPeer()` — a genuine sibling sharing
  the identical `delete(..., "col = '$var'")` pattern, confirmed
  DIRECTLY reachable (not merely DB-derived, contrary to TASK-0026N's
  own characterization — see Phase 3 below) via
  `ExtensionsController::removeAction()`'s raw `$_POST['id']`.

3 sites fixed total across 2 files.

Does not touch: route redesign, user-management redesign, telephony
semantics, legacy SIP removal, UI/menu/i18n, or Product Readiness — all
explicitly out of scope per this task's own instructions. Product
Readiness work was not started.

## Phase 1 — Blocker inventory reconstruction

Reconstructed from current source (not from category names alone), each
traced end to end (`HTTP request → controller → SQL construction /
Manager → database execution`):

| ID | Class/file | Method | Entry point | Controlled value | SQL sink (pre-fix) | Direct/second-order | Exploitability |
|---|---|---|---|---|---|---|---|
| O1 | `RouteController` | `indexAction()` | route list page itself (`default_route_read`/`default_route_write`) | `$_GET['type']` | `->where("type = '$type'")` | DIRECT | confirmed live |
| O2 | `Snep_Binds_Manager` | `removeBond($id)` | `UsersController::removeAction()` (route param `id`) and `::bondAction()` (`$_POST['id']`), both `default_users_write` | raw `$id` | `->delete('core_binds', "user_id = '$id'")` | DIRECT | confirmed live |
| O3 | `Snep_Binds_Manager` | `removeBondException($id)` | same `bondAction()` POST, same `$data['id']` | raw `$id` | `->delete('core_binds_exceptions', "user_id = '$id'")` | DIRECT | confirmed live |

**Sibling found during reconstruction, fixed as an exact match**:
`Snep_Binds_Manager::removeBondByPeer($peer)` — reachable via
`ExtensionsController::removeAction()`
(`snep/modules/default/controllers/ExtensionsController.php:939`) with
`$exten = $_POST['id']` (raw, unvalidated). TASK-0026N's own handoff
characterized this as "not independently confirmed exploitable... only
ever DB-derived-int-PK-fed at its one call site" — that characterization
was incorrect: `getPeer($exten)` (line 932) is called first, but its
result assigns only `$idExten = $result['id']`; the call to
`removeBondByPeer($exten)` two lines later still passes the **original
raw `$exten`**, not `$idExten`. Since `Snep_Extensions_Manager::getPeer()`
returns `false` (not an exception) for a non-matching id
(`snep/lib/Snep/Extensions/Manager.php:90-103`, a plain `fetch()`),
execution reaches `removeBondByPeer()` with the raw, still-injectable
value regardless of whether it matches a real extension. Confirmed live
during this task's own development (Phase 4).

## Phase 2 — `RouteController::indexAction()`

**Domain analysis**: `regras_negocio.type` is a MariaDB
`enum('incoming','outgoing','others') NOT NULL DEFAULT 'others'` column
(`snep/install/database/schema.sql`). The only three values a real row
can ever carry are the ones offered by `route/index.phtml`'s own dropdown
links (`type=incoming`/`type=outgoing`/`type=others`) and
`route.xml`'s `typeRule` select element. This is a finite, closed domain
— per this task's own explicit Phase 2 preference ("If `type` is
selecting between a finite set of route categories, prefer a strict
allowlist"), an allowlist was used rather than parameterization alone.

**Fix** (`snep/modules/default/controllers/RouteController.php`,
`indexAction()`):

```php
// before
if(isset($_GET["type"])){
    $type = $_GET['type'];
    $select = $db->select()->from("regras_negocio")->where("type = '$type'");
}else{
    $select = $db->select()->from("regras_negocio");
}

// after
$validRouteTypes = array("incoming", "outgoing", "others");
$select = $db->select()->from("regras_negocio");
if(isset($_GET["type"])){
    $type = $_GET['type'];
    if (in_array($type, $validRouteTypes, true)) {
        $select->where("type = ?", $type);
    } else {
        $select->where("1 = 0");
    }
}
```

A value outside the enum's domain can never have matched a real row even
before this fix (any real `regras_negocio.type` is always one of the
three enum values) — falling to `1 = 0` (an empty result set) for any
unrecognized/malicious `type` therefore preserves pre-fix behavior for
every legitimate input while eliminating the interpolation entirely.
`?type=incoming`/`outgoing`/`others` (with or without `hide_routes`),
pagination, ordering, and the "no `type` given" default are all
byte-for-byte unchanged.

**Sibling audit — `RouteController`, full file**: this was the only raw
SQL construction site in the controller. Every other action
(`add`/`edit`/`duplicate`/`remove`/`toogle`) delegates to `PBX_Rules`
(already `PARAMETERIZED_SAFE`, fixed by TASK-0026N) or
`Snep_Route::getRegra()` (`snep/lib/Snep/Route.php:49-69`, already
`PARAMETERIZED_SAFE` — three `->where(..., ?)` bound statements,
unchanged). `RouteFormController.php` (the route editor's own AJAX
helper, `RouteFormController::get_rule_actions()`) contains no SQL of its
own — it also delegates to the already-safe `PBX_Rules::get()`.
`cleanSrcDst()` performs no SQL. No further RouteController-family sites
required a fix.

## Phase 3 — `Snep_Binds_Manager`

**Fix** (`snep/lib/Snep/Binds/Manager.php`):

```php
// before (removeBond)
$db->delete('core_binds', "user_id = '$id'");
// after
$db->delete('core_binds', $db->quoteInto('user_id = ?', $id));

// before (removeBondException)
$db->delete('core_binds_exceptions', "user_id = '$id'");
// after
$db->delete('core_binds_exceptions', $db->quoteInto('user_id = ?', $id));

// before (removeBondByPeer, sibling)
$db->delete('core_binds', "peer_name = '$peer'");
// after
$db->delete('core_binds', $db->quoteInto('peer_name = ?', $peer));
```

Mechanical, minimal-diff — the exact `$db->quoteInto('col = ?', $val)`
pattern this program has now used nine times over (TASK-0026C/F1/J/K/L/M/N
and this task). Bind removal, exception removal, and user/extension
lifecycle semantics are unchanged for every legitimate id.

**Full class sibling audit** (`snep/lib/Snep/Binds/Manager.php`):

| Method | SQL | Classification |
|---|---|---|
| `getBond($id)` | `->where("core_binds.user_id = ?", $id)` | `PARAMETERIZED_SAFE` — unchanged |
| `getBondException($id)` | `->where("core_binds_exceptions.user_id = ?", $id)` | `PARAMETERIZED_SAFE` — unchanged |
| `addBond()` / `addBondException()` | `$db->insert(...)` only | `PARAMETERIZED_SAFE` — unchanged |
| `removeBond($id)` | see above | **O2 — fixed** |
| `removeBondByPeer($peer)` | see above | **sibling — fixed** |
| `removeBondException($id)` | see above | **O3 — fixed** |
| `ResultBinds()` | no SQL (array-only logic) | `STATIC_SAFE` — unchanged |

No unexplained request-controlled SQL interpolation remains in this
class.

**`UsersController` sibling check**: `indexAction()`'s own inline SQL
(`snep/modules/default/controllers/UsersController.php:56-60`) is fully
static (unconditional `users`/`profiles` join, no request-controlled
value) — `STATIC_SAFE`. Every other action delegates to
`Snep_Users_Manager`, whose every method (`get()`, `getAll()`,
`getName()`, `remove()`, `edit()`, `addProfileByName()`,
`removeQueuesPermission()`, etc. —
`snep/lib/Snep/Users/Manager.php`) is already `PARAMETERIZED_SAFE`
(`quoteInto()`/bound `where(?, ...)` throughout, including the mass-
privilege-escalation sink TASK-0026C already closed in
`addProfileByName()`). No fix needed there — outside this task's assigned
scope regardless (`Snep_Binds_Manager` only).

## Phase 4 — Safe exploit proof

All boundaries were reproduced pre-fix and reconfirmed clean post-fix
through the real, authenticated HTTP flow (or, where a real
`core_binds`/`core_binds_exceptions` row's FK requires fixture `users`/
`peers` rows not easily reached over HTTP, through direct Manager
invocation using the same CLI-bootstrap pattern this program's suite
already uses) — never a direct unauthenticated DB connection, never
password/hash/schema extraction, only harmless apostrophe-shaped and
boolean-oracle payloads.

| Sink | Payload | Pre-fix | Post-fix |
|---|---|---|---|
| O1, `RouteController::indexAction()` | `?type=foo%27bar` (authenticated GET) | `SQLSTATE[42000]... near 'bar') ORDER BY \`prio\` DESC, \`id\` ASC' at line 1` | HTTP 200, no SQL error |
| O2, `UsersController::removeAction()` | `id=foo'bar` (authenticated POST) | `SQLSTATE[42000]... near 'bar')' at line 1` | HTTP 302, no SQL error |
| O3, `removeBondException()` (direct invocation) | `"foo'bar"` | `SQLSTATE[42000]... near 'bar')' at line 1` | no exception |
| sibling, `removeBondByPeer()` (direct invocation) | `"foo'bar"` | `SQLSTATE[42000]... near 'bar')' at line 1` | no exception |
| O2/O3 boolean isolation (direct invocation, real victim fixture) | `"0' OR user_id='{$victimId}"` | genuinely deleted the victim's real `core_binds`/`core_binds_exceptions` row (confirmed: row count 1→0 pre-fix) | victim's row unchanged (count stays 1) |

The boolean-isolation payload above is the classic apostrophe-escape
form (`"user_id = '$id'"` requires an actual `'` to break out, not a
bare `0 OR ...`) — verified by constructing a real "victim" `users` row
with a real `core_binds`/`core_binds_exceptions` row (FK-required,
`snep/install/database/schema.sql`), issuing the malicious call against a
*different* target string that resolves to the victim's real id, and
confirming pre-fix it genuinely cross-matched and deleted the victim's
row, post-fix it did not.

For O1, a real `type=outgoing` canary route (unique `desc` marker,
created via `PBX_Rules::register()`) was used to prove the same property
for the list-filtering boundary: a boolean-shaped, non-allowlisted `type`
value cannot bypass the filter to leak the canary across type boundaries
(the exact bypass a pre-fix `where("type = '$type'")` would have allowed
via `?type=foo' OR '1'='1`).

## Phase 5 — Extended residual SQL security suite

Extended (not duplicated) `scripts/residual-sql-security-smoke-test.sh` /
`make residual-sql-security-smoke`, preserving every existing
TASK-0026J–N check unchanged (171 retained).

New coverage, 25 checks:

- **Preflight**: `/index.php/default/users` added to the zero-permission
  authorization-boundary loop (correctly denied). `default_users_write=1`
  added to the admin permission-grant step. `default_route_read=1` added
  alongside the existing `default_route_write=1` — see "Pre-existing
  authorization quirk discovered" below for why both are required.
- **Route list (8 checks)**: legitimate list; legitimate `type=incoming`;
  apostrophe-shaped `type` (no SQL error); a real `type=outgoing` canary
  route fixture; positive control (`type=outgoing` shows the canary);
  negative control (`type=incoming` hides it); the core boolean proof
  (a boolean-shaped `type` cannot leak the canary across the filter);
  an unsupported-but-harmless `type` value (fails safely, no rows, no
  error).
- **User binds real-HTTP proof (1 check)**: apostrophe-shaped
  `UsersController::removeAction()` id (O2).
- **User binds direct-invocation coverage (14 checks)**: real victim/
  other `users` + `peers` + `core_binds`/`core_binds_exceptions` fixture
  pair; apostrophe-shaped and boolean-isolation checks for
  `removeBond()`, `removeBondException()`, and the `removeBondByPeer()`
  sibling; legitimate-flow removal for all three; inline cleanup.
- **Health check (1 check)**: PHP Fatal Error count unchanged.
- A best-effort DB-level safety-net cleanup was also registered in case
  the direct-invocation fixture script aborts before its own inline
  cleanup runs, per this task's own explicit "Guarantee cleanup"
  instruction.

**Result: PASS, 196/196** (up from 171/171). Cleanup ran cleanly —
`regras_negocio` back to its exact baseline (1 row), zero
`task0026o`-prefixed residue in `users`/`peers`/`core_binds`/
`core_binds_exceptions`.

## Phase 6 — Sibling audit summary

| File | Site | Classification |
|---|---|---|
| `RouteController.php` | `indexAction()`'s `type` filter | `ALLOWLISTED_IDENTIFIER` — `FIXED_BY_0026O` |
| `RouteController.php` | every other action (delegates to `PBX_Rules`/`Snep_Route`) | `PARAMETERIZED_SAFE` — unchanged |
| `RouteFormController.php` | `get_rule_actions()` (delegates to `PBX_Rules::get()`) | `PARAMETERIZED_SAFE` — unchanged |
| `Snep/Route.php` | `getRegra()` (3 statements) | `PARAMETERIZED_SAFE` — unchanged |
| `Snep/Binds/Manager.php` | `removeBond()` | `PARAMETERIZED_SAFE` — `FIXED_BY_0026O` |
| `Snep/Binds/Manager.php` | `removeBondException()` | `PARAMETERIZED_SAFE` — `FIXED_BY_0026O` |
| `Snep/Binds/Manager.php` | `removeBondByPeer()` | `PARAMETERIZED_SAFE` — `FIXED_BY_0026O` |
| `Snep/Binds/Manager.php` | `getBond()`, `getBondException()`, `addBond()`, `addBondException()`, `ResultBinds()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — unchanged |
| `UsersController.php` | `indexAction()`'s inline SQL | `STATIC_SAFE` — unchanged |
| `UsersController.php` | every other action (delegates to `Snep_Users_Manager`) | `PARAMETERIZED_SAFE` — unchanged |
| `Snep/Users/Manager.php` | every method | `PARAMETERIZED_SAFE` — already closed by TASK-0026C, re-confirmed, unchanged |

No unexplained request-controlled SQL interpolation remains in either of
this task's two assigned boundaries.

## Phase 7 — Final supported-surface SQL sweep

A repository-wide sweep for `request-controlled value → raw SQL
construction → database execution` and `persisted user-controlled value
→ raw SQL construction → database execution`, matching the methodology
TASK-0026Z/J/K/L/M/N each used at their own closure point. This sweep
also resolved TASK-0026M/N's five carried-forward, previously
unconfirmed candidates to a definitive verdict:

| Candidate | Verdict |
|---|---|
| `snep/lib/Snep/Extensions.php` (`Snep_Extensions` class — distinct from `Snep_Extensions_Manager`) | `DEAD/UNREACHABLE` — zero callers anywhere in the tree (confirmed via repository-wide search); raw-interpolated sinks in `get()`/`update()`/`delete()` exist but are never invoked |
| `snep/lib/Snep/Operadoras.php` | `DEAD/UNREACHABLE` — zero callers anywhere in the tree; same disposition |
| `snep/lib/Snep/PjsipTransports/Manager.php:253` (`update()`) | `PARAMETERIZED_SAFE`/effectively-safe — `$id = (int) $id;` casts before the raw `"id = $id"` interpolation, neutralizing any injection regardless of input |
| `PBX_Rules::getAll()`'s optional `$where` | `DEAD/UNREACHABLE`, re-confirmed — both call sites (`PBX_Dialplan.php:68`, `PBX_Dialplan/Verbose.php:114`) still always call with zero arguments |
| `snep/lib/Snep/ModuleSettings/Manager.php` | **confirmed exploitable — see below** |

**Confirmed exploitable, NEW, outside this task's assigned scope**:

`Snep_ModuleSettings_Manager::getConfig($module)`
(`snep/lib/Snep/ModuleSettings/Manager.php`):

```php
$select = $db->select()->from('core_config')->where("config_name = '$module'");
```

Reachable via `ModuleSettingsController::indexAction()`'s own POST
handling (`snep/modules/default/controllers/ModuleSettingsController.php:254`):

```php
foreach($formData as $key => $value){
    $res = explode("_x_", $key);
    ...
    $exist_config = Snep_ModuleSettings_Manager::getConfig($res[1]);
```

`$key` iterates the raw **field names** of the submitted POST body (not
their values) — an attacker fully controls arbitrary field names in a
raw HTTP POST, so `$res[1]` is directly attacker-controlled.
`module-settings` has no `write` child in `resources.xml` (only a bare
`<resource id="module-settings">`), so only a `default_module-settings_read`
grant exists at all — this action is reachable by a **read**-only grant,
not merely a write one.

**Confirmed live**: an authenticated POST to
`/index.php/default/module-settings` with a field named
`default_x_foo'bar=someval` produced a genuine
`SQLSTATE[42000]: Syntax error or access violation: 1064 ... near
'bar')' at line 1`.

Sibling disposition within the same class: `get($module)`
(`->where("config_module = '$module'")`) shares the identical pattern,
but its only two real call sites
(`ModuleSettingsController.php:151,181`) pass `"default"` (a hardcoded
literal) or `$val["name"]` (sourced from `json_decode()` of a
filesystem `config.json`, not request-controlled) — not independently
confirmed exploitable via any supported HTTP surface. `delConfig($module)`
(`->delete("core_config", "config_module='{$module}'")`) has zero
callers anywhere in the tree — `DEAD/UNREACHABLE`. `updateConfig()`'s
real call site (`ModuleSettingsController.php:257`) passes a properly
`quoteInto()`-shaped array (`['config_module = ? ' => $res[0], ...]`,
Zend_Db's array-keyed `_whereExpr()` form) — `PARAMETERIZED_SAFE` in
practice, despite the method's own signature not enforcing that shape on
a hypothetical future caller. `addConfig()` uses `$db->insert()` only —
`PARAMETERIZED_SAFE`.

Not modified. Outside this task's assigned scope (`RouteController`/
`Snep_Binds_Manager` only), and per CLAUDE.md's "do not fix unrelated
legacy bugs opportunistically"/"do not mix migration phases" principles,
fixing it is not this task's call to make unilaterally.

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

Per this task's own explicit instruction ("If another clearly
exploitable supported-surface SQL sink is found: STOP… Do not
automatically create TASK-0026P"), **no new task was created**. This
finding is handed off as evidence only.

## Phase 8 — Focused validation

```bash
make residual-sql-security-smoke
```

**Result: PASS, 196/196** (up from 171/171). Both assigned headline
findings closed, plus the one sibling site discovered during
reconstruction. Every TASK-0026J–N check preserved and still passing.
Cleanup: every fixture's own inline cleanup succeeded, backed by an
additional DB-level safety net; `regras_negocio` confirmed back to its
exact baseline (1 row); no `task0026o`-prefixed residue in
`users`/`peers`/`core_binds`/`core_binds_exceptions`.

## Unrelated infrastructure fix

While bringing up the Docker environment for this task's own validation
(`make up`), the build failed:
`docker/asterisk.Dockerfile` pinned `ASTERISK_VERSION=22.10.1`, but
`downloads.asterisk.org` no longer serves that tarball (confirmed live:
HTTP 404) — Asterisk keeps only the latest published patch per LTS
branch on that server, and `22.11.0` has since superseded `22.10.1`
there. This blocked `make up`/`make lint`/`make regression`/the residual
SQL smoke suite entirely, unrelated to this task's own SQL-injection
scope.

Per this project's "check with the user before risky/shared-infra
changes" discipline, explicit authorization was requested before
touching it (three options offered: bump the pin to 22.11.0, switch to
the GitHub source-tag archive for the exact same 22.10.1 version, or
stop and wait). The user chose to bump the pin.

**Fix**: `docker/asterisk.Dockerfile`'s `ARG ASTERISK_VERSION` bumped
from `22.10.1` to `22.11.0` (confirmed via the GitHub releases API: tag
`22.11.0`, `prerelease=false`, published 2026-08-27 — a genuine, current,
non-prerelease Asterisk 22 LTS release, still pinned to an exact version
per CLAUDE.md's Docker rules, not `latest`).
`scripts/smoke-test.sh`'s `systemstatus` check (part of the `http-smoke`
regression suite) asserts the exact rendered Asterisk version string —
updated from `'Asterisk - 22.10.1'` to `'Asterisk - 22.11.0'` to match,
otherwise that pre-existing check would have started failing on every
future run regardless of this task's own changes.

No Asterisk 22.11.0-specific compatibility work was performed or was in
scope — `make lint` and two full `make regression` runs (Phase 9) both
passed cleanly against it, including `pjsip-config-security`,
`call-smoke`, `trunk-smoke`, `transport-smoke`, and `restart-smoke`.

## Pre-existing authorization quirk discovered, deliberately not fixed

Not an SQL defect, so not fixed here per CLAUDE.md's "do not fix
unrelated legacy bugs opportunistically" — documented as debt.
`RouteController::indexAction()` and `UsersController`'s actions both
require a distinct `_read`-suffixed permission for the list/index action
specifically — a `_write` grant alone is not sufficient. This surprised
this task's own development: `resources.xml`'s `<resource id="route">`
and `<resource id="users">` each declare **only** a `<resource
id="write">` child, yet `Snep_Modules::loadResources()`
(`snep/lib/Snep/Modules.php:143-151`) synthesizes an implicit `read`
entry for **every** top-level resource regardless of what its own
children declare (`if (!isset($explode[2]) || !$explode[2]) $explode[2]
= "read";`), and `Snep_PermissionPlugin::preDispatch()` always maps
`action=='index'` to `type='read'`
(`snep/modules/default/model/PermissionPlugin.php:150-155`). The
permission-editing UI does show both checkboxes
(`UsersController::permissionAction()`'s own `$controller["write"] =
$controller["read"];` line copies the "read" label onto "write"'s
otherwise-empty one) — but under the **exact same visible label** for
both, making it easy for an admin to grant only "write" and be surprised
the list page itself still denies access. Confirmed live during this
task's own development (a restricted user granted only
`default_route_write` got HTTP 302→`permission/error` on a bare
`/index.php/default/route` GET; adding `default_route_read` fixed it).
This task's own residual SQL smoke suite now grants both
`default_route_read` and `default_route_write` for that reason.

## Files changed

```
docker/asterisk.Dockerfile                     unrelated infra fix -- Asterisk pin bump (22.10.1 -> 22.11.0)
scripts/smoke-test.sh                          unrelated infra fix -- systemstatus version-string check updated to match
scripts/residual-sql-security-smoke-test.sh    TASK-0026O focused coverage (+25 checks, 171->196)
snep/lib/Snep/Binds/Manager.php                O2/O3 + removeBondByPeer() sibling (3 sites)
snep/modules/default/controllers/RouteController.php   O1 (1 site, allowlist)
```

Every other prior TASK-0026x file is untouched.
`RouteFormController.php`/`UsersController.php`/`Snep/Route.php`/
`Snep/Users/Manager.php` are untouched (already safe). Product Readiness
work was not started.

## Security handoff — why `SECURITY_GATE` remains `NO-GO`

Per Phase 7's explicit instruction, this task stops here rather than
silently expanding its own scope. Both assigned headline sinks (and
their one in-class sibling) are closed, verified, and
regression-covered. However:

```text
known SQL injection = 0 in supported surfaces   NOT SATISFIED
```

`Snep_ModuleSettings_Manager::getConfig()`'s own `$module` interpolation
(reachable via `ModuleSettingsController::indexAction()`'s POST
field-name parsing, gated only by a **read**-level permission) carries
the exact same unescaped-`'$var'`-in-`WHERE`-clause defect this task and
its six predecessors have now closed nine times over — not touched by
this task.

**Recommended next task** (not opened automatically, per Phase 7): close
this confirmed sink (`snep/lib/Snep/ModuleSettings/Manager.php`,
`getConfig()`) using the exact same `$db->quoteInto()`/bound-`where()`
pattern this task and TASK-0026C/F1/J/K/L/M/N have now established nine
times over, reached via `ModuleSettingsController::indexAction()`. While
auditing that file, also resolve `get($module)`'s disposition for
defense-in-depth (currently only file/literal-fed at its two real call
sites, same reasoning TASK-0026N applied to `PBX_Usuarios::get()`'s
fragile-but-currently-safe escape) and note `delConfig()`'s
`DEAD/UNREACHABLE` status if it is not independently fixed. Every other
candidate this task's own Phase 7 sweep touched
(`Snep/Extensions.php`, `Snep/Operadoras.php`,
`Snep/PjsipTransports/Manager.php:253`, `PBX_Rules::getAll()`'s dead
`$where`) was resolved to a definitive, evidenced verdict and needs no
further follow-up.
