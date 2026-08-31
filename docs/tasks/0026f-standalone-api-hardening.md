# TASK-0026F — Standalone API authentication and service-resolution hardening (F17)

## Status

Implemented and validated. `make api-security-smoke`, `make lint`, and
`make regression` (two consecutive full runs) all PASS. Not committed —
this is the validated TASK-0026F checkpoint, awaiting explicit
authorization to commit.

## Scope

Re-traces and remediates finding **F17** from
`docs/tasks/0026-pre-pilot-security-release-audit.md` against the
CURRENT code in `snep/modules/default/api/index.php`. F17 has two
distinct defects:

- **F17-A (pass-the-hash)** — two Basic-auth credential-parsing
  branches normalized the password inconsistently: one applied
  `md5()`, one did not. A stored MD5 hash used directly as the
  password authenticated successfully via the unhashed branch.
- **F17-B (path traversal / arbitrary file inclusion)** —
  `$_GET['service']` was concatenated directly into a PHP filename and
  `require_once`'d with only a `file_exists()` check, no allowlist.

Explicitly out of scope (per the task's own instructions, and CLAUDE.md
principles #3/#12/#13 — do not mix migration phases, do not fix
unrelated legacy bugs opportunistically): session/cookie/CSRF hardening
(a future TASK-0026G), migrating password storage to
`password_hash()`/`password_verify()`, login rate limiting,
default-credential removal, any redesign of the main API or the
standalone API's authorization model, PJSIP-only migration, UI/menu/i18n
work, and — critically — the newly-discovered SQL-injection findings in
the individual service files (see "Newly discovered, unremediated
technical debt" below), which are unrelated to F17 and belong to a
dedicated future task of their own.

## Architecture — why this API is not routed through `Snep_PermissionPlugin`

`snep/modules/default/api/index.php` is a standalone entry point with
its own, entirely separate bootstrap: its own `parse_ini_file`, its own
autoloader registration, its own `Zend_Db::factory`, its own
`Zend_Log`. It is never dispatched through the main Zend
`Zend_Controller_Front` / `Snep_AuthPlugin` / `Snep_PermissionPlugin`
stack that governs the rest of the application's session-based web UI.

This is a deliberate, pre-existing architectural separation, not an
oversight this task should "fix": the standalone API is meant to be
called by external HTTP clients using HTTP Basic credentials on every
request (stateless), not by a browser holding a `Snep_AuthPlugin`
session cookie. Routing it through the main MVC stack would require a
broader redesign of how this API authenticates and would change its
public contract for every existing caller — explicitly out of scope
here (Phase 10's instruction). No P0 authorization-bypass finding
(distinct from F17 itself) was discovered while tracing this
architecture.

There is also no per-service authorization/RBAC layer inside the
standalone API itself: any user with valid credentials for *any* row in
`users` can call *any* registered service. This was true before this
task and remains true after it — this task hardens *authentication* and
*dispatch*, not per-service authorization, per Phase 10's explicit
instruction not to redesign API RBAC. This absence is worth a future
product-readiness review but is not a regression introduced or left
newly-discovered by this task (the historical audit's F17 already
implied this by treating "any authenticated user" as the trust
boundary).

## 1. Finding inventory (re-verified against current code and live behavior)

### F17-A — pass-the-hash via inconsistent Basic-auth normalization

Original code (`index.php`, pre-fix):

```php
if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
        if (strpos(strtolower($_SERVER['HTTP_AUTHORIZATION']),'basic')===0)
          list($user,$passwd) = explode(':',base64_decode(substr($_SERVER['HTTP_AUTHORIZATION'], 6)));
}else if (isset($_SERVER['PHP_AUTH_USER'])) {
	$passwd = md5($_SERVER['PHP_AUTH_PW']);
	$user = $_SERVER['PHP_AUTH_USER'];
}
```

The `HTTP_AUTHORIZATION` branch assigns `$passwd` from the raw decoded
header with **no** `md5()` applied; the `PHP_AUTH_USER`/`PHP_AUTH_PW`
branch applies `md5()`. Both values are then compared, unmodified,
against `users.password` (an MD5 hash — see "Password representation"
below) via `Zend_Auth_Adapter_DbTable`. Whichever branch skips hashing
therefore accepts the *stored hash itself* as a valid password.

**Empirical fact discovered during this task's own reproduction**: in
this project's actual Apache/PHP runtime, `$_SERVER['HTTP_AUTHORIZATION']`
is **never populated** for a normal `Authorization: Basic ...` request —
only `PHP_AUTH_USER`/`PHP_AUTH_PW` are populated (confirmed with a
disposable diagnostic script, deployed and deleted within this task).
This means the vulnerable branch was not reachable over real HTTP in
*this exact deployment* — but the fix must not rely on that (a
different Apache/PHP-FPM/CGI configuration, or a reverse proxy that
forwards the raw header, could populate `HTTP_AUTHORIZATION` instead).
Confirmed via a controlled, non-HTTP PHP-level reproduction (bootstrapping
the same Zend/DB stack via `docker compose exec app php <script>`,
exercising the exact pre-fix `HTTP_AUTHORIZATION`-branch logic against a
disposable fixture user): a stored MD5 hash submitted as the password
through that branch authenticated successfully; the real plaintext
password through that same (pre-fix) branch was rejected, since the
branch never hashed it.

### F17-B — path traversal / arbitrary file inclusion via `$_GET['service']`

Original code (pre-fix):

```php
if(!isset($_GET['service'])){
    $service_name = "CallsReportService";
}else{
    $service_name = $_GET['service'] . "Service";
}
$filename = dirname(__FILE__) . "/actions/" . $service_name . ".php";
if (file_exists($filename)) {
    require_once($filename);
} else {
    error("Servico nao encontrado; $service_name") ;
}
```

`$_GET['service']` is concatenated directly into a filesystem path with
no traversal or allowlist check — `file_exists()` only guards against a
missing file, not against an unexpected path.

**Confirmed via safe, disposable reproduction**: a harmless, inert
marker file (`task0026fmarkerService` class, returning a static array,
no filesystem/network access) was placed at `/tmp/task0026f-markerService.php`
inside the `app` container. A request with
`service=../../../../../../../../tmp/task0026f-marker` (8 `../`
segments, matching the actual depth of `.../api/actions` from
filesystem root) produced HTTP 500 with an **empty response body**
(no path/stack-trace disclosure to the client), and the server error
log showed:

```
PHP Fatal error:  Uncaught Error: Class "../../../../../../../../tmp/task0026f-markerService" not found in .../index.php:122
```

This proves `require_once()` **succeeded** against the traversal path —
a `file_exists()` failure would instead have produced the normal
`{"status":"error","cause":"Servico nao encontrado; ..."}` JSON body.
The only reason execution didn't fully succeed is that PHP class names
cannot contain `/` characters, so the subsequent `new $service_name`
failed — the file-inclusion boundary itself was already broken. The
marker file was deleted from both the container and host immediately
after this proof.

### Additional discoveries folded into this same fix (not scope creep — same code block being rewritten)

1. **Exhaustive auth-result check.** The original `switch
   ($result->getCode())` only handled
   `FAILURE_IDENTITY_NOT_FOUND`/`FAILURE_CREDENTIAL_INVALID` with no
   `default` case — any other `Zend_Auth_Result` failure code (notably
   `FAILURE_IDENTITY_AMBIGUOUS`, a real possible outcome since
   `users.name VARCHAR(45)` has **no UNIQUE constraint**, only `id` is
   the primary key) would silently fall through as if authentication
   had succeeded. Replaced with an exhaustive
   `if ($result->getCode() !== Zend_Auth_Result::SUCCESS)` check.
2. **Credential echoed in error response.** The auth-failure message
   was `"User or password invalid: {$user}:{$passwd}"`, echoing the
   submitted (post-normalization) password back to the client —
   violates Phase 7's "never expose password representations". Now
   `"User or password invalid"`, no credential included.
3. **Unbounded `explode()`.** `explode(':', base64_decode(...))` had no
   limit, so a password containing `:` was silently mis-parsed (only
   the text before the first `:` survived). Now
   `explode(':', $decoded, 2)`.
4. **Dormant `Signup` bypass removed.** No `SignupService.php` file
   exists anywhere in `actions/` (confirmed via directory listing) —
   `service=Signup` was already a non-functional, dead bypass path
   (any unauthenticated `Signup` request already always failed with
   `"Servico nao encontrado"`). The new service registry excludes
   `Signup` entirely, making authentication unconditional for every
   request. This changes zero client-observable behavior for that
   request shape (it already always failed) while removing the
   structural bypass. **Documented decision (Phase 6)**: if a real
   public self-signup flow is ever needed, it should be added as an
   explicit, reviewed, intentional entry in the registry with its own
   dedicated task — not resurrected as an auth-bypass side effect.

## 2. Service inventory and dispatch policy

`snep/modules/default/api/actions/` contains exactly 6 real service
classes (verified via `grep -n "^class "`) plus the shared
`SnepService` interface:

| Request `service=` value | Class              | File                        | Auth policy (post-fix) |
|---------------------------|---------------------|------------------------------|--------------------------|
| *(absent)*                 | `CallsReportService` | `CallsReportService.php`     | Authenticated |
| `CallsReport`               | `CallsReportService` | `CallsReportService.php`     | Authenticated |
| `Contacts`                  | `ContactsService`    | `ContactsService.php`        | Authenticated |
| `CSV_ExportData`            | `CSV_ExportDataService` | `CSV_ExportDataService.php` | Authenticated |
| `CSV_GetParams`             | `CSV_GetParamsService`  | `CSV_GetParamsService.php`  | Authenticated |
| `RankingReport`             | `RankingReportService` | `RankingReportService.php`  | Authenticated |
| `ServicesReport`            | `ServicesReportService` | `ServicesReportService.php` | Authenticated |
| any other value             | *(none)*              | *(none)*                     | Rejected — `"Servico nao encontrado"` (fails closed regardless of auth) |

There is no per-service authorization tier beyond "does this request
carry valid credentials for some row in `users`" — see the
architecture section above. `Signup` is deliberately not in the
registry (see discovery #4).

`Snep_Services::getPathService()` (`snep/lib/Snep/Services.php`) builds
a URL string pointing at this same API but has **zero call sites**
anywhere in the codebase (confirmed via
`grep -rln "getPathService\|new Snep_Services"`) — dead code, documented
only, not touched.

## 3. Password representation and the MD5 compatibility boundary (Phase 11)

`users.password VARCHAR(45) NOT NULL` (`snep/install/database/schema.sql`)
stores an MD5 hash (32 hex chars). `AuthController::loginAction()` (the
main app's own login flow) already uses
`$authAdapter->setCredential(md5($password))` — this is the project's
existing, established convention.

**This task extends that exact convention to the API, it does not
invent a new one and does not modernize it.** After this fix, both
Basic-auth branches produce a `(username, plaintext-password)` pair
*before* any hashing; exactly one call site afterward computes
`md5($plainPassword)` and hands it to
`Zend_Auth_Adapter_DbTable::setCredential()`.

- **Current compatibility**: plaintext credential → `md5()` → compare
  against the stored MD5 hash. Matches `AuthController`.
- **Future task (explicitly deferred, not started here)**: migrate
  `users.password` and all comparison call sites (both `AuthController`
  and this API) to `password_hash()`/`password_verify()`. This is a
  data-migration-shaped change (rehashing on next successful login, or
  a one-time batch migration) affecting the main app too, and must not
  be done piecemeal in one call site.

## 4. Fix implemented — `snep/modules/default/api/index.php`

- **Unified credential parsing** (Phase 3): a single
  `resolveApiCredentials()` function extracts `(username,
  plaintext-password)` from whichever server variable this deployment
  populates (`HTTP_AUTHORIZATION` first, then `PHP_AUTH_USER`/`PHP_AUTH_PW`,
  preserving the original branch precedence), with `explode(..., 2)` to
  handle passwords containing `:`. It never applies `md5()` — that
  happens exactly once, afterward, at the single call site that builds
  the `Zend_Auth_Adapter_DbTable` credential.
- **Unconditional authentication** (Phase 6): the `Signup`-bypass
  branch is gone; every request without a rejected/absent credential
  pair returns 401 with `WWW-Authenticate: Basic realm="SNEP Services"`
  (preserved exactly).
- **Exhaustive auth-result check**: `$result->getCode() !==
  Zend_Auth_Result::SUCCESS` (see discovery #1).
- **Controlled error response** (Phase 7): auth failure now reports
  `"User or password invalid"` with no credential included; the
  unknown-service error reports `"Servico nao encontrado"` with no
  filesystem path.
- **Finite service registry** (Phase 5): a hardcoded PHP associative
  array maps the 6 known `service=` values to their exact, trusted
  filenames. `$_GET['service']` is only ever used as an
  `array_key_exists()` lookup key — never concatenated into a path,
  even after validation. An unknown or non-string (e.g. `service[]=...`)
  value fails closed with the same generic error, before `require_once`
  is ever reached.
- **Preserved exactly**: default-to-`CallsReport` when no `service`
  param is given; `CallsReport`'s JSON slash-unescaping
  (`str_replace('\\/', '/', json_encode($resultado))`); the 401/
  `WWW-Authenticate` response shape for missing credentials; HTTP 200
  (not 401) on a *wrong* credential (`error()` never sets a status code
  before `die()` — a pre-existing, minor HTTP-semantics quirk,
  intentionally not "fixed" per Phase 7's "preserve existing HTTP
  semantics where reasonable" and CLAUDE.md's no-opportunistic-fixes
  principle); compatibility with `call-smoke-test.sh`/
  `trunk-smoke-test.sh`'s existing `curl -u` callers.
- **Net behavior change (intended, not incidental)**: plaintext
  credentials submitted via a raw `Authorization` header now
  authenticate correctly (previously that branch could never
  authenticate a real plaintext credential at all, since it compared
  plaintext directly against the stored hash) — this is the correct
  and expected result of unifying the two branches' normalization.

## 5. Newly discovered, unremediated technical debt (NOT fixed in this task)

While inventorying the 6 service files for the reachability checks in
Phase 8's smoke suite, this task discovered that **most of the
standalone API's individual service files build SQL by direct string
concatenation of `$_GET` values**, with no parameterization
(`Zend_Db`'s `?`/`quoteInto()`, the pattern TASK-0026C established for
the main app's controllers) — e.g.:

```php
// CSV_ExportDataService.php
$select = "SELECT ". $fields . " FROM " . $table . " ORDER BY " . $order;
$stmt = $db->query($select);
```

```php
// ContactsService.php
$select = "select ... where contacts_phone.phone like '%{$phone}'";
```

`CallsReportService.php`, `RankingReportService.php`, and
`ServicesReportService.php` show the same `$_GET`-into-query-string
pattern for date ranges and filter clauses. This is a **SQL-injection
class of finding, distinct from and unrelated to F17-A/F17-B**, sitting
in a part of the codebase TASK-0026C's own SQL-hardening pass never
covered (that task scoped to the main MVC controllers only). Any
authenticated API caller (there is no per-service authorization tier —
see the architecture section) can potentially reach these sinks.

Per CLAUDE.md's bug/technical-debt policy (do not fix opportunistically,
document and propose a dedicated future task): **this is not fixed
here.** It is flagged as a candidate for a dedicated follow-up task,
tentatively "Standalone API SQL Boundary Hardening" — mirroring
TASK-0026C's own scope and approach, applied to
`snep/modules/default/api/actions/*.php` instead of the main
controllers. Given the concatenation pattern is broad and reaches a raw
`$db->query()` call with attacker-controlled table/column/clause
fragments in `CSV_ExportDataService.php` specifically, this should be
treated as a security priority for that future task, not routine
cleanup.

Also discovered, and separately unrelated to F17: **both
`ContactsService::execute()` and `CSV_ExportDataService::execute()`
throw an uncaught PHP Fatal Error under PHP 8.4 when called with none
of their expected `$_GET` parameters** —
`ContactsService.php:70` (`$db->query(null)` →
`ValueError: PDO::prepare(): Argument #1 ($query) must not be empty`)
and `CSV_ExportDataService.php:46` (`$this->view->translate(...)` on a
`$view` property that is never initialized anywhere in the class →
`Error: Call to a member function translate() on null`). Neither is
related to authentication or dispatch; both are pre-existing PHP 8.4
compatibility gaps in the service bodies themselves, out of scope for
this task, and not fixed here. `scripts/api-security-smoke-test.sh`
calls these two services with the minimal legitimate parameters they
actually require (`phone=0000000000` for Contacts;
`table=users&fields=id&order=id` for CSV_ExportData — harmless,
non-sensitive literals, not an injection attempt) specifically to avoid
tripping this unrelated, pre-existing crash while still proving the
F17-B dispatch fix works correctly for every registered service.

## 6. Post-remediation execution audit (Phase 9)

Searched `snep/modules/default/api/index.php` for every remaining
`require`/`include`/`file_exists`/`$_GET`/`$_REQUEST`/
`HTTP_AUTHORIZATION`/`PHP_AUTH` occurrence:

- The only `require_once` fed by request-influenced data is
  `require_once(dirname(__FILE__) . "/actions/" . $serviceRegistry[$requestedService]);`
  — the interpolated value is always one of 6 hardcoded literal
  strings from the trusted array; `$requestedService` itself is used
  only as an array key for a membership/lookup check, never
  concatenated into the path.
- `$_GET['service']` appears only as an `array_key_exists()` lookup key
  and in the two behavior-preserving equality checks
  (`isset($_GET['service']) && $_GET['service'] == "CallsReport"`).
- `file_exists()` remains only for the fixed, non-request-derived
  bootstrap config path (`../../../includes/setup.conf`).
- No other file under `snep/modules/default/api/` references `$_GET`
  for dispatch or contains a dynamic `require`/`include`.

No unexplained request-value → path-concatenation → `require`/`include`
path remains.

## 7. Files changed

- `snep/modules/default/api/index.php` — F17-A/F17-B fix (Phases 3–7),
  as described above.
- `scripts/api-security-smoke-test.sh` (new) — Phase 8 focused suite.
- `Makefile` — new `api-security-smoke` target.
- `scripts/regression.sh` — `api-security` suite wired in after
  `pjsip-config-security`, before `authorization-coverage` (Phase 12's
  suggested order).

## 8. Focused security smoke — `scripts/api-security-smoke-test.sh`

22 checks, `make api-security-smoke` → PASS. Covers (Phase 8's ≥15
requirement, across all three required categories):

**Authentication (F17-A):**
1. Valid plaintext via `PHP_AUTH_USER`/`PHP_AUTH_PW` still succeeds
   (existing real-caller path, e.g. `call-smoke-test.sh`).
2. Stored hash as password via `PHP_AUTH_USER`/`PHP_AUTH_PW` still
   rejected (pre-existing correct behavior, regression guard).
3. Valid plaintext via a raw `Authorization` header now succeeds (the
   net behavior change from unification).
4. **Core F17-A proof**: stored hash as password via a raw
   `Authorization` header is now rejected (pre-fix, this authenticated
   successfully).
5. A password containing `:` survives intact (`explode(...,2)`).
6. An ordinary wrong password is rejected and never echoed back.
7. No credentials at all → 401 + `WWW-Authenticate: Basic`.
8. `service=Signup` no longer bypasses authentication.

**Service resolution (F17-B):**
9. All 6 registered services remain reachable and functional.
10. No `service` param defaults to `CallsReport`.
11. **Core F17-B proof**: an 8-segment traversal-shaped `service` value
    fails closed with the generic error, no new Fatal Error, no
    path/stack-trace disclosure.
12. An absolute-path-shaped value also fails closed (proves the
    registry allowlist is doing the work, not a naive dot-filter).
13. A plausible-but-unregistered name fails closed.
14. An array-shaped `service[]=...` parameter fails closed without a
    crash.
15. `CallsReport`'s slash-unescaping behavior is preserved.
16. An unauthenticated dispatch attempt against a real, registered
    service name is still denied (401).

Uses a dedicated, persistent `task0026f-restricted` fixture user
(password reset to a known baseline every run), matching the exact
convention already established by `task0026a/c/d/e-restricted` in this
project's other focused smoke suites. No real admin credential is ever
used to prove the exploit; the traversal proof uses a disposable,
inert marker file created and destroyed entirely within this task's own
manual reproduction (not part of the automated suite, since a
filesystem-planted fixture outside the repo isn't appropriate for a
suite that must run unattended in CI/dev).

## 9. Validation

- `php -l` on the touched file: no syntax errors.
- `make api-security-smoke`: PASS (22/22).
- `make lint`: PASS (5/5).
- `make regression`: PASS (17/17 suites), run twice consecutively since
  this task touched application code — both runs clean, no flakiness.
- Manual verification against all 9 key scenarios (valid/invalid
  credentials on both auth branches, traversal, unknown service,
  Signup, no-credentials, default service) via direct `curl` against
  the running dev stack, cross-checked against the Apache error log for
  new Fatal Errors — none introduced.

## 10. Health and cleanup (Phase 14)

- `app`, `db`, `asterisk`, `provider` containers: all healthy.
- Asterisk 22.10.1, `res_pjsip.so` loaded and running, 3 PJSIP
  transports present (tcp/udp/wss), ODBC DSN `snep` with 1/1 active
  connection.
- 0 active channels, 0 active calls at the end of validation.
- The single Fatal Error present in the log at the end of validation is
  the pre-existing, already-documented TASK-0026D `CnlController`/
  `Zend_File_Transfer_Adapter_Http::receive()` PHP 8.4 incompatibility
  (triggered by `shell-security-smoke-test.sh`'s own CNL-upload check,
  part of the regression suite) — unrelated to this task, not newly
  introduced.
- All ad hoc reproduction artifacts from this task's own manual Phase 2
  work (the `task0026f-probe`/`task0026f-verify` disposable DB users,
  the `whoami-debug.php` diagnostic script, the `f17a-repro.php` script,
  and the `task0026f-markerService.php` traversal marker) were deleted
  from both the container and host — confirmed via direct `ls`/`find`
  checks, zero residue.
- The `task0026f-restricted` fixture user (id=121) remains in the dev
  database — this is the suite's own intentional, persistent fixture
  (matching `task0026a/c/d/e-restricted`'s established pattern), not
  leftover ad hoc residue.
- `git diff --check`: clean (no whitespace errors).
- `git diff --stat` / `git status --short`: changes scoped exactly to
  `Makefile`, `scripts/regression.sh`,
  `snep/modules/default/api/index.php`, and the new
  `scripts/api-security-smoke-test.sh` — no scope creep.

## Deferred — not in scope here

- TASK-0026G: session/cookie/CSRF hardening for the main application.
- Password-hashing modernization (`password_hash()`/`password_verify()`)
  for both `AuthController` and this API.
- Login rate limiting; default-credential removal.
- Main API redesign / REST modernization / OAuth.
- Per-service authorization (RBAC) inside the standalone API.
- **Standalone API SQL boundary hardening** (newly discovered in this
  task, see section 5 above) — the concatenated-SQL pattern across
  `ContactsService.php`, `CSV_ExportDataService.php`,
  `CallsReportService.php`, `RankingReportService.php`, and
  `ServicesReportService.php`.
- The two pre-existing PHP 8.4 crash-on-missing-parameters bugs in
  `ContactsService.php` and `CSV_ExportDataService.php` (see section 5).
- `Snep_Services::getPathService()` dead code removal.
