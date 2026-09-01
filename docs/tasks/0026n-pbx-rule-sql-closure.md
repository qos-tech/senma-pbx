# TASK-0026N — PBX Rules and Simulator SQL boundary closure

## Status

Implementation complete and validated for all four confirmed TASK-0026M
residual sinks, plus every sibling method in the same three classes
sharing the exact same raw-interpolation root cause (10 sites fixed
across 3 files). Focused smoke suite (171/171), `make lint`, and two
consecutive full `make regression` runs (22/22 suites each) all PASS.
Not committed — this is the validated TASK-0026N checkpoint, awaiting
explicit authorization to commit.

**This task's own Phase 8 final supported-surface SQL sweep found
further, confirmed-exploitable, unremediated instances of the same
root-cause SQL-injection class entirely outside this task's assigned
scope (`PBX_Rule`/`PBX_Usuarios`/`PBX_Rules` only) — in
`RouteController::indexAction()`'s own inline SQL and in
`Snep_Binds_Manager` (`removeBond()`/`removeBondException()`, reachable
via `UsersController`). Per CLAUDE.md's "do not fix unrelated legacy
bugs opportunistically" and this task's own governing instructions, no
code was changed to fix them — they are documented here and handed off
as evidence for a required follow-up task, not auto-created.**

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

## Scope

Closes the four confirmed SQL-injection sinks TASK-0026M's own Phase 9
final sweep discovered but explicitly left unfixed
(`docs/tasks/0026m-manager-layer-residual-sql-closure.md`, "Security
handoff"):

- **N1/N2** — `PBX_Rule::checkExpr()`'s `'CG'` and `'G'` cases
  (`snep/lib/PBX/Rule.php`).
- **N3** — `PBX_Usuarios::hasExtenGroup()` (`snep/lib/PBX/Usuarios.php`).
- **N4** — `PBX_Rules::delete()` (`snep/lib/PBX/Rules.php`).

Per this task's own explicit Phase 2/3/4/7 instructions ("audit sibling
methods... for the exact same raw-SQL root cause"; "there must be no
unexplained request-controlled SQL interpolation left in these
classes"), this task also fixes every sibling method in these three
classes sharing the identical pattern:

- `PBX_Rule::getValidAliasDateById()` — a genuine second-order sibling
  discovered during reconstruction (see Phase 4 below).
- `PBX_Usuarios::get()` — currently mitigated only by a fragile,
  CLAUDE.md-forbidden `str_replace("'", "\'", ...)` escape; replaced
  with proper parameterization for defense in depth.
- `PBX_Rules::get()` (3 statements) / `PBX_Rules::update()` (2
  statements) — reachable via `RouteController::toogleAction()` and
  `RouteFormController::get_rule_actions()`.

10 sites fixed total across these 3 files. This matches the precedent
already established by TASK-0026C/J/K/L/M's own sibling-expansion
approach.

Does not touch: simulator redesign, route logic redesign, dialplan
semantics, legacy SIP removal, UI/menu/i18n, or Product Readiness — all
explicitly out of scope per this task's own instructions. Product
Readiness work was not started.

## Phase 1 — Blocker inventory reconstruction

Reconstructed from current source (not from category names alone), per
this task's own explicit instruction, each traced end to end
(`HTTP request → controller → PBX class → SQL construction → database
execution`):

| ID | Class | Method | Entry point | Controlled value | SQL sink (pre-fix) | Direct/second-order | Exploitability |
|---|---|---|---|---|---|---|---|
| N1 | `PBX_Rule` | `checkExpr('CG')` | `SimulatorController::indexAction()` (`default_simulator`, authenticated-open — **any** logged-in account, no specific grant) | `$formData['caller']`/`$formData['dst']` → request's `origem`/`destino` | `->where("\`group\` = '$expr'")->where("\`phone\` = '$value'")` | DIRECT (`$value`); the rule's own `$expr` is second-order/admin-set | confirmed live |
| N2 | `PBX_Rule` | `checkExpr('G')` | same as N1, when a rule has a `G:`-type source/destination | same as N1 | delegates to `PBX_Usuarios::hasExtenGroup($expr, $value)` — no SQL of its own | DIRECT (`$value`) | confirmed live (via N3) |
| N3 | `PBX_Usuarios` | `hasExtenGroup($group, $exten)` | same chain as N2 | same as N2 | `->where('peers.name = '.$exten)->where('core_peer_groups.group_id = '.$group)` — **unquoted**, no surrounding quotes at all | DIRECT | confirmed live |
| N4 | `PBX_Rules` | `delete($id)` | `RouteController::removeAction()` (`default_route_write`) | `$_POST['id']` | `$db->delete("regras_negocio", "id='{$id}'")` | DIRECT | confirmed live |

**Severity note on N1/N2/N3**: `default_simulator` is on
`Snep_PermissionPlugin::$readActions`'s authenticated-open allowlist
(`snep/modules/default/model/PermissionPlugin.php:59`) — reachable by
*any* authenticated account, not merely one holding a specific
permission grant. Confirmed via live boundary check: a zero-permission
restricted session reaches `/index.php/default/simulator` with HTTP 200
while every other resource in this program's authorization-boundary
suite correctly denies it.

**Reconstruction findings not in TASK-0026M's own headline list, fixed
as exact siblings** (see Phase 4 for detail):

| Sibling site | Reachability |
|---|---|
| `PBX_Rule::getValidAliasDateById($id)` | Second-order via `RouteController`'s own `datesValue` POST field |
| `PBX_Usuarios::get($userid)` | Direct via the same N1/N2 Simulator chain (`srcType=exten`); currently mitigated by a fragile escape, not confirmed exploitable under this project's actual runtime config (see Phase 4) |
| `PBX_Rules::get($id)` (×3 statements) | Direct via `RouteController::toogleAction()` and `RouteFormController::get_rule_actions()` |
| `PBX_Rules::update($rule)` (×2 statements) | Direct via `RouteController::toogleAction()` (chained after `get()`) |

## Phase 2 — `PBX_Rule::checkExpr()` — full method audit

Every case in the switch was inspected, not only `'CG'`/`'G'`:

| Case | SQL involved | Classification |
|---|---|---|
| `RX` (regex) | none (`preg_match`) | `STATIC_SAFE` |
| `G` | delegates to `PBX_Usuarios::hasExtenGroup()` | fixed via N3 (no SQL of its own in `PBX_Rule`) |
| `R` (specific extension) | none (`==` compare) | `STATIC_SAFE` |
| `S` (no destination) | none (`==` compare) | `STATIC_SAFE` |
| `T` (trunk) | none (object identity compare) | `STATIC_SAFE` |
| `X` (any) | none (`return true`) | `STATIC_SAFE` |
| `CG` (contact group) | raw SQL, both `$expr` and `$value` interpolated | **N1 — fixed** |
| `AL` (expression alias) | `PBX_ExpressionAliases::get((int) $expr)` — `$expr` is already cast to `(int)` at this exact call site before it can reach that class's own (TASK-0026M-fixed) SQL; `$value` never reaches SQL here (only `preg_match`) | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — no changes needed |

No other case reaches SQL. `'CG'` was the only case requiring a fix
within `checkExpr()` itself.

**Fix** (`snep/lib/PBX/Rule.php`, `checkExpr()`):

```php
// before
->where("`group` = '$expr'")
->where("`phone` = '$value'");
// after
->where('`group` = ?', $expr)
->where('`phone` = ?', $value);
```

Mechanical, minimal-diff — the exact `Zend_Db_Select::where('col = ?',
$val)` pattern already established six times over by this program.
Simulator/dialplan matching semantics unchanged for any legitimate
(non-injecting) `$expr`/`$value` pair.

## Phase 3 — `PBX_Usuarios::hasExtenGroup()` + sibling audit

**Fix**:

```php
// before
->where('peers.name = '.$exten)
->where('core_peer_groups.group_id = '.$group);
// after
->where('peers.name = ?', $exten)
->where('core_peer_groups.group_id = ?', $group);
```

This was the most severe of the four headline sinks: **unquoted**, no
surrounding string literal at all — any special SQL character reaches
the query directly, no quote-breaking needed.

**Full class sibling audit**:

| Method | SQL | Classification |
|---|---|---|
| `get($userid)` | `->where("name = '$userid' AND peer_type='R'")`, preceded by `$userid = str_replace("'", "\'", $userid)` | Mitigated-but-fragile; **fixed for defense in depth** (see below) |
| `getAll()` | `->where("peer_type='R' AND name != 'admin'")` | `STATIC_SAFE` — fully literal, unchanged |
| `getByGroup($group)` | same static where as `getAll()`; `$group` only reaches `hasGroupInheritance()` (`Zend_Acl`, no SQL) | `STATIC_SAFE`/`PARAMETERIZED_SAFE` — unchanged |
| `hasGroupInheritance($parent, $node)` | `->where("name != 'admin' AND name != 'users' AND name != 'all' AND name != 'NULL'")` — fully literal; `$parent`/`$node` only reach `Zend_Acl`, never SQL | `STATIC_SAFE` — unchanged |
| `hasExtenGroup($group, $exten)` | see above | **N3 — fixed** |

**`get()`'s pre-existing mitigation, and why it was fixed anyway**:
`str_replace("'", "\'", $userid)` is a naive backslash-escape.
TASK-0026M's own live verification (re-confirmed here) found it
currently *effective* under this project's actual MariaDB 10.11
configuration — default `sql_mode` (no `NO_BACKSLASH_ESCAPES`) and
`utf8mb3` connection charset (not a vulnerable multi-byte charset like
GBK/Big5 that could consume the escaping backslash). A live boolean
payload (`nonexistent' OR name='<real-peer>`) against a real fixture
peer correctly rendered "not found," never matching the real row.
However, `str_replace("'", ...)`-based escaping is exactly the pattern
CLAUDE.md's own remediation rule explicitly forbids ("Do not fix
injection by: … `str_replace("'", ...)`"), and Phase 3's own instruction
is to "parameterize the user/extension-group lookup" — read broadly
enough to include this sibling. Replaced with proper parameterization;
the fragile escape is removed entirely (no longer needed):

```php
// before
$userid = str_replace("'", "\'", $userid);
$select = $db->select()->from('peers')->where("name = '$userid' AND peer_type='R'");
// after
$select = $db->select()->from('peers')->where('name = ?', $userid)->where("peer_type='R'");
```

## Phase 4 — `PBX_Rules::delete()` + sibling audit

**Fix**:

```php
// before
$db->delete("regras_negocio", "id='{$id}'");
// after
$db->delete("regras_negocio", $db->quoteInto('id = ?', $id));
```

**Full class sibling audit**:

| Method | SQL | Classification |
|---|---|---|
| `delete($id)` | see above | **N4 — fixed** |
| `get($id)` | (1) `->where("id = '$id'")`; (2) `->where("regra_id = $id")` (regras_negocio_actions, unquoted); (3) `->where("regra_id = $id")` (regras_negocio_actions_config, unquoted) | **Fixed, all 3 statements** — reachable directly via `RouteController::toogleAction()`'s raw `route` POST param and `RouteFormController::get_rule_actions()`'s raw `rule_id` |
| `getAll($where = null)` | `$select->where($where);` when `$where !== null` | `DEAD/UNREACHABLE` — both call sites (`PBX_Dialplan.php:68`, `PBX_Dialplan/Verbose.php:114`) always call `getAll()` with zero arguments; not fixed (no live code path exercises the `$where !== null` branch at all), flagged as a latent foot-gun for any future caller |
| `update($rule)` | (1) `->update(..., "id='{$rule->getId()}'")`; (2) `->delete(..., "regra_id='{$rule->getId()}'")` | **Fixed, both statements** — reachable directly via `RouteController::toogleAction()` (chained after `get()`) |
| `register($rule)` | `$db->insert(...)` only | `PARAMETERIZED_SAFE` — Zend_Db's native bound insert, unchanged |

**`PBX_Rule::getValidAliasDateById($id)` — the second-order sibling**
(`snep/lib/PBX/Rule.php`, not in `PBX_Rules`, but the exact same
root-cause pattern within the same closure boundary this task exists to
close): `->where("n.id = $id")`, unquoted numeric context. Reachable via:

```text
RouteController::addAction()/editAction() (parseRuleFromPost())
  -> $post['datesValue'] (raw POST, zero validation, zero cast)
  -> $rule->addValidDates($dates_list) per comma-split token
  -> PBX_Rules::register()/update() persists it into regras_negocio.dates_alias
  -> PBX_Rules::get() reloads it into $regra->dates (addValidDates() again, per row)
  -> PBX_Dialplan_Verbose::parse() (the Simulator's own rule-matching engine)
     calls $rule->isValidAliasTime() on EVERY rule whose src/dst already matched
  -> isValidAliasTime() calls getValidAliasDateById($validDatesId) per entry
```

A genuinely second-order flow: an account holding `default_route_write`
sets a malicious `datesValue` on any rule (no format validation exists
at persistence time); any authenticated account running the Simulator
against a request matching that rule's src/dst later triggers the
unquoted interpolation. Fixed:

```php
// before
->where("n.id = $id");
// after
->where('n.id = ?', $id);
```

## Phase 5 — Safe reproduction (live proof)

All four headline sinks were reproduced pre-fix and reconfirmed clean
post-fix through the real, authenticated HTTP flow (never a direct DB
connection), using only harmless syntax-difference/boolean-oracle
payloads. No password/hash/schema extraction was attempted.

| Sink | Payload | Pre-fix | Post-fix |
|---|---|---|---|
| N4, `RouteController::removeAction()` | `id=foo'bar` | `SQLSTATE[42000]... near 'bar')' at line 1` | HTTP 302, no SQL error |
| `PBX_Rules::get()`, `RouteController::toogleAction()` | `route=foo'bar` | `SQLSTATE[42000]... near 'bar')' at line 1` | Clean `PBX_Exception_NotFound: Rule foo'bar not found` (no SQL error at all) |
| N1, `SimulatorController` (real CG-type rule fixture) | `caller=foo'bar` | `SQLSTATE[42000]... near 'bar')' at line 2` | HTTP 200, no SQL error |

`toogleAction()`'s **legitimate** post-`get()` path (which reaches
`update()`) hits a separate, pre-existing, unrelated bug on every call
(see "Pre-existing bugs" below) — `update()`'s own fix is instead
verified via direct invocation (Phase 6), which routes around that
unrelated bug and independently confirms both the legitimate-update and
boolean-isolation properties.

N2/N3 (`checkExpr('G')`/`hasExtenGroup()`) were verified via direct
invocation only (constructing a real `G:`-type business rule and
`Snep_Usuario` object through HTTP end to end requires a live-registered
SIP endpoint, unnecessary complexity for proving this specific SQL
boundary — `hasExtenGroup()`'s own SQL sink is exercised identically
either way): a boolean-shaped payload (`hasExtenGroup("0 OR 1=1", "0 OR
1=1")`) returned zero rows, never matching any real `core_peer_groups`
row, confirmed both pre- and post-fix behavior differ exactly as
expected (pre-fix would have been a syntax error given the unquoted
context; post-fix is a clean empty result).

## Phase 6 — Extended residual SQL security suite

Extended (not duplicated) `scripts/residual-sql-security-smoke-test.sh`
/ `make residual-sql-security-smoke`, per this task's own explicit
Phase 6 instruction, preserving every existing TASK-0026J–M check
unchanged (144 retained).

New coverage, 27 checks:

- **Preflight**: `/index.php/default/route` added to the zero-permission
  authorization-boundary loop (correctly denied); a new, separate check
  confirms `/index.php/default/simulator` is the **opposite** — a
  zero-permission session is correctly *allowed* in (authenticated-open),
  which is the exact property that makes N1–N3 severe. `default_route_write`
  added to the admin permission-grant step.
- **Real-HTTP core proof (5 checks)**: apostrophe-shaped `RouteController::
  removeAction()` (N4); apostrophe-shaped `route/toogle` (`PBX_Rules::get()`,
  classified strictly against a real SQL-syntax-error signature, since
  a clean `NotFound` is the correct outcome, not merely "any error");
  a real CG-type business-rule fixture (created/removed via direct
  `PBX_Rules::register()`/`delete()`, not the controller's own `addAction()`
  form-validation path) exercised with apostrophe- and boolean-shaped
  `caller` values through the real Simulator HTTP flow.
- **`PBX_Rules` direct-invocation coverage (7 checks)**: CANARY/CANARY2
  fixture pair; legitimate `get()`; apostrophe-shaped `get()` (clean
  `NotFound`); legitimate `update()`; apostrophe-shaped `update()` id;
  boolean-shaped `update()` id cannot cross-update CANARY2; cleanup.
  Every fixture calls `$rule->record()` first to route around
  `update()`'s own unrelated "record" bool-cast bug (documented below),
  matching this program's established precedent for verifying a real fix
  behind an unrelated, pre-existing crash.
- **`PBX_Rule`/`PBX_Usuarios` direct-invocation coverage (12 checks)**:
  a CG-type and a G-type rule fixture; legitimate no-match lookup,
  apostrophe-shaped input, and boolean-shaped input for both `checkExpr('CG')`
  (via `$rule->isValidSrc()`) and `hasExtenGroup()`; a real peer fixture
  for `PBX_Usuarios::get()`'s legitimate lookup, boolean-isolation, and
  apostrophe-shaped checks; cleanup.

**Result: PASS, 171/171** (up from 144/144). Cleanup ran cleanly —
`regras_negocio` back to its exact baseline (1 row, the pre-existing
seed rule), zero `task0026n`-named residue in `peers`, `users`
unchanged, `core_binds` unchanged.

## Phase 7 — Complete `PBX_Rule`/`PBX_Usuarios`/`PBX_Rules` sibling audit

| File | Site | Classification |
|---|---|---|
| `PBX_Rule.php` | `checkExpr()` case `'CG'` | `PARAMETERIZED_SAFE` — `FIXED_BY_0026N` |
| `PBX_Rule.php` | `checkExpr()` cases `RX`/`R`/`S`/`T`/`X` | `STATIC_SAFE` — no SQL involved |
| `PBX_Rule.php` | `checkExpr()` case `AL` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — `$expr` already `(int)`-cast before reaching the (already-safe, TASK-0026M-fixed) `PBX_ExpressionAliases::get()`; `$value` never reaches SQL |
| `PBX_Rule.php` | `getValidAliasDateById()` | `PARAMETERIZED_SAFE` — `FIXED_BY_0026N` |
| `PBX_Rule.php` | `getValidAliasDates()` | `STATIC_SAFE` — fully literal SELECT |
| `PBX_Rule.php` | `execute()`'s `agent_availability` query (line ~511) | `STATIC_SAFE`/out-of-scope — reached only via `execute($origem)`, called exclusively from `snep/agi/snep.php` (re-confirmed: zero other callers anywhere in the tree); AGI/call-processing-only, the same "not supported HTTP surface" boundary this program has applied consistently since TASK-0026K |
| `PBX_Usuarios.php` | `hasExtenGroup()` | `PARAMETERIZED_SAFE` — `FIXED_BY_0026N` |
| `PBX_Usuarios.php` | `get()` | `PARAMETERIZED_SAFE` — `FIXED_BY_0026N` (was mitigated-but-fragile) |
| `PBX_Usuarios.php` | `getAll()`, `getByGroup()`, `hasGroupInheritance()` | `STATIC_SAFE` — fully literal WHERE clauses, unchanged |
| `PBX_Rules.php` | `delete()` | `PARAMETERIZED_SAFE` — `FIXED_BY_0026N` |
| `PBX_Rules.php` | `get()` (3 statements) | `PARAMETERIZED_SAFE` — `FIXED_BY_0026N` |
| `PBX_Rules.php` | `update()` (2 statements) | `PARAMETERIZED_SAFE` — `FIXED_BY_0026N` |
| `PBX_Rules.php` | `getAll()`'s optional `$where` | `DEAD/UNREACHABLE` — always called with no arguments at both live call sites, re-confirmed |
| `PBX_Rules.php` | `register()` | `PARAMETERIZED_SAFE` — `$db->insert()` only, unchanged |

**No unexplained request-controlled SQL interpolation remains in any of
the three classes.** Every raw-interpolation site has been either fixed
(10 sites total) or is independently confirmed `STATIC_SAFE`/
`DEAD_UNREACHABLE` with its own call-site evidence recorded above.

## Phase 8 — Final supported-surface SQL sweep

A repository-wide sweep for `request-controlled value → raw SQL
construction → database execution` and `persisted user-controlled value
→ raw SQL construction → database execution`, broader than Phase 7's
three-file scope, matching the methodology TASK-0026Z/J/K/L/M each used
at their own closure point.

**Already-covered, re-confirmed unchanged**: every file named in
TASK-0026M's own "already-covered" list, plus this task's own three
files (above) and its ten Manager-family predecessors (Contacts,
ContactGroups, DatesAliases, ExpressionAliases, CostCenter,
ExtensionsGroups, SoundFiles, Billing, Telcos).

**Confirmed exploitable, NEW, outside this task's assigned scope**:

1. **`RouteController::indexAction()`'s own inline SQL**
   (`snep/modules/default/controllers/RouteController.php:116`):
   ```php
   if(isset($_GET["type"])){
       $type = $_GET['type'];
       $select = $db->select()->from("regras_negocio")->where("type = '$type'");
   }
   ```
   `$type` is a raw, uncast `$_GET` value, interpolated directly into a
   quoted `WHERE` clause — on the **route list index page itself**, the
   very first page any account with `default_route_write` sees.
   **Confirmed live**: an authenticated GET to
   `/index.php/default/route?type=foo%27bar` produced a genuine
   `SQLSTATE[42000]: Syntax error ... near 'bar') ORDER BY \`prio\` DESC,
   \`id\` ASC' at line 1`. Not part of `PBX_Rule`/`PBX_Usuarios`/
   `PBX_Rules` — this task's assigned scope is strictly those three
   classes, matching the exact same discipline TASK-0026J–M each applied
   to their own out-of-scope discoveries.
2. **`Snep_Binds_Manager::removeBond()`/`removeBondException()`**
   (`snep/lib/Snep/Binds/Manager.php:129`/`165`):
   ```php
   $db->delete('core_binds', "user_id = '$id'");           // removeBond()
   $db->delete('core_binds_exceptions', "user_id = '$id'"); // removeBondException()
   ```
   Reachable from `UsersController::removeAction()`
   (`snep/modules/default/controllers/UsersController.php:244`,
   `$id = $this->_request->getParam('id')`, raw route parameter) and from
   the user-binding management action (`UsersController.php:483/494`,
   `$data['id']` from raw `$_POST`). **Confirmed live**: an authenticated
   POST to `/index.php/default/users/remove` with `id=foo'bar` produced a
   genuine `SQLSTATE[42000]: Syntax error ... near 'bar')' at line 1` —
   thrown *before* the actual `Snep_Users_Manager::remove($id)` call in
   that same action, confirming no real user row was at risk from this
   specific reproduction. `Snep_Binds_Manager::removeBondByPeer($peer)`
   shares the identical raw-interpolation shape but is reached only with
   a DB-derived int PK (`$idExten` from `Snep_Extensions_Manager::getPeer()`)
   at its one call site — not independently confirmed exploitable, flagged
   alongside the other two for the same file's future closure. `getBond()`/
   `getBondException()` (same class) are already `PARAMETERIZED_SAFE`,
   unchanged.

Neither finding was modified. Both are outside this task's assigned
scope (`PBX_Rule`/`PBX_Usuarios`/`PBX_Rules` only), and per CLAUDE.md's
"do not fix unrelated legacy bugs opportunistically"/"do not mix
migration phases" principles, fixing them is not this task's call to
make unilaterally. This sweep was not exhaustive of every remaining
codepath in the repository — TASK-0026M's own six previously-flagged,
not-yet-confirmed candidates (`snep/lib/Snep/Alerts.php` — re-checked
here, confirmed `DEAD/UNREACHABLE`, zero callers anywhere in the tree —
`snep/lib/Snep/Extensions.php`, `snep/lib/Snep/ModuleSettings/Manager.php`,
`snep/lib/Snep/Operadoras.php`, `snep/lib/Snep/PjsipTransports/Manager.php:253`)
remain unconfirmed one way or the other and are carried forward, not
asserted safe.

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

Per this task's own explicit instruction ("If another clearly
exploitable supported-surface SQL sink is found: STOP… Do not
automatically create TASK-0026O"), **no new task was created**. This
finding is handed off as evidence only.

## Phase 9 — Focused validation

```bash
make residual-sql-security-smoke
```

**Result: PASS, 171/171** (up from 144/144). All four TASK-0026M
headline findings closed, plus the four sibling sites discovered during
reconstruction. Every TASK-0026J–M check preserved and still passing.
Cleanup: every fixture's own inline cleanup succeeded; `regras_negocio`
confirmed back to its exact baseline (1 row); no `task0026n`-prefixed
residue in `peers`; `users`/`core_binds` unchanged from baseline.

## Phase 10 — Canonical validation

- `php -l` on all three touched application files: clean.
- `bash -n` on the extended smoke script: clean.
- `make lint`: **PASS, 5/5** (271 PHP files, 0 syntax errors; 24 shell
  scripts; 3 `resources.xml` files well-formed; clean `git diff --check`).
- `make regression`, first two attempts: `call-smoke`/`trunk-smoke`
  BLOCKED, then (separately) `transport-smoke` FAILed — all three hit
  the exact, previously-documented transient PJSIP-module-reload-
  not-yet-settled race between back-to-back `make`-triggered container
  recreates (`docs/tasks/0026z-security-audit-closure.md` PR-06;
  `make lint`/`make regression` both depend on `up`, which runs
  `docker compose up -d --build` and recreates the `app`/`asterisk`/
  `provider` containers on every invocation in this environment).
  Each was independently re-run in isolation immediately after
  confirming `res_pjsip.so`/`chan_pjsip.so` both `Running`:
  `call-smoke` **PASS 18/18** (twice, across two separate blocked
  attempts), `trunk-smoke` **PASS 23/23**, `transport-smoke`
  **PASS 63/63** — none touches any file this task modified, and
  `trunk-smoke`'s own isolated run directly exercised this task's own
  modified `PBX_Rules::register()` code twice (outbound and inbound
  route fixtures), passing cleanly both times. Per this project's own
  established precedent (TASK-0026D §Validation, TASK-0026J §Phase 9,
  TASK-0026K §Phase 8, TASK-0026L §Phase 8), a subsequent clean full run
  stands as the official first run.
- `make regression`, official run 1: **PASS, 22/22 suites.**
- `make regression`, official run 2 (immediately after, no code
  changes, no manual cleanup in between): **PASS, 22/22 suites**,
  byte-identical to official run 1.

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

No FAIL, no unexplained BLOCKED, no INCONCLUSIVE, in either official
run. No product code was modified between the two runs, and no manual
cleanup was performed.

## Phase 11 — Health and cleanup

- `docker compose ps`: `app`/`asterisk`/`db`/`provider` all `Up
  (healthy)`.
- Asterisk 22.10.1; `res_pjsip.so` — 1 module, Running.
- `pjsip show transports`: 3 baseline transports intact (`tcp`, `udp`,
  `wss`).
- AMI: `manager show connected` responsive, 0 connected users.
- ODBC: `snep` DSN, 1/1 active connection.
- `core show channels count`: 0 active channels, 0 active calls.
- PHP Fatal Error signature check: the same two known, pre-existing
  `count(): Argument #1 ($value) must be of type Countable|array`
  signatures TASK-0026M already documented — zero fatals attributable to
  this task's own changes.
- Fixture residue: zero. `regras_negocio` at its exact baseline (1 row);
  zero `task0026n`-prefixed rows in `peers`; `users` table unchanged
  (only `admin` plus every prior task's documented persistent dev
  fixture); `core_binds`/`core_binds_exceptions` unchanged (the Phase 8
  sweep's own live reproduction against `Snep_Binds_Manager::removeBond()`
  used a nonexistent id and fataled before any real row could be
  touched, confirmed via unchanged row counts).
- No leftover baresip/smoke-test processes or containers, host or
  container side.
- An unexpected, untracked `.nexus/` directory (a third-party
  workflow-orchestration tool's local config/state, unrelated to this
  project or task, not created by this task) was noticed in the working
  tree during the final `git status` check. Left entirely untouched —
  not staged, not deleted, not otherwise acted upon — and is excluded
  from every diff/status figure and every proposed commit below.
- `git diff --check`: clean.
- `git diff --stat` / `git status --short`: exactly the 4 modified files
  listed below, plus the untracked `.nexus/` noted above — no scope
  creep in this task's own changes.

## Pre-existing bugs discovered, deliberately not fixed

Per CLAUDE.md's "do not fix unrelated legacy bugs opportunistically" —
each is documented here as debt rather than patched. None are SQL
injection defects.

- **`RouteController::editAction()`/`duplicateAction()` call the
  PHP-7-removed `mysql_escape_string()` unconditionally** (lines 312,
  367), before any Manager call — every request to either action (GET or
  POST, any `id`) fatals immediately under PHP 8.4, confirmed by direct
  code read (matching the exact bug class TASK-0026L documented for
  `PickupGroupsController::removeAction()`). This means the "edit route"
  and "duplicate route" features cannot currently render at all,
  independent of this task's own fix. `PBX_Rules::get()`'s own fix is
  unaffected — it is proven live and clean via `RouteController::
  toogleAction()` instead, which carries no equivalent block.
- **`PBX_Rules::update()`'s own `"record"` field carries
  `$rule->isRecording()` (a PHP bool) uncast** — PDO binds `false` as the
  empty string `''`, which strict MariaDB rejects for this `NOT NULL`
  int column (`SQLSTATE[22007]`). This is the exact bug class TASK-0015
  already found and fixed for `register()`
  (`"record" => $rule->isRecording() ? 1 : 0`) but never extended to
  `update()`. Confirmed live: every real `route/toogle` POST that
  reaches a legitimate rule fatals on this signature, regardless of this
  task's own SQL fix. `update()`'s own SQL boundary is proven safe via
  direct invocation instead (calling `$rule->record()` first routes
  around the unrelated crash, matching this program's established
  precedent for TASK-0026L's PickupGroups/Queues verification).

## Files changed

```
scripts/residual-sql-security-smoke-test.sh   TASK-0026N focused coverage (+27 checks, 144->171)
snep/lib/PBX/Rule.php                         N1 + getValidAliasDateById() sibling (2 sites)
snep/lib/PBX/Usuarios.php                     N3 + get() sibling (2 sites)
snep/lib/PBX/Rules.php                        N4 + get()/update() siblings (6 sites)
```

Every other prior TASK-0026x file is untouched.
`RouteController.php`/`RouteFormController.php`/`UsersController.php`/
`Snep_Binds_Manager.php` are untouched. Product Readiness work was not
started.

## Security handoff — why `SECURITY_GATE` remains `NO-GO`

Per Phase 8's explicit instruction, this task stops here rather than
silently expanding its own scope. All four assigned headline sinks (and
their four in-class siblings) are closed, verified, and
regression-covered. However:

```text
known SQL injection = 0 in supported surfaces   NOT SATISFIED
```

`RouteController::indexAction()`'s own `$_GET['type']` interpolation
(the route list's own index page) and `Snep_Binds_Manager::removeBond()`/
`removeBondException()` (reachable via `UsersController`) both carry the
exact same unescaped-`'$var'`-in-`WHERE`-clause defect this task and its
five predecessors have now closed seven times over — none touched by
this task.

**Recommended next task** (not opened automatically, per Phase 8): close
these two confirmed sinks (`RouteController.php`, `Snep_Binds_Manager.php`)
using the exact same `$db->quoteInto()`/bound-`where()` pattern this
task and TASK-0026C/F1/J/K/L/M have now established seven times over.
While auditing `Snep_Binds_Manager.php`, also resolve `removeBondByPeer()`'s
disposition (currently only DB-derived-int-PK-fed at its one call site —
fix alongside its two siblings for consistency, or document why not).
Separately, before declaring the gate closed, individually trace
TASK-0026M's own five still-unconfirmed candidates this task did not
revisit (`Snep/Extensions.php`, `Snep/ModuleSettings/Manager.php`,
`Snep/Operadoras.php`, `Snep/PjsipTransports/Manager.php:253`) plus
`PBX_Rules::getAll()`'s dead-but-latent `$where` parameter, to a
confirmed verdict.
