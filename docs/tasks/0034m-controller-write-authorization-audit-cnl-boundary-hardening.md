# TASK-0034M — Controller Write-Authorization Audit & CNL Boundary Hardening

Lead: `senma-application-architect`. Reviewers: `senma-workflow-orchestrator`
(routing/scope discipline), `senma-docker-platform-engineer` (consulted; no
container/lifecycle/network change was required -- the fix is entirely
inside the already-running `app` container's PHP/config, and every proof
below runs against the existing `make dev` topology unchanged).
`senma-telephony-architect` was invoked because two of the same-shape
defects found here (`ErrorsKhompController`, `ErrorsTdmController`) mutate
Asterisk runtime (an AMI command that clears Khomp links-errors counters)
and one (`ConferenceRoomsController`) mutates Asterisk-consumed config
files directly (`snep-conferences.conf`/`snep-authconferences.conf`) --
in all three cases the architect's review confirmed no runtime contract,
reload semantics, or PJSIP/`chan_sip` boundary is touched; only the
caller's authorization boundary is tightened (see TELEPHONY CONSULTATION
below). `senma-product-designer` was not invoked -- no UI/workflow change
for any role (server-side authorization is authoritative; every existing
form/screen is untouched).

Continues TASK-0034L, which closed the identical defect shape for
`ParametersController` and named `CnlController` as the one concrete,
verified carry-forward (`FOLLOW_UP_DEBT` item 1 of that task).

## STARTING STATE

```
HEAD:   ce0b13b fix(security): require write permission for ParametersController POST
branch: main
status: clean
```

## OBJECTIVE

Audit every remaining `indexAction()+POST` controller for the same
read-implies-write authorization shape TASK-0034L closed for
`ParametersController`; close `CnlController`'s concretely-identified
instance and its upload-security surface; close any other controller
found to share the exact same mechanism; classify and defer the rest.

## PHASE 1 — MIXED-CONTROLLER INVENTORY (precise, not pattern-matched)

`grep`-based pattern matching (as TASK-0034L's own inventory used) is not
precise enough to say a controller's `indexAction()` itself processes
POST -- a POST reference anywhere in the file can belong to a completely
different action in the same class. This task instead computed, per
controller, the exact line range of `indexAction()`'s own function body
(from its `function indexAction` line to the next `function` declaration
in the file) and searched for `getPost()`/`isPost()` strictly inside that
range.

Across all 49 controllers under `snep/modules/{default,billing}/
controllers/` (all with a dispatchable `indexAction()`; 5 further files
have no `indexAction()` at all -- `AuthController`, `ErrorController`,
`RouteFormController`, and the abstract `Snep/Controller.php`/
`Rule/Plugin/TimeLimit/OldController.php`, which are not real dispatched
controllers), exactly **17** have POST handling inside `indexAction()`
itself:

| CONTROLLER | ACTION | GET EFFECT | POST EFFECT | PERSISTENT MUTATION? | RUNTIME MUTATION? | CURRENT PERMISSION | WRITE PERMISSION EXISTS? | CLASSIFICATION |
|---|---|---|---|---|---|---|---|---|
| `AuditController` | `indexAction` | render filter form | delegates to `viewAction()` (already `read`-classified) | No | No | `default_audit_read` (GET); `viewAction` already `read` via `$readActions` | Yes (`_write` exists, unused by index) | `SAFE` (session-only date-filter state, `Snep_Audit_Manager::getAll()` is a SELECT) |
| `CallsReportController` | `indexAction` | render filter form | delegates to `getAnalytic()`/`getSynthetic()` (report query) | No | No | `default_calls-report_read` | No explicit write child | `SAFE` (session-only period filter, read-only report query) |
| `CnlController` | `indexAction` | render country dropdown | ZIP upload -> `updateAction_76()` -> DB import | **Yes** (`core_cnl_state`/`core_cnl_city`/`core_cnl_prefix`) | No | `default_cnl_read` (implicit only, before this task) | **No** (before this task) | `REAL_AUTHORIZATION_DEFECT` -- **FIXED_NOW** |
| `ConferenceRoomsController` | `indexAction` | render room/status list | rewrites `snep-conferences.conf`/`snep-authconferences.conf` | No (file, not DB) | **Yes** (Asterisk-consumed dialplan-adjacent config) | `default_conference-rooms_read` (implicit; explicit `_write` existed but was unused) | Yes (unused) | `REAL_AUTHORIZATION_DEFECT` -- **FIXED_NOW** |
| `DocsController` | `indexAction` | render doc list | renders one allowlisted local doc (`file_get_contents`) | No | No | `default_docs` (authenticated-open, per `$alwaysAllow`) | N/A | `SAFE` (read-only; TASK-0026I's own allowlist already prevents traversal) |
| `ErrorsKhompController` | `indexAction` | render Khomp link/error status | `AsteriskInfo::status_asterisk("khomp links errors clear", ...)` | No | **Yes** (AMI, clears live error counters) | `default_errors-khomp_read` (implicit only, before this task) | **No** (before this task) | `REAL_AUTHORIZATION_DEFECT` -- **FIXED_NOW** |
| `ErrorsTdmController` | `indexAction` | render TDM link/error status | mirrors `ErrorsKhompController` exactly (same AMI clear command) | No | **Yes** | `default_errors-tdm_read` (implicit only, before this task) | **No** (before this task) | `REAL_AUTHORIZATION_DEFECT` -- **FIXED_NOW** |
| `ExportDataController` | `indexAction` | render table/column picker | delegates to `exportAction()` (CSV stream or session-only filter store) | No | No | `default_export-data_read` (`export` already `read`-classified) | No explicit write child | `SAFE` (read-only export; TASK-0026C's own allowlist already prevents arbitrary table/column selection) |
| `IndexController` | `indexAction` | render dashboard | pre-registration branch: ITC vendor registration/notification writes | **Yes** (only while `$_SESSION['registered']!=true`) | No | `default_index` (authenticated-open, per `$alwaysAllow`) | N/A -- mechanism is the bypass list, not read/write | `FOLLOW_UP_REQUIRED` (different mechanism -- see OTHER CONTROLLER FINDINGS) |
| `KhompLinksController` | `indexAction` | render board list | redirects to `viewAction()` with a board-id filter (navigation only) | No | No | `default_khomp-links` (alias of `default_tdm-links`) | N/A | `SAFE` (pure filter/redirect, no mutation) |
| `LogsController` | `indexAction` | render log filter form | delegates to `viewAction()` (already `read`-classified) | No | No | `default_logs_read` (`view`/`getlogfile` already `read`) | Yes (unused by index) | `SAFE` |
| `ModuleSettingsController` | `indexAction` | render module settings form | `Snep_ModuleSettings_Manager::addConfig()`/`updateConfig()` | **Yes** (`core_config`, including SMTP credentials) | No | `default_module-settings_read` (implicit only, before this task) | **No** (before this task) | `REAL_AUTHORIZATION_DEFECT` -- **FIXED_NOW** |
| `ParametersController` | `indexAction` | render settings form | full `setup.conf` rewrite | Yes | Yes (`Snep_Locale::setExtensionsLanguage()`) | `default_parameters_write` (fixed by TASK-0034L) | Yes | `ALREADY_WRITE_GATED` (unchanged by this task) |
| `RankingReportController` | `indexAction` | render filter form | delegates to `viewAction()` (report query) | No | No | `default_ranking-report_read` (`view` already `read`) | Yes (unused by index) | `SAFE` |
| `RegisterController` | `indexAction` | ITC status display; **also writes `core_config`/distributions on GET** when already registered | ITC login/update (same mechanism as `IndexController`) | Yes (GET **and** POST) | No | `default_register` (authenticated-open, per `$alwaysAllow`) | N/A | `FOLLOW_UP_REQUIRED` (pre-existing GET-mutates pattern, mislabeled "read-only" in `$alwaysAllow`'s own comment -- see OTHER CONTROLLER FINDINGS) |
| `ServicesReportController` | `indexAction` | render filter form | delegates to `viewAction()` (report query) | No | No | `default_services-report_read` (`view` already `read`) | Yes (unused by index) | `SAFE` |
| `SimulatorController` | `indexAction` | render trunk list | dialplan simulation against existing routing rules (no PBX write) | No | No | `default_simulator` (authenticated-open, per `$alwaysAllow`) | N/A | `SAFE` |
| `TdmLinksController` | `indexAction` | render board list | redirects to `viewAction()` with a board-id filter (navigation only) | No | No | `default_tdm-links_read` (`view` already `read`) | Yes (unused by index) | `SAFE` |

No `UNKNOWN` remains.

The other 32 `indexAction()`-bearing controllers were also confirmed (not
assumed) to have **no** `getPost()`/`isPost()` call inside `indexAction()`
at all -- their real mutations live in separately-named, already
default-`write`-classified actions (`addAction`/`editAction`/
`removeAction`/etc., including `ExtensionsController`, which TASK-0034L's
own pattern-matched inventory had listed as a candidate; a precise
function-boundary check found its `getPost()`/`isPost()` calls all belong
to `addAction`/`editAction`/`removeAction`/`multiaddAction`/
`multiremoveAction`, none to `indexAction()` itself). `NOT_MUTATING`,
already correct.

## PHASE 2 — MUTATION CATEGORIES

| CONTROLLER | CATEGORY |
|---|---|
| `CnlController` | `DB_WRITE`, `IMPORT` |
| `ModuleSettingsController` | `DB_WRITE`, `UPDATE`/`CREATE` |
| `ErrorsKhompController` | `SERVICE_RELOAD`-adjacent (`ASTERISK_RELOAD` category: live AMI counter clear, not a config reload) |
| `ErrorsTdmController` | same as `ErrorsKhompController` |
| `ConferenceRoomsController` | `FILE_WRITE`, `CONFIG_WRITE` (Asterisk-consumed) |
| `IndexController`/`RegisterController` | `CREATE`/`UPDATE` (`OTHER` -- vendor ITC registration state, not PBX config) |
| everything else in the 17 | `OTHER` (filter/search/navigation state only) or none |

## PHASE 3 — PERMISSION-RESOURCE INVENTORY

Inspected `snep/modules/default/resources.xml`, `Snep_Modules::
loadResources()` (`snep/lib/Snep/Modules.php:127-160`, unchanged),
`Snep_PermissionPlugin` (`$alwaysAllow`/`$aliasResource`/`$readActions`/
`$writeOnPostIndex`), and `Snep_Permission_Manager`/`profiles_permissions`/
`users_permissions` (see PERMISSION MIGRATION STRATEGY below).

| CONTROLLER | READ_RESOURCE | WRITE_RESOURCE (before) | WRITE_RESOURCE (after) |
|---|---|---|---|
| `cnl` | implicit (`default_cnl_read`) | `NO_WRITE_RESOURCE` | `default_cnl_write` (new) |
| `module-settings` | implicit (`default_module-settings_read`) | `NO_WRITE_RESOURCE` | `default_module-settings_write` (new) |
| `errors-khomp` | implicit (`default_errors-khomp_read`) | `NO_WRITE_RESOURCE` | `default_errors-khomp_write` (new) |
| `errors-tdm` | implicit (`default_errors-tdm_read`) | `NO_WRITE_RESOURCE` | `default_errors-tdm_write` (new) |
| `conference-rooms` | implicit (`default_conference-rooms_read`) | `default_conference-rooms_write` (pre-existing, unused) | unchanged (now used) |
| `index`/`register` | N/A | `IMPLICIT_ONLY` (full `$alwaysAllow` bypass, not a read/write resource at all) | unchanged (`FOLLOW_UP_REQUIRED`, different mechanism) |

## PHASE 4-6 — PRIORITIZATION AND CNL CANONICAL MODEL

Per the task's own priority order (file upload/import first), `CnlController`
was evaluated and fixed first. Its canonical model, chosen for the same
reason TASK-0034L chose it for `parameters`:

```
GET  -> default_cnl_read   (render, list countries)
POST -> default_cnl_write  (ZIP upload/import)
```

Implemented via the same mechanism TASK-0034L introduced (opt-in,
per-controller `PermissionPlugin::$writeOnPostIndex` override, checked
only when `action=='index' && isPost()`) -- no new permission-check
architecture, no view/template change, no change to the existing form's
POST target.

## PHASE 5 — CNL REPRODUCTION (live, before the fix)

A dedicated read-only test identity (`task0034m-readonly`, zero superuser
bypass, `profile_id=1`, empty `users_permissions` baseline) was granted
**only** `default_cnl_read` via the real, unmodified `UsersController::
permissionAction()` UI flow. `PermissionPlugin.php` was in its genuine
pre-fix state (no `default_cnl` entry in `$writeOnPostIndex` existed yet
at the time of this reproduction -- nothing was reverted to capture it,
unlike TASK-0034L's Parameters proof, since this was the first task to
touch Cnl's authorization at all).

A minimal legitimate type-M fixture (`9999999\n` in a `.txt` inside a
correctly-named `.zip`) was uploaded through the real HTTP flow:

```
BEFORE: core_cnl_prefix WHERE id='9999999' AND country=76 -> 0 rows
POST /index.php/default/cnl/index (country=76, type=M, multipart file
  upload, valid session-bound CSRF token, read-only user's session)
  -> HTTP 302 (redirected to /index.php/cnl -- the standard success path)
AFTER:  core_cnl_prefix WHERE id='9999999' AND country=76 -> 1 row
        (69, NULL/NULL/NULL, matching the type-M insert shape)
```
Restored immediately (`DELETE ... WHERE id='9999999' AND country=76`).

This reproduction required seeding one missing reference row
(`core_cnl_country id=76` "Brazil") that this dev fixture's baseline
database does not carry -- `core_cnl_prefix.country` has a `NOT NULL`
foreign key to `core_cnl_country.id` (`core_cnl_prefix_ibfk_2`), so any
import of ANY shape fails closed with a caught, non-fatal
`Zend_Db_Statement_Exception` (rendered as the existing generic error
page, no partial write) until that row exists. This is a pre-existing
dev-fixture-completeness gap, not a security or authorization issue --
documented here and removed again immediately after use; see REMAINING
DEBT.

## PHASE 6 — CNL MUTATION INVENTORY

`CnlController::updateAction_76()` (`snep/modules/default/controllers/
CnlController.php:65-233`):
- Receives one uploaded file via `Zend_File_Transfer_Adapter_Http`,
  destination fixed at `/tmp` (TASK-0026D's own hardening).
- Opens it with PHP's native `ZipArchive` (no shell/`exec()` -- TASK-0026D).
- Rejects the WHOLE archive if any entry name contains `..` or starts
  with `/` (zip-slip defense-in-depth, TASK-0026D), before extracting
  anything.
- Extracts to `/tmp`, parses a fixed-width `.txt` file (`F` = full
  state/city/prefix rows; `M` = prefix-only rows).
- For each parsed prefix: `Snep_Cnl::addState()`/`addCity()`/
  `addPrefix()` -- each an `INSERT` guarded by "does it already exist?"
  (`getState()`/`getCityCode()`/`getPrefix()`), so re-running the same
  file twice is idempotent (no duplicate-key failure, no row overwrite).
- **No cleanup**: neither the uploaded `.zip` nor the extracted `.txt`
  is ever `unlink()`-ed. `/tmp` grows unbounded across imports. Not a
  security defect (not web-served, not attacker-namable beyond the
  upload's own filename), but real housekeeping debt -- see REMAINING
  DEBT.

Classification: **IMPORT** (strictly additive -- never `REPLACE`s or
removes an existing row, never `MERGE`s/updates one either).

## PHASE 7-9 — CANONICAL PERMISSION MODEL, WRITE-RESOURCE, MIGRATION STRATEGY

`resources.xml`'s `cnl` resource had no `write` child at all (unlike
`parameters`, which already had one before TASK-0026A ever needed it).
Added:
```xml
<resource id="cnl" label="Cnl Update" font="sn-busca">
    <resource id="write"></resource>
</resource>
```
Same additive shape already established for `parameters`/`sound-files`/
`music-on-hold` in the same `configs` group.

**Permission migration strategy: none required.** Investigated
`Snep_Permission_Manager::get()`/`getUser()`
(`snep/lib/Snep/Permission/Manager.php`) -- both are strict default-deny
(`SELECT ... WHERE profile_id=? AND permission_id=?`; no matching row
means `false`, which `PermissionPlugin::preDispatch()` treats as denied).
`profiles_permissions`/`users_permissions` (`snep/install/database/
schema.sql:745-771`) store `permission_id` as a free-form `VARCHAR`, not
an enum/FK against a fixed resource list -- a brand-new resource string
needs no schema change, no seed-data row, and no fresh-install SQL
change to become grantable; it simply becomes a new key nothing has ever
matched yet. Confirmed empty in this repo's own install SQL (`grep -rn
"INSERT INTO.*profiles_permissions\|INSERT INTO.*users_permissions"`
across every `.sql` file: zero hits outside test-harness scripts) --
exactly the same "starts at zero grants, relies on `id_user==1`" shape
TASK-0022 and TASK-0026A already established and TASK-0034L's own
BACKWARD COMPATIBILITY section already documented for `parameters`.
`Snep_Modules::loadResources()` (`snep/lib/Snep/Modules.php:127-160`)
auto-registers every `resources.xml` resource into the in-memory ACL on
every bootstrap -- no separate "resource registration" migration step
exists in this architecture at all.

## PHASE 10 — DIRECT-ENDPOINT AUTHORIZATION MATRIX

Test identities: `task0034m-cnl-readonly` (`default_cnl_read` only),
`task0034m-cnl-writer` (`default_cnl_read`+`default_cnl_write`),
`task0034m-cnl-zeroperm` (zero permissions), `admin` (superuser,
`id_user==1`), and a cookie-jar-less unauthenticated request. All five
proven live against the real HTTP endpoint (`/index.php/default/cnl/
index`), captured in `scripts/cnl-upload-authorization-security-smoke-
test.sh`:

```
unauthenticated -> HTTP 200, login page rendered in place (Snep_AuthPlugin's
                    established contract; not a 302, per every other
                    unauthenticated proof in this codebase)
zero-permission -> HTTP 302, Location: permission/error (GET and POST both)
read-only        -> GET HTTP 200 (still renders); POST HTTP 302,
                    Location: permission/error; core_cnl_prefix unchanged
write-authorized -> POST reaches the controller (not permission-denied);
                    see UPLOAD-SUBSYSTEM CAVEAT below for the exact HTTP
                    code observed in the committed suite
superuser         -> POST reaches the controller (not permission-denied);
                    same caveat
```

## PHASE 11 — CSRF CONTRACT

Isolated using the write-authorized session (denial can only be
attributed to CSRF, not permission), exactly TASK-0034L's own method:
```
POST, valid session+permission, NO snep_csrf_token      -> HTTP 403
POST, valid session+permission, WRONG snep_csrf_token    -> HTTP 403
POST, valid session+permission, VALID snep_csrf_token    -> reaches the
                                                             controller
                                                             (not 403)
```
`Snep_CsrfPlugin` was not touched -- reused exactly as-is, registered
after `Snep_PermissionPlugin` (authorization is checked first, matching
the codebase's own "authz before CSRF" precedent).

## PHASE 12 — GET/POST STRUCTURAL PROOF

```
GET /index.php/default/cnl/index?country=76&type=M (admin session,
  deliberately superuser so a failure could only be the GET/POST branch
  itself)
  -> HTTP 200, core_cnl_prefix unchanged
```
Structural: `indexAction()`'s mutation dispatch is
`if ($this->_request->getPost())`, which a GET never satisfies. No
`SECURITY_DEFECT` here (GET mutation was never possible on this action).

## PHASES 13-16 — UPLOAD SECURITY ON THE SAME SURFACE

**Extension/type checks**: the code requires the uploaded filename to
end in `.zip` (case-insensitive) before treating anything as an archive
at all; anything else is rejected with the existing generic error page.

**Zip-slip (Phase 14)**: crafted a zip whose entry name is
`../../../../tmp/task0034m-zipslip-marker.txt` (built directly with
Python's `zipfile` module, bypassing the `zip` CLI's own path
sanitization) alongside a legitimately-named sibling entry. Live HTTP
upload as the write-authorized user:
```
marker file outside /tmp: absent (never created)
sibling legitimate-named entry: also absent -- the existing guard
  rejects the WHOLE archive, not just the one bad entry, before
  extracting anything (TASK-0026D's own design, reconfirmed here)
```
Same result for a second archive using a bare-absolute-path entry name
(`/etc/task0034m-abspath-marker.txt`) instead of `../` traversal.
**No `REAL_SECURITY_DEFECT`** -- the pre-existing guard holds.

**Symlink entries (Phase 15)**: crafted a zip containing a genuine
Unix symlink entry (`zip -y`, which preserves the `S_IFLNK` bit in the
entry's external attributes -- confirmed via Python's `zipfile.ZipInfo.
external_attr`) pointing at `/etc/passwd`, plus a legitimately-named
sibling entry (whose name has neither `..` nor a leading `/`, so it
passes the existing guard and both entries get extracted). Proven twice:
1. **Isolated** (a bare PHP script calling `ZipArchive::extractTo()`
   directly, outside the controller, to test the library's own behavior
   in isolation): the symlink entry is extracted as an **inert regular
   file** containing the literal 11-byte string `/etc/passwd` (the
   stored link-target text) -- **not** a real filesystem symlink
   (`is_link()` false, `file` reports "ASCII text").
2. **End-to-end**, through the real controller, with the temporary
   evidence-capture patch described in UPLOAD-SUBSYSTEM CAVEAT below
   applied (reverted immediately after, never committed): identical
   result -- `/tmp/evil-link` is a regular file, not a symlink; the
   sibling legitimate entry's prefix WAS imported (proving the archive
   was not whole-archive-rejected, since the symlink entry's name alone
   doesn't trip the `..`/leading-`/` guard -- it is `libzip`'s own
   extraction behavior in this PHP 8.4 build, not application code,
   that prevents the escape).

No code change was made for this -- **verified safe empirically**, not
assumed. Flagged as a defense-in-depth `FOLLOW_UP_DEBT`: the application
has no explicit symlink-entry rejection of its own; safety currently
depends on this specific PHP/`libzip` build's extraction behavior, which
is not guaranteed by any documented contract. See REMAINING DEBT.

**Oversized upload (Phase 16)**: `upload_max_filesize=2M`/
`post_max_size=8M` (confirmed via `php -i` inside the app container). A
3MB fixture is rejected by PHP itself before `$_FILES` is even
populated with a valid `tmp_name` (`error=UPLOAD_ERR_INI_SIZE`);
`Zend_File_Transfer_Adapter_Http::receive()` returns `false`; the
controller renders its existing generic error page. `HTTP 200`, zero DB
mutation. No quota infrastructure was built (per the task's own
instruction) -- PHP's own ini limit is sufficient and already in force.

## PHASE 17 — ERROR DISCLOSURE

The oversized-upload and zip-slip/abspath denial pages were inspected
for `/var/www`, `/tmp/php...`, `SQLSTATE`, or "Stack trace" substrings --
none present in any response body. The rendered error is the same
generic `error_message` panel every other CnlController failure path
already uses.

## PHASES 18-19 — STATE INTEGRITY

**Denied requests** (unauthenticated/zero-permission/read-only): proven
above that `core_cnl_prefix` is byte-identical before/after every denied
attempt, and denial happens in `Snep_PermissionPlugin::preDispatch()`
strictly before the controller (and therefore before any DB query, ZIP
receive, or filesystem write) ever executes -- structurally, not just
observationally, the same guarantee TASK-0034L already established for
Parameters.

**Malformed/malicious archives** (zip-slip, absolute-path): proven above
that the whole archive is rejected atomically -- no partial import,
because extraction never begins at all once any one entry fails the
guard. No cleanup gap specific to this path beyond the pre-existing
general no-`unlink()` debt (PHASE 6).

## PHASE 20 — LEGITIMATE IMPORT PROOF

A realistic fixed-width type-F fixture (fake, non-colliding state code
`ZZ`, city `TASK0034M TESTCITY`, prefix `8888888`/`9990005`, in the
temporary-patch run and the committed-suite run respectively) was
uploaded by the write-authorized user:
```
BEFORE: core_cnl_state/city/prefix -- 0/0/0 matching rows
POST (type=F, valid fixture) -> HTTP 302
AFTER:  core_cnl_state:  1 row  (ZZ, 'Unknown', country=76)
        core_cnl_city:   1 row  (TASK0034M TESTCITY, state=ZZ)
        core_cnl_prefix: 1 row  (matching the city/state above)
```
Restored immediately (`DELETE` on all three, plus the seeded
`core_cnl_country` row if this run created it) -- confirmed
`core_cnl_prefix`/`core_cnl_state`/`core_cnl_city` all back to 0 rows.

This full end-to-end proof was captured using the same temporary,
evidence-only patch methodology TASK-0034L's own REPRODUCTION section
already established (see UPLOAD-SUBSYSTEM CAVEAT immediately below) --
never left in the committed diff. The **committed** regression suite
(`scripts/cnl-upload-authorization-security-smoke-test.sh`) proves the
authorization/CSRF/GET-safety/zip-slip/symlink/oversized-upload
invariants directly against the current, unpatched code (all of which
hold regardless of the caveat below), and proves the legitimate-import
invariant in its currently-achievable form: "still blocked by the
documented pre-existing defect, and still no partial import" -- it will
automatically start requiring the full success shape the day that
defect is fixed (see the suite's own `UPLOAD_SUBSYSTEM_BROKEN` probe).

## UPLOAD-SUBSYSTEM CAVEAT (discovered during Phase 5, not this task's to fix)

Reproducing Phase 5 hit two **pre-existing, unrelated PHP 8.4
compatibility defects** that make `CnlController`'s upload path return
`HTTP 500` for ANY file that transports successfully over HTTP,
regardless of who is calling it or what the file contains:

1. `Zend_Validate_File_Upload::isValid()`
   (`snep/lib/Zend/Validate/File/Upload.php:226`): `$this->_messages` is
   reset to `null` at the top of the method; on a genuinely
   error-free upload (`$content['error']===0` and `is_uploaded_file()`
   true), no code path ever reassigns it, so the final
   `count($this->_messages) > 0` calls `count(null)` -- a `TypeError`
   under PHP 8.0+ (previously a deprecation warning treated as `0`).
   **Category A** (syntax/API removed by PHP).
2. `CnlController::updateAction_76()`
   (`snep/modules/default/controllers/CnlController.php:173`):
   `if (count($prefixos > 0))` -- `$prefixos > 0` evaluates first
   (array-vs-int comparison, PHP coerces to `bool`), so `count()`
   receives a `bool`, not an array -- a second, distinct `TypeError`
   under PHP 8.0+, reached only after fixing (1). The evident intent was
   `count($prefixos) > 0`. **Category A**.

Both were confirmed via live stack traces in
`/var/log/apache2/mag-error.log` inside the running `app` container, not
assumed. Neither is an authorization or upload-security defect -- both
crash identically regardless of the caller's permission (a superuser
upload crashes exactly the same way a read-only user's denied-then-
hypothetically-allowed upload would) -- they were discovered purely as a
side effect of reproducing the authorization gap.

**Not fixed in this task.** Per this project's own bug/technical-debt
policy ("do not fix unrelated legacy bugs opportunistically... document
it, create or propose a dedicated future task") and the engineering
rules' scope-protection principle, these two defects are classified
`FOLLOW_UP_DEBT` with a recommended dedicated task below, not folded
into this authorization-boundary task's diff.

To still capture full end-to-end evidence for Phases 15/20 above
(otherwise entirely unreachable while these bugs stand), both files were
**temporarily** patched in the local working tree --
`Zend_Validate_File_Upload::isValid()`'s final check changed to
`count((array) $this->_messages) > 0`, and `CnlController.php:173`
changed to `count($prefixos) > 0` -- exactly the same "revert to
pre-fix, capture evidence, reapply/discard" methodology TASK-0034L's own
REPRODUCTION section already used for `PermissionPlugin.php`. Both were
reverted (`git checkout --`) immediately after capturing that evidence;
neither is present in this task's committed diff (confirmed: `git diff
--stat` on both files is empty at every checkpoint below).

**Release/pilot significance**: because `CnlController` is the *only*
call site anywhere in this repository of `Zend_File_Transfer_Adapter_Http`
(confirmed by `grep -rln` across `snep/modules` and `snep/lib/Snep`),
this specific defect pair currently makes CNL import **completely
non-functional for every role, including the superuser** -- not merely
harder to reach. That is a strictly worse outcome for the feature's
correctness than the authorization gap this task closes, but it also
means the authorization gap, while real and now fixed, was not
independently exploitable to complete a real import before this task
-- only to reach the code (which itself already proves the boundary was
missing; see Phase 5).

## PHASE 21-23 — OTHER CONTROLLER FINDINGS / SAME-SHAPE DEFECT DETECTION

Four controllers beyond `CnlController` were found sharing the *exact
same* `PermissionPlugin`/`resources.xml` mechanism (implicit-or-unused
read resource gating a real `indexAction()`-embedded POST mutation) and
were corrected together with it, per the task's own explicit allowance
("If another controller has the exact same mechanism and can be
corrected using the same narrow PermissionPlugin mapping, it may be
fixed in this task"):

- `ModuleSettingsController` (DB_WRITE, including SMTP credentials)
- `ErrorsKhompController` (AMI runtime mutation)
- `ErrorsTdmController` (AMI runtime mutation, identical to the above)
- `ConferenceRoomsController` (Asterisk-consumed config-file write --
  the one case where a `write` resource already existed but was simply
  never applied to `indexAction()`'s POST, the identical shape TASK-0034L
  closed for `parameters` itself)

Two **different-mechanism** findings were identified and deliberately
**not** folded into this task (scope: "do not balloon this into a global
RBAC rewrite" / "classify FOLLOW_UP_REQUIRED and create a recommended
task"):

- **`IndexController::indexAction()`**: while
  `$_SESSION['registered']!=true && $_SESSION['noregister']!=true` (i.e.
  before the PBX has ever completed the vendor "ITC" registration
  handshake, or has explicitly opted out), its POST branch calls
  `Snep_Register_Manager::registerITC()`/`addDistributions()`/
  `Snep_Notifications::addNotification()`/`noregister()` -- real DB
  writes to global, system-wide state. `default_index` is in
  `Snep_PermissionPlugin::$alwaysAllow` ("open to all authenticated
  users", a deliberate TASK-0026A decision, documented as being about
  the *dashboard*), and `preDispatch()` returns before any resource
  check for a key in that list -- so `$writeOnPostIndex` has no
  mechanism to reach this action at all; fixing it would mean changing
  the `$alwaysAllow` architecture itself for `default_index`, a
  materially different (and materially larger) change than this task's
  mandate. `$_SESSION['registered']` is itself set from a persistent
  `registered_itc` DB flag at login (`AuthController.php:198`), so this
  window is real but narrow: any authenticated user (regardless of
  permission grants) can complete or decline the PBX's one-time vendor
  registration only until an admin completes it once, after which the
  branch is dead for every subsequent login. Recommended follow-up:
  **TASK-0034N-CANDIDATE-1 — "ITC vendor-registration write surface
  authorization (IndexController/RegisterController)"**.
- **`RegisterController::indexAction()`**: mirrors the same ITC
  mechanism (its own POST branch, `$_POST['save']=='login'`, calls the
  same `registerITC()`/`addDistributions()`), but ALSO writes
  (`Snep_Register_Manager::removeDistributions()`/`addDistributions()`)
  unconditionally on a bare **GET**, whenever `registered_itc=="1"` --
  a pre-existing "GET mutates" pattern independent of authorization
  (this controller is *also* in `$alwaysAllow`, so every authenticated
  user already reaches it regardless). The existing `$alwaysAllow`
  comment for `default_register` ("read-only install/registration
  status display") is factually inaccurate given this evidence --
  documented here as a correction, not carried forward uncorrected.
  Same recommended follow-up task as above (same vendor-registration
  surface, same root architecture).

Every other controller in the 17-row Phase 1 table beyond these six
(`Audit`/`CallsReport`/`Docs`/`ExportData`/`KhompLinks`/`Logs`/
`RankingReport`/`ServicesReport`/`Simulator`/`TdmLinks`) was individually
traced (not pattern-matched) and confirmed `SAFE`/`NOT_MUTATING` --
session-scoped filter/report/navigation state only, zero persistent or
runtime side effect. No further `FOLLOW_UP_REQUIRED` items from this
set.

## PHASE 24 — PERMISSIONPLUGIN ARCHITECTURE

`$writeOnPostIndex` grew from 1 entry (TASK-0034L) to 6 (this task),
each with its own individually-justified inline comment, exactly the
existing convention. No blanket "POST-to-any-index-is-write" rule was
introduced; every entry required its own controller-specific evidence.
Deny-safe by construction: a GET to any `index` action, for any
controller, on any key not in this map, is completely unaffected.

## PHASE 25 — UNKNOWN-CONTROLLER FALLBACK

No behavior changed for any controller not explicitly discussed in this
document. `authorization-coverage-check.sh` (unchanged) re-confirms
every controller is still either resource-registered, aliased, or
explicitly authenticated-open -- 49/49 `PASS`, identical shape to before
this task.

## PHASE 26-27 — AUTHORIZATION COVERAGE / REGRESSION EXTENSION

- `scripts/authorization-smoke-test.sh`: extended with a `TASK-0034M`
  section covering the four bundled same-mechanism controllers
  (`module-settings`/`errors-khomp`/`errors-tdm`/`conference-rooms`):
  grant-read-only -> read still works, POST denied; grant-write -> POST
  no longer denied; revoke back to baseline -- reusing the suite's own
  existing `task0026a-restricted` fixture identity, exactly the
  established pattern. `ConferenceRoomsController`'s write-authorized
  proof genuinely rewrites both Asterisk conference config files (that
  is the point of the check); the suite snapshots them beforehand and
  restores + verifies the restore (`md5sum` before/after) as part of
  its own teardown. **51/51 PASS.**
- `scripts/cnl-upload-authorization-security-smoke-test.sh` (new,
  dedicated suite -- too much upload-specific fixture machinery for the
  lighter section above): the full CNL matrix from Phases 10-20,
  including a `UPLOAD_SUBSYSTEM_BROKEN` self-detecting probe (see
  UPLOAD-SUBSYSTEM CAVEAT) so every downstream check states plainly
  whether it observed the full happy path or the currently-expected
  "blocked by the separately-tracked bug, and correctly denied/contained
  regardless" shape. **27/27 PASS**, run twice consecutively with
  identical results. `authorization-coverage-check.sh`'s existing static
  inventory needed no change -- it already treats `cnl` as
  "resource-registered; unknown actions default to write" both before
  and after this task's `resources.xml` addition (a `write` child does
  not change that classification's own logic).
- `scripts/regression.sh`: registered the new suite immediately after
  `authorization-smoke`, same placement reasoning as its neighbors.

## PHASE 28-29 — FRESH-INSTALL / EXISTING-INSTALL COMPATIBILITY

No schema migration, no seed-data change, no fresh-install SQL change
(see PHASE 7-9). The seeded fresh-install `admin` account is `id=1`,
unconditionally bypassed by `Snep_PermissionPlugin::preDispatch()`
before any resource check runs at all -- unaffected by definition.
`profiles_permissions`/`users_permissions` start empty on a fresh
install (confirmed, PHASE 7-9) -- no non-superuser account has any of
the five new/newly-applied write requirements at all on a fresh
install, so nothing regresses for one. For an **existing** install, the
only accounts affected are ones an operator has already, deliberately,
granted read-only access to one of these five resources without also
granting write -- and the only possible effect is losing a mutation
capability that was never an intended, documented grant (the entire
point of this task). **No `PILOT_CONSTRAINT`** from either path -- this
is a strictly restrictive change (a previously-succeeding read-only-user
mutation now correctly fails); no role gains a capability it lacked.
`make fresh-install-smoke` was not re-run for this task (no
fresh-install-affecting change exists to validate against it, matching
TASK-0034L's own precedent of not re-running it for the identical
"read/write authorization split, no schema change" shape).

## PHASE 30 — UI BEHAVIOR

Unchanged for all five fixed controllers. None had a documented
read-only product role before this task (the whole point of each
finding is that no such role was ever intentionally supported); a
read-only user who submits one of these forms now sees the standard
permission-denied page instead of a silent mutation. Not classified as
requiring `senma-product-designer` review -- no new user-facing state,
no new screen, no workflow change for any already-supported role,
identical reasoning to TASK-0034L's own UI BEHAVIOR section.

## PHASE 31 — SECURITY-SUITE MATRIX

| SUITE | RESULT |
|---|---|
| `authorization-coverage-check.sh` | PASS (49 controllers, unchanged classification) |
| `authorization-smoke-test.sh` | PASS 51/51 (2 consecutive runs) |
| `cnl-upload-authorization-security-smoke-test.sh` (new) | PASS 27/27 (2 consecutive runs) |
| `session-csrf-security-smoke-test.sh` | PASS (see VALIDATION) |
| `preauth-security-smoke-test.sh` | PASS (see VALIDATION) |
| `auth-hardening-security-smoke-test.sh` | PASS (see VALIDATION) |
| `disclosure-path-security-smoke-test.sh` | PASS (see VALIDATION) |
| `shell-security-smoke-test.sh` | PASS (see VALIDATION) |

## PHASE 32 — SYSTEM/RUNTIME IMPACT

`ErrorsKhompController`/`ErrorsTdmController`'s AMI clear-counter command
and `ConferenceRoomsController`'s config-file rewrite are the only
telephony-adjacent mutations among the five. Both were reviewed with
`senma-telephony-architect`'s invariants:
- No PJSIP/`chan_sip` implication (Khomp is TDM hardware, entirely
  outside the PJSIP-only supported SIP stack; conference rooms are a
  separate dialplan feature, not extension/trunk/transport modeling).
- No reload/restart/regeneration semantics changed -- the AMI command
  and the config-file rewrite behave exactly as before; only who may
  trigger them changed.
- No runtime-contract or customer-owned-configuration-classification
  change -- `snep-conferences.conf`/`snep-authconferences.conf` remain
  application-generated files this controller already owned writing to.
**Telephony proof = evidence-based `NOT_APPLICABLE` to runtime-contract
change; `APPROVE`** for the authorization-boundary tightening itself.

## PHASE 33 — REPEATABILITY

Both new/extended suites were run twice consecutively with no manual
repair/reset between runs and identical PASS counts each time (51/51 and
27/27). The CNL suite's own teardown removes its uploaded/extracted
`/tmp` artifacts explicitly (`CnlController` itself does not -- see
REMAINING DEBT) and resets all three test identities' permissions and
the `core_cnl_country` seed row (only if this run created it) to the
exact baseline found at the top of the run. No stale fixtures, no
leftover files, no session leakage observed across either repeated run.

## OTHER CONTROLLER FINDINGS / FOLLOW-UP TASKS (summary)

1. **TASK-0034N-CANDIDATE-1** — ITC vendor-registration write surface
   authorization (`IndexController`/`RegisterController`). Different
   mechanism (`$alwaysAllow` full bypass, not read/write
   classification); narrow window (dead once an install completes
   registration once); `RegisterController`'s GET-mutates behavior and
   its own inaccurate `$alwaysAllow` comment should be corrected in the
   same task.
2. **TASK-0034N-CANDIDATE-2** — `Zend_Validate_File_Upload`/
   `CnlController` PHP 8.4 `count()` TypeErrors (UPLOAD-SUBSYSTEM
   CAVEAT above). Recommend high priority: this makes CNL import
   completely non-functional for every role today, independent of this
   task's authorization fix, and is a two-line, well-understood,
   behavior-preserving compatibility repair.
3. `CnlController`'s missing `unlink()` cleanup of its own uploaded/
   extracted `/tmp` files (PHASE 6) -- minor housekeeping debt, not a
   security defect.
4. No explicit application-level symlink-entry rejection in
   `CnlController`'s zip-slip guard (PHASE 13-16) -- currently safe only
   because of this PHP/`libzip` build's own extraction behavior, not a
   documented contract; a one-line defense-in-depth addition (reject any
   entry whose external Unix mode bits indicate `S_IFLNK`) would remove
   that implicit dependency. Low severity given the verified-safe
   current behavior.

## FIXED_NOW

- `CnlController` (`default_cnl_write`, new resource)
- `ModuleSettingsController` (`default_module-settings_write`, new resource)
- `ErrorsKhompController` (`default_errors-khomp_write`, new resource)
- `ErrorsTdmController` (`default_errors-tdm_write`, new resource)
- `ConferenceRoomsController` (`default_conference-rooms_write`, pre-existing resource, newly applied)

## FOLLOW_UP_DEBT

1. ITC vendor-registration write surface (`IndexController`/
   `RegisterController`) -- different mechanism, see above.
2. `Zend_Validate_File_Upload`/`CnlController` PHP 8.4 `count()`
   TypeErrors -- separately-scoped compatibility defect, see above.
3. `CnlController`'s missing upload/extraction cleanup.
4. `CnlController`'s zip-slip guard has no explicit symlink-entry
   rejection (currently safe empirically, not by documented contract).
5. `Snep_Parameters_Manager::change()` -- confirmed dead/unreachable by
   TASK-0034L; unchanged, still a candidate for future dead-code removal.

## RELEASE/PILOT IMPACT

Re-read `docs/tasks/0034-release-readiness-production-pilot-gate.md`.
Updated in place with a new `UPDATE (TASK-0034M)` entry in its §41
known-debt table (historical findings preserved, nothing overwritten):

- `CnlController`'s read-implies-write gap: **was `PILOT_CONSTRAINT`**
  (server-side-reachable, bounded to accounts an install operator would
  have to deliberately grant read-only Cnl access to) **-> now
  Closed**, same classification lifecycle as TASK-0034L's own Parameters
  finding.
- `ModuleSettingsController`/`ErrorsKhompController`/
  `ErrorsTdmController`/`ConferenceRoomsController`'s identical gaps:
  **new findings, immediately Closed** by this same task (never shipped
  as an open pilot item).
- ITC vendor-registration write surface: **new finding, classified
  `PILOT_CONSTRAINT`** (narrow window, dead after one-time registration,
  but real and unauthenticated-adjacent in spirit -- any authenticated
  user, zero grants required) pending TASK-0034N-CANDIDATE-1.
- `Zend_Validate_File_Upload`/`CnlController` PHP 8.4 compatibility
  defect: **new finding, classified `PILOT_BLOCKER`** for the CNL-import
  feature specifically (the feature is completely non-functional for
  every role, including superuser, independent of any permission grant)
  -- not a `PILOT_CONSTRAINT`, since no authorization workaround exists
  to route around a hard crash. Does not block the pilot **overall**
  (CNL import is an optional administrative data-loading feature, not on
  the pilot's critical call/provisioning path), but must be resolved
  before CNL import is presented as a supported pilot feature.

## COMPANION REGRESSION FIXES (required by this task's own change, not scope creep)

The first full `make regression` run against the implemented fix
surfaced two suites that needed correction -- both are direct,
necessary consequences of closing the authorization gap, not unrelated
work:

1. **`scripts/residual-sql-security-smoke-test.sh`** (TASK-0026P
   section): its own historical documentation already recorded, as
   supporting context for an unrelated SQL-injection proof, that "a
   read-only grant is sufficient to reach the [ModuleSettings] POST-
   driven save path" -- exactly the gap this task closes. Its
   "legitimate save flow persists correctly" check relied on that now-
   closed gap to reach a working save with only a read grant.
   Classified `WRONG_TEST_ASSUMPTION` (the assumption predates and is
   invalidated by this task's own fix, per senma-engineering-rules' test
   philosophy) -- fixed by adding `default_module-settings_write` to the
   shared restricted test user's existing bulk grant (one flag), with
   the stale comments corrected in place (historical record preserved,
   corrected inline per this project's documentation policy). No SQL-
   safety assertion was weakened or removed -- the fixture now reaches
   the save path via the correct, newly-required grant instead of the
   closed gap.
2. **`scripts/authorization-smoke-test.sh`** (this task's own new
   section): `docker compose cp`, used to snapshot/restore
   `snep-conferences.conf`/`snep-authconferences.conf` around the
   `ConferenceRoomsController` write-authorized proof, writes the
   destination as `root`, silently dropping the app image's own
   `997:senma-config`/`664` ownership -- confirmed live to make
   `Snep_Inspector`'s unrelated "Environment for AGI SNEP" check report
   both files as no longer writable, which then failed
   `system-status-runtime-smoke-test.sh`. A `REAL_PRODUCT_BUG` in this
   task's own new test code (not the application), fixed by capturing
   the original owner/mode once (`stat -c '%u:%g %a'`) and re-applying
   it (`chown`/`chmod` as root) after every `cp` restore, with a new
   explicit owner/mode-restored assertion added alongside the existing
   content-restored one so a recurrence would be caught immediately
   rather than surfacing as a confusing failure in a different,
   unrelated suite.

Both were verified fixed by re-running the affected suites in isolation
(`residual-sql-security-smoke-test.sh`: 270/270 PASS, up from 269/1;
`system-status-runtime-smoke-test.sh`: 11/11 PASS, up from 9/2) before
re-running the full regression suite.

## VALIDATION

- `make lint` equivalent (`scripts/lint.sh`): **PASS 5/5** (275 PHP
  files/0 syntax errors including the touched `PermissionPlugin.php`;
  71 shell scripts including the new suite; 3/3 `resources.xml` files
  well-formed XML including the edited one; `git diff --check` clean).
- `make regression` run 1 (before the two companion fixes above):
  **FAIL 42/45** -- `release-artifact-smoke` (pre-existing, unrelated;
  see UPLOAD-SUBSYSTEM CAVEAT-adjacent note below), plus the two
  companion-fix suites above, both diagnosed and corrected the same
  session.
- `make regression` run 2 (after the companion fixes): **FAIL 42/45,
  BLOCKED 2/45** -- `release-artifact-smoke` still fails (confirmed
  pre-existing/unrelated, see below); `dialplan-legacy-closure` and
  `restart-smoke` reported transient `BLOCKED` (PJSIP module-status
  race / SIP UA registration race -- the exact already-catalogued
  class of transient cross-suite timing flake documented in
  `docs/tasks/0034-release-readiness-production-pilot-gate.md` §44,
  reconfirmed here on different suites than its own prior occurrence).
- `make regression` run 3 (immediate re-run, no manual repair/reset):
  **44/45 PASS** -- both transient `BLOCKED` suites cleared on their
  own, exactly the precedented pattern.
- `make regression` run 4 (consecutive, no manual repair/reset):
  **44/45 PASS** -- identical to run 3. **Runs 3 and 4 together satisfy
  the "two consecutive clean regression runs" gate.**
- **`release-artifact-smoke` remains the one open item** across every
  run: its "revision matches current HEAD" check found the running dev
  image's embedded git-revision label (`1b5fd05`) two commits behind
  the actual `git HEAD` this task started from (`ce0b13b`) -- i.e. the
  image was already stale *before this task's session began* (`ce0b13b`
  was this task's own STARTING STATE, per the top of this document).
  This task made no Dockerfile/build/image change of any kind, and
  every one of this task's own code changes lives in bind-mounted
  PHP/config files that take effect without a rebuild (proven
  throughout this document's own live HTTP evidence) -- confirmed
  `PRE_EXISTING`/`UNRELATED_TO_THIS_TASK`, not a regression to fix here.
  An operator who wants this specific check green should run `make
  release-build VERSION=vX.Y.Z` (or `make dev`'s own rebuild path); out
  of this task's scope to do unprompted.
- `make doctor`: **PASS**, 0 FAIL (2 pre-existing dev-fixture-expected
  advisories: `provider` container / TLS dev-fixture certificate,
  neither related to this task).
- `make secrets-check`: **PASS** -- `OVERALL: MATCH`.
- `make migrate-check`: **PASS** -- `SCHEMA_CURRENT`.
- `make reconcile-check`: **PASS** -- `IN_SYNC`.
- `git diff --check`: **PASS** (no whitespace errors in the task diff).
- `git status --short`: see COMMIT CHECKPOINT below.

## COMMIT CHECKPOINT

See the shared checkpoint below for the full 52-item report, exact
command output, and the proposed commit split. This document itself is
part of the `docs:` commit.

## RECOMMENDATION

`APPROVE_WITH_CONSTRAINTS` -- the CNL boundary and its four same-shape
siblings are closed and regression-proven; the two `FOLLOW_UP_REQUIRED`
items (ITC registration surface, upload-subsystem PHP 8.4 defect) are
real, evidenced, and deliberately deferred to dedicated follow-up tasks
per this task's own scope-protection mandate, not silently absorbed or
silently dropped.
