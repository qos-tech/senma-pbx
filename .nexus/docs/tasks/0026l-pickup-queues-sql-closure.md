# TASK-0026L — Pickup Groups and Queues SQL boundary closure

## Status

Implementation complete and validated for the two assigned blockers, plus
14 sibling sites sharing the exact same root-cause pattern in the same
two Manager files. Focused smoke suite (50/50), `make lint`, and two
consecutive full `make regression` runs (22/22 suites each) all PASS.
Not committed — this is the validated TASK-0026L checkpoint, awaiting
explicit authorization to commit.

**This task's own Phase 7 final supported-surface SQL sweep found
numerous additional, unremediated, confirmed-exploitable instances of the
same root-cause SQL-injection class outside this task's assigned scope
(`Snep_PickupGroups_Manager`/`Snep_Queues_Manager` only) — spanning at
least the `Contacts`, `ContactGroups`, `CostCenter`, `DatesAliases`,
`ExpressionAliases`, `ExtensionsGroups`, `SoundFiles` Managers and the
entire `billing` module (`Billing`/`Telcos` Managers). Per this task's
own governing instructions, no code was changed to fix them — they are
documented here and handed off as evidence for a required follow-up
task, not auto-created.**

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

## Scope

Closes exactly the two SQL-injection findings TASK-0026K's own Phase 9
final static closure sweep discovered but explicitly left unfixed
(`docs/tasks/0026k-report-controller-sql-closure.md`, "Security
handoff"):

- **BLOCKER E** — `Snep_PickupGroups_Manager::get($id)`'s raw
  interpolation — reachable via `PickupGroupsController::editAction()`.
- **BLOCKER F** — `Snep_Queues_Manager::getValidation($id)`'s raw
  interpolation — reachable via `QueuesController::removeAction()`.

Per this task's own explicit Phase 2/3/6 instructions ("audit sibling
methods... for the exact same root-cause pattern"; "there must be no
unexplained request-controlled SQL concatenation in these boundaries"),
this task also fixes every sibling method in
`Snep_PickupGroups_Manager`/`Snep_Queues_Manager` sharing the identical
raw-interpolation pattern — 14 additional sites, all reachable from the
same two controllers. This matches the precedent already established by
TASK-0026C (which fixed 5 sibling methods for F7, 12 for F8, 4 for F9)
and TASK-0026J (BLOCKER A's own sibling audit).

Does not touch: Pickup Groups/Queues redesign, telephony behavior,
PJSIP-only work, UI/menu/translations, or any Product Readiness bug
unrelated to these boundaries — all explicitly out of scope per this
task's own instructions.

## Phase 1 — Blocker reconstruction

### BLOCKER E — `Snep_PickupGroups_Manager::get($id)`

- **Entry points**: `PickupGroupsController::editAction()` (line 137,
  `$id = $this->_request->getParam('id')`, a raw route parameter, no
  cast, no validation) and `removeAction()` (line 237/242,
  `$_POST['id']` directly).
- **Pre-fix SQL** (line 67): `->where("cod_grupo = '$id'")` — raw string
  interpolation inside `Zend_Db_Select::where()`.
- **Required authorization**: `default_pickup-groups_write` (the only
  permission level this resource exposes per `resources.xml`'s nested
  `<resource id="write">`).
- **Exploitability — confirmed live**: an authenticated GET to
  `/index.php/default/pickup-groups/edit/id/foo%27bar` (a lone,
  deliberately unbalanced apostrophe, harmless syntax-difference probe,
  no data extraction attempted) produced a genuine
  `SQLSTATE[42000]: Syntax error ... near 'bar')' at line 1` against the
  live dev stack, reproduced before any code change.
- **Reachability nuance discovered during this task's own live
  reconstruction**: `removeAction()` calls
  `mysql_escape_string($this->getRequest()->getParam('id'))`
  unconditionally at its very first line (216) — a function removed
  entirely from PHP since 7.0. This fatals (`Error: Call to undefined
  function mysql_escape_string()`) on **every** request to this action,
  GET or POST, any `id`, confirmed live. `get()`/`delete()`/
  `getValidation()` inside `removeAction()` are therefore currently
  **unreachable via HTTP** in this environment — the task's original
  claim that `get()` is "reachable through removeAction()" does not hold
  against current runtime behavior, though it held historically before
  this pre-existing bug was traced this precisely. Per CLAUDE.md
  ("evidence from the repository and runtime behavior takes precedence
  over assumptions... correct documentation when later evidence disproves
  an earlier assumption"), this is documented here rather than silently
  repeated. `editAction()`'s GET-render path (which does reach `get()`,
  unconditionally, before any POST-only logic) remains fully live and is
  the confirmed, currently-exploitable path — this is what was fixed and
  what the live A/B proof above exercises. This pre-existing,
  category-A PHP 8.4 compatibility bug is **not fixed** by this task
  (see "Pre-existing bugs discovered, not fixed" below) — the vulnerable
  Manager methods reachable only through it (`delete()`, `getValidation()`)
  are still fixed here regardless, matching TASK-0026C's own F10
  precedent of fixing real vulnerable code even when a separate,
  unrelated bug currently blocks its only HTTP path.

### BLOCKER F — `Snep_Queues_Manager::getValidation($id)`

- **Entry point**: `QueuesController::removeAction()` (line 313),
  `$id = $this->_request->getParam('id')` — a raw, unvalidated route
  parameter (SNEP's own field convention throughout this controller: the
  `id` route/POST field carries the queue's **name**, not its numeric
  database id — every Manager method it feeds keys on `name`; confirmed
  live and preserved exactly as-is, not a bug this task fixes).
- **Pre-fix SQL** (line 358): raw string concatenation, `rconf.value =
  '$id'`, inside a hand-built `SELECT` passed to `$db->query()`.
- **Required authorization**: `default_queues_write`.
- **Exploitability — confirmed live**: an authenticated GET to
  `/index.php/default/queues/remove/id/foo%27bar` produced a genuine
  `SQLSTATE[42000]: Syntax error ... near 'bar' AND (rconf.key =
  'queue'))' at line 1` against the live dev stack, reproduced before any
  code change. Unlike `PickupGroupsController::removeAction()`,
  `QueuesController::removeAction()`'s render path carries no equivalent
  blocking bug — it is fully reachable via real HTTP GET/POST, as
  originally claimed.

## Phase 2/3 — Remediation (mechanical, minimal-diff)

Every fix uses the exact `$db->quoteInto('col = ?', $val)` /
`->where('col = ?', $val)` / `$db->quote($val)` pattern already
established four times over by TASK-0026C/F1/J/K — no new pattern, no
behavior change for any legitimate (non-injecting) input. `where('cod_grupo
= ?', $id)` and the old unquoted `where("cod_grupo = '$id'")` produce
byte-identical query results for any value that was never exploiting the
missing quoting in the first place.

### `snep/lib/Snep/PickupGroups/Manager.php` — 8 sites fixed

| Method | Before | After | Reachability |
|---|---|---|---|
| `delete($id)` | `"cod_grupo='{$id}'"` | `$db->quoteInto('cod_grupo = ?', $id)` | `removeAction()` (currently HTTP-unreachable, see Phase 1) |
| `get($id)` | `"cod_grupo = '$id'"` | `'cod_grupo = ?', $id` | **BLOCKER E** — `editAction()` (live), `removeAction()` (currently HTTP-unreachable) |
| `getFilter($field, $query)` | `"$field like '%$query%'"` | `"$field like ?", "%$query%"` | DEAD/UNREACHABLE — zero call sites anywhere in the tree (re-confirmed); fixed for consistency per TASK-0026K's own handoff note recommending this, matching TASK-0026C's F10 precedent of fixing real vulnerable dead code |
| `getValidation($id)` | raw `'$id'` in hand-built SQL string | `$db->quote($id)` concatenation | `removeAction()` (currently HTTP-unreachable) |
| `edit($pickupGroup)` | `'cod_grupo =' . $pickupGroup['id']` (no quotes at all) | `$db->quoteInto('cod_grupo = ?', ...)` | DEAD/UNREACHABLE — zero call sites (byte-identical twin of `editGroup()`, which the controller actually calls); fixed for consistency |
| `addExtensionsGroup($extensionsGroup)` | `"name = " . $extensionsGroup['extensions']` (no quotes) | `$db->quoteInto('name = ?', ...)` | `addAction()`/`editAction()` POST, via the `duallistbox_group[]` array values |
| `getGroup($id)` | `"cod_grupo = '$id'"` | `'cod_grupo = ?', $id` | DEAD/UNREACHABLE — zero call sites (byte-identical twin of `get()`); fixed for consistency |
| `editGroup($pickupGroup)` | `'cod_grupo =' . $pickupGroup['id']` (no quotes) | `$db->quoteInto('cod_grupo = ?', ...)` | `editAction()` POST, raw route `id` |

### `snep/lib/Snep/Queues/Manager.php` — 8 sites fixed

| Method | Before | After | Reachability |
|---|---|---|---|
| `edit($queue)` | `"name = '{$queue['name']}'"` | `$db->quoteInto('name = ?', ...)` | **Second-order** — `editAction()` POST; `$queue['name']` is mass-assignable at `add()` time with zero server-side sanitization, the exact same second-order pattern TASK-0026J's BLOCKER A closed for trunk names |
| `remove($name)` | `"name = '$name'"` | `$db->quoteInto('name = ?', ...)` | `removeAction()` POST, `$_POST['id']` (the "id" field carries the queue name, see Phase 1) |
| `removeQueues($name)` | `"queue = '$name'"` | `$db->quoteInto('queue = ?', ...)` | `removeAction()` POST |
| `removeUserPermission($id)` | `"...queue_id = $id"` (no quotes at all — unquoted numeric context, the most severe variant) | `$db->quoteInto('...queue_id = ?', ...)` | `removeAction()` POST, `$_POST['name']` |
| `removeQueuePeers($queue)` | `"...fila = '$queue'"` | `$db->quoteInto('...fila = ?', ...)` | `removeAction()` POST |
| `removeAllMembers($queue)` | `"queue_name = '$queue'"` | `$db->quoteInto('queue_name = ?', ...)` | `membersAction()` POST, raw route `id` |
| `removeMember($member)` | `"membername = '$member'"` | `$db->quoteInto('membername = ?', ...)` | DEAD/UNREACHABLE — zero call sites anywhere in the tree (re-confirmed); fixed for consistency (byte-identical twin of `removeAllMembers()`) |
| `getValidation($id)` | raw `'$id'` in hand-built SQL string | `$db->quote($id)` concatenation | **BLOCKER F** — `removeAction()` (live) |

## Phase 4 — Safe reproduction

For both named blockers, the same apostrophe-shaped and boolean-shaped
payloads were run against the live dev stack before and after the fix,
through the real, authenticated HTTP flow (never a direct DB connection),
using only harmless, non-destructive syntax-difference/boolean-oracle
probes. No password/hash/schema extraction was attempted at any point.

| Payload | Pre-fix | Post-fix |
|---|---|---|
| PickupGroups, `editAction` id=`foo'bar` | `SQLSTATE[42000]... near 'bar')' at line 1` | HTTP 200, no SQL error, treated as a nonexistent group |
| Queues, `removeAction` id=`foo'bar` | `SQLSTATE[42000]... near 'bar' AND (rconf.key = 'queue'))' at line 1` | HTTP 200, no SQL error, treated as a nonexistent queue |

For the sibling methods, a CANARY/MALICIOUS fixture pair was used per
boundary (created directly via `Snep_PickupGroups_Manager::addGroup()`/
`Snep_Queues_Manager::add()` — see "Pre-existing bugs" below for why the
real `addAction()` HTTP flow could not be used) and a boolean-shaped
payload matching TASK-0026J BLOCKER A's own proven shape
(`"0 OR cod_grupo=<CANARY_ID>"` — a leading `0` collapses to numeric `0`
under MariaDB's implicit string→int coercion once bound as literal data,
matching no real row) was submitted against `editGroup()`. Post-fix,
CANARY's own row is provably untouched and its name never leaks into the
malicious lookup's response. Full detail for every sibling method is in
the focused suite (Phase 5) and was independently confirmed live during
this task's own development (both via the real HTTP flow where reachable,
and via direct `Snep_PickupGroups_Manager`/`Snep_Queues_Manager` method
invocation where the only HTTP path is currently blocked by an unrelated,
pre-existing bug — see below).

## Phase 5 — Focused security suite

Extended (not duplicated) `scripts/residual-sql-security-smoke-test.sh` /
`make residual-sql-security-smoke`, per this task's own explicit Phase 5
instruction, preserving every existing TASK-0026J/K check (BLOCKER A–D)
unchanged.

New coverage, 22 checks:

- **Preflight**: `/index.php/default/pickup-groups` and
  `/index.php/default/queues` added to the zero-permission
  authorization-boundary loop; `default_pickup-groups_write`/
  `default_queues_write` added to the admin permission-grant step.
- **BLOCKER E (8 checks)**: legitimate lookup (the pre-existing `GERAL`
  seed group renders correctly via `editAction()`); apostrophe-shaped id
  causes no SQL error; a CANARY/MALICIOUS fixture pair is created; a
  boolean-shaped id cannot cross-leak CANARY's own name; `getValidation()`
  (legitimate, apostrophe-shaped, boolean-shaped), `editGroup()`
  (boolean-shaped cannot alter CANARY; legitimate rename works),
  `addExtensionsGroup()` (SQL-shaped value causes no exception),
  `getFilter()` (apostrophe-shaped query causes no exception), and
  `delete()` (apostrophe-shaped id causes no exception, CANARY untouched)
  are all verified via direct Manager invocation (see below); a health
  check confirms zero new PHP Fatal Errors attributable to this section.
- **BLOCKER F (8 checks)**: a CANARY/CANARY2/MALICIOUS fixture triple is
  created; a legitimate `removeAction()` lookup reaches the DB layer
  cleanly; an apostrophe-shaped id causes no SQL error; a boolean/
  apostrophe-shaped POST cannot delete CANARY2 (`remove()`/
  `removeQueues()`/`removeUserPermission()`/`removeQueuePeers()` all
  exercised in one request); a legitimate remove of CANARY actually
  works end to end; `edit()`'s second-order boundary (MALICIOUS's own
  mass-assignable, apostrophe-bearing name) applies a legitimate update
  cleanly; `membersAction()`'s `removeAllMembers()` boundary (SQL-shaped
  route id) causes no crash; a health check confirms zero new PHP Fatal
  Errors attributable to this section.

**Verification-path note**: where the real controller action is
reachable via HTTP, the suite drives it exactly like every prior
BLOCKER A–D check (real authenticated request, real session, real CSRF
token). Where it is not (see "Pre-existing bugs" below), the suite
invokes the now-fixed Manager method directly inside the app container,
through a small CLI bootstrap that replicates `snep/index.php`'s registry
setup (`Snep_Config`, `Zend_Application`, `Zend_Registry`
`config`/`db`) without dispatching a controller — the same real PHP code
path, same `Zend_Db` adapter, just without the broken HTTP entry point in
front of it. This mirrors TASK-0026C's own established precedent for
`ProfilesController::addAction()` (F8): "routes around [a pre-existing,
unrelated PHP 8.4 bug] by creating its fixture profile directly via
`Snep_Profiles_Manager::add()` and exercising the real vulnerable sink
through `editAction()` instead."

**Result: PASS, 50/50** (up from 27/27). Cleanup ran cleanly — all
fixtures removed via direct Manager calls (matching how they were
created), zero residue.

## Phase 6 — Complete Manager/controller sibling audit

| File | Site | Classification |
|---|---|---|
| `Snep_PickupGroups_Manager.php` | `delete()`, `get()`, `getFilter()`, `getValidation()`, `edit()`, `addExtensionsGroup()`, `getGroup()`, `editGroup()` | `PARAMETERIZED_SAFE` — fixed by this task (8 sites) |
| `Snep_PickupGroups_Manager.php` | `getAll()`, `getAllMembers()` (its inner `where("pickupgroup = ?", ...)`), `add()`, `addGroup()`, `getExtensionsAll()`, `getExtensionsOnlyGroup()`, `getName()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — already safe, unchanged |
| `Snep_Queues_Manager.php` | `edit()`, `remove()`, `removeQueues()`, `removeUserPermission()`, `removeQueuePeers()`, `removeAllMembers()`, `removeMember()`, `getValidation()` | `PARAMETERIZED_SAFE` — fixed by this task (8 sites) |
| `Snep_Queues_Manager.php` | `get()`, `getQueueAll()`, `add()`, `getMembers()`, `getAllMembers()`, `insertMember()`, `getValidationPeers()`, `getValidationAgent()`, `insertLogQueue()`, `getCsv()`, `getName()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — already safe, unchanged |
| `PickupGroupsController.php` | (no direct `$db`/SQL calls — all persistence routed through the Manager) | N/A |
| `QueuesController.php` | `indexAction()`'s `$select` (line 73) | `STATIC_SAFE` — fully literal SQL, no request-controlled interpolation |

**No unexplained request-controlled SQL concatenation remains in either
Manager or either controller.** Every raw-interpolation site has been
either fixed (16 sites total) or is independently confirmed
`STATIC_SAFE`/`DEAD_UNREACHABLE` with its own call-site grep evidence
recorded above.

## Phase 7 — Final supported-surface SQL sweep

A repository-wide sweep for `request-controlled value → raw SQL
concatenation → database execution`, broader than Phase 6's two-file
scope, matching the methodology TASK-0026Z/J/K each used at their own
closure point. Every file touching `$db->query(`/`->where(`/`->update(`/
`->delete(`/`->insert(` with an adjacent, non-parameterized interpolation
pattern was enumerated and traced across the full repository (~2,838 PHP
files scanned; ~260 `$db->query()` and ~140
`$db->update()`/`delete()`/`insert()` call sites individually traced back
to their controller), not just the two files this task's own scope
names.

**Already-covered, re-confirmed unchanged**: `ExtensionsController.php`/
`Snep/Extensions/Manager.php` (F7), `TrunksController.php`/
`Snep/Trunks/Manager.php` (F9), `Snep_InterfaceConf.php` (TASK-0026J
BLOCKER A), `{Calls,Ranking,Services}ReportController.php` (TASK-0026J/K),
`Snep/CsvIE.php` (F10), `ExportDataController.php` (F11),
`Snep/Users/Manager.php`/`Snep/Profiles/Manager.php` (F8),
`PjsipTrunkConf.php`/`PjsipConf.php`/`PjsipTransportConf.php`
(TASK-0026E), all five standalone API report/CSV/contacts services
(TASK-0026F1), and `Snep_PickupGroups_Manager.php`/`Snep_Queues_Manager.php`
(this task, above) — no site in any of these reclassified.

**Confirmed `STATIC_SAFE`/out-of-scope**: `Snep_Dashboard_Manager::get()`/
`set()` (interpolates `$_SESSION['id_user']`, but that session value is
always an integer PK set post-auth via an already-parameterized query in
`AuthController.php`, never attacker-supplied text — same trust boundary
this program has consistently applied to session-derived values);
`Snep_PjsipTransports_Manager::update()`/`remove()` (`$id = (int)$id` cast
before interpolation); `ParametersController.php`'s `language` field
(allowlist-validated via `Snep_Locale::isSupportedLanguage()` before
reaching SQL); `Billing_Manager::rate()`'s `trunks WHERE id='{$telco_id}'`
(only reachable from `snep/agi/snep.php`, the AGI/call-processing
pipeline — same "not supported HTTP surface" classification TASK-0026K's
own Phase 9 already applied to `PortabilityAction.php` and its siblings).

**Confirmed exploitable, NEW, outside this task's assigned scope**: this
sweep found the *exact same* root-cause pattern this task just closed in
`Snep_PickupGroups_Manager`/`Snep_Queues_Manager` — an unescaped
`'$var'`/`$var` value inside an `Zend_Db_Adapter_Abstract::update()`/
`delete()` third-argument WHERE string, driven by a raw, uncast,
unvalidated `$_POST`/route parameter — repeated across at least eleven
further controller/Manager pairs, none previously in scope for any
TASK-0026x task:

| Controller (action) | Request param | Sink |
|---|---|---|
| `ContactsController::removeAction()` | `$_POST['id']` | `Snep_Contacts_Manager::remove()` (`snep/lib/Snep/Contacts/Manager.php:207`): `$db->delete('contacts_names', "id = '$id'")` |
| `ContactsController::editAction()` | `getParams()['id']` | `Snep_Contacts_Manager::edit()` (`Contacts/Manager.php:269`): `$db->update("contacts_names", $data, "id = '{$contact['id']}'")` |
| `ContactGroupsController::removeAction()` | `$_POST['id']` | `Snep_ContactGroups_Manager` (`snep/lib/Snep/ContactGroups/Manager.php:101` delete, `:119` update) |
| `DatesAliasController::removeAction()` | `$_POST['id']` | `PBX_DatesAliases` (`snep/lib/PBX/DatesAliases.php:177` delete, `:153` update) |
| `ExpressionAliasController::removeAction()` | `$_POST['id']` | `Snep_ExpressionAliases_Manager` (`snep/lib/Snep/ExpressionAliases/Manager.php:50`): `$db->delete("expr_alias", "aliasid='$id'")` |
| `CostCenterController` (edit/remove) | `$_POST['id']`/`getParams()` | `Snep_CostCenter_Manager` (`snep/lib/Snep/CostCenter/Manager.php:106` delete, `:128` update) |
| `ExtensionsGroupsController::removeAction()` | `$_POST['id']` | `Snep_ExtensionsGroups_Manager::remove()` (`snep/lib/Snep/ExtensionsGroups/Manager.php:378`): `$db->delete("core_groups", "id= ".$id)` — not even quoted |
| `SoundFilesController` (edit/remove) | `$_POST['id']` | `Snep_SoundFiles_Manager` (`snep/lib/Snep/SoundFiles/Manager.php:128` remove, `:113` edit) |
| `snep/modules/billing/controllers/BillingController.php` (edit/remove) | `$_POST['id']` | `Billing_Manager` (`snep/modules/billing/lib/Billing/Manager.php:167` delete, `:192` update) |
| `snep/modules/billing/controllers/TelcosController.php` (edit/remove) | `$_POST['id']` | `Telcos_Manager` (`snep/modules/billing/lib/Telcos/Manager.php:95` delete, `:121` update) |

All confirmed via `Zend_Db_Adapter_Abstract::update()`/`delete()` (`snep/
lib/Zend/Db/Adapter/Abstract.php`), which passes a plain-string third
argument straight into `WHERE $where` with zero escaping. The `billing`
module is a routable, `resources.xml`-registered permission
(`billing_billing_write`, `billing_telcos_write`) — not dead code, not
AGI-only. Two entries (`ContactsController`, `ExtensionsGroupsController`)
were independently re-confirmed by direct source read during this task's
own closure, not taken on the sweep's word alone.

**This is "another clearly exploitable supported-surface SQL injection"
found during the mandated sweep, per this task's own Phase 7 framing.**
Per that phase's explicit instruction:

```text
STOP.
Report: RESIDUAL_SQL_GATE = NOT CLOSED, SECURITY_GATE = NO-GO.
Do not automatically create TASK-0026M.
```

None of the eleven sinks above were modified. All are outside this task's
assigned scope (limited to `Snep_PickupGroups_Manager`/
`Snep_Queues_Manager`), and per CLAUDE.md's "do not fix unrelated legacy
bugs opportunistically" / "do not mix migration phases" principles,
fixing them is not this task's call to make unilaterally. They are handed
off as evidence for the next security task, not silently absorbed into
this one's scope.

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

## Phase 8 — Canonical validation

- `php -l` on both touched Manager files: clean.
- `bash -n` on the extended smoke script: clean.
- `make residual-sql-security-smoke`: **PASS, 50/50** (up from 27/27).
- `make lint`: **PASS, 5/5** (271 PHP files, 0 syntax errors; 24 shell
  scripts; 3 `resources.xml` files well-formed; clean `git diff --check`).
- `make regression`, first attempt: 21/22 suites PASS, `trunk-smoke`
  BLOCKED (`res_pjsip.so/chan_pjsip.so not both Running on both
  instances`) — the exact, previously-documented transient
  PJSIP-module-reload-not-yet-settled race between back-to-back
  regression suites (`docs/tasks/0026z-security-audit-closure.md` PR-06,
  mitigated but not eliminated at the harness level). Confirmed
  unrelated to this task's own changes: neither
  `Snep_PickupGroups_Manager.php` nor `Snep_Queues_Manager.php` touches
  PJSIP/trunk config generation at all. Independently re-run in
  isolation immediately after: **PASS, 23/23**, confirming the transient
  nature. Per this project's own established precedent (TASK-0026D
  §Validation, TASK-0026J §Phase 9, TASK-0026K §Phase 8), a subsequent
  clean full run stands as the official first run.
- `make regression`, official run 1: **PASS, 22/22 suites.**
- `make regression`, official run 2 (immediately after, no code changes,
  no manual cleanup in between): **PASS, 22/22 suites**, byte-identical
  to official run 1.

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

No FAIL, no unexplained BLOCKED, no INCONCLUSIVE, in either official run.
No product code was modified between the two runs, and no manual cleanup
was performed.

## Phase 9 — Health and cleanup

- `docker compose ps`: `app`/`asterisk`/`db`/`provider` all `Up
  (healthy)`.
- Asterisk 22.10.1; `res_pjsip.so` — 1 module, Running.
- `pjsip show transports`: 3 baseline transports intact (`tcp`, `udp`,
  `wss`).
- AMI: `manager show connected` responsive, 0 connected users.
- ODBC: `snep` DSN, 1/1 active connection.
- `core show channels count`: 0 active channels, 0 active calls.
- PHP Fatal Error signature check: exactly two known, pre-existing
  signatures present anywhere in the log —
  `CallsReportController.php:402`'s `count()`/`Countable` PHP 8.4 bug
  (TASK-0026J's own documented Product Readiness item) and
  `Zend/Validate/File/Upload.php:226`'s `count()`/`Countable` PHP 8.4 bug
  (TASK-0026D's own documented PR-03, triggered by `shell-security`'s own
  F5-reachability check) — zero fatals attributable to this task's own
  changes, zero `SQLSTATE`/syntax-error-shaped fatals anywhere in the
  post-validation log.
- Fixture residue: zero (`queues` table empty, `grupos` table contains
  only the pre-existing `GERAL` seed row, `trunks` table empty, zero
  `peer_type='T'` orphans, zero `/tmp/task0026l*` files in the app
  container). `users` contains only `admin` plus every prior task's
  documented persistent dev fixture (`task0026a-restricted` through
  `task0026j-restricted`) — this task reused the existing
  `task0026j-restricted` fixture (same `MARKER`/`RESTRICTED_USER` as the
  script it extends), no new persistent user was needed.
- No leftover baresip/smoke-test processes or containers, host or
  container side.
- `git diff --check`: clean.
- `git diff --stat` / `git status --short`: exactly the 3 modified files
  listed below — no scope creep.

## Pre-existing bugs discovered, deliberately not fixed

Per CLAUDE.md's "do not fix unrelated legacy bugs opportunistically" —
each is documented here as debt rather than patched. None of these are
SQL-injection defects; all are PHP 8.4 compatibility (category A/B per
CLAUDE.md's own taxonomy) or pre-existing functional issues discovered
while reconstructing these two boundaries:

- **`PickupGroupsController::removeAction()` calls the PHP-7-removed
  `mysql_escape_string()`** (line 216) unconditionally, before any
  Manager call. Fatals on every request to this action, GET or POST, any
  `id` — confirmed live (`Error: Call to undefined function
  mysql_escape_string()`). This means the "remove pickup group" feature
  cannot currently render or execute at all under PHP 8.4 in this
  environment, independent of this task's own fix. A one-line
  `Snep_Security_Password`-style removal/replacement (the value can now
  flow straight into the parameterized Manager calls this task just
  fixed, with no escaping needed) would resolve this; left undone per
  this task's own scope boundary. This is the same bug class already
  flagged for `TrunksController.php`/`RouteController.php` by
  TASK-0015A, never extended to this controller.
- **`PickupGroupsController::addAction()`/`editAction()`'s POST branch
  both run `count(Snep_PickupGroups_Manager::getName($name))`**, which is
  a `TypeError` under PHP 8+ whenever `getName()` returns `false` (i.e.
  whenever the submitted name does not already exist as another row) —
  the exact same bug class TASK-0026C already documented for
  `ProfilesController::addAction()` (F8: "`count(): Argument #1 ($value)
  must be of type Countable|array, false given`"), never extended here.
  Confirmed live: submitting any brand-new pickup group name fatals
  immediately. Creating/renaming a pickup group to a genuinely new name
  is currently broken end to end under PHP 8.4; editing without changing
  the name (or renaming to a name that already exists on another row,
  which correctly shows "already exists") both work, since neither path
  hits the `count(false)` branch.
- **`QueuesController::addAction()` has the identical
  `count(Snep_Queues_Manager::getName($name))` bug** — confirmed live,
  same signature. Creating a brand-new queue is currently broken end to
  end under PHP 8.4.
- **SNEP's own field-naming convention throughout `QueuesController`**
  (not a bug, documented for clarity): the route/POST `id` field carries
  the queue's **name** (every Manager method reachable from this
  controller keys its lookup on `name`, never the numeric primary key),
  while the POST `name` field carries the queue's real numeric database
  id (used only by `removeUserPermission()`'s `queue_id` foreign-key
  lookup). Confirmed live via the real remove-confirmation form
  (`remove/remove.phtml`) and preserved exactly as-is throughout this
  task's fix and its test coverage.

None of the four items above are security defects on their own — they
are functional/compatibility gaps that happen to make parts of these two
features currently unusable under PHP 8.4, independent of the SQL
boundaries this task closes. They are Product Readiness debt, not
security-gate-blocking.

## Security handoff — why `SECURITY_GATE remains NO-GO`

Per Phase 7's explicit instruction, this task stops here rather than
silently expanding its own scope. The two originally assigned blockers
(and their 14 in-file siblings) are closed, verified, and
regression-covered. However:

```text
known SQL injection = 0 in supported surfaces   NOT SATISFIED
```

Eleven further sinks across seven Manager classes and two modules
(`Contacts`, `ContactGroups`, `CostCenter`, `DatesAliases`,
`ExpressionAliases`, `ExtensionsGroups`, `SoundFiles`, plus the entire
`billing` module's `Billing`/`Telcos` Managers) carry the exact same
unescaped-`'$id'`/`$id`-in-WHERE-clause defect this task and
TASK-0026C/J/K just closed five times over in different controllers —
all reachable via the same permission-plugin/CSRF authorization model as
every other controller this program has audited, gated by an ordinary
`write` permission grant, none touched by this task.

**Recommended next task** (not opened automatically, per Phase 7): close
these eleven sinks using the exact same `$db->quoteInto()`/`(int)` cast
pattern this task and TASK-0026C/F1/J/K have now established five times
over — expected to be small and mechanical per that track record, though
larger in file count than any single prior TASK-0026x SQL closure (11
sinks across 9 files/2 modules, vs. this task's 2+14 across 2 files).
Given the volume, a dedicated task should also decide whether to extend
`residual-sql-security-smoke-test.sh` again or start a new, separate
focused suite (this task's own governing instructions for a
similarly-sized prior extension said "extend... rather than creating
another one-off SQL suite," but the `billing` module in particular is a
structurally separate module tree — `snep/modules/billing/` — worth an
explicit scope decision rather than silent precedent-following). The
sweep that found these sinks was not exhaustive of every codepath in the
`billing` module beyond `Billing`/`Telcos` — a dedicated task should
re-sweep that module specifically before closing it out.

## Files changed

```
scripts/residual-sql-security-smoke-test.sh   BLOCKER E/F focused coverage (+23 checks, 27->50)
snep/lib/Snep/PickupGroups/Manager.php        BLOCKER E fix + 7 sibling sites
snep/lib/Snep/Queues/Manager.php              BLOCKER F fix + 7 sibling sites
```

`PickupGroupsController.php`, `QueuesController.php`,
`ContactsController.php`, every file in `snep/modules/billing/`, and
every prior TASK-0026x file are untouched. Product Readiness work was
not started.
