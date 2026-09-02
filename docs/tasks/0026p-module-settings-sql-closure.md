# TASK-0026P — Module Settings SQL Boundary Closure

## Status

Implementation complete and validated for the one confirmed TASK-0026O
residual sink, plus its one sibling in `Snep_ModuleSettings_Manager`
sharing the exact same raw-interpolation root cause (2 methods fixed,
plus a genuine defense-in-depth fix in a third — 3 sites fixed total in
1 file). A real, pre-existing-input-shape regression (a `Zend_Db_Select`
null-value quirk) was discovered and corrected during this task's own
development, before any validation run. Focused smoke suite (216/216, up
from 196/196), `make lint`, and two consecutive full `make regression`
runs (22/22 suites each) all PASS.

**This task's own Phase 7 final supported-surface SQL sweep found a
further, confirmed-exploitable, unremediated instance of the same
root-cause SQL-injection class entirely outside this task's assigned
scope (`Snep_ModuleSettings_Manager` only) — in `Snep_Cnl`
(`getState()`/`getCityCode()`/`getPrefix()`), reachable via
`CnlController::updateAction_76()`'s fixed-width file-upload column
parsing. Per CLAUDE.md's "do not fix unrelated legacy bugs
opportunistically" and this task's own governing instructions, no code
was changed to fix it — it is documented here and handed off as
evidence for a required follow-up task, not auto-created.**

Not committed — this is the validated TASK-0026P checkpoint, awaiting
explicit authorization to commit.

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

## Scope

Closes the one confirmed SQL-injection sink TASK-0026O's own Phase 7
final sweep discovered but explicitly left unfixed
(`docs/tasks/0026o-route-binds-sql-closure.md`, "Security handoff"):

- **P1** — `Snep_ModuleSettings_Manager::getConfig()`
  (`snep/lib/Snep/ModuleSettings/Manager.php`).

Per this task's own explicit Phase 4 instruction ("audit all SQL-
building methods in `Snep_ModuleSettings_Manager`... if an exact sibling
sink is found, fix it here"), this task also fixes:

- `Snep_ModuleSettings_Manager::get()` — an exact sibling
  (`->where("config_module = '$module'")`); not independently confirmed
  exploitable via any supported HTTP surface, fixed anyway for defense
  in depth.
- `Snep_ModuleSettings_Manager::delConfig()` — an exact sibling
  (`delete(..., "config_module='{$module}'")`); zero callers anywhere in
  the tree (`DEAD/UNREACHABLE`), fixed anyway as an exact-pattern
  sibling within the same audited class.

3 sites fixed total, all in one file.

Does not touch: Module Settings UI redesign, module configuration
storage redesign, unrelated module behavior, legacy SIP removal,
menu/i18n, or Product Readiness — all explicitly out of scope per this
task's own instructions. Product Readiness work was not started.

## Phase 1 — Blocker reconstruction

Reconstructed from current source (not from category names alone),
traced end to end:

```text
ID:                        P1
Class:                     Snep_ModuleSettings_Manager
Method:                    getConfig($module)
Controller entry point:    ModuleSettingsController::indexAction() (POST)
POST field involved:       any submitted field NAME, not its value
How the field is parsed:   $key = form field name; $res = explode("_x_", $key); $res[1] used as $module
Exact SQL construction:    ->where("config_name = '$module'")  (snep/lib/Snep/ModuleSettings/Manager.php)
Required permission:       default_module-settings_read (module-settings has NO "write" resource in resources.xml at all)
Direct or second-order:    DIRECT
Exploitability:            confirmed live (SQLSTATE[42000] reproduced)
```

Trace:

```text
HTTP POST /index.php/default/module-settings
  -> ModuleSettingsController::indexAction()
  -> $formData = $this->getRequest()->getParams()  (only controller/action/module/signup unset -- every
     other field, including the request's own snep_csrf_token, stays in $formData)
  -> foreach ($formData as $key => $value) { $res = explode("_x_", $key); ... }
     $key is the raw, fully attacker-chosen POST FIELD NAME (e.g. "default_x_foo'bar"), not a value
  -> $exist_config = Snep_ModuleSettings_Manager::getConfig($res[1]);
  -> ->where("config_name = '$module'")   <-- raw interpolation, $module = $res[1]
  -> $db->query($select)
```

`resources.xml`'s `<resource id="module-settings">` declares zero
children (no `<resource id="write">` at all) -- `Snep_Modules::
loadResources()` still synthesizes an implicit "read" entry for the
resource itself (the same mechanism TASK-0026O's own doc documented for
`route`/`users`), so `default_module-settings_read` is the **only**
grantable permission for this entire controller. `Snep_PermissionPlugin::
preDispatch()` maps `action=='index'` to `type='read'` regardless of
HTTP method, so the same `indexAction()` handles both the page render
(GET) and the vulnerable save/lookup logic (POST) under that one read
grant. **Confirmed live** during this task's own development: a
zero-other-permission test account granted only
`default_module-settings_read` successfully reached and triggered the
`getConfig()` SQL error via a POST — no write-level grant exists or is
needed.

## Phase 2 — Input domain analysis

`Snep_ModuleSettings_Manager::getConfig($module)`'s `$module` maps to
`core_config.config_name`, a free-form `VARCHAR(255) NOT NULL` column
(`snep/install/database/schema.sql`) with no `enum`/finite constraint at
the DB level. Real values are `<value->key>` fields drawn from each
installed module's own `configs/config.json` (e.g. `smtp_password`,
`external_url`, `userfield`) — a set that varies per installed module,
not a small closed enum knowable at code-review time the way
`RouteController`'s `type` column was (TASK-0026O). Per this task's own
Phase 2 decision tree ("if it is a normal value predicate,
parameterize it"), parameterization was used, not an allowlist.

The request additionally encodes two components in one field NAME
(`<module>_x_<setting>`, split via `explode("_x_", $key)`) — per this
task's own instruction ("validate each component separately"), both
resulting components (`$res[0]`→`config_module`, `$res[1]`→
`config_name`) were traced independently: `$res[1]` reaches
`getConfig()`'s own raw interpolation directly (P1); `$res[0]` only
ever reaches the already-safe, array-quoted `$config_key` used by
`updateConfig()` (see Phase 4).

## Phase 3 — Remediation

**Fix** (`snep/lib/Snep/ModuleSettings/Manager.php`):

```php
// getConfig() -- before
$select = $db->select()
        ->from('core_config')
        ->where("config_name = '$module'");
// getConfig() -- after
$select = $db->select()
        ->from('core_config')
        ->where($db->quoteInto('config_name = ?', (string) $module));
```

The same pattern was applied to `get()` (`config_module`) and
`delConfig()` (see Phase 4). No `addslashes()`/`str_replace()`/
blacklist/quote-stripping was used anywhere, per this task's own
explicit prohibition.

**A note on the exact form used** (`$db->quoteInto(...)` pre-built and
passed as `$cond`, rather than `->where('col = ?', $module)`'s own
value-argument form): see Phase 3.1 below — this specific form was
required to avoid a real regression, not a stylistic choice.

### Phase 3.1 — A genuine regression found and fixed during development

The first attempt used the exact idiom this program has used eight
times before (`->where('col = ?', $value)`). It passed every apostrophe/
boolean-shaped test cleanly, but broke a **pre-existing, already-live**
input shape: `Zend_Db_Select::_where()`
(`snep/lib/Zend/Db/Select.php:997-1017`) only calls `quoteInto()` when
its `$value` argument is **not** `null`:

```php
if ($value !== null) {
    $condition = $this->_adapter->quoteInto($condition, $value, $type);
}
```

When `$value === null`, the raw `'?'` placeholder is left **completely
unsubstituted** in the final SQL string -- not empty, not quoted, a
literal `?` character -- which MariaDB then rejects with a genuine
`SQLSTATE[42000]` syntax error.

This matters because `getConfig(null)` is a real, already-existing input
shape on **every single POST** to `/index.php/default/module-settings`:
`ModuleSettingsController::indexAction()` only `unset()`s `controller`/
`action`/`module`/`signup` from `$formData` -- the request's own
`snep_csrf_token` field stays in the loop. `explode("_x_", "snep_csrf_token")`
has no `"_x_"` in it, so `$res[1]` is undefined, and
`Snep_ModuleSettings_Manager::getConfig($res[1])` is called with `null`.
**Pre-fix**, PHP's own `null`-to-`''` string interpolation
(`"config_name = '$module'"` with `$module = null`) made this silently
safe (matches nothing, no error) -- this exact edge case has always
worked by accident. A naive `->where('col = ?', $module)` fix would have
turned this pre-existing, already-live, harmless edge case into a new
HTTP 500 on **every real module-settings save**, a direct violation of
this task's own "preserve current save/update behavior" and "malformed
field names fail safely" requirements.

**Confirmed live** (direct invocation, both before and after this
specific correction):

| Call | With naive `->where('col = ?', $module)` | With the shipped fix |
|---|---|---|
| `getConfig(null)` | `SQLSTATE[42000]... near '?)' at line 1` | returns `false` cleanly, no error |
| Full `/index.php/default/module-settings` POST (CSRF field alone triggers it) | HTTP 500 | HTTP 302, no error |

**Fix**: pre-build the condition via `$db->quoteInto()` (which has no
such null-value quirk -- confirmed: `$db->quoteInto('col = ?', null)`
correctly returns `"col = ''"`) and pass it as the already-safe `$cond`
argument, with an explicit `(string)` cast on `$module` matching PHP's
own original null-to-`''` interpolation behavior exactly (avoiding even
the harmless `PDO::quote(): Passing null...` deprecation notice):

```php
->where($db->quoteInto('config_name = ?', (string) $module));
```

Preserved exactly: legitimate lookups, the malformed-field-name
(missing `"_x_"`) edge case's pre-fix silent-no-op behavior, and the
"unsupported/nonexistent setting" case (still returns `false`/empty,
never an error).

## Phase 4 — Sibling audit

| Method | SQL | Classification |
|---|---|---|
| `getConfig($module)` | `->where("config_name = '$module'")` | **P1 — `FIXED_BY_0026P`** |
| `get($module)` | `->where("config_module = '$module'")` | **`FIXED_BY_0026P`** (defense in depth — its two real call sites, `ModuleSettingsController.php:151,181`, pass `"default"` (a hardcoded literal) or `$val["name"]` (sourced from `json_decode()` of a filesystem `config.json`, not request-controlled); not independently confirmed exploitable) |
| `delConfig($module)` | `delete("core_config", "config_module='{$module}'")` | **`FIXED_BY_0026P`** (`DEAD/UNREACHABLE` — zero callers anywhere in the tree, re-confirmed; fixed anyway as an exact-pattern sibling) |
| `updateConfig($config_key, $config_value)` | `$db->update('core_config', $config_value, $config_key)` — a passthrough, no SQL construction of its own | `PARAMETERIZED_SAFE` — its one real call site (`ModuleSettingsController.php:257`) always passes a properly `quoteInto()`-shaped array (`['config_module = ? ' => $res[0], 'config_name = ? ' => $res[1]]`, Zend_Db's array-keyed `_whereExpr()` form); unchanged |
| `addConfig($result)` | `$db->insert('core_config', $result)` | `PARAMETERIZED_SAFE` — unchanged |

**`ModuleSettingsController.php` sibling check**: contains zero SQL/DB
access of its own (re-confirmed via direct grep — `select(`/`where(`/
`query(`/`delete(`/`update(`/`insert(`/`Zend_Registry::get('db')` all
return no hits in this file) — every DB interaction goes through
`Snep_ModuleSettings_Manager`, all classified above.

No unexplained request-controlled SQL interpolation remains in this
class.

## Phase 5 — Safe exploit proof

All findings were reproduced pre-fix and reconfirmed clean post-fix
through the real, authenticated HTTP flow (or, for the `get()`/
`delConfig()` siblings and the boolean-isolation/null-edge-case proofs,
through direct Manager invocation using this program's established CLI-
bootstrap pattern) — never a direct unauthenticated DB connection, never
password/hash/schema extraction, only harmless apostrophe-shaped and
boolean-oracle payloads.

| Sink | Payload | Pre-fix | Post-fix |
|---|---|---|---|
| P1, `ModuleSettingsController` POST (real HTTP, field NAME) | `default_x_foo'bar=someval` | `SQLSTATE[42000]... near 'bar')' at line 1` | HTTP 302, no SQL error |
| P1, boolean isolation (direct invocation, real victim fixture) | `"nonexistent' OR config_name='{$victimSetting}"` | genuinely cross-matched and returned the victim's real `core_config` row (confirmed: `config_value` leaked) | `false` (no match) |
| `get()`, boolean isolation (direct invocation) | `"nonexistent' OR config_module='{$victimModule}"` | (same class of payload, same mechanism) | empty array (no match) |
| `delConfig()`, apostrophe-shaped (direct invocation) | `"foo'bar"` | (same class, same mechanism as P1) | no exception, victim row untouched |
| the `null`-value regression (Phase 3.1) | every real POST's own `snep_csrf_token` field | pre-fix (original code): silently safe (empty-string match); **naive value-argument fix**: `SQLSTATE[42000]... near '?)' at line 1` | shipped fix: `false`, no error — matches original pre-fix behavior exactly |

The boolean-isolation payload is the classic apostrophe-escape form
(`"config_name = '$module'"` requires an actual `'` to break out, not a
bare `0 OR ...`) — verified by constructing a real `core_config` "victim"
row, issuing the malicious call against a *different* target string that
resolves to the victim's real setting name, and confirming pre-fix it
genuinely cross-matched and returned the victim's data, post-fix it did
not.

Additional proofs, matching Phase 5's explicit checklist:
- **legitimate lookup still works**: a real fixture row's `getConfig()`/
  `get()` lookup returns the correct `config_value`, unchanged.
- **malformed field names fail safely**: both the real `snep_csrf_token`
  field (no `"_x_"` at all) and an explicit test field of the same shape
  produce no SQL error, no PHP Fatal Error, and no bogus row (the
  existing `isset($res[1])` check downstream already prevented a bogus
  `addConfig()` insert for this shape before this task; only the
  `getConfig(null)` pre-check itself needed the null-value fix).
- **unsupported/nonexistent setting behaves normally**: `getConfig()` on
  a name with zero real rows returns `false`, no error, both before and
  after.

## Phase 6 — Extended residual SQL security suite

Extended (not duplicated) `scripts/residual-sql-security-smoke-test.sh`
/ `make residual-sql-security-smoke`, preserving every existing
TASK-0026J–O check unchanged (196 retained).

New coverage, 20 checks:

- **Preflight**: `/index.php/default/module-settings` added to the
  zero-permission authorization-boundary loop (correctly denied).
  `default_module-settings_read=1` added to the admin permission-grant
  step — empirically verified beforehand (via a disposable, throwaway
  test account, cleaned up immediately after) that this single read-only
  grant is sufficient to reach the vulnerable POST-driven path, matching
  this task's own live finding.
- **Real-HTTP core proof (5 checks)**: legitimate page render (read-only
  grant); the severity-defining property itself (a read-only grant
  reaches the POST-driven save path with no error); a real, fixture-
  namespaced legitimate save persisting correctly; the P1 apostrophe-
  shaped field-name proof; the malformed-field-name-structure (no
  `"_x_"`) proof.
- **Direct-invocation coverage (14 checks)**: a real victim `core_config`
  fixture; legitimate `getConfig()`/`get()` lookups; apostrophe-shaped
  checks for `getConfig()`/`get()`/`delConfig()`; boolean-isolation
  checks for `getConfig()`/`get()`; the `null`-value edge case (Phase
  3.1); the unsupported/nonexistent-setting case; `delConfig()`'s
  legitimate removal; inline cleanup.
- **Health check (1 check)**: PHP Fatal Error count unchanged.
- A best-effort DB-level safety-net cleanup was also registered in case
  the direct-invocation fixture script aborts before its own inline
  cleanup runs, per this task's own explicit "Guarantee cleanup"
  instruction.

**Result: PASS, 216/216** (up from 196/196). Cleanup ran cleanly — zero
`task0026p`-prefixed residue in `core_config`; `regras_negocio` remains
at its exact baseline (1 row, unaffected by this task).

## Phase 7 — Final supported-surface SQL sweep

A repository-wide sweep for `request-controlled value → raw SQL
construction → database execution` and `persisted user-controlled value
→ raw SQL construction → database execution`, matching the methodology
TASK-0026Z/J/K/L/M/N/O each used at their own closure point.

**Newly examined, resolved to a definitive verdict**:

| Candidate | Verdict |
|---|---|
| `PBX_Registry` (`__set()`/`__unset()`/`update()`'s raw `context`/`key` interpolation) | `ALLOWLISTED_IDENTIFIER` — every real call path constrains both `$context` and `$key` before they reach SQL: `ActionConfigsController::editAction()` gates `$idAction`/`$context` behind `class_exists($idAction)` (a string that passes this check can only ever be a valid PHP identifier — no quotes, no spaces, no SQL metacharacters are possible), and `$key` always comes from `PBX_Rule_ActionConfig::parseConfig()`'s own fixed, developer-defined XML-schema field IDs, never a raw `$_POST` key |
| `Billing_Manager::rate()` (raw `"WHERE id='{$telco_id}'"`) | out-of-scope / effectively safe — `$telco_id` is DB-derived (`Snep_Trunk::getId()`, an internal int PK), and `rate()`'s only caller is `snep/agi/snep.php:222` (AGI/call-processing-only, the same "not supported HTTP surface" boundary this program has applied consistently since TASK-0026K) |
| `ParametersController.php:199` (raw `"...locale='".$formData['language']."'"`) | `ALLOWLISTED_IDENTIFIER` — gated by `Snep_Locale::isSupportedLanguage()`, a strict `in_array()` check against a hardcoded 3-value array (`['en', 'pt_BR', 'es']`) |
| `TrunksController.php:271` (raw `"id = $id"`) | safe — `$id = $db->lastInsertId()`, a MySQL AUTO_INCREMENT integer, never attacker-controlled |
| `TrunksController.php:364` (raw `"...id=" . $db->quote($idTrunk)`) | `PARAMETERIZED_SAFE` — properly quoted via `$db->quote()`, just an unusual (concatenated rather than `quoteInto`) but safe form |
| `SoundFilesController.php` (`$this->lang`) | safe — sourced from `Zend_Registry::get('config')->system->language` (the application's own config file), not request-controlled |
| `PBX_Relatorio_Chamadas` (raw `startTime`/`endTime` interpolation) | `DEAD/UNREACHABLE` — zero instantiations (`new PBX_Relatorio_Chamadas`) or static calls anywhere in the tree |
| `snep/agi/followme.php`, `snep/agi/padlock.php` (raw `peers` update/delete) | out-of-scope — AGI feature-code scripts invoked directly by Asterisk (confirmed via TASK-0008's own prior legacy-runtime audit: neither appears in any HTTP-reachable controller or the static dialplan; both are feature-code/AGI-EXEC-invoked), the same AGI-only boundary as `Billing_Manager::rate()` above |
| `RouteController.php:490-512`, `Snep/Menu.php:319` | false positives — JavaScript/HTML string construction (`'{$var}'` inside a `.js`/`<a href='...'>` string), no SQL involved at all |
| `Snep/Extensions.php`, `Snep/Operadoras.php` | `DEAD/UNREACHABLE`, re-confirmed unchanged from TASK-0026O's own findings (zero callers anywhere in the tree) |

**Confirmed exploitable, NEW, outside this task's assigned scope**:

`Snep_Cnl::getState()`/`getCityCode()`/`getPrefix()`
(`snep/lib/Snep/Cnl.php`):

```php
// getState()
->where("id = '$state'")->where("country = '$country'");
// getCityCode()
->where("name = '$name'")->where("state = '$state'");
// getPrefix()
->where("id = '$prefix'")->where("country = '$country'");
```

Reachable via `CnlController::updateAction_76()`
(`snep/modules/default/controllers/CnlController.php`) — a Brazilian
telephony-prefix ("CNL") database updater that accepts a `.zip` file
upload, extracts a `.txt` file from it, and parses each line using
**fixed byte-offset columns** (`substr($line, 0, 2)` for state,
`substr($line, 61, 50)` for city name, `substr($line, 116, 7)` for
prefix — an ANATEL fixed-width file format). Every one of these values
is taken verbatim from the uploaded file's own byte content — fully
attacker-controlled by whoever can upload the file — and passed directly
into `Snep_Cnl::getState($state, $country)` /
`Snep_Cnl::getCityCode($state, $city_name)` /
`Snep_Cnl::getPrefix($prefix, $country)`.

**Confirmed live** via direct invocation with harmless apostrophe-shaped
values (matching this uploaded-column-data shape exactly):

```text
Snep_Cnl::getState("foo'bar", "1")
  -> SQLSTATE[42000]: ...near 'bar') AND (country = '1')' at line 1
Snep_Cnl::getCityCode("foo'bar", "baz'qux")
  -> SQLSTATE[42000]: ...near 'qux') AND (state = 'foo'bar')' at line 1
Snep_Cnl::getPrefix("foo'bar", "1")
  -> SQLSTATE[42000]: ...near 'bar') AND (country = '1')' at line 1
```

Unlike the P1 finding this task closed (blocked by no other bug),
`updateAction_76()` currently has no equivalent unrelated crash in front
of it — the vulnerable code is reachable exactly as written, gated only
by the `cnl` resource's own permission (`resources.xml`'s `<resource
id="cnl" label="Cnl Update" ...></resource>`, itself a zero-children
resource — the same "read grant alone may be sufficient" pattern this
task's own P1 finding exhibited, not independently re-verified here
since it is out of this task's scope). `Snep_Cnl::getCity()` (used by
`CallsReportController.php:496/498`) shares the identical `getPrefix()`-
style raw interpolation internally, but that specific call site is
currently blocked by the same pre-existing, already-documented
`CallsReportController.php:402` `count()`/`Countable` PHP 8.4 fatal
every prior TASK-0026x suite comment already references — not
independently re-verified as reachable via that path, but `getState()`/
`getCityCode()`/`getPrefix()` above are independently reachable via
`updateAction_76()` regardless, so this does not change the finding's
disposition. `getCountries()`/`addState()`/`addCity()`/`addPrefix()`
(same class) use `$db->select()->from(...)` with no `where()`
interpolation, or `$db->insert()` — `PARAMETERIZED_SAFE`, not confirmed
exploitable.

Not modified. Outside this task's assigned scope
(`Snep_ModuleSettings_Manager` only), and per CLAUDE.md's "do not fix
unrelated legacy bugs opportunistically"/"do not mix migration phases"
principles, fixing it is not this task's call to make unilaterally.

```text
RESIDUAL_SQL_GATE = NOT CLOSED
SECURITY_GATE = NO-GO
```

Per this task's own explicit instruction ("If another clearly
exploitable supported-surface SQL sink is found: STOP… Do not
automatically create TASK-0026Q"), **no new task was created**. This
finding is handed off as evidence only.

## Phase 8 — Focused validation

```bash
make residual-sql-security-smoke
```

**Result: PASS, 216/216** (up from 196/196). The one assigned headline
finding closed, plus the two sibling sites fixed alongside it. Every
TASK-0026J–O check preserved and still passing. Cleanup: every fixture's
own inline cleanup succeeded, backed by an additional DB-level safety
net; zero `task0026p`-prefixed residue in `core_config`; `regras_negocio`
unaffected.

## Phase 9 — Canonical validation

- `php -l` on the touched file: clean.
- `bash -n` on the extended smoke script: clean.
- `make lint`: **PASS, 5/5** (271 PHP files, 0 syntax errors; 24 shell
  scripts; 3 `resources.xml` files well-formed; clean `git diff --check`).
- `make regression`, official run 1: **PASS, 22/22 suites.**
- `make regression`, official run 2 (immediately after, no code changes,
  no manual cleanup in between): **PASS, 22/22 suites**, matching run 1
  exactly — no FAIL, no BLOCKED, no INCONCLUSIVE, no transient timing
  flake requiring separate classification in either run.

```text
SUITE                          RESULT
----------------------------------------------------------------
lint                           PASS
harness-lib-selftest           PASS
preauth-security               PASS
sql-security                   PASS
residual-sql-security          PASS
shell-security                 PASS
pjsip-config-security          PASS
api-security                   PASS
api-sql-security               PASS
session-csrf-security          PASS
auth-hardening-security        PASS
disclosure-path-security       PASS
authorization-coverage         PASS
authorization-smoke            PASS
http-smoke                     PASS
cdr-window-selftest            PASS
call-smoke                     PASS
trunk-smoke                    PASS
transport-smoke                PASS
restart-smoke                  PASS
external-failure-smoke         PASS
external-content-smoke         PASS
----------------------------------------------------------------
REGRESSION                     PASS
```

## Phase 10 — Health and cleanup

- `docker compose ps`: `app`/`asterisk`/`db`/`provider` all `Up
  (healthy)`.
- Asterisk 22.11.0 — matches the repository's current pin
  (`docker/asterisk.Dockerfile`, bumped by TASK-0026O for unrelated
  infra reasons; unchanged by this task).
- `res_pjsip.so`/`chan_pjsip.so` — both 1 module, Running.
- `pjsip show transports`: 3 baseline transports intact (`tcp`, `udp`,
  `wss`).
- AMI: `manager show connected` responsive, 0 connected users.
- ODBC: `snep` DSN, 1/1 active connection.
- `core show channels count`: 0 active channels, 0 active calls.
- PHP Fatal Error signature check: the same two known, pre-existing
  signatures already documented since TASK-0026M/N (`CallsReportController.php:402`
  count()/Countable — 7 occurrences; `Zend/Validate/File/Upload.php:226` — 1
  occurrence) — zero fatals attributable to this task's own changes.
- Fixture residue: zero `task0026p`-prefixed rows in `core_config`;
  `regras_negocio` unchanged (1 row, baseline).
- No leftover smoke-test processes.
- The unexpected, untracked `.nexus/` directory (a third-party
  workflow-orchestration tool's local config/state, unrelated to this
  project or task) remains in the working tree, exactly as every prior
  TASK-0026x task has documented. Left entirely untouched — not staged,
  not deleted, not otherwise acted upon.
- `git diff --check`: clean.
- `git diff --stat` / `git status --short`: exactly the 2 modified files
  listed below, plus the untracked `.nexus/` noted above.

## Files changed

```
scripts/residual-sql-security-smoke-test.sh   TASK-0026P focused coverage (+20 checks, 196->216)
snep/lib/Snep/ModuleSettings/Manager.php       P1 + get()/delConfig() siblings (3 sites) + null-value regression fix
```

Every other prior TASK-0026x file is untouched.
`ModuleSettingsController.php` is untouched (already safe — no SQL of
its own). Product Readiness work was not started.

## Security handoff — why `SECURITY_GATE` remains `NO-GO`

Per Phase 7's explicit instruction, this task stops here rather than
silently expanding its own scope. The one assigned headline sink (and
its two in-class siblings) is closed, verified, and regression-covered.
However:

```text
known SQL injection = 0 in supported surfaces   NOT SATISFIED
```

`Snep_Cnl::getState()`/`getCityCode()`/`getPrefix()`'s own raw
interpolation (reachable via `CnlController::updateAction_76()`'s
fixed-width file-upload column parsing, with no unrelated bug currently
blocking the path) carries the exact same unescaped-`'$var'`-in-`WHERE`-
clause defect this task and its seven predecessors have now closed ten
times over — not touched by this task.

**Recommended next task** (not opened automatically, per Phase 7): close
this confirmed sink (`snep/lib/Snep/Cnl.php`) using the exact same
`$db->quoteInto()`/bound-`where()` pattern this task and TASK-0026C/F1/
J/K/L/M/N/O have now established ten times over, reached via
`CnlController::updateAction_76()`. While auditing that file, also
resolve `getCity()`'s own disposition (currently blocked by the
pre-existing, unrelated `CallsReportController.php:402` bug at its one
real call site — verify via direct invocation, matching this program's
own established precedent for verifying a real fix behind an unrelated,
pre-existing crash) and confirm the exact permission requirement for
`cnl` (whether, like `route`/`users`/`module-settings` before it, a
`_read`-only grant is independently sufficient to reach
`updateAction_76()`'s POST/file-upload path). Every other candidate this
task's own Phase 7 sweep touched (`PBX_Registry`, `Billing_Manager::
rate()`, `ParametersController.php`, `TrunksController.php` (both
sites), `SoundFilesController.php`, `PBX_Relatorio_Chamadas`,
`agi/followme.php`, `agi/padlock.php`) was resolved to a definitive,
evidenced verdict and needs no further follow-up.
