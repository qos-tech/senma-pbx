# TASK-0031 — Extensions + Trunks Administration Experience

Lead: senma-product-designer. Reviewers: senma-telephony-architect (trunk
connection-model mapping), senma-application-architect (save/apply
feedback generalization, dependency-check pattern). Implements the
Extensions/Trunks half of TASK-0030's split.

## CURRENT EXTENSION FLOW

List → Add (full-page form) → server-side `execAdd()` runs ~6 sequential
checks → on any failure, the form was discarded and the admin redirected
to a generic full-page error (all typed values lost) → on success, the
stored SIP secret and padlock PIN were echoed back into the rendered form
on every subsequent edit load (`value="<?php echo $this->extension['secret'];?>"`)
→ a bare, silent redirect to the list on success, no feedback of any kind
→ Delete pre-checked route dependencies (already good), but a raw
`PDOException::getMessage()` reached the user if the delete itself failed
at the DB layer.

## TARGET EXTENSION FLOW

```text
open → Basic (extension, name, group, credential, voicemail)
     → Advanced (collapsed: NAT, direct media, qualify, transport,
       DTMF, codecs, padlock, follow-me, BLF)
     → Diagnostics (edit only, read-only runtime status)
     → save
     → Saved and active / Saved, pending / Runtime apply failed
       (never a silent redirect)
```

Error path: a validation rejection re-renders the same form with
everything the admin already typed (`ExtensionsController::buildFormViewFromPost()`
+ `applyPjsipFormState()`), HTTP 200, not a redirect. Server errors
never include raw exception text.

## CURRENT TRUNK FLOW

One undifferentiated form covered every legacy technology
(SIP/IAX2/KHOMP/Virtual/SnepSIP/SnepIAX2/PJSIP/PJSIP_EXTERNAL) via
JS show/hide, even though the server only ever accepted `pjsip` or
`pjsip_external` -- every other branch was dead markup, unreachable
through the form's own two-option dropdown. The single biggest product
decision a trunk-creating admin makes -- registered vs. registrationless
vs. IP-authenticated vs. external -- was implied by a bare "Force reverse
authentication" checkbox, an opaque technical label. No save feedback of
any kind existed; a `loadConfFromDb()` failure inside the save path was
invisible.

## TARGET TRUNK CONNECTION MODELS

```text
select Connection Type:
  Provider with registration    -> technology=pjsip, reverse_auth=1
  Provider without registration -> technology=pjsip, reverse_auth=0, credentials shown
  IP-authenticated provider     -> technology=pjsip, reverse_auth=0, no credentials
  External PJSIP endpoint       -> technology=pjsip_external
→ only the fields relevant to that type
→ Advanced (collapsed)
→ save
→ registration/runtime result appropriate to the chosen type
```

`reverse_auth` is no longer a visible control -- it is derived by
client-side JS (`applyConnectionType()`, `trunks/addedit.phtml`) from
the Connection Type choice and carried as a hidden field, exactly the
"may remain an internal/derived persisted value" the task allowed. On
edit, `TrunksController::editAction()` derives which of the three
`pjsip` connection types a persisted row represents (reverse_auth +
whether a username is on file) purely to pre-select the right radio;
technology itself remains fixed on edit, unchanged from before this task.
Switching to IP-authenticated explicitly clears the username/secret
inputs (not merely hides them) so a save reflects the admin's expressed
intent rather than silently persisting stale credentials.

## FIELD CLASSIFICATION

Fields removed from the presented UI (not from the database -- every
one keeps receiving its existing fixed default via a hidden input, no
schema or persisted-value change):

| Field | Classification | Disposition |
|---|---|---|
| Trunk "Type" (peer/user/friend) | DEAD (no PJSIP meaning) | hidden input, `friend` |
| "Insecure" | DEAD (no PJSIP meaning) | hidden input, `` |
| "Channel Limit" | DEAD (no PJSIP meaning) | hidden input, `1` |
| "Dial Method" | DEAD (superseded by reverse_auth, TASK-0028Y) | hidden input, `normal` |
| IAX2 Trunking / Channel Technology / ID Regex / Board (Khomp) / Identifier (SnepIAX2) | DEAD (technology dropdown never offered these) | removed entirely, no hidden replacement needed (never reachable through the UI's own control) |
| Extensions' Khomp channel selector | DEAD (technology is fixed `pjsip`) | removed |
| Extensions' commented-out Minute Control markup + its live JS validation rules | DEAD | removed |

Fields reclassified CORE for their relevant connection type (previously
buried inside one undifferentiated "SIP" block): Provider address
(host), Username, Password, Monitor reachability (qualify) -- shown only
when relevant to the selected connection type per Phase 7.

## TERMINOLOGY

| Old label | New product label | Technical meaning |
|---|---|---|
| "Force reverse authentication" (checkbox) | Connection Type: "Provider with registration" | Creates a PJSIP registration object; SENMA sends the outbound REGISTER |
| "Remote Host" | "Provider address" | AOR contact / identify-match / registration-server target, depending on connection type |
| "Username" | "Account username" | PJSIP auth `username=`, shown only for credential-authenticated types |
| "Qualify" (yes/no/specify) | "Monitor reachability" | Enables periodic OPTIONS probing; the precondition for the Status column's ACTIVE/DEGRADED distinction |
| n/a | "External PJSIP endpoint" (kept, help text added) | SENMA creates no endpoint/AOR/auth object; only references, by name, an object provisioned entirely outside SENMA |

`transport`, `NAT`, and the extension "Password"/"Password Padlock"
naming were left as-is -- already reasonably clear to the technical
administrator audience these forms serve, per the task's own "do not
rename purely cosmetically" instruction. The Padlock PIN field now
carries explicit help text distinguishing it from the SIP password
above it.

## CREDENTIAL SECURITY

Both the extension's SIP secret/padlock PIN and the trunk's provider
password are never echoed back into the rendered HTML. The input's
`value` is always empty; the placeholder text distinguishes "create a
password" (add) from "leave blank to keep the current password" (edit).
Server-side, a blank submission on an update reuses the existing stored
value (`$update ? $resultGetId['secret'] : ""` in
`ExtensionsController::execAdd()`; the equivalent fallback to
`$ip_info['secret']` in `TrunksController::editAction()`) -- a blank
field means "unchanged," never "cleared." A fresh add is unaffected: a
blank secret there behaves exactly as it did before this task (an
existing, out-of-scope gap, not newly introduced or newly hidden).

## SAVE/APPLY FEEDBACK

Both controllers now call `Snep_PjsipStatus_Manager::checkApplyResult()`
(one new, shared method reusing the class's existing AMI parsers) after
every save, and never let the redirect alone imply success:

```text
SAVED_ACTIVE            -> endpoint confirmed loaded (registered trunk:
                            also confirmed Registered)
SAVED_PENDING           -> AMI unreachable (can't confirm yet), or a
                            registered trunk's registration is still in
                            progress -- never confused with apply failure
RUNTIME_APPLY_FAILED    -> endpoint confirmed NOT loaded, or a
                            registered trunk's registration was Rejected
SAVE_REJECTED           -> validation failure, form re-rendered (HTTP 200)
```

`RESTART_REQUIRED` was deliberately not implemented for either entity:
no evidence was found that any extension/trunk endpoint-level save ever
needs a hard Asterisk restart (PJSIP endpoint reload is dynamic,
TASK-0029B) -- restart-required stays exclusively a transport-level
concern (TASK-0020/0029A), consistent with "use only states actually
supported by backend/runtime evidence." Live-verified: a registered
trunk against the dev environment's test provider correctly shows
`SAVED_PENDING` ("Registration with the provider is still in progress"),
never a false `SAVED_ACTIVE`.

## VALIDATION

Unchanged classification, confirmed still correct: server-side checks
(uniqueness, PJSIP-only technology, transport existence/enabled, safe
config-value characters, live external-endpoint existence) remain
SERVER-AUTHORITATIVE; client-side jQuery Validate rules remain
CLIENT-CONVENIENCE only (verified they do not gate the real HTTP flow --
the regression suite's own creates bypass the browser entirely). The one
behavior change: a validation rejection now re-renders the submitted
form (`buildFormViewFromPost()`/`buildTrunkViewFromPost()` +
`applyPjsipFormState()`/`applyTrunkCheckedState()`) instead of
redirecting to a generic error page that discarded the input -- live
confirmed for both a duplicate extension number and a duplicate trunk
name.

## DELETE DEPENDENCIES

The existing route-dependency check (both entities, pre-existing,
already correct) is unchanged and confirmed not regressed. Queue/group
membership dependency checks were NOT added -- no backend introspection
capability for those exists today (`Snep_Extensions_Manager` has no
queue-membership query), and the task explicitly directs against
inventing a broad dependency scanner where no capability exists. Tracked
as `FOLLOW_UP_DEBT` below.

## ACCESSIBILITY

Added across both forms: explicit `for`/`id` label association on every
core field, `aria-required` on genuinely required fields plus a visible
`*` marker, `role="radiogroup"`/`role="group"` with `aria-labelledby` on
the NAT/DTMF/direct-media/qualify/connection-type control clusters
(previously bare `<label>` wrappers with no group semantics), and native
`<details>/<summary>` for the Advanced/Diagnostics sections (keyboard-
and screen-reader-operable disclosure with zero custom JS/ARIA needed,
rather than a hand-rolled collapsible).

## RESPONSIVE BEHAVIOR

Both list tables (Extensions: 6 columns, Trunks: 7 columns) now use
Bootstrap's existing `hidden-xs`/`hidden-sm` utility classes to collapse
the lowest-priority columns (Channel/Extension Group for Extensions;
Code/Type/Interface Type/Time Credit for Trunks) at narrow widths,
keeping Name/Status/Actions always visible. `footable` (present in the
asset tree but not wired to any table, and not proven compatible with
the existing DataTables initialization already on these same tables)
was deliberately not adopted here -- the plain Bootstrap utility-class
approach achieves the same "column priority over forced horizontal
scroll" outcome with no new JS-interaction risk. Transport table
responsiveness remains TASK-0032 scope.

## REGRESSION PROOF

New suite: `scripts/extensions-trunks-admin-experience-smoke-test.sh`
(`make extensions-trunks-admin-experience-smoke`), 25 checks, all
against the real application/Asterisk stack:

- extension create/edit still provisions a live PJSIP endpoint
- SIP secret/padlock PIN, and the trunk provider password, are never
  present in rendered HTML (extension and trunk)
- a blank password on edit keeps the existing secret unchanged
  (extension and trunk, confirmed via direct DB read)
- all four trunk connection types persist the correct
  technology/reverse_auth/username combination and provision a real,
  live PJSIP object (including a real external-endpoint fixture)
- dead legacy controls (Khomp channel selector, Minute Control, IAX2/
  KHOMP/Virtual/SnepSIP/SnepIAX2 markup) are absent from the rendered
  add/edit pages
- a validation rejection re-renders the form (HTTP 200) with the
  submitted values preserved, for both entities
- `ExtensionsController` contains no `error_message`/`getMessage()`
  concatenation (static check, covering all three occurrences the audit
  found, including the one inside `multiremoveAction()` a first pass
  missed and this suite caught)
- a save/apply flash renders on both list pages
- `checkApplyResult()`'s evidence basis holds live: a nonexistent
  endpoint name produces no `Endpoint:` line, and a real registered
  trunk's endpoint is confirmed loaded live
- the pre-existing route-dependency delete guard still blocks deletion
  and leaks no raw SQL/exception text (locale-independent check, since
  the guard's own message is translated to this environment's active
  pt-BR locale)
- unauthenticated requests render no extension data; a POST with no
  session/CSRF token is rejected

Also re-ran and confirmed clean: `trunk-smoke` (25/25),
`pjsip-external-trunk-smoke` (19/19), `pjsip-lifecycle-smoke` (36/36),
`pjsip-runtime-status-smoke` (14/14), `authorization-smoke` (17/17),
`authorization-coverage`, `call-smoke` (18/18) -- confirming the field/
markup restructuring did not change any accepted POST shape or break
TASK-0029B's status columns. Two full consecutive `make regression`
runs: **PASS, 30/30**, both clean on the first attempt.

## REMAINING DEBT

- Queue/group-membership delete-dependency checks: `FOLLOW_UP_DEBT`,
  needs a new `Snep_Extensions_Manager`/queue-membership query
  (`SMALL_BACKEND_CHANGE`) not built here.
- Trunks has no post-creation "Disable" action (only `enableAction()`
  exists) -- pre-existing gap, confirmed still present, out of this
  task's scope (a new capability, not a UI reorganization).
- Full removal of the dead IAX2/KHOMP/Virtual/SnepSIP/SnepIAX2
  backend/manager code remains its own follow-up task (this task only
  removed the now-unreachable-anyway UI controls, per the explicit
  "do not delete database columns/read compatibility" instruction).
- Transport UI/shared runtime primitives, responsive behavior, and
  status-vocabulary reconciliation remain TASK-0032 scope, untouched
  here.

## RECOMMENDATION

APPROVE.
