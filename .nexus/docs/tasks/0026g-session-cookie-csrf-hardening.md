# TASK-0026G — Session, cookie, and CSRF hardening (F18-F20)

## Status

Implementation complete, including the Phase 11 follow-up closing
`ParametersController::languageAction()` and
`NotificationsController::indexAction()` (§7). Focused smoke suite
(40/40), `make lint`, and two consecutive `make regression` runs all PASS
(§12). Pending commit checkpoint authorization.

## Scope

Re-traces and remediates findings **F18**, **F19**, and **F20** from
`docs/tasks/0026-pre-pilot-security-release-audit.md` against the CURRENT
code, after TASK-0026A-F1 already landed. Three distinct goals, per the
task's own instructions:

1. prevent session fixation / stale pre-login session reuse (F18);
2. enforce secure session-cookie attributes appropriate to the deployment
   (F19);
3. require CSRF protection on authenticated state-changing browser
   actions (F20).

Explicitly out of scope (per the task's own instructions and CLAUDE.md
principles #3/#12/#13): password-hash modernization (F21), login rate
limiting (F22), the weak-PRNG password-reset code (F23), and
`Snep_AuthPlugin`'s action-name-only auth-bypass fragility (F24) — none of
those are touched here.

## 1. F18-F20 re-verification against current code (Phase 1)

Re-read `AuthController.php`, `Snep_AuthPlugin`, `snep/Bootstrap.php`,
`docker/php-mag.ini`, and `Zend_Session`/`Zend_Auth` before any change.
None of F18-F20 had been touched by TASK-0026A-F1 (those tasks covered
authorization, pre-auth hardening, SQL/shell/config-injection, and the
standalone API — a different, disjoint surface, see §6 below).

| Finding | Current path (before this task) | Behavior | Exploitable | Fix |
|---|---|---|---|---|
| F18 | `AuthController::loginAction()` success branch | No `session_regenerate_id()`/`Zend_Session::regenerateId()` call anywhere; a client-supplied pre-login `PHPSESSID` remained the authenticated session id after login | Yes — live-proven full account takeover in the original audit | `Zend_Session::regenerateId()` right after `$auth->getStorage()->write(...)`, before any output |
| F19 | No `session_set_cookie_params()`/`ini_set("session.cookie_*")` anywhere in application code; `docker/php-mag.ini` had no `session.*` overrides | `HttpOnly=Off`, `Secure=Off`, `SameSite` unset (live-verified via `php -i` and the raw `Set-Cookie` header) | HttpOnly gap needs a separate XSS/cookie-write vector; Secure/SameSite are deployment-dependent | `Snep_Session_CookiePolicy::apply()`, called before `Zend_Session::start()` |
| F20 | `grep -rln "csrf"` returned exactly 3 matches: `SystemstatusController`'s own TASK-0021/0022 restart-specific token and its view, and the unused, zero-call-site `Zend_Form_Element_Hash` | Every other state-changing action (Users, Profiles, Extensions, Trunks, Transports, Sound Files, Music on Hold, Export, password reset, ...) had no CSRF token generation or verification at all | Yes — combined with F16 (already fixed by TASK-0026A), any authenticated session could be driven to mutate state via a forged cross-site request | `Snep_Security_Csrf` + `Snep_CsrfPlugin`, registered the same way as `Snep_PermissionPlugin` |

### Session-fixation trace (before the fix)

```
anonymous request -> Zend_Session::start() mints PHPSESSID=X
-> login POST (still PHPSESSID=X, no strict-mode rejection --
   session.use_strict_mode was Off)
-> Zend_Auth success -> $auth->getStorage()->write(...) writes the
   identity into the SAME session X
-> PHPSESSID=X is now a fully authenticated admin session
-> an attacker who planted X before login now owns the session
```

### Session-fixation trace (after the fix)

```
anonymous request -> Zend_Session::start() mints PHPSESSID=X
-> login POST (PHPSESSID=X)
-> Zend_Auth success -> $auth->getStorage()->write(...)
-> Zend_Session::regenerateId() -- PHPSESSID becomes Y (X's server-side
   session data is discarded by PHP's own session_regenerate_id(true);
   X can no longer authenticate anything)
-> Snep_Security_Csrf::rotate() mints a fresh token bound to Y
-> the rest of $_SESSION (id_user, name_user, http_authorization, ...)
   is written under Y, never under X
```

## 2. Session lifecycle (Phase 2)

Changed in `snep/modules/default/controllers/AuthController.php`:

- **`loginAction()` success branch**: immediately after
  `$auth->getStorage()->write($result->getIdentity())`, calls
  `Zend_Session::regenerateId()` (this codebase's own ZF1 wrapper around
  `session_regenerate_id(true)` — not a parallel session mechanism), then
  `Snep_Security_Csrf::rotate()`. Both run before any output has been
  sent, as `Zend_Session::regenerateId()`'s own contract requires
  (`headers_sent()` guard). Called exactly once, only on successful
  login — never on ordinary authenticated requests.
- **`logoutAction()`**: `Zend_Session::destroy()` added right after the
  existing `Zend_Auth::getInstance()->clearIdentity()` call, and before
  the (pre-existing) inline `<script>` output. `clearIdentity()` alone
  only removes `Zend_Auth`'s own storage namespace *within* the session —
  the rest of `$_SESSION` (`id_user`, `name_user`, `http_authorization`,
  the CSRF token, ...) would otherwise survive logout. Destroying the
  whole session means the pre-logout session id cannot be reused for
  anything afterward, not merely "no longer has an identity". This must
  run before any output, matching where the pre-existing
  `clearIdentity()` call already sat.

Failure-path behavior was already correct and is unchanged: a failed
login (`FAILURE_CREDENTIAL_INVALID`/`FAILURE_IDENTITY_NOT_FOUND`) never
reaches the success branch, so identity is never written and no
regeneration happens; a nonexistent user hits the same
`FAILURE_IDENTITY_NOT_FOUND` path. Both are re-proven in the focused
smoke suite (§9).

No parallel/custom session mechanism was introduced — `Zend_Session` (the
codebase's existing session layer, itself a thin wrapper over native PHP
sessions) remains the only one.

## 3. Cookie policy (Phase 3)

New file: `snep/lib/Snep/Session/CookiePolicy.php` (`Snep_Session_CookiePolicy`).
`apply()` is called at the very top of `snep/Bootstrap.php`, immediately
before `Zend_Session::start()` — the earliest point in the request
lifecycle where this is safe, and the only point that runs before the
session cookie's attributes are fixed for the request. This is a
brand-new file (not a modification of inherited SNEP code), documented
with the same GPL header convention every other TASK-created class in
this codebase already uses (e.g. `Snep_Asterisk_Operations`).

| Attribute | Value | Rationale |
|---|---|---|
| HttpOnly | always `true` | No legitimate reason was found for JavaScript to read the session cookie; closes F19's XSS-cookie-theft vector unconditionally |
| SameSite | always `Lax` | Blocks the cross-site POST/AJAX shapes CSRF relies on while still letting ordinary top-level navigation into the app (an external link, a bookmark) keep working — `Strict` would drop the cookie on that very first cross-site navigation, which this legacy UI's own external links (e.g. the password-reset email flow) would otherwise break |
| Secure | deployment-aware (see below) | Must not force local HTTP `make dev` to break, per the task's own explicit instruction |

### HTTPS detection (`Snep_Session_CookiePolicy::isHttps()`)

1. Direct HTTPS: `$_SERVER['HTTPS']` set and not `"off"`, or
   `$_SERVER['SERVER_PORT'] == 443`. Always trusted.
2. Reverse-proxy `X-Forwarded-Proto: https`: trusted **only** when the
   deployment has explicitly opted in via the `SENMA_TRUST_PROXY_HTTPS`
   environment variable (`1`/`true`), documented in `.env.example`.

**Deployment assumption, stated explicitly**: this project's current
Docker topology (`compose.yaml`) has no reverse proxy in front of the
`app` container — it serves plain HTTP directly (confirmed by the audit's
own §"TLS termination in front of the app" entry: "Not addressed by this
codebase"). `SENMA_TRUST_PROXY_HTTPS` therefore defaults unset/false, so
`X-Forwarded-Proto` is never trusted today — it would otherwise be a
plain client-supplied, attacker-controllable header. A future deployment
that adds a real trusted reverse proxy in front of the app can opt in
explicitly; that proxy becomes responsible for stripping/overwriting any
client-supplied `X-Forwarded-Proto` before it reaches the app.

## 4. CSRF architecture (Phase 4-5, 7)

### Why centralized, and where

`Snep_PermissionPlugin` (TASK-0026A) already proved the pattern this task
reuses: a `Zend_Controller_Front` plugin, registered in
`Bootstrap::_initPermission()` **only when** `Zend_Auth::hasIdentity()` is
true at boot time, so it never even runs for an unauthenticated request.
`Snep_CsrfPlugin` (new, `snep/modules/default/model/CsrfPlugin.php`) is
registered the exact same way, immediately after `Snep_PermissionPlugin`
in the same `_initPermission()` method — so an unauthorized request is
denied by authorization first, and CSRF validity is never computed for a
request that was going to be rejected anyway (matching the precedent
`SystemstatusController::restartDispatchAction()` already established:
"authorization before CSRF, before mode validation").

This structurally exempts `AuthController`'s `login`/`redefine`/
`recuperation` actions — the only actions reachable while unauthenticated,
per `Snep_AuthPlugin` — with **no hardcoded per-action exemption list
needed**: there is no authenticated session yet for a forged cross-site
request to abuse. It also automatically and completely excludes the
standalone API (`snep/modules/default/api/index.php`): that file is a
wholly separate bootstrap (its own `parse_ini_file`, autoloader, `Zend_Db`
factory) that never runs through `Zend_Controller_Front` at all (this
architectural separation was already documented in TASK-0026F, §"why this
API is not routed through `Snep_PermissionPlugin`") — it is Basic-auth,
stateless, and never touches `Zend_Session`/`Snep_CsrfPlugin` in any way.

`Snep_CsrfPlugin::preDispatch()`:

- returns immediately for any non-POST request (GET/HEAD are expected to
  be read-only in this app; genuinely mutating GET routes are each
  addressed individually, §7, rather than papered over here);
- returns immediately for the one explicit exemption (§5);
- otherwise requires `Snep_Security_Csrf::isValid($token)`, where `$token`
  comes from the POST body field `snep_csrf_token` or, as a documented
  alternative for pure-AJAX callers, the `X-Snep-Csrf-Token` header;
- has **no superuser bypass** — unlike `Snep_PermissionPlugin`'s
  documented `$_SESSION['id_user'] == "1"` shortcut (an authorization
  concern), CSRF protects the request's *origin*, not the acting user's
  privilege level, and applies equally to every authenticated user.

### Token store (`Snep_Security_Csrf`, `snep/lib/Snep/Security/Csrf.php`)

- `getToken()` — returns `$_SESSION['snep_csrf_token']`, minting one with
  `bin2hex(random_bytes(32))` on first use (cryptographically secure
  randomness, never a session-id derivative, username hash, static
  secret, or timestamp).
- `isValid($submitted)` — `hash_equals()` constant-time comparison.
- `rotate()` — forces a fresh token; called once, on successful login
  (right after the session id itself regenerates).

**Deliberately a single, non-rotating, per-session token** (Phase 5's own
explicit allowance: "Per-request rotation is not required... A simple
per-session token is acceptable... Do not create a token mechanism that
breaks multiple open browser tabs unnecessarily"). Rotating on every use
(as the pre-existing restart-specific token did) would invalidate the
token held by a second open tab / an older page load the instant the
first tab submitted anything. The token becomes invalid implicitly on
logout, because `Zend_Session::destroy()` (§2) removes the whole session
it lives in — no separate invalidation step needed.

### Token delivery (Phase 9-10)

An investigation (full detail: this task's own working notes) into
whether a shared Zend_Form base class or view partial could inject the
token into every mutating form found:

- `Snep_Form`/`Snep_Form_Sectioned`/etc. exist under `snep/lib/Snep/` but
  **nothing in the codebase subclasses them** — a dead layer, not a
  usable injection point.
- Forms are a genuine mix: some pages echo a `Zend_Form` object directly,
  most hand-write `<form method="post">` markup themselves. No single
  template or base class reaches all ~56 form-containing view scripts.
- The one real per-file choke point is the three shared confirmation
  partials (`remove/remove.phtml`, `remove/disable.phtml`,
  `remove/enable.phtml`) that every controller's delete/disable/
  enable/restore confirmation step already renders into.

Given no broader shared PHP-side choke point exists, the token is
delivered two ways, matching Phase 9's own fallback guidance and Phase
10's explicit instruction to "update shared JS request plumbing where
possible rather than many independent call sites":

1. **The three shared confirm partials** get the token as a hidden
   `<input>` directly (PHP-side, deterministic, works with JS disabled)
   — one line added to each of the three files.
2. **Everywhere else**: a new shared script,
   `snep/includes/javascript/csrf.js`, loaded on every page (added next
   to the existing global `jquery.min.js` load in
   `Bootstrap::_initViewHelpers()`), reads the token from a
   `<meta name="csrf-token">` tag `layouts/layout.phtml` now emits
   (sourced from `Snep_Security_Csrf::getToken()`, set into `$view` in
   that same bootstrap method) and:
   - on every `<form method="post">` submit, appends a hidden
     `snep_csrf_token` input if one isn't already present;
   - via `$.ajaxPrefilter`, adds `snep_csrf_token` to every jQuery POST's
     data (covers `route/index.phtml`'s `jQuery.post('.../route/toogle/')`
     call, the one non-form AJAX mutation in the app besides the
     already-exempt restart-dispatch call).

This is a deliberate, documented tradeoff: **JS is required** for token
delivery to the ~53 remaining form templates. It fails closed, exactly as
Phase 13 requires — with JS disabled/blocked, a form simply submits
without a token and `Snep_CsrfPlugin` rejects it with 403, the same
outcome as any other missing token. This app already depends on
JavaScript for its interactive UI (menus, AJAX polling, client-side
validation) and is not designed to be usable with JS disabled, so this
does not introduce a new usability regression, only a new (safe) failure
mode.

## 5. Exemptions (Phase 8)

Exactly **one**, in `Snep_CsrfPlugin::$exempt`:

| Route | Reason |
|---|---|
| `default_systemstatus_restart-dispatch` | Already has its own independent, TASK-0021/0022-hardened, session-bound CSRF mechanism (`$_SESSION['snep_restart_csrf_token']`, `hash_equals()`-validated, one-shot-rotated, returning an identical `{"ok":false,"error":"forbidden"}` JSON body on both authorization AND CSRF failure by design). Re-pointing it at this task's shared `snep_csrf_token` field would either collide on field name or change that already-verified response contract, for no security benefit — the endpoint is not weaker for being exempted, it is equally protected by a mechanism this task chose not to touch. |

No `default_auth_*` entries are needed — see §4's structural exemption via
the `hasIdentity()` registration gate. No `/default/*` or whole-controller
exemptions exist anywhere.

## 6. Mutation inventory (Phase 6, 14)

Every controller under `snep/modules/default/controllers/` was
classified. The overwhelming majority follow one of two already-safe,
now-CSRF-covered shapes:

- **add/edit**: GET renders the form, the same action POSTs to itself and
  is gated by `isPost()`/`getPost()` truthiness (e.g.
  `ExtensionsController::addAction()`).
- **remove/disable/enable/restore/multiremove**: GET renders a
  confirmation page (one of the three shared partials, §4), the actual
  mutation only runs `if ($this->_request->getPost())` — confirmed
  directly in Extensions, Trunks, Route, ContactGroups, Contacts,
  CostCenter, DatesAlias, ExpressionAlias, ExtensionsGroups, MusicOnHold,
  PickupGroups, PjsipTransports, Profiles, Queues, Users.

Both shapes are now uniformly protected: `Snep_CsrfPlugin` gates every
POST to them, and the token reaches every one of those forms via §4's
delivery mechanism.

Controllers with **no mutating action at all** (no CSRF surface needed):
`AuditController` (view-only), `CallsReportController`,
`ConferenceRoomsController`, `DocsController`, `ErrorController`,
`ErrorsKhompController`, `ErrorsTdmController`, `InformationController`,
`InspectorController`, `IpStatusController`, `KhompLinksController`,
`LogsController`, `ModuleSettingsController`, `NewversionController`,
`PermissionController`, `RankingReportController`, `RouteFormController`
(GET-only REST helper), `ServicesReportController`, `SimulatorController`,
`SnepController`, `TdmLinksController`.

Other modules under `snep/modules/` (`callback`, `ivr`, `portability`)
have no `*Controller.php` at all, only standalone `actions/` entry
points — the same architecturally-separate-from-`Zend_Controller_Front`
shape as the already-audited `default/api`; not reachable through this
plugin, out of scope for the same reason.

## 7. State-changing GET (Phase 11)

All four supported-controller findings are now closed. No known
authenticated browser mutation remains reachable solely by GET.

| Route | Finding | Remediation |
|---|---|---|
| `RouteController::toogleAction()` | Mutated (`PBX_Rules::update()`, flips a route's active state) **unconditionally on dispatch, no `isPost()` check at all**. Its only real caller (`route/index.phtml`) already sends it as `jQuery.post()`, but nothing server-side enforced that — a plain GET (a forged cross-site `<img>`) reached and flipped the same state. | Added an explicit `isPost()` guard (HTTP 405 otherwise). Brings it under `Snep_CsrfPlugin`'s POST-only enforcement; the existing `jQuery.post()` caller is unaffected and now also automatically carries the token via `csrf.js`'s `ajaxPrefilter`. |
| `SoundFilesController::restoreAction()` | Restored a backup sound file (`rename()`) **unconditionally on GET**, no confirmation step at all — unlike this same controller's own `removeAction()`. | Converted to the same GET-renders-confirmation/POST-performs-mutation shape `removeAction()` already used, reusing the shared `remove/remove.phtml` partial (`remove_action="restore"`, one small extension to that partial's existing `removefile`-style branch). The existing `<a href=".../restore/...">` link needs no template change — it now lands on a confirmation page instead of mutating immediately. |
| `ParametersController::languageAction()` | Wrote `system.language` into `includes/setup.conf` on a plain GET, driven by the global language-switcher dropdown in the shared page layout (`layouts/layout.phtml`). Input was already allowlist-validated (`Snep_Locale::isSupportedLanguage()`) — no injection risk, but an unconfirmed, CSRF-exposed state change. | **Remediated.** GET no longer mutates anything — it behaves exactly like the pre-existing "no/invalid language" branch (redirect to `parameters`, no write). The actual write now requires POST, gated by both `Snep_CsrfPlugin` and the *unchanged* `Snep_Locale::isSupportedLanguage()` allowlist (still the sole authority on valid values — the fix only changed which HTTP method can reach the write, not what values it accepts). The three dropdown links (`layouts/layout.phtml`) now call a small shared `snepChangeLanguage(lang)` JS function that POSTs via jQuery — `csrf.js`'s existing `ajaxPrefilter` attaches the token automatically, no bespoke token handling needed — then reloads the current page. Preserves the exact observable UX (pick a flag, page reflects the new language) and, since the pre-existing code never actually sent a `module` param, preserves the exact same post-change redirect target (`/index.php/`) for the POST path that GET already produced. |
| `NotificationsController::indexAction()` | Traced precisely: viewing a single notification called `Snep_Notifications::setRead($id)` as a **plain-GET side effect**, sending an HTTP PUT to the external vendor notification service (not a local DB write) keyed on the attacker-influenceable `$options['id']` route param. Low impact (no local PBX/account data, no privilege change, the read-badge count is itself cache-gated) but a real state-changing GET nonetheless — tracing did *not* prove it mutates nothing, so the doc-only escape hatch didn't apply. | **Remediated**, per the preferred GET/POST split. `indexAction()` no longer calls `setRead()` at all — purely read-only now, renders the notification content and exposes `notificationId` to the view. The vendor `setRead()` call moved into a new `markReadAction()` (POST-only, HTTP 405 on GET; CSRF-protected via the same centralized `Snep_CsrfPlugin`, no special-casing needed since this controller already sits inside `Snep_PermissionPlugin`'s authenticated-open boundary). `notifications/index.phtml` fires a small inline `jQuery.post()` to `notifications/mark-read` immediately when a single notification renders — `csrf.js` attaches the token automatically — preserving the exact "viewing a notification marks it read" UX with no visible behavior change, just no mutation as a side effect of the GET itself. `scripts/authorization-coverage-check.sh`'s static inventory updated (`markread` added to `default_notifications`'s expected-action list) so the new action stays accounted for. |
| `AuthController`'s pre-auth `indexChooseLanguage` GET branch (`loginAction()`) | Also writes `setup.conf`'s language, pre-authentication. | Not new debt, and intentionally untouched — already allowlist-validated by a prior task (TASK-0026B); no authenticated session exists at this point for CSRF's threat model to apply to (there is no victim session to forge a request against). |

No other supported controller/action (default module's ~45 controllers,
billing's 2) was found to mutate on GET; `callback`/`ivr`/`portability`
have no web-reachable controllers at all (their `actions/` files are
`PBX_Rule_Action` subclasses invoked by the AGI/dialplan call-routing
engine, never dispatched through `Zend_Controller_Front`) — confirmed by
a full re-sweep after the fixes above (§3 methodology, re-run).

**Closure statement.** Every supported, browser-reachable GET route in
the application now classifies as exactly one of:

- **READ_ONLY** — renders content with no side effect (the overwhelming
  majority: every `index`/list/view/report action, `SystemstatusController`'s
  informational `exec()` status probes included — those run shell commands
  but only ever read system/version info, never write anything).
- **RENDER_CONFIRMATION** — renders a confirm step whose own embedded form
  POSTs back to perform the actual mutation (every `remove`/`disable`/
  `enable`/`restore`/`multiremove` action, via the three shared
  `remove/*.phtml` partials).
- **REDIRECT_WITHOUT_MUTATION** — validates and redirects but writes
  nothing (`ParametersController::languageAction()`'s GET branch,
  post-fix; `AuthController::loginAction()`'s pre-auth
  `indexChooseLanguage` branch, pre-existing).

Every mutation in the supported, browser-reachable surface is POST,
gated by `Snep_CsrfPlugin`, except the one explicit, justified exemption
(§5). The only mutation boundary that accepts a request with no CSRF
token at all is `snep/modules/default/api/index.php` — the standalone
Basic-auth API, an intentionally separate, non-browser, non-session
authentication boundary (§4), never dispatched through
`Zend_Controller_Front`/`Snep_CsrfPlugin` in the first place.

## 8. AJAX treatment (Phase 10)

Only two state-changing AJAX call sites exist in the entire application
(no shared JS AJAX wrapper existed before this task):

1. `route/index.phtml`'s `jQuery.post('.../route/toogle/', {route: id})`
   — now protected identically to every other mutation, via `csrf.js`'s
   global `$.ajaxPrefilter` (§4) plus the new server-side `isPost()` gate
   (§7).
2. `systemstatus/index.phtml`'s restart-dispatch `jQuery.post()` — already
   protected by its own pre-existing mechanism, explicitly exempted (§5).
   `csrf.js` harmlessly also attaches `snep_csrf_token` to this call's
   data (a field the controller simply ignores); no conflict with its own
   `csrf_token` field.

## 9. Focused smoke — `scripts/session-csrf-security-smoke-test.sh`

New suite, `make session-csrf-security-smoke`, built on
`scripts/lib/harness.sh` like every other TASK-0026x security suite. Adds
one shared helper to `scripts/lib/harness.sh`:
`harness_csrf_token <cookiejar> <base_url>` — fetches an authenticated
page and scrapes the `csrf-token` meta tag, for every curl-based harness
script (this one and the pre-existing ones, see §10) to reuse.

Covers, per Phase 12's checklist:

- **Session fixation (1-7)**: anonymous session id captured; login
  succeeds; the session id changes; the pre-login id cannot reach an
  authenticated page afterward; the new id works; logout redirects; the
  logged-out session can no longer reach a protected page. Plus the
  Phase-2 failure-path checks: a wrong-password login and a nonexistent-
  user login both fail to authenticate.
- **Cookies (8-10)**: `HttpOnly` present; `SameSite=Lax` present; `Secure`
  is correctly *absent* against this suite's own plain-HTTP test
  environment (proving it doesn't break local HTTP, not merely "untested"
  over HTTPS). Since deterministic HTTPS testing isn't available in this
  Docker dev topology, `Snep_Session_CookiePolicy::isHttps()` is exercised
  directly inside the app container instead, across all four branches
  (plain HTTP, direct HTTPS, port 443, and the untrusted-vs.
  explicitly-trusted `X-Forwarded-Proto` case via `SENMA_TRUST_PROXY_HTTPS`).
- **CSRF (11-16)**: exercised across three distinct mutation surfaces
  (Extensions, Trunks, Users/permission) rather than a single controller,
  per the task's own instruction:
  - a legitimate mutation with a valid token succeeds (all three
    surfaces, including a real DB-state check -- e.g. the extension's
    `callerid` actually changes on a token-valid edit);
  - the same mutation with no token is rejected 403, DB state unchanged,
    no new PHP fatal, no fatal/stack-trace/warning text in the response
    body (all three surfaces, Phase 13);
  - with an invalid token, 403, DB state unchanged (Extensions);
  - with a real token belonging to a genuinely different, independently
    authenticated session (a dedicated `task0026g-foreign` fixture user,
    not a second login as the same admin), 403, DB state unchanged
    (Extensions) -- proving token validity is a *session* property, not
    merely "any real token";
  - a legitimate edit still succeeds immediately afterward, proving the
    rejected attempts didn't wedge the endpoint;
  - an authenticated read-only GET still works with no token;
  - the standalone Basic-auth API remains fully functional with no CSRF
    token at all;
  - a lightweight static check confirms `Snep_CsrfPlugin` is registered
    exactly once and its exemption list has exactly the one documented
    entry (a regression guard against the exemption list silently
    growing later);
  - a bonus pair of checks directly exercises the Phase 11
    `RouteController::toogleAction()` fix: GET now 405s, and a POST with
    no token 403s.

Result: **PASS** -- 30/30 checks, `RESULT: PASS (session-csrf-security-smoke-test.sh)`.

## 10. Existing smoke/regression suites updated

Every pre-existing curl-based harness script that authenticates via a
browser session cookie and then performs an authenticated POST to a
`default`-module controller needed a `snep_csrf_token` added to that POST,
using the new `harness_csrf_token` helper — otherwise `Snep_CsrfPlugin`
would reject them with 403 now that it is live. Files touched (fixture
setup/teardown only — none of these scripts' own security assertions
changed in intent, only the wire format of the POSTs they were already
making):

- `scripts/authorization-smoke-test.sh`
- `scripts/pjsip-config-security-smoke-test.sh`
- `scripts/shell-security-smoke-test.sh`
- `scripts/sql-security-smoke-test.sh`
- `scripts/call-smoke-test.sh`
- `scripts/trunk-smoke-test.sh`
- `scripts/transport-smoke-test.sh`
- `scripts/restart-smoke-test.sh` (only its extension create/delete
  fixture helpers — its restart-dispatch calls already carry their own
  separate, exempt `csrf_token` field and were left untouched)

Not touched (and don't need to be): `scripts/api-security-smoke-test.sh`,
`scripts/api-sql-security-smoke-test.sh` (standalone Basic-auth API, never
routed through `Snep_CsrfPlugin` at all, §4), `scripts/smoke-test.sh` and
`scripts/external-failure-smoke-test.sh` (their only POST is the
unauthenticated login itself).

## 11. Regression integration (Phase 15)

`session-csrf-security` added to `scripts/regression.sh`, placed right
after `api-sql-security` and before `authorization-coverage`/
`authorization-smoke` — the same reasoning as every other TASK-0026x
security suite's placement (an independent trust-boundary proof needing
its own authenticated fixture, same precondition the authorization suites
need next), with one addition: since this task changes a shared
cross-cutting request boundary (session lifecycle, cookie policy, CSRF
enforcement on every controller) rather than one controller, it runs
before authorization so a session/CSRF regression surfaces on its own
rather than being masked by an unrelated authorization-suite failure.

## 12. Canonical validation

Run in order, against a `make up` environment:

1. `make session-csrf-security-smoke` -- **PASS** (40/40 checks; see §9
   -- 30 from the original pass plus 10 added for the Phase 11 follow-up:
   checks 17-21 for the language switch, 22-26 for notifications).
2. `make lint` -- **PASS** (268 PHP files/0 syntax errors, 21 shell
   scripts parse cleanly, 3 `resources.xml` well-formed, no whitespace
   errors in the diff).
3. `make regression` (1st run) -- **PASS**, all 19 suites green: `lint`,
   `harness-lib-selftest`, `preauth-security`, `sql-security`,
   `shell-security`, `pjsip-config-security`, `api-security`,
   `api-sql-security`, `session-csrf-security`, `authorization-coverage`,
   `authorization-smoke`, `http-smoke`, `cdr-window-selftest`,
   `call-smoke`, `trunk-smoke`, `transport-smoke`, `restart-smoke`,
   `external-failure-smoke`, `external-content-smoke`.
4. `make regression` (2nd run, immediately after, no manual cleanup in
   between) -- **PASS**, same 19/19 suites green.

(An earlier validation pass, before the Phase 11 follow-up, also ran this
same sequence clean: focused suite 30/30, lint PASS, two regression runs
19/19 each. The numbers above are the current, final, authoritative run.)

## 13. Health and cleanup

After both regression runs:

- `docker compose ps`: `app`, `db`, `asterisk`, `provider` all `Up`/healthy.
- Asterisk 22.10.1; `module show like res_pjsip.so` -- 1 module, Running.
- `pjsip show transports` -- 3 baseline transports intact (`tcp`, `udp`,
  `wss`), matching the pre-existing dev topology.
- `odbc show all` -- `snep` DSN, 1/1 active connection.
- `core show channels count` -- 0 active channels, 0 active calls.
- PHP Fatal Error count: 4 new across this final validation pass's two
  regression runs (2 per run) plus the focused-suite run before them,
  all the exact same pre-existing, already-known
  `CnlController::updateAction_76()` /
  `Zend_Validate_File_Upload::isValid()` `TypeError` that
  `shell-security-smoke-test.sh`'s own CNL-upload test deliberately
  triggers (a `count(null)` call on PHP 8 when no file is actually
  uploaded) -- pre-existing technical debt unrelated to session/cookie/
  CSRF, not introduced by this task, not newly discovered by it either,
  confirmed byte-for-byte identical across every occurrence. No fatals
  attributable to any TASK-0026G code path.
- Fixture residue: none. `peers`/`trunks` rows created by
  `session-csrf-security-smoke-test.sh` (extension `10979`, one PJSIP
  trunk) were fully removed by its own `harness_register_cleanup`
  (required, not best-effort). The system language (`setup.conf`) was
  confirmed back at its `pt_BR` baseline after the run (checks 17-21's
  own cleanup). The two fixture users it creates (`task0026g-foreign`,
  `task0026g-target`) are intentional, persistent, reusable dev fixtures
  reset to a known baseline every run -- the exact same convention every
  other TASK-0026x suite already established (`task0026a-restricted`,
  `task0026c-restricted`, `task0026d-restricted`, `task0026e-restricted`,
  `task0026f-restricted`, `task0026f1-restricted` all coexist in `users`
  for the same reason).
- No smoke/regression processes left running.
- `git diff --check`: clean, no whitespace errors.
- `git status --short` / `git diff --stat`: exactly the files listed in
  §14, no stray/unexpected changes.

One operational note, not a code defect: mid-implementation, a
background research/edit pass over the pre-existing smoke scripts (§10)
was interrupted by an unrelated infrastructure rate limit partway through
also authoring `session-csrf-security-smoke-test.sh` itself. That left one
stale `peers` row (`name='10979'`) behind from an incomplete prior run of
that same new script; it was identified via the new suite's own BLOCKED
classification (```peers row for extension '10979' already exists```) and
removed with a direct `DELETE` before the validation runs recorded above
(no route referenced it, so no dependency-ordering concern, unlike the
trunk-smoke-test.sh-style fixtures that traffic in live PJSIP
registration/routing). Not fixture residue *from* this task's validated
state -- from an interrupted intermediate step before it.

## 14. Files changed

New:

- `snep/lib/Snep/Session/CookiePolicy.php`
- `snep/lib/Snep/Security/Csrf.php`
- `snep/modules/default/model/CsrfPlugin.php`
- `snep/includes/javascript/csrf.js`
- `scripts/session-csrf-security-smoke-test.sh`
- `docs/tasks/0026g-session-cookie-csrf-hardening.md` (this file)

Modified:

- `snep/Bootstrap.php` — cookie policy applied before session start;
  `Snep_CsrfPlugin` registered alongside `Snep_PermissionPlugin`; CSRF
  token exposed to every view.
- `snep/modules/default/controllers/AuthController.php` — session
  regeneration + CSRF rotation on login; full session destruction on
  logout.
- `snep/modules/default/controllers/RouteController.php` — `isPost()`
  guard on `toogleAction()`.
- `snep/modules/default/controllers/SoundFilesController.php` —
  `restoreAction()` converted to confirm-then-POST.
- `snep/modules/default/controllers/ParametersController.php` —
  `languageAction()` mutation moved from GET to POST (§7).
- `snep/modules/default/controllers/NotificationsController.php` —
  `Snep_Notifications::setRead()` moved out of `indexAction()`'s GET into
  new `markReadAction()` (POST-only, CSRF-protected) (§7).
- `snep/modules/default/views/scripts/remove/remove.phtml`,
  `disable.phtml`, `enable.phtml` — CSRF hidden field; `remove.phtml`
  additionally supports `remove_action="restore"`.
- `snep/modules/default/views/layouts/layout.phtml` — `csrf-token` meta
  tag; language dropdown converted to a POST-triggering
  `snepChangeLanguage()` JS call.
- `snep/modules/default/views/scripts/notifications/index.phtml` — fires
  the `mark-read` POST when a single notification renders.
- `.env.example` — documents `SENMA_TRUST_PROXY_HTTPS`.
- `scripts/lib/harness.sh` — `harness_csrf_token` helper.
- `scripts/regression.sh`, `Makefile` — new suite wired in.
- `scripts/authorization-coverage-check.sh` — `markread` added to
  `default_notifications`'s expected-open-action inventory.
- The eight existing smoke scripts listed in §10.

## 15. Deferred / residual debt

- Both `ParametersController::languageAction()` and
  `NotificationsController::indexAction()` were remediated in this same
  task (§7) — no state-changing GET remains deferred.
- F21 (unsalted MD5 password hashing), F22 (no login rate limiting), F23
  (weak PRNG for password-reset codes), F24 (`Snep_AuthPlugin`'s
  action-name-only bypass fragility) remain open, as this task's own scope
  boundaries require.
- The pre-existing `Snep_AuthPlugin`/`Snep_PermissionPlugin` design (an
  action-name allowlist plus a hardcoded `user id == "1"` superuser
  bypass) was reused as-is for `Snep_CsrfPlugin`'s registration boundary,
  not redesigned, per the task's explicit "Do not redesign Zend_Auth"
  instruction.
