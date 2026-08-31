# TASK-0026I — Information disclosure and path traversal closure (F25, F26, F28)

## Status

Implementation complete. Focused smoke suite (21/21), `make lint` (5/5),
and two consecutive `make regression` runs (21/21 suites each) all PASS
(see §5-§7). Pending commit checkpoint authorization.

## Scope

Re-traces and remediates findings **F25**, **F26**, and **F28** from
`docs/tasks/0026-pre-pilot-security-release-audit.md` against the CURRENT
code, after TASK-0026A-H/F1/0027/0027A already landed. This closes the
remaining catalogued findings from that audit. Explicitly out of scope
per this task's own instructions: Product Readiness work, global
error-page redesign, dead-code removal beyond what §4 documents, menu/UI
restructuring, translations, chan_sip/iax2 removal, logging redesign,
standalone-API redesign, and unrelated file-serving behavior.

## 1. F25/F26/F28 reconstruction (Phase 1)

| Finding | Entry point | Current behavior | Exposure | Status |
|---|---|---|---|---|
| F25 | Any uncaught exception app-wide -> `ErrorController::errorAction()` -> `error/error.phtml:11` | `<?php echo $this->exception->getMessage(); ?>` ran whenever `$this->code != 404`, **not** gated by `APPLICATION_ENV` (unlike the fuller trace/params block a few lines below, which correctly was) | Raw exception text (including raw `SQLSTATE[...]` DB error text, per the audit's own TASK-0024 diagnostic example) shown to any user who triggers a 500, in every environment | confirmed, unchanged since the audit -> remediated |
| F26 | (a) every HTTP response; (b) `api/index.php?service=CallsReport\|ServicesReport` | (a) no `expose_php=Off` -> `X-Powered-By: PHP/8.4.25` on every response; (b) `CallsReportService`/`ServicesReportService` returned the fully-built SQL text (`select`/`selectcont`/`selectcount`) in their JSON payload on every call -- the sibling instance TASK-0026F1 Sec.5 explicitly deferred by name ("candidate for a future response-hygiene pass") | (a) version fingerprinting; (b) internal query/schema/table-name disclosure to any authenticated API caller | confirmed, unchanged since the audit / since TASK-0026F1 -> remediated |
| F28 | `POST /index.php/default/docs` -> `DocsController::indexAction()` | `file_get_contents('/var/www/html/snep/docs/'. strtoupper($key) .'.md')` where `$key` is a raw **POST parameter NAME** -- only `strtoupper()` applied, no `/`/`..` stripping, no `realpath()`/containment check | Contained to files ending in the literal `.md` suffix, but any `.md` file elsewhere on the container filesystem reachable via `../` in a parameter name was disclosed, rendered through Parsedown into the authenticated UI | confirmed, unchanged since the audit -> remediated |

Authorization context for F28 (out of scope to change here): `default_docs`
is in `Snep_PermissionPlugin::$alwaysAllow`, added and justified by
TASK-0026A as "read-only local documentation viewer, no PBX/account
data" -- reachable by any authenticated user by design, independent of
this task. This task only closes the traversal inside that action.

## 2. F25 — exception-message disclosure (Phase 2)

`snep/modules/default/views/scripts/error/error.phtml`: the "Server
Message" line is now gated by the same `'development' == APPLICATION_ENV`
check the class-name/stack-trace/request-params block below it already
used, instead of only `$this->code != 404`.

`snep/modules/default/controllers/ErrorController.php::errorAction()`:
added one `error_log()` call (this codebase's own established
server-side-logging convention -- see `Snep_PjsipConf`,
`Snep_Asterisk_Operations`, `Snep_InterfaceConf`) so the full exception
class + message is still recorded for operational diagnosis via
`make logs` even though the client no longer sees it, satisfying this
task's "internal detailed error -> server log -> controlled user-facing
error" requirement.

Before/after (production `APPLICATION_ENV`, the default):

| | Before | After |
|---|---|---|
| Client response | `Server Message: SQLSTATE[23000]: Integrity constraint violation: ...` (or any exception text) | Generic translated message only (`"Some internal error occured..."`) |
| Server log | nothing beyond PHP's own warning-level noise | `ErrorController: uncaught <ExceptionClass>: <message>` |

Live-verified (§5) against a real, reproducible 500 already documented in
this codebase (TASK-0026A's own no-Khomp `errors-tdm` 500) rather than a
synthetic fixture.

## 3. F26 — information disclosure (Phase 3)

**(a) `X-Powered-By` / `expose_php`**: `docker/php-mag.ini` now sets
`expose_php = Off`. Required an app image rebuild (`docker compose build
app && docker compose up -d app`) since `docker/php-mag.ini` is `COPY`'d
into the image at build time, not bind-mounted -- a plain container
restart does not pick up the change. Live-verified via `curl -I`: header
absent after rebuild.

**(b) raw SQL text in report-service JSON responses**: this is the exact
technical debt TASK-0026F1 Sec.5 named and deferred
("`CallsReportService.php`/`ServicesReportService.php`... raw
`select`/`selectcont`/`selectcount` SQL text echoed back in the JSON
response... candidate for a future response-hygiene pass"). Per this
task's Phase 3 instruction, it is resolved here as the same
information-disclosure class as F25/F26:

- `CallsReportService::execute()`: dropped `"select"`/`"selectcont"` from
  the returned array. The functional payload (`data`/`quantity`/`totals`)
  is unchanged; the underlying query behavior (already parameterized by
  TASK-0026F1) is untouched.
- `ServicesReportService::execute()`: dropped `"select"`/`"selectcount"`
  from the returned array. The functional payload (`totals`) is
  unchanged.

Before/after (live-verified via `curl` against the real API, admin
credentials, real date range):

| Service | Before (JSON keys) | After (JSON keys) |
|---|---|---|
| CallsReport | `status, data, quantity, totals, select, selectcont` | `status, data, quantity, totals` |
| ServicesReport (non-empty) | `status, totals, select, selectcount` | `status, totals` |

## 4. F28 — path traversal remediation (Phases 5-9)

`snep/modules/default/controllers/DocsController.php`:

- Added `private static $allowedDocs`, an explicit map of the 7 real
  button names (`changelog`, `install_guide`, `practical_guide`,
  `realtime_disable`, `register_error`, `repository_snep_guide`,
  `translation`) to their exact on-disk filenames under `snep/docs/`
  (Phase 7's preferred finite-resource-map approach -- the doc set is
  small and static, so an allowlist is simpler and stronger than parsing/
  sanitizing the traversal shape).
- `indexAction()` now looks up `self::$allowedDocs[$key]` first; any
  parameter name not in the map (including any traversal/encoded/
  absolute-path payload) is `continue`'d past with zero filesystem
  access -- the fix does not parse or transform the input at all, it
  simply never builds a path from anything not already known-good.
- Defense in depth (Phase 6/8): even for an allowlisted key, the
  candidate path is `realpath()`-resolved and verified to still start
  with `realpath(docsRoot) . DIRECTORY_SEPARATOR` before
  `file_get_contents()` is called. `realpath()` returning `false`
  (nonexistent target) is also rejected.

**Symlink behavior (Phase 8)**: explicitly tested by planting a symlink
at an *allowlisted* slot (`snep/docs/TRANSLATION.md` -> a test-owned
marker file one level above the docs root) and confirming the
`realpath()`-based containment check rejects the resolved target even
though the requested key itself was legitimate. This is the strongest
available proof: the containment check is what stops the escape, not the
allowlist alone.

**Encoded traversal (Phase 9)**: the current Zend/PHP request stack
url-decodes `application/x-www-form-urlencoded` parameter names once
before they reach the controller, same as any ordinary form field. Since
the fix is an exact-match lookup against a fixed set of literal strings
(not a string-transform-then-compare), no encoding, double-encoding, or
mixed-slash variant of a traversal payload can ever equal one of the 7
allowed keys -- verified with a `%2e%2e%2f`-encoded payload in addition to
a literal `../` one.

Before/after:

| | Before | After |
|---|---|---|
| `changelog=changelog` | renders `CHANGELOG.md` | renders `CHANGELOG.md` (unchanged) |
| `../../../../etc/passwd=x` | blocked only by the unconditional `.md` suffix (would still traverse to any `*.md` file) | rejected before any path is built (key not in the allowlist) |
| `%2e%2e%2f...=x` | same partial containment as above | rejected identically |
| symlink at an allowlisted slot escaping the docs root | would have been followed (no containment check existed at all) | rejected by the `realpath()`-based containment check |

## 5. Focused security smoke — `scripts/disclosure-path-security-smoke-test.sh`

New suite, `make disclosure-path-security-smoke`, using
`scripts/lib/harness.sh`. 21/21 checks PASS. Covers:

**Disclosure (checks 1-11)**: `X-Powered-By` absence; legitimate
CallsReport/ServicesReport requests succeed with no raw SQL text or
`select`/`selectcont`/`selectcount` fields in the JSON; a real,
reproducible 500 (the pre-existing, documented no-Khomp `errors-tdm`
condition from TASK-0026A -- GET-only, no state mutated, not a new
fixture) does not show `Server Message`, absolute filesystem paths, or a
stack trace, while still rendering a controlled generic error page and
recording the full exception server-side via the new `error_log()` call;
confirms the reproduced condition is a handled `Exception` (caught by
Zend's error handler), not a new raw PHP Fatal Error.

**Path traversal (checks 12-19)**: two distinct legitimate allowlisted
docs render with their real content; `../` traversal, `%2e%2e%2f`-encoded
traversal, and an absolute-path parameter name are all rejected; a
test-owned inert marker file placed outside the docs root is not
disclosed via a non-allowlisted traversal key; a symlink planted at an
*allowlisted* slot is rejected by the containment check; the swapped
file is restored byte-for-byte afterward (verified via direct file diff,
not a fresh HTTP request -- see the in-script comment on
`realpath_cache_ttl=120` for why an immediate HTTP re-check of the same
path would have been flaky for reasons unrelated to the fix).

No real sensitive file (`/etc/passwd`, secrets, keys) is ever targeted:
traversal payloads either never reach the filesystem (rejected by the
allowlist lookup itself, before any path is built) or target only this
suite's own marker file, which is deleted in cleanup along with the
`TRANSLATION.md` backup tempfile and the admin cookie jar.

## 6. Regression integration (Phase 12)

Added `disclosure-path-security` to `scripts/regression.sh`, placed
right after `auth-hardening-security` and before `authorization-coverage`
(same reasoning every prior TASK-0026x security suite's placement comment
gives: an independent trust-boundary proof needing its own authenticated
session, same precondition the authorization suites need next). Added the
`disclosure-path-security-smoke` Makefile target and its name to
`.PHONY`.

## 7. Validation

- `php -l` on all 4 touched PHP files (inside the app container): no
  syntax errors.
- `make disclosure-path-security-smoke`: **PASS (21/21)**.
- `make lint`: **PASS (5/5)** — `php -l` across 271 project PHP files,
  `bash -n` across 23 shell scripts (was 22 -- includes the new suite),
  XML well-formedness, `git diff --check` (fixed one pre-existing-style
  space-before-tab whitespace issue introduced by matching the touched
  file's own legacy indentation on the first pass).
- `make regression`, run twice consecutively: **PASS (21/21 suites)**
  both times, no manual cleanup between runs, no fixture residue.

## 8. Health and cleanup

- app, db, asterisk, provider containers: all `Up (healthy)`.
- `res_pjsip.so`: `Running`, 1 module loaded.
- Baseline PJSIP transports intact: `tcp`, `udp`, `wss` on their expected
  bind addresses.
- AMI responsive (`manager show connected`: reachable, 0 stale
  connections).
- ODBC: `snep` DSN, 1/1 active connection.
- `0 active channels`, `0 active calls` — no unexpected active channels.
- PHP Fatal Error count: 2 new lines appeared in `mag-error.log` during
  the two `make regression` runs, both the pre-existing, already-
  documented `Zend_Validate_File_Upload` / `CnlController` fatal from
  `shell-security-smoke-test.sh`'s own F5-reachability check (TASK-0026D,
  unrelated to this task's F25/F26/F28 scope, not newly introduced by
  this task's changes). Zero fatals attributable to TASK-0026I.
- No traversal test marker remains (`snep/OUTSIDE-MARKER.md` removed by
  the suite's own required cleanup).
- `snep/docs/TRANSLATION.md` restored byte-for-byte after the symlink
  test (verified by the suite's own check 19, and independently by
  `git status --short` showing no diff on that file after the run).
- No smoke process left running; no lingering cookie-jar/temp files.
- `git diff --check`: clean.
- `git status --short`: only the intended files listed in §9 below.

## 9. Static post-remediation audit (Phase 11)

| Construct | Location | Classification |
|---|---|---|
| `error/error.phtml` "Server Message" line | `snep/modules/default/views/scripts/error/error.phtml:12` | **CONTROLLED_RESPONSE** — now gated by `APPLICATION_ENV`, matches the existing trace/params block's own gating |
| `ErrorController::errorAction()` new `error_log()` call | `snep/modules/default/controllers/ErrorController.php:72` | **SAFE_INTERNAL** — server-side log only, never reaches the client |
| `error/error.phtml` full trace/class/params block | lines 19-31 | **CONTROLLED_RESPONSE** — unchanged, already correctly gated (pre-existing, F35 positive finding) |
| `CallsReportService`/`ServicesReportService` `select`/`selectcont`/`selectcount` JSON fields | `snep/modules/default/api/actions/{CallsReportService,ServicesReportService}.php` | **CONTROLLED_RESPONSE** — removed from the response; internal `$select`/`$selectcont` variables remain (needed for the real, unrelated query execution, not disclosure) |
| `X-Powered-By` header | `docker/php-mag.ini` | **CONTROLLED_RESPONSE** — `expose_php=Off` |
| `DocsController::indexAction()` path build | `snep/modules/default/controllers/DocsController.php` | **VALIDATED_PATH** — fixed allowlist + `realpath()` containment |
| Nine per-controller `<controller>/error.phtml` view scripts (`dates-alias`, `contact-groups`, `calls-report`, `expression-alias`, `extensions`, `logs`, `simulator`, `trunks`, `queues`) | `snep/modules/default/views/scripts/*/error.phtml` | **DEAD/UNREACHABLE** — grepped every controller in this project for a `render('error')`/`renderScript('<ctrl>/error.phtml')`/`errorAction()` call that would resolve to these view templates by Zend's naming convention; found none. Every controller that has an error-display path renders the shared `error/sneperror.phtml` instead. No live route reaches these files. Not deleted here (unrelated to F25/F26/F28, and CLAUDE.md's own instruction is not to remove unrelated legacy code opportunistically) |
| Raw `$ex->getMessage()`/`$e->getMessage()` fed into `$this->view->error_message` (then rendered by the shared, already-reachable `error/sneperror.phtml`) | `DatesAliasController.php:99,138`; `ExpressionAliasController.php:112,174`; `SimulatorController.php:85`; `ExtensionsController.php:952,1013,1137` ("DB Delete Error: " prefix) | **DEFERRED** — a real, distinct information-disclosure pattern, but not part of F25's audited boundary (F25's finding is specifically the *global* uncaught-exception fallback at `error/error.phtml`, not these per-controller *caught*-exception paths through the separate, pre-existing `sneperror.phtml` mechanism) and not named anywhere in the original audit. Per this task's explicit scope boundary ("only close the audited disclosure surfaces plus exact sibling instances in the same boundary" / "do not perform a framework-wide exception redesign"), left untouched and flagged here as a candidate for a future, explicitly-scoped Product Readiness task |
| CSV/other file-serving controllers not named by F28 | out of this task's audited scope | **DEFERRED** — "change unrelated file-serving behavior" is explicitly out of scope per this task's own instructions |

There is no unexplained user-controlled path to arbitrary file access
remaining in F28's scope, and no audited raw SQL/exception/path
disclosure remains in F25/F26's scope.

## 10. Files changed

- `snep/modules/default/views/scripts/error/error.phtml`
- `snep/modules/default/controllers/ErrorController.php`
- `docker/php-mag.ini`
- `snep/modules/default/api/actions/CallsReportService.php`
- `snep/modules/default/api/actions/ServicesReportService.php`
- `snep/modules/default/controllers/DocsController.php`
- `scripts/disclosure-path-security-smoke-test.sh` (new)
- `scripts/regression.sh`
- `Makefile`

## 11. Remaining deferred debt (for Product Readiness, not TASK-0026J)

- The per-controller raw `$ex->getMessage()` -> `sneperror.phtml` sinks
  listed in §9 (not part of F25/F26's audited boundary).
- The nine dead `<controller>/error.phtml` view scripts (candidate for
  removal in a future, explicitly-scoped legacy-cleanup task; left as-is
  here per CLAUDE.md's "do not remove unrelated legacy code" rule).
- Full HTTP security header rollout (CSP, X-Frame-Options,
  X-Content-Type-Options, Referrer-Policy, HSTS) — F26's own audit text
  already explicitly deferred this beyond `expose_php`.

None of these are pilot-blocking on their own; none constitute a new
security class beyond what TASK-0026 already catalogued. Per this task's
own instructions, TASK-0026J is not opened.
