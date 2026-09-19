# TASK-0034I-R7 — Global Front-Controller / Base-URL Audit and Hardening

**Status:** local implementation checkpoint (see FINAL DECISION in agent report)
**Depends on:** TASK-0034I-R6 / `v0.1.0-rc.17` (immutable)
**Does not:** mutate `v0.1.0-rc.17`, deploy, create a new RC, broad URL
rewrite of unrelated modules, PickupGroups/Parameters `mysql_escape_string`
sites (deferred), open-redirect / X-Forwarded-* model changes

## Pilot evidence

| Flow | Method | URL | Status | Root cause |
|---|---|---|---|---|
| Duplicate rule | GET | `/index.php/route/duplicate/id/1` | **500** | `mysql_escape_string()` removed in PHP 7+ (`RouteController.php` duplicateAction) |
| Edit rule | GET | `/index.php/route/edit/id/1` | **500** | same (`editAction`) |
| Create + Queue action | POST | `/index.php/default/route/add` | **302** when payload correct | Not an index.php bug; empty `actions_list` warned under PHP 8 |
| Delete from list | GET | `/route/remove/id/1` (generated href) | **404** | List view omitted front-controller prefix |
| Duplicate from list | GET | `/index.php/route/duplicate/1` (generated href) | **500** then would be **404** | Missing `/id/` key; ZF does not bind trailing segment as `id` |
| Dashboard | href | `/index.php/index.php/default/index` | broken | `getBaseUrl()` already `/index.php` + literal `/index.php/...` |

Create-with-Queue **succeeds** when `actions_order=actions_list[]=0` (Scriptaculous serialize shape). Pilot “create route to queue fails” aligns with edit/duplicate fatals and broken list URLs, not with a separate Queue action bug.

## Index.php relationship

`index.php` is **not** the cause of the HTTP 500 (that is `mysql_escape_string`).
It **is** causally involved in:

1. R6 recording URLs (`getBaseUrl()` + `/arquivos` → `/index.php/arquivos/...`) — already fixed.
2. Route list/delete/simulator/dashboard URL construction that conflates
   Zend FC base (may include `index.php`) with deployment web base (`path.web`)
   and with the view helper `$this->baseUrl()` (strips script name).

## Canonical contract (`Snep_Url`)

| Helper | Meaning | Root example | Subdir example |
|---|---|---|---|
| `webBasePath()` | Deployment base (`path.web`) | `""` | `/senma` |
| `scriptUrl()` | Front-controller entry | `/index.php` | `/senma/index.php` |
| `publicAssetBaseUrl()` / `assetUrl()` | Static/public assets | `/arquivos/...` | `/senma/arquivos/...` |
| `actionUrl($c,$a,$params,$module)` | Controller/action URL | `/index.php/route/edit/id/1` | `/senma/index.php/route/edit/id/1` |

Rules:

- Callers must not append `/index.php` onto `Zend_Controller_Front::getBaseUrl()`.
- Static assets must never include `index.php`.
- Absolute / scheme-relative / `..` paths are rejected (no open redirect / host injection).
- No new trust of `X-Forwarded-*`.

`Snep_Manutencao::publicAssetBaseUrl()` now delegates to `Snep_Url`.
`snep-env.js.php` emits `SNEP_BASEURL` / `SNEP_SCRIPTURL` from the same helpers.

## Fixes in this task

- `RouteController` edit/duplicate: `(int)$id` + 404 for `<1`; no `mysql_escape_string`
- `isValidPost` / `parseRuleFromPost`: empty `actions_list` safe under PHP 8
- `route/index.phtml`: list/filter/simulator/toogle/delete via `Snep_Url::actionUrl`
- `Snep_Menu` dashboard: no doubled `index.php`
- `agi_rules.js`: remove-button image uses `SNEP_BASEURL` (not hardcoded `/snep/`)

## Deferred URL debt

| Item | Category | Notes |
|---|---|---|
| `PickupGroupsController` / `Snep_Parameters_Manager` `mysql_escape_string` | PHP8 debt | Same removed-function class; not route/URL pilot |
| `Snep_Services` `/snep/modules/default/api/` | D hardcoded | External service URL; needs product decision |
| `contacts/addedit.phtml` `/snep/includes/cidades.php` | D/E | Not exercised by this task |
| `notifications.js` `/snep/images/...` | D | Cosmetic |
| `login.phtml` `$this->baseUrl()/index.php/...` | A valid | View helper strips script; keep |
| `Snep_Modules` menu `$path.web/index.php/...` | A valid | Bootstrap before Front Controller |
| `Snep_Notifications::getNotifications($url."/index.php/...")` | E risk | Appears unused; defer |
| Broad `$this->view->url = getBaseUrl()/controller` in other controllers | E risk | Same pattern as pre-fix routes; selective follow-up |

## Validation

| Gate | Result |
|---|---|
| `make global-url-basepath-smoke` | **PASS** (17/17) |
| `make recording-report-url-smoke` | **PASS** (18/18) |
| `make queue-management-php8-smoke` | **PASS** (22/22) |
| `make lint` | **PASS** |
| `make regression` #1 | **FAIL** — sole suite: `doctor-smoke` (Release artifact identity DRIFT vs immutable RC / local `:dev`) |
| `make regression` #2 | **FAIL** — same sole fail; `global-url-basepath-smoke` + `recording-report-url-smoke` PASS both runs |
| `git diff --check` | **PASS** |

**Constraint:** Do not mutate immutable RC manifests / images to green doctor.
All other regression suites PASS on two consecutive runs.

## Files

- `snep/lib/Snep/Url.php` (new)
- `snep/lib/Snep/Manutencao.php`
- `snep/lib/Snep/Menu.php`
- `snep/modules/default/controllers/RouteController.php`
- `snep/modules/default/views/scripts/route/index.phtml`
- `snep/includes/javascript/agi_rules.js`
- `snep/includes/javascript/snep-env.js.php`
- `scripts/global-url-basepath-smoke-test.sh`
- `scripts/regression.sh`
- `Makefile`
- `docs/tasks/0034i-r7-global-url-basepath-hardening.md`
