# TASK-0026M — Manager-layer residual SQL injection closure

## Status

Implementation complete and validated for all confirmed TASK-0026L
residual sinks, plus every sibling method in the same files/classes
sharing the exact same raw-interpolation root cause (31 sites fixed
across 10 files). Focused smoke suite (144/144), `make lint`, and two
consecutive full `make regression` runs (22/22 suites each) all PASS.
Not committed — this is the validated TASK-0026M checkpoint, awaiting
explicit authorization to commit.

**This task's own Phase 8 final supported-surface SQL sweep found
further, confirmed-exploitable, unremediated instances of the same
root-cause SQL-injection class entirely outside this task's assigned
scope — in `PBX_Rule.php`'s dialplan-rule matching engine (`checkExpr()`,
the `'CG'` and `'G'` cases) and `PBX_Usuarios.php` (`hasExtenGroup()`),
both reachable via `SimulatorController::indexAction()` (open to every
authenticated user, not merely a privileged one), plus
`PBX_Rules::delete()` reachable via `RouteController::removeAction()` (a
core, heavily-used Business Rules feature). Per CLAUDE.md's "do not fix
unrelated legacy bugs opportunistically" and this task's own governing
instructions, no code was changed to fix them — they are documented here
and handed off as evidence for a required follow-up task, not
auto-created.**

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

## Scope

Closes the residual Manager-layer SQL-injection sinks TASK-0026L's own
Phase 7 final sweep discovered but explicitly left unfixed
(`docs/tasks/0026l-pickup-queues-sql-closure.md`, "Security handoff"),
spanning:

- `Snep_Contacts_Manager` (`snep/lib/Snep/Contacts/Manager.php`)
- `Snep_ContactGroups_Manager` (`snep/lib/Snep/ContactGroups/Manager.php`)
- `PBX_DatesAliases` (`snep/lib/PBX/DatesAliases.php`)
- `Snep_ExpressionAliases_Manager`
  (`snep/lib/Snep/ExpressionAliases/Manager.php`)
- `Snep_CostCenter_Manager` (`snep/lib/Snep/CostCenter/Manager.php`)
- `Snep_ExtensionsGroups_Manager`
  (`snep/lib/Snep/ExtensionsGroups/Manager.php`)
- `Snep_SoundFiles_Manager` (`snep/lib/Snep/SoundFiles/Manager.php`)
- `Billing_Manager` (`snep/modules/billing/lib/Billing/Manager.php`)
- `Telcos_Manager` (`snep/modules/billing/lib/Telcos/Manager.php`)

Per this task's own explicit Phase 2/6/7 instructions ("do not artificially
limit the task to exactly 11 lines if sibling methods in the same
affected Manager are obviously equivalent"; "there must be no unexplained
request-controlled SQL concatenation remaining in these boundaries"),
this task also fixes every sibling method in each of those nine classes
sharing the identical raw-interpolation pattern, plus one closely-related
twin class discovered during reconstruction:

- `PBX_ExpressionAliases` (`snep/lib/PBX/ExpressionAliases.php`) — a
  second, parallel class operating on the exact same `expr_alias` table
  for the exact same Expression-Alias feature (`get()`/`update()`/
  `delete()` are the real, live `register()`/`update()` paths behind
  `ExpressionAliasController::addAction()`/`editAction()`, while
  `Snep_ExpressionAliases_Manager` only supplies `delete()`/
  `getValidation()` — the controller mixes both classes for one feature).
  This matches TASK-0026C/J/K/L's own established precedent of fixing
  "exact sibling sites sharing the same root cause" even across a class
  boundary when they are genuinely the same feature/table.

31 sites fixed total across these 10 files. This matches the precedent
already established by TASK-0026C (5/12/4 sibling sites across three
findings) and TASK-0026L (2 headline blockers → 16 sites across two
files).

Does not touch: Manager architecture redesign, conversion to
`Zend_Select` throughout, PHP 8.4 compatibility bugs unrelated to SQL
injection (several were discovered and are documented, not fixed, below),
legacy SIP removal, UI/menu/i18n, or Product Readiness — all explicitly
out of scope per this task's own instructions. Product Readiness work was
not started.

## Phase 1 — Blocker inventory reconstruction

Reconstructed from current source (not from category names alone), per
this task's own explicit instruction. TASK-0026L's own Phase 7 table
listed 10 controller/Manager pairs (its own prose rounds this to "eleven
further sinks" — a pre-existing minor miscount in that document, not
repeated here; CLAUDE.md: "correct documentation when later evidence
disproves an earlier assumption"). Each was re-traced end to end
(`HTTP request → controller/action → Manager method → request/persisted
value → SQL construction → database execution`) against current code:

| ID | Manager | Headline method(s) | Entry point | Controlled value | SQL sink (pre-fix) | Class |
|---|---|---|---|---|---|---|
| M1 | `Snep_Contacts_Manager` | `remove($id)` | `ContactsController::removeAction()` POST | `$_POST['id']` | `delete('contacts_names', "id = '$id'")` | DIRECT |
| M2 | `Snep_Contacts_Manager` | `edit($contact)` | `ContactsController::editAction()` POST | `$dados['id']` = raw route `id`, no cast | `update(..., "id = '{$contact['id']}'")` | DIRECT |
| M3 | `Snep_ContactGroups_Manager` | `remove($id)` / `edit($group)` | `ContactGroupsController::removeAction()`/`migrationAction()`/`editAction()` POST | `$_POST['id']` / route `id` | `delete(..."id = '$id'")` / `update(..."id = '{$group['id']}'")` | DIRECT |
| M4 | `PBX_DatesAliases` | `delete($id)` / `update($dates)` / `getValidation($id)` | `DatesAliasController::removeAction()` POST/GET | `$_POST['id']` / route `id` (uncast) | `delete/update "...=$id"` / `FIND_IN_SET($id, ...)` | DIRECT (`getValidation()` reachable via bare GET, no CSRF needed) |
| M5 | `Snep_ExpressionAliases_Manager` | `delete($id)` | `ExpressionAliasController::removeAction()` POST | `$_POST['id']` | `delete("expr_alias", "aliasid='$id'")` | DIRECT |
| M5b | `PBX_ExpressionAliases` (twin class, same table) | `update($expression)` / `delete($id)` | `ExpressionAliasController::editAction()` POST (`update()`); `delete()` unused by any controller, fixed for consistency | `$expression['id']` = route `id`, currently `(int)`-cast at the one call site | `update(..."aliasid='$id'")` / `delete("expr_alias","aliasid='$id'")` | Guarded-but-raw at present; fixed for defense-in-depth |
| M6 | `Snep_CostCenter_Manager` | `remove($id)` / `edit($costcenter)` | `CostCenterController::removeAction()`/`editAction()` POST | `$_POST['id']` / route `id` | `delete(..."codigo = '$id'")` / `update(..."codigo = '{$costcenter['id']}'")` | DIRECT |
| M7 | `Snep_ExtensionsGroups_Manager` | `delete($id)` (+ `get()`/`editGroup()`/`deleteGroupExtensions()`/`deleteExtensionGroups()` siblings) | `ExtensionsGroupsController::removeAction()`/`editAction()`/`migrationAction()` POST | `$_POST['id']` / route `id` | `delete("core_groups","id= ".$id)` — not even quoted | DIRECT |
| M8 | `Snep_SoundFiles_Manager` | `remove($file,$class)` / `edit($file)` | `SoundFilesController::removeAction()`/`editAction()` POST; `MusicOnHoldController::editfileAction()`/`removefileAction()` POST | `$_POST['id']` / `$dados['arquivo']`/`$dados['secao']` | `delete/update "arquivo='$file'..."` | DIRECT |
| M9 | `Billing_Manager` | `remove($id)` / `update($bill)` | `Billing_BillingController::removeAction()`/`editAction()` POST | `$_POST['id']` / route `id` | `delete(..."id = '$id'")` / `update(..."id = '{$bill['id']}'")` | Real vulnerable code; **currently HTTP-unreachable** (see below) — fixed regardless, matching TASK-0026C's F10/TASK-0026L's precedent |
| M10 | `Telcos_Manager` | `remove($id)` / `update($telco)` | `Billing_TelcosController::removeAction()`/`editAction()` POST | `$_POST['id']` / route `id` | `delete(..."id = '$id'")` / `update(..."id = '{$telco['id']}'")` | Same as M9 — HTTP-unreachable, fixed regardless |

**M9/M10 reachability nuance, discovered during this task's own live
reconstruction (matching TASK-0026L's own PickupGroups precedent for a
different, unrelated bug class):** every action in both
`Billing_BillingController` and `Billing_TelcosController` that touches
`Billing_Manager`/`Telcos_Manager` beyond `getAll()` fatals immediately
under PHP 8.4 — confirmed live:

```text
PHP Fatal error: Uncaught Error: Non-static method Billing_Manager::getAll()
  cannot be called statically in BillingController.php:16   (indexAction, GET)
PHP Fatal error: Uncaught Error: Non-static method Billing_Manager::getBillTypes()
  cannot be called statically in BillingController.php:29   (addAction, GET)
PHP Fatal error: Uncaught Error: Non-static method Billing_Manager::get()
  cannot be called statically in BillingController.php:103  (removeAction, POST)
PHP Fatal error: Uncaught Error: Non-static method Telcos_Manager::add()
  cannot be called statically in TelcosController.php:56    (addAction, POST)
PHP Fatal error: Uncaught Error: Non-static method Telcos_Manager::get()
  cannot be called statically in TelcosController.php:120   (removeAction, POST)
```

`Billing_Manager`/`Telcos_Manager` declare every method except
`getAll()` (and, for Telcos, `getAll()` alone — see the class's own
TASK-0015A docblock) as plain instance methods, but every controller
calls them with `::` static syntax throughout — a PHP 8.0 fatal
(`Error: Non-static method X::Y() cannot be called statically`),
confirmed via a minimal live reproduction against this environment's
actual PHP 8.4.25. This is the same bug **class** (not the same bug)
TASK-0026L documented for `PickupGroupsController::removeAction()`
(`mysql_escape_string()`), TASK-0026C documented for
`ProfilesController::addAction()` (F8, `count(false)`), and TASK-0015A
already flagged for `Telcos_Manager` itself ("a separate, unexercised
instance of the identical bug… not fixed here"). `BillingController`'s
`indexAction()`/`addAction()`/`editAction()` and
`TelcosController::addAction()`/`editAction()` are unconditionally
fatal-broken on **every** GET or POST, any input; `removeAction()`'s GET
render path survives (no Manager call until POST), but its POST branch
(where `remove()` actually lives) is equally fatal-broken. **The entire
billing module is therefore currently non-functional under PHP 8.4,
independent of this task's own fix** — a pre-existing, category-A/B PHP
8.4 compatibility defect, **not fixed here** (see "Pre-existing bugs"
below). Per TASK-0026L's own established precedent ("the vulnerable
Manager methods reachable only through it are still fixed here
regardless"), M9/M10 are fixed anyway — real, vulnerable code — and
verified via direct Manager invocation (see Phase 6).

## Phase 2 — Scope normalization / sibling grouping

Grouped by root cause (`$db->delete()`/`$db->update()`/hand-built SQL
string with unescaped `'$var'`/`$var` in a `WHERE`-equivalent position)
and fixed together within each file, per this task's own explicit
instruction not to stop at exactly the headline sinks:

| File | Sites fixed | Sink methods |
|---|---|---|
| `snep/lib/Snep/Contacts/Manager.php` | 5 | `remove()`, `removeGroup()`, `removePhone()`, `edit()`, `removeByGroupId()` |
| `snep/lib/Snep/ContactGroups/Manager.php` | 4 | `remove()`, `edit()`, `insertContactOnGroup()`, `removeContactOnGroup()` |
| `snep/lib/PBX/DatesAliases.php` | 4 | `get()`, `update()` (×2 statements), `delete()` (×2 statements), `getValidation()` |
| `snep/lib/PBX/ExpressionAliases.php` | 3 | `get()` (×2 statements), `update()` (×2 statements), `delete()` |
| `snep/lib/Snep/ExpressionAliases/Manager.php` | 1 | `delete()` |
| `snep/lib/Snep/CostCenter/Manager.php` | 2 | `remove()`, `edit()` |
| `snep/lib/Snep/ExtensionsGroups/Manager.php` | 5 | `get()`, `editGroup()`, `delete()`, `deleteGroupExtensions()`, `deleteExtensionGroups()` |
| `snep/lib/Snep/SoundFiles/Manager.php` | 3 | `edit()`, `remove()` (×2 branches), `editClassFile()` |
| `snep/modules/billing/lib/Billing/Manager.php` | 2 | `remove()`, `update()` |
| `snep/modules/billing/lib/Telcos/Manager.php` | 2 | `remove()`, `update()` |
| **Total** | **31** | |

(Counts above are per-method; several methods interpolate the tainted
value into more than one SQL statement — e.g. `PBX_DatesAliases::update()`
touches both `date_alias` and `date_alias_list` — each such statement was
fixed individually.)

## Phase 3 — Remediation pattern

Every fix uses the exact `$db->quoteInto('col = ?', $val)` (for
`update()`/`delete()`'s string `$where` argument) or
`->where('col = ?', $val)` (for `Zend_Db_Select`) pattern already
established five times over by TASK-0026C/F1/J/K/L — no new pattern, no
behavior change for any legitimate (non-injecting) input. For array-form
`$where` arguments (`Snep_ExtensionsGroups_Manager::deleteGroupExtensions()`/
`deleteExtensionGroups()`, `Snep_SoundFiles_Manager::remove()`/`edit()`/
`editClassFile()`), the pre-fix code passed a list-indexed array of raw
concatenated strings (`Zend_Db_Adapter_Abstract::_whereExpr()` treats an
int-keyed array entry as a literal, unescaped fragment); the fix converts
each to the associative `array('col = ?' => $val, ...)` form, which the
same `_whereExpr()` implementation quotes via `quoteInto()` per entry —
confirmed by direct read of `Zend_Db_Adapter_Abstract::_whereExpr()`
(`snep/lib/Zend/Db/Adapter/Abstract.php:676-703`). No `addslashes()`,
`str_replace()`-based escaping, or blacklist filtering was introduced
anywhere.

Example (`Snep_ExtensionsGroups_Manager::deleteGroupExtensions()`):

```php
// before
$db->delete("core_peer_groups",
    array('peer_id = '.$member['peer_id'],
          'group_id = '.$member['group_id']));
// after
$db->delete("core_peer_groups",
    array('peer_id = ?' => $member['peer_id'],
          'group_id = ?' => $member['group_id']));
```

`PBX_ExpressionAliases::get()`'s two hand-built `SELECT ... WHERE
aliasid='$id'` strings use the same `$db->quoteInto("SELECT ... WHERE
aliasid=?", $id)` concatenation TASK-0026L already established for
`Snep_Queues_Manager::getValidation()`'s comparable hand-built-string
shape.

No real numeric-domain field was blanket-cast to `(int)` in place of
binding — every fix preserves the existing string/mixed parameter shape
and lets `quoteInto()`/bound `where()` handle correct SQL-level quoting,
matching this task's own stated preference for binding over casting
except where the domain is genuinely, unambiguously integer.

## Phase 4 — Direct vs second-order classification

- **DIRECT** (raw request value reaches the SQL sink in the same
  request, no intervening persistence): M1, M2, M3, M4, M5, M6, M7, M8 —
  all confirmed live (Phase 5 below).
- **Second-order** (a request-controlled value is persisted first, then
  later re-enters SQL construction on a *different* request): none of
  the 31 fixed sites in this task's scope were purely second-order in
  the TASK-0026J BLOCKER-A/TASK-0026L BLOCKER-F sense (a mass-assignable
  field silently overriding an auto-generated identifier). The closest
  analogues:
  - `Snep_ContactGroups_Manager::insertContactOnGroup()`/
    `removeContactOnGroup()` take a `$contactId` sourced from the
    `duallistbox_group[]` POST array's *keys* (`addAction()`/
    `editAction()`) — a request-controlled array key, not previously
    persisted, but arriving through an indirection layer (array-key
    extraction) rather than a bare `$_POST['id']`. Fixed identically to
    every other sibling in the same class.
  - `Snep_SoundFiles_Manager::edit()`'s `$file['arquivo']` and
    `editClassFile()`'s `$file['arquivo']`/`$file['secao']` are POST
    values matched against a *previously uploaded* file's stored name —
    the stored name itself was validated by `isSafeFilename()` at upload
    time (TASK-0026D), so this is not a live second-order injection
    vector today, but the edit-time value is the raw POST field, not the
    stored one, so it was fixed as DIRECT.
  - `Billing_Manager`/`Telcos_Manager`'s `update()` methods interpolate
    `$bill['id']`/`$telco['id']`, themselves the raw route `id` re-POSTed
    by the edit form — DIRECT, not second-order, since the id round-trips
    within one browser session's edit flow, never persisted-then-reused
    across sessions.
- M9/M10 (Billing/Telcos) are documented separately above as real
  vulnerable code currently gated by an unrelated PHP 8.4 fatal, not as
  second-order — the classification is about data flow shape, and both
  are structurally DIRECT once the unrelated blocking bug is
  hypothetically fixed.

No purely second-order finding (in the TASK-0026J BLOCKER-A mold —
mass-assignable field silently displacing a server-generated identifier)
was found among this task's assigned nine Manager families.

## Phase 5 — Safe reproduction (live proof)

For every DIRECT family (M1–M8), an apostrophe-shaped payload
(`foo'bar`) was submitted through the real, authenticated HTTP flow
(never a direct DB connection) against the pre-fix code, confirmed to
produce a genuine `SQLSTATE[42000]` syntax error, then reconfirmed clean
(HTTP 200/302, zero SQL/syntax error) after the fix — all via `git
stash`-free live A/B (the fix was applied incrementally per file, tested,
then the next file's fix applied):

| Family | Payload | Pre-fix | Post-fix |
|---|---|---|---|
| Contacts (`removeAction`) | `id=foo'bar` | `SQLSTATE[42000]... near 'bar')' at line 1` | HTTP 302, no SQL error |
| ContactGroups (`removeAction`) | `id=foo'bar` | `SQLSTATE[42000]... near 'bar')' at line 1` | HTTP 302, no SQL error |
| DatesAlias (`removeAction`, POST `delete()`) | `id=foo'bar` | `SQLSTATE[42000]... near ''bar)' at line 1` | HTTP 302, no SQL error |
| DatesAlias (`removeAction`, **GET** `getValidation()`) | route `id=foo'bar` | `SQLSTATE[42000]... near ''bar, regras_negocio.dates_alias))' at line 1` | HTTP 200, no SQL error |
| ExpressionAlias (`removeAction`) | `id=foo'bar` | `SQLSTATE[42000]... near 'bar')' at line 1` | HTTP 302, no SQL error |
| CostCenter (`removeAction`) | `id=foo'bar` | `SQLSTATE[42000]... near 'bar')' at line 1` | HTTP 302, no SQL error |
| ExtensionsGroups (`removeAction`) | `id=foo'bar` | `SQLSTATE[42000]... near ''bar)' at line 1` | HTTP 302, no SQL error |
| SoundFiles (`removeAction`) | `id=foo'bar` | `SQLSTATE[42000]... near 'bar' and tipo='AST' and language = 'pt_BR')' at line 1` | HTTP 302, no SQL error |

**DatesAlias's `getValidation()` finding is a notable severity
escalation over the headline M4 entry**: it is reachable via a bare,
unauthenticated-by-CSRF **GET** to `removeAction()` (the render path
calls `PBX_DatesAliases::getValidation($id)` unconditionally, before any
POST branch, with `$id` a raw, uncast route parameter) — no CSRF token
needed at all, only the ordinary `default_dates-alias_write` session.

M9/M10 (Billing/Telcos) were verified via direct Manager invocation
instead (see Phase 6) since no real HTTP path reaches them at all — 15
checks each (apostrophe-shaped id causes no exception; boolean-shaped id
cannot cross-update/cross-delete a second CANARY row; legitimate
update/remove still work end to end), matching TASK-0026L's own BLOCKER
E/F precedent for its own two HTTP-unreachable sub-boundaries.

No password/hash/schema extraction was attempted at any point; every
payload was a harmless, non-destructive syntax-difference or
boolean-oracle probe against fixtures this task owns.

## Phase 6 — Semantics preserved

For every changed method: CRUD behavior, not-found behavior,
authorization (no permission/resource changes), list/filter semantics,
current IDs/names, and current controller/view expectations are all
unchanged for any legitimate (non-injecting) input — `quoteInto('col =
?', $val)` and the old unquoted `"col = '$val'"` produce byte-identical
query results for any value that was never exploiting the missing
quoting in the first place. No method signature, return type, or public
behavior changed. Confirmed via the focused suite's own "legit"/"cleanup
works end to end" checks for every family (Phase 9).

## Phase 7 — Extended residual SQL security suite

Extended (not duplicated) `scripts/residual-sql-security-smoke-test.sh` /
`make residual-sql-security-smoke`, per this task's own explicit Phase 6
instruction, preserving every existing TASK-0026J/K/L check (BLOCKER
A–F) unchanged.

New coverage, 94 checks (suite grew from 50 to 144 total):

- **Preflight**: nine new boundary paths
  (`/index.php/default/{contacts,contact-groups,dates-alias,
  expression-alias,cost-center,extensions-groups,sound-files}`,
  `/index.php/billing/{billing,telcos}`) added to the zero-permission
  authorization-boundary loop; the corresponding nine `*_write`
  permissions added to the admin permission-grant step. The shared CLI
  bootstrap gained `Zend_Registry::set('log', new Zend_Log())` (required
  by `Billing_Manager`'s constructor, which the prior BLOCKER
  A–F-only bootstrap never needed).
- **Real-HTTP core proof (8 checks)**: an apostrophe-shaped payload
  against the primary, directly-reachable sink in each of the seven
  web-reachable families (plus DatesAlias's GET-reachable
  `getValidation()`) causes no SQL/syntax error and no new PHP Fatal
  Error — driven through the real, authenticated, CSRF-protected HTTP
  flow exactly like every BLOCKER A–F check.
- **Sibling/second-order coverage (80 checks)**: one self-contained,
  self-cleaning block per family, invoking the now-fixed Manager methods
  directly inside the app container via a new `run_manager_php_file()`
  helper (added alongside the existing `run_manager_php()` — takes an
  already-written local PHP file instead of a bash string argument,
  avoiding error-prone `\$`-escaping at this scale). Each block: creates
  a CANARY/CANARY2 (or CANARY/MALICIOUS) fixture pair via the Manager's
  own `add()`-equivalent (never the controller's `addAction()`, several
  of which carry the same `count(false)`-shaped PHP 8.4 TypeError
  TASK-0026L already documented — see "Pre-existing bugs" below);
  exercises a legitimate operation; exercises an apostrophe-shaped
  payload against every fixed sibling method in that file, asserting no
  exception (or, for `PBX_DatesAliases::update()`/
  `PBX_ExpressionAliases::update()`, no *syntax-error-shaped* exception —
  both throw a legitimate `SQLSTATE 22007` type-rejection on their own
  unrelated `dateid`/`aliasid` int columns when fed a non-numeric id,
  which is the *correct*, non-injection-related outcome once the `WHERE`
  clause itself is safely parameterized); exercises a boolean-shaped
  payload (`"0 OR id=<CANARY2_ID>"`) proving CANARY2 is never
  cross-affected; and cleans up by deleting both fixtures via the same
  Manager, verified via a final `_CLEANUP` marker.
- A `sweep_task0026m_residue()` best-effort safety-net cleanup (mirroring
  BLOCKER A's `sweep_orphaned_trunk_peers()` precedent) is registered
  once, up front, in case any block exits early.

**Result: PASS, 144/144** (up from 50/50). Cleanup ran cleanly — every
family's own inline cleanup succeeded, the safety-net sweep found
nothing left to remove, and every affected table (`contacts_names`,
`contacts_group`, `date_alias`/`date_alias_list`, `expr_alias`/
`expr_alias_expression`, `ccustos`, `core_groups`/`core_peer_groups`,
`sounds`, `telcos`, `billing`) was independently confirmed back to its
exact pre-run row count.

## Phase 8 — Complete Manager/class sibling audit

| File | Site | Classification |
|---|---|---|
| `Snep_Contacts_Manager` | `remove()`, `removeGroup()`, `removePhone()`, `edit()`, `removeByGroupId()` | `PARAMETERIZED_SAFE` — fixed (5 sites) |
| `Snep_Contacts_Manager` | `get()`, `getMember()`, `getPhone()`, `getStates()`, `getCity()`, `add()`, `addNumber()`, `getLastId()`, `getAll()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — already safe, unchanged |
| `Snep_ContactGroups_Manager` | `remove()`, `edit()`, `insertContactOnGroup()`, `removeContactOnGroup()` | `PARAMETERIZED_SAFE` — fixed (4 sites) |
| `Snep_ContactGroups_Manager` | `get()`, `getAll()`, `add()`, `getGroupContacts()`, `getValidation()`, `getName()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — already safe, unchanged |
| `PBX_DatesAliases` | `get()`, `update()`, `delete()`, `getValidation()` | `PARAMETERIZED_SAFE` — fixed (4 sites) |
| `PBX_DatesAliases` | `getInstance()`, `getAll()`, `getAllList()`, `add()` | `STATIC_SAFE`/no-SQL — unchanged (`add()` uses `$db->insert()`, natively bound) |
| `PBX_ExpressionAliases` | `get()`, `update()`, `delete()` | `PARAMETERIZED_SAFE` — fixed (3 sites); `get()`/`update()`'s own `$id` is presently `(int)`-cast (`get()`) or protected by an is-integer input guard at its call site, but the interpolation itself is fixed for defense-in-depth consistency, matching `PBX_DatesAliases::get()`'s own identical situation |
| `PBX_ExpressionAliases` | `getInstance()`, `getAll()`, `register()`, `getExpression()` | `STATIC_SAFE`/`PARAMETERIZED_SAFE` — already safe, unchanged |
| `Snep_ExpressionAliases_Manager` | `delete()` | `PARAMETERIZED_SAFE` — fixed (1 site) |
| `Snep_ExpressionAliases_Manager` | `getValidation()`, `get()`, `getAll()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — already safe, unchanged (`get()`/`getAll()` are dead code — the controller uses `PBX_ExpressionAliases`'s own methods instead — re-confirmed via `grep`, fixed pattern already safe regardless) |
| `Snep_CostCenter_Manager` | `remove()`, `edit()` | `PARAMETERIZED_SAFE` — fixed (2 sites) |
| `Snep_CostCenter_Manager` | `getAll()`, `get()`, `add()`, `getCdr()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — already safe, unchanged |
| `Snep_ExtensionsGroups_Manager` | `get()`, `editGroup()`, `delete()`, `deleteGroupExtensions()`, `deleteExtensionGroups()` | `PARAMETERIZED_SAFE` — fixed (5 sites) |
| `Snep_ExtensionsGroups_Manager` | `getAll()`, `getExtensionsGroup()`, `getExtensionsNoGroup()`, `getExtensionsAll()`, `getExtensionsOnlyGroup()`, `getName()`, `getValidation()`, `getExtensionsAllGroup()`, `getGroupsExtensions()`, `addGroup()`, `addExtensionsGroup()`, `updateExtensionsGroup()`, `updateGroupsExtension()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — already safe, unchanged |
| `Snep_SoundFiles_Manager` | `edit()`, `remove()`, `editClassFile()` | `PARAMETERIZED_SAFE` — fixed (3 sites, 5 statements) |
| `Snep_SoundFiles_Manager` | `get()`, `add()`, `getClassFile()`, `addClassFile()`, `getClassFiles()`, `syncFiles()`, `addSounds()`, `getSounds()`, `addClass()`/`editClass()`/`removeClass()`/`getClasse()`/`getClasses()` (file-based, no SQL), `isSafeFilename()`/`isSafeDirectoryName()`/`removeDirectoryRecursive()`/`checkType()`/`parseName()`/`converter()` (no SQL) | `PARAMETERIZED_SAFE`/`STATIC_SAFE`/N-A — already safe or no SQL involved, unchanged |
| `Billing_Manager` | `remove()`, `update()` | `PARAMETERIZED_SAFE` — fixed (2 sites); currently HTTP-unreachable (see Phase 1) |
| `Billing_Manager` | `getAll()`, `getBillTypes()`, `add()`, `get()`, `getByArea()`, `getByType()`, `getRate()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — already safe, unchanged |
| `Billing_Manager` | `rate()`'s `SELECT telco FROM trunks WHERE id='{$telco_id}'` | `STATIC_SAFE`/out-of-scope — `$telco_id` is `PBX_Trunks`-object-derived (`->getId()`), reached only from `snep/agi/snep.php`'s call-processing pipeline; re-confirmed unchanged from TASK-0026L's own identical classification, same AGI-only "not supported HTTP surface" boundary this program has applied since TASK-0026K |
| `Telcos_Manager` | `remove()`, `update()` | `PARAMETERIZED_SAFE` — fixed (2 sites); currently HTTP-unreachable (see Phase 1) |
| `Telcos_Manager` | `getAll()`, `add()`, `get()` | `PARAMETERIZED_SAFE`/`STATIC_SAFE` — already safe, unchanged |

**No unexplained request-controlled SQL concatenation remains in any of
the ten fixed files.** Every raw-interpolation site has been either fixed
(31 sites total) or is independently confirmed `STATIC_SAFE`/
`PARAMETERIZED_SAFE`/no-SQL with its own call-site evidence recorded
above.

## Phase 9 — Broader supported-surface SQL sweep

A repository-wide sweep for `request-controlled value → raw SQL
concatenation → database execution` and `persisted user-controlled value
→ raw SQL construction → database execution`, broader than Phase 8's
ten-file scope, matching the methodology TASK-0026Z/J/K/L each used at
their own closure point.

**Already-covered, re-confirmed unchanged**: every file named in
TASK-0026L's own Phase 7 "already-covered" list (`ExtensionsController.php`/
`Snep/Extensions/Manager.php`, `TrunksController.php`/
`Snep/Trunks/Manager.php`, `Snep_InterfaceConf.php`,
`{Calls,Ranking,Services}ReportController.php`, `Snep/CsvIE.php`,
`ExportDataController.php`, `Snep/Users/Manager.php`/
`Snep/Profiles/Manager.php`, `PjsipTrunkConf.php`/`PjsipConf.php`/
`PjsipTransportConf.php`, all five standalone API report/CSV/contacts
services, `Snep_PickupGroups_Manager.php`/`Snep_Queues_Manager.php`) plus
this task's own ten files (above) — no site in any of these reclassified.

**Confirmed `STATIC_SAFE`/out-of-scope, newly re-verified**:
`Snep_Dashboard_Manager`, `Snep_PjsipTransports_Manager::update()`/
`remove()` (`(int)` cast before interpolation — re-confirmed by direct
read of the current method body), `ParametersController.php`'s
`language` field (allowlist-validated), `Billing_Manager::rate()` (AGI-only,
above).

**Confirmed exploitable, NEW, outside this task's assigned scope**:

1. **`PBX_Rule::checkExpr()`'s `'CG'` case**
   (`snep/lib/PBX/Rule.php:381-391`):
   ```php
   case 'CG':
     $db = Zend_Registry::get('db');
     $select = $db->select()
     ->from(array("n" => "contacts_names"))
     ->join(array("p" => "contacts_phone"), 'n.id = p.contact_id')
     ->where("`group` = '$expr'")
     ->where("`phone` = '$value'");
   ```
   `$value` traces directly to `SimulatorController::indexAction()`'s
   `$formData['caller']` (or `$formData['dst']`) POST field — no cast, no
   validation — via `PBX_Dialplan_Verbose::parse()` →
   `PBX_Rule::isValidSrc()`/`isValidDst()` → `checkExpr()`. `$expr` is the
   persisted business rule's own `'CG:<id>'`-encoded source/destination
   value (second-order, admin-configured). `default_simulator` is on the
   **authenticated-open allowlist** (`Snep_PermissionPlugin::$readActions`,
   `snep/modules/default/model/PermissionPlugin.php:59`) — reachable by
   *any* logged-in account, not merely a privileged one. **Confirmed
   live**: with a temporary `CG:1`/`X` test rule in place (created and
   removed by this task's own reconstruction, never left behind), an
   authenticated POST to `/index.php/default/simulator` with
   `caller=foo'bar` produced a genuine
   `SQLSTATE[42000]: Syntax error ... near 'bar')' at line 2`.
2. **`PBX_Usuarios::hasExtenGroup()`**
   (`snep/lib/PBX/Usuarios.php:196-210`):
   ```php
   $select = $db->select()
       ->from('core_peer_groups')
       ->joinInner('peers','peers.id = core_peer_groups.peer_id')
       ->where('peers.name = '.$exten)
       ->where('core_peer_groups.group_id = '.$group);
   ```
   Reached from the identical `checkExpr()`/Simulator chain (`case 'G'`,
   `snep/lib/PBX/Rule.php:359-364`) — an **unquoted** concatenation (no
   surrounding `'...'` at all), a strictly more severe variant than
   `'CG'` above since it requires no quote-breaking at all, only a
   syntactically-invalid bareword.
3. **`PBX_Rules::delete($id)`** (`snep/lib/PBX/Rules.php:47`):
   `$db->delete("regras_negocio", "id='{$id}'")`. Reached from
   `RouteController::removeAction()` (`snep/modules/default/controllers/
   RouteController.php:649`) with `$_POST['id']` raw, gated by the
   ordinary `default_route_write` permission — Route/Business Rules is a
   core, heavily-used feature, not a peripheral one. **Confirmed live**:
   an authenticated POST to `/index.php/default/route/remove/id/1` with
   `id=foo'bar` produced a genuine
   `SQLSTATE[42000]: Syntax error ... near 'bar')' at line 1`.

**`PBX_Usuarios::get($userid)`** (`snep/lib/PBX/Usuarios.php:50-60`,
reached from the same `SimulatorController` when `srcType=exten`) was
also inspected — it interpolates `$userid` inside a quoted string, but
the method itself calls `str_replace("'", "\'", $userid)` first, a
naive-but-currently-effective backslash-escape (this project's MariaDB
10.11 default `sql_mode` — `STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,
NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION` — does **not** set
`NO_BACKSLASH_ESCAPES`, and the connection charset is `utf8mb3`, not a
vulnerable multi-byte charset like GBK/Big5 that could consume the
escaping backslash). **Confirmed live**, against a real `peer_type='R'`
fixture row: a boolean-injection payload
(`caller=nonexistent' OR name='<real-peer-name>`) rendered "not found" —
the entire payload was treated as inert literal string data, not SQL
syntax, no cross-row match. Per this task's own explicit Phase 8/9
caution ("Do not treat every raw SQL statement as vulnerable"),
`PBX_Usuarios::get()` is classified **`NOT CONFIRMED EXPLOITABLE`** under
this project's actual supported default configuration — real, fragile,
non-idiomatic legacy code (`str_replace()`-based escaping is exactly the
pattern this program's own remediation rule forbids as a *fix*, but this
is pre-existing code, not a new fix), flagged as technical debt for a
future defensive-hardening task, not counted toward this Phase's
exploitable-sink conclusion.

None of the three confirmed-exploitable sinks above were modified. All
are outside this task's assigned scope (the nine named Manager
families), and per CLAUDE.md's "do not fix unrelated legacy bugs
opportunistically"/"do not mix migration phases" principles, fixing them
is not this task's call to make unilaterally. They are handed off as
evidence for the next security task, not silently absorbed into this
one's scope. This sweep was not exhaustive of every remaining codepath in
the repository (matching TASK-0026L's own honesty about its sweep's
limits) — `snep/lib/PBX/Rules.php`'s own `update()`/other sites,
`snep/lib/Snep/Alerts.php`, `snep/lib/Snep/Binds/Manager.php`,
`snep/lib/Snep/Extensions.php`, `snep/lib/Snep/ModuleSettings/Manager.php`,
`snep/lib/Snep/Operadoras.php`, and
`snep/lib/Snep/PjsipTransports/Manager.php:253` (`update()`, unquoted
`"id = $id"`) were identified via grep as carrying the same raw-`$db->
delete()`/`update()`-with-interpolation shape but were **not**
individually traced to a confirmed-live verdict — flagged for the next
sweep, not asserted safe.

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

Per this task's own explicit instruction ("If a new supported-surface
SQL injection sink is found: STOP… Do not automatically create
TASK-0026N"), **no new task was created**. This finding is handed off as
evidence only.

## Phase 10 — Focused validation

```bash
make residual-sql-security-smoke
```

**Result: PASS, 144/144** (up from 50/50). All nine new Manager families
covered (Contacts, ContactGroups, DatesAlias, ExpressionAlias, CostCenter,
ExtensionsGroups, SoundFiles, Billing, Telcos), plus `PBX_ExpressionAliases`.
Every TASK-0026J/K/L check (BLOCKER A–F) preserved and still passing.
Cleanup: every family's own inline cleanup succeeded; the
`sweep_task0026m_residue()` safety net found nothing outstanding; every
affected table independently confirmed back to its exact baseline row
count (`contacts_names` 0, `contacts_group` 1, `date_alias`/
`date_alias_list` 0/0, `expr_alias`/`expr_alias_expression` 4/7, `ccustos`
10, `core_groups`/`core_peer_groups` 1/0, `sounds` 318, `telcos` 0,
`billing` 0).

## Phase 11 — Canonical validation

- `php -l` on all 10 touched application files: clean.
- `bash -n` on the extended smoke script: clean.
- `make lint`: **PASS, 5/5** (271 PHP files, 0 syntax errors; 24 shell
  scripts; 3 `resources.xml` files well-formed; clean `git diff --check`).
- `make regression`, first run: **PASS, 22/22 suites.**
- `make regression`, second consecutive run (immediately after, no code
  changes, no manual cleanup in between): **PASS, 22/22 suites**,
  byte-identical to the first run.

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

No FAIL, no BLOCKED, no INCONCLUSIVE, in either run — no transient
flakes were hit this time. No product code was modified between the two
runs, and no manual cleanup was performed.

## Phase 12 — Health and cleanup

- `docker compose ps`: `app`/`asterisk`/`db`/`provider` all `Up
  (healthy)`.
- Asterisk 22.10.1; `res_pjsip.so` — 1 module, Running.
- `pjsip show transports`: 3 baseline transports intact (`tcp`, `udp`,
  `wss`).
- AMI: `manager show connected` responsive, 0 connected users.
- ODBC: `snep` DSN, 1/1 active connection.
- `core show channels count`: 0 active channels, 0 active calls.
- PHP Fatal Error signature check: the two known, pre-existing
  `count(): Argument #1 ($value) must be of type Countable|array` /
  `null given` signatures (`CallsReportController.php:402` and
  `Zend/Validate/File/Upload.php:226`, both TASK-0026J/D's own documented
  Product Readiness items) — zero fatals attributable to this task's own
  changes.
- One pre-existing, unrelated `SQLSTATE[HY000]: ... Field 'secao'
  doesn't have a default value` entry was newly observed in the log
  during regression (triggered by `shell-security-smoke-test.sh`'s own
  real sound-file upload fixture via `SoundFilesController::addAction()`
  → `Snep_SoundFiles_Manager::add()`) — `add()`'s own `$insert_data` array
  never includes `secao` (a `NOT NULL`, no-default, primary-key column),
  a pre-existing strict-SQL-mode compatibility gap (CLAUDE.md category D)
  entirely unrelated to SQL injection and untouched by this task's own
  fix (`add()` itself was not modified). This task's own smoke fixtures
  route around the identical gap by inserting directly rather than via
  `add()` (documented inline in the suite). Flagged here as newly-noticed
  Product Readiness debt, not fixed.
- Fixture residue: zero across every table this task touched (see Phase
  10). `users` contains only `admin` plus every prior task's documented
  persistent dev fixture — this task introduced no new persistent user
  (its own fixtures are all delete-at-end-of-run, non-persistent).
- No leftover baresip/smoke-test processes or containers, host or
  container side.
- `git diff --check`: clean.
- `git diff --stat` / `git status --short`: exactly the 11 modified
  files listed below — no scope creep.

## Pre-existing bugs discovered, deliberately not fixed

Per CLAUDE.md's "do not fix unrelated legacy bugs opportunistically" —
each is documented here as debt rather than patched. None are SQL
injection defects.

- **`Billing_Manager`/`Telcos_Manager`'s "non-static method called
  statically" fatal** (Phase 1) — every mutating action in both
  `Billing_BillingController` and `Billing_TelcosController` currently
  fatals under PHP 8.4, confirmed live with five distinct fatal
  signatures. The entire billing module is non-functional end to end
  independent of this task's own fix. A `TASK-0002`/`TASK-0015A`-style
  per-method static/instance classification (matching this class's own
  existing `getAll()` precedent) would resolve this; left undone per
  this task's own scope boundary. `TASK-0015A`'s own docblock in
  `Telcos_Manager.php` already flagged this exact debt for `add()`/
  `get()`/`remove()`/`update()` — still unresolved.
- **`Snep_SoundFiles_Manager::add()`'s missing `secao` insert field**
  (Phase 12) — a pre-existing strict-SQL-mode compatibility gap
  (category D), newly observed during this task's own regression run via
  `shell-security-smoke-test.sh`'s real upload fixture. Not an SQL
  injection defect (no attacker-controlled value is involved — the
  column is simply omitted from the `INSERT` field list); `add()` itself
  was not modified by this task.
- **`PBX_DatesAliases::update()`/`PBX_ExpressionAliases::update()`'s
  incomplete transaction try/catch** (Phase 7) — both wrap only their
  final `$db->commit()` call in `try`/`catch(...) { $db->rollBack(); }`,
  not the `$db->insert()` calls that precede it; an exception from that
  `insert()` (e.g. a genuinely malformed non-numeric id reaching the
  int-typed `dateid`/`aliasid` column on the child table) propagates with
  the transaction left open. Confirmed harmless to this task's own
  parameterization fix (the `WHERE`-clause safety property this task
  cares about is fully exercised and proven before the unrelated
  `insert()` ever runs), and not itself a security defect — a
  transaction-handling completeness gap, category B/C.

## Files changed

```
scripts/residual-sql-security-smoke-test.sh    TASK-0026M focused coverage (+94 checks, 50->144)
snep/lib/Snep/Contacts/Manager.php             M1/M2 + 3 sibling sites (5 total)
snep/lib/Snep/ContactGroups/Manager.php        M3 + 2 sibling sites (4 total)
snep/lib/PBX/DatesAliases.php                  M4 + 1 sibling site (4 total)
snep/lib/PBX/ExpressionAliases.php             M5b twin-class fix (3 sites)
snep/lib/Snep/ExpressionAliases/Manager.php    M5 (1 site)
snep/lib/Snep/CostCenter/Manager.php           M6 (2 sites)
snep/lib/Snep/ExtensionsGroups/Manager.php     M7 + 4 sibling sites (5 total)
snep/lib/Snep/SoundFiles/Manager.php           M8 + 1 sibling site (3 sites, 5 statements)
snep/modules/billing/lib/Billing/Manager.php   M9 (2 sites)
snep/modules/billing/lib/Telcos/Manager.php    M10 (2 sites)
```

Every other prior TASK-0026x file is untouched. Product Readiness work
was not started.

## Security handoff — why `SECURITY_GATE` remains `NO-GO`

Per Phase 9's explicit instruction, this task stops here rather than
silently expanding its own scope. All nine assigned Manager families (and
their 21 in-file/one cross-file siblings) are closed, verified, and
regression-covered. However:

```text
known SQL injection = 0 in supported surfaces   NOT SATISFIED
```

`PBX_Rule::checkExpr()` (`'CG'`/`'G'` cases) and `PBX_Usuarios::
hasExtenGroup()`, both reachable via `SimulatorController::indexAction()`
(open to every authenticated user), plus `PBX_Rules::delete()` reachable
via `RouteController::removeAction()` (an ordinary `default_route_write`
grant), all carry the exact same unescaped-`'$var'`/`$var`-in-`WHERE`
defect this task and TASK-0026C/J/K/L have now closed six times over in
different controllers — none touched by this task.

**Recommended next task** (not opened automatically, per Phase 9): close
these three confirmed sinks in `PBX_Rule.php`/`PBX_Usuarios.php`/
`PBX_Rules.php` using the exact same `$db->quoteInto()` pattern this task
and its five predecessors have now established six times over. While
auditing those files, also individually trace the six additional
grep-flagged-but-unconfirmed candidates this task's own Phase 9 sweep
surfaced (`PBX_Rules.php`'s remaining sites, `Snep/Alerts.php`,
`Snep/Binds/Manager.php`, `Snep/Extensions.php`,
`Snep/ModuleSettings/Manager.php`, `Snep/Operadoras.php`,
`Snep/PjsipTransports/Manager.php:253`) to a confirmed verdict before
declaring the gate closed. Separately, and only as a follow-on decision
(not blocking this SQL-specific gate): the `PBX_Rule`/`PBX_Rules`/
`PBX_Usuarios`/`PBX_Dialplan` family represents a structurally distinct
"business-rule matching engine" root cause, not merely more Manager-layer
CRUD sinks — a dedicated task should decide whether it needs its own
architectural review (e.g. of `SimulatorController`'s authenticated-open
allowlist status) rather than a purely mechanical fix.
