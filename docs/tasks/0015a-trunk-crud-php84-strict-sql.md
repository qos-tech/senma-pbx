# TASK-0015A — Restore trunk CRUD on PHP 8.4 and strict SQL

## Status

**Implemented and validated.** `make smoke`: 16 PASS / 0 FAIL / 0
EXPECTED_LIMITATION. `make call-smoke`: 18/18 PASS. Zero new PHP Fatal
Errors. Full trunk create/edit/delete lifecycle validated against the
real running UI (not direct SQL). Not committed — stopping at the
commit checkpoint per the task instructions.

## Goal

Restore the existing chan_sip/IAX2/KHOMP/VIRTUAL trunk add/edit/delete
lifecycle to working order under PHP 8.4 and strict MariaDB, as a
prerequisite for TASK-0015 (outbound PJSIP trunk provisioning). No PJSIP
trunk objects were implemented. This task's scope is entirely
compatibility restoration in code that already exists.

## Summary of what was found

The two blockers named in TASK-0014
(`docs/tasks/0014-pjsip-trunk-provisioning-architecture.md`) were
confirmed exactly as described, fixed, and validated. **Investigating
and validating them live surfaced three further, independent blockers**
in the same create/edit code paths — each was stopped on, reported, and
fixed only after explicit approval, per the task's instruction not to
recursively absorb newly discovered blockers. All five together were
necessary to get a real, working trunk create/edit/delete round trip
through the actual UI; fixing only the original two would still have
left every trunk creation attempt failing.

---

## P0-1 — `Telcos_Manager::getAll()` called statically, not declared static

- **File/class/method**: `snep/modules/billing/lib/Telcos/Manager.php:20`
  (`Telcos_Manager::getAll()`), called from
  `snep/modules/default/controllers/TrunksController.php` in
  `addAction()` and `editAction()`.
- **Exact runtime failure** (reproduced first, before any fix, via
  `GET /index.php/default/trunks/add`):
  ```
  PHP Fatal error:  Uncaught Error: Non-static method Telcos_Manager::getAll()
  cannot be called statically in .../TrunksController.php:202
  ```
- **Technology-agnostic or PJSIP-specific**: technology-agnostic — fires
  on the form's initial `GET`, before any technology field is read.
- **Trace performed before editing**: read the complete
  `Telcos_Manager` class (`getAll()`, `add()`, `get()`, `remove()`,
  `update()`) — **every method uses no `$this` at all**. Searched all
  call sites across the tree (`grep -rn "Telcos_Manager::"`): 10 total —
  `TrunksController.php` (`addAction`/`editAction`, the only ones this
  task's scope covers) and `TelcosController.php`/`BillingController.php`
  (billing module's own Telcos management UI, 8 call sites, calling
  `getAll`/`add`/`get`/`remove`/`update` — **all** via `::`, never via
  `new Telcos_Manager()`). Every method is uniformly stateless and
  uniformly called statically everywhere in this codebase — there is no
  mixed instance/static usage to reconcile.
- **Is making only `getAll()` static behavior-preserving?** Yes,
  unambiguously — the method body uses no `$this`, PHP allows a class to
  mix static and non-static method declarations freely, and no code
  anywhere calls `getAll()` in a way that depends on instance state (no
  such call exists). Declaring only this one method static changes
  nothing about how it executes or how any caller invokes it.
- **Why not blanket-convert the class**: `add()`/`get()`/`remove()`/
  `update()` are called identically to `getAll()` (via `::`, using no
  `$this`) but from `TelcosController.php`/`BillingController.php` —
  **files this task never touches**. Per CLAUDE.md's static-method-
  migration rule ("classify methods individually... do not blanket-
  convert mixed classes") and this task's own scope boundary ("do not
  fix unrelated legacy bugs"), only the one method this task's own
  validation path actually calls was changed. The other four methods are
  almost certainly hit by the identical fatal the moment
  `TelcosController`'s own UI is used — **noted here as a discovered,
  adjacent, out-of-scope finding, not fixed**, exactly matching this
  task's item 6 instruction ("if another independent blocker appears:
  stop and report it, do not recursively absorb it without approval") —
  reported, not absorbed.
- **Fix applied**: added `static` to `Telcos_Manager::getAll()`'s
  declaration. One keyword, no other change to the file.
- **Validation performed**: `php -l`; `GET
  /index.php/default/trunks/add` and `/trunks/edit/trunk/<id>` both
  return `200` and render the form; full create/edit/delete lifecycle
  (below) exercised end-to-end; `make smoke`'s `trunks` check (list page)
  stays green.

---

## P0-2 — `peers.password`/`trunk`/`lastms` omitted from the trunk INSERT

- **File/class/method**:
  `TrunksController::preparePost()` (`snep/modules/default/controllers/
  TrunksController.php`), specifically its `$ip_fields` allow-list and
  the loop building `$ip_data` — the array later passed to
  `Zend_Db::insert("peers", ...)` for any `trunktype=="I"` (SIP/IAX2/
  SNEPSIP/SNEPIAX2) trunk.
- **Exact runtime failure**, reproduced via a minimal, immediately-
  deleted direct SQL test reconstructing exactly what `preparePost()`'s
  `$ip_data` would contain (performed during TASK-0014, re-confirmed
  live via the real UI in this task after P0-1 was fixed):
  ```
  SQLSTATE[HY000]: General error: 1364 Field 'password' doesn't have a default value
  ```
  then, once `password` was included, `'trunk' doesn't have a default
  value`, then `'lastms' doesn't have a default value` — three columns,
  chained, all `NOT NULL` with no `DEFAULT` clause in `schema.sql`, all
  simply never present in `$ip_data`.
- **Technology-agnostic or PJSIP-specific**: technology-agnostic — the
  `peers` INSERT/UPDATE for *any* `trunktype=="I"` row, chan_sip/IAX2/
  SNEPSIP/SNEPIAX2 alike. Identical class of bug to the `peers.lastms`
  gap TASK-0011 already found and fixed for **extensions**'
  `ExtensionsController::execAdd()` — that fix never touched
  `TrunksController::preparePost()`'s separate INSERT, so the twin bug
  survived, plus two further columns (`password`, `trunk`) extensions'
  own INSERT already happened to include.
- **Trace performed before editing (per item 3's explicit questions)**:
  - **Legacy intended initial value, evidenced from the sibling,
    already-working extensions INSERT** (`ExtensionsController::
    execAdd()`, read in full): `password='$extenPass'` where
    `$extenPass = $formData["passwordpadlock"]` — a separate numeric-PIN
    feature unrelated to the SIP secret (TASK-0010 §2 already
    established this for extensions); the trunk form has **no
    equivalent field at all**, so the behavior-preserving value is the
    same "no PIN set" state a fresh extension gets when its own
    padlock field is left blank: `''`. `trunk='no'` — extensions' INSERT
    writes this literal value in the `trunk` column position; cross-
    checked against `Snep_InterfaceConf.php:154`'s still-present but
    commented-out `// $peers .= 'trunk=' . $peer['trunk'] . "\n";`
    (guarded by a commented `// if ($trunk->type == "IAX2")`), confirming
    `peers.trunk` was originally intended to drive chan_iax2's native
    `trunk=yes/no` directive — `'no'` is the non-trunking default, not
    an arbitrary placeholder. `lastms=0` — identical reasoning and
    precedent as TASK-0011's own fix for extensions (the "never
    qualified" placeholder chan_sip peers show before their first real
    registration).
  - **Would old non-strict MySQL have implicitly supplied a different
    value?** For `password`/`trunk` (both `VARCHAR`), non-strict mode's
    own implicit default would have been `''` for both — matching the
    evidenced value for `password` exactly, but **not** for `trunk`
    (whose evidenced, deliberate value from the sibling extensions code
    is `'no'`, not an accidental `''`). This is precisely why the fix
    uses the sibling code's explicit value rather than "whatever
    non-strict mode would have silently done" — the two aren't always
    the same, and the explicit value is the stronger, deliberate
    evidence per the task's own instruction to prefer that over
    "existing rows" (this dev database has no legacy production rows to
    inspect either way — the sibling, already-correct extensions code
    was the best available evidence).
  - **Does the application later update these columns?** No — confirmed
    via `grep -rn "lastms"`/`peers.trunk` writers across `snep/lib` and
    `snep/modules`: the only other reference to either column anywhere
    in first-party code is `ExtensionsController.php`'s own INSERT.
    Nothing updates them post-creation for either extensions or trunks.
  - **Does schema.sql need a default added instead?** No evidence found
    that it should — the schema itself is not "wrong": these are
    meaningful, evidenced values (a disabled feature, a real chan_iax2
    directive default, a "never qualified" placeholder) that belong at
    the write site, exactly as extensions' own already-correct code
    already does it for two of the three columns. Adding a blanket
    schema default would paper over the same missing-explicit-value
    problem at a different layer, for no evidenced benefit.
- **Fix applied**: three explicit assignments added to `$ip_data` at the
  end of `preparePost()`, mirroring `ExtensionsController::execAdd()`'s
  own explicit values:
  ```php
  $ip_data['password'] = '';
  $ip_data['trunk'] = 'no';
  $ip_data['lastms'] = 0;
  ```
- **Validation performed**: a real trunk created through the HTTP form
  (`POST /index.php/default/trunks/add`) persisted successfully; the
  resulting `peers` row was inspected directly and confirmed correct
  (`password=''`, `trunk='no'`, `lastms=0`, `secret`/`canal`/`peer_type`
  all correct and untouched by this fix); edit and delete both exercised
  afterward.

---

## Three further blockers found during live validation (not in TASK-0014's original list)

Each was stopped on and reported before any fix was applied, per the
task's item 6 instruction. All three were approved by the user before
being fixed. All three are in the exact same create/edit write paths
P0-1/P0-2 already target — none expand scope into a different
subsystem, except where explicitly noted and left unfixed below.

### Blocker 3 — `count()` on a `fetch()`-`false` result (duplicate-name check)

- **File/method**: `TrunksController::addAction()` line 221 and the
  identical pattern in `editAction()` line ~428:
  ```php
  $newId = Snep_Trunks_Manager::getName($_POST['callerid']);
  if (count($newId) > 1) { ... }
  ```
- **Exact failure**: `Snep_Trunks_Manager::getName()`
  (`snep/lib/Snep/Trunks/Manager.php:210`) returns
  `Zend_Db_Statement::fetch()`'s raw result — `false` when no trunk with
  that callerid exists yet (the normal case for *any* new trunk), or a
  single 2-key associative array (`id`, `callerid`) when one does.
  `count(false)` is a PHP 8 fatal `TypeError` (`count()` requires
  `Countable|array`). Reproduced live: fires on every create attempt
  where the callerid doesn't already collide — i.e. every legitimate new
  trunk.
- **Why independent from P0-1/P0-2**: a different mechanism entirely
  (return-type mismatch vs. missing schema-required columns), in a
  different manager class, fatal-ing at a different point in the
  request (before the DB write is even attempted).
- **Root-cause note**: `count() == 2` on the "found" case only ever
  "worked" by coincidence — it was counting the found row's 2 selected
  columns, not the number of matching rows. The real intent was always a
  plain existence check.
- **Fix applied**: replaced `count($newId) > 1` with `$newId` (a plain
  truthiness check) in both `addAction()` and `editAction()` — preserves
  the exact original intent (row found vs. not) without depending on the
  coincidental column-count.
- **Validation**: real trunk create succeeded past this check; a second
  create attempt with the same callerid was not separately tested in
  this task (out of scope — this task validates the base lifecycle, not
  every validation branch), but the fix is a direct, narrow,
  behavior-preserving correction of a return-type mismatch, not new
  logic.

### Blocker 4 — PHP `false` binds as `''` (not `'0'`) via PDO, failing `BOOLEAN`/`int` columns

- **File/method**: `TrunksController::preparePost()`, three assignments:
  ```php
  $trunk_data['dtmf_dial']       = ($post['dtmf_dial'] === "dtmf_dial" ? true : false);
  $trunk_data['map_extensions']  = ($post['map_extensions'] === "map_extensions" ? true : false);
  $trunk_data['reverse_auth']    = ($post['reverse_auth'] === "reverse_auth" ? true : false);
  ```
  plus two closely adjacent, same-root-cause instances found while
  fixing these: `time_initial_date` (fell back to `""` instead of
  `NULL`, unlike its sibling `time_total` two lines above which already
  correctly used `NULL`) and `telco` (took the raw posted value,
  `""` when unset, verbatim).
- **Exact failure**, reproduced live, one column at a time as each was
  fixed (a chained sequence, same pattern as P0-2's three columns):
  ```
  SQLSTATE[22007]: Invalid datetime format: 1366 Incorrect integer value: '' for column trunks.dtmf_dial
  ... then trunks.time_initial_date ... then trunks.telco
  ```
- **Root cause**: `Zend_Db_Adapter::insert()`/`update()` bind values via
  PDO positional parameters (`$stmt->execute($bind)`) with no explicit
  PDO type. PDO's implicit binding stringifies a bound PHP `bool` —
  `(string)false === ''`, `(string)true === '1'`. MariaDB's strict mode
  accepts `'1'` for a `BOOLEAN`/`TINYINT` column but rejects `''` for
  any integer-family column — which is exactly why only the
  `false`/unchecked case ever surfaced this, never the `true`/checked
  one. `time_initial_date`/`telco` hit the identical strict-mode
  rejection via an explicit `""` literal instead of PDO's coercion, but
  the underlying failure (`''` bound to an `int`/`BOOLEAN` column) is
  the same class of problem, in the same function, discovered in the
  same investigative pass.
- **Why independent from P0-1/P0-2/Blocker 3**: a distinct mechanism
  (PDO's implicit scalar-to-string binding, not a missing column or a
  return-type mismatch), though in the same write path — reported and
  approved before fixing, per item 6, rather than folded in silently.
- **Fix applied**:
  ```php
  $trunk_data['dtmf_dial']       = ($post['dtmf_dial'] === "dtmf_dial" ? 1 : 0);
  $trunk_data['map_extensions']  = ($post['map_extensions'] === "map_extensions" ? 1 : 0);
  $trunk_data['reverse_auth']    = ($post['reverse_auth'] === "reverse_auth" ? 1 : 0);
  $trunk_data['time_initial_date'] = ($post['tempo'] === "tempo" ? $trunk_data['time_initial_date'] : NULL);
  $trunk_data['telco'] = ($post['telco'] === "" ? NULL : $post['telco']);
  ```
  `1`/`0` bind as themselves (no stringification ambiguity); `NULL`
  matches `time_total`'s already-correct, already-nullable handling
  (both `time_initial_date` and `telco` are `int(...) DEFAULT NULL` in
  `schema.sql` — genuinely nullable columns, so `NULL` is the column's
  own correct "not set" value, not a new default being invented).
- **Validation**: a real trunk created through the HTTP form persisted
  successfully with `dtmf_dial=0`, `map_extensions=0`, `reverse_auth=0`,
  `time_initial_date=NULL`, `telco=NULL` — confirmed by direct
  inspection of the resulting row.

### Blocker 5 — `mysql_escape_string()` removed since PHP 7 (blocks `editAction()`)

- **File/method**: `TrunksController::editAction()` line 314:
  ```php
  $idTrunk = mysql_escape_string($this->getRequest()->getParam("trunk"));
  ```
- **Exact failure**: `PHP Fatal error: Uncaught Error: Call to undefined
  function mysql_escape_string()` — this function was removed entirely
  in PHP 7.0 (deprecated since 5.5). Fires on every `GET
  /index.php/default/trunks/edit/trunk/<id>`, before the form can
  render at all.
- **Why independent, and why only this one call site was touched**:
  the identical call exists in **4 other files unrelated to trunks**
  (`RouteController.php` ×2, `PickupGroupsController.php`,
  `Snep_Parameters_Manager.php`) — confirmed via
  `grep -rn "mysql_escape_string"`. Fixing all 5 would mean editing
  three controllers and one manager class this task has no reason to
  touch, well beyond "restore trunk CRUD." Reported before fixing, per
  item 6; approved to fix **only** the trunk call site, leaving the
  other 4 as documented, unrelated, pre-existing PHP 8 compatibility
  debt for a separate future task.
- **Fix applied**: replaced the removed function with
  `Zend_Db_Adapter_Abstract::quote()` — already present and used
  throughout this codebase's `Zend_Db` layer — and adjusted the SQL
  text accordingly, since `quote()` returns an already-quoted string
  (unlike `mysql_escape_string()`, which only escaped, leaving the
  surrounding literal quotes to the caller):
  ```php
  $idTrunk = $this->getRequest()->getParam("trunk");
  $trunk = $db->query("select * from trunks where id=" . $db->quote($idTrunk))->fetch();
  ```
  Same escaping/quoting guarantee, same generality (no new assumption
  that the ID is always numeric), smallest possible change.
- **Validation**: `GET /index.php/default/trunks/edit/trunk/<id>`
  returns `200` and renders the existing trunk's data correctly (spot-
  checked: the edit form's callerid input carries the exact value
  stored in the database).

---

## UI lifecycle validation (real HTTP, not direct SQL)

All steps performed against the actual running app, in order, in one
continuous session:

1. **Add form renders**: `GET /index.php/default/trunks/add` → `200`.
2. **Create**: `POST /index.php/default/trunks/add` (technology=sip,
   dialmethod=normal, a clearly-marked fixture secret
   `task0015a-fixture`) → `302`. `peers`/`trunks` rows inspected
   directly and confirmed correct on every column touched by this
   task's fixes.
3. **List renders it**: `GET /index.php/default/trunks` → `200`, the
   created trunk's callerid present exactly once.
4. **Edit form renders**: `GET /index.php/default/trunks/edit/trunk/<id>`
   → `200`, form pre-populated with the real stored values.
5. **Edit succeeds**: `POST .../trunks/edit/trunk/<id>` with a changed
   callerid → `302`.
6. **List reflects the edit**: new callerid present exactly once, old
   callerid absent.
7. **Delete**: confirmation page renders (`200`), `POST
   .../trunks/remove/id/<id>/name/<name>` → `302`.
8. **List returns to clean state**: `0` matches for the fixture's
   callerid; `trunks`/`peers` tables both confirmed empty via direct
   inspection (the same direct-inspection-as-cross-check pattern used
   throughout this project's prior tasks, not as the primary validation
   path, which was the real UI throughout).

## Regression

- `make smoke`: **16 PASS / 0 FAIL / 0 EXPECTED_LIMITATION**.
- `make call-smoke`: **18/18 PASS** (unrelated to trunks — confirms
  these fixes didn't disturb the existing PJSIP extension path).
- `grep -c "Fatal error" /var/log/apache2/mag-error.log` after the full
  validation run: **0** (container recreated by `make call-smoke`,
  giving a clean log; every fatal error ever logged during this task's
  investigation predates the corresponding fix and is quoted above as
  evidence, not left outstanding).

## Files changed

- `snep/modules/billing/lib/Telcos/Manager.php` — `getAll()` declared
  `static` (P0-1). No other method touched.
- `snep/modules/default/controllers/TrunksController.php` — P0-2's three
  explicit `$ip_data` values; the `count($newId)` → `$newId` truthiness
  fix in both `addAction()`/`editAction()`; the three boolean/nullable-
  int `preparePost()` fixes (`dtmf_dial`/`map_extensions`/
  `reverse_auth`/`time_initial_date`/`telco`); the
  `mysql_escape_string()` → `$db->quote()` fix in `editAction()`.

## Remaining blockers/debt before TASK-0015 (documented, not fixed here)

- **`Telcos_Manager::add()`/`get()`/`remove()`/`update()`** — same
  non-static-called-statically pattern as P0-1's `getAll()`, called
  from `TelcosController.php`/`BillingController.php`. Almost certainly
  fatal under identical conditions; out of this task's scope (not a
  trunk file). A natural, small, separate PHP 8.4 compatibility fix.
- **`mysql_escape_string()` in 4 other files** —
  `RouteController.php` (×2), `PickupGroupsController.php`,
  `Snep_Parameters_Manager.php`. Out of scope for the same reason.
- **KHOMP/VIRTUAL/SNEPSIP/SNEPIAX2 trunk create/edit** — only plain SIP
  (`dialmethod=normal`) was exercised end-to-end in this task's
  validation, matching TASK-0015's own planned starting point
  (TASK-0014 §17). The other technologies share the exact same
  `preparePost()`/`Snep_InterfaceConf` code paths already fixed here
  (no technology-specific branch was touched), so there is no
  evidence-based reason to expect them to behave differently, but they
  were not individually re-verified live in this task.
- **No other independent blocker was found** beyond the three reported
  and fixed above — the full create/edit/delete/list lifecycle for a
  plain SIP trunk now works end-to-end through the real UI with no
  further errors encountered.

TASK-0015 (outbound PJSIP trunk provisioning, per TASK-0014's proposed
scope) can now proceed on top of a genuinely working trunk CRUD
foundation.

---

Stopping here at a commit checkpoint. No PJSIP trunk objects were
implemented. Not beginning TASK-0015.
