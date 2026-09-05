# TASK-0029B — PJSIP runtime status visibility

Status: Resolved. Two consecutive full `make regression` PASS runs (28/28
each, including the new `pjsip-runtime-status-smoke` suite), `make lint`
PASS, `git diff --check` PASS. Not committed — awaiting authorization per
CLAUDE.md's commit policy.

Lead: `senma-telephony-architect` (implementation carried through
directly, matching this task's own "implementation may be handed to the
appropriate specialist" allowance). Reviewer: `senma-product-designer`.
`senma-application-architect`/`senma-docker-platform-engineer` were not
invoked — see SCOPE for why.

## Objective

TASK-0028W found PJSIP runtime status visibility PARTIAL/product-blind:
SENMA could provision PJSIP entities but gave administrators no
coherent view of Asterisk's actual live state, routinely letting
CONFIGURED be confused with LIVE/REACHABLE/REGISTERED. This task defines
and implements a normalized runtime-status contract for extensions,
registered trunks, registrationless trunks, `pjsip_external` trunks, and
(by reuse) transports.

## CURRENT STATUS MODEL (Phase 1 inventory)

- **`IpStatusController` / `Snep_IpStatus_Manager` / `snep/includes/
  ip_status_*.php`**: the only pre-existing status mechanism. Classified
  **LEGACY_ONLY / MISLEADING for PJSIP**. Confirmed by direct code
  inspection and live testing:
  - `Snep_IpStatus_Manager::getTrunks($like)` filters
    `trunks.channel LIKE 'SIP%'`/`'IAX%'` — a PJSIP trunk's channel is
    always `PJSIP/<name>`, so PJSIP trunks are structurally **absent**
    from this page entirely, with no indication why.
  - `Snep_IpStatus_Manager::getPeers()` filters only `peer_type='R'`
    (matches every technology) — a PJSIP extension DOES appear in this
    list, but `ip_status_peers.php`'s own live-status AJAX call
    (`AMI::get_sippeer()`) is a chan_sip-only AMI action that returns
    nothing for a PJSIP peer, so its IP/latency columns show `N.D.`
    **forever** — indistinguishable from "still loading."
  - Disposition (Phase 19): **ISOLATE_AS_LEGACY**. Not REPLACE/EXTEND
    (chan_sip's flat peer/registry model and PJSIP's endpoint/AOR/
    contact/registration model are different enough that patching one
    mechanism to understand both would conflate two real object
    models, not simplify anything). Not REMOVE (queues status and any
    genuine legacy chan_sip/IAX rows a customer's install might still
    carry are still correctly served by it). A brand new, disjoint
    PJSIP-only surface (this task) avoids the "two contradictory status
    systems" trap by construction: the two systems cover non-
    overlapping technology scopes and neither claims authority over the
    other's objects.
- **`pjsip-transports` list (TASK-0020)**: already the correct,
  reusable template — `runtime_state` (`active`/`restart_required`)
  computed fresh on every page load from one bulk `pjsip show
  transports`-derived call, rendered as a `label-success`/`label-
  warning` badge with a `title` tooltip and a `data-runtime-state`
  attribute. **REUSABLE** as the UI convention (badge shape, tooltip,
  data-attribute) for the new extensions/trunks columns; its own
  narrower vocabulary (config-vs-runtime coherence) is intentionally
  NOT force-fit into the fuller registration/reachability vocabulary
  extensions/trunks need — see NORMALIZED STATUS MODEL.
- No other status/online/registered/reachable logic exists for PJSIP
  extensions or trunks anywhere in the codebase prior to this task.

## SCOPE

`senma-application-architect` was **not** invoked: `Snep_PjsipStatus_Manager`
is a new stateless service class in this codebase's own well-established
`Snep_X_Manager` pattern — no new table, no new API endpoint, no new
authorization boundary; it is called from the two existing `indexAction()`
methods exactly the way `Snep_PjsipTransports_Manager` already is.
`senma-docker-platform-engineer` was **not** invoked: every runtime
source is the existing `PBX_Asterisk_AMI::getInstance()->Command(...)`
mechanism already used throughout this codebase — no container/platform
dependency.

Changed:
- `snep/lib/Snep/PjsipStatus/Manager.php` (new) — the runtime-status
  service.
- `snep/modules/default/controllers/ExtensionsController.php`,
  `TrunksController.php` — one bulk status call each, merged into the
  existing row arrays as `runtime_status`.
- `snep/modules/default/views/scripts/extensions/index.phtml`,
  `trunks/index.phtml` — one new "Status" column, same badge/tooltip
  convention as the transport list.
- `Makefile`, `scripts/regression.sh` — new `pjsip-runtime-status-smoke`
  suite wired in.
- `scripts/pjsip-runtime-status-smoke-test.sh` (new).

Not changed: `IpStatusController` and everything under it (deliberately
isolated, see above); `pjsip-transports/index.phtml` and its own
`runtime_state` logic (already correct, not this task's concern).

**Carried-over, pre-existing debt found during this task, not part of
its own scope**: `snep/install/database/system_data.sql` still shows as
modified in `git status` — this is TASK-0029A's own `wss` seed-row
change (cert_file/priv_key_flle defaults, `enabled=true`), which that
task's own commit (`20bf7ed`) omitted. It is genuine, already-reviewed,
already-validated TASK-0029A content, not new work from this task; see
PROPOSED COMMIT for how it is handled.

## RUNTIME SOURCES

Two bulk AMI `Command()` calls, total, regardless of how many DB rows
exist on the page:

- `pjsip show endpoints` (no argument = every endpoint) — confirmed
  live to inline each endpoint's own `Aor`/`Contact` line(s) exactly
  like `pjsip show endpoint <name>` does for one, so ONE call answers
  "does this endpoint exist" and "what does its contact look like" for
  every extension AND every PJSIP/`PJSIP_EXTERNAL` trunk on the page.
- `pjsip show registrations outbound` — one call, used only for
  `reverse_auth=1` trunks.

Both calls are parsed by two private methods
(`parseEndpoints()`/`parseRegistrations()`) inside
`Snep_PjsipStatus_Manager` — no raw CLI text reaches a controller or
view; callers only ever see `array('state' => ..., 'detail' => ...)`.

## ENTITY-SPECIFIC SEMANTICS (Phase 2, all evidence live)

**A. Extensions.** Cross-references SENMA's own `peers.qualify` config
with Asterisk's live Contact status — neither source alone is enough
(confirmed live: a brand-new contact and a disabled-qualify contact
produce the IDENTICAL `NonQual` string in `pjsip show endpoints`; only
the DB's own qualify setting disambiguates "not monitored" from "first
check pending"):

| DB config | Live evidence | Status |
|---|---|---|
| — | no Contact line at all | INACTIVE — "No device registered" |
| qualify disabled | (any) | ACTIVE — "Registered -- reachability not monitored (qualify disabled)" |
| qualify enabled | Contact status `Avail` | ACTIVE — "Registered -- reachable (Xms)" |
| qualify enabled | Contact status `NonQual` | PENDING — "Registered -- reachability check pending" |
| qualify enabled | Contact status `Unavail` | DEGRADED — "Registered -- not responding to reachability checks" |

Multi-contact aggregation (ANY reachable/unmonitored → ACTIVE, only
DEGRADED if ALL contacts are failing) is implemented correctly for
N > 1 even though SENMA currently hardcodes `max_contacts=1` for every
endpoint it generates — there is nothing to prove live today, but
nothing to fix later either.

**B. Registered trunks (`reverse_auth=1`).** Authoritative source is the
OUTBOUND REGISTRATION object, not endpoint existence — confirmed live,
a registration can be `Rejected` while its endpoint object is still
perfectly "loaded." Real Asterisk 22 vocabulary observed live against
the project's own `provider` fixture: `Registered`, `Unregistered`
(transient), `Rejected` (stable terminal state on bad credentials).
`Request Sent`/`Auth Sent`/`Registering`/`Stopped` are parsed defensively
(the task's own Phase 11 candidate vocabulary) via prefix-matching on
the untouched remainder string — never positional token-splitting,
which breaks on `(exp. 3587s)`-style multi-word details captured live.
Mapped: Registered→ACTIVE, Rejected→ERROR, Unregistered/Registering/
Request Sent/Auth Sent→PENDING, Stopped→INACTIVE, anything else→UNKNOWN
with the raw state name in the detail (never fabricated).

**C. Registrationless trunks (`reverse_auth=0`).** Uses the exact same
`classifyContact()` logic as extensions (qualify config × Contact
status), applied to the trunk's static `trunk-<id>` AOR/contact (always
generated unconditionally by `Snep_PjsipTrunkConf`, confirmed by
inspection — this entity can never have zero contacts the way an
extension can). Proven live against a genuinely unreachable RFC 5737
TEST-NET-3 host with qualify enabled: DEGRADED. Per the task's own Phase
13 guidance, a qualify-DISABLED registrationless trunk is ACTIVE with
detail "Configured -- reachability not monitored" — deliberately NOT
claiming confirmed reachability, since none was checked.

**D. `pjsip_external` trunks.** SENMA never creates a `peers` row for
these (confirmed by `TrunksController::preparePost()`'s own explicit
comment) — the trust boundary is real, not assumed. Status is
existence-only against `trunks.username` (the referenced external
endpoint's name): found → ACTIVE ("SENMA does not manage its
configuration" stated explicitly in the detail text); not found →
ERROR. Read-only by construction — this service issues zero PJSIP
config writes anywhere. Proven live both directions, including the
harder case (an endpoint that WAS present when the trunk was created,
then disappeared from Asterisk's runtime independently — SENMA has no
way to know except by observing it, exactly the scenario this task
exists to surface).

**E. Transports.** Not modified. TASK-0020's existing `runtime_state`
(`active`/`restart_required`) and TASK-0029A's `apply_failed` flash
message remain the authoritative transport status mechanism, unchanged
— reusing its badge/tooltip visual convention for the new columns is
enough for a coherent cross-page UX without conflating two genuinely
different underlying models (a transport's own contract is "does saved
config match loaded config," not "is a remote peer registered/
reachable").

## NORMALIZED STATUS MODEL (Phase 3, DECISION)

```
ACTIVE    confirmed working right now (or, for a config-only entity
          with monitoring off, "loaded/configured as specified" --
          the entity-specific detail text always says which)
DEGRADED  loaded/registered, but a reachability check is failing
PENDING   a transitional runtime state (registering, or a reachability
          check not yet completed)
INACTIVE  no live counterpart at all (no contact/registration),
          without implying anything is broken
DISABLED  the SENMA row itself is disabled
ERROR     an explicit failure (rejected registration, referenced
          external endpoint missing)
UNKNOWN   the runtime query itself failed or returned something this
          parser does not recognize -- NEVER downgraded to any other
          state
```

Seven states, not the six sketched in the task's own Phase 3 example —
DISABLED was kept separate from INACTIVE deliberately: "the admin
turned this off" and "nothing has registered yet" are different enough
facts that collapsing them would make the badge lie by omission, per
the product-designer's own "state must be precise" principle.

## FRESHNESS MODEL (Phase 5, DECISION)

**Queried live on every page load, no caching, no polling, no new HTTP
endpoint.** Identical to the transport list's own already-accepted
pattern (TASK-0020) — the objective ("administrators lack a coherent
view") is fully satisfied by an accurate view on every page visit;
nothing in TASK-0028W's own gap analysis asked for live-without-reload
updates. Building a polling/AJAX layer for this would be new
infrastructure this task does not need (Phase 9's own "do not build
WebSocket/SSE... unless already available" instruction, extended to
"don't build a new polling endpoint either when a page load already
satisfies the actual gap"). Left as documented, explicit remaining
debt for a future task if a live-updating view is ever wanted.

## UNKNOWN/FAILURE CONTRACT (Phase 6, DECISION)

Two independent layers, confirmed live:

1. **Pre-existing, page-level.** `ExtensionsController::init()`/
   `TrunksController::init()` already construct `AsteriskInfo()`
   (predates this task) — if AMI is unreachable AT ALL, the whole page
   renders a generic "Erro! Falha na conexão com o servidor Asterisk"
   panel instead of any list at all. Confirmed live by stopping the
   `asterisk` container entirely: no fabricated per-row badge of any
   kind was rendered.
2. **New, per-call, inside `Snep_PjsipStatus_Manager::amiCommand()`.**
   Wraps every AMI `Command()` in try/catch; any failure (a thrown
   exception, or a malformed/missing `data` key) returns `null`, which
   every caller treats as "could not observe" and reports UNKNOWN with
   an explicit detail string — never silently reused as "empty/nothing
   found." This is the layer that matters if AMI is reachable but one
   specific command fails or returns something this parser does not
   expect; verified directly (a controlled bootstrap invoking
   `getExtensionStatuses()`/`getTrunkStatuses()` against a broken AMI
   dependency returned UNKNOWN for every row, not a fabricated
   INACTIVE/ERROR).

Neither layer was weakened, and neither ever produces a false "Offline"
for an observation failure.

## UX CONTRACT (Phase 7 — senma-product-designer)

- One badge per row, `label-success` (ACTIVE) / `label-warning`
  (PENDING, DEGRADED) / `label-default` (INACTIVE, DISABLED, UNKNOWN) /
  `label-danger` (ERROR) — reused verbatim from the transport list's own
  established convention, so the same color already means the same
  thing everywhere in the product.
- Never color-alone: every badge carries its own text label (Active/
  Pending/Degraded/Inactive/Disabled/Error/Unknown) translated through
  the existing `$this->translate()` mechanism.
- Detail/reason surfaces as a `title` tooltip on hover, in plain
  product language ("Registered -- reachable (0.3ms)", "Registration
  rejected by the provider"), never as raw Asterisk CLI text.
- A legacy (non-PJSIP) row renders a plain muted dash — `null` is a
  real, distinct product state ("this service does not cover this
  technology"), not silently coerced into any of the seven statuses.
- `data-runtime-status="..."` on every status cell — unambiguous for
  automated inspection (this task's own regression suite), mirroring
  TASK-0020's `data-runtime-state` precedent.
- Placement (Phase 8): the existing extensions and trunks LIST pages
  only, one new column each — the two operational surfaces an admin
  already visits, not a new dedicated status dashboard (explicitly out
  of scope: "general dashboard redesign").

## SECURITY (Phase 16)

Read-only throughout: `Snep_PjsipStatus_Manager` issues only `pjsip
show endpoints`/`pjsip show registrations outbound` AMI Command()
calls — no config write, no reload, no restart, nothing state-changing.
Both index pages already sit behind this application's existing session/
authentication plugin (confirmed live: an unauthenticated request
renders the login page, with zero `data-runtime-status` content — proven
by direct inspection, not merely assumed). No secret/password/private-
key material is ever placed in a status/detail string — confirmed live
by grepping every fixture's own configured secret against the rendered
pages.

## PERFORMANCE (Phase 17)

Two bulk AMI calls per page load, regardless of row count — confirmed
functionally (the same `pjsip show endpoints` bulk response inlines
every endpoint's own Contact lines, verified with 2+ endpoints in one
response) and by construction (`getExtensionStatuses()`/
`getTrunkStatuses()` each call `amiCommand()` exactly once, in a single
non-looping code path, before iterating DB rows in memory). No N+1 AMI
calls at any row count.

## LIVE PROOF (Phase 12-15, all via the real HTTP list pages)

- Extension, no device ever registered → **INACTIVE**.
- Extension, real baresip UA registered and answering OPTIONS → **ACTIVE**
  ("Registered -- reachable (0.2-0.3ms)").
- Extension, real WSS registration (TASK-0028Z's client, which
  deliberately never answers OPTIONS) → **DEGRADED** after a forced
  qualify check.
- Registered trunk, real REGISTER against the `provider` fixture
  succeeds → **ACTIVE**.
- Registered trunk, real REGISTER with deliberately wrong credentials
  against the same provider → **ERROR** ("Registration rejected").
- Registrationless trunk, RFC 5737 TEST-NET-3 host (genuinely
  unreachable), qualify enabled → **DEGRADED**.
- `pjsip_external` trunk referencing a real, currently-loaded external
  endpoint → **ACTIVE**.
- `pjsip_external` trunk referencing an endpoint removed from Asterisk's
  runtime after the trunk was created → **ERROR**.
- Asterisk stopped entirely → the pre-existing page-level connection-
  error panel, zero fabricated per-row badges; on restart, status
  reporting resumes correctly (bounded polling, since a freshly
  restarted trunk's registration needs a moment to re-settle).

## REGRESSION PROOF

New suite `scripts/pjsip-runtime-status-smoke-test.sh`: **14/14 PASS**,
run standalone twice consecutively. Covers every live-proof scenario
above through the real HTTP flow (never raw SQL), plus: no secrets leak
into rendered pages, and unauthenticated requests render no status data.

Affected pre-existing suites re-run individually, no regressions:
`call-smoke` (18/18), `trunk-smoke` (25/25), `pjsip-external-trunk-smoke`
(19/19), `pjsip-lifecycle-smoke` (36/36).

`make lint`: PASS (5/5 — 271 PHP files 0 syntax errors, 36 shell scripts
parse cleanly, 3 `resources.xml` well-formed, clean `git diff --check`).

`make regression`: two consecutive **PASS, 28/28 suites** (both attempts
clean on the first try — no flakes this time).

`git diff --check`: PASS. `git status --short`:

```
 M Makefile
 M scripts/regression.sh
 M snep/install/database/system_data.sql
 M snep/modules/default/controllers/ExtensionsController.php
 M snep/modules/default/controllers/TrunksController.php
 M snep/modules/default/views/scripts/extensions/index.phtml
 M snep/modules/default/views/scripts/trunks/index.phtml
?? scripts/pjsip-runtime-status-smoke-test.sh
?? snep/lib/Snep/PjsipStatus/
```

(`system_data.sql` is TASK-0029A carry-over, not new to this task — see
SCOPE and PROPOSED COMMIT.) Not committed — awaiting authorization per
CLAUDE.md's commit policy.

## REMAINING DEBT

Kept strictly separate from monitoring/history/alerting (explicitly out
of scope): no historical availability graphs, no alerting integration,
no CDR-analytics tie-in. Genuine, explicitly out-of-scope items:

- No live-updating (polling/AJAX) status column — page-load-fresh only,
  a deliberate Phase 5 decision, not an oversight; a future task could
  add bounded polling reusing this same service if ever needed.
- `IpStatusController`'s own chan_sip/IAX-only status remains exactly
  as misleading for PJSIP peers as it was before this task (a PJSIP
  extension still shows `N.D.` there forever) — deliberately left
  ISOLATE_AS_LEGACY rather than patched, per the disposition analysis
  above; a dedicated future task could add an explicit "this technology
  is not monitored on this page, see Extensions" note there if that
  confusion proves real in practice.
- TASK-0029A's own `system_data.sql` change was found uncommitted
  (that task's own commit omitted the file) — not new debt from this
  task, flagged for the commit step below.

## RECOMMENDATION

`APPROVE`.

## PROPOSED COMMIT

Two commits:

1. A small fix-up completing TASK-0029A's own already-approved,
   already-validated change (the file its commit omitted):
   ```
   fix(pjsip): include the wss seed-row cert defaults omitted from the TLS certificate management commit

   Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
   Claude-Session: https://claude.ai/code/session_01FP7YzWTLhPbMEVgpGAsNdv
   ```
   (path: `snep/install/database/system_data.sql` only)

2. This task's own feature, as one coherent commit (service, controller
   wiring, view, tests are one indivisible feature):
   ```
   feat(pjsip): add PJSIP runtime status visibility for extensions and trunks

   Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
   Claude-Session: https://claude.ai/code/session_01FP7YzWTLhPbMEVgpGAsNdv
   ```
   (paths: `Makefile`, `scripts/regression.sh`,
   `scripts/pjsip-runtime-status-smoke-test.sh`,
   `snep/lib/Snep/PjsipStatus/`,
   `snep/modules/default/controllers/ExtensionsController.php`,
   `snep/modules/default/controllers/TrunksController.php`,
   `snep/modules/default/views/scripts/extensions/index.phtml`,
   `snep/modules/default/views/scripts/trunks/index.phtml`,
   `docs/tasks/0029b-pjsip-runtime-status-visibility.md`)
