# TASK-0032 — Transport + Shared Runtime UX Foundation

Lead: `senma-product-designer`. Reviewers: `senma-telephony-architect`
(status-vocabulary reconciliation, WSS/native-TLS certificate wording),
`senma-application-architect` (shared view-helper boundary). Implements
the Transport half of TASK-0030's split, and closes the shared-primitive
debt TASK-0031 explicitly deferred to this task.

## CURRENT TRANSPORT FLOW

List → Add/Edit (one flat form: Transport fields, NAT/Advertised-address
fields, and a protocol-conditional TLS/Certificate fieldset all in a
single page, no Basic/Advanced/Diagnostics separation) →
`validatePost()`/`validateTlsFields()` (pre-flight bind-collision check,
live certificate parsing — unchanged, already correct) →
`Manager::create()`/`update()` → `regenerateAll()` →
`reportApplyResult()` (already the most product-mature part of this
surface — six distinct, already-product-worded flash outcomes; unchanged
by this task) → Delete blocked outright if `usage_count > 0` (itemized
extension/trunk list, hand-built `error_message` string) or if removing
the last default transport, otherwise a real confirm page.

Confirmed gaps by direct inspection before any change:

- **No try/catch around `Snep_PjsipTransportConf::getRuntimeTransportNames()`
  in `indexAction()`.** Unlike Extensions/Trunks (`preDispatch()`'s own
  `AsteriskInfo()` connectivity check) and `Snep_PjsipStatus_Manager::
  amiCommand()` (`try/catch`, returns `null` on any failure), a stopped
  Asterisk container reaching this one specific call would have thrown
  uncaught out of `indexAction()` — a genuine, previously-undetected
  crash risk, not merely a UX rough edge. Confirmed live in Part E of the
  new regression suite (Asterisk stopped, page still returns HTTP 200).
- **Status/Runtime were two separate columns/badges** (`Status` =
  enabled/disabled, `Runtime` = active/restart_required, TASK-0020's own
  disjoint two-value vocabulary), never reconciled with the 7-state
  ACTIVE/DEGRADED/PENDING/INACTIVE/DISABLED/ERROR/UNKNOWN vocabulary
  TASK-0029B already established and TASK-0031 already applied to
  Extensions/Trunks.
- **The badge markup itself (class/label maps) was duplicated in THREE
  places** by the time this task started: `extensions/index.phtml`,
  `trunks/index.phtml`, and `trunks/addedit.phtml`'s own Diagnostics
  section (a third, independent copy TASK-0031 introduced without
  factoring out — confirmed by inspection, not merely inferred from the
  TASK-0030 audit).
- **The dependency-warning ("cannot delete, referenced by…") message was
  hand-built three times independently**, in `ExtensionsController::
  removeAction()`/`disableAction()`, `TrunksController::removeAction()`,
  and `PjsipTransportsController::removeAction()` — two of the three had
  no per-item identity (generic "Cannot remove." with no object name),
  and **all three concatenated the dependent-item label with zero HTML
  escaping** (`$regra['id'] . " - " . $regra['desc']`, unescaped) — a
  real, if narrow, XSS-hardening gap this task closes as a natural side
  effect of building the one shared primitive that replaces all three.
- **Extensions/Trunks delete had no success feedback of any kind** — a
  bare silent 302, the same class of gap TASK-0031 already closed for
  save.
- **The TLS/certificate conditional fieldset toggled a `visible`/
  `invisible` CSS class**, not `hidden`/`aria-hidden` — the exact
  accessibility gap TASK-0030 flagged, and confirmed still present in
  TASK-0031's OWN new trunk connection-type panels too (out of this
  task's scope — see REMAINING DEBT).
- **The transport edit page had no runtime-status display of any kind** —
  only the list page did; TASK-0031 already added this Diagnostics
  section to trunks/addedit.phtml, transports never got the equivalent.
- **Transport list had no responsive column-priority behavior** —
  9 plain columns, no `hidden-xs`/`hidden-sm`, unlike Extensions/Trunks
  (TASK-0031).
- **No empty-state message, and no way to distinguish "no transports
  configured" from "runtime status could not be queried."**

Confirmed NOT a gap (TASK-0030's own audit re-verified, still true): no
`INTERNAL_ONLY`, `DEAD`, or `LEGACY_COMPATIBILITY` fields exist on the
transport form — every field is either `CORE` or `ADVANCED`.

## TARGET TRANSPORT FLOW

```text
open → Basic/Connection (name, protocol, bind address/port, enabled)
     → TLS/Certificate (protocol-conditional: tls/wss/ws only,
       hidden/aria-hidden disclosure)
     → Advanced (collapsed <details>: domain, external addresses,
       local networks, symmetric transport, allow reload, default
       transport)
     → Diagnostics (edit only, collapsed <details>: shared status
       badge, certificate identity summary)
     → save
     → reportApplyResult()'s existing six-outcome flash (unchanged)
```

## STATUS VOCABULARY RECONCILIATION

`PjsipTransportsController::normalizeStatus($rawState)` (new, private to
the controller — a presentation-layer mapping only, per
`docs/tasks/0030-telephony-administration-ux-foundation.md`'s own STATUS
MODEL decision):

```text
active            -> ACTIVE    "Asterisk currently has this transport
                                 loaded, matching its saved configuration."
restart_required  -> PENDING   "Configuration saved; Asterisk restart
                                 required to apply."
disabled          -> DISABLED  "This transport is disabled and not
                                 loaded in Asterisk."
(query failed)     -> UNKNOWN   "Could not query Asterisk's live
                                 transport state."
```

`restart_required` covers BOTH directions the original two-value
vocabulary already conflated (enabled-but-not-loaded, and
disabled-but-still-loaded) — kept as ONE shared state per TASK-0030's own
decision, since the underlying runtime signal genuinely is the same
"config and runtime disagree" condition either way; the per-instance
DETAIL text (not implemented as two different states, since none was
asked for) is where that nuance would go if ever needed, per Phase 14's
"do not collapse them into one badge if meaning would be lost" — here
nothing is lost because the pre-existing `data-runtime-state` attribute
(see below) already preserves the raw distinction verbatim.

ERROR is deliberately never produced by this mapping: a bind-collision or
TLS-handshake apply failure is a save-time-only signal
(`reportApplyResult()`'s own `apply_failed` flash), not something
derivable from a plain "is this name loaded" query on every page view —
exactly mirroring how Extensions/Trunks' own per-row `runtime_status` is
likewise separate from their save-time `checkApplyResult()` flash. Never
fabricated to fill out the vocabulary.

**`runtime_state` itself (`active`/`restart_required`/`disabled`, and now
also `unknown` for a failed query) is completely unchanged** — same
computation, same `data-runtime-state` attribute, same three original
values `scripts/transport-smoke-test.sh`'s own `t20_runtime_badge()`
already depends on. This is a reconciliation of PRESENTATION, not a
re-architecture of how transport runtime truth is computed.

## SHARED STATUS PRIMITIVE

`Snep_View_Helper_StatusBadge` (`snep/lib/Snep/View/Helper/StatusBadge.php`),
registered once in `snep/Bootstrap.php::_initViewHelpers()` via
`$view->addHelperPath('Snep/View/Helper', 'Snep_View_Helper')` — the
first app-specific Zend view-helper path this codebase has ever
registered (confirmed by inspection: no `partial()` calls and no custom
helper path existed anywhere before this task; the established "shared
markup" convention here was full view-SCRIPT reuse via `renderScript()`,
e.g. `error/sneperror.phtml`/`remove/remove.phtml` — a per-row/per-call
badge doesn't fit that shape, so a real Zend view helper is the natural
fit, not a new pattern invented for its own sake).

`$this->statusBadge($state, $options)` renders ONE badge (+ optional
visible detail paragraph for a Diagnostics context) from any view script
in any module. Deliberately renders ONLY the badge, never the surrounding
`<td>`/data-attribute — a list cell and a Diagnostics form-group need
different wrappers, and callers keep that responsibility.

Adopted by: `extensions/index.phtml`, `trunks/index.phtml`,
`trunks/addedit.phtml` (Diagnostics), `pjsip-transports/index.phtml`
(replacing the merged Status/Runtime columns), `pjsip-transports/
addedit.phtml` (new Diagnostics section) — every place the class/label
map was previously duplicated (four call sites, not three — the audit's
own count was revised upward once the transport list was included).

## SHARED APPLY FEEDBACK

`Snep_View_Helper_ApplyFeedback` renders the canonical outcome → Bootstrap
alert-class mapping (`saved_active`→success, `deleted`→success,
`saved_pending`→info, `restart_required`→warning, `apply_failed`→danger),
in a fixed order, from whatever subset of FlashMessenger message arrays
a controller passes in. **No controller-side FlashMessenger logic
changed** — every controller still computes exactly the outcomes it
already did (`reportSaveResult()`/`reportTrunkSaveResult()`/
`reportApplyResult()`, none renamed, none given new states); only the
VIEW markup that renders those arrays was deduplicated. Extensions/
Trunks pass `saved_active`/`saved_pending`/`apply_failed`/`deleted`;
Transports pass `restart_required`/`apply_failed` — RESTART_REQUIRED is
still never forced onto Extensions/Trunks, matching TASK-0031's own
explicit "no evidence any endpoint-level save ever needs a hard restart"
finding.

`SAVE_REJECTED` is not a flash outcome for any of the three entities
(each re-renders the submitted form inline, HTTP 200, per TASK-0031's own
validation-failure contract) and so is intentionally absent from this
helper's class map.

## DEPENDENCY WARNING PATTERN

`Snep_View_Helper_DependencyWarning` — `dependencyWarning($objectType,
$objectName, array $items, $nextStep)` — builds:

```text
Cannot remove <type> '<name>'.
The following N item(s) depend on it:
  • <item 1>
  • <item 2>
What to do next: <nextStep>
```

"Cannot remove" (not "Cannot delete") is kept verbatim — the
already-regression-proven phrase `scripts/transport-smoke-test.sh` checks
for, not renamed for its own sake. **No new backend dependency
discovery** — every caller still uses its existing
`getValidation()`/`getRules()`/`getUsageDetails()` query, just hands the
already-fetched rows to this helper as plain formatted strings instead of
concatenating its own HTML.

Object identification (Phase 8) was a real, closed gap for two of the
three callers:

- Extensions: already had the extension number available (`$exten`) —
  simply not previously included in the message text.
- Transports: already had `$transport['name']` — not previously included.
- **Trunks: `TrunksController::removeAction()` previously had no
  admin-facing identity to show at all.** `trunks.name` (the only value
  the old code path had in scope via the `name` URL param) is an opaque
  internal identifier the admin never sees in the UI —
  `trunks/index.phtml`'s own "Name" column is actually `callerid`
  (`trunks.name` only ever surfaces there as the hidden-by-default
  "Code" column). Fixed by fetching the trunk row once, up front, in
  `removeAction()` (`$trunkRow = Snep_Trunks_Manager::get($id)`) and
  using `$trunkRow['callerid']` — this ALSO removed a second, redundant
  `Snep_Trunks_Manager::get($id)` call the delete-success path used to
  make on its own.

Also closed as a direct consequence of building one shared primitive
instead of three hand-built ones: every dependent-item label is now
`$view->escape()`d. Previously, all three call sites concatenated
`$regra['id'] . " - " . $regra['desc']` (or the transport equivalent)
with **zero escaping** — a route's own `desc` column, or a peer/trunk
`name`/`label`, reaching the page unescaped. Classified
`REQUIRED_FOR_CURRENT_TASK`-adjacent (same disposition TASK-0030 gave the
`PDOException::getMessage()` leak it found and TASK-0031 then fixed) —
this task is already rewriting this exact code into one shared helper,
so fixing the escaping gap in that same helper is the smallest safe
place to do it, not a separate opportunistic pass over unrelated code.

## DESTRUCTIVE ACTIONS

Reviewed all three delete flows for title/object-identification/
dependency-explanation/confirmation-language/cancel/error-behavior
consistency (Phase 8):

- Title, cancel action, and error behavior were already consistent
  (shared `remove/remove.phtml` confirm partial, shared
  `error/sneperror.phtml` blocked-panel, shared CSRF token field) — not
  touched.
- Object identification in the BLOCKED panel is now consistent across
  all three (see DEPENDENCY WARNING PATTERN above).
- The generic pre-delete CONFIRM copy (`remove/remove.phtml`'s own
  `remove_message`, e.g. "The trunk will be deleted. After that, you have
  no way get it back.") is deliberately **left unparameterized** — that
  partial is shared by several OTHER entities outside this task's scope
  (SoundFiles, Users, Queues, …), and folding a specific object identity
  into it would mean auditing every caller across the app, not just the
  three entities TASK-0032 covers. Tracked as REMAINING DEBT, not fixed
  here — a materially larger, cross-cutting change than "the three
  telephony administration surfaces" this task is scoped to.
- Materially different consequences ARE still surfaced distinctly, not
  hidden behind generic wording: the transport delete confirm/flash
  wording (post-delete socket-may-remain-bound warning) is entity-
  specific and unchanged, exactly because deleting a transport has a
  real consequence deleting an extension/trunk does not.

## TRANSPORT DIAGNOSTICS

New, edit-only `<details id="diagnosticsSection">` (same
`<details>`/`<summary>` pattern TASK-0031 established for Extensions/
Trunks): shared status badge (with `showDetail` — a visible reason, not
tooltip-only, matching Phase 5's "consistent tooltip/detail" extended to
a non-hover context) + certificate identity summary (subject/expiry from
the already-existing `certInspection`, private-key mode warning from the
already-existing `keyCheck` — MOVED here from inside the editable
TLS/Certificate fieldset, where it was previously mixed into the input
form itself, contrary to this task's own IA rule that Diagnostics is
"never part of the create/edit input form"). No new AMI call, no new
Manager method — `certInspection`/`keyCheck` are TASK-0029A's own
existing computations, `normalizedStatus` reuses the exact same
`getRuntimeTransportNames()` call `indexAction()` already makes (also
now wrapped in the same try/catch — see PROTOCOL-SPECIFIC DISCLOSURE's
sibling finding above).

Deliberately NOT shown: private key file contents, raw AMI payload text
(confirmed absent, Part F of the new regression suite). Private key
*path* and certificate *subject/expiry* are shown — unchanged from
TASK-0029A's own established ownership model (SENMA never reads key
bytes; a path reference only).

## PROTOCOL-SPECIFIC DISCLOSURE

TLS/Certificate fieldset visibility: unchanged logic (`tls`/`wss`/`ws`
show it, `udp`/`tcp` don't; `verify_server`/`method` are TLS-only within
that), but the MECHANISM changed from a `visible`/`invisible` CSS class
(TASK-0030's own flagged accessibility gap) to the native `hidden`
attribute + a mirrored `aria-hidden`, server-rendered on first paint (so
a client with JS disabled still sees the correct fields for whatever
protocol is already saved) and kept in sync on `protocol` change by
`senmaSetHidden()`, a small new JS helper replacing the old
`className = "visible"/"invisible"` assignment.

## CERTIFICATE UX

WSS/WS and native `tls` now render visibly DIFFERENT explanatory text
directly above the cert_file/priv_key_file fields (Phase 16):

- WSS/WS: "this certificate configures Asterisk's single, process-wide
  HTTP/TLS listener — not a per-transport TLS context. Only one enabled
  WSS/WS transport may reference a certificate at a time."
- Native TLS: "this certificate applies directly to this transport's own
  PJSIP TLS context."

This is wording only — TASK-0029A's actual certificate architecture
(Model B, externally-managed paths; the one-active-WSS-certificate
conflict check; native-TLS in-place-rotation restart requirement) is
completely unchanged. No upload UI, no certificate-inventory entity was
added or implied.

## ACCESSIBILITY

Applied to the transport form (the surface this task actually changed)
and to the new shared primitives:

- Required-field markers (`<span class="text-danger" aria-hidden="true">*</span>`
  + `aria-required="true"`) added to Name/Protocol/Bind Address/Bind
  Port — previously present on Extensions/Trunks (TASK-0031) but absent
  from Transports.
- Every input in the restructured form now has an explicit `id`/`for`
  pair (several previously relied on positional/implicit association).
- `<details>`/`<summary>` for Advanced/Diagnostics — same
  keyboard-and-screen-reader-native disclosure TASK-0031 already
  established, zero custom JS/ARIA needed for the collapse itself.
- TLS/Certificate conditional disclosure: `hidden` + `aria-hidden`
  (see PROTOCOL-SPECIFIC DISCLOSURE above) instead of a CSS-class-only
  toggle.
- Status badges: text + color, never color-alone (unchanged principle,
  now enforced by ONE shared implementation instead of four copies that
  could each individually drift).

**Not touched, and explicitly flagged as still-open**: Trunks' OWN
connection-type conditional panels (`panel-external`/`panel-provider`/
`panel-credentials`, `trunks/addedit.phtml`) still toggle a `visible`/
`invisible` CSS class — the identical pattern this task just removed from
Transports. This is TASK-0031's own new code (added in that task, not
inherited from before it), confirmed still present by direct inspection
before this task's changes. Retrofitting it is out of this task's
explicit phase list (Phase 2/3's disclosure work is scoped to the
Transport form) and touches a materially different form (the trunk
connection-type chooser, not a shared list/badge/dependency/flash
primitive) — tracked as REMAINING DEBT, not silently left unmentioned.

## RESPONSIVE MODEL

Transport list: `Name`/`Protocol`/`Bind`/`Status`/`Actions` stay always
visible; `External Signaling`/`External Media` collapse first
(`hidden-xs hidden-sm`), `In Use` collapses at the next breakpoint
(`hidden-xs`) — same Bootstrap-utility-class approach TASK-0031 used for
Extensions/Trunks (no `footable` dependency introduced, matching that
task's own already-validated rejection of it). This also required
merging the old Status+Runtime two-column layout into one Status column
(see STATUS VOCABULARY RECONCILIATION) — Phase 12's own suggested
high-priority column list for Transports (`name, protocol, bind, status,
actions`) only has room for ONE status column, which is what settled the
merge decision, not merely a de-duplication preference.

Extensions/Trunks' own responsive columns (TASK-0031) were reviewed and
found unchanged/still correct — no further action needed there (Phase 12's
"review... if they still differ" — they don't).

## EMPTY / ERROR STATES

Transport list now distinguishes three states explicitly:

```text
DB has 0 transport rows                     -> "No transports configured
                                                 yet." (plain text, no
                                                 table rendered at all)
DB has rows, runtime query succeeded        -> normal table, real
                                                 per-row status
DB has rows, runtime query failed           -> explicit warning banner
                                                 ("could not be queried
                                                 right now... Status
                                                 columns show Unknown")
                                                 + every row's status
                                                 badge is UNKNOWN, never
                                                 a fabricated ACTIVE/
                                                 DISABLED
```

The third case did not exist before this task in any form — a runtime
query failure previously threw an UNCAUGHT exception out of
`indexAction()` (see CURRENT TRANSPORT FLOW's own first bullet). Fixed
with a `try`/`catch` around `Snep_PjsipTransportConf::
getRuntimeTransportNames()`, mirroring the exact defensive pattern
`Snep_PjsipStatus_Manager::amiCommand()` already established elsewhere in
this codebase — not a new failure-handling idiom invented for this task.

Extensions/Trunks were reviewed against the same three-way distinction
and found ALREADY correct (TASK-0029B's own two-layer contract: a total
AMI outage is caught earlier, at `preDispatch()`, by the pre-existing
`AsteriskInfo()` connectivity check and renders a full-page connection
error instead of any list at all; a narrower per-call AMI failure is
caught inside `Snep_PjsipStatus_Manager::amiCommand()` and reported as
UNKNOWN per row) — no change needed there.

## REGRESSION PROOF

New suite: `scripts/transport-shared-runtime-ux-smoke-test.sh`
(`make transport-shared-runtime-ux-smoke`), 23 checks, all against the
real application/Asterisk stack, standalone run: **23/23 PASS**. Covers:

- shared `data-runtime-status` attribute present on Extensions/Trunks/
  Transports list rows;
- transport list status cell carries BOTH the new `data-runtime-status`
  (shared vocabulary) and the pre-existing `data-runtime-state` (TASK-0020,
  unchanged) attributes — proves `scripts/transport-smoke-test.sh`'s own
  `t20_runtime_badge()` still finds exactly what it expects;
- the transport list's Status/Runtime columns are merged into one;
- transport list responsive `hidden-xs`/`hidden-sm` columns present;
- transport add page: TLS fieldset uses `hidden`+`aria-hidden` for the
  `udp` default, and no `visible`/`invisible` className toggle remains
  anywhere in the form's own JS;
- WSS edit page shows WSS-specific certificate-ownership wording (not
  the native-TLS wording) + a Diagnostics section with a real status
  badge;
- transport dependency-warning panel (blocked by a referencing
  extension): canonical `Cannot remove transport '<name>'.` wording,
  the referencing extension listed, no raw SQL/exception leak;
- extension dependency-warning panel (blocked by a referencing route):
  same canonical wording/no-leak proof;
- trunk dependency-warning panel (blocked by a referencing route,
  reusing a real, newly-created trunk fixture): same proof, AND confirms
  the object-identity fix (`callerid`, not the internal `trunks.name`)
  actually renders;
- extension delete and trunk delete both now show a "deleted
  successfully" flash (previously silent);
- Asterisk stopped entirely → transport list still returns HTTP 200 with
  the explicit runtime-unavailable banner + `UNKNOWN` badges, never a
  fatal error, never a fabricated "no transports configured"; Asterisk
  restarted → status reporting resumes (`ACTIVE` badges return);
- no private-key PEM content anywhere in any page this task touched;
- an unauthenticated request renders no `data-runtime-status` content.

Affected pre-existing suites re-run individually as part of the full
regression pass below, no regressions: `transport-smoke` (64/64),
`tls-cert-management-smoke` (19/19), `pjsip-runtime-status-smoke`
(14/14), `extensions-trunks-admin-experience-smoke` (25/25),
`trunk-smoke`, `pjsip-external-trunk-smoke`, `pjsip-lifecycle-smoke`,
`call-smoke`, `authorization-smoke`.

`make lint`: **PASS** (5/5 — 274 PHP files 0 syntax errors, 38 shell
scripts parse cleanly, 3 `resources.xml` well-formed, clean
`git diff --check`).

`make regression`: two consecutive **PASS, 31/31 suites** official runs
(both clean on the first attempt — no flakes, no unrelated pre-existing
failures). One earlier attempt in this session's own history is worth
recording honestly rather than omitting: a first regression pass was
killed mid-run by the host's own low-memory condition (unrelated Docker
projects on the same machine, not this suite) — not counted as an
official attempt. A second, complete attempt then surfaced one real,
self-inflicted bug: this task's own new suite used a different admin
dev-account test password (`SmokeTest0032!`) than the
`SmokeTest123!` baseline every other suite in this repository already
shares and depends on (confirmed: `scripts/auth-hardening-security-
smoke-test.sh` documents it explicitly and restores it as a required
cleanup step; `scripts/preauth-security-smoke-test.sh` relies on it being
already set, without setting it itself) — breaking `preauth-security-
smoke` when the new suite's manual/standalone runs earlier in this
session left that shared value changed. Fixed by aligning the new
suite's `TEST_PASSWORD` to the same established baseline. The two
official runs reported above were both taken AFTER that fix, back to
back.

## REMAINING DEBT

- Trunks' own connection-type conditional panels (`trunks/addedit.phtml`)
  still toggle a `visible`/`invisible` CSS class instead of `hidden`/
  `aria-hidden` — TASK-0031's own new code, confirmed not touched by
  this task (out of Phase 2/3's Transport-form scope). A future small
  accessibility task could apply the same `senmaSetHidden()`-style fix
  there.
- `remove/remove.phtml`'s generic pre-delete confirmation copy ("The X
  will be deleted…") is not parameterized with the specific object's own
  identity — real, but shared by several entities outside this task's
  three-entity scope (SoundFiles, Users, Queues, …); fixing it well means
  auditing every caller across the app, not a Transport/shared-runtime-UX
  change.
- Queue/group-membership delete-dependency checks remain `FOLLOW_UP_DEBT`
  (unchanged from TASK-0031 — no backend introspection capability exists
  for those yet; the shared `dependencyWarning()` helper built here is
  ready to render them the moment that capability exists, but this task
  does not add it).
- No certificate-expiration warning/alerting in the UI (unchanged from
  TASK-0029A's own already-accepted deferral).
- Multi-delete (`ExtensionsController::multiremoveAction()`) was not
  given the same "deleted successfully" flash treatment — a distinct
  bulk-operation flow not named in any of this task's 20 phases; noted
  here rather than silently expanded into.

## RECOMMENDATION

`APPROVE`.

## PROPOSED COMMIT

One coherent commit — the shared view helpers have no meaning without the
controller/view code that adopts them, and vice versa; splitting further
would leave intermediate commits with dead or unreachable helper code:

```
feat(ux): unify transport, extension, and trunk administration UX

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FP7YzWTLhPbMEVgpGAsNdv
```

Paths: `Makefile`, `scripts/regression.sh`,
`scripts/transport-shared-runtime-ux-smoke-test.sh`,
`snep/Bootstrap.php`, `snep/lib/Snep/View/Helper/`,
`snep/modules/default/controllers/ExtensionsController.php`,
`snep/modules/default/controllers/PjsipTransportsController.php`,
`snep/modules/default/controllers/TrunksController.php`,
`snep/modules/default/views/scripts/extensions/index.phtml`,
`snep/modules/default/views/scripts/pjsip-transports/addedit.phtml`,
`snep/modules/default/views/scripts/pjsip-transports/index.phtml`,
`snep/modules/default/views/scripts/trunks/addedit.phtml`,
`snep/modules/default/views/scripts/trunks/index.phtml`,
`docs/tasks/0032-transport-shared-runtime-ux-foundation.md`.
