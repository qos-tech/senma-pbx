# TASK-0004 — PHP 8.4 remaining compatibility fixes

## Objective
Resolve the remaining confirmed PHP 8.4 incompatibility categories from
`docs/tasks/0002-php84-compatibility-baseline.md` §6–11, while preserving
behavior. First batch: curly-brace string/array offset syntax (§2).

## Scope (this batch)
- Curly-brace string/array offset syntax (`$var{expr}`, removed in
  PHP 8.0 — a parse-time fatal, not just a runtime one).
- Re-verification of the entire category before editing anything (per
  CLAUDE.md's static-analysis rules and this task's explicit instruction),
  not a blind re-application of TASK-0002's inventory.

## Explicitly out of scope
- Categories §6–11 other than curly-brace offsets (dynamic properties,
  `count()`/`sizeof()` misuse, object/array misuse, changed offset
  behavior, signature incompatibilities, undefined constants) — next
  batches.
- Architectural refactoring.
- Asterisk 22, PJSIP, PostgreSQL, frontend redesign.

## Re-verification method and findings

Re-scanned the entire `snep/` tree with a broader pattern than TASK-0002
used (which only matched `$varname{`, missing `->property{expr}` forms),
then manually read every candidate's actual context rather than trusting
either the old inventory or the new regex.

**Correction to TASK-0002's count**: `lib/Zend/Json/Decoder.php` actually
has **6** real occurrences (327, 354, 361, 434, 497, 555), not the 1
originally recorded. `lib/Zend/Amf/Util/BinaryStream.php:143` is
confirmed real (`$this->_stream{$this->_needle++}` — a property-offset
form the original narrower regex should have caught but a second look
confirms is genuine).

**First-party code (`modules/`, `includes/`, `inspectors/`, `lib/Snep/`,
`lib/PBX/`) re-scanned with a broad pattern: zero real occurrences**
outside the already-known `lib/Asterisk/AGI.php`. The only first-party
matches (`TdmLinksController.php`, `KhompLinksController.php`,
`includes/ParseDown.php`) are false positives — literal strings like
`"kecs{Busy,Locked,RemoteLock}"` (Khomp hardware status-code text) and
regex quantifier syntax (`'/^[ ]{0,4}/'`) inside `preg_*` pattern
strings, not PHP offset syntax. `lib/Zend/Db/Statement.php:194` is
re-confirmed a false positive too (ordinary `"...{$escapeChar}..."`
string interpolation adjacent to literal regex text, not offset syntax).

**New finding that changes TASK-0002's "probably reachable" classification
for `Zend_Json_Decoder`/`Encoder`**: traced `Zend_Json::decode()`/
`encode()` (`lib/Zend/Json.php`) and found both only delegate to
`Zend_Json_Decoder`/`Encoder` when `function_exists('json_decode'/
'json_encode') === false` or `Zend_Json::$useBuiltinEncoderDecoder ===
true`. PHP 8.4's `json` extension is always present, and nothing in the
codebase ever sets `$useBuiltinEncoderDecoder` — confirmed via grep, zero
hits. Additionally, all 7 `Encoder.php` sites are inside `_utf82utf16()`,
itself guarded by `function_exists('mb_convert_encoding')` — confirmed
the `mbstring` extension is installed in this image (`php -m`). Same
guard pattern found on the `_utf162utf8()` method containing Decoder's
line 555. **Net effect: both classes' buggy code paths are currently
unreachable in this specific Docker image**, not "probably reachable" as
speculated — corrected per CLAUDE.md's instruction to fix
known-wrong findings rather than preserve them.

## Fix vs. defer decision

Despite being currently unreachable, `Zend_Json_Decoder`/`Encoder` were
**fixed, not deferred**, because `Zend_Json::decode()`/`encode()` (the
class that wraps them) is genuinely used by first-party code —
`IndexController.php`, `RegisterController.php`,
`ModuleSettingsController.php`, `lib/Snep/Version.php`,
`lib/Snep/Notifications.php`, `lib/Snep/Rest/Controller.php` — so this is
a fragile, environment-dependent landmine (would fatal immediately if a
future image ever lacked `mbstring`, or if `$useBuiltinEncoderDecoder`
were ever set) on a class family that's actually in the application's
call graph, unlike the fully-dead vendored classes below. The fix itself
is a zero-risk, zero-behavior-change syntax swap (`{` → `[`), so fixing
it now costs nothing and removes real latent risk.

Everything else is **deferred**, each for a distinct, documented reason
— re-verified zero first-party usage (grepped fresh, not assumed from
TASK-0002):

| File(s) | Sites | Reason deferred |
|---|---|---|
| `lib/Asterisk/AGI.php` | 27 | First-party, but loaded only by `snep/agi/*.php` — a separate PHP execution context (Asterisk-invoked AGI, not the Apache/HTTP path). Cannot be exercised or validated by `make smoke`; belongs to a future AGI/Asterisk-focused task (Phase 4/5). |
| `lib/Zend/Barcode/Object/{Code25,Ean5,Ean8,Ean13,Identcode,ObjectAbstract,Upca,Upce}.php` | 11 across 8 files | Re-confirmed zero first-party usage of `Zend_Barcode`. |
| `lib/Zend/Amf/Util/BinaryStream.php` | 1 | Re-confirmed zero first-party usage of `Zend_Amf`. |
| `lib/Zend/Validate/Isbn.php` | 3 | Re-confirmed zero first-party usage. |
| `lib/Zend/Filter/Compress/Zip.php` | 1 | Re-confirmed zero first-party usage. |
| `lib/Zend/View/Helper/Navigation/Sitemap.php` | 2 | Re-confirmed zero first-party usage (`Zend_Navigation`). |
| `lib/Zend/Wildfire/Plugin/FirePhp.php` | 1 | Re-confirmed zero first-party usage; debug-only plugin. |
| `lib/Zend/Tool/Project/Context/Zf/ApplicationConfigFile.php` | 1 | Re-confirmed zero first-party usage; `zf` CLI tooling, not part of the runtime app. |

No fix is speculative or applied to unreachable code in this batch,
matching the discipline established throughout TASK-0002.

## Files changed
- `snep/lib/Zend/Json/Decoder.php` — 6 sites, `$str{$i}`-style →
  `$str[$i]`, plus a class-level doc comment explaining the fix and its
  reachability analysis.
- `snep/lib/Zend/Json/Encoder.php` — 7 sites, `$utf8{0}`-style →
  `$utf8[0]`, same doc-comment treatment.

## Validation performed
- `php -l` on both touched files: clean.
- Fresh re-grep of both files: zero real curly-brace offsets remain (only
  matches are inside the explanatory doc comments, which quote the old
  syntax as an example).
- `make smoke`: **14 PASS, 0 FAIL, 1 EXPECTED_LIMITATION** (`queues`,
  unchanged, documented no-Asterisk limitation) — identical result to the
  pre-batch baseline.
- App log inspection: fatal-error count `0 → 0`; only pre-existing
  cosmetic warnings (`compact(): Undefined variable $extras`) and the
  expected `403`-denial log lines for the protected-config-file check.
  **Zero new PHP Fatal Errors.**

## Unresolved / follow-up (batch 1)
- `lib/Asterisk/AGI.php`'s 27 sites and the 7 vendored-dead files above
  remain exactly as inventoried in TASK-0002, now re-verified rather than
  just carried forward — still not fixed, deferred for the reasons in the
  table above.
- TASK-0002 §6–11 (dynamic properties, `count()` misuse, etc.) — not
  started, next batch(es).

---

# Batch 2 — `lib/linfo` PHP 8.4 fatal chain

## Objective
Resolve the highest-priority remaining PHP 8.4 incompatibility that is
first-party-reachable (in practice, not just in principle), testable
without Asterisk, and fixable without behavior change.

## Re-verification and new findings

Re-checked TASK-0002 §7 (`count()`/`sizeof()` misuse) against the current
tree before accepting it as a batch candidate, and found both remaining
live candidates disqualified:

- `ErrorsTdmController.php:93`'s zero-argument `count()` sits behind
  `new AsteriskInfo()` (line 55 of the same action), which throws
  immediately in this no-Asterisk topology and returns before line 93 is
  ever reached — requires Asterisk to validate, out of this batch's scope.
- `Billing/Manager.php`'s 3 `count($falsy)` sites (`getByArea()`,
  `getByType()`, `rate()`) — traced every call site in the tree and found
  **zero callers anywhere**. `CallsReportController.php` (the only place
  that references `Billing_Manager` at all) only does
  `class_exists("Billing_Manager")` feature-detection to decide whether to
  join a `rated_calls` table in raw SQL — it never instantiates or calls
  the class. TASK-0002's "reachable if billing reports render" was
  speculative and is corrected here: these 3 sites are dead code.

**New finding, not in TASK-0002's inventory**: `snep/lib/linfo/` (a
vendored system-info library) was never covered by either of TASK-0002's
systematic sweeps (the curly-brace sweep only covered `lib/Zend/*` and
`lib/Asterisk/AGI.php`; the §12 removed-function sweep only covered
`modules/`, `lib/Snep`, `lib/PBX`, `lib/Asterisk`, `includes/`, `agi/`,
`inspectors/`). It is, however, genuinely reachable two ways: directly,
unauthenticated, at `GET /lib/linfo/index.php?out=xml` (no Apache
restriction on `/lib/`, confirmed by inspecting the Docker config), and
indirectly via `SystemstatusController::indexAction()`
(`GET /index.php/default/systemstatus`), which fetches that same URL
through an internal loopback HTTP request. Neither path requires
Asterisk.

Direct `curl` to that endpoint returned a bare HTTP 500; the app log
showed:
```
PHP Fatal error:  __autoload() is no longer supported, use spl_autoload_register() instead in /var/www/html/snep/lib/linfo/init.php on line 70
```
Confirmed via `php -l`, which also fails on this file: declaring a
function literally named `__autoload()` is a **compile-time** fatal since
PHP 8.0, regardless of the `if (function_exists('spl_autoload_register'))`
guard around it not being taken at runtime — same severity class as
curly-brace offsets (blocks the file from loading at all), a different
forbidden construct.

Tracing further: `lib/linfo/config.inc.php` (the live, non-sample config)
sets `$settings['show']['distro'] = true`, so `getDistro()` — containing
the 2 `create_function()` sites TASK-0002 had flagged but marked
"not yet confirmed either way" — executes unconditionally on the very
next step of the same request, once the `__autoload` blocker is cleared.
Both bugs sit on the identical, unconditionally-reachable path.

Swept the rest of `lib/linfo/lib/*.php` for every other known
incompatibility pattern (other removed PHP8 functions, PHP4-style
constructors, additional `each()`/curly-brace sites) before proposing
scope — clean, nothing else found in that sweep.

Also found, not part of the proposed/authorized scope: `lib/linfo/lib/functions.init.php:29`
has the identical `function __autoload($class)` bug, unconditionally (no
guard at all) — but it is never `require`/`include`d anywhere in the tree
(grepped for `functions.init.php`), confirmed dead, and was excluded from
this batch per instruction.

## Fix

**`snep/lib/linfo/init.php`** — renamed the dead-branch
`function __autoload($class)` to `function linfo_legacy_autoload($class)`.
Same body, same never-taken branch (`spl_autoload_register` has existed
since PHP 5.1.2 and is always available here), same
`if (function_exists('spl_autoload_register'))` guard preserved exactly —
zero behavior change, the file now simply parses under PHP 8.4.

**`snep/lib/linfo/lib/class.OS_Linux.php`** — replaced both
`create_function('$ini', '...')` calls in `getDistro()`'s
`$contents_distros` array (the `/etc/lsb-release` and `/etc/os-release`
parsers) with equivalent closures (`function($ini) { ...same body... }`).
Confirmed drop-in safe: the sole consumer,
`$distro['closure']($contents)` at line 1372 (now shifted by the added
doc comment), calls the value directly — this works identically whether
`'closure'` holds the callable string `create_function()` used to return
or a real `Closure` object. Added a class-level doc-comment paragraph
explaining the fix and its reachability, matching batch 1's convention.

## New finding uncovered by validation — not fixed, out of this batch's scope

Testing the fix (`curl` directly against `/lib/linfo/index.php?out=xml`)
surfaced a **third, distinct, pre-existing bug** in the same method chain,
previously masked because the `__autoload` fatal always fired first:
```
PHP Fatal error:  Uncaught TypeError: ceil(): Argument #1 ($num) must be
of type int|float, string given in
/var/www/html/snep/lib/linfo/lib/class.OS_Linux.php:339
Stack trace:
#0 class.OS_Linux.php(339): ceil('371714.72 36954...')
#1 class.Linfo.php(248): OS_Linux->getUpTime()
#2 index.php(31): Linfo->scan()
```
`getUpTime()` passes the raw string contents of `/proc/uptime` (space-
separated float text, e.g. `"371714.72 369545.10"`) straight to `ceil()`
without a numeric cast — PHP 8's stricter internal-function typing (no
more implicit string→float coercion with trailing garbage) turns this
into a fatal `TypeError` where PHP 7 would have silently coerced the
leading numeric portion. This is a **different incompatibility category**
than either fix in this batch (internal-function argument-type
strictness, not a removed API), was not part of the scope authorized for
this batch (`init.php` + the 2 `create_function()` sites only), and was
not touched. Reproduced twice for certainty; not a flake.

**Effect on the two reachable entry points**:
- `GET /lib/linfo/index.php?out=xml` directly: still returns a bare 500 —
  now from this newly-exposed `ceil()` bug instead of the two fixed ones.
  Net progress, not yet a clean 200.
- `GET /index.php/default/systemstatus` (authenticated): **unchanged
  external behavior** from the pre-batch baseline — still the same clean,
  caught "500 — Erro Interno / Unable to connect to manager" page
  documented in TASK-0002's P0 section. Traced why: `indexAction()`'s
  loopback call catches only `HttpException`, and Zend_Http_Client does
  not throw on a non-2xx response by default — it just returns the
  (empty, since `display_errors=Off`) body. So a failing linfo endpoint
  degrades silently into `$this->sysInfo` being unusable, non-fatal
  warnings on the subsequent property/array accesses, and the page's
  *visible* failure mode continues to be `statusbar_info()`'s uncaught
  `AsteriskInfo` connection exception (line 140) — the same pre-existing,
  out-of-scope, no-Asterisk limitation as always. This batch's fixes are
  real and verified (confirmed by the log showing execution now reaching
  fully through both previously-fatal lines into `getUpTime()`), but they
  don't change this page's observed behavior yet, since a third,
  unauthorized-for-this-batch bug sits between the fixes and a working
  response.

Recorded here as a candidate for a future batch — not fixed now, per this
batch's explicit scope boundary.

## Security/architecture finding — documented, not remediated

`GET /lib/linfo/index.php?out=xml` is reachable directly over HTTP with
**no authentication and no session** — confirmed via `curl` with no
cookie jar. It's a raw PHP script under the docroot, not routed through
the Zend front controller (where `AuthController`'s login gate lives), and
`/lib/` carries no Apache-level access restriction (unlike
`/includes/setup.conf`, which TASK-0003's smoke suite confirms returns
403). Once the `ceil()` bug above is eventually fixed too, this endpoint
would expose CPU/RAM/disk/OS/network system information to any
unauthenticated visitor. This is a pre-existing exposure (predates this
task entirely — the endpoint was equally unauthenticated before, it just
also happened to fatal), not introduced or worsened by this batch's
fixes. Per instruction, **not remediated here** — this batch is a
compatibility fix, not an access-control change. Flagged for a future
security/architecture-focused task.

## Validation performed
- `php -l` on both touched files: clean (`class.OS_Linux.php` also emits
  one pre-existing, unrelated cosmetic warning — "continue targeting
  switch" at line 1267 — not introduced by this batch, not fixed, per
  the bug/technical-debt policy of documenting rather than opportunistically
  fixing unrelated issues).
- Direct `curl` to `/lib/linfo/index.php?out=xml`: confirmed both target
  fatals (`__autoload`, `create_function()`) no longer occur; confirmed
  (twice) the next-in-chain `ceil()` bug is what now surfaces instead —
  see above.
- `GET /index.php/default/systemstatus` (authenticated): confirmed
  unchanged from TASK-0002's documented P0 baseline — same clean, caught
  500, same message, no raw fatal text in the response body.
- `make smoke`: **14 PASS, 0 FAIL, 1 EXPECTED_LIMITATION**, identical to
  the pre-batch baseline, run twice for a clean final snapshot.
- App log inspection: `make smoke`'s own before/after fatal-error diff is
  `0 → 0` both runs (the smoke suite's 10 flows never touch
  `systemstatus`/`lib/linfo`, so it can't observe the `ceil()` bug either
  way). **Zero new PHP Fatal Errors on any of the 10 required flows.**
  Diagnostic `curl` probes against `/lib/linfo/index.php` directly (not
  part of the smoke suite) did surface the pre-existing `ceil()` fatal
  described above — this is a newly-*uncovered*, not newly-*introduced*,
  bug (confirmed by the stack trace showing it fires deeper in the same
  call chain, past both of this batch's fixes).

## Files changed
- `snep/lib/linfo/init.php` — 1 site, `__autoload` → `linfo_legacy_autoload`.
- `snep/lib/linfo/lib/class.OS_Linux.php` — 2 sites,
  `create_function()` → closures, plus a class-level doc comment.

## Unresolved / follow-up (batch 2)
- `lib/linfo/lib/class.OS_Linux.php:339`'s `ceil()` `TypeError` in
  `getUpTime()` — real, reachable, confirmed, not fixed (out of this
  batch's authorized scope) — candidate for the next batch.
- `lib/linfo/lib/functions.init.php:29`'s identical `__autoload` bug —
  confirmed dead code (zero includers), deliberately excluded per
  instruction.
- Unauthenticated reachability of `/lib/linfo/index.php` — documented
  above as a security/architecture finding, deliberately not remediated
  in this compatibility-focused batch.
- `ErrorsTdmController.php:93` and `Billing/Manager.php`'s 3 sites (§7
  `count()` misuse) — re-confirmed Asterisk-gated / dead respectively,
  excluded from this batch, unchanged from TASK-0002.
