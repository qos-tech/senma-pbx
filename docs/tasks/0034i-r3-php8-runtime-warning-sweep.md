# TASK-0034I-R3 — PHP 8 Runtime Warning Sweep / UI Runtime Hardening

**Status:** `PHP8_RUNTIME_WARNING_SWEEP_PASS_WITH_CONSTRAINTS` (local checkpoint)
**Depends on:** TASK-0034I-R1, TASK-0034I-R2, v0.1.0-rc.13 pilot navigation
**Does not:** mutate `v0.1.0-rc.13`, deploy, create `v0.1.0-rc.14`, reopen E7,
repository-wide PHP 8 modernization

## Pilot evidence (TEXTE-PBX-001 / v0.1.0-rc.13)

R1 remained **PASS** (no `127.0.0.1:80` / `Zend_Http_Client` / raw stack).

R2 remained **PASS** (`cloud_noticed`, register `false`, Asterisk version index).

Broader UI navigation then exposed three additional PHP 8 warning families:

| Family | Location | Warning |
|---|---|---|
| A | `systemstatus/index.phtml` ~413 | Undefined array key `"apt"` |
| B | `CallsReportController.php` ~81 | Undefined array key `"admin"`; offset on null |
| C | `Zend/View/Helper/HeadLink.php` ~393 | `compact(): Undefined variable $extras` |

Family A appears on many screens because `geral.js` loads
`/index.php/systemstatus/` into the global `#statusbar` asynchronously.

## A — apt / SNEP Version widget

### Original purpose

The orphaned block titled "SNEP Version" echoed `$this->indexData["apt"]`
in brackets. In legacy SNEP installs this likely reflected Debian package /
apt package version status for the product.

### Current producer search

- Only consumer: `index.phtml` (pre-fix).
- `SystemstatusController` assigns `$this->view->indexData = $this->systemInfo`
  and populates `systemInfo['snep']` from `configs/snep_version` — **never**
  `apt`.
- No `apt` / `apt-get` producer in the controller path.
- Server Status already renders SNEP via `indexData['snep']`.

### Root cause

View consumer without producer. PHP 8 warns on undefined key. Calling
`apt`/`apt-get` on every statusbar fetch is unacceptable.

### Fix

Gate the legacy apt block with `!empty($this->indexData['apt'])` and escape
output. Absent/empty → omit block. Present → render (optional legacy). Do not
invoke package managers. SNEP version remains via `indexData['snep']`.

## B — CallsReport session / user

### getName contract

`Snep_Users_Manager::getName($name)` returns `$stmt->fetch()` on `users`
(`id`, `name`): associative array, or `false` when no row.

### Session contract

`$_SESSION[$user['name']]['period']` is written on successful report POST
(`getselect`). First access / new session legitimately lacks the key or the
per-user namespace.

### Root cause

Direct indexing of `$user['name']` and nested session keys without validating
`getName()` / session shape → undefined key + offset-on-null/false.

### Fix

`Snep_Reports::getSavedPeriod()` / `setSavedPeriod()`:

- invalid/missing user → null / no write (no fabricated username)
- missing session/period → null → existing default (`startDate`/`endDate` false)
- valid saved period preserved

**Out of scope (documented debt):** identical unsafe patterns remain in
`RankingReportController`, `ServicesReportController`, and
`AuditController` (`periodAudit`). Not expanded in R3.

## C — Zend HeadLink `$extras`

### Root cause

`createDataStylesheet()` / `createDataAlternate()` call
`compact(..., 'extras')` but only assign `$extras` when optional args include
an extras array. Common path (`setStylesheet($href)` only) leaves `$extras`
undefined → PHP 8 `compact()` warning on nearly every layout render.

### Compatibility analysis

Classic ZF1 + PHP 8 defect. This repo already carries targeted Zend PHP 8
patches (e.g. curly-brace offsets in `Zend_Json_*`). Same class of local
compat fix — not a ZF upgrade.

### Fix

Initialize `$extras = array()` before the optional-args branch in both
methods. Empty extras → same `<link>` HTML as historical omitted-key compact
behavior. No `@`, no global warning suppression.

## Authorization

CallsReport remains read-gated (`default_calls-report_read`). Period helpers
do not grant access, fabricate identities, or weaken CSRF/authz.

## Tests

`scripts/php8-runtime-warning-smoke-test.sh` (+ Makefile /
`scripts/regression.sh`):

- static guards for the three pilot forms
- apt absent/empty/present fixtures
- period valid / no-session / no-period / false / null / missing-name
- HeadLink no-extras / with-extras / alternate; warn_count=0
- live systemstatus + calls-report + layout disclosure guards

### Gate note (residual-sql manager_check)

During canonical regression, `residual-sql-security` falsely failed two
`manager_check` assertions (`Simulator` trunk apostrophe /
`RouteController` `T:foo'bar`) with `fatal_delta=0` and clean
NotFound/BadArg outcomes. Root cause: `manager_check` grepped any
`SQLSTATE` in the last 4KB of `mag-error.log`, matching leftover
`SQLSTATE[22007]` data-type rejections from earlier apostrophe probes in
the same suite. The suite's own Q3 comments require **42000-class /
syntax-error** signatures only. Tightened
`manager_check` / `manager_check_get` accordingly (test harness only).

## Release / E7

- `v0.1.0-rc.13` immutable. Next candidate after merge: `v0.1.0-rc.14`
  (not created here).
- TASK-0035E7 remains paused. rc.12/rc.13 proofs for E10-R1, Fail2ban,
  release identity, R1 HTTP, R2 controller hardening remain valid.

## Decision

`PHP8_RUNTIME_WARNING_SWEEP_PASS_WITH_CONSTRAINTS`

Constraints:

- Not a repository-wide PHP 8 sweep.
- Sibling report controllers still carry the period pattern (debt).
- Pilot re-validation of R3 awaits next RC.
