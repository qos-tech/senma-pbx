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

## Unresolved / follow-up
- `lib/Asterisk/AGI.php`'s 27 sites and the 7 vendored-dead files above
  remain exactly as inventoried in TASK-0002, now re-verified rather than
  just carried forward — still not fixed, deferred for the reasons in the
  table above.
- TASK-0002 §6–11 (dynamic properties, `count()` misuse, etc.) — not
  started, next batch(es).
