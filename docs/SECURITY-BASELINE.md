# SENMA PBX — Security baseline

Operational reference for the security posture established by the
TASK-0026 remediation program (0026A–I/F1) and closed out by TASK-0026Z
(`docs/tasks/0026z-security-audit-closure.md`). This is not a historical
narrative — see `docs/tasks/0026-pre-pilot-security-release-audit.md` for
that. This document describes current, supported behavior only, and must
be updated whenever a change alters any invariant below.

## Authentication model

- Browser login (`AuthController::loginAction()`) and the standalone API
  (`snep/modules/default/api/index.php`) both authenticate through the
  same `Snep_Auth_Adapter_Password` (`snep/lib/Snep/Auth/Adapter/Password.php`)
  — one password semantic across both entry points.
- Identity lookup is case-sensitive, parameterized (`name = BINARY ?`).
- A stored password hash submitted *as* the credential never
  authenticates (no pass-the-hash) — verified structurally by
  `password_verify()`'s asymmetry and, for the legacy-MD5 branch, by
  never comparing the stored value against itself.
- The standalone API has no per-service authorization tier: any account
  with valid credentials can call any registered service in
  `snep/modules/default/api/actions/`. This is a deliberate, pre-existing
  architectural property, not a regression.

## Password-hash policy

- New/changed passwords: `password_hash()` with `PASSWORD_DEFAULT`,
  SHA-256-normalized first to avoid bcrypt's 72-byte truncation
  (`Snep_Security_Password`, `snep/lib/Snep/Security/Password.php`).
- Legacy unsalted-MD5 accounts authenticate once against the legacy
  representation, then migrate transparently to the modern hash on that
  same successful login (`needsRehash()`/`Snep_Auth_Adapter_Password`).
  No forced batch migration; no account is ever locked out by this.
- Minimum password length: `Snep_Security_Password::MIN_LENGTH = 8`
  bytes, enforced server-side on every password-setting flow (add, edit,
  password recovery). No complexity (uppercase/digit/symbol) rules.

## Session / cookie policy

- Session ID regenerates on every successful login
  (`Zend_Session::regenerateId()`); the pre-login session id cannot reach
  an authenticated page afterward.
- Logout destroys the entire session (`Zend_Session::destroy()`), not
  only the `Zend_Auth` identity namespace.
- Cookie attributes (`Snep_Session_CookiePolicy`,
  `snep/lib/Snep/Session/CookiePolicy.php`, applied before
  `Zend_Session::start()`): `HttpOnly` always on; `SameSite=Lax` always
  on; `Secure` on only when the request is detected as HTTPS (direct
  `HTTPS`/port 443, or `X-Forwarded-Proto: https` — the latter trusted
  only when `SENMA_TRUST_PROXY_HTTPS=1` is explicitly set, since this
  project's current Docker topology has no reverse proxy in front of
  `app`).

## CSRF policy

- `Snep_CsrfPlugin` (`snep/modules/default/model/CsrfPlugin.php`),
  registered alongside `Snep_PermissionPlugin`, only when a session
  identity exists — so it never runs for an unauthenticated request and
  automatically excludes `AuthController`'s pre-auth actions.
- Every authenticated POST to the main MVC application requires a valid,
  session-bound token (`Snep_Security_Csrf`,
  `snep/lib/Snep/Security/Csrf.php`) via the `snep_csrf_token` POST field
  or the `X-Snep-Csrf-Token` header. One exemption exists:
  `default_systemstatus_restart-dispatch`, which keeps its own
  independent, already-hardened TASK-0021/0022 CSRF mechanism.
- The standalone Basic-auth API is not routed through
  `Zend_Controller_Front` and carries no CSRF token — by architecture,
  not by omission (stateless, non-browser, non-session).
- No known state-changing GET remains reachable in the supported,
  browser-facing surface.

## Authorization default-deny invariant

- `Snep_PermissionPlugin` denies by default: every action on a
  registered resource requires `*_read` (index/explicit read-only
  actions) or `*_write` (everything else) unless the controller is on a
  small, explicitly reviewed authenticated-open allowlist.
- An unregistered controller/action is denied, not silently allowed.
- `scripts/authorization-coverage-check.sh` is a deterministic static
  gate: every controller must be resource-registered, an allowlisted
  authenticated-open controller, or a resource alias — a new
  controller/action cannot silently reintroduce the pre-TASK-0026A
  implicit-allow gap.
- Superuser (`$_SESSION['id_user'] == "1"`) retains a bypass; CSRF
  enforcement does not share this bypass.

## Supported API authentication behavior

- `snep/modules/default/api/index.php` requires HTTP Basic credentials
  on every request (stateless); both credential-parsing branches
  (`HTTP_AUTHORIZATION` header and `PHP_AUTH_USER`/`PHP_AUTH_PW`) apply
  identical normalization.
- `$_GET['service']` is only ever used as a lookup key into a fixed,
  hardcoded registry of 7 known service names — never concatenated into
  a filesystem path.
- Every read-only SQL sink in `api/actions/*.php` is parameterized
  (`quoteInto()`/`quote()`/`(int)` casts) or reaches an identifier
  allowlist (`CSV_ExportDataService`).

## Default-admin / bootstrap behavior

- The install seed no longer ships an operational credential: `admin`'s
  seeded password is the sentinel `!SENMA-BOOTSTRAP-PENDING!`, which
  cannot authenticate under any submitted value.
- `docker/entrypoint.sh` invokes `docker/bootstrap-admin.php` on every
  container start; the script is idempotent — it only acts while the
  sentinel is still in place, generating a random 128-bit credential,
  hashing it, and printing it once to container stdout
  (`docker compose logs app` / `make logs`).
- Fresh installs have no usable admin credential until bootstrap runs
  and its one-time console output is read.

## Login rate limiting

- `Snep_Security_LoginThrottle` (`snep/lib/Snep/Security/LoginThrottle.php`),
  backed by the `login_attempts` table.
- `MAX_FAILURES_PER_ACCOUNT = 5` within a 15-minute window, scoped to
  `(source IP, username)` — a different source's failures against the
  same username don't count together.
- `MAX_FAILURES_PER_IP = 20` within the same window, scoped to the
  source IP alone (credential-stuffing/scanning guard).
- Both windows auto-expire; a successful login clears only that exact
  `(ip, username)` pair's failure history.
- Scope: browser login only. The standalone API has no rate limiting
  (stateless Basic-auth has a different threat shape; tracked as
  Product Readiness debt, not a pilot blocker on its own).

## Security regression command

```bash
make lint
make regression
```

`make regression` runs 21 suites serially (see
`docs/tasks/0026z-security-audit-closure.md` §"Security regression
inventory" for the full list and per-suite purpose) and never treats
FAIL/BLOCKED/INCONCLUSIVE as PASS.

## Security gate expectations

A release candidate's security gate is `GO` only when every criterion in
TASK-0026Z's Phase 6 holds, most notably:

```text
known unauthenticated RCE = 0
known SQL injection = 0 in supported surfaces
known shell injection = 0 in supported surfaces
known config injection = 0 in supported surfaces
known auth bypass = 0
known pass-the-hash = 0
known CSRF on supported browser mutations = 0
known universal default credential = 0
known path traversal on supported surfaces = 0
canonical security regression = PASS
```

See `docs/tasks/0026z-security-audit-closure.md` for the current gate
state and the reasoning behind it — a green `make regression` alone does
not certify this gate, since the regression suites do not cover every
code path (see that document's "newly discovered security debt" table).

## Deferred Product Readiness security debt

Tracked in full in `docs/tasks/0026z-security-audit-closure.md`
("Product Readiness handoff"). Summary of items with a security
dimension:

- Two confirmed, unremediated SQL-injection sinks outside any prior
  task's scope: `Snep_InterfaceConf.php`'s legacy chan_sip/iax2 trunk
  lookup, and `CallsReportController.php`'s request-driven report-filter
  query construction (main web UI, not the already-hardened API twin).
  **Pilot-blocking** — see the closure document's GO/NO-GO decision.
- Per-controller `getMessage()` → `sneperror.phtml` disclosure sinks
  (`DatesAliasController`, `ExpressionAliasController`,
  `SimulatorController`, `ExtensionsController`) — a distinct, narrower
  disclosure pattern than F25's global handler, never in that finding's
  audited boundary.
- Potential stored XSS via unescaped log content
  (`logs/view.phtml`'s `echo trim($buffer)`), flagged but not confirmed
  reachable, during TASK-0026D.
- Standalone API has no rate limiting (see above).
- Full HTTP security-header rollout (CSP, X-Frame-Options,
  X-Content-Type-Options, Referrer-Policy, HSTS) beyond `expose_php=Off`.
- Reachable `chan_sip`/`iax2` legacy technology selection remains a
  broader Product Readiness / architecture question (whether to keep it
  selectable at all), independent of the SQL-injection debt above.
