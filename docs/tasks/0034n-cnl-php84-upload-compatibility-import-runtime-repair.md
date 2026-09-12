# TASK-0034N — CNL PHP 8.4 Upload Compatibility & Import Runtime Repair

Lead: `senma-application-architect` (compatibility/runtime repair on the
CNL upload path). Reviewers: `senma-workflow-orchestrator` (routing/scope
discipline). Telephony and Docker/platform specialists were **not**
invoked -- this task touches neither Asterisk runtime/config nor
container/lifecycle/network topology; every proof below runs against the
existing `make dev` topology unchanged. `senma-product-designer` was not
invoked -- no UI/workflow change for any role (server-side upload path
only; the existing form/screen is untouched).

Continues TASK-0034M, which closed the CNL authorization boundary and
named the two PHP 8.4 `count()` TypeErrors on the CNL upload path as
`FOLLOW_UP_DEBT` item 2 / `TASK-0034N-CANDIDATE-2` (also listed as a
feature-scoped `PILOT_BLOCKER` in
`docs/tasks/0034-release-readiness-production-pilot-gate.md` §41).

## STARTING STATE

```
HEAD:   c1f038ef740bc0ae5469ca671021c0afcd38567f
branch: main
status: dirty -- one uncommitted, pre-existing working-tree change on
        snep/lib/Zend/Validate/File/Upload.php (the exact first
        TypeError fix this task needs; captured below and kept as part
        of this task's own diff, not discarded or rewritten)
```

The working-tree change already present at task start was inspected
(`git diff`) before any further edit: it is exactly the
`_messages = null` -> `_messages = array()` reset documented by
TASK-0034M as the temporary evidence patch that was supposed to have
been reverted. It was left in the working tree from a prior local
session; it was **not** committed. This task owns it now (it is the
correct, minimal fix for TypeError #1) and does not invent a second,
different Zend-side patch.

## OBJECTIVE

Restore legitimate CNL ZIP import under PHP 8.4 by fixing the two known
`count()` TypeErrors discovered during TASK-0034M, without weakening:

* authorization (TASK-0034M boundary stays unchanged);
* CSRF protection;
* upload validation;
* ZIP traversal protections;
* symlink safety;
* fixture isolation;
* existing regression coverage.

This is a targeted compatibility/runtime repair, not a CNL redesign.

## REPRODUCTION (live, before the full fix)

Against the running `make dev` topology (PHP 8.4.25, app/db/asterisk
healthy), with the working-tree Zend patch temporarily stashed so the
code matched the committed pre-TASK-0034N state:

1. Seeded the missing `core_cnl_country id=76` reference row (FK
   required by `core_cnl_prefix`; the same fixture-completeness gap
   TASK-0034M already documented).
2. Logged in as `admin` (superuser, `id_user==1`).
3. Uploaded a minimal legitimate type-M ZIP (`9990001\n` in `legit.txt`
   inside `legit.zip`) through the real HTTP flow with a valid
   session-bound CSRF token.

```
POST /index.php/default/cnl/index (country=76, type=M, multipart file
  upload, valid session-bound CSRF token, admin session)
  -> HTTP 500, empty body
```

Live stack trace in `/var/log/apache2/mag-error.log`:

```
PHP Fatal error: Uncaught TypeError: count(): Argument #1 ($value)
must be of type Countable|array, null given in
/var/www/html/snep/lib/Zend/Validate/File/Upload.php:226
Stack: Zend_Validate_File_Upload->isValid()
  <- Zend_File_Transfer_Adapter_Abstract->isValid()
  <- Zend_File_Transfer_Adapter_Http->receive()
  <- CnlController->updateAction_76()
  <- CnlController->indexAction()
```

Restored the working-tree Zend patch (`git stash pop`) and re-ran the
exact same upload:

```
POST (same fixture, same admin session, same CSRF)
  -> HTTP 500 again
```

Second live stack trace:

```
PHP Fatal error: Uncaught TypeError: count(): Argument #1 ($value)
must be of type Countable|array, true given in
/var/www/html/snep/modules/default/controllers/CnlController.php:173
Stack: CnlController->updateAction_76()
  <- CnlController->indexAction()
```

**Both TypeErrors occur sequentially on the same request path**: #1
fires first (inside `receive()`); #2 is reachable only after #1 is
bypassed/fixed. Confirmed empirically, not assumed from the TASK-0034M
report. Restored the seeded country row (and any leftover `/tmp`
artifacts from these two failed uploads) after capture.

## ROOT CAUSE

### TypeError #1 — `Zend_Validate_File_Upload::isValid()`

Vendored/framework code (`snep/lib/Zend/Validate/File/Upload.php`).
`isValid()` resets `$this->_messages = null` at the top of the method.
On a genuinely error-free upload (`$content['error']===0` and
`is_uploaded_file()` true), no code path ever reassigns it, so the
final `count($this->_messages) > 0` calls `count(null)`.

* Older PHP: `count(null)` returned `0` (with a deprecation warning
  under PHP 7.2+).
* PHP 8.0+: `count(null)` is a `TypeError`.
* Declared type on `Zend_Validate_Abstract`:
  `protected $_messages = array();` -- an empty array is the type-
  correct reset, and is what every other Zend validator already does
  via `_error()`'s own path and `Zend_Validate_Abstract::setMessage()`
  etc.

**Category A** (syntax/API removed by PHP). Only call site of
`Zend_File_Transfer_Adapter_Http` in this repository is `CnlController`
(confirmed by `grep -rln` across `snep/modules` and `snep/lib/Snep` in
TASK-0034M; reconfirmed here).

### TypeError #2 — `CnlController::updateAction_76()`

SENMA-owned (inherited SNEP) application code.
`if (count($prefixos > 0))` evaluates `$prefixos > 0` first
(array-vs-int comparison, PHP coerces to `bool`), so `count()` receives
a `bool`, not the array -- a second, distinct `TypeError` under
PHP 8.0+. The evident intent was always `count($prefixos) > 0`
(non-empty parsed-line array). Confirmed: the `else` branch of that
`if` is the existing "No data found in the file" error path, which only
makes sense if the predicate is "the array has at least one entry".

**Category A**. Narrow search for the same parenthesis-misplaced
`count($x > 0)` shape across `snep/modules` found **zero** other
occurrences. The only other `count(...)` sites in the same upload
execution path (`Zend_File_Transfer_Adapter_{Abstract,Http}`) all
operate on already-initialized arrays; no further TypeError in the
path.

## CONTRACT (supported after this task)

### Authorization (unchanged from TASK-0034M)

* unauthenticated: denied (login page rendered in place);
* zero permission: denied (`Location: permission/error`);
* read-only: GET allowed, POST denied (`Location: permission/error`);
* write-authorized: POST allowed;
* superuser: POST allowed.

### CSRF (unchanged)

* missing/invalid token: HTTP 403;
* valid token: accepted.

### ZIP safety (unchanged)

* zip-slip/`../` traversal: whole archive rejected, no escape;
* absolute-path entries: whole archive rejected, no escape;
* symlink entries: not materialized as a real filesystem symlink;
* oversized upload: rejected by PHP `upload_max_filesize`, no DB
  mutation, no path/SQL/stack disclosure.

### Legitimate import (NEW -- previously unreachable)

A valid type-F CNL ZIP must:

* return HTTP 302 (success redirect to `/index.php/cnl`);
* create the expected state/city/prefix rows;
* create no unexpected rows;
* leave runtime/application state consistent;
* be cleanly restorable by the test fixture.

The focused CNL suite must FAIL if the legitimate import returns
HTTP 500 again. The TASK-0034M-era `UPLOAD_SUBSYSTEM_BROKEN` tolerance
is removed.

## IMPLEMENTATION

### Decision: Zend-side fix for TypeError #1 is unavoidable and safe

A SENMA-side workaround (e.g. subclassing
`Zend_Validate_File_Upload`, monkey-patching `receive()`, or replacing
the whole Zend File Transfer stack) would be larger, more invasive, and
would still leave the vendored defect in place for any future call site.
The smallest coherent fix is the one-line reset change already present
in the working tree at task start, which restores the declared type of
`$_messages` and matches what every other Zend validator already does.
Documented here as an intentional, narrowly-scoped vendored-code edit
(same class of change already established for other PHP 8.4 Zend
compatibility sites in this repository, e.g. `Zend/Cache/Core.php`,
`Zend/Registry.php`).

### Changes

1. `snep/lib/Zend/Validate/File/Upload.php`
   * `$this->_messages = null;` -> `$this->_messages = array();`
   * with an inline PHP 8.0+ compatibility comment explaining why.
2. `snep/modules/default/controllers/CnlController.php`
   * `if (count($prefixos > 0))` -> `if (count($prefixos) > 0)`
   * with an inline PHP 8.0+ compatibility comment explaining the
     original parenthesis bug and the intended semantics.
3. `scripts/cnl-upload-authorization-security-smoke-test.sh`
   * removed the `UPLOAD_SUBSYSTEM_BROKEN` tolerance flag and every
     success-path branch that accepted HTTP 500 as "still expected";
   * the compatibility probe now REQUIRES HTTP 302 + one created row
     and fails on HTTP 500;
   * write-authorized / superuser / valid-CSRF / type-F import checks
     now require the full success shape;
   * zip-slip / absolute-path checks still require no escape, but now
     also require HTTP 302 (the controller's own whole-archive reject
     path, reachable only after the validator no longer crashes);
   * symlink check now also asserts the legitimately-named sibling
     entry WAS imported (proving the archive was not whole-archive-
     rejected -- the symlink entry's name alone never tripped the
     `..`/leading-`/` guard; safety remains libzip's inert-file
     extraction behavior, unchanged).
4. `docs/tasks/0034-release-readiness-production-pilot-gate.md` §41
   * the CNL-import PHP 8.4 `PILOT_BLOCKER` row is marked Closed by
     this task (historical finding preserved, classification updated
     in place -- same lifecycle as TASK-0034M's own Closed entries).
5. This document.

### Cleanup classification

`CnlController`'s missing `unlink()` of its own uploaded/extracted
`/tmp` artifacts (TASK-0034M REMAINING DEBT item 3) was inspected live:
after a successful type-F import, `/tmp/legit-f.zip` and
`/tmp/legit-f.txt` remain as `www-data`-owned regular files. Not a
security defect (not web-served, not attacker-namable beyond the
upload's own filename). The focused suite already cleans its OWN
fixtures after every run. **Classified `FOLLOW_UP_DEBT`** -- not
required for correctness, security, deterministic testing, or runtime
integrity of this repair. Not fixed here.

## SECURITY IMPACT

* Authorization boundary: **unchanged** (TASK-0034M's
  `default_cnl_write` / `$writeOnPostIndex` mapping untouched).
* CSRF: **unchanged**.
* Upload validation / ZIP traversal / symlink / oversized: **unchanged
  and now actually reachable** end-to-end (previously the validator
  crashed before any of those guards ran for a successfully-
  transported file).
* No new attack surface: the two changes only restore the pre-PHP-8
  success-path semantics of already-existing predicates.

## LIVE POST-FIX PROOF

With both fixes applied, against the same admin session / same CSRF /
same fixtures:

```
type-M: HTTP 302, core_cnl_prefix id='9990001' country=76 -> 1 row
        (NULL/NULL/NULL city/lat/long/hemispher, matching type-M shape)
type-F: HTTP 302,
        core_cnl_state  id='ZZ' country=76 -> 1 row
        core_cnl_city   name LIKE 'TASK0034N%' -> 1 row
        core_cnl_prefix id='9990006' country=76 -> 1 row
```

Restored immediately after capture (all three tables + the seeded
country row + leftover `/tmp` artifacts). Confirmed zero residual rows.

## VALIDATION

### Focused

| SUITE | RESULT |
|---|---|
| `cnl-upload-authorization-security-smoke-test.sh` | **PASS 27/27** (2 consecutive runs before gates, plus 1 more after env recovery; identical) |
| `authorization-smoke-test.sh` | **PASS 51/51** (authorization boundary unchanged; reconfirmed) |

### Canonical gates

| GATE | RESULT |
|---|---|
| `make lint` | **PASS 5/5** |
| `make regression` run 1 | **FAIL** — `pjsip-lifecycle-smoke` BLOCKED (`res_pjsip.so`/`chan_pjsip.so` not both Running within the suite's 8s bound). Same already-catalogued transient PJSIP module-status race class as TASK-0034M / release-readiness §44. All other suites including `cnl-upload-authorization-security` PASS. Investigated; **unrelated to this task**. |
| `make regression` run 2 | **FAIL** — cascade of BLOCKED/FAIL after leftover TASK-0026LQ queue fixtures (`task0026lqcanary2` / `task0026lq-mal's` duplicate rows) crashed `Bootstrap::_initQueues()` with `Queue already registered` on every HTTP request (app unhealthy, HTTP 500). Root cause confirmed via `/var/log/apache2/mag-error.log`. **Unrelated to this task** (fixture leak from `sql-security`, not CNL). Cleaned the leaked fixture rows (only those) to restore a valid environment; consecutive-PASS count restarted. |
| `make regression` run 3 | **PASS 45/45** (counted consecutive #1) |
| `make regression` run 4 | **PASS 45/45** (counted consecutive #2; no manual repair/reset between 3 and 4) |
| `git diff --check` | **PASS** |
| `git status --short` | see COMMIT CHECKPOINT below |

Runs 3 and 4 together satisfy the "two consecutive clean regression runs" gate.

## REMAINING DEBT

1. ITC vendor-registration write surface (`IndexController`/
   `RegisterController`) -- still open from TASK-0034M
   (`TASK-0034N-CANDIDATE-1` / `PILOT_CONSTRAINT`). Unchanged by this
   task.
2. `CnlController`'s missing upload/extraction `unlink()` cleanup --
   `FOLLOW_UP_DEBT` (housekeeping, not security). Unchanged.
3. `CnlController`'s zip-slip guard has no explicit symlink-entry
   rejection (currently safe empirically via this PHP/`libzip`
   build's inert-file extraction, not a documented contract) --
   `FOLLOW_UP_DEBT`, low severity. Unchanged.
4. `Snep_Parameters_Manager::change()` -- confirmed dead/unreachable
   by TASK-0034L; still a candidate for future dead-code removal.
5. Dev-fixture-completeness gap: `core_cnl_country id=76` is absent
   from this repository's baseline DB seed, so any CNL import of ANY
   shape fails closed with a caught `Zend_Db_Statement_Exception`
   until that row exists. The focused suite seeds and removes it
   per-run. Not a security issue; fixture-completeness debt only.

## RECOMMENDATION

`APPROVE` -- both PHP 8.4 TypeErrors are closed with the smallest
behavior-preserving corrections; the authorization/CSRF/ZIP-safety
matrix from TASK-0034M is reconfirmed intact; the focused suite now
fails closed if the legitimate import returns HTTP 500 again; the
feature-scoped `PILOT_BLOCKER` in the release-readiness gate is
Closed.
