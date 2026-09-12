# TASK-0034O — ITC Vendor Registration Authorization Boundary Audit & Hardening

Lead: `senma-application-architect`. Reviewer: `senma-workflow-orchestrator`
(routing/scope discipline). `senma-product-designer`, `senma-docker-platform-engineer`,
and telephony specialists were not required -- the registration contract was
derivable from code/runtime evidence; no Compose/runtime topology change; no
Asterisk/PJSIP mutation on the audited write path (DB-only ITC state).

Predecessor: TASK-0034M (`docs/tasks/0034m-controller-write-authorization-audit-cnl-boundary-hardening.md`)
flagged `IndexController`/`RegisterController` as `FOLLOW_UP_REQUIRED` because
they sit on `PermissionPlugin::$alwaysAllow` (a different mechanism from the
read-implies-write `indexAction`+POST pattern closed by 0034L/0034M).

## ARCHITECTURE (product decision)

```text
SENMA core = standalone

ITC / future portal integration = optional
```

Historical ITC was an external portal operated by Opens (maintainer of SNEP).
SENMA may build a similar portal later. Therefore:

- DO NOT remove ITC code wholesale;
- DO NOT delete the ITC data model merely because it is legacy;
- DO NOT redesign a future portal integration now.

SENMA must no longer depend on ITC registration or ITC availability to operate.
ITC is an **optional integration** behind an explicit opt-in flag.

### Standalone SENMA contract (default)

Without any ITC configuration (`itc_enabled` absent or not `"true"`):

```text
SENMA starts
→ user logs in
→ normal dashboard/application opens
→ no registration prompt blocks the user
→ no external ITC call is required
```

Required to work without ITC registration and without a reachable external
ITC service: application startup, login, authenticated navigation, dashboard,
PBX administration, telephony configuration, normal operational workflows.

### Optional ITC contract

When `setup.conf` `[system] itc_enabled = "true"`:

- historical interstitial / RegisterController paths remain available;
- POSTs still require `default_index_write` / `default_register_write` + CSRF;
- GET Register must not mutate `itc_consumers`;
- `itc_required` only applies while ITC is enabled (hides "register later").

Default installs ship `itc_enabled = "false"` in `setup.conf.dist`.

Security findings from this task remain valid under both modes and are
**additional to** the architectural decoupling, not a replacement for it.

## STARTING STATE

```
HEAD:   0f9de3d docs: close TASK-0034N CNL compatibility repair
branch: cursor/cloud-agent-1789228026971-noiwv
status: clean at task start (TASK-0034N commits present)
```

## `$alwaysAllow` SEMANTICS (proven)

`$alwaysAllow` does **not** mean unauthenticated public access.

Dispatch order (live evidence):

1. `Snep_AuthPlugin` -- unauthenticated requests are rewritten to the login
   page before permission checks run.
2. Superuser (`id_user == 1`) -- PermissionPlugin returns early (unchanged).
3. `PermissionPlugin::$alwaysAllow` -- for listed controllers, any
   **authenticated** user may reach the controller without a per-resource
   grant -- historically for every action/method.
4. `Snep_CsrfPlugin` -- still enforces CSRF on authenticated POSTs
   (field `snep_csrf_token`), including alwaysAllow controllers.

TASK-0034O refined step 3: if the controller is also listed in
`$writeOnPostIndex`, a POST to `index` falls through the alwaysAllow
short-circuit and requires `default_<controller>_write` (same shape
0034L/0034M already use for non-alwaysAllow controllers). GET and other
actions on alwaysAllow controllers remain authenticated-open.

## ITC DEPENDENCY MAP

| Dependency | Location | Behavior (before → after) | Classification |
|---|---|---|---|
| `itc_enabled` gate | `Snep_Register_Manager::isEnabled()` | absent/`false` → core path; `"true"` → optional ITC | OPTIONAL_INTEGRATION |
| Interstitial branch | `IndexController::indexAction` | gated on `isEnabled()` + session flags; default skips | was CORE_BLOCKING_DEPENDENCY → OPTIONAL_INTEGRATION |
| Outbound ITC ping / auth APIs | `IndexController` / `RegisterController` via `itc_address` | only when enabled and on ITC UI paths | OPTIONAL_INTEGRATION |
| Session `registered` / `noregister` / `uuid` | `AuthController` login | **disabled:** ephemeral empty placeholders only, **zero ITC DB I/O**; **enabled:** historical hydrate/seed from `itc_register` | OPTIONAL_INTEGRATION (gated) |
| `itc_register` row bootstrap | `AuthController` + `Snep_Auth_Manager::adduuid()` | runs **only when ITC enabled**; skipped in standalone login | OPTIONAL_INTEGRATION |
| `itc_register` / `itc_consumers` tables | schema + `Snep_Register_Manager` | retained for optional / future portal; unused by standalone login | FUTURE_PORTAL_CANDIDATE |
| `RegisterController` | GET/POST registration status / re-login | redirects `/` when disabled; write-gated POST when enabled | OPTIONAL_INTEGRATION |
| Registration layouts | `register.phtml`, `loginregister.phtml` | used only when interstitial/Register active | OPTIONAL_INTEGRATION |
| Menu "Cloud Server Informations" | `layout.phtml` → `/default/register` | still visible; redirects home when disabled | DISPLAY_ONLY |
| `itc_required` / `itc_distro` / `itc_address` | `setup.conf` | irrelevant while disabled; address unused on core path | OPTIONAL_INTEGRATION |
| Commented `Snep_ITCRegister` | `IndexController` | unused | DEAD_LEGACY |
| Permission resources `index`/`register` write | `resources.xml` + `$writeOnPostIndex` | authz for optional POSTs | OPTIONAL_INTEGRATION (security boundary) |

### Architecture contract (login / navigation)

```text
ITC disabled (default):
  zero ITC DB activity in normal login/navigation flow
  no SELECT/INSERT/UPDATE on itc_register or itc_consumers
  no outbound itc_address traffic
  login → normal authenticated SENMA landing

ITC enabled:
  legacy/optional integration behavior available
  (AuthController hydrates itc_register; interstitial/Register as before,
   with TASK-0034O write/CSRF hardening)
```

### Current blocking dependencies (after this task)

**None for core product use.** External ITC availability and registration
state no longer gate login → dashboard when `itc_enabled` is not `"true"`.
Standalone login does not require any `itc_register` / `itc_consumers` row.

Residual non-blocking leftovers:

- Menu link to Register remains visible (harmless redirect when disabled).

### Did the interstitial change the post-login landing path?

**Yes (historical / optional-enabled):** after login, `AuthController`
redirects to `/`; `IndexController` previously showed the registration
layout whenever `$_SESSION['registered']` and `$_SESSION['noregister']`
were both false, including a mandatory path when `itc_required=true`
(no "register later").

**Default after this task:** with `itc_enabled=false`, Index opens the
normal dashboard (or empty-dashboard redirect to `index/add`) regardless
of those session flags. Failure of an unreachable `itc_address` is
irrelevant because the ping is not executed on the core path.

## ENDPOINT INVENTORY (ITC registration flow)

| Controller | Action | Methods | AuthN | AuthZ (after) | CSRF | State mutation | Classification |
|---|---|---|---|---|---|---|---|
| IndexController | indexAction (core dashboard) | GET | required | alwaysAllow | n/a | none (or empty-dashboard redirect) | AUTHENTICATED_READ (default) |
| IndexController | indexAction (pre-registration branch) | GET | required | alwaysAllow | n/a | none (render + outbound ITC ping) | OPTIONAL — AUTHENTICATED_READ |
| IndexController | indexAction (`save=register/confirm/login/opensnep/noregister`) | POST | required | `default_index_write` | required | `itc_register` / `itc_consumers` / notifications / session | OPTIONAL — AUTHENTICATED_WRITE |
| IndexController | indexAction (`?dashboard_add=`) | GET | required | alwaysAllow | n/a | per-user dashboard prefs | AUTHENTICATED_WRITE (FOLLOW_UP_DEBT -- not ITC) |
| IndexController | addAction | GET/POST | required | alwaysAllow | POST: required | per-user dashboard prefs | AUTHENTICATED_WRITE (FOLLOW_UP_DEBT -- not ITC) |
| RegisterController | indexAction when disabled | GET | required | alwaysAllow | n/a | none (redirect `/`) | OPTIONAL off → AUTHENTICATED_READ |
| RegisterController | indexAction (already registered) | GET | required | alwaysAllow | n/a | **none after this task** (display only; may call external ITC) | OPTIONAL — AUTHENTICATED_READ |
| RegisterController | indexAction (`save=login`) | POST | required | `default_register_write` | required | `itc_register` keys + `itc_consumers` rewrite | OPTIONAL — AUTHENTICATED_WRITE |
| RegisterController | indexAction (not registered) | GET | required | alwaysAllow | n/a | session `noregister=false` then redirect `/` | OPTIONAL — session-only side effect |

Unauthenticated callers never reach these actions (AuthPlugin → login).

## REPRODUCTION (authorization defect, before fix)

Live HTTP against the running stack (`admin` / dedicated zero-permission
fixture, valid CSRF):

```
BEFORE: itc_register.noregister = 0
POST /index.php/default/index  save=noregister&snep_csrf_token=<valid>
  as zero-permission authenticated user
  -> HTTP 302 Location: / (success)
AFTER:  itc_register.noregister = 1
```

CSRF missing → HTTP 403, state unchanged (CSRF already correct).

Unauthenticated GET/POST → login page, state unchanged.

RegisterController GET (registered_itc=1) previously called
`removeDistributions()`/`addDistributions()` on every page view.

Root-cause decision: **A — CONFIRMED_SECURITY_DEFECT**.

## INTENDED CONTRACT (authorization + architecture)

```
anonymous:
  may not reach ITC registration UI or mutate ITC state
  (AuthPlugin login gate -- unchanged)

default (itc_enabled != "true"):
  login → normal core landing
  no mandatory registration interstitial
  no outbound ITC HTTP required
  RegisterController redirects home without mutation

optional (itc_enabled = "true"):
  unregistered installs may see historical interstitial
  any authenticated user may GET interstitial / Register status
  may NOT POST ITC mutations without default_index_write /
      default_register_write
  may NOT rewrite itc_consumers via GET

default_index_write (or superuser), when ITC enabled:
  may POST register/confirm/login/opensnep/noregister on IndexController

default_register_write (or superuser), when ITC enabled:
  may POST RegisterController login/update

all authenticated POSTs:
  require valid snep_csrf_token
```

Public/anonymous vendor self-registration is **not** part of the product
contract. Fresh install with empty grants: only superuser (`id=1`) can
complete or decline ITC registration when the optional path is enabled.

## SECURITY FINDINGS

| Area | Finding | Disposition |
|---|---|---|
| Authorization scope | Any authenticated user could POST system-wide ITC writes | FIXED (writeOnPostIndex + resources.xml write children) |
| GET mutates | RegisterController GET rewrote `itc_consumers` | FIXED (sync deferred to POST) |
| CSRF | Already enforced; register layouts lacked meta/csrf.js so browser POSTs 403'd | FIXED (layouts emit meta + csrf.js) |
| Core blocked by ITC | Interstitial + outbound ping on every unregistered login | FIXED (`itc_enabled` default false; Index/Register gated) |
| Mass assignment / privileged fields on `noregister` | Extra POST fields ignored; only `noregister` flips | SAFE_BY_CONTRACT (proven by test) |
| Duplicate/replay noregister | Idempotent flag set | SAFE_BY_CONTRACT |
| Information disclosure | No credentials/stack traces in deny path | SAFE_BY_CONTRACT |
| Sibling dashboard writes (`addAction`, `dashboard_add`) | Still alwaysAllow authenticated writes of per-user prefs | FOLLOW_UP_DEBT (different asset; not ITC) |

## ROOT-CAUSE DECISION

**A. CONFIRMED_SECURITY_DEFECT** (authorization) **plus** architectural
decoupling so ITC is optional — implemented as the narrowest combined fix.

## CHANGES

1. `PermissionPlugin.php` -- alwaysAllow short-circuit falls through for
   `index`+POST when `$writeOnPostIndex` lists the controller; added
   `default_index` and `default_register` to `$writeOnPostIndex`; comments
   corrected.
2. `resources.xml` -- `index` gained `<resource id="write">`; new
   `register` resource with write child under the index group.
3. `RegisterController.php` -- removed GET-side
   `removeDistributions()`/`addDistributions()`; display-only on GET;
   sync remains on POST login (now write-gated); redirects `/` when
   `!isEnabled()` without session/DB mutation.
4. `register.phtml` / `loginregister.phtml` -- CSRF meta + `csrf.js`.
5. `Snep_Register_Manager::isEnabled()` -- explicit opt-in
   (`itc_enabled === "true"` only).
6. `IndexController::indexAction` -- interstitial only when `isEnabled()`
   and session unregistered/noregister false.
7. `setup.conf.dist` -- `itc_enabled = "false"`, `itc_required = "false"`
   with comments documenting standalone default.
8. `AuthController.php` -- ITC `itc_register` SELECT/INSERT hydrate and
   uuid seed run only when `Snep_Register_Manager::isEnabled()`; disabled
   login sets ephemeral empty session placeholders and performs zero ITC
   DB activity.

## LEGACY ITC COMPONENTS RETAINED (and why)

| Component | Why retained |
|---|---|
| `IndexController` ITC branches | Future optional portal / historical re-enable |
| `RegisterController` + views | Same |
| `Snep_Register_Manager` + country/state helpers | Same |
| Tables `itc_register`, `itc_consumers` | Data model for optional / future portal; not deleted |
| `setup.conf` `itc_*` keys | Narrow enable/disable without a new config subsystem |
| Menu link "Cloud Server Informations" | DISPLAY_ONLY leftover; harmless redirect when disabled |
| Auth login ITC hydrate/seed | Retained **only when `isEnabled()`**; standalone login performs zero ITC DB I/O |

## TEST CHANGES

- `scripts/itc-registration-authorization-security-smoke-test.sh`
  covers:
  1. Standalone (`itc_enabled=false`) + unreachable `itc_address`: login,
     core landing, no interstitial, Register redirects home,
     unauthenticated deny.
  2. **DB isolation:** exact `itc_register`/`itc_consumers` snapshot
     equality across standalone login; empty-table login still lands and
     does not re-seed ITC rows.
  3. Optional mode authz matrix: zero/RO deny writes; writer + superuser
     noregister; CSRF; Register GET no consumer rewrite; Register POST
     write-gated; CSRF meta; field injection.
  4. Failure isolation: core landing with `itc_address=127.0.0.1:1`.
- Wired: `Makefile` target `itc-registration-authorization-security-smoke`;
  `scripts/regression.sh` suite
  `itc-registration-authorization-security` immediately after the CNL
  authz suite.
- `scripts/smoke-test.sh` (http-smoke): accepts empty-dashboard core
  landing `HTTP 302 -> /index.php/index/add` when ITC is disabled and
  no widgets are configured. Previously only HTTP 200 (dashboard or
  registration layout) was accepted; after standalone default that
  empty-dashboard redirect is the normal authenticated landing and must
  not FAIL the suite. Optional `id="registerLayout"` landing remains
  accepted when `itc_enabled=true`.

## SAME-MECHANISM INVENTORY (`$alwaysAllow`)

| Key | Classification | Notes |
|---|---|---|
| `default_index` | FIXED_NOW (POST index); FOLLOW_UP_DEBT (`addAction` / GET `dashboard_add`) | ITC POST closed; dashboard-pref mutations remain authenticated-open |
| `default_register` | FIXED_NOW | GET no longer mutates; POST write-gated; disabled → redirect |
| `default_auth` | SAFE_BY_CONTRACT | login/logout/recovery must stay reachable |
| `default_error` | SAFE_BY_CONTRACT | shared error renderer |
| `default_installer` | DEAD/UNREACHABLE | no backing controller; parity only |
| `default_permission` | SAFE_BY_CONTRACT | deny landing page (redirect-loop safety) |
| `default_systemstatus` | SAFE_BY_CONTRACT | restart independently self-gated (TASK-0022) |
| `default_docs` | SAFE_BY_CONTRACT | read-only local docs |
| `default_information` | SAFE_BY_CONTRACT | greeting widget |
| `default_newversion` | SAFE_BY_CONTRACT | read-only version display |
| `default_notifications` | DIFFERENT_RISK / NEEDS_FOLLOW_UP | view/dismiss only; low stakes; dismiss is intentional self-service write |
| `default_simulator` | SAFE_BY_CONTRACT | read-only dialplan simulation |
| `default_snep` | DEAD/UNREACHABLE | legacy redirect to `/` |

No other endpoint shared the exact confirmed ITC defect closely enough to
fold into this task without broadening scope.

## FOLLOW_UP_DEBT / REMAINING LEGACY ITC DEBT

1. `IndexController::addAction` and GET `?dashboard_add=` -- authenticated
   alwaysAllow mutation of per-user dashboard preferences (not system-wide
   ITC state).
2. `RegisterController` unregistered GET (when enabled) clears session
   `noregister` and redirects -- soft re-prompt side effect.
3. Menu link to Register remains when ITC disabled (DISPLAY_ONLY).
4. Notifications dismiss under alwaysAllow -- intentional self-service;
   document-only unless a future audit reclassifies vendor-notice writes.
5. Carry-forward from 0034M/0034N: CNL upload `unlink()` cleanup;
   symlink-entry defense-in-depth.
6. Do not build the replacement portal in this task (explicit non-goal).

(Auth login ITC hydrate/seed while disabled was closed in this task --
gated behind `Snep_Register_Manager::isEnabled()`; standalone login
performs zero ITC DB activity.)

## VALIDATION

Focused:

- `itc-registration-authorization-security-smoke-test.sh` — see checkpoint
- `authorization-smoke-test.sh` — prior 51 PASS (authz sibling suite)

Canonical gates: see final checkpoint (lint + two consecutive regressions).

## GATE-ENV REMEDIATION (not ITC product logic)

During full regression validation of this task:

1. `scripts/smoke-test.sh` (http-smoke) previously accepted only HTTP 200
   dashboard or registration layout at `GET /index.php/`. With
   `itc_enabled=false` and an empty dashboard, IndexController redirects
   `302 -> /index.php/index/add` (pre-existing non-ITC branch). The smoke
   now accepts that core empty-dashboard landing.
2. **Root cause of mid-regression `system-status-runtime-smoke` FAIL:**
   the ITC smoke used host-side `sed -i` on the bind-mounted
   `snep/includes/setup.conf`, which rewrote the file as the host user
   (uid 1000). System Status "File Permissions" then stayed red for every
   later suite because `www-data` could not `is_writable()` that file.
   Fix: after every host edit, restore `www-data:www-data` mode 664;
   cleanup handlers do the same. Defense-in-depth: system-status smoke
   retries and restores setup.conf ownership when that panel is red.
3. App entrypoint also re-asserts AGI tree writability on boot (bind-mount
   drift defense for "Environment for AGI SNEP").
4. Earlier gate remediations (backup staging chmod / GNU `stat -c`) remain
   as a separate thematic commit candidate from the ITC boundary work.
