# TASK-0034L — ParametersController Authorization Boundary Hardening

Lead: `senma-application-architect`. Reviewers: `senma-workflow-orchestrator`
(routing/scope discipline), `senma-telephony-architect` (consulted; no
Asterisk-specific implementation change was required -- the only
telephony-adjacent side effect, `Snep_Locale::setExtensionsLanguage()`,
already went through TASK-0034K's hardening and its propagation mechanism
is unchanged here, only who may reach it). `senma-asterisk-pjsip-engineer`
and `senma-product-designer` were not invoked -- no Asterisk runtime
*implementation* change and no material UI/UX change (server-side
authorization is authoritative; the existing form/screen is untouched).

Split from TASK-0034K, which found this gap while tracing the pre-auth
language-switcher defect but deliberately did not fix it (broader than
language, out of that task's narrow-fix mandate).

## STARTING STATE

```
HEAD:   1b5fd05 fix(security): separate UI locale from PBX call-language authority
branch: main
status: clean
```

## ORIGINAL FINDING

TASK-0034K's writer inventory found that `ParametersController::
indexAction()`'s POST branch (the full system-settings save -- 13+
`setup.conf` fields, including DB and AMI credentials, plus the PBX call
language via `Snep_Locale::setExtensionsLanguage()`) was authorized only
via `Snep_PermissionPlugin`'s blanket rule that any action literally named
`index` is classified `read`, **regardless of HTTP method**. A user
granted only `default_parameters_read` (the sibling `languageAction()`
already correctly requires `default_parameters_write`, per TASK-0026A)
could therefore POST through `indexAction()` and mutate the same global
configuration `languageAction()` protects.

## REPRODUCTION (live, before the fix)

A dedicated read-only test user (`task0034l-readonly`, zero superuser
bypass, `profile_id=1` with an empty group-permission baseline -- see
§41 of the release-readiness gate) was granted **only**
`default_parameters_read` via the real, unmodified `UsersController::
permissionAction()` UI flow (not a raw SQL insert of the effective grant
itself -- only user/password provisioning used SQL, matching this
repo's own established test-fixture convention). `PermissionPlugin.php`
was temporarily reverted to its pre-fix state to capture authentic
before-evidence, then re-applied (the file was never left in the
vulnerable state between test runs).

```
BEFORE: setup.conf emp_nome = "Opens Tecnologia"
POST /index.php/default/parameters/index (full form body, emp_nome
  changed, valid session-bound CSRF token, read-only user's session)
  -> HTTP 302 (success -- redirected to '/')
AFTER:  setup.conf emp_nome = "Opens Tecnologia TASK0034L-TEST"
```
A harmless, reversible field (`emp_nome`, the company display name) was
used deliberately, per the task's own instruction not to reuse the
language field TASK-0034K already exercised. Restored immediately after
capture.

## PARAMETERS ACTION INVENTORY (Phase 1)

The controller has exactly two dispatchable actions (`init()` is a
lifecycle hook Zend calls before every action, not itself routable):

| Action | Classification |
|---|---|
| `init()` | `READ_ONLY` (sets 2 view vars only, no side effects) |
| `indexAction()` | `MIXED` -- GET renders the full settings form (read); POST processes the entire save (mutating) |
| `languageAction()` | `MUTATING` -- POST-only (GET redirects with no write, TASK-0026G), already correctly gated by `default_parameters_write` + CSRF |

No `UNKNOWN` remains.

## SIDE-EFFECT INVENTORY (Phase 2)

| ACTION | METHOD | INPUT | PERSISTENT EFFECT | RUNTIME EFFECT | PERMISSION (before) | PERMISSION (after) |
|---|---|---|---|---|---|---|
| `indexAction()` | GET | none | none (render only) | none | `default_parameters_read` | unchanged |
| `indexAction()` | POST | 20 form fields | `setup.conf` rewrite: `emp_nome`, `debug`, `show_help`, `hide_routes`, `language`, `locale`, `timezone`, `country_code`, `peers_digits`, `ip_sock`/`user_sock`/`pass_sock` (AMI creds), `mail`, `linelimit`, `conference_app`, `db.dbname`/`db.host`/`db.username`/`db.password` (DB creds), `record.*`, `path_voz*`, `valor_controle_qualidade`; also 1 read-only `SELECT` against `core_cnl_country` | `Snep_Locale::setExtensionsLanguage()` (extensions.conf rewrite + AMI `dialplan reload`, TASK-0034K mechanism, unchanged here); `$_SESSION[UI_LANGUAGE_SESSION_KEY]` mirror | **`default_parameters_read`** (the gap) | `default_parameters_write` |
| `languageAction()` | GET | none | none (redirects, no write -- TASK-0026G) | none | N/A | unchanged |
| `languageAction()` | POST | `language`, `module` | `setup.conf` (`system.language` only) | `setExtensionsLanguage()` + session mirror | `default_parameters_write` | unchanged (already correct) |

No module/service restart, no filesystem write outside `setup.conf`/
`extensions.conf`, no other DB table write.

## CURRENT PERMISSION MODEL (Phase 4)

`resources.xml`'s `configs` group declares:
```xml
<resource id="parameters" label="Parameters" font="sn-parametros">
    <resource id="write"></resource>
</resource>
```
`Snep_Modules::loadResources()` (`snep/lib/Snep/Modules.php:127-152`)
auto-registers the bare declaration as an **implicit** `default_
parameters_read` ACL resource, and the nested `<resource id="write">`
child as an **explicit** `default_parameters_write` resource -- both
already exist and are already correctly used by `languageAction()`
(added specifically for it by TASK-0026A; see that resource's own
in-repo comment, which already documented the risk shape this task
closes). **No new permission was invented** -- `default_parameters_write`
is reused exactly as-is.

`Snep_PermissionPlugin::preDispatch()` computed the required resource as
`{module}_{controller}_{type}`, where `$type` was `'read'`
unconditionally whenever `$action == 'index'` (`PermissionPlugin.php:151`,
pre-fix), independent of `$request->isPost()`.

## CANONICAL AUTHORITY MODEL (Phase 5/6)

Preferred, smallest-supported-model choice: **GET renders under the
existing read permission; POST mutates under the existing write
permission** -- without splitting `indexAction()` into two Zend actions
(the task's own Phase 6 explicitly permits this).

Two implementation options were weighed:
1. Split the POST-handling code into a new dedicated action (e.g.
   `saveAction()`), changing the view's form `action=` target.
2. A narrow, per-controller-scoped, opt-in classification override
   inside `Snep_PermissionPlugin` itself.

**Chosen: (2).** Rejected (1) because it would change the form's POST
target URL (`views/scripts/parameters/index.phtml:17`, currently
`array("controller"=>"parameters","action"=>"index")`), risking silent
breakage for anything that POSTs to the current URL directly (a stale
bookmark, cached page, external automation) -- the task's own "Existing
legitimate admin workflows must continue to work" invariant. Option (2)
touches zero view/template code and preserves the exact existing URL,
form, and button.

**Why this is not a "general RBAC redesign"** (explicitly out of scope):
a full-repo scan found the `action=='index'` blanket-read rule is relied
on by many other controllers whose `indexAction()` also reads
`$_request->getPost()` (see HIDDEN-WRITER INVENTORY below) -- but the
fix here is an **opt-in table keyed by exact controller**, checked only
when `($action=='index' && isPost())`. It changes classification for
`default_parameters` and nothing else; every other controller's `index`
action is provably unaffected (confirmed in regression: 44/44 unrelated
suites pass unchanged both before and after).

## IMPLEMENTATION

`snep/modules/default/model/PermissionPlugin.php`:
- New `private static $writeOnPostIndex = array('default_parameters' =>
  true);` -- one entry, individually justified in its own docblock,
  matching the existing `$readActions`/`$aliasResource` precedent for
  per-controller overrides.
- `preDispatch()`: the `$action == 'index'` branch now checks
  `$request->isPost() && isset(self::$writeOnPostIndex[$key])` first; a
  GET to `index` (any controller) is untouched -- still always `'read'`.

No `resources.xml` change (the resource already existed). No
`ParametersController.php` change (the controller's own code, and its
view, are untouched -- the fix is entirely in the authorization layer
that gates it).

## UNAUTHENTICATED PROOF (Phase 10)

```
POST /index.php/default/parameters/index (no session cookie)
  -> HTTP 200 (Snep_AuthPlugin renders the login page in place, the
     established contract for every unauthenticated request)
setup.conf emp_nome: unchanged
```

## ZERO-PERMISSION PROOF (Phase 11)

Dedicated `task0034l-zeroperm` user, authenticated, zero `users_
permissions` rows:
```
GET /index.php/default/parameters  -> HTTP 302, Location: permission/error
  (denied before a CSRF token could even be obtained)
POST /index.php/default/parameters/index (no CSRF token available)
  -> HTTP 302, Location: permission/error
setup.conf emp_nome: unchanged
```

## READ-ONLY MUTATION-DENIAL PROOF (Phase 12 -- the key proof)

Same `task0034l-readonly` user as REPRODUCTION, now against the fixed
`PermissionPlugin.php`:
```
GET /index.php/default/parameters -> HTTP 200 (read still works)
POST /index.php/default/parameters/index (valid session CSRF, full form,
  emp_nome=TASK0034L-SHOULD-BE-DENIED)
  -> HTTP 302, Location: permission/error
setup.conf emp_nome: unchanged ("Opens Tecnologia")
```
No legitimate read-only Parameters role existed as a documented product
concept before this task; `default_parameters_read` (implicit,
TASK-0026A-era) is the correct existing boundary and is exactly what
this task now enforces server-side for the mutating path too.

## AUTHORIZED-ADMIN MUTATION PROOF (Phase 13)

Two distinct personas, both proven:
1. **`id=1` superuser** (`admin`, the historically-supported role --
   `PermissionPlugin`'s documented bypass at line 160, completely
   unaffected by this change since it returns before any resource check
   runs at all): POST through `indexAction()` -> HTTP 302, `emp_nome`
   updated, restored.
2. **Non-superuser, explicitly granted `default_parameters_read` +
   `default_parameters_write`** (`task0034l-writer`, id 422 -- the
   genuine exercise of the new boundary, not merely the bypass): POST
   through `indexAction()` -> HTTP 302, `emp_nome` updated to
   `"Opens Tecnologia TASK0034L-ADMIN-OK"`, restored to the original
   value afterward via the same authorized path.

Runtime propagation was also proven through this exact newly-gated path
using the language field (not just `emp_nome`):
```
BEFORE: setup.conf language="en"; extensions.conf SNEP_LANGUAGE=en
Writer user POST indexAction, language=es -> HTTP 302
AFTER:  setup.conf language="es"; extensions.conf SNEP_LANGUAGE=es
        `asterisk -rx "dialplan show globals"`: SNEP_LANGUAGE=es (live)
Restored to "en" via the same path immediately after.
```

## CSRF PROOF (Phase 7)

Isolated from authorization using the write-authorized, non-superuser
`task0034l-writer` session (so a denial can only be attributed to CSRF,
not permission):
```
POST indexAction, valid session+permission, NO snep_csrf_token
  -> HTTP 403 "Forbidden: missing or invalid CSRF token."
POST indexAction, valid session+permission, WRONG snep_csrf_token
  -> HTTP 403 "Forbidden: missing or invalid CSRF token."
POST indexAction, valid session+permission, VALID snep_csrf_token
  -> HTTP 302, mutation applied
```
CSRF architecture (`Snep_Security_Csrf`/`Snep_CsrfPlugin`) was not
touched -- reused exactly as-is, per the task's own instruction.

## GET/POST PROOF (Phase 8/9)

```
GET /index.php/default/parameters/index?emp_nome=TASK0034L-GET-SHOULD-NOT-APPLY
  (admin session, deliberately superuser so a failure could only be the
  GET/POST branch itself, not an authorization side effect)
  -> HTTP 200, setup.conf unchanged
```
Structural, not merely policy: `indexAction()`'s mutation block is
`if ($this->_request->getPost())`, which a GET (with or without a query
string) never satisfies. No `SECURITY_DEFECT` here (GET mutation was
never possible on this action) -- confirmed empirically, not assumed.

## STATE-INTEGRITY PROOF (Phases 16-19)

- **setup.conf**: byte-identical `emp_nome` line before/after every
  denied attempt (unauthenticated, zero-permission, read-only) --
  automated in `authorization-smoke-test.sh`.
- **Asterisk config / runtime**: `extensions.conf`'s `SNEP_LANGUAGE` and
  the live `asterisk -rx "dialplan show globals"` output were confirmed
  unchanged across the denied-attempt sequence (denial happens in
  `Snep_PermissionPlugin::preDispatch()`, strictly before the controller
  -- and therefore before any DB query, config write, or AMI call --
  ever executes).
- **DB**: `indexAction()`'s only DB interaction is a read (`SELECT id
  FROM core_cnl_country WHERE locale=...`); no table write exists on
  this path to verify beyond `setup.conf`, which is covered above.

## BACKWARD COMPATIBILITY (Phases 23-25)

- **Fresh install**: the seeded `admin` account is `id=1`, which
  `Snep_PermissionPlugin` bypasses unconditionally *before* any resource
  check -- this change cannot affect it. `profiles_permissions` (group
  grants) starts empty by default (already documented, §41 of the
  release-readiness gate, TASK-0022) -- no non-superuser account has any
  Parameters grant at all on a fresh install, so nothing regresses.
  **Not a `PILOT_BLOCKER`.**
- **Existing installs**: only an account that was explicitly granted
  `default_parameters_read` **without** `default_parameters_write` is
  affected -- and the only possible effect is losing a capability that
  was never an intended, documented grant (the whole point of this
  task). No migration, no permission-baseline update, no data change of
  any kind was needed or performed.
- **No permission broadening** (Phase 37): the change is exclusively
  restrictive (POST via read-only now denied where it previously
  succeeded); no role gained any capability it did not already have.

## LANGUAGE PATH REGRESSION (Phase 14, TASK-0034K)

Not reopened. `preauth-security-smoke-test.sh` (15/15, unchanged) and
the live language-flip proof above (via the now-more-strictly-gated
`indexAction()` itself) both reconfirm: pre-auth selection stays
session-only, the authenticated global write stays admin-authorized-only,
and propagation to `extensions.conf`/the live dialplan still works.

## HIDDEN-WRITER INVENTORY (Phase 15)

Searched for other callers of the same write surface:
- **`setup.conf` writers outside `ParametersController`**: `snep/
  modules/default/api/index.php` only *reads* `setup.conf` (bootstrap
  config for its own independent HTTP-Basic-Auth-gated API, a fixed
  6-service allowlist unrelated to Parameters) -- `SAFE`, not a writer.
  `Snep_Parameters_Manager::change()` (a generic `setup.conf` writer
  utility) has **zero live callers anywhere in the repo** (the one grep
  hit outside its own file is a stale cross-reference comment from
  TASK-0015A, not an actual call) -- `SAFE` (`WRITE_CAPABLE_BUT_
  UNREACHABLE`, per the architect's own classification taxonomy; not
  removed, out of this task's scope).
- **The same `action=='index'`-is-always-read PATTERN** (distinct from
  the same *writer*) recurs across roughly two dozen other controllers
  whose `indexAction()` also reads `$_request->getPost()`
  (`AuditController`, `CallsReportController`, `DocsController`,
  `ErrorsKhompController`/`ErrorsTdmController`, `ExportDataController`,
  `ExtensionsController`, `IndexController`, `KhompLinksController`,
  `LogsController`, `ModuleSettingsController`, `RankingReportController`,
  `RegisterController`, `ServicesReportController`, `SimulatorController`,
  `TdmLinksController`, and others). Most of these appear, from their
  names and general shape, to use POST only for read-only filter/search
  submission -- not evidenced as real mutations, and not individually
  audited (doing so for all of them is exactly the "all-controller
  permission rewrite" this task's own scope excludes). **One concrete
  exception was found and verified**: `CnlController::indexAction()`'s
  POST branch (`country=76`) accepts an uploaded ZIP, extracts it, and
  updates dialing-prefix reference data -- a genuine mutation, currently
  gated only by the implicit `default_cnl_read` resource (`resources.xml`
  declares no `write` child for `cnl` at all, so a `default_cnl_write`
  permission does not even exist yet to grant). This **shares the exact
  same flaw shape** as the original Parameters finding, but fixing it
  requires an *additional* `resources.xml` change (a new permission, not
  reuse of an existing one) for a different controller/screen entirely --
  classified **`FOLLOW_UP_DEBT`**, not folded into this task's fix, to
  keep this change reviewable as the one thing it claims to be.

## PERMISSION NAMING CLARITY (Phase 22)

`default_parameters_read` = may view/render the System Settings screen.
`default_parameters_write` = may save changes on that screen -- now
covers the *entire* `indexAction()` save surface, not only the dedicated
language-switcher AJAX call it already covered. No permission identifier
was renamed.

## UI BEHAVIOR (Phase 26)

Unchanged. The settings form's Save button remains visible/enabled
regardless of the viewer's permission (server-side authorization is
authoritative, per the task's own core principle); a read-only user who
submits it now sees the standard permission-denied page instead of a
silent no-op or a false success. Not classified as requiring
`senma-product-designer` review -- no new user-facing state, no new
screen, no workflow change for any already-supported role.

## AUDIT LOGGING (Phase 21)

No dedicated audit-logging subsystem exists for Parameters changes today
(confirmed: no `Snep_Audit_Manager`/`Snep_LogUser` call site inside
`ParametersController.php`), and none was built here, per the task's own
instruction. Denials already produce the standard
`Snep_PermissionPlugin::deny()` redirect, identical to every other
denied resource in the application. Classified `FOLLOW_UP_DEBT` if
Parameters-specific change auditing is ever required -- not a security
correctness gap for this task (the mutation is now correctly blocked,
not merely unlogged).

## REGRESSION PROOF

- `scripts/authorization-smoke-test.sh`: extended with 8 new checks
  (admin grants read-only permission, read-only user renders, read-only
  user denied mutation + `setup.conf` unchanged, GET-never-mutates,
  admin grants write, write-authorized mutation succeeds, restore,
  revoke-to-baseline) -- **25/25 PASS**, run twice consecutively with
  identical results (no fixture leakage; separate cookie jars per
  persona throughout, confirming session isolation).
- `scripts/system-status-runtime-smoke-test.sh`: **11/11 PASS**
  (`PermissionPlugin.php` is shared bootstrap-adjacent code, loaded on
  every authenticated request).
- `make lint`: **PASS 5/5**.
- `make regression` run 1: **PASS 44/44**.
- `make regression` run 2 (consecutive, no manual repair): **PASS
  44/44** -- baseline unchanged from TASK-0034K (no new suite was
  registered in `scripts/regression.sh`; the new checks extend an
  already-registered suite).

## REMAINING DEBT

1. `CnlController::indexAction()`'s POST-gated ZIP-upload mutation,
   gated only by an implicit read resource with no `write` child yet
   declared -- concrete, verified, `FOLLOW_UP_DEBT` (see HIDDEN-WRITER
   INVENTORY).
2. ~20 other controllers whose `indexAction()` also reads
   `$_request->getPost()` -- pattern-matched but individually
   unaudited; a dedicated systemic review is the right-sized next task,
   not a blanket reclassification here.
3. `Snep_Parameters_Manager::change()` -- confirmed dead/unreachable;
   candidate for removal in a future dead-code cleanup, not acted on
   here.
4. No Parameters-specific change audit log exists -- pre-existing,
   unrelated to this task's correctness.

## RELEASE/PILOT IMPACT (Phase 39)

Re-read `docs/tasks/0034-release-readiness-production-pilot-gate.md`.
This finding was not present in that document (discovered later, by
TASK-0034J) -- added as a new row in its §41 known-debt table, marked
**Closed**, referencing this task. It was the only *authorization*-related
open item in that document besides the already-accepted, unrelated
`id_user==1` superuser-bypass/empty-`profiles_permissions` baseline
(§41, classified `POST_PILOT` in 0022, unaffected by this change). No
other open release-gate item required updating.

**Classification: was `PILOT_CONSTRAINT`** (real, server-side-reachable,
bounded to accounts an install operator would have to deliberately grant
read-only Parameters access to -- not reachable by an anonymous or
zero-permission actor) **prior to this task; now `Closed`.**

## RECOMMENDATION

`APPROVE_WITH_CONSTRAINTS` -- see REMAINING DEBT above (item 1,
`CnlController`, is the one concretely-evidenced carry-forward; items 2-4
are lower-confidence/lower-severity housekeeping).
