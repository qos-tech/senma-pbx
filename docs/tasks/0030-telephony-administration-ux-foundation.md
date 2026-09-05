# TASK-0030 — Telephony Administration UX Foundation

Status: DESIGN/ARCHITECTURE REVIEW — no implementation in this task.
Lead: senma-product-designer. Reviewers: senma-telephony-architect, senma-application-architect.

## Context

TASK-0028C/W/X/Y/Z and TASK-0029A/B closed out the PJSIP runtime modernization
phase: extensions and trunks have a complete supported PJSIP lifecycle,
`pjsip_external` works inbound/outbound, all four transport protocols are
operational, TLS/WSS certificates have a production-safe ownership model, and
runtime status is now visible for extensions and trunks. The backend is
materially ahead of the UI it was originally built around. This task is the
first FASE 4 (Experience) task: define the coherent administration UX for
Extensions, Trunks, and Transports before any further backend work.

This document is the product of direct code inspection (not assumption) of
`ExtensionsController.php`, `TrunksController.php`,
`PjsipTransportsController.php`, their view scripts, and the managers/config
generators behind them, performed as three parallel evidence-gathering passes
for this task.

## CURRENT JOURNEYS

### Extensions
List → Add (full-page form, technology hardcoded to `pjsip`) → server-side
`execAdd()` runs ~6 sequential checks → **on any failure, the whole form is
discarded and the user is redirected to a generic full-page error** (no
inline/per-field errors, no field values preserved) → on success, `peers` is
written and `Snep_InterfaceConf`/`Snep_PjsipTransportConf`/`Snep_PjsipConf`
`loadConfFromDb()` are called with their return values ignored → **silent
redirect to the list, no success message at all** → Edit pre-fills every
field, blocks editing legacy (non-PJSIP) rows outright → Delete pre-checks
route dependencies (blocks with an itemized rule-id list if referenced),
otherwise shows a real, CSRF-protected confirm page (not a JS `confirm()`) →
silent redirect on success, no confirmation toast.

### Trunks
List → Add (one undifferentiated form covering every legacy technology via a
JS show/hide switch, even though the server only ever accepts `pjsip` or
`pjsip_external`) → `preparePost()` validation → transactional
`trunks`(+`peers`) write → the same fire-and-forget `loadConfFromDb()` calls →
**silent redirect, no success message, and no distinction at all between
"saved," "saved but runtime apply pending," and "runtime apply failed"** →
Edit → Delete pre-checks route dependencies (best-designed part of this
surface: itemized route list, matches the task's own worked example) →
generic confirm page → silent redirect.

### PJSIP Transports
List → Add/Edit → server-side `validatePost()`/`validateTlsFields()`
(includes a pre-flight bind-collision check and live certificate parsing) →
`Manager::create()`/`update()` → `regenerateAll()` → **`reportApplyResult()`
actually compares before/after state and probes live Asterisk**, producing
one of six distinct, already-product-worded flash messages (rename →
"restart required," disable → "socket may remain in use," bind collision →
"could not apply," TLS mismatch → "certificate could not be confirmed," WSS
listener down → "TLS listener did not come up," plain success → no banner) →
Delete is blocked outright if `usage_count > 0` (itemized extension/trunk
list) or if removing the last default transport, otherwise a real confirm
page, with the post-delete flash explicitly warning the socket may remain
bound until restart.

**Transports is the only one of the three surfaces that already solves the
"configuration saved" vs. "runtime active" distinction this task calls out.**
It is the reference implementation the other two should be brought up to,
not a fourth thing to redesign from scratch.

## FIELD CLASSIFICATION

Full per-field tables (label / underlying concept / classification /
rationale) were produced for all three entities during evidence-gathering.
Summary of what falls outside CORE/ADVANCED:

**Extensions** — `DEAD`: "Minute Control" fields (already commented out of
the template but still referenced by validation JS and `execAdd()`), a
Khomp hardware channel selector (unreachable, technology is locked to
`pjsip`). `INTERNAL_ONLY` (correctly already hidden): the technology field
itself. Naming collision flagged: "Password" (SIP secret) and "Password
Padlock" (an unrelated numeric PIN) share the word "Password" with no
visual distinction.

**Trunks** — by far the largest concentration of non-CORE/ADVANCED fields:
`DEAD` markup/JS for IAX2, KHOMP, Virtual, SnepSIP, and SnepIAX2 technologies
— the dropdown only ever renders two options (`pjsip`, `pjsip_external`), so
these branches are unreachable through the UI's own control, not merely
edge cases. `LEGACY_COMPATIBILITY`: `peers.type` (peer/user/friend),
`insecure`, call-limit, dial-method — all chan_sip-era, already
JS-hidden for `pjsip` but still present in the DOM and validated. Most
significant finding: **the connection model itself (registered /
registrationless / IP-authenticated / external) is not a first-class
choice** — it is implied by the "Force reverse authentication" checkbox
(`reverse_auth`), an opaque technical label that is actually the entire
product decision a trunk-creating admin is making.

**Transports** — no `INTERNAL_ONLY`, `DEAD`, or `LEGACY_COMPATIBILITY`
fields found; TLS/certificate fields are already conditionally
shown/hidden by protocol (a genuine existing positive precedent from
TASK-0029A). Two fields have materially inadequate help text today:
`Symmetric Transport` and `Allow Reload` (the latter links to a doc file
instead of explaining the option in product language).

## PRODUCT TERMINOLOGY

For the concepts the task specifically flagged as needing review:

| Concept | Product label | Technical meaning | Help text | When shown |
|---|---|---|---|---|
| `reverse_auth` | Not shown directly — becomes the derived outcome of the trunk's **Connection type** choice ("Provider with registration") | Creates a PJSIP registration object; SENMA sends the outbound REGISTER | "SENMA registers with the provider so it can receive calls without the provider needing a fixed source IP for you." | Never as an independent checkbox in the target design |
| `transport` | "Network transport" (label already adequate per TASK-0019) | The PJSIP transport object (protocol + bind) this endpoint/trunk binds through | "Which network configuration this connects through. Ask your network administrator if unsure." | Advanced tier, all entities |
| `qualify` | "Monitor reachability" (+ "Check every N seconds") | Enables periodic PJSIP OPTIONS probing; now also the precondition for TASK-0029B's ACTIVE/DEGRADED distinction | "When enabled, SENMA periodically checks whether this is reachable and reflects that in Status. When disabled, Status shows as configured but is not monitored." | Advanced for extensions/registered trunks; CORE for registrationless trunks (their primary reachability signal) |
| NAT | "Behind a firewall/NAT" (simple default) + an "Advanced NAT options" sub-disclosure for the raw 5-way choice | `peers.nat` rport/media-rewrite directive | "Enable if this device or provider is behind a router doing network address translation." | Advanced tier, all entities |
| External PJSIP endpoint | "External PJSIP endpoint" (kept, but always paired with explicit trust-boundary help text) | SENMA creates no endpoint/AOR/auth object at all — only references, by name, an object provisioned entirely outside SENMA | "Use only if the SIP endpoint already exists in Asterisk's own configuration. SENMA will not create, modify, or manage it — only reference it by name." | One of 4 connection-type choices, help text always visible when selected |
| registration | "Registration status" | Live outbound REGISTER state (Registered/Rejected/Unregistered — TASK-0029B vocabulary) | Contextual per state, e.g. "The provider rejected our registration — check the username/password." | Status badge + diagnostics detail, registered-trunk model only |
| host | "Provider address" | Overloaded today — a single `peers.host` column backs AOR contact, identify-match, and registration-server roles depending on connection type | "The address (hostname or IP) of your provider's SIP server." | CORE, registered/IP-authenticated/registrationless only — never shown for external-endpoint trunks |
| username | "Account username" | PJSIP auth `username=` | "The username your provider issued for this trunk, if required." | CORE, credential-authenticated models only — hidden entirely for IP-authenticated and external-endpoint |
| client URI / server URI | Not exposed as form fields (already correctly true today — no admin-facing field renders these names) | server_uri = target Asterisk registers to; client_uri = identity Asterisk registers as | Diagnostics tier only, if ever, as read-only derived values | Diagnostics tier only |

Principle applied throughout: do not rename technical concepts merely to
sound simpler, but do not force an admin to understand internal
variable/database names to make a routine choice — `reverse_auth` is the
clearest violation of this found in the audit.

## TARGET INFORMATION ARCHITECTURE

Consistent four-tier disclosure model across all three entities:

```text
Basic / Connection  → always visible, minimal common-case fields
Advanced            → collapsed by default, same page (no tab reload),
                      never duplicated across sections
Diagnostics         → read-only, runtime-derived, shown on list/status
                      detail and an optional expandable block on edit —
                      never part of the create/edit input form
```

Concretely:

- **Extensions**: Basic (extension, name, group, password, voicemail
  toggle+email) / Advanced (NAT, direct media, DTMF, codecs, transport,
  pickup group, follow-me, BLF) / Diagnostics (status detail, qualify
  detail).
- **Trunks**: Connection type (first, standalone step) → type-relevant
  connection fields only / Advanced (NAT, codecs, DTMF, transport, qualify
  tuning) / Diagnostics (registration/status detail).
- **Transports**: Basic (name, protocol, bind address/port, enabled) →
  TLS/Certificate (only rendered for tls/ws/wss, reusing TASK-0029A's
  existing conditional-disclosure JS as the pattern) / Advanced (domain,
  external addresses, local networks, symmetric transport, allow reload) /
  Diagnostics (runtime state, last apply result).

`INTERNAL_ONLY` fields are never rendered as form controls (already true
for Extensions' hidden technology field; must become the rule for Trunks'
dead legacy-technology markup too). `LEGACY_COMPATIBILITY` fields are not
shown in the create flow at all; they remain reachable only when editing a
pre-existing row that already carries that legacy configuration.

## EXTENSION WORKFLOW (target)

```text
open → essential fields (extension, name, group, password, voicemail)
     → optional Advanced (collapsed)
     → save
     → runtime result: Saved and active / Saved, runtime pending /
       Runtime apply failed  (never a silent redirect)
```

Error path: validation failures render inline against the still-populated
form (replacing today's full-page-redirect-with-data-loss), server errors
are pre-translated product strings, and the delete confirmation states the
extension's own identity plus a real dependency summary rather than a
generic "no way to get it back" line with no context.

## TRUNK WORKFLOW (target)

```text
select connection type:
  Provider with registration | Provider without registration
  | IP-authenticated provider | External PJSIP endpoint
→ only the fields relevant to that type
→ Advanced (collapsed)
→ save
→ registration/runtime result appropriate to the chosen type
```

The connection-type step directly replaces the `reverse_auth` checkbox and
the always-visible field bloat inherited from dead chan_sip/IAX/KHOMP
branches. Editing a pre-existing legacy-technology trunk still needs to
work; whether that means read-only display + delete-only, or a narrow
still-editable legacy path, is a `senma-telephony-architect` question for
the implementation task, contingent on whether such rows still exist in
supported production data.

## TRANSPORT WORKFLOW (target)

```text
select protocol (UDP/TCP/TLS/WS/WSS)
→ bind/network fields
→ TLS/certificate fields only when protocol is TLS/WS/WSS
  (already implemented, TASK-0029A)
→ save
→ runtime/restart result (already implemented, TASK-0020/0029A)
```

Largely already correct. Remaining gaps are the status-vocabulary
reconciliation (below), no dedicated empty-state message, and accessibility
gaps (no required-field markers; hidden TLS fields are JS-`className`-hidden
rather than `hidden`/`aria-hidden`, so they may still be announced by
assistive technology).

## STATUS MODEL

TASK-0029B's 7-state vocabulary (ACTIVE/DEGRADED/PENDING/INACTIVE/
DISABLED/ERROR/UNKNOWN) is already correct and already applied uniformly
to extensions and trunks. Transports currently use a **separate, disjoint**
two-value vocabulary (`active`/`restart_required`, TASK-0020), rendered by
its own inline badge markup rather than the shared badge block extensions
and trunks already duplicate between themselves.

**Decision: one shared status vocabulary and one shared badge partial for
all three entities.** Transport states map onto the existing enum without
changing what is actually measured — `active` → `ACTIVE`,
`restart_required` → `PENDING` (detail: "Configuration saved; Asterisk
restart required to apply"), a bind-collision/apply-failure →
`ERROR`, a disabled row → `DISABLED`. This is a presentation-layer
reconciliation, not a re-architecture of how transport runtime truth is
computed — `reportApplyResult()`'s live-Asterisk comparison stays exactly
as it is.

Status stays list-page-fresh (no polling, no new endpoint), matching the
already-validated TASK-0029B freshness model. Edit pages gain a
Diagnostics-tier expandable detail block instead of duplicating the badge
inline in the form. A manual "Refresh" action is sufficient (reloads the
page); no WebSocket/SSE is justified for this.

## SAVE/APPLY FEEDBACK

Transports already fully implement what Phase 9 of this task asks for
(`reportApplyResult()`, TASK-0020/0029A). Extensions and Trunks currently
give **no save feedback of any kind** — success is a bare redirect, and a
`loadConfFromDb()` failure inside the save path is invisible to the user
today. This is the single largest functional gap found in this audit.

**Decision:** generalize the existing `reportApplyResult()` pattern to
Extensions and Trunks so all three surfaces resolve every save into exactly
one of:

```text
Saved and active
Saved, runtime application pending
Saved, restart required
Save rejected
Runtime apply failed
```

This reuses mechanisms that already exist (AMI status query from
TASK-0029B, generated-config/live-state comparison from TASK-0029A/0020) —
it does not require a new persistence or API boundary, only observing
results that are currently discarded.

## VALIDATION/ERROR CONTRACT

Across all three entities, server-side validation is already authoritative
and (with one exception) already speaks product language rather than
leaking internals — a good baseline to preserve, not rebuild.

The one confirmed leak: `ExtensionsController::removeAction()`'s
`catch (PDOException $e)` renders `$e->getMessage()` directly into the
user-facing error panel on a DB-level delete failure. This is a real,
narrow defect (raw internal detail disclosure, not a data-exposure issue)
inside a controller that TASK-0031 will already be modifying for the
save/apply-feedback work above — it is documented here as
`REQUIRED_FOR_CURRENT_TASK`-adjacent debt to close in TASK-0031 rather than
patched in this review-only pass, to avoid touching production controller
code in a task scoped to architecture/design.

Classification used throughout: CLIENT-CONVENIENCE (jQuery Validate rules;
present on all three, several targeting already-dead fields on the Trunks
form and needing cleanup alongside the dead-field removal), 
SERVER-AUTHORITATIVE (uniqueness/format/existence checks — the real gate 
in all three controllers), RUNTIME-DEPENDENT (pjsip_external's live 
existence check, transport's live certificate/bind-collision checks).

## DESTRUCTIVE ACTIONS

Trunks and Transports already implement the exact pattern the task asks
for: a pre-delete dependency check that blocks with an itemized list
("Cannot remove. The following routes/objects are using this: ...")
before any confirm dialog is shown, followed by a real, CSRF-protected,
keyboard-reachable confirm page (not a JS `confirm()`) — this is the
model, not a target for redesign. Extensions has the same route-dependency
check but a plainer confirm message; Transports additionally blocks
removing the last default transport, a case Extensions/Trunks have no
equivalent of by design (no single-default constraint exists for them).

Gap to close: the shared confirm page's copy is generic ("The X will be
deleted. After that, you have no way get it back.") with no per-item
identity or dependency summary folded into the same message; and none of
the three currently give a delete-time warning about queue-membership or
group-membership dependencies, only route dependencies. Extending the
existing dependency-check pattern to cover those is `SMALL_BACKEND_CHANGE`
scope for TASK-0031, not a new capability.

## ACCESSIBILITY

Consistent gaps across all three surfaces: labels are present via
Bootstrap `<label class="control-label">` but several (notably Extensions'
NAT checkbox group) wrap multiple inputs under one label with no
`for=`/`id` pairing; no surface marks required fields visually or via
`aria-required`, relying entirely on client-side JS validation feedback
with no `aria-live` announcement; JS-driven show/hide (Trunks' technology
switch, Transports' TLS field group) toggles CSS classes rather than
`hidden`/`aria-hidden`, so a screen reader may still announce fields that
are visually absent. Positive existing pattern to keep: every destructive
confirmation is a real page/form, not a blocking native dialog, and status
badges already pair color with text and a tooltip rather than relying on
color alone.

## RESPONSIVE MODEL

All three list tables are plain Bootstrap/DataTables tables with no
column-priority or collapse strategy — Trunks (7 columns) and Transports
(9 columns) will overflow at narrow widths with only the browser's default
horizontal scroll as a fallback, which is exactly what this task's Phase
15 calls out to avoid. Notably, `footable` (a responsive-table plugin)
already exists in the asset tree (`footable/bootstrap.css`) but is not
wired to any of these tables — the target design should define column
priority per table (e.g., Trunks: Name/Type/Status/Actions stay, Code/Time
Credit collapse first) and use that existing dependency rather than
introducing a new one.

## SHARED UI PATTERNS

Patterns to formalize as reusable partials/helpers (reducing duplication
that already exists, not introducing a component framework):

- **Status badge** — one partial (label + color class + tooltip +
  `data-runtime-status`/`data-runtime-state` attribute) replacing the
  inline-duplicated blocks in `extensions/index.phtml` and
  `trunks/index.phtml`, and generalized to also render Transports' states
  under the reconciled vocabulary above.
- **Dependency-warning panel** — "Cannot delete X. N routes/trunks are
  using it: [itemized list]" — already implemented twice independently
  (Trunks, Transports); formalize into one partial, then reuse it for
  Extensions' queue/group-membership extension.
- **Destructive confirm page** — `remove/remove.phtml` is already shared;
  keep it, extend its parameters to carry the specific entity name/id into
  the message body.
- **Save/apply flash banner** — generalize Transports' existing
  FlashMessenger success/warning/danger namespaces into the shared
  five-state contract above.
- **Advanced-settings collapsible fieldset** — one shared markup/JS pattern
  for the Basic/Advanced disclosure across all three add/edit forms.

## BACKEND REQUIREMENTS

| Requirement | Classification | Note |
|---|---|---|
| Status data for extensions/trunks | AVAILABLE_NOW | TASK-0029B |
| Transport apply-result computation | AVAILABLE_NOW | TASK-0020/0029A, pattern to replicate elsewhere |
| Route-dependency queries (trunks, transports, extensions) | AVAILABLE_NOW | `getValidation()`/`getValidationRules()`/`usage_count` already exist for all three |
| Generalizing `reportApplyResult()`-style feedback to Extensions/Trunks saves | SMALL_BACKEND_CHANGE | Observing existing `loadConfFromDb()`/AMI results already computed elsewhere, not a new boundary — needs `senma-application-architect` + `senma-telephony-architect` sign-off since it changes what "save" contractually reports |
| Queue/group-membership dependency checks at delete time | SMALL_BACKEND_CHANGE | Extends the existing dependency-check pattern; no new persistence boundary |
| Trunk connection-type field-relevance mapping | SMALL_BACKEND_CHANGE | Pure UI/controller-side conditional logic over already-existing `reverse_auth`/technology fields; no schema change |
| Full removal of dead IAX2/KHOMP/Virtual/SnepSIP/SnepIAX2 trunk code | FOLLOW_UP_DEBT (own task) | Confirm nothing else references it before deleting, out of scope here |
| New application capability of any kind | NONE IDENTIFIED | No new endpoints, tables, or API surfaces required by any decision in this document |

Everything decided above is implementable against **existing** backend
capability; no `NEW_APPLICATION_CAPABILITY` item was found.

## IMPLEMENTATION SPLIT

The audit found substantial, largely independent redesign work for Trunks
(connection-type model, dead-field removal) and for Extensions
(save/apply feedback, credential-handling/error-leak fixes), materially
different in shape from the Transports/status/accessibility/responsive
work. Per this task's own instruction, that calls for `SPLIT_TASK` rather
than a single giant implementation commit.

```text
TASK-0031 — Extensions + Trunks administration experience
  - Trunk connection-type chooser (Step 1), field relevance mapping
  - Removal/isolation of dead legacy-technology trunk UI
  - Save/apply feedback contract for Extensions and Trunks
  - Extensions credential-handling and PDOException-leak fixes
  - Dependency-warning partial extended to queue/group membership
  - Terminology relabeling per this document's table

TASK-0032 — Transport + shared runtime/status experience
  - Status vocabulary reconciliation (transport active/restart_required
    into the shared 7-state model) + shared status-badge partial
  - Shared dependency-warning and save/apply-banner partials adopted by
    all three entities
  - Accessibility fixes (required-field marking, aria-hidden on
    JS-toggled sections, label association) across all three
  - Responsive table column-priority (footable) across all three
  - Transport empty-state message
```

## RECOMMENDATION

`SPLIT_TASK` — see above for the precise TASK-0031/TASK-0032 boundary.
