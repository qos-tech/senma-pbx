# TASK-0028Y — PJSIP parameter-coverage corrections and regression-coverage closure

## Status

Resolved. All four parameter gaps and the closeable regression gaps
implemented, live-verified against a running `make dev` environment, and
covered by a new permanent regression suite. Two consecutive full
`make regression` runs PASS (26/26 suites each).

Originates directly from the completed PJSIP Completeness Architecture
Review (TASK-0028W): SENMA controls that expose a UI, persist a value, but
have no corresponding PJSIP runtime effect (`field visible + value
persisted + runtime ignores it`).

## Objective

Close the four confirmed parameter gaps (trunk qualify, extension/trunk
NAT `auto_*`, extension call-limit, trunk dialmethod) and the five
regression-coverage gaps TASK-0028W identified, each classified as
`IMPLEMENTED`, `REMOVED_FROM_SUPPORTED_CONTROL`,
`PRESERVED_AS_LEGACY_COMPATIBILITY`, or `DEFERRED_WITH_BLOCKER`. No
silently-ignored state may remain.

---

## 1. Trunk qualify

**OLD PRODUCT CONTRACT**: "Delay Qualification" (yes/no/specify-a-value)
on the trunk form is a real chan_sip-era control -- `Snep_InterfaceConf.php`
passes `peers.qualify` straight through to chan_sip's own `qualify=`
directive for every legacy trunk technology (`InterfaceConf.php:174,223`).

**CURRENT BUG**: `Snep_PjsipTrunkConf::renderTrunk()` never read
`peers.qualify` at all -- the generated AOR (`[trunk-<id>]`, `type=aor`)
had no `qualify_frequency=` line, ever, for any native PJSIP trunk.
Asterisk therefore never sent OPTIONS to probe trunk liveness, regardless
of what an admin configured. The extension generator
(`Snep_PjsipConf::renderExtension()`) already implements this correctly
(TASK-0011) -- trunks were the one gap.

**DECISION**: `IMPLEMENTED`. Direct PJSIP mapping exists
(`qualify_frequency` on the AOR); no product/UI change needed
(`senma-asterisk-pjsip-engineer`, no architecture/product escalation
required -- this makes an existing control finally work as presented).

**IMPLEMENTATION** (`snep/lib/Snep/PjsipTrunkConf.php::renderTrunk()`):

- `qualify === 'yes'` -> `qualify_frequency=60` (reuses the extension
  generator's own chosen-default convention verbatim, for consistency --
  not independently derived).
- `qualify === 'no'` / `''` / `NULL` -> `qualify_frequency=0` (disabled).
- `qualify` a digits-only string (the "specify" case, carried over from
  chan_sip's own `qualify=<milliseconds>` directive) -> converted
  ms -> seconds, `round()`, with a 1s floor for any positive input so a
  sub-second value doesn't silently round to `0` (disabled). Direct
  pass-through was rejected: PJSIP's `qualify_frequency` is documented in
  *seconds*, so a legacy `"2000"` (2s in chan_sip) would otherwise become
  a 2000-*second* (33 minute) interval -- silently defeating the
  control's presented purpose.
- Anything else (unreachable through the real UI after the controller
  fix below) skips the whole trunk with an `error_log()` entry, matching
  the existing unsafe-value discipline in the same method.

`TrunksController::preparePost()`: added digit-only validation
(1-5 digits, matching `peers.qualify char(5)`) for the "specify" value at
submission time -- previously wholly unvalidated (harmless only because
nothing consumed it). Rejects with a translated error instead of either
a raw SQL fatal (>5 digits) or a silently-skipped trunk (non-numeric) at
generation time.

**RUNTIME PROOF**: live-verified against a real trunk created through the
HTTP flow (`qualify=specify`, `qualify_value=2000`), against a running
`make dev` environment:

```text
$ asterisk -rx 'pjsip show aor trunk-1121'
 ParameterName        : ParameterValue
 ============================================
 ...
 qualify_frequency    : 2
 ...
```

Generated `senma-pjsip-trunks.conf` for the same trunk:

```text
[trunk-1121]
type=aor
contact=sip:203.0.113.10:5060
qualify_frequency=2
```

The plain `qualify=yes` case (`trunk-smoke-test.sh`'s own existing
fixture) is separately verified live at `qualify_frequency: 60`. An
actual OPTIONS probe was not separately packet-captured -- `qualify_frequency`
is Asterisk's own documented, single mechanism for enabling periodic
OPTIONS qualification (`res_pjsip_pubsub`/`res_pjsip_outbound_registration`'s
own behavior once this AOR field is non-zero); the live parameter dump
above is the direct, authoritative confirmation Asterisk itself received
and applied the value, which is what this gap needed proven.

**REGRESSION PROOF**: `scripts/pjsip-lifecycle-smoke-test.sh` (new, Part
A) proves the "specify" case end to end, generated config + live
Asterisk, on a registrationless fixture. `scripts/trunk-smoke-test.sh`
(existing, extended) now additionally asserts `qualify_frequency=60`
(generated config + live `pjsip show aor`) on its own pre-existing
`qualify=yes` fixture, so both value shapes have permanent coverage.
Both suites: PASS, twice consecutively (see Validation).

---

## 2. Extension NAT `auto_*`

**OLD PRODUCT CONTRACT**: chan_sip's `nat=auto_force_rport`/
`auto_comedia` meant "decide based on whether the incoming request
already carries an `rport` parameter" -- a genuine runtime auto-detection
mode with no PJSIP equivalent (`force_rport`/`rtp_symmetric` are plain
booleans). TASK-0010 (architecture) floated collapsing `auto_*` into the
same boolean as its direct sibling (`auto_force_rport` -> `force_rport=yes`,
`auto_comedia` -> `rtp_symmetric=yes`) as an explicit, flagged product
decision; TASK-0011 (implementation) deliberately deferred that decision
rather than infer it, leaving both checkboxes visibly present but
functionally inert for any extension using only the `auto_*` flags
(documented explicitly in both tasks' own docs).

**CURRENT BUG**: the deferred decision was never made -- the checkboxes
remained inert indefinitely, presenting a NAT-accommodation control that
silently does nothing for an `auto_*`-only entity.

**DECISION**: `IMPLEMENTED`. Adopts TASK-0010's originally-floated
mapping. Per the architecture-review authorization for this task and the
explicit product-designer escalation rule ("if implementation simply
makes an existing control finally work as already presented, product
review is not required") -- this collapses a previously-inert checkbox
into the accommodation the UI already visually groups it with, it does
not remove, rename, or repurpose any control.

**IMPLEMENTATION** (`snep/lib/Snep/PjsipConf.php::renderExtension()`):
`force_rport` now derives from `force_rport OR auto_force_rport`;
`rtp_symmetric` from `comedia OR auto_comedia`.

**RUNTIME PROOF**: live-verified. An extension created with
`nat_auto_force_rport`/`nat_auto_comedia` only (no direct flags):

```text
$ asterisk -rx 'pjsip show endpoint 1198'
 ParameterName                      : ParameterValue
 ...
 force_rport                        : true
 ...
 rtp_symmetric                      : true
```

Updating the same extension to `nat_no` only correctly flips both back
to `false` live, confirming the mapping is live/reactive, not a
create-time-only artifact.

**REGRESSION PROOF**: `scripts/pjsip-lifecycle-smoke-test.sh` (new, Part
B) creates an extension with `auto_*` only, asserts
`force_rport=yes`/`rtp_symmetric=yes` in both the generated config and
live `pjsip show endpoint`, then updates it to explicit `no` and
re-asserts the flip in both places. PASS, twice consecutively.

---

## 3. Trunk NAT `auto_*`

**OLD PRODUCT CONTRACT**: identical UI/DB shape to extensions (same
`nat_*` checkbox set, same comma-joined `peers.nat` column, TASK-0014 §13
confirmed no trunk-specific semantic difference).

**CURRENT BUG**: `Snep_PjsipTrunkConf::renderTrunk()` had the identical
gap as the pre-fix extension generator -- `auto_force_rport`/
`auto_comedia` tokens were never checked.

**DECISION**: `IMPLEMENTED`, identical mapping and rationale as extensions
(§2), applied so the two supported entity types do not diverge on an
implemented-vs-not basis for the same product concept.

**IMPLEMENTATION** (`snep/lib/Snep/PjsipTrunkConf.php::renderTrunk()`):
same `OR auto_*` collapse as the extension generator.

**RUNTIME PROOF**: live-verified on the same registrationless trunk
fixture used for §1 (`nat_auto_force_rport`+`nat_auto_comedia` only):

```text
$ asterisk -rx 'pjsip show endpoint trunk-1121'
 ...
 force_rport                        : true
 ...
 rtp_symmetric                      : true
```

Generated config's endpoint stanza: `force_rport=yes`, `rtp_symmetric=yes`.

**REGRESSION PROOF**: `scripts/pjsip-lifecycle-smoke-test.sh` (new, Part
A) -- same fixture as §1's qualify/registrationless proof, asserting
`force_rport=yes`/`rtp_symmetric=yes` in both generated config and live
`pjsip show endpoint`. PASS, twice consecutively.

---

## 4. Extension call-limit

**OLD PRODUCT CONTRACT**: chan_sip's native per-peer `call-limit=`
directive capped concurrent calls at the channel-driver level. SENMA's
extension form has always exposed "Simultaneous Call Limit"
(`calllimit`), persisted to `peers.call-limit`, unconditionally (not
technology-gated in the UI).

**CURRENT BUG**: since TASK-0028A locked extension creation/edit to
`technology=pjsip` exclusively (`ExtensionsController.php:633-638` --
new extensions are always `pjsip`; editing a legacy extension is
rejected outright until migrated), **every reachable state** of this
field is PJSIP. The only consumer of `peers.call-limit` is
`Snep_InterfaceConf.php`'s chan_sip/IAX2 generator, which never
processes a `PJSIP/`-prefixed `canal` row. The value an admin sets has
therefore been unconditionally inert in every state the real UI can
reach.

Traced whether a native PJSIP equivalent exists: res_pjsip has no
endpoint-level concurrent-call cap comparable to chan_sip's `call-limit`.
The closest analogue would be a new dialplan-level `GROUP()`/
`GROUP_COUNT()` counting mechanism -- this is explicitly a **new
telephony capability** (SENMA's dialplan never implemented this; it was
always delegated to the channel driver), and is listed as out of scope
for this task ("no new telephony capabilities not already exposed").

**DECISION**: `REMOVED_FROM_SUPPORTED_CONTROL` (senma-product-designer
review, TASK-0028Y -- full workflow trace and rationale below). No safe,
direct, evidence-backed PJSIP equivalent exists without inventing new
product behavior; the codebase's own bulk-provisioning flow
(`multiaddAction()`) already treats this exact column as a fixed,
non-user-facing `'1'` default with **no UI field at all**
(`ExtensionsController.php:1229`, pre-existing, unrelated to this task) --
this decision brings the single add/edit form in line with a pattern the
product already established elsewhere for the identical column.
`peers.call-limit` is **not** dropped (no schema change): legacy,
non-PJSIP historical rows (if any survive an environment predating the
PJSIP lockdown) are unaffected, since `Snep_InterfaceConf.php`'s
consumption of the column for those rows is untouched.

**Product-designer review summary**: user goal is capping concurrent
calls per extension. Current workflow presented an always-visible,
unvalidated number field with zero technology-conditional messaging and
no indication the value is never enforced -- "invalid configuration
appearing successful," a HIGH-severity design-debt class per this
skill's own classification. Target workflow: field removed entirely
(no conditional hide needed -- extension technology has no other
reachable state to preserve visibility for; the technology selector
itself is already a fixed hidden input, not a live dropdown, unlike
trunks). Backend feasibility confirmed with the PJSIP engineer role
before deciding (no invented runtime capability).

**IMPLEMENTATION**:

- `snep/modules/default/views/scripts/extensions/addedit.phtml`: removed
  the "Simultaneous Call Limit" form-group entirely.
- `snep/modules/default/controllers/ExtensionsController.php`: `execAdd()`
  no longer reads `$formData["calllimit"]` (no longer submitted); writes
  a fixed `'1'`, matching `multiaddAction()`'s own established default
  for the same column.

**RUNTIME PROOF**: N/A (control removed, not runtime-mapped) -- proof is
that the field no longer appears and the column keeps receiving a
deterministic value regardless of input. Live-confirmed: creating an
extension with no `calllimit` POST key at all (the new, post-removal
shape) persists `peers.call-limit = '1'` and creates successfully.

**REGRESSION PROOF**: `call-smoke-test.sh`/`trunk-smoke-test.sh`/
`transport-smoke-test.sh`'s existing extension fixtures still post a
(now-ignored) `calllimit=1` key -- confirmed harmless (PHP silently
ignores an unread POST key) by all three suites' continued PASS, twice
consecutively, with zero changes required to those suites. No suite
needed weakening.

---

## 5. dialmethod

**OLD PRODUCT CONTRACT**: for legacy SIP/IAX2 trunks, `dialmethod=NOAUTH`
selected an unauthenticated (`PBX_Asterisk_Interface_{SIP,IAX2}_NoAuth`)
outbound-dial interface (`PBX_Trunks.php:92`) and suppressed the
generated `register =>` line (`Snep_InterfaceConf.php:165,205,207`) --
a real, functional control for those technologies.

**Traced (repo-wide)**: `PBX_Trunks::get()`'s `PJSIP` branch explicitly
does **not** special-case `dialmethod` (documented inline,
`PBX_Trunks.php:120-123`, TASK-0015's own deliberate scope note).
`Snep_PjsipTrunkConf::renderTrunk()` never reads `trunks.dialmethod` at
all -- the decision to emit a registration object is driven entirely by
`reverse_auth` (TASK-0014 §4/§17/§20, a **deliberate**, already-documented
architecture choice, not an oversight). `TrunksController::preparePost()`
only re-interprets `dialmethod` inside its (unreachable-since-TASK-0028B)
`SIP`/`IAX2` branches -- every reachable trunk save today is
`technology ∈ {pjsip, pjsip_external}` (the function's own top-of-body
guard rejects anything else), so the legacy `NOAUTH` channel-string branch
can never execute for a trunk created or edited through the real UI.

**CLASSIFICATION**: `DEAD_SUPPORTED_CONTROL` -- for the currently
save-able/editable trunk product surface (pjsip/pjsip_external, the only
two reachable technologies), `dialmethod`'s only remaining UI presentation
(the "Dial Method" radio group, visible whenever `technology=pjsip`) has
zero effect. It remains `PRESERVED_AS_LEGACY_COMPATIBILITY` at the schema/
generator level for any pre-existing legacy SIP/IAX2 trunk row that might
still exist from before the technology lockdown (`Snep_InterfaceConf.php`/
`PBX_Trunks::get()`'s SIP/IAX2 branches are untouched and still honor it)
-- though such a row can no longer be *saved* through this controller
either way.

**DECISION**: `REMOVED_FROM_SUPPORTED_CONTROL` (senma-product-designer
review, TASK-0028Y). No new PJSIP mapping was invented for `NOAUTH`
(e.g. conditionally suppressing `outbound_auth=`) -- introducing a second
registration/auth-gating meaning that could interact incoherently with
the already-authoritative `reverse_auth` field would be exactly the kind
of unevidenced new mapping this task and CLAUDE.md both prohibit.
`trunks.dialmethod` is **not** dropped (no schema change; still written
on every save, unchanged, for historical/legacy-row compatibility).

**Product-designer review summary**: hidden via the exact same
`isPjsip`-conditional `showDiv()` pattern already established (TASK-0015)
for `trunk_type_group`/`trunk_insecure_group`/`trunk_calllimit_group` --
those three fields were found, in the course of this same review, to
already be dead-when-visible for the identical reason (technology is
fully locked to pjsip/pjsip_external for any save, and `#ip` -- the div
containing all four -- is never shown at all for `pjsip_external`).
Conditional hide (not outright deletion, unlike extension call-limit)
matches this existing, already-approved precedent, since trunks (unlike
extensions) have a live, if two-valued, technology selector.

**IMPLEMENTATION**:

- `snep/modules/default/views/scripts/trunks/addedit.phtml`: added
  `id="trunk_dialmethod_group"` to the "Dial Method" form-group; added it
  to `showDiv()`'s `isPjsip`-hide list alongside its three siblings.
- No controller/generator change -- `dialmethod` continues to be
  persisted exactly as before; only its presentation for `pjsip` is
  removed.

**RUNTIME PROOF**: N/A (already-confirmed-dead control, no runtime
mapping introduced).

**REGRESSION PROOF**: `trunk-smoke-test.sh`/`pjsip-lifecycle-smoke-test.sh`
still post `dialmethod=normal` (a hidden-but-still-submitted field, same
as its `trunk_calllimit_group` sibling) -- both suites PASS unchanged,
twice consecutively, confirming the hide is purely presentational and
does not block trunk create/edit.

---

## Regression closure

### 1. Registrationless PJSIP trunk (reverse_auth=0)

Closed by `scripts/pjsip-lifecycle-smoke-test.sh` (new, Part A), against
a real trunk created via `TrunksController::addAction()` with
`reverse_auth` not sent:

- endpoint + auth + static-contact AOR generated (`senma-pjsip-trunks.conf`
  contains `[trunk-<id>]`/`[trunk-<id>-auth]`, both live via
  `pjsip show endpoint`/`pjsip show aor`);
- **no** `[trunk-<id>-registration]` section generated, and
  `pjsip show registrations outbound` correctly lists nothing for it
  (live-confirmed both before AND after this task's other fixes, isolating
  this from qualify/NAT);
- config loads in Asterisk (reload succeeds, confirmed via the endpoint/aor
  visibility checks above, bounded-retried per TASK-0027's own established
  reload-non-atomicity finding);
- update: editing the same trunk to enable `reverse_auth` makes a real
  `[trunk-<id>-registration]` section appear in both the generated config
  and live `pjsip show registrations outbound` -- proving the behavior is
  driven live by `reverse_auth`, not fixed at creation time;
- delete: proven in item 4 below (same fixture, same script, immediately
  following).

No live call fixture was added for this specific trunk (task wording:
"if a live fixture is available" -- treated as optional here) --
TASK-0015/0016's own `trunk-smoke-test.sh` already proves a full
registered-trunk call flow end to end in both directions; duplicating
that against a second, unreachable-by-design host (`203.0.113.10`,
RFC 5737 TEST-NET-3) would prove nothing new.

PASS, twice consecutively.

### 2. Extension update beyond transport_id

Closed by `scripts/pjsip-lifecycle-smoke-test.sh` (new, Part B): an
extension created with NAT `auto_force_rport`/`auto_comedia` only is
updated (same `ExtensionsController::editAction()` HTTP flow
`transport-smoke-test.sh` already exercises for `transport_id`) to NAT
`no` only. Both the generated config's endpoint stanza and live
`pjsip show endpoint` are asserted to flip from
`force_rport=yes`/`rtp_symmetric=yes` to
`force_rport=no`/`rtp_symmetric=no`. This is a field this task itself
implemented (§2), so the update proof and the parameter's own runtime
proof reinforce each other rather than being redundant. PASS, twice
consecutively.

### 3. Extension delete cleanup

Traced the production delete path (`ExtensionsController::removeAction()`):
`Snep_Extensions_Manager::remove()` (DB delete) ->
`Snep_InterfaceConf::loadConfFromDb()` ->
`Snep_PjsipTransportConf::loadConfFromDb()` ->
`Snep_PjsipConf::loadConfFromDb()` (full-stateless-rewrite regenerate,
then `module reload res_pjsip.so`). The generator's full-rewrite property
means a deleted row is structurally absent from the regenerated file, and
Asterisk's own sorcery reload removes any object no longer present in the
reloaded config. No functional gap found here -- this was a **coverage**
gap (existing suites asserted only the HTTP 302 redirect), not a
production defect.

Closed by `scripts/pjsip-lifecycle-smoke-test.sh` (new, Part B,
step 11): after deleting the Part B extension fixture, explicitly
(bounded-poll) asserts:

- generated `senma-pjsip.conf` no longer contains `[<ext>]`;
- live `pjsip show endpoint <ext>` / `pjsip show aor <ext>` both report
  "Unable to find object";
- `peers` row count for that name is `0`.

Live-verified manually first (see below), then encoded as permanent
coverage. PASS, twice consecutively.

### 4. Trunk delete cleanup

Same pattern, traced via `TrunksController::removeAction()`:
`Snep_Trunks_Manager::remove()`/`removePeers()` ->
`Snep_InterfaceConf::loadConfFromDb()` ->
`Snep_PjsipTransportConf::loadConfFromDb()` ->
`Snep_PjsipTrunkConf::loadConfFromDb()`. Same conclusion: no functional
gap, coverage gap only (existing `trunk-smoke-test.sh` cleanup also only
implicitly relied on the HTTP 302 inside its harness cleanup pass, never
asserting live/generated absence).

Closed by `scripts/pjsip-lifecycle-smoke-test.sh` (new, Part A, step 8),
against the same registrationless-then-registered trunk fixture from
item 1 -- explicit (bounded-poll) assertions after delete:

- generated `senma-pjsip-trunks.conf` contains no `trunk-<id>*` section
  at all;
- live `pjsip show endpoint`/`pjsip show aor` both "Unable to find object";
- live `pjsip show auths` no longer lists `trunk-<id>-auth`;
- live `pjsip show registrations outbound` no longer lists
  `trunk-<id>-registration` (this fixture had one, from the update step);
- live `pjsip show identifies` no longer lists `trunk-<id>-identify`;
- `trunks` and `peers` row counts are both `0`.

Manually verified first, live, against the real environment:

```text
$ asterisk -rx 'pjsip show endpoint trunk-1121'
Unable to find object trunk-1121.
$ asterisk -rx 'pjsip show aor trunk-1121'
Unable to find object trunk-1121.
$ asterisk -rx 'pjsip show auths' | grep trunk-1121
(no output)
$ asterisk -rx 'pjsip show registrations outbound'
No objects found.
$ asterisk -rx 'pjsip show identifies'
No objects found.
```

then encoded as permanent coverage. PASS, twice consecutively.

### 5. macro-dialpeer / ramais-agentes path

**Re-verified, not re-derived**: TASK-0028C's live include-graph audit
(`docs/tasks/0028c-pjsip-legacy-runtime-closure.md` §1/§7) already found
`extensions.conf`'s `[ramais-agentes]` context **orphaned** -- no
producer sets `context=ramais-agentes` (`ExtensionsController` hardcodes
`context='default'` for every extension it creates or edits, confirmed
still true at `ExtensionsController.php:615`). Repo-wide search
(`grep -rl "ramais-agentes"`) confirms the string appears **only** in the
static `extensions.conf` dialplan template itself -- no PHP/view code
anywhere offers it as a settable value. `macro-dialpeer` itself **is**
reachable (TASK-0028C §6: the busy-callback feature's spooled `.call`
file dials into it, and its own `Dial(${INTERFACE},...)` is already
technology-agnostic/PJSIP-resolving) -- it is specifically the
`[ramais-agentes]` context that has no live producer.

**CONCLUSION**: `ramais-agentes` remains genuinely orphaned/unreachable
by any current supported configuration. Per this task's own instruction
("If orphaned/unreachable... document it as such; do not fabricate a
fake supported workflow merely to exercise it") and CLAUDE.md's
"Do not reopen TASK-0028C unless a real reachable defect is found" -- no
defect was found (TASK-0028C already closed the one real hard-error
risk, the unregistered `SIPAddHeader`, converting it to
`PJSIP_HEADER(add,...)`), so no regression coverage is added for this
path and TASK-0028C is not reopened. This finding is a re-confirmation
of already-documented, unchanged residual debt
(TASK-0028C §13), not a new one.

---

## Changes

### PRODUCTION

- `snep/lib/Snep/PjsipTrunkConf.php` -- `qualify_frequency=` generation
  (gap #1); `auto_force_rport`/`auto_comedia` NAT collapse (gap #3).
- `snep/lib/Snep/PjsipConf.php` -- `auto_force_rport`/`auto_comedia` NAT
  collapse (gap #2).
- `snep/modules/default/controllers/TrunksController.php` -- digit-only
  validation for the "specify" qualify value.
- `snep/modules/default/controllers/ExtensionsController.php` -- fixed
  `'1'` call-limit write, no longer reads removed form field.
- `snep/modules/default/views/scripts/extensions/addedit.phtml` --
  removed "Simultaneous Call Limit" field.
- `snep/modules/default/views/scripts/trunks/addedit.phtml` -- hid "Dial
  Method" for `technology=pjsip`.

### TEST

- `scripts/pjsip-lifecycle-smoke-test.sh` -- new suite: registrationless
  trunk lifecycle (create/generated-config/live-state/update/delete),
  extension update-beyond-transport_id, extension delete-cleanup,
  qualify "specify" + NAT `auto_*` runtime proof (trunk and extension).
- `scripts/trunk-smoke-test.sh` -- added `qualify_frequency=60` assertion
  (generated config + live `pjsip show aor`) to the suite's own existing
  `qualify=yes` fixture.
- `Makefile` -- new `pjsip-lifecycle-smoke` target + `.PHONY` entry.
- `scripts/regression.sh` -- new suite wired in immediately after
  `pjsip-external-trunk-smoke`, before `transport-smoke`.

### DOCUMENTATION

- This file.

## Validation

- **Qualify runtime proof**: §1 above (`qualify_frequency=2` live for
  `specify`=2000ms; `qualify_frequency=60` live for `yes`, both on real
  trunks).
- **NAT runtime proof**: §2/§3 above (`force_rport`/`rtp_symmetric=true`
  live, extension and trunk, `auto_*`-only fixtures; confirmed reactive
  on update too).
- **call-limit/dialmethod decision proof**: §4/§5 above (field
  removed/hidden; existing suites' now-ignored POST keys confirmed
  harmless; no suite weakened).
- **Registrationless trunk proof**: Regression closure §1.
- **Extension update proof**: Regression closure §2.
- **Extension deletion proof**: Regression closure §3.
- **Trunk deletion proof**: Regression closure §4.
- **macro-dialpeer result**: Regression closure §5 -- orphaned,
  re-confirmed, no coverage fabricated, TASK-0028C not reopened.
- **Target suites run individually** (before the full regression, all
  PASS): `pjsip-lifecycle-smoke` (new, PASS 36/36 twice consecutively),
  `call-smoke` (18/18), `trunk-smoke` (25/25, includes the new qualify
  assertions), `pjsip-external-trunk-smoke` (19/19), `transport-smoke`
  (64/64) -- zero regressions from this task's production changes.
- **`make lint`**: PASS (270 PHP files/0 syntax errors, 33 shell scripts,
  3 resources.xml, `git diff --check` clean).
- **`make regression` run 1**: PASS -- 26/26 suites, including the new
  `pjsip-lifecycle-smoke`.
- **`make regression` run 2**: PASS -- 26/26 suites, identical matrix.
- **`git diff --check`**: PASS (no whitespace errors).
- **`git status --short`**:

```text
 M Makefile
 M scripts/regression.sh
 M scripts/trunk-smoke-test.sh
 M snep/lib/Snep/PjsipConf.php
 M snep/lib/Snep/PjsipTrunkConf.php
 M snep/modules/default/controllers/ExtensionsController.php
 M snep/modules/default/controllers/TrunksController.php
 M snep/modules/default/views/scripts/extensions/addedit.phtml
 M snep/modules/default/views/scripts/trunks/addedit.phtml
?? docs/tasks/0028y-pjsip-parameter-regression-closure.md
?? scripts/pjsip-lifecycle-smoke-test.sh
```

## Remaining debt

- `[ramais-agentes]`'s `PJSIP_HEADER` conversion still has no live
  2-endpoint proof (TASK-0028C §13, unchanged, out of scope here -- the
  context remains orphaned, so no defect to fix).
- `Snep_Trunks_Manager::getTrunkLog()`'s backtick/shell-exec bug
  (dead code, zero callers, TASK-0014 §16 / CLAUDE.md's own worked
  example) -- untouched, out of scope.

TASK-0028Z/0029A/0029B are not pulled into this task.

## Recommendation

APPROVE.

## Proposed commit

Narrowest coherent split, three commits:

1. `fix(pjsip): implement trunk qualify_frequency and NAT auto_* mapping`
   -- `snep/lib/Snep/PjsipTrunkConf.php`, `snep/lib/Snep/PjsipConf.php`,
   `snep/modules/default/controllers/TrunksController.php` (qualify
   validation only).
2. `fix(pjsip): remove dead call-limit and dialmethod controls from the
   supported product surface` -- `snep/modules/default/controllers/ExtensionsController.php`
   (call-limit write), `snep/modules/default/views/scripts/extensions/addedit.phtml`,
   `snep/modules/default/views/scripts/trunks/addedit.phtml`.
3. `test(pjsip): add lifecycle/parameter regression coverage for
   TASK-0028Y` -- `scripts/pjsip-lifecycle-smoke-test.sh`,
   `scripts/trunk-smoke-test.sh`, `Makefile`, `scripts/regression.sh`,
   plus this documentation file.

Not committed automatically -- awaiting authorization per CLAUDE.md's
commit policy.
