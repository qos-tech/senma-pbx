# TASK-0026E — PJSIP/Asterisk configuration-injection hardening (F12–F15)

## Status

Implementation complete and validated. Two consecutive full `make
regression` passes both PASS. Not committed.

## Scope

TASK-0026 (the pre-pilot security audit) recorded four configuration-
injection findings in root-cause group C: F12 (Extensions), F13
(Trunks), F14 (PJSIP Transports), F15 (legacy chan_sip). This task
remediates exactly those four, using the current tree and live
application behavior as authoritative rather than the audit's
historical line numbers. It does not touch: F1–F11 (already handled by
TASK-0026B/C), F16+ (authorization/API findings), shell execution
(TASK-0026D), the PJSIP-only legacy-cleanup/removal decision (explicitly
deferred to a later Product Readiness task), or the database schema.

## Security principle applied

"User-controlled PBX data may become configuration values, but must
never become configuration syntax." The one mechanism that actually
achieves this across every generator in this codebase is rejecting any
control character (0x00–0x1F, 0x7F) or `;` in a value before it is
written — a real newline is the only thing that lets a value break out
of its own `key=value` line into new syntax Asterisk's `.conf` parser
will interpret (a new directive, or, combined with `[`, an entirely new
section); `;` starts an Asterisk comment mid-line, which the audit
separately flagged as a way to silently truncate/hide the rest of an
injected line. This was applied as one shared, narrow validator
(`Snep_PjsipConf::isSafeConfigValue()`), reused at both the
controller-input boundary (the primary control) and the generator-
output boundary (defense-in-depth), exactly as the audit's own F12
write-up suggested.

## 1. Finding inventory (re-verified against current code and live behavior)

| Finding | Object | Input | Generated file/section | Required permission | Current status |
|---|---|---|---|---|---|
| F12 | Extensions | `exten` (section identifier), `name`→`callerid` (value) | `senma-pjsip.conf`, `[name]`/`[name-auth]` | `extensions_write` (live-verified) | **confirmed exploitable** |
| F13 | Trunks | `context`/`callerid`/`fromuser`/`fromdomain`/`host`/`secret`/`username`→`defaultuser` (values) | `senma-pjsip-trunks.conf`, `[trunk-<id>]` | `trunks_write` (live-verified) | **confirmed exploitable** for every value field; the audit's own claim that "name/auth/registration/identify are also used as unguarded [section] headers" **does not hold for the current code** — see below |
| F14 | PJSIP Transports | `name` (identifier), `protocol`/`bind_address`/`bind_port`/`domain`/`external_signaling_address`/`_port`/`external_media_address`/`local_net` (values) | `senma-pjsip-transports.conf`, `[name]` | `pjsip-transports_write` (live-verified) | **already fully mitigated** — see below |
| F15 | legacy chan_sip/iax2 (`technology=sip`/`iax2`) | same `exten`/`name`/`context`/`host`/`secret`/`fromuser`/`fromdomain`/`defaultuser` fields as F12/F13, consumed by a different generator | `snep-sip.conf`/`snep-iax2.conf`, `[name]`/`[defaultuser]` | same `extensions_write`/`trunks_write` (live-verified) | **confirmed reachable** (see reclassification below), fixed as REACHABLE per Phase 12 |

### F13 partial reclassification

The audit's F13 text states section identity (`name`/`auth`/
`registration`/`identify`) is "unguarded". Tracing the current
`Snep_PjsipTrunkConf::renderTrunk()` shows this is no longer accurate
for the PJSIP generator specifically: every section name is built as
`"trunk-" . $trunk['id']` (and suffixes of it), where `$trunk['id']` is
the `trunks` table's own auto-increment primary key — never a
user-controlled field. This was a deliberate TASK-0014 design choice
(the class's own doc comment: "not trunk-<trunks.name> ... a
same-shaped but independently-computed string, weaker uniqueness
guarantee than the real primary key"), predating this audit or simply
not re-traced against the current architecture. **The section-identity
half of F13 is not exploitable in the current PJSIP generator.** The
value-position half (context/callerid/fromuser/fromdomain/host/secret,
plus `defaultuser`, which *is* still a raw section header but only in
the separate legacy chan_sip/iax2 generator — see F15) remains fully
exploitable and is fixed below. This does not rewrite the historical
finding — F13 as originally written still describes a real defect
class; only the section-header claim specifically no longer matches
the current PJSIP-generator code, and is documented here rather than
silently corrected in the original audit file.

### F14 — already fully mitigated (not a fix, a finding)

`PjsipTransportsController::validatePost()` (via
`Snep_PjsipTransports_Manager::validateName()`/`validateProtocol()`/
`validateIpOrHostname()`/`validatePort()`/`validateCidr()`) already
rejects every dynamic transport field with a strict allowlist —
`name` against `^[A-Za-z0-9_-]{1,80}$`, `protocol` against a fixed
enum, `bind_address`/`domain`/`external_signaling_address`/
`external_media_address` against a real IP-or-hostname grammar,
`bind_port`/`external_signaling_port` against a 1–65535 integer range,
and `local_net` against a real CIDR grammar — all implemented in
TASK-0019/0020, well before this task. Live-confirmed (a raw POST with
`domain=legit.example\r\n[task0026e-injected]\r\ntype=transport`
rejected with "Invalid domain", HTTP 200, no marker in
`senma-pjsip-transports.conf`) both before and after this task's other
changes. **No code was changed for F14** — it is reconfirmed by the
focused smoke suite below as a regression guard, not remediated, since
there was nothing left to remediate.

### F15 — reachability, reclassified from the audit's own conditional

The audit itself said: "Pilot classification: P1 if the pilot is
confirmed PJSIP-only... reclassify P0 if any chan_sip-technology
extension/trunk is planned." Current tracing shows `technology=sip` and
`technology=iax2` remain fully selectable options on both the
Extensions and Trunks add/edit forms (`addedit.phtml` in both modules),
with `Snep_InterfaceConf::loadConfFromDb()` actively called from four
call sites in `ExtensionsController.php` and four in
`TrunksController.php` — not dead code, not gated behind any feature
flag. **Classified REACHABLE** per this task's Phase 12 criteria, and
remediated with the smallest safe boundary correction rather than
deferred.

## 2. F12 — Extensions

**Current call path:** `ExtensionsController::execAdd()` had zero
server-side shape validation on `exten`/`name` before persistence;
`Snep_PjsipConf::renderExtension()` (`snep/lib/Snep/PjsipConf.php`)
then built `"[$name]\n"`, `` "context=" . $peer['context'] . "\n" ``,
`` "callerid=" . $peer['callerid'] . "\n" ``, and
`` "password=" . $peer['secret'] . "\n" `` via raw concatenation, with
`$name` also forming `$name."-auth"` (a second section header) and
`aors=$name`/`username=$name`.

**Fix:**
- `snep/lib/Snep/PjsipConf.php`: new
  `Snep_PjsipConf::isSafeConfigValue($value)` — the one shared
  validator (rejects any 0x00–0x1F/0x7F control character or `;`),
  reused by every generator and controller in this task.
- `snep/modules/default/controllers/ExtensionsController.php`
  (`execAdd()`): `exten` must match `^[0-9]{1,20}$` (the exact numeric
  shape the form has always asked for — "Only numbers",
  `type="number"` — and the shape `multiaddAction()`'s own bulk-
  provisioning flow already assumes elsewhere); `name` (→ `callerid`)
  and `password` (→ `secret`) must pass `isSafeConfigValue()`. Rejected
  with a translated form error before any DB write, matching this
  method's own existing "return a string on failure" convention.
- `snep/lib/Snep/PjsipConf.php` (`renderExtension()`): defense-in-depth
  — re-checks `name`/`callerid`/`context`/`secret` independently before
  writing, throwing `PBX_Exception_NotFound` to skip just that one row
  (the same discipline `resolveTransportName()` already established for
  a disabled-transport reference), in case a row ever reaches this
  generator through a path other than `execAdd()`.

**Before/after (inert marker, not a real payload):** submitting
`name` = `Task0026e<CRLF>[task0026e-injected]<CRLF>type=endpoint<CRLF>task0026e_marker=yes`
is now rejected outright (form error, no DB write); before this fix it
would have produced, verbatim in `senma-pjsip.conf`:
```
callerid=Task0026e
[task0026e-injected]
type=endpoint
task0026e_marker=yes
```
— an entirely new, attacker-named PJSIP section.

## 3. F13 — Trunks

**Current call path:** `TrunksController::preparePost()` merges the
whole POST body into `$trunk_data`/`$ip_data` with only a key-name
allowlist (`$trunk_fields`/`$ip_fields`), never validating what
characters the *values* may contain; `Snep_PjsipTrunkConf::renderTrunk()`
then raw-concatenates `context`/`callerid`/`from_user`/`from_domain`/
`secret`/`defaultuser`/`host` (the last inside `contact=sip:$host:$port`,
`client_uri=sip:$username@$host:$port`, `server_uri=sip:$host:$port`,
and `match=$host`).

**Fix:**
- `snep/modules/default/controllers/TrunksController.php`
  (`preparePost()`): new private `validateConfigFields($ip_data)`,
  called once at the end of `preparePost()` (shared by both
  `addAction()` and `editAction()`, which both already check
  `is_string($trunk_data)` on `preparePost()`'s return value and abort
  with the returned translated error — no new error-handling plumbing
  needed). Validates `context`/`callerid`/`fromuser`/`fromdomain`/
  `secret` with `isSafeConfigValue()`; `host` with
  `Snep_PjsipTransports_Manager::validateIpOrHostname()` (reused rather
  than reinvented, since it also reaches `sip:`-URI construction);
  `defaultuser` with `Snep_PjsipTransports_Manager::validateName()`
  when non-empty (the stricter identifier grammar, because the legacy
  chan_sip/iax2 generator — F15 — uses this same field as a raw
  section header; PJSIP's own use of it is only as a value, so the
  stricter check costs it nothing).
- `snep/lib/Snep/PjsipTrunkConf.php` (`renderTrunk()`): defense-in-depth
  — re-checks `context`/`callerid`/`fromuser`/`fromdomain`/`host`/
  `secret`/`defaultuser` before writing, skip-and-log per row (same
  `PBX_Exception_NotFound` pattern as F12). Documents explicitly that
  `$name`/`$auth` (this class's own section identifiers) need no such
  check — they are already `trunk-<id>`, safe by construction.

**Before/after:** submitting `callerid` = `Task0026e<CRLF>[task0026e-injected]<CRLF>type=endpoint`
is now rejected outright; before this fix it would have produced a new
section immediately following the trunk's own `callerid=` line, inside
the SAME `[trunk-<id>]` endpoint block. Submitting a newline-bearing
`host` is separately caught as "Invalid trunk host" by the reused
IP-or-hostname grammar.

## 4. F14 — PJSIP Transports

**Classification:** already fully mitigated by TASK-0019/0020 (see
§1 above). **No code changed.** Re-confirmed live before and after this
task's other changes: a newline/section-shaped `domain` value is
rejected with "Invalid domain" before any DB write or config
generation, and the focused smoke suite (§6) exercises this as a
permanent regression guard.

## 5. F15 — legacy chan_sip/iax2

**Current call path:** `Snep_InterfaceConf::loadConfFromDb()`
(`snep/lib/Snep/InterfaceConf.php`) reads the exact same `peers`/
`trunks` rows F12/F13 already validate at the point of persistence —
`technology=sip`/`iax2` extensions and trunks are created through the
identical `ExtensionsController::execAdd()`/`TrunksController::preparePost()`
code paths, just branching internally on `$techType`/`$trunktype`. This
generator then raw-concatenates `type`/`context`/`host`/`secret`/
`callerid`/`fromdomain`/`fromuser`/`disallow`/`allow`/`directmedia`,
using `` '[' . $peer['defaultuser'] . "]\n" `` (trunks) or
`` '[' . $peer['name'] . "]\n" `` (extensions) as raw, unguarded section
headers — the one place in this whole task where a user-controlled
field is *still* directly a section identifier in a live generator.

**Fix:** the controller-level validation added for F12/F13 is the
*primary* control here too — since F15 consumes the same already-
validated `peers`/`trunks` data, no newline/`;`-bearing value or
unsafe-shaped `exten`/`defaultuser` can ever reach this generator via
the supported UI once F12/F13's checks are in place. On top of that,
`snep/lib/Snep/InterfaceConf.php` (`loadConfFromDb()`) gets the same
defense-in-depth discipline as the other two generators: before
building any line for a peer, it checks `name`/`defaultuser`/`context`/
`callerid`/`host`/`secret`/`fromuser`/`fromdomain` via
`Snep_PjsipConf::isSafeConfigValue()` and, on failure, `error_log()`s a
warning and `continue`s to the next peer — skipping just that row
rather than corrupting the whole file (this file predates the
exception-based skip convention the PJSIP generators use, so a plain
`continue` was used instead of introducing that pattern into
otherwise-untouched legacy code).

**Before/after:** creating a `technology=sip` extension with a
newline-bearing `name` is now rejected at the exact same controller
boundary as a `technology=pjsip` one (proven live in the focused suite);
a legitimate `technology=sip` extension still generates
`[10973]`/`type=friend`/etc. in `snep-sip.conf` exactly as before.

**Also noted, not fixed (out of this task's scope):** `Snep_InterfaceConf.php:94`
(current line number) has a second, unrelated raw-SQL-interpolation
sink — `` $db->select()->from('trunks')->where("name = {$peer['name']}") ``
— the same root-cause-B pattern TASK-0026C fixed elsewhere, but this
file was never in that task's F7–F11 scope. Documented as separate,
deferred SQL-injection debt; not a configuration-injection concern and
not addressed here.

## 6. Raw params / dynamic-key analysis (Phase 5)

Searched every generator and its controllers
(`Snep_PjsipConf`/`Snep_PjsipTrunkConf`/`Snep_PjsipTransportConf`/
`Snep_InterfaceConf`, `ExtensionsController`/`TrunksController`/
`PjsipTransportsController`) for any `params`/`options`/`advanced`/
`config`-style free-form or dynamic-key mechanism. **None exists.**
Every directive *name* in every generator (`callerid=`, `context=`,
`type=`, `host=`, etc.) is a fixed string literal hardcoded in the
generator's own PHP source; only the *values* are ever dynamic. The
FREEFORM and DIRECTIVE_NAME categories from this task's own
classification scheme are therefore not applicable to this codebase —
there is no user-configurable PJSIP option-key surface to allowlist,
confirmed by direct code search rather than assumed.

## 7. Files changed

```
snep/lib/Snep/PjsipConf.php                                   new isSafeConfigValue(); F12 defense-in-depth
snep/lib/Snep/PjsipTrunkConf.php                               F13 defense-in-depth
snep/lib/Snep/InterfaceConf.php                                F15 defense-in-depth
snep/modules/default/controllers/ExtensionsController.php     F12 primary validation
snep/modules/default/controllers/TrunksController.php         F13 primary validation
scripts/pjsip-config-security-smoke-test.sh                    new -- Phase 9 focused harness
Makefile                                                        + pjsip-config-security-smoke target
scripts/regression.sh                                           + pjsip-config-security suite, after shell-security
```

`snep/lib/Snep/PjsipTransportConf.php` and
`PjsipTransportsController.php` (F14) were **not modified** — already
correct. No TASK-0026A/B/C/D file was touched.

## 8. Focused security smoke — `scripts/pjsip-config-security-smoke-test.sh`

Built on `scripts/lib/harness.sh` (TASK-0027 conventions). Registered as
`make pjsip-config-security-smoke` and as the `pjsip-config-security`
stage in `make regression`, immediately after `shell-security` and
before `authorization-coverage`.

Preflight grants exactly the three real permissions
(`default_extensions_write`, `default_trunks_write`,
`default_pjsip-transports_write`/`_read`) a non-superuser pilot role
would need to a dedicated `task0026e-restricted` fixture user (after
confirming a zero-permission user is denied on all three `/add`
boundaries), and exercises every F12–F15 body through that account.

Injection payloads are sent via curl's `--data-urlencode`, one field at
a time (`post_fields()`), rather than a hand-built query string — this
is what lets a field carry a literal `\r\n` correctly percent-encoded
on the wire, so PHP's `$_POST` decodes the exact original bytes
server-side.

Per finding: a normal legitimate object is created via the real UI
flow and its generated config is inspected for the expected section(s)
and directive(s); a newline/section-shaped value targeting a unique,
harmless marker (`task0026e-injected` / `task0026e_marker=yes`) is
submitted; the request is confirmed rejected before persistence (or,
for F14, was already rejected by pre-existing validation); the marker
is confirmed absent from every one of the five generated config files
(`senma-pjsip.conf`, `senma-pjsip-trunks.conf`,
`senma-pjsip-transports.conf`, `snep-sip.conf`, `snep-iax2.conf`) after
a fresh regenerate; Asterisk's live `pjsip show endpoint
task0026e-injected` is confirmed to report "Unable to find object";
the app stays healthy (no new PHP Fatal Errors); every fixture is
cleaned up via the same supported HTTP paths (`extensions/remove`,
`trunks/remove`, `pjsip-transports/remove/id/<id>`) other suites in
this project already use. **Result: PASS, 27/27**, reproduced across
multiple independent runs with clean fixture teardown each time.

A pre-existing, already-documented (TASK-0026C) orphaned-trunk-type-
peers-row issue was re-encountered while building this suite
(`TrunksController::preparePost()`'s `MAX(name)+1`-or-`"1"` auto-naming
collides with a stale `peer_type='T'` row left by an interrupted prior
run) — the same `sweep_orphaned_trunk_peers()` precaution TASK-0026C's
own `sql-security-smoke-test.sh` established was reused here verbatim,
via the same supported `extensions/remove` HTTP path, never a raw SQL
delete.

## 9. Post-remediation execution audit (Phase 11)

Repeating the targeted search for raw config-generation patterns across
every touched file:

- `Snep_PjsipConf.php`: `[$name]`/`[$auth]` section headers — safe
  identifier (numeric-only, enforced by the controller); every value
  (`context`/`callerid`/`secret`) — validated value, both at the
  controller boundary and again here. **No unexplained pattern
  remains.**
- `Snep_PjsipTrunkConf.php`: `[$name]`/`[$auth]`/`[$identify]`/
  `[$registration]` section headers — safe identifier (`trunks.id`,
  never user input); every value (`context`/`callerid`/`from_user`/
  `from_domain`/`secret`/`host`/`defaultuser`) — validated value, both
  boundaries. **No unexplained pattern remains.**
- `Snep_PjsipTransportConf.php`: `[$name]` section header and every
  value — all validated value/identifier/host/port/CIDR, entirely by
  pre-existing TASK-0019/0020 code. **No unexplained pattern remains;
  no code touched.**
- `Snep_InterfaceConf.php`: `[$peer['defaultuser']]`/`[$peer['name']]`
  section headers and every value field — validated at the controller
  boundary (primary) and re-checked here (defense-in-depth). The
  separate, unrelated raw-SQL `where("name = {$peer['name']}")` sink at
  line 94 is classified `legacy/deferred` (root-cause B, not C; see
  §5).

There is no remaining `$requestValue . "\n"`, `"[" . $requestValue . "]"`,
or `$key . "=" . $value` construction with an attacker-controlled
syntax component left unexplained in F12–F15 scope.

## Validation

- `php -l` on every touched file: clean.
- `make lint`: PASS (18 shell scripts, up from 17).
- `make pjsip-config-security-smoke`: PASS, 27/27, reproduced across
  multiple independent runs with clean fixture teardown.
- `make regression`, first run: **16/16 PASS**, no BLOCKED, no
  INCONCLUSIVE.
- `make regression`, second consecutive run (this task changed
  application code, not only an isolated suite, so both runs were
  required regardless of whether flakiness appeared): **16/16 PASS**,
  byte-for-byte the same result.
- Health: `app`/`asterisk`/`db`/`provider` all `Up`/`healthy`;
  `res_pjsip.so` loaded and `Running`; AMI responsive; the 3 baseline
  PJSIP transports (`tcp`, `udp`, `wss`) intact; ODBC DSN `snep`
  connected; 0 active channels; 1 PHP Fatal Error present, unchanged
  from before this task's work and matching the count already
  documented as a pre-existing, unrelated PHP 8.4 Zend upload-validator
  bug in `docs/tasks/0026d-shell-execution-hardening.md` — not a new
  regression. `res_pjsip_config_wizard.c: Unable to load config file
  'pjsip_wizard.conf'` appears repeatedly in Asterisk's own log
  (30,845 occurrences across this whole session) — confirmed
  pre-existing and unrelated: this project has never referenced
  `pjsip_wizard.conf` anywhere in its own Docker/Asterisk configuration,
  it is a stock, unused, optional PJSIP module Asterisk ships and warns
  about on every reload regardless of any of this task's changes; not a
  parse error in any file this task's generators produce.
- Cleanup: zero `task0026e`-named residue anywhere (peers, trunks,
  pjsip_transports tables; every generated config file); no orphaned
  `peer_type='T'` rows; no leftover smoke processes.
- `git diff --check`: clean.
- `git diff --stat` / `git status --short`: exactly the 7 modified
  files plus the new smoke script listed in
  [Files changed](#7-files-changed) — full diff reviewed line-by-line,
  every change is a validation addition; no unrelated refactoring, no
  TASK-0026A/B/C/D file touched.

## Deferred — not in scope here

- **The PJSIP-only legacy-cleanup/removal decision for `technology=sip`/
  `iax2`.** F15 was fixed narrowly (the injection defect), not removed
  or migrated. Whether `chan_sip`/`chan_iax2` provisioning should remain
  selectable at all is a Product Readiness / architecture question this
  task's own Phase 12 instruction explicitly excludes ("Do not perform
  the full SIP→PJSIP product migration in TASK-0026E").
- **`Snep_InterfaceConf.php:94`'s raw-SQL `where("name = {$peer['name']}")`.**
  A genuine, separate SQL-injection finding (root-cause B), not a
  configuration-injection one; never in TASK-0026C's F7–F11 scope
  either. Documented here as newly-confirmed debt for a future
  SQL-hardening task.
- **`SoundFilesController`/`MusicOnHoldController`-adjacent debt from
  TASK-0026D** and **`sounds.secao`/`Zend_File_Transfer_Adapter_Http`
  PHP 8.4 bugs** already documented in
  `docs/tasks/0026d-shell-execution-hardening.md` are unaffected by and
  unrelated to this task; not re-litigated here.
