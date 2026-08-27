# TASK-0022 — System administration authorization hardening

## Status

**Implemented and validated** — see the implementation section at the
end of this document for files changed, evidence, and the final
regression baseline. The investigation below is preserved exactly as
originally written and approved.

---

## Investigation (approved before implementation)

No runtime code, views, session logic, permission tables, database
schema, or tests were modified during this phase. Findings below come
from reading the current committed code (`HEAD` = `9d517b2`, "feat: add
operational Asterisk restart controls") and from live experiments
against the running `make dev` environment, including creating a
genuinely restricted, non-admin test user and proving — with a real
Asterisk uptime reset as evidence — that it can dispatch a real restart
today. The fixture user was removed afterward; the working tree and
database are otherwise unchanged. Stopping here — awaiting approval
before any implementation.

Goal: determine the smallest safe way to ensure operational system
actions such as Asterisk restart are available only to users actually
authorized for system administration. **This is not a full RBAC
redesign.**

---

## 1. The authentication boundary

**File:** `snep/modules/default/controllers/AuthController.php`,
`loginAction()`.

- Credentials are checked via `Zend_Auth_Adapter_DbTable` against the
  `users` table (`name`/`password` columns, MD5 hash — legacy, unrelated
  to this task, not touched).
- On success: `$auth->getStorage()->write($result->getIdentity())`
  stores the **username string** as the Zend_Auth identity (this is
  exactly what `Zend_Auth::getInstance()->getIdentity()` returns
  everywhere else in the app, e.g. `Snep_Audit_Manager::SaveLog()` and
  TASK-0021's own `logRestart()`).
- Separately, plain `$_SESSION` keys are set: `id_user` (the `users.id`
  primary key — **this exact value is what every privilege check in
  this codebase keys off, not the Zend_Auth identity**), `name_user`,
  `active_user`, `http_authorization` (an encrypted `username:password`
  pair, used elsewhere for API basic-auth — unrelated to this task),
  `uuid`.
- **No `profile_id` is ever stored in the session.** Every permission
  check re-fetches it fresh from the `users` table on every request
  (see §19).

**File:** `snep/lib/Snep/AuthPlugin.php`, `Snep_AuthPlugin::preDispatch()`
(registered unconditionally in `snep/Bootstrap.php:37`, runs before
every request).

- The entire boundary: `if (!$auth->hasIdentity() && ($action !=
  "redefine" && $action != "recuperation")) { redirect to
  default/auth/login }`. No other exceptions. This is the **only** thing
  that prevents an unauthenticated request from reaching
  `SystemstatusController` (or any other controller) today — confirmed
  by reading the plugin and by the fact that TASK-0021's restart actions
  already inherit it correctly (an unauthenticated POST to
  `restart-dispatch` is redirected to login, never dispatches).
- Logout: `AuthController` (not re-read in full this session, unchanged
  since TASK-0003/0021) clears the Zend_Auth identity; `make smoke`'s
  own "logout session invalidation" check already proves a
  post-logout request re-renders the login page, not the dashboard.

---

## 2. The authorization architecture

Two additional plugins run after `Snep_AuthPlugin`, both registered in
`snep/Bootstrap.php`:

```
request
  → Snep_AuthPlugin::preDispatch()        -- "are you logged in at all?"
  → Snep_PermissionPlugin::preDispatch()  -- "is this action allowed?"
  → controller action
```

**File:** `snep/modules/default/model/PermissionPlugin.php`,
`Snep_PermissionPlugin::preDispatch()` (registered at
`Bootstrap.php:167`).

```php
$group = Snep_Profiles_Manager::getIdProfile($_SESSION['id_user']);
if ($_SESSION['id_user'] == "1") return;               // (A)
if (Snep_Permission_Manager::checkExistenceCurrentResource()) {  // (B)
    $type = ($action == 'index') ? 'read' : 'write';
    if ($action is one of: index, add, edit, remove,
        duplicate, multiremove, multiadd) {              // (C)
        $result = Snep_Permission_Manager::get($group, "{module}_{controller}_{type}");
        $user   = Snep_Permission_Manager::getUser($id_user, "{module}_{controller}_{type}");
        if ($user != false) $result = $user;              // per-user override wins
        if (!$result || !$result['allow']) redirect to /error/permission;
    }
}
```

Three independent gates all have to be true before any check actually
runs:

- **(A)** — `$_SESSION['id_user'] == "1"` unconditionally returns,
  skipping every check below. This is the real "admin" mechanism — see
  §7.
- **(B)** — `Snep_Permission_Manager::checkExistenceCurrentResource()`
  (`snep/lib/Snep/Permission/Manager.php`) returns `true` only if the
  **controller name itself** (as parsed from the URL) is a registered
  key in `Snep_Modules::$resources[$module][$controller]` — which is
  populated purely by parsing `snep/modules/default/resources.xml` at
  bootstrap (`Snep_Modules::loadResources()`,
  `snep/lib/Snep/Modules.php`). A controller with no matching
  `resources.xml` entry is **never checked at all**, for any user.
- **(C)** — even if (B) passes, the action name itself must be one of a
  **fixed, hardcoded whitelist**: `index`, `add`, `edit`, `remove`,
  `duplicate`, `multiremove`, `multiadd`. Any other action name (e.g.
  `restart-dispatch`, `restart-status`) is never checked, regardless of
  whether the resource is registered.

**Data layer:** `Snep_Permission_Manager` (same file) wraps two tables
directly, no ORM/Acl abstraction beyond this:

- `profiles_permissions` (`profile_id`, `permission_id`, `allow`) — the
  group/profile-level grant.
- `users_permissions` (`user_id`, `permission_id`, `allow`) — a
  per-user override that supersedes the profile grant when present
  (`getUser()` checked, and if non-`false`, replaces `$result`).

`permission_id` is a free-form string matching the
`{module}_{controller}_{read|write}` shape resources.xml produces (e.g.
`default_pjsip-transports_write`) — **no foreign key or enum**; any
string works, so a new permission never requires a schema change (see
§12).

**Menu visibility** (`Snep_Menu::getPermission()`,
`snep/lib/Snep/Menu.php`) is a **separate, UI-only** consumer of the
exact same `Snep_Permission_Manager::get()/getUser()` pair, checking
only the `_read` variant, for the same id=1 bypass. It decides whether a
`<li>` renders in the sidebar. **It has no bearing on whether a request
actually reaches a controller action** — confirmed by reading the code
(rendering is the only side effect) and by this task's own live test
(§9): a URL can be requested directly regardless of whether any menu
link points at it.

Architecture map:

```
user (users.id, "id_user" in session)
  → profile (users.profile_id, looked up fresh every request)
    → profiles_permissions[profile_id][resource] = allow/deny  (group default)
    → users_permissions[user_id][resource] = allow/deny        (per-user override, wins if present)
  → Snep_PermissionPlugin: enforces the above, but ONLY for
    resources.xml-registered controllers AND ONLY for the
    {index,add,edit,remove,duplicate,multiremove,multiadd} action names
  → Snep_Menu: renders/hides sidebar links using the SAME data,
    read-only, no enforcement effect
```

---

## 3. Permission inventory relevant to this task

Queried live against the current dev database (fresh install this
session):

```
users:               1 row  (admin, id=1, profile_id=1)
profiles:             1 row  (id=1, name="default")
profiles_permissions: 0 rows
users_permissions:    (not separately queried; UsersController's own
                       permissionAction() UI is the only writer, and no
                       user other than admin exists to have one)
```

**There are zero permission grants in the entire system.** The "default"
profile — the only one that exists, and the one any newly-created user
would get — grants nothing.

Resources relevant to "administration," from `resources.xml`:

| Resource id | Group | Read/write sub-resource | Currently assignable via UI? |
|---|---|---|---|
| `users` | `manage` | `write` | Yes (registered) |
| `profiles` | `manage` | `write` | Yes (registered) |
| `pjsip-transports` | `pjsip` | `write` | Yes (registered) |
| `inspector` (label "System Status") | `status` | — (read only) | Yes (registered) — **but see §6, this is a different controller than the one this task is about** |
| *(none)* | — | — | `SystemstatusController` (the actual restart-control page) has **no** `resources.xml` entry at all |

No resource named anything like "system administration" or "Asterisk
operations" exists today. The closest existing concepts are `users`/
`profiles` (user/account management — a different concern from
operating the PBX) and `pjsip-transports` (PJSIP configuration
authorship — adjacent to, but not the same as, restarting Asterisk).

---

## 4. `SystemstatusController` action audit

| Action | Class | Notes |
|---|---|---|
| `indexAction` | A. read-only | CPU/RAM/disk/Asterisk version/uptime. Renders the restart controls block (TASK-0021). |
| `statusbarAction` | A. read-only | Legacy, appears dead (`echo "xxxxxxx"` at the top — pre-existing, not touched). |
| `restartStatusAction` | A. read-only, but operationally sensitive | Reports RUNNING/RESTART_PENDING/RECOVERING/UNAVAILABLE/ERROR — no side effect, cannot dispatch anything. |
| `restartDispatchAction` | C. destructive/privileged | Issues a real `core restart gracefully`/`core restart now` against the real Asterisk instance. |

None of these are resource-registered (§2), so `Snep_PermissionPlugin`
enforces nothing on any of them today, for any user other than the
`id_user==1` bypass making the point moot. **Only `restartDispatchAction`
needs a new authorization gate.** `indexAction` and `restartStatusAction`
should keep their current audience — see §14/§15 for why.

---

## 5. Established server-side permission pattern

The only real, working, DB-backed pattern in this codebase is
`Snep_Permission_Manager::get($profileId, $resourceKey)` +
`Snep_Permission_Manager::getUser($userId, $resourceKey)`, with the
per-user result overriding the profile result when present, and a
missing/falsy result treated as **deny** (`Snep_PermissionPlugin`'s own
`if (!$result || !$result['allow'])`). This is already proven in
production use for every CRUD controller with a `resources.xml` entry.

It cannot be reused **through `Snep_PermissionPlugin` itself** for this
task, for two independent, structural reasons (§2 gates B and C):
registering `SystemstatusController` as a resource would start gating
`indexAction` too (an unwanted regression — see §15), and the plugin's
hardcoded action whitelist would never check `restart-dispatch`/
`restart-status` regardless of registration. **The fix is to call
`Snep_Permission_Manager::get()`/`getUser()` directly from inside
`restartDispatchAction()`**, exactly replicating the plugin's own
deny-by-default, per-user-override-wins logic, against a resource key
of our own choosing — not inventing a new framework, just invoking the
existing data-layer methods directly instead of through a dispatcher
that structurally cannot reach this action name. This is the narrowest
proven pattern available, and the recommended model for TASK-0022.

Confirmed safe under PHP 8.4 (already running in production use by
every existing CRUD controller, no compatibility issues found), does
not rely on menu state (menu code is a separate consumer, §2), and is
not covered by any automated test today (no existing smoke script
exercises a non-admin permission-denied path — this is new ground, see
§21).

---

## 6. Menu permission behavior (TASK-0012) and a naming trap

TASK-0012's fix (`Snep_Menu::getPermission()`) is correct today: it
properly strips the configured base URL before parsing path segments,
so the permission check it performs is no longer silently bypassed.
Re-read in full this session — no further bug found.

**However, a naming trap was found and must be documented precisely**:
the `resources.xml` entry labeled "System Status" (`id="inspector"`)
points at a **completely different controller**,
`InspectorController` (`snep/modules/default/controllers/
InspectorController.php`), which runs `Snep_Inspector::getInspects()`
— a configuration-requirements checker (e.g. "is X installed"), not
the CPU/RAM/Asterisk-version page. `SystemstatusController` (the actual
subject of TASK-0021/0022) has never had a `resources.xml` entry and
has no corresponding menu link at all — it appears to be reached only
as an AJAX-loaded dashboard fragment (`indexAction()`'s own comment:
"Disables layout so jQuery .get() can call pure HTML"). This means:
**even if `Snep_Menu`'s permission filtering were perfect, it would
have no bearing whatsoever on `SystemstatusController`**, since no menu
item points at it to hide. This is exactly the task's own point,
proven precisely rather than assumed: **hiding a button (or never
showing one in the first place) is not, and cannot be, a security
boundary.**

---

## 7. Admin semantics, and reconciling the TASK-0003 finding

**Admin's effective "do anything" behavior comes entirely from the
hardcoded `$_SESSION['id_user'] == "1"` check in
`Snep_PermissionPlugin::preDispatch()` — not from `profile_id`, not
from any `profiles_permissions`/`users_permissions` row, and not from
any other flag.** The same literal `users.id == 1` special case also
appears, independently, in:

- `Snep_Menu::render()`/`renderModule()` (menu-permission bypass, §6).
- `Snep_Profiles_Manager::getUsersProfiles()`/`getUsersnotProfile()`
  (both hardcode `WHERE users.id != 1`, excluding the admin row from
  profile-membership lists and management screens entirely).

This directly reconciles TASK-0003's finding, precisely as the task
asked: the `smoketest` user created in TASK-0003 had `profile_id=1`
(the **profile** row named "default") but a **different `users.id`**
(a freshly inserted row, never `1`). `profile_id=1` and `users.id==1`
are two unrelated numbers that happen to collide in this fresh
install — one is "which permission group," the other is "are you
literally the seeded superuser row." The smoketest user got neither the
bypass (wrong `users.id`) nor any real permission (the "default"
profile grants nothing, confirmed live in §3) — hence its redirect to
`/permission/error` on every admin page. **Reproduced and confirmed
directly this session** with a new, differently-purposed fixture user
(§9): same profile, same zero-grants outcome.

There is no dedicated "is_admin" flag, wildcard permission row, or
special profile anywhere in the schema — the entire admin concept is
this one hardcoded ID comparison, repeated in three call sites.
**Changing that is explicitly out of scope** (§24 — not a full RBAC
redesign); TASK-0022's design deliberately preserves it and reuses the
identical convention for the new restart-specific check (§11), rather
than trying to fix or replace it.

---

## 8. Test fixture: a genuinely restricted user

**Preferred path (A, existing UI) was attempted first and found
broken — documented as separate, unrelated debt, not fixed here:**

1. `UsersController::addAction()` → `Snep_Users_Manager::getName()`
   returns `false` (via `Zend_Db_Statement::fetch()`) when no existing
   user matches, but the controller does `count($name_exist) > 1` on
   that result — a `count()` on `false` is a hard PHP 8.4 `TypeError`
   (previously silently wrong, never fatal, and apparently never
   exercised before this session: this is the actual, live error
   observed, not a theoretical read). **This blocks every user-creation
   attempt through the real UI**, admin or otherwise.
2. Falling back to Option B (`Snep_Users_Manager::add()` called
   directly): also fails — `users.dashboard` is `TEXT NOT NULL` with no
   default, and `add()` never populates it, so the insert itself
   throws under MariaDB strict mode (a Phase 2 category-D legacy
   database-semantics bug, per CLAUDE.md's own classification).

Both are genuine, pre-existing, unrelated bugs, newly discovered by
this investigation because — as far as this project's history shows —
nothing before this session had ever exercised "create a second user"
end to end. **Documented here as separate technical debt for a
dedicated future task, not fixed as part of TASK-0022**, per CLAUDE.md's
explicit bug-and-technical-debt policy.

**Fixture actually used (Option C, direct SQL, justified by the above):**
a single `INSERT INTO users (...) VALUES ('task0022-restricted', <md5
hash>, 'restricted@example.test', '', 1, NOW(), NOW())` — `profile_id=1`
is the only profile that exists, and (§3) it grants nothing. This
satisfies "genuinely restricted, not a renamed admin account": the
fixture has a real, different `users.id`, a real session, and zero
permission rows anywhere.

**Live-tested this session, then removed:**
- Logged in successfully (real session, real `id_user`).
- `GET /default/extensions` → `302` to `/index.php/permission/error`
  (a real, resource-registered admin controller correctly denies it —
  proving the fixture is genuinely unprivileged, not just untested).
- `GET /default/systemstatus` → `200` (matches today's intended-or-not
  behavior, see §15).
- `GET /default/systemstatus/restart-status` → `200`,
  `{"state":"RUNNING",...}`.
- **`POST /default/systemstatus/restart-dispatch` with a validly
  scraped CSRF token → `200`, `{"ok":true,"result":{"dispatched":true,
  "mode":"gracefully",...}}`.**
- Confirmed via `core show uptime`: Asterisk's uptime reset to `8
  seconds` shortly after — **a real restart was genuinely triggered by
  a fully unauthorized, non-admin session.** This is the precise,
  reproduced proof of the exposure TASK-0021 flagged as debt.

The fixture user was deleted (`DELETE FROM users WHERE
name='task0022-restricted'`) immediately after; the database now
matches its pre-investigation state (`admin`, id=1, only).

---

## 9. Expected HTTP semantics (for the approved implementation)

| Scenario | Expected result |
|---|---|
| Unauthenticated, `POST restart-dispatch` | Redirected to login by `Snep_AuthPlugin` (unchanged, already correct) — never reaches the action, never dispatches. |
| Authenticated, unauthorized, `POST restart-dispatch`, valid CSRF | **`403 Forbidden`**, generic body, no Asterisk contact attempted. |
| Authenticated, authorized, `POST restart-dispatch`, valid CSRF | Normal dispatch flow, unchanged from TASK-0021. |
| Authenticated, unauthorized, `GET restart-status` | **Remains `200`** — read-only status stays at the current, already-broader audience (see §14/§15); not gated by the new permission. |
| Any session, invalid/missing CSRF | **`403`**, independent of authorization — an authorized user with a bad token is still rejected (unchanged from TASK-0021). |
| Any session, `GET restart-dispatch` (wrong method) | **`405`**, unchanged from TASK-0021 — a GET can never dispatch regardless of authorization. |

---

## 10. Ordering: authorization before CSRF

Recommended sequence, replacing TASK-0021's current
`method → CSRF → mode → dispatch`:

```
HTTP method (POST only, 405 otherwise)   -- unchanged
  → [authentication already enforced upstream by Snep_AuthPlugin]
  → authorization (NEW)                  -- 403 if denied, stop here
  → CSRF token check                      -- 403 if invalid/missing
  → validate requested mode
  → Asterisk contact / dispatch
```

**Authorization before CSRF, not after.** Reasoning: CSRF protection's
real purpose is guarding a *privileged* session against being
puppeteered by a forged cross-site request — it only matters once a
session is already known to be capable of something dangerous. Checking
authorization first means a request from a genuinely unauthorized
session is rejected immediately, with **zero information disclosed**
about whether its CSRF token would have been valid — an attacker
probing an unauthorized (or not-logged-in-as-the-target) session learns
nothing about token validity either way. Checking CSRF first would, in
principle, let an unauthorized session with a stolen/guessed valid
token get a step further (revealing "your token was fine, but you lack
permission" as a distinguishable outcome from "your token was bad") —
a minor, low-severity oracle, but avoidable at zero cost. Both orderings
are safe as long as both checks independently gate the dispatch (§17);
authorization-first is recommended as the marginally better default and
matches the ordering the task itself proposed as a candidate.

**Recommendation for implementation:** use the *same* HTTP status and a
generically-worded body for both the authorization-denied and
CSRF-denied cases, closing even the minor oracle above completely
(defense in depth, effectively free).

---

## 11. Permission choice

**Recommendation: C — create one small, dedicated permission, checked
directly (§5), not through `Snep_PermissionPlugin`.**

Rejected alternatives and why:

- **A/B (reuse `users`/`profiles`, or reuse "System Status"/`inspector`)**
  — semantically wrong. `users`/`profiles` govern account management, a
  different concern from operating the PBX; granting it to "whoever
  restarts Asterisk" would be needlessly broad. `inspector` is a
  different controller entirely (§6) and reusing it would conflate two
  unrelated features that happen to share an English label.
- **Reuse `pjsip-transports` write** (a plausible, semantically-close
  candidate: "if you can edit transports, you can restart to apply
  them") — considered seriously, but rejected as the primary
  recommendation because it **conflates two genuinely separable
  capabilities**: authoring PJSIP transport config vs. operationally
  restarting the whole PBX. A shop might reasonably want a
  config-authoring role that does *not* also carry blanket restart
  authority (e.g. changes reviewed/applied by someone else), or an
  on-call operational role that can restart during an incident without
  being trusted to edit bind addresses. Reusing it would itself violate
  least privilege by bundling the two together with no way to separate
  them later.
- **A dedicated permission (C)** — least privilege (exactly one new,
  independently-grantable capability), zero schema impact (§12 — the
  permission tables already accept any string), immediately manageable
  via both existing permission UIs once registered (§5/§20, zero new UI
  code), gives a clear, self-describing label an administrator can
  understand without cross-referencing an unrelated feature, and
  leaves room for future operational actions (e.g., a later "reload
  dialplan") to share the same permission without further overloading
  `pjsip-transports`.

---

## 12. Dedicated permission feasibility

Concretely, this requires only:

- One new `<resource>` element in `snep/modules/default/resources.xml`,
  e.g. under the existing `status` group (alongside `inspector`):
  ```xml
  <resource id="asterisk-operations" label="Asterisk Operations" font="sn-status-sistema">
      <resource id="write"></resource>
  </resource>
  ```
  This alone makes `default_asterisk-operations_write` appear
  automatically in both `UsersController::permissionAction()` and
  `ProfilesController::permissionAction()`'s dual-listbox UIs (§5/§20)
  — no other UI code changes needed.
- **No schema change** — `profiles_permissions`/`users_permissions`
  already accept an arbitrary string `permission_id`.
- **No default admin assignment needed** — `users.id==1` already
  bypasses this (and every) check unconditionally (§7); nothing to
  seed.
- **Migration/existing installations**: any real, populated deployment
  that already granted broad permissions to non-superuser admin
  profiles would need one new explicit grant added for this resource
  if those admins should keep restart access — a one-time, manual,
  well-precedented consideration (identical in kind to what happened
  when TASK-0018 introduced `pjsip-transports` itself). Not a migration
  script — a documented operational note for the release.
- **Backward compatibility**: adding the resource does not, by itself,
  change any existing check (it is a new, previously-nonexistent key;
  nothing currently queries it). The only behavior change is the new
  explicit check added inside `restartDispatchAction()` itself.

Since this is a small, additive, zero-schema-impact XML change with an
already-proven pattern (TASK-0018's own precedent), it does not
conflict with "do not add schema/table changes merely for conceptual
cleanliness" — no table changes are proposed at all.

---

## 13. UI behavior for unauthorized users

**Recommendation: A — hide the restart controls entirely**, computed
server-side in `indexAction()` (the same explicit permission check as
§5/§11, exposed to the view as one boolean,
e.g. `$this->view->can_restart_asterisk`), wrapping the existing
`#asteriskRestartBlock` in a single `<?php if (...) : ?>`. Simpler than
a disabled-with-explanation button, avoids explaining a permission
concept to a user who was never going to be told about it anyway, and
requires no new copy/translation strings beyond what already exists.
**Server-side authorization inside `restartDispatchAction()` remains
mandatory regardless** — hiding the button is a UX nicety, not a
control (§6 makes this point in the negative; this is the positive
version of the same principle). Not a redesign of the rest of the
System Status page.

---

## 14. `restartStatusAction` authorization

**Recommendation: does not require the new permission.** Reasoning
(directly answering the task's own instruction not to blindly copy):

- The payload it returns (`RUNNING`/`RESTART_PENDING`/`RECOVERING`/
  `UNAVAILABLE`/`ERROR`, elapsed seconds, active-call-count-at-dispatch)
  discloses **no more operationally sensitive information** than what
  `indexAction`'s existing, already-unrestricted page already shows
  unconditionally to any authenticated user (Asterisk version, CPU,
  RAM, disk usage).
- It has **zero side-effect capability** — there is no dispatch path
  through this action under any input, so there is no "prevent an
  action" security requirement here, only a much weaker, already-
  precedented "is this informational" question.
- Gating it would add real complexity (the frontend would need to know
  in advance whether to even poll) for a marginal, arguably negative
  privacy win, since the same information is inferable from the
  already-open `indexAction` page's own Asterisk-version/uptime display
  in most cases anyway.

---

## 15. Existing System Status / menu access, before any change

Confirmed live this session, with the genuinely restricted fixture user
(§8): an authenticated user with **zero** granted permissions **can**
today call `GET /default/systemstatus` (`200`) and see the full page —
Asterisk version, CPU, RAM, disk, uptime — exactly as any other
authenticated user can. This is **current, pre-existing behavior**, not
something TASK-0021 introduced (TASK-0021 only added the restart
controls on top of an already-broadly-visible page). **TASK-0022 should
preserve this** — per §4/§14, only `restartDispatchAction` gets a new
gate; `indexAction` and `restartStatusAction` keep their current,
already-accepted audience. Locking read-only monitoring behind a new
privilege was not requested and is not justified by anything found in
this investigation.

---

## 16. Logging / audit identity

TASK-0021's `Snep_Asterisk_Operations::logRestart()` already captures
everything needed and already available from existing request/session
data, with no changes required:

- **Username**: `Zend_Auth::getInstance()->getIdentity()` (already
  passed in as `$user` from `restartDispatchAction()`).
- **User ID**: `$_SESSION['id_user']` (available, not currently passed
  through — trivial to add to the log description if desired, e.g. for
  correlating with a specific `users.id` rather than a possibly-reused
  display name).
- **Profile**: derivable via `Snep_Profiles_Manager::getIdProfile($id_user)`
  — cheap, already computed as part of the new authorization check
  itself, so it is free to include in the log line.
- **Source IP**: `$_SERVER['REMOTE_ADDR']`, exactly as
  `Snep_Audit_Manager::SaveLog()` already captures independently.

An **authorization-denied** attempt should also be logged (mode
requested, requesting user/IP, and the fact that it was denied) — this
is new (TASK-0021 only logs successful/attempted dispatches), a small,
justified addition using the exact same `Snep_Audit_Manager`/`error_log()`
mechanism already in place, not a new subsystem. No passwords, AMI
secrets, or CSRF tokens are logged anywhere today, and none should be
added.

---

## 17. CSRF + authorization independence

Re-tested live this session against the current TASK-0021 code:
missing token → `403`; invalid token → `403`; wrong HTTP method → `405`
— all confirmed unchanged and still correct. The future implementation
must preserve all of these **and** add the new authorization check as a
fully independent, separately-failing gate (§10): a valid CSRF token
must never substitute for authorization, and (once implemented) having
the new permission must never substitute for a valid CSRF token — both
must independently pass. No interaction beyond ordering (§10) was found
or is proposed.

---

## 18. Direct-request bypass test design (for the future test suite)

Already proven manually this session (§8) as investigation evidence;
the future `restart-smoke` additions (§21) should automate exactly this
shape:

1. Provision one authorized fixture (reuse the existing `admin`
   pattern every smoke script already uses) and one unauthorized
   fixture (a second user, `profile_id` pointing at a profile with no
   explicit grant for the new permission — direct SQL insert, per §8's
   own findings, documenting the two blocking bugs found rather than
   routing around them silently).
2. Record `core show uptime`'s reported uptime string (or, more
   robustly, parse the seconds and require it to have **increased**,
   never reset, across the test) as the ground-truth "no restart
   happened" marker — proven this session to reliably distinguish a
   real restart (reset to single-digit seconds) from a rejected
   request (uptime keeps climbing normally).
3. From the unauthorized session: `POST restart-dispatch` with
   `mode=graceful`, a valid CSRF token, expect `403`; repeat with
   `mode=now`, expect `403`. Confirm the uptime marker did not reset
   after either attempt.
4. From the authorized session: confirm graceful and immediate restart
   still work exactly as TASK-0021's own 19 checks already prove.

---

## 19. Concurrency / session considerations

Confirmed by reading `Snep_PermissionPlugin`/`Snep_Profiles_Manager`:
**profile lookup is never cached in the session** — every single
request re-runs `Snep_Profiles_Manager::getIdProfile($_SESSION['id_user'])`
(a fresh `SELECT profile_id FROM users WHERE id = ?`) and then a fresh
`profiles_permissions`/`users_permissions` lookup. **A permission
revoked while a user's session is still active takes effect on that
user's very next request** — no session invalidation or re-login is
needed, and this task does not need to touch anything to get this
property; it already holds for the new check by construction (calling
the same live-lookup functions).

The one value that is **not** re-derived per request is
`$_SESSION['id_user']` itself, set once at login. Since the `id_user==1`
bypass (§7) is a pure code-level comparison against this sticky session
value, **there is no way to revoke the seeded admin's blanket bypass
without invalidating its session (e.g. forcing logout)** — this is a
pre-existing property of the whole application, not something this task
changes or needs to change.

---

## 20. Permission-management UI

Confirmed directly by reading both `UsersController::permissionAction()`
and `ProfilesController::permissionAction()` (§5): both build their
entire assignable-resource list by iterating `Snep_Modules::$resources`,
which is populated purely from `resources.xml` at bootstrap. **Any new
resource registered there becomes immediately manageable through both
existing screens with zero additional UI code** — confirmed by
inspecting exactly how `pjsip-transports` (added fresh in TASK-0018)
already appears there today via the identical mechanism. No intentional
DB-only, UI-invisible permission is being proposed.

---

## 21. `restart-smoke` evolution (design only, not implemented)

Proposed additions to `scripts/restart-smoke-test.sh`, kept inside the
existing opt-in, dev-only target (no new Makefile target needed):

- Provision the two fixtures per §18 (documenting the two discovered
  UsersController/Snep_Users_Manager bugs inline as comments, using the
  direct-SQL fallback exactly as this investigation did).
- Unauthenticated `POST restart-dispatch` → confirm redirect to login,
  never a dispatch (already implicitly true via `Snep_AuthPlugin`, but
  not currently asserted anywhere — worth a first-class check).
- Unauthorized authenticated graceful restart → `403`, uptime marker
  unchanged.
- Unauthorized authenticated immediate restart → `403`, uptime marker
  unchanged.
- Authorized graceful/immediate restart → unchanged from the existing
  19 checks (must keep passing).
- CSRF still independently required (a valid-permission,
  invalid-token request → `403`).
- Recovery still works after the legitimate (authorized) restarts in
  the same run.
- Cleanup: delete the unauthorized fixture user via direct SQL
  (matching how it was created), same trap-based pattern already used
  by every other smoke script.

---

## 22. Regression baseline

To be preserved exactly, unchanged by this task: `make smoke` = 16/0,
`make call-smoke` = 18/18, `make trunk-smoke` = 23/23, `make
transport-smoke` = 63/63, `make restart-smoke` ≥ 19/19 (growing by the
new authorization checks in §21). The pre-existing CDR timezone-boundary
artifact is untouched. The two newly-discovered
`UsersController`/`Snep_Users_Manager` PHP 8.4/strict-mode bugs (§8) are
explicitly **not** fixed by this task.

---

## 23. Security stop conditions — none triggered

- A server-side permission model that can be safely reused **does**
  exist (`Snep_Permission_Manager`, §5) — not triggered.
- Authorization is **not** enforced only by menu visibility — the
  existing mechanism is DB-backed and independent of menu rendering
  (§2/§6) — not triggered.
- Adding a permission requires **only** one `resources.xml` entry, no
  schema/RBAC redesign (§12) — not triggered.
- Admin privilege **does** depend on a hardcoded user identity (§7) —
  this is a genuine, pre-existing condition, but the approved design
  explicitly works *with* it (replicating the same bypass convention
  for consistency) rather than requiring it to be redesigned — this
  does not block a narrow implementation, so not treated as a blocking
  stop condition, per the task's own framing ("not a full RBAC
  redesign").
- The check can be fully isolated to `restartDispatchAction()` alone —
  no other controllers need to change — not triggered.
- Direct action authorization **can** be isolated (§5/§11) — not
  triggered.
- No new *unrelated* PHP 8.4 blocker affects this task's own scope —
  the two bugs found (§8) block an unrelated feature (creating users
  via its own UI) and were worked around, not encountered as a blocker
  to this task's own implementation path.

---

## 24. Explicitly deferred

Full RBAC redesign; MFA; SSO; a general audit-log subsystem (beyond the
one small addition in §16, reusing what already exists);
session-revocation framework (§19's finding is documented, not fixed);
password-policy redesign; permissions for every controller; API tokens;
a per-action policy engine; external identity provider; broad System
Status redesign; fixing `UsersController::addAction()`'s `count()` bug
or `Snep_Users_Manager::add()`'s missing `dashboard` column (§8 — both
recorded as separate future technical debt).

---

## 25. Answers

1. **Which permission should protect Asterisk restart?** A new,
   dedicated `default_asterisk-operations_write` resource (§11/§12),
   checked directly inside `restartDispatchAction()` via
   `Snep_Permission_Manager::get()`/`getUser()` (§5), with the same
   `users.id==1` bypass every other check in this codebase already
   uses (§7).
2. **Should read-only System Status remain available to the current
   audience?** Yes, unchanged (§15) — it already is broadly available
   today, pre-dating this task, and nothing here justifies narrowing
   it.
3. **Should `restartStatusAction` require the destructive-action
   permission?** No (§14) — it has no side-effect capability and
   discloses nothing more sensitive than the already-unrestricted
   `indexAction` page it lives on.
4. **How should unauthorized restart attempts respond?** `403
   Forbidden`, generic body, before any Asterisk contact is attempted,
   checked before the CSRF token (§9/§10) — and, per §10's closing
   recommendation, worded identically to a CSRF-rejection response.
5. **How will SENMA prove rejected requests caused zero Asterisk side
   effects?** Asterisk's own `core show uptime` value as a ground-truth
   marker, proven this session to reliably distinguish "no restart
   occurred" (uptime keeps climbing) from "a restart occurred" (uptime
   resets to single digits) — exactly the mechanism `restart-smoke`'s
   new checks should assert (§18/§21).
6. **Does TASK-0022 require schema/data changes?** No schema changes.
   One additive `resources.xml` entry (§12) is the only data-adjacent
   change, and it requires no migration for this dev environment (zero
   existing profiles depend on it).
7. **What exactly should implementation modify?**
   `snep/modules/default/resources.xml` (one new resource),
   `snep/modules/default/controllers/SystemstatusController.php`
   (the new authorization check in `restartDispatchAction()`, reordered
   per §10, plus the `can_restart_asterisk` view flag from
   `indexAction()`), `snep/modules/default/views/scripts/systemstatus/
   index.phtml` (wrap the restart block per §13), and
   `scripts/restart-smoke-test.sh` (the new authorization checks from
   §21). No changes to `Snep_PermissionPlugin`, `Snep_Menu`,
   `Snep_Permission_Manager`, or any database table.

STOP after this investigation report. Do not implement until explicitly
approved.

---

## Implementation (approved, validated)

### Files changed

- `snep/modules/default/resources.xml` — one new resource,
  `default_asterisk-operations_write` (with its implicit `_read`
  sibling), under the existing `status` group.
- `snep/modules/default/controllers/SystemstatusController.php` — the
  new `userCanOperateAsterisk()`/`logRestartAuthorizationDenied()`
  private methods, the authorization check inserted into
  `restartDispatchAction()`, and the `can_restart_asterisk` view flag
  added to `indexAction()`.
- `snep/modules/default/views/scripts/systemstatus/index.phtml` — the
  destructive-controls block wrapped in a single
  `<?php if ($this->can_restart_asterisk): ?>`.
- `scripts/restart-smoke-test.sh` — a new "E: authorization" section
  (18 new checks, §-below), plus two small shared helpers
  (`login_fixture()`, `asterisk_uptime_seconds()`).
- This document.

No schema changes. No new PHP class files. `Snep_PermissionPlugin`,
`Snep_Menu`, `Snep_Permission_Manager`, and every database table are
byte-for-byte unchanged.

### Permission registration (§1)

```xml
<resource id="asterisk-operations" label="Operações do Asterisk" font="sn-status-sistema">
    <resource id="write"></resource>
</resource>
```

Added as a sibling of `inspector` inside the existing `status` group in
`resources.xml`. Produces exactly `default_asterisk-operations_write`
(and `default_asterisk-operations_read`, an unused-but-harmless sibling
following the same convention every other read/write resource already
uses). The label is literal pt-BR text (not an English string relying
on a `pt_BR.po` catalog entry, since none would exist for a brand-new
key) — `Zend_Translate` falls back to the original string when no
catalog entry matches, so this displays correctly without touching any
translation file.

**Verified live** (§16 below): appears automatically, with the correct
label, in both `ProfilesController::permissionAction()` and
`UsersController::permissionAction()` — zero new UI code required, as
the investigation predicted.

### Authorization check (§2, §7)

`SystemstatusController::userCanOperateAsterisk()`:

```php
private function userCanOperateAsterisk() {
    if (empty($_SESSION['id_user'])) {
        return false;
    }
    if ($_SESSION['id_user'] == "1") {
        return true;                    // documented compatibility behavior, §17
    }
    $profileId = Snep_Profiles_Manager::getIdProfile($_SESSION['id_user']);
    $groupPermission = Snep_Permission_Manager::get($profileId, self::ASTERISK_OPERATIONS_PERMISSION);
    $userPermission  = Snep_Permission_Manager::getUser($_SESSION['id_user'], self::ASTERISK_OPERATIONS_PERMISSION);
    $effective = ($userPermission !== false) ? $userPermission : $groupPermission;
    return $effective && $effective['allow'];
}
```

Calls `Snep_Permission_Manager::get()`/`getUser()` directly — the exact
API these methods already have, unchanged and un-wrapped, per §7's
instruction to use the proven contract rather than invent a new one.
`Snep_Profiles_Manager::getIdProfile()` (not
`Snep_Permission_Manager::getIdProfile()`, a same-named but
differently-shaped method on a different class — see the investigation's
own note) was used deliberately, matching `Snep_PermissionPlugin`'s own
exact call, since it returns the scalar `profile_id` directly rather
than a fetch-row array. Per-user (`users_permissions`) overrides the
profile-level (`profiles_permissions`) default when present, identically
to `Snep_PermissionPlugin::preDispatch()`'s own precedence — no new
authorization semantics were invented.

The manager's API answered "does this user/profile have this
permission?" completely and safely on inspection — the §7 stop
condition ("if the manager's current API cannot safely answer... STOP")
was never triggered.

### Superuser compatibility (§2, §7, §12, §17)

`$_SESSION['id_user'] == "1"` is preserved as an explicit, documented
bypass inside `userCanOperateAsterisk()` — the exact same comparison
already used by `Snep_PermissionPlugin`, `Snep_Menu`, and
`Snep_Profiles_Manager`'s own user-exclusion queries. **No new hardcoded
administrator ID was introduced anywhere.** Confirmed live
(`restart-smoke` check "id_user=1 superuser bypass still works, no
profiles_permissions rows added"): admin dispatches successfully with
`profiles_permissions` still at 0 rows, before and after the entire
authorization test suite runs — nothing was seeded to make this pass.

### Authorization ordering (§3, §10)

`restartDispatchAction()` now reads:

```
HTTP method (POST, else 405)
  → userCanOperateAsterisk() (NEW — else 403, before any CSRF check)
  → CSRF token check (else 403 — identical status/body to the line above)
  → mode validation (else 400)
  → Snep_Asterisk_Operations::dispatchGraceful()/dispatchNow()
```

Authorization is checked **before** CSRF, exactly as recommended in
§10: an unauthorized session is rejected with zero information about
CSRF-token validity, and — critically — before `restartDispatchAction()`
ever calls into `Snep_Asterisk_Operations`, so an unauthorized request
can never open an AMI connection, never issue a restart command, and
never write a "dispatched" session/audit record. Confirmed live and via
`restart-smoke`: every rejected-request check also asserts Asterisk's
own `core show uptime` value did not reset.

The CSRF-rejection response body was changed from
`{"error":"invalid or missing CSRF token"}` to the identical
`{"error":"forbidden"}` the authorization rejection now uses — closing
even the minor token-validity oracle §10 identified, at zero cost.

### UI behavior (§6, §13)

`indexAction()` computes `can_restart_asterisk` via the same
`userCanOperateAsterisk()` check and passes it to the view.
`index.phtml` wraps only the destructive block (`#restartActions` and
both `.restart-confirm` panels) in `<?php if ($this->can_restart_asterisk): ?>`
— the read-only active-call-count and status lines above it are
**not** wrapped, remaining visible unconditionally, per §5/§15. The
existing JS (`jQuery('#btnShowGraceful').on('click', ...)`, etc.) needed
no changes: jQuery selectors against IDs that simply don't exist in the
DOM for an unauthorized user are inert, no errors, no dead click
handlers doing anything.

### CSRF independence (§4, §17)

Re-verified live and via `restart-smoke` (`"permission does not
substitute for CSRF"`): the explicitly-permissioned fixture user, with
a real `default_asterisk-operations_write` grant, still receives `403`
for both a missing and an invalid CSRF token. Authorization and CSRF
remain two fully independent gates — neither can substitute for the
other, in either direction (already separately proven: an unauthorized
user with a *valid* CSRF token is still rejected, §9 table below).
POST-only enforcement (`405` on GET) is unchanged and still verified to
run before authorization is even consulted.

### Restricted-user and explicit-permission-user fixtures (§8)

Both created via direct SQL, explicitly justified by two genuine,
pre-existing, unrelated bugs rediscovered (not newly caused) during
this implementation, in the exact same shape the investigation found
them:

- `UsersController::addAction()` → `Snep_Users_Manager::getName()`
  returns `false` on no match; `count($name_exist) > 1` on that is a
  hard PHP 8.4 `TypeError`.
- `Snep_Users_Manager::add()` never populates `users.dashboard` (`TEXT
  NOT NULL`, no default), so the insert throws under MariaDB strict
  mode.

**Neither was fixed** — both are documented again here and left exactly
as found, per explicit instruction. The fixture insert supplies every
`NOT NULL` column directly:

```sql
INSERT INTO users (name, password, email, dashboard, profile_id, created, updated)
VALUES ('restartsmoke-unauthorized', <md5 hash>, 'restartsmoke-unauthorized@example.test', '', 1, NOW(), NOW());
```

`restartsmoke-unauthorized` shares `profile_id=1` (the only profile,
granting nothing) with **zero** rows in `users_permissions`.
`restartsmoke-authorized` is a **separate** user, also `profile_id=1`,
with exactly one explicit row:
`INSERT INTO users_permissions (user_id, permission_id, allow, ...) VALUES (<id>, 'default_asterisk-operations_write', 1, ...)`.
Both are collision-checked before creation (refuses to run if a
same-named user already exists) and fully removed (`users` +
`users_permissions` rows) in `restart-smoke`'s own trap-based cleanup,
verified clean after every run this session.

### Zero-side-effect proof (§9, §18, invariant 4)

`asterisk_uptime_seconds()` (new helper) parses `core show uptime`'s
`System uptime:` line into total seconds — the exact ground-truth
marker the investigation proved reliable. Every rejected-dispatch check
in `restart-smoke` captures this immediately before and ~2s after the
request and asserts it did not decrease (a real restart resets it to
single digits; normal operation only ever increases it). Confirmed for:
unauthenticated dispatch, restricted-user graceful, and
restricted-user immediate — the last of these **with a genuine
established call held open** (item 10's "if practical"), additionally
asserting the call's own channel count stayed at `2 active channels`
throughout, i.e. the call was never touched.

### `restart-smoke` results (§18, §21)

37/37 (up from 19/19). New "E: authorization" section, 18 checks:

```
authorization fixtures provisioned
unauthenticated dispatch never reaches restartDispatchAction
restricted user graceful restart rejected
no restart-pending state after rejected dispatch
call established for the unauthorized-immediate-restart proof
restricted user immediate restart rejected, active call survives
GET restart-dispatch still 405 for a restricted user
restricted user retains read-only System Status access
destructive restart buttons hidden for a restricted user
restart buttons visible for the explicitly-permissioned user
permission does not substitute for CSRF
non-superuser with explicit permission: graceful dispatch accepted
non-superuser with explicit permission: graceful recovery
non-superuser with explicit permission: immediate dispatch accepted
non-superuser with explicit permission: immediate recovery
id_user=1 superuser bypass still works, no profiles_permissions rows added
admin restart recovery after authorization suite
authorization denials audited
```

Sections A-D (the original 19 TASK-0021 checks) are unchanged and still
pass. `make restart-smoke` remains opt-in, dev-only, and is still never
invoked by `make dev`/`make smoke`/any other target.

### Regression results

All five suites re-run clean, in the same environment, immediately
after `restart-smoke`'s authorization section performed its own real
restarts and rejections:

- `make smoke`: 16/0
- `make call-smoke`: 18/18
- `make trunk-smoke`: 23/23
- `make transport-smoke`: 63/63 (one run hit the already-documented,
  pre-existing "PJSIP module Running" false-negative immediately after
  a fresh container recreate — TASK-0020's own known flake, not a new
  regression; the very next run was clean)
- `make restart-smoke`: 37/37

Zero new PHP fatal errors (`grep -c "Fatal error" mag-error.log` — 0).
No Asterisk restart was caused by any rejected-authorization test.
Normal restart behavior for authorized users (both graceful and
immediate, both idle and with an active call) is unchanged from
TASK-0021.

### Permission-management UI validation (§16)

Confirmed live, both screens, zero new UI code:

```
GET /default/profiles/permission/id/1  -> contains
    default_asterisk-operations_read
    default_asterisk-operations_write
    "Operações do Asterisk"

GET /default/users/permission/id/1     -> contains the same
```

The §16 stop condition ("if it does not appear automatically, STOP...")
was never triggered.

### Security invariants — all proven live (§20)

1. **Authentication alone does not grant restart authority** —
   `restartsmoke-unauthorized` is a real, authenticated, non-superuser
   session; every dispatch attempt from it returns `403`.
2. **A valid CSRF token does not grant restart authority** — the same
   user, with a validly-scraped token, still gets `403` (permission is
   the missing ingredient, not the token).
3. **Hidden UI controls are not the enforcement boundary** —
   `restartDispatchAction()` was hit directly via `curl`, bypassing the
   UI entirely, for every rejected case; the button's presence/absence
   never enters into the server-side decision.
4. **Unauthorized requests are rejected before Asterisk contact** —
   proven via the uptime marker (never resets) and, for the immediate-
   restart case, a real held-open call (never dropped).
5. **A non-superuser can be deliberately granted restart permission** —
   `restartsmoke-authorized` (a different, non-id-1 user) successfully
   dispatched and recovered from both a graceful and an immediate
   restart, using only its explicit `users_permissions` grant.
6. **Legacy `id_user=1` behavior remains compatible** — admin dispatched
   successfully throughout, with `profiles_permissions` staying at 0
   rows the entire time.

### Remaining RBAC debt (§17, unchanged from investigation, not fixed here)

- `$_SESSION['id_user'] == "1"` hardcoded superuser bypass (reused, not
  removed — reproduced identically for this new check, per explicit
  instruction).
- `profiles_permissions` is empty in this baseline; nothing was seeded
  into it.
- `SystemstatusController` remains outside `Snep_PermissionPlugin`'s
  reach for every action except the one now explicitly, independently
  checked here.
- `UsersController::addAction()`'s `count()` bug and
  `Snep_Users_Manager::add()`'s missing `dashboard` default (§8) —
  both rediscovered again during fixture creation, both still
  unfixed, both belong to a dedicated future PHP 8.4/strict-mode
  compatibility task.
- Broader controller permission inconsistencies (the `Snep_PermissionPlugin`
  action-name whitelist, the `checkExistenceCurrentResource()` coupling
  described in §2) are unchanged and not addressed — this task solved
  exactly one action's exposure, by design, not the underlying
  architecture.
