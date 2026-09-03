# TASK-0002 — PHP 8.4 compatibility baseline

## Objective
Make the existing MAG/SNEP administrative interface navigable under PHP 8.4
without fatal errors, while preserving behavior. This is Phase 2
(PHP modernization) per `CLAUDE.md` — narrower than a full rewrite: the goal
is "doesn't fatal," not "fully correct" or "modernized."

## Scope
- Removed PHP APIs and syntax incompatibilities (`each()`, curly-brace
  string/array offsets, `create_function()`, PHP4-style constructors, etc.)
- Fatal `TypeError`/`Error`s caused by PHP 8.x behavior changes (e.g.
  internal functions now enforcing real-array/non-null arguments,
  non-static methods called statically)
- Runtime warnings only when they break HTTP responses, redirects, JSON, or
  otherwise change observable application behavior — cosmetic warnings that
  just print to `make logs` are left alone (as in TASK-0001)
- Minimal, targeted compatibility changes only

## Explicitly out of scope
- Architectural refactoring
- Frontend redesign
- PJSIP
- Asterisk modernization
- PostgreSQL
- Database schema redesign
- MAG filesystem rebranding (path.base stays `/var/www/html/snep` per
  TASK-0001)

## Method
1. Build a static inventory of PHP 8-incompatible patterns before editing
   anything (this document, "Inventory" section). **Inventory is not yet
   fully reviewed — do not begin a broad fix pass until it is.**
2. Classify `each()` and "non-static called statically" call sites by usage
   semantics, not by blind grep-and-replace — verify actual `$this` usage
   and every call site across the codebase before reclassifying a method as
   `static`.
3. Exercise real HTTP flows inside the running Docker environment
   (`make dev`), not just `php -l`/grep, for every flow in "Flows to
   validate."
4. Fix only what actually fatals or breaks a flow's expected HTTP behavior
   on the exercised code path. Latent issues in code paths not reached by
   the flows below are recorded, not fixed (matches TASK-0001's precedent).
5. Document every compatibility pattern encountered and its replacement in
   "Compatibility patterns and fixes."

## Flows to validate
For each, record: expected HTTP response/redirect, presence/absence of a
PHP Fatal Error, and whether output/headers were corrupted.
- login
- dashboard
- extensions
- trunks
- routes
- groups
- queues
- reports
- settings
- logout

---

## Inventory

Status: **complete — categories 1–12 below, from two static-analysis
passes.** No broad fix pass has started; the "23 safe" Manager-class list
and every other multi-file finding below is inventoried, not yet applied.
Three narrowly-scoped, individually-verified fixes were applied
opportunistically while first exercising the login flow (see "Fixes
applied so far" at the end of this document) — everything else described
below is inventory only, pending review before further edits.

### 1. `each()` — removed in PHP 8.0, fatal `Error` at the call site

**Correction to an earlier estimate:** TASK-0001 recorded "~130 latent
`each()` usages," based on `grep -l "each("`. That count is a **false
positive** — it matches the substring `each(` inside `foreach(`. The real
count of files with a genuine `each()` **function call** is **13**
(verified with a word-boundary regex plus manual exclusion of the
`foreach(` substring match). This correction is preserved here as the
authoritative count going forward.

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 18 call sites across 13 files | **FATAL** (`Error: Call to undefined function each()`) at the exact line when executed | 10 sites across 4 files, yes (see below) |

Representative call site (already-fixed pattern, `snep/lib/Zend/Cache/Core.php:146`, fixed in TASK-0001):
```php
while (list($name, $value) = each($options)) {
    $this->setOption($name, $value);
}
```
Safest migration: `foreach ($options as $name => $value) { ... }` — but
**only** after confirming no other code in the same scope calls
`reset()`/`next()`/`current()`/`key()`/`prev()` on the same array (which
would depend on `each()`'s side effect of advancing the internal pointer).

| File | Line(s) | Bucket | Reachable? |
|---|---|---|---|
| `snep/lib/Zend/Cache/Core.php` | 146 (constructor `each()`, fixed in TASK-0001) | SIMPLE_FOREACH | No — `Zend_Cache` unused by first-party code |
| `snep/lib/Zend/Cache/Backend.php` | 66, 83 (both fixed in TASK-0001) | SIMPLE_FOREACH | No |
| `snep/lib/Zend/Cache/Frontend/Class.php` | 110 | SIMPLE_FOREACH | No — dead subsystem |
| `snep/lib/Zend/Cache/Frontend/File.php` | 91 | SIMPLE_FOREACH | No — dead subsystem |
| `snep/lib/Zend/Cache/Frontend/Function.php` | 66 | SIMPLE_FOREACH | No — dead subsystem |
| `snep/lib/Zend/Cache/Frontend/Page.php` | 132 | SIMPLE_FOREACH | No — dead subsystem |
| `snep/lib/Zend/Config/Yaml.php` | 292 | **POINTER_DEPENDENT** — recursive-descent parser shares `&$lines` by reference across recursive calls; a `prev($lines)` a few lines later deliberately rewinds the pointer so a parent call's `each()` re-reads a line a child call "pushed back." **Not** safely `foreach`-convertible without an index-cursor rewrite. | No — `Zend_Config_Yaml` unused |
| `snep/lib/Zend/Http/UserAgent/Features/Adapter/TeraWurfl.php` | 91 | SIMPLE_FOREACH | No — device-detection adapter, unused |
| `snep/lib/Zend/Service/DeveloperGarden/Client/ClientAbstract.php` | 138 | SIMPLE_FOREACH | No — unused Deutsche Telekom API client |
| `snep/lib/Zend/XmlRpc/Value.php` | 489, 495 | **OBJECT_OR_UNCLEAR** — `each($xml)`/`each($namespaceXml)` on a `SimpleXMLElement` object, not a plain array; relies on SimpleXML's legacy array-pointer object handlers. Needs a manual (non-mechanical) rewrite if ever touched. | No — `Zend_XmlRpc` unused |
| `snep/modules/default/controllers/TdmLinksController.php` | 75, 257, 293 | SIMPLE_FOREACH — parses `explode("\n", ...)` output from Asterisk CLI commands, no pointer interleaving | **Yes — trunks/TDM link status pages** |
| `snep/modules/default/controllers/KhompLinksController.php` | 115, 276, 312 | SIMPLE_FOREACH, same pattern | **Yes — trunks/Khomp link status pages** |
| `snep/modules/default/controllers/ErrorsKhompController.php` | 80, 101 | SIMPLE_FOREACH, same pattern | **Yes — reports/errors pages** |
| `snep/modules/default/controllers/ErrorsTdmController.php` | 77, 102 | SIMPLE_FOREACH, same pattern | **Yes — reports/errors pages**. Same file also has a zero-argument `count()` call — see §7. |

Net: of 18 real call sites, all are mechanically safe `foreach` conversions
except the 2 flagged POINTER_DEPENDENT/OBJECT_OR_UNCLEAR — and neither of
those two is reachable from the web UI, so they can be left alone for this
task.

### 2. Curly-brace string/array offset syntax (`$var{expr}`) — PHP 8.0 **parse**-time fatal

A `require`/`include` of any file containing this syntax fatals immediately
on load, regardless of whether the specific line ever executes — the
highest-severity category by mechanism, though most hits below are in code
paths not loaded by the web UI.

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 44 sites across 18 files | **FATAL** (`Fatal error: syntax error`, at file-load time) | Likely yes for `Zend_Json_Decoder`/`Encoder` (7); no for the rest |

| File | Lines | Count | Note |
|---|---|---|---|
| `snep/lib/Asterisk/AGI.php` | 830,840,859,869,888,898,917,927,949,959,978,988,1007,1017,1035,1045,1133,1182(×2),1184,1360,1400,1435,1494,1527,1529,1531 | 27 | First-party, but loaded only by `snep/agi/*.php` (Asterisk-invoked CLI runtime) — a separate PHP execution context from the Apache web request path, not reachable by the flows in this task. Flagged for whichever future task first exercises AGI. |
| `snep/lib/Zend/Json/Decoder.php` | 555 | 1 | **Probably reachable** — JSON is commonly used by AJAX-driven admin screens (extensions/trunks/queues CRUD). Priority: confirm via Docker flow tests before deciding to fix. |
| `snep/lib/Zend/Json/Encoder.php` | 561,562,563,568,569,570,571 | 7 | Same as above — probably reachable, same file family. |
| `snep/lib/Zend/Barcode/Object/{Code25,Ean5,Ean8,Ean13,Identcode,ObjectAbstract,Upca,Upce}.php` | various | 11 across 8 files | Not used by first-party code — dead. |
| `snep/lib/Zend/Amf/Util/BinaryStream.php` | 143 | 1 | `Zend_Amf` unused — dead. |
| `snep/lib/Zend/Validate/Isbn.php` | 171,189,191 | 3 | Unused validator — dead. |
| `snep/lib/Zend/Filter/Compress/Zip.php` | 240 | 1 | Unused filter — dead. |
| `snep/lib/Zend/View/Helper/Navigation/Sitemap.php` | 256,259 | 2 | Unused view helper — dead. |
| `snep/lib/Zend/Wildfire/Plugin/FirePhp.php` | 740 | 1 | Debug-only plugin — dead in this deployment. |
| `snep/lib/Zend/Tool/Project/Context/Zf/ApplicationConfigFile.php` | 142 | 1 | `zf` CLI tooling, not part of the runtime app — dead. |

Likely false positive, excluded from the count above:
`snep/lib/Zend/Db/Statement.php:194` —
`preg_replace("/$q([^$q{$escapeChar}]*|($qe)*)*$q/s", ...)` — the
`{$escapeChar}` there is ordinary double-quoted-string interpolation
adjacent to a literal `$q{` from the regex text, not the removed offset
syntax.

Safest migration for a genuine hit: replace `$var{expr}` with `$var[expr]`
— semantically identical, PHP has supported `[]` for string/array offsets
since PHP 4; this is a pure syntax swap, zero behavior change.

### 3. `create_function()` — removed in PHP 8.0, runtime fatal

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 3 call sites across 2 files | **FATAL** (`Error: Call to undefined function create_function()`) | Unconfirmed for one file — see below |

| File | Line | Note |
|---|---|---|
| `snep/lib/Zend/Feed/Element.php` | 196 | `array_map(create_function(...), $nodes)` — dead, no first-party `Zend_Feed` usage found. |
| `snep/lib/linfo/lib/class.OS_Linux.php` | 1323, 1335 | System-info gathering library (`linfo`). `SystemstatusController.php` (a flow-adjacent page, part of "settings"/"reports" navigation) may invoke code that reaches this — **not yet confirmed either way; needs a Docker flow test on the systemstatus page specifically**, not assumed dead. |

Safest migration if reachable: replace with an equivalent closure
(`function($x) use (...) { ... }` or an arrow function) — `create_function()`
was always just a string-eval wrapper around an anonymous function.

### 4. Non-static methods called via `::` — the dominant finding, largest fatal surface in the codebase

This is a distinct category from `each()`/curly-braces: a PHP 8.0 behavior
change, not a removed API. Calling a non-static method using `::` syntax
without an object context was a **deprecation notice, silently tolerated,
since PHP 5** — it is a **fatal `Error`** ("Non-static method X::y() cannot
be called statically") since PHP 8.0. This is why it wasn't caught by
`php -l`/syntax linting in TASK-0001 — it's a well-formed parse, only a
runtime fatal on the exact line that executes it.

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| ~152 methods across 29 `Snep_*`/`PBX_*` classes, ~325 call sites (regex cross-reference; narrower "23 classes fully safe" subset below is verified) | **FATAL**, one call site at a time, as each is exercised | Yes — this is first-party CRUD/business logic, directly on the admin UI's critical path (confirmed: 3 fatals hit in a row just getting through the login flow) |

**Confirmed root cause, same shape every time:** a family of "Manager"
classes was authored to be used as a static utility namespace — an empty
no-op `__construct()`, zero `$this` usage anywhere in the class body, never
instantiated with `new` anywhere in the tree — but every method is
declared `public function` (instance) rather than `public static function`,
and every call site in the codebase already calls it via `::`.

**23 classes independently confirmed 100% safe for a blanket per-class fix**
(zero `$this` usage anywhere in the class, never `new`'d, every call site
uses `::`) — verified by whole-codebase grep, not assumed:

`Snep_Audit_Manager`, `Snep_Auth_Manager`, `Snep_Binds_Manager`, `Snep_Cnl`,
`Snep_Config` (abstract — cannot be instantiated at all, so `::` was always
the only possible usage), `Snep_ContactGroups_Manager` (one `new` site
exists at `RouteController.php:228`, but it only calls `->getAll()`, and
PHP explicitly permits calling a static method through an instance arrow —
still safe), `Snep_Contacts_Manager`, `Snep_CostCenter_Manager`,
`Snep_Dashboard_Manager`, `Snep_ExpressionAliases_Manager`,
`Snep_ExtensionsGroups_Manager`, `Snep_Extensions_Manager`,
`Snep_IpStatus_Manager`, `Snep_Notifications`, `Snep_PickupGroups_Manager`,
`Snep_Profiles_Manager`, `Snep_Queues_Manager`, `Snep_Register_Manager`,
`Snep_Reports`, `Snep_Trunks_Manager`, `Snep_Users_Manager`,
`Snep_ValidateExpression`, `Snep_Version`, `PBX_DatesAliases`.

Method counts per class (all non-static today, all called via `::`):
`Snep_Queues_Manager` (17), `Snep_Users_Manager` (14),
`Snep_Contacts_Manager` (14), `Snep_ExtensionsGroups_Manager` (11),
`Snep_Profiles_Manager` (11), `Snep_ContactGroups_Manager` (10),
`Snep_Notifications` (9), `Snep_Trunks_Manager` (9),
`Snep_Extensions_Manager` (7), `Snep_Dashboard_Manager` (7 methods; its
`getKey()` alone has 34 call sites), `PBX_DatesAliases` (7),
`Snep_Register_Manager` (7), `Snep_Binds_Manager` (6),
`Snep_CostCenter_Manager` (6), `Snep_PickupGroups_Manager` (5),
`Snep_Version` (3), `Snep_IpStatus_Manager` (3),
`Snep_ExpressionAliases_Manager` (4), `Snep_Config` (2 — `getConfiguration()`
alone has 7 call sites), `Snep_Reports` (2 — `fmt_date()` alone has 10 call
sites), `Snep_Cnl` / `Snep_Audit_Manager` / `Snep_Auth_Manager` /
`Snep_ValidateExpression` (1 each).

**5 classes need per-method treatment, not a blanket fix** — they mix
instance state (`$this`) with static-style methods, so only the
individually-verified-safe method should move, not the whole class:

| Class | `$this` uses elsewhere in class | Individually safe to make `static` | Call sites |
|---|---|---|---|
| `Snep_Locale` | 12 | `setExtensionsLanguage()` | 3 |
| `Snep_Request` | 2 | `send_request()` | 12 |
| `Snep_Manutencao` | 1 | `arquivoExiste()` | 1 |
| `PBX_Interfaces` | 1 | `getCodecs()` | 3 |
| `Snep_SoundFiles_Manager` | 36 | none confidently flagged — heavily stateful; hand-review every candidate before touching | — |

**Confidence caveat (from the analysis itself):** this is regex-based, not
a real PHP parser — it can misattribute when multiple classes share a
method name, or miss traits/interfaces. Treat the "23 safe" classification
as strong evidence, not proof; a quick `grep -c '$this'` re-check per file
immediately before editing costs nothing and catches drift.

Representative call site (already fixed, see "Fixes applied so far"):
```php
// modules/default/controllers/AuthController.php:81
$case = Snep_Acl::getCaseSensitive($username);
// lib/Snep/Acl.php:68 (before fix) — public function, no $this used, single call site
public function getCaseSensitive($username) { ... }
```
Safest migration: add `static` to the method declaration — zero behavior
change when `$this` is provably unused and the class is provably never
instantiated. **This task has verified 3 classes this way so far
(`Snep_Acl`, `Snep_Usuario::encrypt` only, `Snep_Auth_Manager` minus
`adduuid`); the other 26 classes above are inventoried, not yet fixed.**

### 5. PHP4-style constructors — not fatal, silently broken (highest-danger class of bug in this inventory)

Unlike every other category here, this one produces **no error at all**.
Under PHP 8, a method with the same name as its class (PHP 4's constructor
convention) is simply an ordinary method, not a constructor — `new X()`
silently succeeds without running it. Any state that method was supposed
to initialize is just... not initialized, and the failure surfaces later,
at whatever line first dereferences the missing state, often with a
confusing, distant error message.

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 1 confirmed class | **SILENT_BEHAVIOR_CHANGE**, then a **FATAL** one method-call later, at a distant, confusing call site | **Yes — directly on the trunks and extensions flows** |

**`snep/includes/AsteriskInfo.php:38`**:
```php
class AsteriskInfo {
    private static $asterisk;
    public function AsteriskInfo() {          // PHP4-style ctor: NOT __construct()
        self::$asterisk = PBX_Asterisk_AMI::getInstance();
        ...
    }
    public function status_asterisk($comando) {
        ...
        self::$asterisk->command($comando)     // fatals: "Call to a member function command() on null"
        ...
    }
}
```
`new AsteriskInfo()` is called from 14 sites, overlapping heavily with
flows this task must validate: `snep/includes/functions.php:162`,
`TdmLinksController.php:56,217`, `ErrorsKhompController.php:55,133`,
**`TrunksController.php:43,464`**, `KhompLinksController.php:55,236`,
`ErrorsTdmController.php:55,134`, **`ExtensionsController.php:44`**,
`IpStatusController.php:67`, `SystemstatusController.php:140`.

`status_asterisk()` is the class's *only other* method — every one of
those 14 call sites is presumably followed by a call to it, which is where
the fatal actually surfaces (not at construction time), which is exactly
the "distant, confusing" failure mode this bug class is known for.

No other PHP4-style constructors were found anywhere in `snep/` (every
`class X` was checked against a same-named, non-`__construct` method).

Safest migration: rename `AsteriskInfo()` to `__construct()` — a direct,
standard, behavior-restoring rename, zero logic change, restores exactly
the pre-PHP8 behavior.

### 6. Dynamic properties

Deprecated since PHP 8.2 (`E_DEPRECATED`, **not fatal**) unless a specific
downstream consequence is found. A broad sweep of `$obj->prop =`
assignments (255 raw hits) was narrowed to objects other than
`$this`/`$config`, then cross-checked against each class's declared
properties. Most raw hits are false positives — `Asterisk_AGI::$requestObj`
is declared, `Asterisk_AGI_Request` has `__set()`, `Zend_Mime_Part`
declares its dynamic-looking properties, `json_decode()` results are
`stdClass` (explicitly exempt from the deprecation), and `$this->view->x`
(the single most common shape in the codebase) is fine because
`Zend_View_Abstract` implements `__set()`/`__get()`/`__isset()`.

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 3 confirmed classes/property pairs (~16 sites); ~9 more lower-confidence candidates, not individually verified | **DEPRECATION_WARNING** — logged via `make logs`, does not fatal or break output | Yes — directly on trunks/extensions |

| Class | Property | Occurrences | Representative site | Migration |
|---|---|---|---|---|
| `Snep_Exten` (extends `Snep_Usuario`; neither declares these) | `followme`, `cancallforward` | 2 | `lib/Snep/Exten.php:257` — `$this->followme = $ramal;` (via `setFollowme()`) | Declare `protected $followme;` / `protected $cancallforward;` on the class |
| `PBX_Rule` | `dates` | 2 | `lib/PBX/Rule.php:417` — `$this->dates = array();` | Declare `protected $dates;` |
| `PBX_Asterisk_Interface` subclasses (`SIP`, `IAX2`, `VIRTUAL`, `KHOMP`, and their `NoAuth` variants — 6 files) | `config`, `tech` | ~12 | `lib/PBX/Asterisk/Interface/SIP.php` — `$this->config = ...; $this->tech = ...;` on a base class that declares neither | Declare `protected $config;` / `protected $tech;` on the abstract base `lib/PBX/Asterisk/Interface.php` |

Lower-confidence candidates (declared-property detection can miss
multi-name `var $a, $b;` declarations or properties inherited from
elsewhere) — not individually verified, listed for completeness:
`lib/Snep/Request.php::$log`, `lib/Snep/Log.php::$arquivo/$dst/$src/$status`,
`lib/PBX/Dialplan/Verbose.php::$execution_day/$foundRule`,
`lib/PBX/Rule/Action/DiscarRamal.php::$allow_voicemail`,
`lib/PBX/Rule/Action/CCustos.php::$config`,
`lib/PBX/Asterisk/AGI/Request.php::$channel/$origem`,
`lib/PBX/Asterisk/Log/Writer.php::$_formatter`,
`lib/Snep/SoundFiles/Manager.php::$base_dir/$lang`.

Since none of these fatal or break output, no fix is required for this
task's scope ("runtime warnings only when they break HTTP responses,
redirects, JSON, or normal application behavior") — recorded for a future
Phase-2 cleanup pass, not actioned here.

### 7. `count()`/`sizeof()` misuse

`count()` has required `array|Countable` since PHP 8.0 (was a non-fatal
warning returning `1` in PHP 7.2–7.4) — a genuine `TypeError` fatal.

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 1 zero-argument site (already known, §"Bonus findings") + 5 new `count($falsy)` sites | **FATAL** (`TypeError`) | 2 of 5 new sites: AGI action, not web UI. 3 of 5: billing module, reachable if billing reports render as part of "reports" |

New confirmed pattern: `count($var)` on a variable assigned straight from
a single-row `->fetch()` (not `->fetchAll()`) with no `false`-check —
`Zend_Db_Statement::fetch()` returns `false` on no matching row, and
`count(false)` is a fatal `TypeError`.

| File:line | Variable | Representative site | Reachable? |
|---|---|---|---|
| `modules/default/actions/DiscarTronco.php:270-272` | `$trunk` | `$trunk = $db->query($sql)->fetch(); if (count($trunk) > 1) {` | AGI action (outbound-dial billing) — not web UI |
| `modules/default/actions/DiscarTronco.php:297-299` | `$query_result` | same shape | AGI action — not web UI |
| `modules/billing/lib/Billing/Manager.php:118-120` | `$telco` | `$telco = $stmt->fetch(); if(count($telco) > 0){` | Billing module — reachable from "reports" if billing reports render |
| `modules/billing/lib/Billing/Manager.php:147-151` | `$telco` | same shape | Same |
| `modules/billing/lib/Billing/Manager.php:222-227` | `$telco` | same shape | Same |

Migration: `$x !== false && count($x) > N`, or `if ($x) { ... }` before
counting — minimal, preserves the original "0 rows found" behavior instead
of fatal-ing on it.

### 8. Object/array function misuse (`array_key_exists($x, $this)` shape)

Exhaustive search for the same shape as the already-fixed
`Zend_Registry::offsetExists()` bug (TASK-0001): every
`array_key_exists|in_array|array_search|array_keys|array_values|
array_merge|compact|extract|array_map|array_filter|array_walk` call across
first-party and vendored code, checked for a *bare* `$this` argument
(`$this->property` is completely normal and excluded).

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 0 additional instances found | **FATAL** where it occurs, but clean result | N/A |

Also specifically checked `count($this)` (4 vendored hits:
`Zend_EventManager_ResponseCollection`, `Zend_Http_CookieJar`,
`Zend_View_Helper_Placeholder_Container_Abstract`,
`Zend_Queue_Message_Iterator`) — all four classes implement `Countable` or
extend `SplStack`/`ArrayObject`, so `count($this)` there is valid PHP 8
usage, not a bug. **No action needed in this category beyond the fix
already applied in TASK-0001.**

### 9. Changed string/array offset behavior (access on `null`/`false`)

Mostly non-fatal on its own ("Trying to access array offset on value of
type bool/null" — a warning, PHP 8 just reworded it from PHP 7's
equivalent notice) — **but two confirmed sites sit directly on required
flows, and one of them explains an already-observed fatal.**

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 2 confirmed sites | **DEPRECATION_WARNING** directly, but one has a **downstream FATAL** consequence via §4 | **Yes — trunks and login** |

| File:line | Pattern | Flow | Consequence |
|---|---|---|---|
| `modules/default/controllers/TrunksController.php:306-307` | `$trunk = $db->query("select * from trunks where id='$idTrunk'")->fetch(); $trunk['qualify_value'] = "";` — writes to an array offset on a possibly-`false` value if `$idTrunk` doesn't match a row | **trunks** (edit-trunk action) | Non-fatal warning, silent no-op write, then `if ($trunk['trunktype'] == "I")` reads a warning-producing `null`. Pre-existing bug (invalid trunk ID) — PHP 8 only changes the warning text, doesn't newly fatal it. |
| `modules/default/controllers/AuthController.php:118` | `$registered = $db->query("SELECT uuid,registered_itc,noregister FROM itc_register")->fetch();` then `$_SESSION['uuid'] = $registered['uuid'];` etc. | **login** | **This is why `Snep_Auth_Manager::adduuid()` fatals on every login attempt in this dev environment, not as a rare edge case.** `itc_register` is empty in the current DB seed (TASK-0001's DB init chain doesn't populate it — no seed data ships for this table at all), so `$registered` is `false`, every `$registered[...]` access is a non-fatal warning returning `null`, `$_SESSION['uuid']` ends up `null`, `AuthController.php:124`'s `if(!isset($_SESSION['uuid']))` is therefore **always true** on this seed data, and `adduuid()` is hit on **every successful login**, deterministically — not conditionally. |

This directly changes the priority of finishing `adduuid()`: it is not an
edge case to defer, it is on the critical path of the login flow as
currently seeded. Migration if pursued: guard both sites with a
`false`-check before offset access, same shape as the §7 fix.

### 10. Argument-order/signature incompatibilities

**10a — optional parameter before a required one** (deprecated since
PHP 8.0, not fatal): three independent regex passes (single-line
signatures, `= <default>, $required)` adjacency, multi-line signatures)
across first-party code.

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 0 | N/A — clean result | N/A |

This codebase consistently writes required parameters first — a genuine
clean result, not a search gap (three independent pattern variants all
came back empty).

**10b — Iterator/ArrayAccess/Countable/IteratorAggregate signature
incompatibilities**: zero first-party classes implement any of these
interfaces — only vendored `lib/Zend/*` (68 files total). A full audit of
all 68 wasn't performed as disproportionate to likely reachability;
spot-checked the ones plausibly reachable from admin CRUD/list screens:
`Zend_Config` (already known — return-type-only mismatch, `E_DEPRECATED`,
not fatal, per TASK-0001), `Zend_Session_Namespace::getIterator()`,
`Zend_Paginator::count()`/`getIterator()`,
`Zend_Form::current()/key()/next()/rewind()/valid()/count()`. All have the
same shape as the known `Zend_Config` case — correct parameter counts,
only missing return-type hints.

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 0 genuine LSP-breaking mismatches found in the checked subset (8 classes of 68 vendored candidates) | N/A in checked subset | N/A |

A parameter-count/type mismatch (as opposed to a missing return type) would
very likely already have been fatal on PHP 7 too, so this is a
low-probability place to find something PHP-8-specific among the remaining
60 unchecked vendored files — not worth a full audit given this task's
"minimal changes, exercised flows only" scope.

### 11. Undefined constants used as bareword strings

Would be **FATAL** (`Error: Undefined constant "X"`, since PHP 8.0 — was a
non-fatal "assumed 'X'" warning in PHP 7) where found.

| Occurrences | PHP 8.4 impact | Reachable from web UI? |
|---|---|---|
| 0 confirmed hits after two search angles; one sub-case not confidently checked | N/A — clean result on checked sub-cases | N/A |

- Bareword array-subscript access (`$arr[identifier]`, no quotes): 15 raw
  regex hits, all false positives — either inside string literals
  (translation strings, config-file-syntax text) or inside `@param`
  docblocks. The two genuinely-code-looking hits
  (`lib/Snep/Dashboard/Manager.php:42,73`, `$_SESSION[id_user]`) are inside
  **double-quoted string interpolation**, where PHP's simple-interpolation
  syntax has always auto-quoted bareword array keys — unaffected by the
  PHP 8 change, which only applies to barewords used as real code tokens
  outside strings.
- Bareword array-literal keys (`array(identifier => ...)`, no quotes): 2
  raw hits, both inside `@param` docblock comments, not real code.
- Bareword *function arguments* (`func(IDENTIFIER)`): **not confidently
  checked** — would need cross-referencing every bareword token against
  every `define()`/`const`/class-constant in the codebase to avoid
  drowning in false positives from legitimate constants (`PHP_EOL`,
  `Zend_Mime::ENCODING_BASE64`-style class constants, etc.). A naive regex
  pass would produce exactly the noisy, low-precision list this task's
  method explicitly avoids. Reported honestly as unchecked rather than
  claimed clean.

### 12. Other removed-in-PHP8 functions (first-party code only)

Checked: `ereg(`, `eregi(`, `ereg_replace(`, `eregi_replace(`, `split(`,
`spliti(`, `session_register(`, `session_unregister(`,
`session_is_registered(`, `set_magic_quotes_runtime(`,
`get_magic_quotes_gpc(`, `get_magic_quotes_runtime(`, `mysql_connect(`,
`mysql_query(`, `mysql_fetch_array(`, `mysql_fetch_assoc(`, `mysql_error(`,
`mysql_num_rows(`, `(real)` cast, `(unset)` cast — across
`snep/modules`, `snep/lib/Snep`, `snep/lib/PBX`, `snep/lib/Asterisk`,
`snep/includes`, `snep/agi`, `snep/inspectors`.

**Zero hits.** Clean — no action needed for this category.

### Bonus findings (outside the requested categories, surfaced incidentally)

- **`snep/modules/default/controllers/ErrorsTdmController.php:90`** —
  `count()` called with **zero arguments**
  (`if($error_message && count())`). `ArgumentCountError` under PHP 8.0+
  (previously just warned and returned 1). Same file as one of the
  `each()` sites in §1.

---

## Proposed migration/fix order

**P0 complete** — see "P0 — completed and validated" above (`AsteriskInfo`,
`adduuid()`, plus 6 classes pulled forward as named exceptions because they
blocked P0 validation: `Snep_Config`, `Snep_Notifications`, `Snep_Request`,
`Snep_Dashboard_Manager`, `Snep_Register_Manager`,
`Snep_SoundFiles_Manager::getClasses()` only).

Remaining, for P1/P2, pending your go-ahead to begin:

1. **P1** — the remaining "23 safe" Manager-family classes not already
   fixed in P0 (§4): `Snep_Audit_Manager`, `Snep_Binds_Manager`, `Snep_Cnl`,
   `Snep_ContactGroups_Manager`, `Snep_Contacts_Manager`,
   `Snep_CostCenter_Manager`, `Snep_ExpressionAliases_Manager`,
   `Snep_ExtensionsGroups_Manager`, `Snep_Extensions_Manager` (done in P0),
   `Snep_IpStatus_Manager`, `Snep_PickupGroups_Manager`,
   `Snep_Profiles_Manager`, `Snep_Queues_Manager`, `Snep_Reports`,
   `Snep_Trunks_Manager`, `Snep_Users_Manager`, `Snep_ValidateExpression`,
   `Snep_Version`, `PBX_DatesAliases`. One class at a time, each with a
   fresh `grep -c '$this'` + whole-codebase call-site re-check immediately
   before editing, in the order the flow tests actually hit them
   (routes/groups/queues/reports/settings first, since those are the
   remaining required flows).
2. **P1** — the 10 reachable first-party `each()` sites in Khomp/TDM
   controllers (§1) — straightforward `foreach`.
3. **P2** — the 3 remaining per-method fixes in mixed classes (§4 table;
   `Snep_Request` and `Snep_SoundFiles_Manager::getClasses()` already done
   in P0) — `Snep_Locale::setExtensionsLanguage`,
   `Snep_Manutencao::arquivoExiste`, `PBX_Interfaces::getCodecs`. Each
   classified independently, same rigor as P0's mixed-class fixes.
4. **P2** — `Zend_Json_Decoder`/`Encoder` curly-brace offsets (§2) — only
   if a flow actually exercises JSON encoding/decoding; confirm via Docker
   flow tests before touching.
5. **P2** — the 3 `count($falsy)` fatals in `Billing/Manager.php` (§7) —
   only if "reports" actually renders billing data; confirm via flow test
   first. The 2 sites in `DiscarTronco.php` are AGI-only, out of reachable
   scope.
6. **P2** — everything else in §6–11 (dynamic properties, the
   `TrunksController` offset-on-false warning, etc.) — deprecation-level or
   non-fatal by this task's own scope rule; not planned unless a flow test
   shows an actual behavioral break.
7. Everything tagged dead/unreachable in every category — do not fix
   speculatively; only if a flow test actually reaches it.

## P0 — completed and validated

### Files changed

Pre-interrupt (verified before the inventory-first pause), all in
`Snep_Auth_Manager`'s peer classes on the login path:

| File | Pattern | Before → after |
|---|---|---|
| `snep/lib/Snep/Acl.php` | §4 non-static-called-statically | `getCaseSensitive()`: `public function` → `public static function`. Single call site (`AuthController.php:81`), zero `$this` in body. |
| `snep/lib/Snep/Usuario.php` | §4 | `encrypt()`: `public function` → `public static function`. Class is `abstract` (never instantiable); single call site; zero `$this`. `decrypt()` (same class, same shape) is dead code — never called anywhere — left untouched. |
| `snep/lib/Snep/Auth/Manager.php` | §4 | `getUser()`, `getPassword()`, `sendEmail()`, `addCode()`, `getUpdatePass()` → `static` (pre-interrupt). `adduuid()` → `static` (P0-1, below). |

**P0-1 — `adduuid()`/`itc_register` login-path failure:**

| File | Pattern | Before → after |
|---|---|---|
| `snep/lib/Snep/Auth/Manager.php` | §4 + a separate, non-PHP8 DB-strict-mode issue found immediately downstream | `adduuid($uuid)`: `public function` → `public static function` (same verified-safe shape as its 5 siblings — zero `$this`, 1 call site, never `new`'d). **Also**: its `$insert_data` array now explicitly includes `'client_key' => ''` and `'api_key' => ''`. Investigated first, per your instruction: `itc_register.client_key`/`api_key` are `NOT NULL` with no `DEFAULT`; MySQL 5.x's original non-strict `sql_mode` silently coerced the omitted columns to `''`, MariaDB 10.11's default `STRICT_TRANS_TABLES` rejects that outright. Confirmed via `Snep_Register_Manager::registerITC()` that these columns are legitimately meant to start empty and get filled in later, once real registration completes — `''` is the DB's own original implicit behavior, not an invented fallback. |

Before: `Snep_Auth_Manager::adduuid()` fataled with "Non-static method cannot be called statically" on every login (deterministic on this seed data — see §9). After fixing the static-call issue alone, it then fataled with a SQL error (`Field 'client_key' doesn't have a default value`) instead. After both fixes, it inserts cleanly.

**P0-2 — `AsteriskInfo` PHP4-style constructor:**

| File | Pattern | Before → after |
|---|---|---|
| `snep/includes/AsteriskInfo.php` | §5 PHP4-style constructor | `public function AsteriskInfo()` → `public function __construct()`. Searched first, per your instruction: zero explicit `->AsteriskInfo()` calls anywhere in the tree (confirmed it was never used as a normal method), so the rename has no other call site to break. |

Before: `new AsteriskInfo()` silently succeeded without initializing `self::$asterisk`; `status_asterisk()` then fataled with "Call to a member function `command()` on null" at whatever distant call site invoked it. After: the constructor actually runs, attempts the AMI connection, and — correctly, since this Docker topology deliberately has no Asterisk service (ADR-0001) — throws `Asterisk_Exception_CantConnect("Unable to connect to manager")`, which the app's own error handler catches and renders as a clean "Erro Interno" page. No PHP Fatal Error either way; the difference is a silent null-pointer crash at a distant, confusing call site vs. the exception the code was actually written to throw.

**Pulled forward from P1, as named exceptions** — each individually
verified (whole-class/whole-method `$this` check + whole-codebase call-site
grep) before being touched, not part of a bulk P1 pass. All were discovered
because they sit on the shared page layout or directly on a P0-required
flow, and P0 validation was impossible without them (confirmed with you at
each juncture rather than assumed):

| File | Pattern | What/why |
|---|---|---|
| `snep/lib/Snep/Config.php` | §4, "23 safe" list | `getConfiguration()`, `getAllConfiguration()` → `static`. Called from the shared `layout.phtml` — blocks every page, not one flow. |
| `snep/lib/Snep/Notifications.php` | §4, "23 safe" list | All 9 methods → `static`. `getNoView()` is called from the shared layout (notification bell). |
| `snep/lib/Snep/Request.php` | §4, mixed class — **individually verified per-method**, not blanket-fixed | `http_context()`, `send_request()`, `parseHeaders()` → `static`. `__construct()` left untouched (uses `$this->log`, but is dead code — the class is never `new`'d anywhere in the tree). `parseHeaders()` needed the same treatment because `send_request()` calls it via `self::`, and a static method has no `$this` context to fall back on. |
| `snep/lib/Snep/Dashboard/Manager.php` | §4, "23 safe" list | All 7 methods → `static`. `getModelos()`/`add()`/`getArray()` are the dashboard's actual rendering path. |
| `snep/lib/Snep/Register/Manager.php` | §4, not in the original 29-class inventory (a gap in the first static pass) | `getCountry()`, `getState()`, `getCity()`, `registerITC()`, `noregister()`, `get()`, `addDistributions()` → `static` (`removeDistributions()` was already static). On the login→dashboard registration-gate path. |
| `snep/lib/Snep/SoundFiles/Manager.php` | §4, mixed class (36 `$this` uses) — **individually verified, one method only** | `getClasses()` → `static`. Zero `$this` in this one method, every call site (3 internal `self::`, 3 external `::`) already static-syntax. No other method in this class touched. On the system-status flow's critical path. |

Also noted but **not** a fix, since it wasn't real code: `IndexController.php`'s reference to `Snep_ITCRegister::register(...)` is entirely inside a commented-out block — the class doesn't exist anywhere in the tree, but the call is unreachable. `Snep_Breadcrumb::renderPath()` was already declared `static` — no change needed.

### Validation performed

All via direct HTTP requests (curl, cookie-jar session) against
`make dev`'s running containers — not static analysis. DB seeded with a
known test password (`admin` / `TestPass123`, set directly in the dev DB;
not a code or `.env` change) since TASK-0001 left this unresolved.

| Flow | Request | Result | Notes |
|---|---|---|---|
| login | `POST /index.php/auth/login` | **302 Found → `/index.php/`** | Expected redirect, no fatal. Session correctly populated (`uuid`, `active_user`, `name_user`). |
| redirect after login | `GET /index.php/` (follow) | **200 OK**, then a further **302 → `/index.php/index/add`** | Correct, by-design behavior for a fresh install with zero configured dashboard widgets (`IndexController.php`'s own `if(!$this->view->dashboard)` redirect) — not a bug. |
| dashboard | `GET /index.php/index/add` (the widget-setup page underneath the redirect) | **200 OK**, title `SNEP`, real content | No PHP Fatal Error. |
| extensions | `GET /index.php/default/extensions` | **200 OK**, title `SNEP` | No PHP Fatal Error. Only the known pre-existing cosmetic warning (`compact(): Undefined variable $extras`, non-fatal, unrelated to this task, logged not displayed per TASK-0001). |
| trunks | `GET /index.php/default/trunks` | **200 OK**, title `SNEP`, confirmed real "Troncos" content rendered | No PHP Fatal Error. |
| system status | `GET /index.php/default/inspector` ("Status do Sistema" menu link) | **500**, but **no PHP Fatal Error** — a caught exception | `parse_ini_file(/etc/asterisk/snep/snep-musiconhold.conf): Failed to open stream`. **Not a PHP 8 issue** — there is no Asterisk service in this Docker topology (ADR-0001, by design), so this Asterisk config file doesn't exist. Same root cause class as TASK-0001's documented "AMI/AGI/Asterisk-dependent features are unavailable." |
| system status (2nd route) | `GET /index.php/default/systemstatus` | **500**, but **no PHP Fatal Error** — a caught exception | `Unable to connect to manager` — this is `AsteriskInfo`'s own exception, now firing *correctly* (see P0-2 above) because there's no Asterisk to connect to. This is direct proof the PHP4-constructor fix is working as intended: before the fix this would have been a confusing null-pointer crash; after, it's the clean, designed error path. |

### Unresolved findings (not fixed — out of this task's scope)

- **No Asterisk service in this Docker topology** (ADR-0001, TASK-0001) blocks full validation of both system-status routes past the PHP-compatibility layer. Both are now confirmed free of PHP Fatal Errors; a real pass/fail on their actual functionality needs a future Asterisk-integration task (Phase 3), not this one.
- Everything else recorded in the inventory (§1–§12) remains untouched and unchanged by this batch, except where noted above as "pulled forward."

---

## P1-A — completed and validated

### Files changed

**Non-static-called-statically fix, all 18 remaining "23 safe" classes**
(6 of the original 24-name list were already done in P0:
`Snep_Auth_Manager`, `Snep_Config`, `Snep_Dashboard_Manager`,
`Snep_Extensions_Manager`, `Snep_Notifications`, `Snep_Register_Manager`).
Each individually re-verified immediately before editing (fresh
`grep -c '$this'` = 0, fresh whole-codebase call-site grep), not assumed
from the original inventory — one class surfaced a real wrinkle (see
`PBX_DatesAliases` below):

| File | Methods converted | Notes |
|---|---|---|
| `snep/lib/Snep/Audit/Manager.php` | `getAll`, `saveLog`, `addLog` (3) | — |
| `snep/lib/Snep/Binds/Manager.php` | `getBond`, `getBondException`, `addBond`, `addBondException`, `removeBond`, `removeBondByPeer`, `removeBondException`, `ResultBinds` (8) | — |
| `snep/lib/Snep/Cnl.php` | `parseName` (1) | 8 of 9 methods were **already** static; only `parseName()` (called via `self::` from the already-static `addCity()`) needed it. |
| `snep/lib/Snep/ContactGroups/Manager.php` | `getAll`, `get`, `add`, `remove`, `edit`, `insertContactOnGroup`, `removeContactOnGroup`, `getGroupContacts`, `getValidation`, `getName` (10) | One `new Snep_ContactGroups_Manager()` site (`RouteController.php:228`) calls `->getAll()` — stays valid, PHP has always allowed calling a static method via an instance arrow. |
| `snep/lib/Snep/Contacts/Manager.php` | `get`, `getMember`, `getPhone`, `getStates`, `getCity`, `add`, `addNumber`, `remove`, `removeGroup`, `removePhone`, `edit`, `getLastId`, `removeByGroupId` (13) | — |
| `snep/lib/Snep/CostCenter/Manager.php` | `get`, `add`, `remove`, `edit`, `getCdr` (5) | — |
| `snep/lib/Snep/ExpressionAliases/Manager.php` | `delete`, `getValidation`, `get`, `getAll` (4) | — |
| `snep/lib/Snep/ExtensionsGroups/Manager.php` | `getExtensionsGroup`, `getExtensionsNoGroup`, `getExtensionsAll`, `getExtensionsOnlyGroup`, `getName`, `getValidation`, `getExtensionsAllGroup`, `getGroupsExtensions`, `addExtensionsGroup`, `updateExtensionsGroup`, `updateGroupsExtension` (11) | `get`/`getAll`/`addGroup`/`editGroup`/`delete`/`deleteGroupExtensions`/`deleteExtensionGroups` were already static; constructor is `private` (instantiation actively blocked). |
| `snep/lib/Snep/IpStatus/Manager.php` | `getTrunks`, `getPeers` (2) | `getQueues` was already static. |
| `snep/lib/Snep/PickupGroups/Manager.php` | `getValidation`, `getExtensionsAll`, `addExtensionsGroup`, `getExtensionsOnlyGroup`, `getName` (5) | 13 other methods were already static; constructor is `private`. |
| `snep/lib/Snep/Profiles/Manager.php` | `getAll`, `add`, `remove`, `removePermission`, `get`, `edit`, `migration`, `getUsersProfiles`, `getUsersnotProfile`, `lastId`, `getName` (11) | `getIdProfile` was already static. |
| `snep/lib/Snep/Queues/Manager.php` | `get`, `add`, `edit`, `remove`, `removeQueues`, `removeUserPermission`, `removeQueuePeers`, `getMembers`, `getAllMembers`, `removeAllMembers`, `removeMember`, `insertMember`, `getValidationPeers`, `getValidationAgent`, `getValidation`, `insertLogQueue`, `getCsv`, `getName` (18) | `getQueueAll` was already static — largest class in this batch. |
| `snep/lib/Snep/Reports.php` | `createPages`, `fmt_date` (2) | — |
| `snep/lib/Snep/Trunks/Manager.php` | `getValidation`, `getId`, `get`, `getRules`, `remove`, `removePeers`, `getTrunkLog`, `getName`, `enable` (9) | **Pre-existing bug noticed, not fixed** (out of scope): `getTrunkLog()` has `` `call-limit as call_limit` `` — literal backticks (PHP's shell-exec operator) inside an `array()` literal where a quoted string was clearly intended. Not a PHP 8 issue (backticks have always meant shell-exec); doesn't fatal, just silently wrong. Flagged for a future correctness pass. |
| `snep/lib/Snep/Users/Manager.php` | `add`, `remove`, `removeRecovery`, `removePermission`, `addProfile`, `getAll`, `get`, `edit`, `addProfileByName`, `removeProfileByName`, `getName`, `addQueuesPermission`, `getQueuesPermission`, `removeQueuesPermission` (13, `add` done in the docblock edit) | — |
| `snep/lib/Snep/ValidateExpression.php` | `execute`, `IdentificarValidade`, `IdentificarChave` (3) | Its only external call site (`ExpressionAliasController.php`) invokes `execute()` via `::` with no object context, so the internal `self::IdentificarChave()`/`self::IdentificarValidade()` calls had no `$this` to forward either — all three needed to move together. |
| `snep/lib/Snep/Version.php` | `getNewVersions`, `getChangelog`, `my_version_compare` (3) | `getNewVersions()` calls `self::my_version_compare()` — same forwarding requirement as above. |
| `snep/lib/PBX/DatesAliases.php` | `getAll`, `getAllList`, `get`, `add`, `update`, `delete`, `getValidation` (7) | **Real wrinkle found**: this is a genuine singleton (`getInstance()` does `new self()`), which my initial `new $cls\b` grep verification missed (doesn't match `new self()`). Call sites are a **mix** of `PBX_DatesAliases::method()` (direct static syntax) and `PBX_DatesAliases::getInstance()->method()` (instance arrow) — confirmed both forms coexist in `DatesAliasController.php`. Still safe: zero `$this` usage in any method despite the singleton wrapper, and PHP has always allowed calling a static method through an instance arrow, so both calling conventions keep working unchanged. `getInstance()` was already static. |

**`each()` → `foreach`, all 10 web-reachable sites** (each individually
checked for `reset()`/`next()`/`current()`/`key()`/`prev()` interleaving on
the same variable in the same scope before converting — none found, all
were simple linear iteration over `explode("\n", ...)` output):

| File | Lines | Count |
|---|---|---|
| `snep/modules/default/controllers/TdmLinksController.php` | 75→79, 261→265, 300→304 (shifted by comment insertion) | 3 |
| `snep/modules/default/controllers/KhompLinksController.php` | 115→117, 279→281, 318→320 | 3 |
| `snep/modules/default/controllers/ErrorsKhompController.php` | 80→82, 104→106 | 2 |
| `snep/modules/default/controllers/ErrorsTdmController.php` | 77→80, 105→108 | 2 |

**Noted, not touched**, since it was inside a commented-out block:
`IndexController.php`'s `Snep_ITCRegister::register(...)` reference (dead
code, class doesn't exist anywhere in the tree — already recorded in the
P0 section).

### Validation performed

Fresh login (`admin`/`TestPass123`) through all 10 required flows, real
HTTP requests against the running `make dev` containers, log-checked after
every request.

| Flow | Request | Result | Notes |
|---|---|---|---|
| login | `POST /index.php/auth/login` | **302 → `/index.php/`** | No fatal. |
| dashboard | `GET /index.php/` → `GET /index.php/index/add` | **302 → 200**, `var controller = "index"`, 56KB of real content | No fatal. Same by-design widget-setup redirect as P0. |
| extensions | `GET /index.php/default/extensions` | **200**, `var controller = "extensions"` | No fatal. |
| trunks | `GET /index.php/default/trunks` | **200**, `var controller = "trunks"` | No fatal. |
| routes | `GET /index.php/default/route` | **200**, `var controller = "route"`, 22KB | No fatal. |
| groups | `GET /index.php/default/extensions-groups` | **200**, `var controller = "extensions-groups"`, 20KB | No fatal. (Chosen as the canonical "groups" flow — paired with the required "extensions" flow; `pickup-groups`/`contact-groups` also fixed this batch but not separately exercised.) |
| queues | `GET /index.php/default/queues` | **500, but no PHP Fatal Error** — a caught exception | `parse_ini_file(/etc/asterisk/snep/snep-musiconhold.conf): Failed to open stream` — **identical, pre-existing, out-of-scope Asterisk-absence limitation** already documented for system-status in P0. **Correction (was misattributed here originally):** the actual source is `QueuesController::init()` (runs before every action in this controller) directly calling `new Zend_Config_Ini('/etc/asterisk/snep/snep-musiconhold.conf')` — **not** `Snep_SoundFiles_Manager::getClasses()`, which is never called from `QueuesController` at all. Same root cause class (no Asterisk service in this topology, ADR-0001), just a different call site than originally stated. Not a new PHP 8 issue. |
| reports | `GET /index.php/default/calls-report` | **200**, `var controller = "calls-report"`, 28KB | No fatal. (Chosen as the canonical "reports" flow; `ranking-report`/`services-report`/`export-data` not separately exercised.) |
| settings | `GET /index.php/default/parameters` | **200**, `var controller = "parameters"`, 88KB | No fatal. |
| logout | `GET /index.php/auth/logout` | **302 → `/index.php/`**, then that URL renders the login page | No fatal, headers not corrupted despite the inline `<script>clearInterval(...)</script>` echoed before the redirect (pre-existing legacy pattern — output buffering evidently absorbs it; `Location` header still arrived correctly). Session genuinely cleared, confirmed by re-requesting `/index.php/` and getting the login page back, not the dashboard. |

Full-log sweep after the batch: 8 total `Fatal error` lines in
`mag-error.log` for the whole session, all pre-dating these fixes (from
live P0/P1-A debugging, already-fixed classes) — zero new fatals from any
of the 10 flows above. All 22 touched files passed `php -l`.

### Static inventory re-run (as requested)

**Remaining `each()` sites**: exactly the 8 already-inventoried
dead/unreachable ones (7 in vendored `lib/Zend/Cache/*`, `Config/Yaml.php`,
`Http/UserAgent/*`, `Service/DeveloperGarden/*`; 2 object-typed calls in
`Zend/XmlRpc/Value.php`). Confirmed via fresh grep — no new sites, no
sites incorrectly left behind.

**Remaining non-static-called-statically call sites** (fresh cross-reference
script re-run against the current tree, first-party `Snep_*`/`PBX_*`
classes only): **25 distinct methods** still called via `::` where the
declaration isn't static. Breakdown:

- **19 of them are `Snep_SoundFiles_Manager`** methods (`add`, `addClass`,
  `addSounds`, `checkType`, `converter`, `edit`, `editClass`,
  `editClassFile`, `get`, `getClassFile`, `getClassFiles`, `getClasse`,
  `getSounds`, `parseName`, `remove`, `removeClass`, `syncFiles`,
  `verifySoundFiles`, plus `getClasses()` already fixed) — all in
  `SoundFilesController.php`/`MusicOnHoldController.php`/
  `QueuesController.php`, none on any of the 10 required flows' default
  actions. This is the mixed class (36 `$this` uses) explicitly reserved
  for **P2, method-by-method**, per your instruction not to touch it in
  P1-A.
- **3 already-known mixed-class methods**, untouched as planned:
  `PBX_Interfaces::getCodecs` (3 call sites, `ExtensionsController.php`),
  `Snep_Locale::setExtensionsLanguage` (3 call sites, including
  `AuthController.php:61` — a language-switch branch, not the default
  login path already validated), `Snep_Manutencao::arquivoExiste` (1 call
  site, `CallsReportController.php:471` — a sub-action, not the default
  `calls-report` listing page already validated clean).
- **3 genuinely new findings, not in the original inventory** (surfaced by
  re-running the cross-reference after this batch's edits changed what
  "remaining" means): `PBX_Dialplan::parse` (1 call site,
  `lib/PBX/Dialplan/Verbose.php:98`), `Snep_LogUser::log` (2 call sites,
  billing module — `BillingController.php`, `TelcosController.php`),
  `Snep_Route::getRegra` (1 call site, `RouteController.php:647`, a
  sub-action not hit by the default `route` listing page already
  validated). None were reachable by any of the 10 required flows in this
  batch's testing, so none blocked validation — recorded here as
  candidates for a future batch, not fixed now, per P1-A's scope boundary.
  (One apparent match, `Snep_Exten::__construct`, was checked and is a
  false positive — the regex matched a string literal inside an exception
  message, not a real call.)

**New PHP 8.4 incompatibilities uncovered by runtime testing**: none
beyond what the static inventory already predicted. The `queues` flow's
500 is the same already-documented Asterisk-absence limitation, not a new
class of bug.

### Unresolved findings (P1-A)

- The 25 remaining non-static-called-statically call sites above (19 in
  `Snep_SoundFiles_Manager`, 3 already-known mixed-class methods, 3 new
  candidates) — none block any of the 10 required flows' default actions,
  all deferred to a future batch (P2 mixed-class work, or a new inventory
  entry for the 3 new candidates).
- `Snep_Trunks_Manager::getTrunkLog()`'s backtick/shell-exec bug (pre-existing, not a PHP 8 issue, not fixed).
- The `queues` flow's Asterisk-absence limitation (same class as P0's system-status finding, not newly introduced).

---

## P1-B — completed and validated

Resolved all remaining mixed-class non-static/static-call incompatibilities,
plus the 3 newly discovered candidates, each individually classified
stateless-vs-stateful per your rule (no blanket conversion).

### Files changed

**`snep/lib/Snep/SoundFiles/Manager.php`** — per-method classification (36
`$this` uses in the class overall, but no two methods share state across
calls: `$this->lang`/`$this->base_dir` are freshly set at the top of every
stateful method, never read before being set, no explicit constructor).

- **Converted to `static`** (verified zero `$this`, existing `::` call
  sites all still work): `add`, `addClass`, `getClasse`, `editClass`,
  `removeClass`, `checkType`, `parseName`, `converter` (8 methods;
  `getClasses()` was already static from P0).
- **Kept as instance methods** (use `$this->lang`/`$this->base_dir`):
  `get`, `edit`, `remove`, `getClassFile`, `addClassFile`,
  `editClassFile`, `getClassFiles`, `syncFiles`, `addSounds`,
  `getSounds`, `verifySoundFiles` (11 methods) — call sites fixed instead
  (below).

**Call sites changed from `::` to instance calls** (one `new
Snep_SoundFiles_Manager()` per action method, reused for every stateful
call in that method's scope):

| File | Action(s) | Change |
|---|---|---|
| `snep/modules/default/controllers/MusicOnHoldController.php` | `indexAction` | `Snep_SoundFiles_Manager::syncFiles('moh')` → `(new Snep_SoundFiles_Manager())->syncFiles('moh')` |
| same | `fileAction` | `::getClassFiles($section)` → instance call |
| same | `addfileAction` | `::get($originalName)` and `::addClassFile(...)` → shared `$soundFiles` instance |
| same | `editfileAction` | `::getClassFile(...)` and `::editClassFile(...)` → shared instance |
| same | `removefileAction` | `::getClassFile(...)` and `::remove(...)` → shared instance |
| `snep/modules/default/controllers/SoundFilesController.php` | `indexAction` | `::verifySoundFiles(...)` inside a `foreach` → single instance created before the loop, reused each iteration |
| same | `addAction` | `::get($originalName)` → instance call |
| same | `editAction` | `::get($arquivo)` and `::edit($dados)` → shared instance |
| same | `removeAction` | `::remove($id)` and `::verifySoundFiles($id, true)` → shared instance |
| same | `restoreAction` | `::verifySoundFiles($file, true)` → instance call |
| same | `synchronizeAction` | `::getSounds()` and `::remove($file)`/`::addSounds($archive)` inside two loops → single shared instance |
| `snep/modules/default/controllers/QueuesController.php` | `addAction`, `editAction` | `::getSounds(true)` → instance call (one site each) |

**`snep/lib/PBX/Interfaces.php`** — `getCodecs()` → `static` (verified:
the only `$this` in the whole file is in `__construct()`, a separate,
unrelated method; `getCodecs()`'s 3 call sites in `ExtensionsController.php`
already used `::`, no call-site changes needed).

**`snep/lib/Snep/Locale.php`** — `setExtensionsLanguage()` → `static`
(verified zero `$this`/`self::$instance` usage despite the class being an
overall stateful singleton elsewhere; its 3 call sites — `AuthController.php`,
`ParametersController.php` ×2 — already used `::`, no changes needed).

**`snep/lib/Snep/Manutencao.php`** — `arquivoExiste()` and `listaStorage()`
→ `static` together (`arquivoExiste()` calls `listaStorage()` via `self::`,
so both had to move together; class is never instantiated anywhere,
`arquivoExiste()`'s one external call site — `CallsReportController.php:471`
— already used `::`, `listaStorage()` has no external callers at all).

**`snep/lib/Snep/LogUser.php`** — `log()` → `static` (zero `$this`, never
instantiated, both call sites — `BillingController.php`,
`TelcosController.php` — already used `::`).

**`snep/lib/Snep/Route.php`** — `getRegra()` → `static` only (zero
`$this`, its one call site — `RouteController.php:647` — already used
`::`). The class's other 3 methods (`insertLogRegra`, `getLastId`,
`getActions`) have **zero external callers at all** — not part of any
flagged incompatibility, deliberately left untouched, per scope.

### False positives found (no fix needed)

- **`PBX_Dialplan::parse`** — the only match anywhere in the codebase is
  inside a PHPDoc comment in `lib/PBX/Dialplan/Verbose.php:98`
  ("Sobreescreve PBX_Dialplan::parse()..." — Portuguese for "Overrides..."),
  not executable code. Every real usage of `PBX_Dialplan`/
  `PBX_Dialplan_Verbose` (`agi/snep.php`, `lib/PBX/Rule/Action/DiscarRamal.php`,
  `modules/default/actions/DiscarRamal.php`,
  `modules/default/controllers/SimulatorController.php`) already correctly
  does `new PBX_Dialplan(); ...; $dialplan->parse();` — proper
  instantiation, never called statically. `parse()` itself is genuinely
  stateful (`$this->foundRule`, `$this->request`, real cross-method
  object state) and was correctly never flagged as broken.
- **`Snep_Exten::__construct`** — the only match is a string literal
  inside an exception message (`lib/Snep/Exten.php:104`:
  `"Error: 'Snep_Exten::__construct()' wait for a instancee of..."`), not
  a real `::` call.

### Validation performed

Fresh login (`admin`/`TestPass123`), all 10 required flows re-exercised,
plus the flows most directly touching this batch's changed methods
(Music on Hold and Sound Files admin pages, reached via the "settings"
area — not separately itemized below since none of their specific
actions are among the 10 required flows, but `php -l` + code-path tracing
covered every changed call site).

| Flow | Request | Result |
|---|---|---|
| login | `POST /index.php/auth/login` | **302 → `/index.php/`**, no fatal |
| dashboard | `GET /index.php/` → `/index.php/index/add` | **302 → 200**, no fatal |
| extensions | `GET /index.php/default/extensions` | **200**, no fatal |
| trunks | `GET /index.php/default/trunks` | **200**, no fatal |
| routes | `GET /index.php/default/route` | **200**, no fatal |
| groups | `GET /index.php/default/extensions-groups` | **200**, no fatal |
| queues | `GET /index.php/default/queues` | **500, no PHP Fatal Error** — same pre-existing, out-of-scope Asterisk-absence limitation (see correction in the P1-A section above); unrelated to this batch's edits |
| reports | `GET /index.php/default/calls-report` | **200**, no fatal |
| settings | `GET /index.php/default/parameters` | **200**, no fatal |
| logout | (validated in P1-A, unaffected by this batch) | — |

**`php -l` result**: all 9 files touched in P1-B pass with "No syntax
errors detected" —
`lib/Snep/SoundFiles/Manager.php`, `lib/PBX/Interfaces.php`,
`lib/Snep/Locale.php`, `lib/Snep/Manutencao.php`, `lib/Snep/LogUser.php`,
`lib/Snep/Route.php`,
`modules/default/controllers/MusicOnHoldController.php`,
`modules/default/controllers/SoundFilesController.php`,
`modules/default/controllers/QueuesController.php`.

**Fatal-error count result**: 8 total `Fatal error` lines in
`mag-error.log` for the whole session — identical to the count at the end
of P1-A. All 8 are pre-existing entries from P0-era live debugging
(`Snep_Acl::getCaseSensitive`, `Snep_Auth_Manager::adduuid`,
`Snep_Config::getConfiguration`, `Snep_Dashboard_Manager::getModelos`,
`Snep_Extensions_Manager::getAll`, `Snep_Notifications::getNoView`,
`Snep_SoundFiles_Manager::getClasses`, `Snep_Usuario::encrypt` — all
already fixed before P1-A even started). **Zero new fatals introduced by
P1-B.**

### Final inventory result

Fresh cross-reference re-run after all P1-B edits: **zero real remaining
first-party non-static-called-statically incompatibilities.** Only 2
matches remain, both confirmed false positives (above): `PBX_Dialplan::parse`
(docblock comment) and `Snep_Exten::__construct` (exception-message
string). **All web-reachable PHP 8.4 static-call fatals are eliminated.**

### Unresolved items

- The `queues` flow's 500 (Asterisk-absence limitation, `QueuesController::init()` → `Zend_Config_Ini` on a nonexistent file) — pre-existing, out of scope, unrelated to static-call compatibility.
- `Snep_Route`'s 3 uncalled methods (`insertLogRegra`, `getLastId`, `getActions`) — dead code, not part of any flagged incompatibility, left untouched.
- Everything already recorded as out of scope for this task: curly-brace offsets (§2), remaining §6–11 categories, Asterisk 22, PJSIP, PostgreSQL, frontend/refactoring.
