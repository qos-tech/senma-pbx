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

## Host-network pilot (TASK-0035E2)

- Pilot/production on a dedicated Linux PBX host uses Docker
  `network_mode: host` for `app` / `asterisk` / `db`
  (`compose.host.yaml`). Dev/regression remains on bridge `compose.yaml`.
- Loopback-only: MariaDB `:3306`, AMI `:5038`, Asterisk HTTP/WS `:8088`.
- HTTP backend (external TLS mode): `0.0.0.0:8080` with
  `/asterisk/ws` → `ws://127.0.0.1:8088/ws`.
- See `docs/tasks/0035e2-host-networking-architecture-local-service-binding.md`.

## Release image immutability (TASK-0035E4 / I4)

- Operational Make targets (`backup`, `reconcile*`, `migrate*`,
  `secrets-check`, `rotate-*`, `doctor`) must **never** rebuild or retag
  release images. They require a running stack (`require-runtime`) or are
  observational.
- `make up` and `make pilot-up` use `--no-build`. Mutable builds are
  explicit (`make dev-build` / `make ensure-dev-stack` for `:dev` only, or
  `make release-build VERSION=…` for release tags).
- `make release-info` fails closed (`UNKNOWN_FATAL` / `DRIFT`) when
  release evidence is missing or disagrees — never a false "no drift"
  without a manifest and OCI labels.
- See `docs/tasks/0035e4-release-immutability-operational-target-hardening.md`.

## Restore runtime topology (TASK-0035E5 / I8)

- Restore preserves **runtime topology** separately from data REPLACE
  semantics. Pilot/production (`RELEASE_VERSION != dev`) recreates
  app/asterisk/db via `compose.yaml` + `compose.pilot.yaml`
  (`network_mode: host`), never bare bridge `compose.yaml`.
- `make restore` wires this automatically; direct `scripts/restore.sh`
  uses `scripts/lib/compose-runtime.sh` and fails closed when ambiguous.
- Restore never builds (`--no-build`) and must leave release image IDs
  unchanged.
- See `docs/tasks/0035e5-restore-runtime-topology-preservation.md`.

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
- TASK-0035E1: the source IP is resolved by `Snep_Security_ClientIp`
  (`snep/lib/Snep/Security/ClientIp.php`). Default (`TRUSTED_PROXY_CIDRS`
  empty) keeps `REMOTE_ADDR` only. When the connecting address is in an
  explicitly configured trusted-proxy CIDR list, `X-Forwarded-For` /
  `X-Real-IP` may supply the real client — never blindly, never via
  trust-all (`0.0.0.0/0`). See
  `docs/tasks/0035e1-trusted-reverse-proxy-client-ip-login-throttle-hardening.md`.
- Scope: browser login only. The standalone API has no rate limiting
  (stateless Basic-auth has a different threat shape; tracked as
  Product Readiness debt, not a pilot blocker on its own).

## Security regression command

```bash
make lint
make regression
```

`make regression` runs 23 suites serially (see
`docs/tasks/0026z-r1-final-security-gate-re-evaluation.md` §7/§8 for the
full current list and per-suite purpose — grown from the 21 at
TASK-0026Z's own checkpoint by TASK-0026J's `residual-sql-security` and
TASK-0026S's `legacy-maintenance-exposure-security`) and never treats
FAIL/BLOCKED/INCONCLUSIVE as PASS.

## Security gate expectations

```text
SECURITY_GATE = GO
```

as of `docs/tasks/0026z-r1-final-security-gate-re-evaluation.md`, which
re-evaluated and superseded TASK-0026Z's original `NO-GO` (the SQL sinks
that drove that NO-GO were closed by TASK-0026J, and every sibling found
by the closure chain that followed — TASK-0026K through TASK-0026R — was
in turn closed; TASK-0026S then closed the one non-SQL finding TASK-0026R's
own post-remediation sweep surfaced). A release candidate's security gate
is `GO` only when every criterion in that document's own Phase 10/§11
holds, most notably:

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
known unauthenticated DB-mutating maintenance endpoint = 0
canonical security regression = PASS (twice consecutively)
```

See `docs/tasks/0026z-r1-final-security-gate-re-evaluation.md` for the
current gate state and full reasoning, and
`docs/tasks/0026z-security-audit-closure.md` for the historical first
closure attempt it reconciles (left unmodified as the historical record)
— a green `make regression` alone does not by itself certify this gate;
it is one of several criteria evaluated explicitly.

## Deferred Product Readiness security debt

Tracked in full in `docs/tasks/0026z-r1-final-security-gate-re-evaluation.md`
§10 (current) and `docs/tasks/0026z-security-audit-closure.md` §12
(historical origin of most items). Summary of items with a security
dimension, none of which is pilot-blocking:

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
  selectable at all) — the SQL-injection sink previously at this exact
  boundary (`Snep_InterfaceConf.php`) is closed (TASK-0026J).
- `snep/agi/*.php` is web-reachable (same unrestricted document root
  `snep/install/` had before TASK-0026S) but non-productive — a plain
  HTTP request hangs on `Asterisk_AGI`'s constructor blocking on a stdin
  protocol-handshake read that never arrives (TASK-0026Q). A distinct
  subtree from TASK-0026S's own fix, not yet remediated; candidate for
  the same `.htaccess`-deny pattern in a small dedicated future task.

Two items previously listed here as pilot-blocking are now closed:
the `Snep_InterfaceConf.php`/`CallsReportController.php` SQL sinks
(TASK-0026J, confirmed by the full TASK-0026K–R closure chain) and the
unauthenticated web-reachable DB-mutating maintenance scripts
(TASK-0026S).
