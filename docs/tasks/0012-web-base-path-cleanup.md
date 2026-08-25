# TASK-0012 — Web base-path cleanup

## Status

**Implemented and validated.** `make smoke`: 16 PASS / 0 FAIL / 0
EXPECTED_LIMITATION, re-verified after a full clean rebuild (deleted the
generated `setup.conf` and let `docker/entrypoint.sh` regenerate it from
scratch, rather than relying on the manual live-patch used during
investigation). `make call-smoke`: 18/18 PASS, including a real
create-extension HTTP flow. Extension create/edit/delete was additionally
validated by hand against the running UI (see §6). Not committed —
stopping at the checkpoint per the task instructions.

## Goal

Make SENMA work correctly when published at the web root
(`http://host:port/`) without generating legacy browser URLs prefixed
with `/snep/`, while leaving filesystem paths (`/var/www/html/snep`)
untouched. Root deployment must work by default; subdirectory deployment
(`/snep`) must remain possible without hardcoding either case.

## 1. Root cause

`snep/includes/setup.conf`'s `[system]` section has always distinguished
two independent settings:

- `path.base` — the filesystem path (`/var/www/html/snep`). Correct,
  untouched, out of scope for this task.
- `path.web` — the application's **web base URL**. Historically hardcoded
  to `"/snep"`, inherited from SNEP's original deployment model (the app
  living in a subdirectory of a shared web root). This project's actual
  Docker deployment serves SENMA directly at the web root
  (`docker/apache-mag.conf`'s `DocumentRoot` points straight at
  `/var/www/html/snep`), so `/snep`-prefixed URLs 404 — confirmed live via
  curl before any fix was applied.

`path.web`'s value is consumed in two very different ways across the
codebase, and conflating them was the source of most of the bugs found
here:

1. **As a literal string prefix**, spliced directly into hardcoded
   `href`/`src`/AJAX-URL strings in views, or used for positional string
   parsing (`explode`, `str_replace`) elsewhere. These call sites broke
   the instant `path.web` stopped being exactly `"/snep"`.
2. **Indirectly, via Zend's own request-derived base URL** —
   `Zend_Controller_Front::getInstance()->getBaseUrl()` (and the
   `$this->baseUrl()` view helper), computed at request time from
   `$_SERVER['SCRIPT_NAME']`. This already worked correctly for both root
   and subdirectory deployments with zero configuration and was already
   used correctly at 314 call sites throughout the codebase.

## 2. Canonical source of the web base URL

**`Zend_Controller_Front::getInstance()->getBaseUrl()` /
`$this->baseUrl()` is the canonical source.** It is self-detecting,
requires no configuration, and is correct in both deployment modes by
construction. `setup.conf`'s `path.web` is kept only as a **necessary
exception** for the one consumer that runs before Zend's front controller
exists:

- `snep/index.php` calls `Snep_Modules::getInstance()->addPath(...)`
  (line 51) — which drives `Snep_Modules::registerModule()`'s menu-URI
  construction — **before** `new Zend_Application(...)` is instantiated
  (line 58). At that point the request object doesn't exist yet, so
  `Zend_Controller_Front::getInstance()->getBaseUrl()` cannot be called.
  This one file has no alternative but to read the base URL from
  `setup.conf` directly.

Because of that one bootstrap-time constraint, the fix makes `path.web`'s
*value* itself environment-configurable (default empty = root) rather
than trying to convert `Snep_Modules.php` (and its handful of incidental
siblings — `Snep_SoundFiles_Manager.php`, `CnlController.php`,
`snep-env.js.php`) to Zend's request-time mechanism. Both sources now
agree by construction: on a root deployment both resolve to `""`; on a
subdirectory deployment both resolve to the same configured prefix.

## 3. Configuration change

`snep/includes/setup.conf.dist` (committed default):
```
path.web = ""
```
(was `"/snep"`). `path.modrewrite` was confirmed completely unused
elsewhere in the codebase and left untouched.

`docker/entrypoint.sh` templates `path.web` from a new environment
variable on first boot only (same pattern already used for DB/AMI
credentials):
```bash
sed -i -e "s|^path\.web = .*|path.web = \"${SENMA_WEB_BASE_PATH:-}\"|" "$SETUP_CONF"
```

New variable, `SENMA_WEB_BASE_PATH` (`.env.example`, `.env`): optional,
default empty (root deployment). Set to e.g. `/snep` (leading slash, no
trailing slash) only for a genuine subdirectory deployment.

This was verified against the actual committed files, not just the
manual live-patch used during investigation: the generated
`snep/includes/setup.conf` (gitignored, runtime-only) was deleted and the
`app` container restarted, letting `entrypoint.sh` regenerate it from
`setup.conf.dist` + environment from scratch. Result: `path.web = ""`,
confirmed correct, and the dashboard/menu HTML confirmed to contain zero
`/snep` occurrences afterward.

## 4. Files changed

67 files touched. All changes are either (a) using the existing
`$this->baseUrl()` helper / `Zend_Controller_Front::getInstance()->getBaseUrl()`
in place of a hardcoded `/snep` literal, or (b) the `path.web`
configuration change described above. No controller logic, PJSIP
provisioning code, or database schema was touched.

**Configuration / infrastructure:**
- `snep/includes/setup.conf.dist` — `path.web` default `"/snep"` → `""`.
- `docker/entrypoint.sh` — templates `path.web` from `SENMA_WEB_BASE_PATH`.
- `.env.example`, `.env` — new `SENMA_WEB_BASE_PATH` variable.

**Two independent, pre-existing "second-order" bugs**, found by tracing
every place that assumed `path.web` was literally the 6-character string
`"/snep"` beyond simple URL building — both would have silently broken
the moment `path.web` changed, regardless of how that change was made:

- `snep/lib/Snep/Menu.php` — `getPermission($uri)` parsed `$uri` via
  `explode("/", $uri)` at **fixed indices** (`[3]`/`[4]`, threshold
  `$count > 4`), hardcoded to the assumption that every URI is the
  6-segment `/snep/index.php/module/action`. With `path.web=""`, real
  URIs are the 4-segment `/index.php/module/action` — silently wrong
  indices and a `$count > 4` that's now always false, causing an
  **unconditional `return true`**, i.e. the entire menu permission system
  would have been bypassed (all menu items visible to all users
  regardless of actual permissions). Fixed by stripping the actual
  configured base URL from `$uri` first, so what's left is always the
  fixed shape regardless of deployment mode.
- `snep/lib/Snep/Dashboard/Manager.php` — `getModelos()` used
  `str_replace("/snep/index.php/".$explode[0]."/", "", $item->getUri())`
  to turn an absolute menu URI into a relative dashboard-widget link.
  Once the URI no longer contained the literal substring, this became a
  silent no-op, leaving `link` as the full absolute URI instead of a
  relative fragment — breaking dashboard-widget shortcut links for
  non-`default`-module items (e.g. billing). Fixed to build the same
  prefix from the actual configured `path.web` value.
- `snep/lib/Snep/Menu.php` — `render()`'s dashboard-icon fallback link and
  `snep/modules/default/views/layouts/layout.phtml`'s logo link/3
  flag-icon `<img>` paths were plain hardcoded `/snep/...` strings;
  switched to the request-time base URL for consistency with the
  already-correct calls on the same pages.

**A separate, unrelated, pre-existing bug found incidentally** while
fixing the first hardcoded URL in `ip-status/index.phtml`: 36 files used
`<?php echo $this->baseUrl ?>` — **missing parentheses**. Zend's
`Zend_View_Abstract::__get()` (magic property access, no parens) just
returns `null`; only `__call()` (i.e. `$this->baseUrl()`, method-call
syntax) actually invokes the view helper. So `$this->baseUrl ?>` silently
evaluated to an empty string in every one of these files, not the
auto-detected base URL — meaning these links were *already* broken
(pointing at `/whatever` instead of `/snep/whatever` or the correct root
path) before this task, independent of the `path.web` question. Fixed by
appending the missing `()` — confirmed via grep that the broken pattern
was 100% consistent (`$this->baseUrl ?>`, never `baseUrl() ?>` or similar)
before applying the fix mechanically across all 36 files.

**Genuine hardcoded `/snep/` literals in `src=`/`href=`/`"sUrl":`/`.load()`
across 44 view files** (`<script src>`, `<link href>`, DataTables i18n
JSON URLs, jQuery `.load()` AJAX calls) — the actual browser-facing-URL
scope of this task. Fixed with one mechanical pass (a single Perl script
applying the same 3 substitution patterns to every matched file, skipping
lines that are pure HTML comments), not per-link hand edits. Representative
files: `route/add_edit.phtml`, `calls-report/analytic.phtml` and
`synthetic.phtml`, `sound-files/index.phtml`, `extensions/index.phtml`,
`users/addedit.phtml`, `queues/members.phtml`, `contacts/addedit.phtml`
(the `.load('/snep/includes/cidades.php...')` AJAX call), and 3 files in
`auth/`, plus `index/add.phtml`, `register.phtml`/`loginregister.phtml`
layouts, and 2 files under `snep/modules/billing/`.

**Two genuine browser-facing URLs built in lib/controller code (not
views), both confirmed live via call-site tracing:**
- `snep/lib/Snep/Manutencao.php` — `arquivoExiste()` (called from
  `CallsReportController.php:471`, its result rendered directly as an
  `<audio src>` in `calls-report/analytic.phtml:77` — a real browser
  playback URL for call recordings) and `compactaArquivos()` both
  returned hardcoded `"/snep/arquivos/..."`. `snep/arquivos/` is a real
  directory served directly from the docroot (confirmed:
  `path_voz = "/var/www/html/snep/arquivos/"`), so this is exactly the
  same class of bug as the CSS/JS asset paths, just built in PHP instead
  of a view. Fixed using `Zend_Controller_Front::getInstance()->getBaseUrl()`
  (both methods only ever run inside a dispatched request, so the front
  controller is guaranteed to exist).
- `snep/modules/default/controllers/NotificationsController.php` —
  `indexAction()`'s notification-carousel HTML built 3 hardcoded
  `"/snep/index.php/default/notifications?id=..."` links; fixed by
  reusing the exact `getFrontController()->getBaseUrl()` pattern already
  used earlier in the same method.

**Identified, deliberately left unchanged:**
- `snep/lib/Snep/Services.php`'s `getPathService()` builds a hardcoded
  `/snep/modules/default/api/...` URL for a server-to-server HTTP
  request. Traced with `grep -rn` for both `Snep_Services` and
  `getPathService`: **zero call sites anywhere in the tree.** Dead code,
  not reachable, not browser-facing even in principle. Left untouched per
  the task's "prefer centralized fix... don't refactor broadly" guidance
  — touching unreachable code has no behavioral effect and only adds
  unnecessary diff.
- The one commented-out `<!-- <link href="/snep/css/bootstrap-theme.min.css" ...> -->`
  line (present in 3 files: `ip-status/index.phtml`,
  `extensions/addedit.phtml`, `trunks/addedit.phtml`) — dead HTML, never
  rendered as a live resource. Left as-is; the mechanical fix script
  explicitly skips comment-only lines.
- `snep/lib/Snep/Modules.php` (the dominant, bootstrap-constrained
  menu-URI builder — see §2), `Snep_SoundFiles_Manager.php`,
  `CnlController.php`, `snep/includes/javascript/snep-env.js.php` — all
  pre-existing consumers of `path.web` that needed no code change, since
  they already read the (now-corrected) config value automatically.
- Filesystem paths shown as configuration *values* (not URLs) — e.g. the
  Settings page's "Caminho dos arquivos de gravação" field, which
  legitimately displays the literal string `/var/www/html/snep/arquivos/`
  — are correctly untouched per the task's explicit instruction not to
  rename/remove filesystem paths.

## 5. Compatibility

- **Root deployment (`SENMA_WEB_BASE_PATH` empty, the project's actual
  default):** works with zero `/snep` prefix anywhere in rendered HTML,
  confirmed across all 8 checklist pages plus static-asset loading.
- **Subdirectory deployment (`SENMA_WEB_BASE_PATH=/snep`):** still
  supported without code changes — `path.web` becomes `/snep`, both the
  Zend-request-derived base URL (which independently detects the same
  prefix from `SCRIPT_NAME`) and the bootstrap-time `Snep_Modules`
  consumer agree, and every fixed call site in this task uses one of
  those two sources rather than a literal. Not re-tested end-to-end in
  this task (out of scope — no subdirectory Apache config exists in this
  project to test against), but the mechanism is symmetric with the
  root-deployment path that *was* fully validated.

## 6. Manual browser/HTTP validation

All 8 checklist pages fetched via authenticated HTTP after a full clean
rebuild (regenerated `setup.conf`, not the manual live-patch):

| Page | Route | HTTP | `/snep` in HTML |
|---|---|---|---|
| Dashboard | `default/index` | 200 | 0 |
| Extensions | `default/extensions` | 200 | 0 |
| Trunks | `default/trunks` | 200 | 0 |
| Routes | `default/route` | 200 | 0 |
| Groups | `default/extensions-groups` | 200 | 0 |
| Queues | `default/queues` | 200 | 0 |
| Reports | `default/calls-report` | 200 | 0 |
| Settings | `default/parameters` | 200 | 2 (legitimate filesystem-path field values, not URLs — see §4) |
| System status | `default/ip-status` | 200 | 1 (dead HTML comment — see §4) |

Static asset spot-check (all 200 at root, no `/snep` prefix needed):
`/css/snep.css`, `/includes/javascript/snep-env.js.php`,
`/images/snep-main-logo.png`,
`/includes/javascript/datatables/media/language/pt-BR.json`.

Extension create/edit/delete, exercised against the real running UI:
- **Create**: `POST /index.php/default/extensions/add` with the full
  PJSIP field set → `302`, extension persisted (`peers` table).
- **Edit**: `GET /index.php/default/extensions/edit/id/<n>` → `200`, form
  `action="/index.php/extensions/edit/id/<n>"` (root-relative, no `/snep`,
  no double-prefix).
- **Delete**: `POST /index.php/default/extensions/remove` → `302`, row
  removed.
- Additionally covered end-to-end (including PJSIP config generation,
  Asterisk registration, an actual call, and CDR readback) by
  `make call-smoke`'s real create/delete HTTP flow — 18/18 PASS.

Forms/redirects/AJAX: extension add/edit form actions verified
root-relative and correct; login/logout redirects verified (`make smoke`);
DataTables i18n AJAX URL and the `cidades.php`/`estados.php` AJAX calls
verified to use `$this->baseUrl()` (see §4); no duplicated `/snep` prefix
found anywhere in any fetched page.

## 7. Regression

- `make smoke`: **16 PASS / 0 FAIL / 0 EXPECTED_LIMITATION**, re-run
  after the full clean rebuild.
- `make call-smoke`: **18/18 PASS**, re-run after the full clean rebuild,
  exercising real extension provisioning end-to-end.

One transient `make smoke` failure occurred mid-investigation (dashboard
expected `302`, got `200`) and was **not a code regression**: the seeded
`admin` account's `dashboard` column had a stale non-empty value
(`a:1:{i:0;i:0;}`) left over from earlier manual dashboard testing
earlier in this session, against the same long-lived dev DB volume.
`smoke-test.sh` documents that it deliberately never touches that column.
Resetting it to empty (matching a genuinely fresh install) restored the
expected `302` redirect-to-`index/add` behavior with no code change.
Recorded here since it looked like a regression at first glance.

## 8. Out-of-scope finding (not fixed, reported only)

While validating the extension list page by hand, found a **pre-existing,
unrelated PHP 8 fatal error**: `ExtensionsController::securityPassword()`
(`snep/modules/default/controllers/ExtensionsController.php:120`) calls
`count(password)` — a bareword `password` (missing `$`), which PHP 8
treats as an undefined-constant reference and throws a fatal `Error`,
crashing the entire extensions list page (`indexAction()` calls
`securityPassword()` for every stored extension) whenever at least one
extension exists in the database. Root cause is unrelated to base-path/URL
behavior (likely also intends `strlen()`, not `count()`, on a password
string) — explicitly out of scope for this task ("do not refactor
controllers broadly"). Not fixed here; the DB state that triggered it
during manual testing was cleaned up (test extension removed) so `make
smoke`/`make call-smoke` are unaffected. Worth a dedicated follow-up task.
