# TASK-0023 — Restore Users CRUD on PHP 8.4 and strict SQL

## Status

**Implemented and validated** — see the implementation section at the
end of this document for files changed, evidence, and the final
regression baseline. The investigation below is preserved exactly as
originally written and approved.

---

## Investigation (approved before implementation)

No runtime code, database schema, permission architecture, views,
JavaScript, or tests were modified during this phase. Every finding
below comes from reading the current committed code (`HEAD` =
`0161600`, "feat: restrict Asterisk restart to authorized users") and
from live reproduction against the running `make dev` environment,
including two new, isolated PHP scripts calling
`Snep_Users_Manager::add()` directly and several real HTTP requests
through the actual `UsersController` (list, add, edit, bond, permission
— grant and removal). One test permission row was created on the
seeded `admin` user via the real permission form during this
investigation and removed immediately afterward; the database now
matches its pre-investigation state (`admin`, id=1, `users_permissions`
empty). No new users were left behind. Stopping here — awaiting
approval before any implementation.

Goal: restore the Users create/list/edit/delete lifecycle through the
real SENMA UI under PHP 8.4 + strict MariaDB. **Not** an authentication,
profile, permission, or RBAC redesign.

---

## 1. Reproduction of the two known blockers, from the current clean tree

### Blocker 1 — `UsersController::addAction()`

- **URL**: `POST /index.php/default/users/add`
- **Request**: real authenticated admin session, `name=task0023-repro`,
  `password=Repro123!`, `email=repro@example.test`, `profile_id=1`
  (the only existing profile).
- **HTTP status**: `500`
- **Exact error**:
  ```
  PHP Fatal error:  Uncaught TypeError: count(): Argument #1 ($value)
  must be of type Countable|array, false given in
  /var/www/html/snep/modules/default/controllers/UsersController.php:90
  ```
- **Call path**: `UsersController::addAction()` line 90
  (`count($name_exist) > 1`) ← `$name_exist =
  Snep_Users_Manager::getName($dados['name'])` ← `Snep_Users_Manager::
  getName()` (`snep/lib/Snep/Users/Manager.php:234`) returns
  `$stmt->fetch()`, which is `false` when no existing row matches the
  submitted name.

### Blocker 2 — `Snep_Users_Manager::add()`

Reproduced in isolation (bypassing blocker 1 entirely) by calling
`Snep_Users_Manager::add()` directly from a standalone PHP script using
the app's real bootstrap/DB connection — proving this is a second,
independent failure, not a downstream consequence of blocker 1.

- **Call path**: `Snep_Users_Manager::add()` (`snep/lib/Snep/Users/
  Manager.php:58`, the `$db->insert('users', $insert_data)` call).
- **Exact error**:
  ```
  Zend_Db_Statement_Exception: SQLSTATE[HY000]: General error: 1364
  Field 'dashboard' doesn't have a default value
  at /var/www/html/snep/lib/Zend/Db/Statement/Pdo.php:234
  ```
- **Cause**: `users.dashboard` is `TEXT NOT NULL` with no default
  (confirmed via `DESCRIBE users`, §4); `$insert_data` in `add()` never
  includes a `dashboard` key.

### Blocker 3 (newly found this session) — `UsersController::permissionAction()`, removing all user-specific permissions

Not one of the two "known" blockers, but discovered while validating
this task's own required lifecycle step (item 9-J/K: remove a
permission through the real UI) — see §7 for the full trace and why it
directly blocks this task's own success criteria, not just a tangential
find.

- **URL**: `POST /index.php/default/users/permission`
- **Request**: real authenticated admin session, `user=1`, **no other
  fields** (simulating every permission checkbox unchecked — e.g.
  removing the one-and-only permission a user was just granted).
- **HTTP status**: `500`
- **Exact error**:
  ```
  PHP Warning:  Undefined array key "permission_id" in
  /var/www/html/snep/modules/default/controllers/UsersController.php
  on line 342
  PHP Fatal error:  Uncaught TypeError: array_diff(): Argument #2 must
  be of type array, null given in
  /var/www/html/snep/modules/default/controllers/UsersController.php:342
  ```
- **Call path**: `permissionAction()` line 342
  (`array_diff($currentResourcesGroup, $dados['permission_id'])`) —
  when zero checkboxes are submitted, the `foreach ($_POST as $key =>
  $permission_id) { $dados['permission_id'][$key] = $key; }` loop above
  it never executes (nothing left in `$_POST` after `unset($_POST['user'])`),
  so `$dados['permission_id']` is never set at all, and PHP 8's
  `array_diff()` signature refuses a `null` second argument.

Live-verified via the real form (not a script): granting
`default_asterisk-operations_write` to the seeded admin via a real
`POST` succeeded (a genuine `users_permissions` row appeared); the very
next `POST` with the same form, checkbox unchecked, is what produced
this 500. The row was **not** removed. Cleaned up via direct SQL
afterward, restoring `users_permissions` to empty.

---

## 2. `UsersController::addAction()` — proven intent

`Snep_Users_Manager::getName($name)` (`snep/lib/Snep/Users/
Manager.php:234`) is a single-row lookup (`$stmt->fetch()`, not
`fetchAll()`): it returns **exactly one** associative array (`['id'=>..,
'name'=>..]`, always 2 keys) if a user with that name exists, or
`false` if none does. There is no other call site for this method.

Tracing what `count($name_exist) > 1` could ever have meant on the old,
pre-PHP-8 runtime this code was written for: `count(false)` was
silently coerced to `0` (with only a deprecation notice, never fatal)
in PHP ≤ 7.x, and a genuine 2-key match array always yields `count()
== 2`. So the check's **two only ever reachable outcomes** were `0 > 1`
(false — no existing user, proceed) and `2 > 1` (true — existing user
found, block with "Name already exists"). **The original intent was a
plain existence check**, expressed through a fragile idiom that
happened to keep working by coincidence of `fetch()`'s fixed 2-column
shape and PHP's old falsy-to-int coercion — not a real "count" of
anything meaningful. This is proven by tracing, not assumed.

**Smallest behavior-preserving replacement**: `$name_exist !== false`
(equivalently `$name_exist === false` for the inverted branch). This
matches `getName()`'s actual, documented return contract exactly, with
no reliance on the array's incidental column count. `!empty($name_exist)`
would produce the identical result here (the array's `id` key is always
a truthy positive integer when present), but `!== false` is the more
precise, self-documenting match to the method's real contract and is
the recommended fix.

---

## 3. Users lifecycle sweep — count()/static/bareword search (scoped)

Searched only `UsersController.php` and `Snep_Users_Manager` (and, once
blocker 3 was found by live testing, its exact code path):

- **`count()` calls**: exactly one in both files combined — the
  already-covered blocker 1. No other `count()` call exists anywhere in
  `UsersController.php` or `Snep_Users_Manager.php`.
- **Static/non-static mismatches**: every manager class
  `UsersController` calls — `Snep_Users_Manager`, `Snep_Profiles_Manager`,
  `Snep_Permission_Manager`, `Snep_Audit_Manager`, `Snep_Queues_Manager`,
  `Snep_Binds_Manager`, `Snep_Extensions_Manager`, `Snep_Breadcrumb`,
  `Snep_Dashboard_Manager` — were checked (several already carry an
  explicit "PHP 8 compatibility: declared static to match actual usage"
  docblock from TASK-0002; the rest were spot-checked directly). Every
  method actually called by the Users controller is declared
  `public static function` (or bare `static function`, equivalent).
  No mismatch found.
- **Bareword constants / removed functions**: none found in either
  file.
- **The independent bug actually found** (blocker 3, §1/§7) was not a
  `count()`/static/bareword pattern — it is the same underlying PHP 8
  *class* of bug (a function that now enforces a strict `array`
  parameter type refusing the `null` an undefined-array-key access used
  to silently produce), just on `array_diff()` instead of `count()`.
  Reported here, before any fix, per this task's own instruction — see
  §7 for why it is not merely tangential to this task's own goal.
- **Non-fatal, in-scope warnings also found** while exercising the full
  lifecycle live (none block a page from rendering, none prevent an
  operation from completing; listed for completeness, not proposed for
  fixing beyond what is unavoidable):
  - `addedit.phtml:51` — `Undefined array key "groupname"` on the
    `<select name="profile_id">`'s own `value="..."` attribute.
    `groupname` is not a real column anywhere on the `users`/`profiles`
    join this form's `$this->user` data ever contains; dead template
    code, cosmetically harmless (the `<select>`'s own `value` attribute
    has no effect on which `<option>` is pre-selected — that's driven
    by the separate per-option `selected` logic below it, unaffected).
  - `addedit.phtml` (add mode) — `$this->user['name']`/`['password']`/
    `['email']`/`['profile_id']`/`['id']` are all read against an unset
    `$this->view->user` (only `editAction()` sets this, `addAction()`
    never does), producing "Trying to access array offset on value of
    type null" warnings on every field on the **add** form specifically.
    Cosmetically harmless (empty string result, matching the intended
    blank-form appearance), but real, in-scope, pre-existing debt.
  - `bond.phtml:39` — `foreach() argument must be of type array|object,
    null given`, because `bondAction()` only sets `$this->view->selected`
    inside its `if ($usersBond) {...}` branch, never in the implicit
    "no bond configured yet" case. Harmless (an empty `<select>` list
    renders correctly regardless), but real, in-scope debt.
  - `Snep/Usuario.php:147` — `Undefined variable $secret_iv` — fires on
    every login, not specific to the Users controller at all; noted
    only because it appeared in the same log window, explicitly **not**
    part of this investigation's scope.

None of the above four warnings block any operation from completing —
distinguished here precisely from the three real blockers, per this
task's own instruction not to treat every warning as a fatal blocker.

---

## 4. `Snep_Users_Manager::add()` and the `dashboard` column

```
DESCRIBE users;
 id          int(11)   NOT NULL  PRI  auto_increment
 name        varchar(45)  NOT NULL
 password    varchar(45)  NOT NULL
 email       varchar(255) NOT NULL
 dashboard   text         NOT NULL   <-- no default
 profile_id  int(11)      NOT NULL  MUL
 created     datetime     NOT NULL
 updated     datetime     NOT NULL

sql_mode: STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
```

The seeded `admin` row (`id=1`, the only real historical user row that
has ever existed in this environment) has **`dashboard = ''`** — a
literal empty string, not `NULL`, not a serialized array, not any kind
of placeholder JSON.

`users.dashboard` is read/written **only** by `Snep_Dashboard_Manager`
(`snep/lib/Snep/Dashboard/Manager.php`), which stores a PHP
`serialize()`'d array of the user's chosen dashboard-widget IDs.
Critically, `Snep_Dashboard_Manager::get()` already, deliberately,
defensively handles a non-array `unserialize()` result:

```php
$array = unserialize($dashboard->dashboard);
if (is_array($array))
    return $array;
else
    return array();
```

Live-tested this session: `unserialize('')` returns `bool(false)` in
this PHP 8.4 build (not a warning-raising malformed-string case, not an
empty array) — `is_array(false)` is `false`, so `get()` cleanly returns
`array()`. **This is exactly, byte-for-byte, the behavior the seeded
admin row already produces today**, and has evidently produced without
issue for as long as this environment has existed (the dashboard/index
flow is exercised by every `make smoke` run and has never failed on
this).

**Conclusion, directly answering the task's own question**: the
smallest, most behavior-preserving fix is an explicit write-site value
— add `'dashboard' => ''` to `Snep_Users_Manager::add()`'s
`$insert_data` array, exactly matching the one piece of real historical
evidence available (the seeded row) and exactly matching what the only
consumer of this column already expects and gracefully handles. **The
schema itself is not wrong** — nothing in this investigation suggests
`dashboard` should be nullable or carry a DB-level default; the
application's own insert code is simply incomplete. No schema change is
proposed or needed.

---

## 5. Full `users` INSERT vs. schema matrix

| Column | NOT NULL, no default? | In current `$insert_data`? | Class |
|---|---|---|---|
| `id` | auto_increment (excluded) | n/a | — |
| `name` | yes | yes (`$user['name']`) | A — already supplied |
| `password` | yes | yes (`md5($user['password'])`) | A — already supplied |
| `email` | yes | yes (`$user['email']`) | A — already supplied |
| `dashboard` | yes | **no** | **E — actual, reproduced blocker (§1/§4)** |
| `profile_id` | yes | yes (`$user['profile_id']`) | A — already supplied |
| `created` | yes | yes (`date('Y-m-d H:i:s')`) | A — already supplied |
| `updated` | yes | yes (`date('Y-m-d H:i:s')`) | A — already supplied |

Every column in `users` is `NOT NULL` with no default (confirmed via
the full `DESCRIBE`, §4) — there are no nullable (class D) or
DB-default (class B) columns in this table at all, and no class C
("implicit legacy value relied on elsewhere") columns beyond `dashboard`
itself. **`dashboard` is the only omitted column, and the only actual
blocker** — this matrix comparison surfaces no additional, previously
unknown INSERT-vs-schema mismatch. Directly answers the task's own
question 3: no, there are no other real strict-SQL blockers in the
`users` INSERT.

---

## 6. Profile assignment trace

A new user's `profile_id` comes directly from the submitted form field
(`<select name="profile_id">` in `addedit.phtml`, populated from
`Snep_Profiles_Manager::getAll()` — currently only the single "default"
profile, `id=1`) — no implicit/default assignment logic exists
elsewhere; whatever the admin selects (or the first `<option>`, if none
is explicitly chosen — the browser's own default `<select>` behavior)
is written verbatim to `users.profile_id`.

No `dashboard`, explicit `users_permissions` rows, or "active/status"
flag are set at creation time beyond what's already covered:
`dashboard` gets the fix in §4; **no explicit per-user permission rows
are ever created at add-time** — a freshly created user starts with
*zero* `users_permissions` rows, inheriting purely whatever its
assigned profile grants via `profiles_permissions` (currently nothing,
since that table is empty in this baseline — TASK-0022 §3). There is no
"status"/"active" column on `users` at all (confirmed via the full
`DESCRIBE`, §4) — every row is implicitly active; the only way to
disable a user's access at all today is to delete the row entirely or
strip its permissions, matching TASK-0022's own finding that there is
no dedicated account-status concept anywhere in this schema. None of
this is changed or proposed for change — documented as-is, per the
task's explicit "do not change semantics" instruction.

TASK-0022's finding is directly reconfirmed here from the creation side:
selecting `profile_id=1` for a brand-new user does **not**, by itself,
grant any effective permission (the profile is empty) and does **not**
grant the `id_user==1` superuser bypass (that is keyed to the literal
seeded row's own primary key, never to any profile choice) — a freshly
created user is exactly as unprivileged as the `restartsmoke-*` fixture
users TASK-0022 already proved this with, using the same `profile_id=1`
by necessity (it's the only profile that exists).

---

## 7. Permissions lifecycle trace

Through the real UI, `UsersController` can currently:

- **Assign a profile** — yes, via the add/edit form's `profile_id`
  `<select>` (unaffected by any of the three blockers).
- **Assign a user-specific permission** — **yes**, live-verified this
  session via a real `POST /users/permission` with a checked box:
  produces a genuine `users_permissions` row
  (`permission_id='default_asterisk-operations_write', allow=1`)
  through `Snep_Permission_Manager::addPermissionUser()`. Not blocked
  by any of the three bugs.
- **Remove a user-specific permission** — **partially**. Unchecking
  *one* box among several still-checked boxes takes the same code path
  as a normal save (`$dados['permission_id']` is still a real, non-empty
  array — just missing one key) and is not affected by blocker 3.
  **Unchecking the *last* remaining box (or saving with nothing ever
  checked) is exactly blocker 3** (§1/§3) — the single most relevant
  case for this task's own integration test (§10, TASK-0022 item 10:
  grant the one operational permission, then remove it), since a
  freshly created test user with exactly one granted permission has, by
  construction, nothing else to leave checked.
- **Persist `users_permissions` rows** — yes, both directions, subject
  to the above.

This matters precisely because TASK-0022 now depends on granting (and,
for a complete integration proof, revoking) a real permission on a
genuinely non-superuser account — confirmed here that the grant half
already works today, and the revoke half is blocked by blocker 3,
directly motivating why blocker 3 is flagged for inclusion in this
task's approved scope rather than deferred as unrelated (§15 discusses
the stop-condition framing explicitly).

---

## 8. Test fixture design

Mirrors TASK-0022's own already-proven, collision-safe pattern, with
one change now made possible: **once the three blockers above are
fixed, the real Users UI itself becomes the fixture-creation mechanism**
— superseding TASK-0022's own direct-SQL fallback (which was only ever
a workaround for these exact bugs, explicitly documented as such at the
time).

Planned validation fixture: one user, e.g. `task0023-restricted`
(collision-checked against existing `users.name` before creation,
exactly like every other smoke script in this project), `profile_id=1`
(the only profile), created **through the real add-user HTTP form**
once blocker 1+2 are fixed. No production data is touched; the seeded
`admin` (`id=1`) is never overwritten, matching this project's
established convention throughout every prior smoke script. Full
cleanup (delete the user, any `users_permissions` rows, any
`users_queues_permissions` rows) planned via the real `removeAction()`
HTTP flow where possible, falling back to direct SQL only if
`removeAction()` itself is found to have a problem (not observed in
this investigation — see §12).

---

## 9. Expected lifecycle validation — current status of each step

Verified live this session where it does not depend on the blockers;
reasoned from precise code tracing plus the proven fixes elsewhere:

| Step | Status today | Notes |
|---|---|---|
| A. Users list renders | **Works** (verified: `GET /users` → 200, real data) | |
| B. Add form renders | **Works** (verified: `GET /users/add` → 200) | Cosmetic-only warnings, §3 |
| C. Create restricted user | **Blocked** — blocker 1, then blocker 2 | Fix: §2, §4 |
| D. List shows user | Will work once C works (same `indexAction`, unaffected by any blocker) | |
| E. Login as new user succeeds | Will work once C works — `add()` already correctly `md5()`-hashes the password; login itself uses the same `AuthController` flow already proven throughout TASK-0021/0022 | |
| F. User does NOT have admin bypass | Structurally guaranteed — `id_user==1` is permanently taken by the seeded row; MariaDB `AUTO_INCREMENT` never reissues an in-use id (already observed across TASK-0022's own fixtures, ids 3–8, never colliding with 1) | |
| G. Edit user | **Works today** (verified: `GET /users/edit/id/1` → 200, correct pre-filled fields including the password hash; POST path traced, no bug found) | |
| H. Assign `default_asterisk-operations_write` | **Works today** (verified live via the real form, §1/§7) | |
| I. Verify permission takes effect | Already fully proven in TASK-0022 (`userCanOperateAsterisk()`) | |
| J. Remove permission | **Blocked** — blocker 3 (§1/§7), specifically the last-checkbox-unchecked case | Fix: §7 |
| K. Verify permission removal takes effect | Will work once J works (same `userCanOperateAsterisk()` re-check, already proven reactive to `users_permissions` state) | |
| L. Delete user | **Works today** (traced in full, §12; not live-tested against a real non-admin user in this session since none could yet be created, but the code path is bug-free and independent of all three blockers) | |
| M. List returns to clean state | Trivial once L works | |

No step required inventing new UI behavior — every one of A/B/D/F/G/H/I/K/L/M
is either already proven or a direct, mechanical consequence of fixing
the three identified bugs. The §9 stop condition ("if the existing UI
does not expose one of these operations as expected: STOP") was not
triggered — the UI already exposes every required operation; three
specific bugs prevent three specific steps from completing.

---

## 10. TASK-0022 integration test plan

Once blockers 1–3 are fixed, the exact sequence TASK-0022's own item 10
describes becomes directly testable through the real UI for the first
time:

1. Create `task0023-restricted` via the real add-user form.
2. Log in as it; `POST restart-dispatch` (valid CSRF, per TASK-0022) →
   `403` (no permission yet).
3. As admin, grant `default_asterisk-operations_write` to
   `task0023-restricted` via the real permission form (proven working
   today, §7).
4. As `task0023-restricted`: `POST restart-dispatch` → accepted, in the
   controlled dev environment, exactly like TASK-0022's own
   `restartsmoke-authorized` fixture already proved (that fixture used
   a direct-SQL-inserted `users_permissions` row; this step proves the
   identical effect when the row is created through the real UI form
   instead).
5. As admin, remove the permission via the real form (**this is
   exactly blocker 3** — requires the fix).
6. As `task0023-restricted`: `POST restart-dispatch` → `403` again.

This is the concrete proof that Users CRUD and permission persistence
actually integrate with TASK-0022's authorization boundary end-to-end,
not merely that each piece works in isolation. `restart-smoke` itself
is **not** proposed to depend permanently on this fixture — TASK-0022's
own `restartsmoke-unauthorized`/`restartsmoke-authorized` direct-SQL
fixtures already cover the authorization boundary adequately and
remain the right mechanism for that suite's own ordinary, unattended
runs; this integration sequence is a one-time (or `users-smoke`-scoped,
if a dedicated suite is later justified) proof that the *creation path*
itself also produces a working permission, not a permanent dependency.

---

## 11. Password handling trace

- **Create**: `Snep_Users_Manager::add()` always does `md5($user['password'])`
  — unconditional hashing of whatever plaintext the form submitted. No
  PHP 8 issue found.
- **Edit, unchanged**: `addedit.phtml`'s password `<input>` is
  pre-filled with `value="<?php echo $this->user['password']; ?>"` — on
  edit, this is the **existing 32-character MD5 hash** read straight
  from the DB (live-verified: `GET /users/edit/id/1` returned
  `value="55a99d0bdb9dbcd964e12dfd43638800"`, the admin row's real
  stored hash). `editAction()` then checks `strlen($dados['password'])
  != 32` — if the admin never touches the field, it comes back as the
  same 32-char string, the length check is false, and the hash is
  written back unchanged (no double-hashing). Fragile (a plaintext
  password that happens to be exactly 32 characters would be
  misidentified as "already hashed" and stored as literal plaintext),
  but this is pre-existing, working-as-designed legacy behavior, not a
  PHP 8 blocker — **no change proposed**, per the task's explicit
  instruction not to redesign hashing.
- **Edit, changed**: a submitted password whose length ≠ 32 gets
  `md5()`'d before `Snep_Users_Manager::edit()`'s `UPDATE`. No PHP 8
  issue found (`Snep_Users_Manager::edit()`'s `$update_data` array is
  fully static-safe, no `count()`/type-strictness risk).
- **Login after each state**: unaffected by anything in this
  investigation — `AuthController::loginAction()` (unchanged since
  TASK-0021/0022) is the single, already-proven login path every
  fixture in this project already relies on.

No password-hashing PHP 8 blocker was found; the §11 stop condition was
not triggered.

---

## 12. Delete semantics trace

`UsersController::removeAction()`'s `POST` branch, in order:

```
Snep_Users_Manager::removeRecovery($id)       -- DELETE password_recovery WHERE user_id=$id
Snep_Users_Manager::removePermission($id)     -- DELETE users_permissions WHERE user_id=$id
Snep_Users_Manager::removeQueuesPermission($id) -- DELETE users_queues_permissions WHERE user_id=$id
Snep_Binds_Manager::removeBond($id)           -- DELETE core_binds WHERE user_id=$id
Snep_Users_Manager::remove($id)               -- DELETE users WHERE id=$id
```

Every one of these is a simple, already-static-correct `$db->delete()`
call wrapped in its own `beginTransaction()`/`commit()`/`rollBack()` —
no `count()`, no strict-typed built-in receiving a possibly-`null`
value, no PHP 8 concern found anywhere in this chain. **No sessions
table or session-store is touched at all** — consistent with
TASK-0022's own §19 finding that this application has no
session-revocation mechanism anywhere: if a deleted user had an active
PHP session, it remains valid (Zend_Auth identity still present in that
session's storage) until it naturally expires or the browser logs out —
a pre-existing property of the whole application, not something this
task changes, redesigns, or needs to. `core_binds_exceptions` rows (the
"bond exceptions" list) are **not** cleaned up by `removeAction()` at
all — a pre-existing gap, noted for completeness, not a PHP 8 blocker,
not proposed for a fix here (out of scope: it is a data-hygiene
question, not a lifecycle-breaking bug — no code path fails because of
it).

---

## 13. Security boundaries

Nothing in the proposed fixes (§2, §4, §7) touches authentication,
CSRF, or TASK-0022's authorization check in any way — all three fixes
are narrowly scoped to `UsersController.php` and
`Snep_Users_Manager.php`, restoring existing intended behavior exactly
as traced, never adding a new bypass, test-only shortcut, or weakening
any existing check. `Snep_AuthPlugin`, `Snep_PermissionPlugin`,
`SystemstatusController::userCanOperateAsterisk()`, and
`Snep_Permission_Manager` are not proposed to change at all.

---

## 14. Regression plan

Once implemented: `make smoke`, `make call-smoke`, `make trunk-smoke`,
`make transport-smoke`, `make restart-smoke`, against the current
baselines (16/0, 18/18, 23/23, 63/63, 37/37). Confirm zero new PHP
Fatal Errors, confirm admin's own behavior is unchanged (still bypasses
everything via `id_user==1`, still logs in and uses every existing
flow identically), and confirm TASK-0022's own `restart-smoke`
authorization section still passes unchanged (its own fixtures remain
direct-SQL, per §10 — not migrated to depend on the newly-fixed UI
path, keeping that suite's existing, already-proven independence from
this task).

---

## 15. Stop conditions — assessed

- **User creation needs schema redesign** — no; `dashboard = ''` is a
  write-site fix, not a schema change (§4). Not triggered.
- **Profile/permission UI is fundamentally broken** — no; two of three
  bugs are narrow, single-line-cause issues in `UsersController.php`
  itself, and the underlying `Snep_Permission_Manager`/
  `profiles_permissions`/`users_permissions` data layer (already proven
  sound in TASK-0022) is untouched and correct. Not triggered.
- **Password handling requires a security-model rewrite** — no (§11).
  Not triggered.
- **Another independent Users bug appears** — **yes, one did** (blocker
  3, §1/§7). Per this task's own instruction ("report it before fixing
  unless it is unavoidable to reproduce the known P0s"): reported here,
  not fixed. It is *not* required to reproduce the two originally-known
  P0s, but it *is* required for this task's own item 9 (J/K) and item
  10 validation to be achievable at all — flagged explicitly for a
  separate, deliberate approval decision (see the answers below), not
  silently folded in or silently ignored.
- **Session revocation becomes necessary** — no; documented as
  pre-existing, unchanged, out of scope (§12). Not triggered.
- **Broad RBAC changes become unavoidable** — no; every fix is narrowly
  scoped to `UsersController.php`/`Snep_Users_Manager.php`. Not
  triggered.

---

## 16. Explicitly deferred

RBAC redesign; removal of the `id_user == 1` bypass; MFA; SSO;
password-policy redesign; general session revocation; an audit-log
framework (the existing `Snep_Audit_Manager` calls already present in
`UsersController` are sufficient and unchanged); profile-model
redesign; schema normalization; API tokens. Also explicitly not
addressed: the four cosmetic, non-blocking warnings found in §3, and
the `core_binds_exceptions` cleanup gap found in §12 — real, minor,
pre-existing debt, documented, not fixed.

---

## 17. Answers

1. **What exactly should replace the broken `count()` logic?**
   `$name_exist !== false` (or the inverted `=== false`), matching
   `Snep_Users_Manager::getName()`'s actual, traced return contract —
   a plain existence check, not a count of anything (§2).
2. **What exact initial value should `dashboard` receive?** The literal
   empty string `''`, matching the seeded admin row's own historical
   value and exactly what `Snep_Dashboard_Manager::get()`'s existing
   defensive `is_array(unserialize(...))` check already expects and
   gracefully handles (§4).
3. **Are there any other real strict-SQL blockers in `users` INSERT?**
   No — the full column-by-column matrix (§5) shows every other column
   already supplied; `dashboard` is the only omission and the only
   blocker.
4. **Can the current Users UI create a genuinely restricted user?** Not
   yet — blocked by blockers 1 and 2 (§1). Once both are fixed
   (narrowly, per §2/§4), yes: the resulting user has no permissions,
   no superuser bypass, and behaves exactly like TASK-0022's own
   direct-SQL fixtures (§6/§9).
5. **Can it assign/remove `default_asterisk-operations_write` without
   new UI work?** *Assign*: yes, already works today, live-verified
   (§7). *Remove*: only partially — removing one of several still-checked
   permissions already works; removing the *last* one (the exact case
   this task's own integration proof needs, §10) is blocked by blocker
   3, found during this investigation (§1/§7) and flagged for an
   explicit approval decision rather than assumed in-scope.
6. **What exact files need to change?**
   `snep/modules/default/controllers/UsersController.php` (the
   `count()` fix at line 90, §2; and — pending explicit approval — the
   `array_diff()`/`array_key_exists` restructuring at line 342, §7) and
   `snep/lib/Snep/Users/Manager.php` (the `dashboard` write-site fix in
   `add()`, §4). No other file requires a change to restore the
   lifecycle.
7. **Does TASK-0023 require schema changes?** No — every fix is an
   application-code write-site correction; the schema itself is not
   wrong (§4/§5).

STOP after this investigation report. Do not implement until explicitly
approved.

---

## Implementation (approved, validated)

### Summary of the three fixes

1. **`UsersController::addAction()` — blocker 1 (originally known)**.
   `count($name_exist) > 1` (a `TypeError` on `count(false)` under PHP
   8) replaced with `$name_exist !== false`, exactly matching
   `Snep_Users_Manager::getName()`'s real single-row-`fetch()`
   contract (§2 of the investigation). No broadening of the
   username-existence logic — same method, same call site, same
   downstream behavior for both outcomes.
2. **`Snep_Users_Manager::add()` — blocker 2 (originally known)**.
   Added `'dashboard' => ''` to the insert array, matching the seeded
   `admin` row's own historical value and exactly what
   `Snep_Dashboard_Manager::get()`'s existing `is_array(unserialize(...))`
   fallback already expects (§4). No schema default added, `dashboard`
   remains `NOT NULL` with no default, serialization behavior
   unchanged.
3. **`UsersController::permissionAction()` — blocker 3 (found during
   investigation, approved for this task by explicit instruction)**.
   The zero-checkboxes-submitted case (`$dados['permission_id']`
   legitimately absent, not malformed input) is now branched explicitly:
   `array_key_exists('permission_id', $dados)` gates whether the
   normal `array_diff()`/`array_merge()` sequence runs, or whether the
   codebase's own already-written — but previously unreachable —
   "Caso se exclua todas as permissões" (delete everything) branch
   runs instead. A second, necessary correction found while verifying
   this fix reaches that branch safely: `$permissionUser` was only ever
   assigned inside a conditional (`if (!empty($currentResourcesUsers))`)
   and would itself be undefined — and therefore fatal `array_merge()`
   under PHP 8 the same way — for a user with *no* pre-existing
   custom permissions at all. Fixed with a single defensive
   `$permissionUser = array();` default before that conditional,
   overwritten unchanged whenever real data exists. Neither change
   alters the permission model: an unchecked permission still becomes
   an explicit `allow=0` deny-override row in `users_permissions` (the
   pre-existing convention, unchanged — see the permission-removal
   evidence below), never a bare `DELETE`.

### Files changed

- `snep/modules/default/controllers/UsersController.php` — fixes 1 and
  3.
- `snep/lib/Snep/Users/Manager.php` — fix 2.
- `docs/tasks/0023-users-crud-php84-strict-sql.md` — this document.

No other files were touched. No schema changes. No changes to
`Snep_PermissionPlugin`, `Snep_Menu`, `Snep_Permission_Manager`,
`Snep_Profiles_Manager`, or `SystemstatusController`/
`Snep_Asterisk_Operations` (TASK-0022's authorization boundary).

### UI lifecycle evidence (all 20 steps, real HTTP requests, admin session unless noted)

1. `GET /users` → `200`, real list.
2. `GET /users/add` → `200`.
3. `POST /users/add` (`task0023-restricted`, `profile_id=1`) → `302`
   (previously `500` on both blocker 1 and, once past that, blocker 2
   — both now fixed; confirmed live, in that order, during
   investigation).
4. List → contains `task0023-restricted`.
5. `POST /auth/login` as `task0023-restricted` → `302`.
6. `GET /extensions` as that user → `302` to
   `/index.php/permission/error` — confirms no `id_user==1` bypass
   (MariaDB `AUTO_INCREMENT` assigned id `9`, never reissuing `1`).
7. `POST restart-dispatch` (valid CSRF, no permission) → `403`.
8. Admin: `POST /users/permission` for user 9,
   `default_asterisk-operations_write=on` → `302`.
9. `users_permissions` row confirmed present (`id=5, user_id=9,
   permission_id='default_asterisk-operations_write', allow=1`) — SQL
   used only as supporting evidence, per instruction; the primary
   confirmation was the successful `302` from the real form submission
   plus step 10's own functional proof.
10. As `task0023-restricted`: `POST restart-dispatch` → `{"dispatched":
    true,...}`, polled to `RUNNING` within 9 seconds — a real,
    controlled Asterisk restart, dispatched by a non-superuser account
    created entirely through the real UI.
11. Admin: `POST /users/permission` for user 9, **zero** fields besides
    `user=9` (every checkbox unchecked — this user's only permission
    was the one just granted) → `302`, **not** `500` — blocker 3's
    fix confirmed directly, in the exact real-world shape TASK-0022's
    own integration test needs.
12. No crash — see 11.
13. Confirmed: the permission page's checkbox for
    `default_asterisk-operations_write` is no longer checked (primary
    evidence). Supporting SQL evidence: a *new* row (`id=6, allow=0`)
    exists alongside the original `id=5, allow=1` row —
    `Snep_Permission_Manager::removePermissionUser()`'s own
    pre-existing, unchanged behavior is to record an explicit deny
    override, not delete the earlier row; the *effective* permission
    (what `userCanOperateAsterisk()` actually evaluates) is correctly
    "no" either way.
14. As `task0023-restricted`: `POST restart-dispatch` (valid CSRF) →
    `403` again.
15. Admin: `POST /users/edit/id/9`, changed `email` only → `302`.
16. Password-preserve: the edit form's password field was scraped
    pre-filled with the real 32-character hash and resubmitted
    unchanged; the DB row's `password` column was byte-identical
    before and after; a fresh login with the *original* plaintext
    password still succeeded (`302`) immediately after this edit.
17. `POST /users/edit/id/9` with a new plaintext password → `302`; old
    password login now fails (`200`, login form re-rendered with an
    error, not a redirect); new password login succeeds (`302`,
    followed by real authenticated access to `/systemstatus`, `200`).
18. Admin: `POST /users/remove` for id 9 → `302`.
19. `users_permissions` rows for user 9: `0` remaining (both the
    `allow=1` and `allow=0` rows removed by `removePermission()`,
    called from `removeAction()`); `users` row for id 9: `0` remaining.
20. List no longer contains `task0023-restricted`;
    `users` table back to exactly `{id=1, admin}`.

No step required any UI behavior beyond what already existed — every
step is a real, unmodified form/endpoint already present before this
task, now reachable because the three narrow fixes removed the fatals
blocking three specific paths through it.

### Zero new PHP fatal errors from the fixes themselves

The app log contained exactly 4 pre-existing fatal-error entries
(timestamped *before* any code change this session: the two originally
known blockers, reproduced once each during investigation, plus two
occurrences of an unrelated flake — see below) at the start of
implementation. After all 20 lifecycle steps completed successfully,
the count remained exactly 4 — no new entry was added by any of the
three fixes or by exercising the full lifecycle.

### Regression results

- `make call-smoke`: 18/18
- `make trunk-smoke`: 23/23
- `make transport-smoke`: 63/63
- `make restart-smoke`: 37/37 — TASK-0022's full authorization suite
  (unauthenticated rejection, restricted-user rejection for both
  modes with a real held-open call, CSRF independence, non-superuser
  explicit-permission dispatch, `id_user==1` bypass with
  `profiles_permissions` still at 0 rows) passed unchanged, confirming
  this task did not alter TASK-0022's authorization behavior.
- `make smoke`: **intermittently failed on an unrelated, pre-existing
  bug**, then passed clean. See below.

#### `make smoke` flake — pre-existing, unrelated, not fixed

Four consecutive `make smoke` runs each failed with exactly one
`500` on a different, effectively random page per run (`reports`, then
`trunks`+`systemstatus`, then `systemstatus`, then `trunks`) — never
a Users-related page, never the same page twice in a row, never
correlated with anything this task changed. Root cause, fully traced:

```
Snep_Request::send_request()  (snep/lib/Snep/Request.php:62-63)
  $raw_response = @file_get_contents($url, 0, $ctx);   -- failure silenced by @
  $headers = self::parseHeaders($http_response_header); -- undefined if the
                                                             request failed
Snep_Request::parseHeaders()  (line 73)
  count($headers)   -- TypeError: count(): Argument #1 ($value) must be
                        of type Countable|array, null given
```

Called from `Snep_Notifications::getAll()`/`getNoView()`
(`snep/lib/Snep/Notifications.php`), invoked unconditionally from the
**shared page layout** (`snep/modules/default/views/layouts/
layout.phtml:111`) on essentially every full-page render — so it can
surface on *any* page, not a Users-specific one. The target URL
(`https://api.opens.com.br/api/v1/...`, from `setup.conf`'s
`itc_address`) is reachable in general (`curl` from inside the app
container returned a fast `404`, not a timeout), but the specific
per-request call apparently fails intermittently (observed roughly 1
in 11 page loads across this session). This is the same *class* of PHP
8 incompatibility as this task's own three fixes (an undefined value
reaching a strictly-typed built-in), but in a completely different,
unrelated subsystem (outbound vendor notifications), newly discovered
by chance during this task's own regression runs — not present in any
of the Users-lifecycle code paths, and not observed in any earlier
task's regression runs in this project's history.

Per explicit instruction: **not fixed, `Snep_Notifications`/
`Snep_Request` not modified.** Documented here as separate,
pre-existing technical debt for a dedicated future task. A bounded
retry policy (up to 5 additional attempts) was applied, exactly like
this project's already-established handling of the other known
environmental flake (the "PJSIP module Running" false-negative
immediately after a container recreate): the very first retry produced
a fully clean `16/0`, `0` new fatal errors — recorded as the
established clean baseline for this task's regression sign-off,
alongside the four failed attempts, transparently, rather than only
reporting the eventual clean run.

### Remaining deferred RBAC / user-management debt

Unchanged from the investigation (§16), plus this session's own new
finding:

- `$_SESSION['id_user'] == "1"` hardcoded superuser bypass — reused,
  not removed.
- `profiles_permissions` remains empty in this baseline — nothing
  seeded.
- The four cosmetic warnings found during investigation (`addedit.phtml`'s
  `groupname`/undefined-`$this->user`-on-add, `bond.phtml`'s
  undefined `$this->selected`) — not fixed, as instructed.
- The `core_binds_exceptions` delete-cleanup gap (§12 of the
  investigation) — not fixed, out of scope.
- **New**: the `Snep_Notifications`/`Snep_Request` outbound-API
  `count(null)` flake (this section, above) — a real, independent,
  pre-existing bug, explicitly not fixed in this task, recommended as
  a dedicated future PHP 8.4 compatibility follow-up given it can
  surface on any page in the application, not just Users.
