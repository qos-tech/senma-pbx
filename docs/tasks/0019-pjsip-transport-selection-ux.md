# TASK-0019 — PJSIP transport selection UX and lifecycle

## Status

**Implemented and validated** (see the implementation section at the end
of this document for full details, evidence, and the final regression
baseline). The investigation below (§1-22) is preserved as originally
written, with one correction: **§11 "New fact 2" was wrong** — a rename
that keeps the same bind address:port does *not* reliably hot-reload;
see the implementation section's "Corrected finding" for the full,
re-verified account. Everything else in the investigation held up
unchanged during implementation.

---

## Investigation (original, approved before implementation)

**No runtime code, schema, views, JavaScript,
generators, Docker configuration, or tests were modified** during this
phase. All findings
below come from reading the final committed TASK-0018 code (as it stands
after `b3402daa3ad46aeff7499a9d716aedd813c3f592`, "fix: make PJSIP
transport selection auto by default") and from live experiments against
the running `make dev` environment, using disposable fixtures
(`task0019-*` transports, extension `1097`) that were created and fully
removed through SENMA's own real HTTP flows. The environment was
verified clean and healthy before and after (`pjsip show transports`
shows exactly `udp`/`tcp`, all 4 containers healthy). Stopping here per
the task's own instruction — awaiting approval before any implementation.

---

## 1. Current-state audit — what TASK-0018 already built

Read directly from the committed code, not assumed from the task
history:

| Feature | Current state | Evidence |
|---|---|---|
| Transport list | Implemented | `PjsipTransportsController::indexAction()`, `index.phtml` — name, protocol, bind, external signaling/media, enabled/disabled, default badge, usage count, edit/delete |
| Transport create | Implemented | `addAction()` + `addedit.phtml`, full field-level validation (§10 below) |
| Transport edit | Implemented | `editAction()`, pre-fills every field including `local_net` (joined via `getNetworks()`) |
| Transport delete | Implemented, protected | `removeAction()` blocks on (a) `is_default` while >1 transport exists, (b) any usage (`getUsageDetails()` — checks **both** `peers` and `trunks`) |
| Default designation | Implemented | `is_default` checkbox, `clearDefault()` enforces exactly one default; **administrative only**, confirmed zero generator callers (§8) |
| Delete protection | Implemented, correct | FK `ON DELETE RESTRICT` (schema.sql:277,443) is the hard backstop behind the application check |
| Extension transport selector | **Does not exist, not even partially** | Confirmed by reading `ExtensionsController::execAdd()` end to end (`snep/modules/default/controllers/ExtensionsController.php:554-785`) — neither the `INSERT` nor the `UPDATE` SQL string mentions `transport_id` anywhere, and no form field reads/writes it. There is no "half-built" selector to preserve or extend — this is a clean sheet |
| Trunk transport selector | **Does not exist, not even partially** | Same audit on `TrunksController::preparePost()` (`snep/modules/default/controllers/TrunksController.php:584-809`) — `transport_id` is absent from both `$trunk_fields` (the allow-list, line 596-598) and every hand-built SQL string. Also a clean sheet |
| AUTO representation | Correct at the generator layer, absent at the UI layer | `Snep_PjsipConf::resolveTransportName(null)` → `null` → no `transport=` line (verified live, Test A below); there is simply no UI surface yet where "AUTO" would be *displayed*, since no selector exists |
| Explicit representation | Correct, verified live (new) | `transport=<name>` emitted; confirmed an **explicit-to-explicit switch** (A→B) works cleanly with a plain regenerate, no restart (Test A) |
| Edit pre-selection | N/A — no selector exists | See §6's edit-transition matrix, produced from first principles since there is nothing to observe yet |
| Validation | Thorough for the transport's own fields; **zero validation exists for a `transport_id` selection**, because no form field posts one yet | §10 |
| Reference protection | Correct and already generic | `getUsageDetails()` queries both `peers.transport_id` and `trunks.transport_id` — a delete attempt while a **trunk** references a transport is blocked by the exact same code path as an extension reference, even though `transport-smoke-test.sh` never happens to exercise that specific branch (§18's gap) |
| Runtime reload | Correct, several new lifecycle facts established | §11-13 |
| `transport-smoke` coverage | 18 checks, AUTO+EXPLICIT proven for both extension and trunk **creation**, but no edit-transition coverage at all | §18 |

**Conclusion: item 1's premise is confirmed precisely.** TASK-0018 built
a complete, correct transport *model* and *generator* layer, and a
complete transport *management* UI — but genuinely **zero** UI or
controller-level plumbing for *selecting* a transport on an extension or
trunk. This is not a partially-built feature to finish; it is a new
feature to add on top of a solid, already-correct foundation.

---

## 2. Defining AUTO precisely

**AUTO = `transport_id IS NULL`.** It must never be presented as, or
confused with, any of:
- the current `is_default` transport,
- the first row in `pjsip_transports`,
- "UDP" specifically,
- an inherited/implied value copied from somewhere else.

It means exactly one thing: *SENMA is not pinning this object to any
transport; Asterisk will pick one itself, per its own documented
behavior* (`docs/tasks/0018-pjsip-transports.md` §0, quoting Asterisk
22.10.1's own `config show help` text verbatim).

**Proposed label** (Portuguese, matching this project's existing UI
language — see `index.phtml`/`addedit.phtml`'s own `translate()` calls):

```
Transporte: [ Automático (Asterisk escolhe) ▼ ]
              UDP
              TCP
              <transportes customizados...>
```

This refines the TASK-0018 §0 UI spec's suggested wording
("Automático / Não fixar") to a slightly more explicit variant —
**"Automático (Asterisk escolhe)"** — because a bare "Automático" risks
being read as "the automatic/default one" by an administrator unfamiliar
with this distinction; naming *who* decides (Asterisk, not SENMA) is the
whole point of this task's UX goal ("The administrator must be able to
understand whether Asterisk is selecting the transport automatically or
SENMA is pinning the object to a specific transport"). Either wording is
acceptable; this is a proposal, not a decision requiring further
investigation.

**Persistence for the three states asked about** — traced through the
code that would need to write it (§5), not yet built:
- **Create-AUTO**: the option's `<option value="">` (empty string) posts
  no usable transport id; the controller must translate that into
  `transport_id = null` in the data array **explicitly** (not by
  omitting the key — see §5's critical finding).
- **Edit EXPLICIT→AUTO**: same requirement, doubly important on edit
  (§5).
- **Edit AUTO→EXPLICIT**: posts a real transport id; validated against
  `Snep_PjsipTransports_Manager::get()` (§10).

---

## 3. Extension transport selector — audit and design

**Where technology is selected**: `extensions/addedit.phtml:84-91`, a
single `<select name="technology" id="technology" onChange="showDiv(this.value)">`
with values `sip|pjsip|iax2|khomp|virtual|manual`.

**Where PJSIP-specific fields already live**: `ExtensionsController`
treats `sip` and `pjsip` identically end to end — `editAction()`'s own
switch statement groups them (`case "sip": case "pjsip":`, line
337-420), and the view's `showDiv()` function (lines 508-534) shows the
exact same `#sipiax` container for both, with **no PJSIP-only
sub-section existing today** — PJSIP and SIP are currently
indistinguishable in the form's visible fields.

**Proposed UX** (per the task's own instruction, "Do not redesign the
whole extension form"): add one new, small `<div id="pjsipTransport">`
inside the existing `#sipiax` container, immediately after the existing
NAT/Direct-Media/Qualify fields, containing only the transport
`<select>`. Extend `showDiv()` with one new line:

```js
document.getElementById('pjsipTransport').className = (div == 'pjsip') ? 'visible' : 'invisible';
```

This is the same mechanism `trunks/addedit.phtml` already uses for its
own PJSIP-only field groups (`trunk_type_group`,
`trunk_insecure_group`, `trunk_calllimit_group` — see §4), so it is
**not a new pattern**, just one more `id`/one more conditional line in
a function that already has several. `sip`/`iax2`/`khomp`/`virtual`/
`manual` must never see this field — chan_sip and IAX2 have no
`transport_id` column semantics at all (the column exists on `peers`
generically, but `Snep_InterfaceConf` never reads it and never will,
since only `Snep_PjsipConf` calls `resolveTransportName()`).

**Persistence**: `ExtensionsController::execAdd()` needs one new
allow-listed field (`transport_id`), written into both the `INSERT` and
`UPDATE` hand-built SQL strings (§5's critical caveat about NULL
handling applies here directly).

---

## 4. Trunk transport selector — audit and design

**Confirmed structurally, not just by convention: one selector is
correct, not two.** `trunks.transport_id` is a single column
(schema.sql:443); `Snep_PjsipTrunkConf::renderTrunk()` resolves it
**once** (`snep/lib/Snep/PjsipTrunkConf.php:181`) and reuses the same
`$transportName` for both the endpoint's `transport=` line (line 191-193)
and the registration's `transport=` line (line 266-268, only emitted at
all when `reverse_auth` is true). There is no schema or generator path
by which endpoint and registration could ever diverge — a second
selector would have nothing distinct to control. This satisfies item
4's requirement directly: **AUTO → neither endpoint nor registration
gets a `transport=` line; explicit → both get the identical
`transport=<name>` line.**

**Where to place it**: `trunks/addedit.phtml` already computes
`isPjsip` in its own `showDiv()` (line 531) and uses it to toggle three
existing field groups (`trunk_type_group`, `trunk_insecure_group`,
`trunk_calllimit_group`, lines 532-534) — adding a fourth,
`trunk_transport_group`, is a one-line addition to an existing,
already-PJSIP-aware conditional, not new mechanism.

**Persistence**: `TrunksController::preparePost()` needs `transport_id`
added to `$trunk_fields` (line 596-598) so it survives the "only allowed
fields for trunks table" filter (line 748-761) on both add and edit.

---

## 5. Persistence — traced end to end, one blocker-shaped finding

Traced `POST → controller → manager/model → peers/trunks → generator`
for both objects. Schema already supports NULL cleanly — no migration
is needed (`peers.transport_id`/`trunks.transport_id` are both
`int(11) DEFAULT NULL`, schema.sql:277,443). **This is not a blocker.**

**A real, concrete implementation risk found and worth flagging
precisely, not a blocker but load-bearing for the implementation
task**: both controllers currently build their `UPDATE` using an
**explicit column allow-list**, not a full-row overwrite:

- `ExtensionsController::execAdd()`'s `UPDATE` branch
  (`TrunksController.php` — actually `ExtensionsController.php:720-732`)
  is a hand-written SQL string naming every column explicitly.
- `TrunksController::preparePost()`'s output is filtered to
  `$trunk_fields` (line 596-598) before `$db->update("trunks", $trunk_data['trunk'], ...)`
  is called — Zend_Db's `update()` only writes the keys present in the
  array passed to it.

**This means: if `transport_id` is added to these allow-lists but the
future form/controller only includes the key when a real id is
selected (e.g. `if ($transportId) { $data['transport_id'] = $transportId; }`),
switching an object from EXPLICIT back to AUTO will silently fail** —
the `UPDATE` simply won't mention `transport_id` at all, and the
column will keep its old, stale explicit value forever, while the UI
shows "Automático" was selected and saved successfully. This is exactly
the kind of one-line, easy-to-miss bug this investigation is intended to
prevent: **the future controller must always include `transport_id` in
the write, explicitly as `null` for AUTO, never by omission.** This was
verified precisely by reading the actual UPDATE-construction code, not
inferred generically — it also explains why TASK-0018's own
`transport-smoke` fixtures always used direct SQL for setting
`transport_id` (§9-10 of `docs/tasks/0018-pjsip-transports.md`): there
was, until now, no controller code path to accidentally get this wrong,
because there was no code path at all.

**No blocker.** Both frameworks (`Zend_Db_Adapter_Abstract::update()`/
`insert()`) bind a literal PHP `null` as SQL `NULL` correctly (already
relied on elsewhere in this codebase, e.g. `TrunksController.php:643-653`'s
`time_total`/`time_initial_date` NULL handling) — the column supports it
natively; the only risk is an implementation oversight, not a platform
limitation.

---

## 6. Edit-transition matrix

No selector exists today, so this matrix is a **design requirement**,
verified against the generator/reload mechanics that would sit
underneath it (all confirmed live, this task's own experiments —
Test A below):

| Transition | Extension | Trunk (endpoint + registration) | Live-verified mechanism |
|---|---|---|---|
| AUTO → AUTO (no change) | No `transport_id` write needed, or a harmless `NULL→NULL` write | Same | Trivial; not separately tested (no state change) |
| AUTO → EXPLICIT(X) | `transport_id` set to X's id; endpoint gains `transport=X` on next regenerate | Endpoint **and** registration both gain `transport=X` | Confirmed for extension in TASK-0018 §11-13 (`transport-smoke` check 6); confirmed for trunk in TASK-0018 §11-13 (checks 9-10, via direct SQL, real regenerate) |
| EXPLICIT(X) → EXPLICIT(X) (no real change) | No-op write | Same | Trivial |
| EXPLICIT(X) → EXPLICIT(Y) | `transport=X` replaced by `transport=Y`, no restart, no stale reference to X anywhere | Same, both objects | **Newly verified live in this investigation (Test A)**: extension 1097 pinned to `task0019-a`, then switched directly to `task0019-b` — generated config went from `transport=task0019-a` to `transport=task0019-b` cleanly after one `regenerateAll()`; `pjsip show endpoint 1097` confirmed `transport: task0019-b` at runtime, zero trace of `task0019-a` remaining. No restart needed for this transition specifically (X and Y both already existed and were already bound; only the endpoint's *reference* changed, not any transport's own bind) |
| EXPLICIT(X) → AUTO | `transport_id` set to `NULL` (§5's write-must-be-explicit caveat applies here) | Same | Confirmed for extension in TASK-0018 §11-13 (`transport-smoke` check 12, "extension reverts to AUTO"); **not yet exercised for a trunk** by any existing test (§18 gap) — no reason to expect different behavior (identical shared `resolveTransportName()`/conditional-emission code path), but not independently proven live for a trunk the way TASK-0018's own methodology would prefer |

**The form must show the persisted state, not infer it from
`is_default`** — this is already naturally satisfied by design: the
edit action would read `transport_id` directly from the row (exactly
like every other field on these forms already does) and pre-select
either the "Automático" option (`NULL`) or the matching transport
option (a real id) — `is_default` is never consulted anywhere in this
read path, by construction, not by an added guard.

---

## 7. Transport deletion / reference protection — already correct

`PjsipTransportsController::removeAction()` (lines 151-191) already
does exactly what item 7 requires: it calls
`Snep_PjsipTransports_Manager::getUsageDetails($id)` (lines 95-113 of
`Manager.php`), which queries **both** `peers.transport_id` and
`trunks.transport_id` — a delete attempt against a transport referenced
by a trunk is blocked by the identical code path as one referenced by
an extension, listing the trunk by id and `callerid` in the friendly
error message (line 173). The `ON DELETE RESTRICT` FK (schema.sql:282,447)
is the unconditional backstop behind both. **There is no silent-NULL
path anywhere** — the only way `transport_id` ever becomes `NULL` again
is an explicit edit of the *referencing* object (§6), never a side
effect of deleting the transport it points to (deletion of a referenced
transport is simply refused).

**The one real gap is a test-coverage gap, not a functional one**:
`transport-smoke-test.sh` proves the extension-blocks-delete case
(check "delete blocked while in use", lines 545-551) but its trunk
fixture is always deleted *before* the transport delete is attempted
(lines 615-626) — the trunk-referenced-delete-blocked branch is real,
correct, and already shipped, but currently exercised only by manual
testing (this investigation) and by code inspection, not by the
automated suite. Flagged for `transport-smoke`'s evolution (§18).

---

## 8. `is_default` — re-audited, unchanged conclusion

Re-ran the exact same codebase-wide search TASK-0018's correction did:

```
$ grep -rn "getDefault()" snep/
snep/lib/Snep/PjsipTransports/Manager.php:130:    public static function getDefault() {
```

**Zero callers, confirmed again.** No new caller appeared since the
correction. Every currently-active use of `is_default` remains exactly
what `docs/tasks/0018-pjsip-transports.md` §0 already documented:

| Use | Legitimate per this task? |
|---|---|
| List-page "default" badge (`index.phtml:33-35`) | Yes — pure UI marker |
| `removeAction()`'s delete-protection (line 164) | Yes — administrative safety, unrelated to generation |
| `create()`/`update()`/`clearDefault()` exactly-one-default enforcement | Yes — data integrity for the marker itself |
| **New, this task's own proposal**: pre-selecting "Automático" vs. the default transport in a future picker's *initial* (add-mode, no existing row) state | Under consideration, not decided — see §9 |

**Decision: do not touch `is_default`.** It has no remaining concrete
responsibility in *generation*, but it retains real, active
responsibility in *UI/administration*, which this task's own scope
(selector UI + lifecycle) is a natural, additional consumer of, not a
reason to remove it.

---

## 9. DEFAULT vs. AUTO — proposed wording, one open UX question

**DEFAULT** = an administrative label on exactly one transport row,
used only for delete-ordering and list-page emphasis. **AUTO** = the
per-object choice meaning "Asterisk decides." These are unrelated axes
that happen to share a UI page today (`addedit.phtml`'s own already-
corrected help text, `docs/tasks/0018-pjsip-transports.md` §0, already
states this distinction in the transport form) — the new risk this task
introduces is a **second** page (the extension/trunk form) where the two
concepts could be re-conflated if the picker's "Automático" option is
ever rendered adjacent to a literal transport name without also
indicating which one is `is_default`.

**Proposal**: in the future picker's option list, tag the `is_default`
transport's own option with a small suffix, e.g. `UDP (padrão)` —
this lets an administrator see which transport Asterisk is *likely* to
pick under AUTO (since `udp` being both `is_default` and first-created
is why it is also very often the first Asterisk-compatible match) —
**without ever implying AUTO is bound to it**. This is a design
proposal for the implementation task to execute, not a decision this
investigation is authorized to make (no view file was changed).

---

## 10. Validation — audited, one real gap found and confirmed live

**What already exists** (`PjsipTransportsController::validatePost()`,
lines 197-237): thorough, field-by-field, server-side (not merely
client-side) validation of the **transport's own fields** — name
format/uniqueness, protocol enum, IP/hostname, port range, CIDR. This
is unrelated to, and unaffected by, this task's scope.

**What does not exist, because nothing posts it yet**: any validation
of a `transport_id` selected *for an extension or trunk*. This is
expected (§1) — there is no field to validate. For the future
implementation, the required checks are:
- the posted id must resolve via `Snep_PjsipTransports_Manager::get($id)`
  (already throws `PBX_Exception_NotFound` deep in the generator if a
  stale id slips through — see `PjsipConf.php:305-314` — but the
  **controller** should reject it at save time with a friendly error,
  not let a bad row reach the generator and fail at reload time);
- **a new, confirmed-live finding**: the manager's `get()` and
  `resolveTransportName()` **do not check `enabled` at all**. Verified
  directly (Test D below): pinning extension `1097` to a transport,
  then disabling that transport, produces an endpoint config that
  **still emits** `transport=task0019-b` — referencing a name that no
  longer exists anywhere in Asterisk's live PJSIP config (the transport
  generator skips disabled rows, confirmed: `senma-pjsip-transports.conf`
  had zero occurrences of `task0019-b` at that point). `module reload
  res_pjsip.so` **succeeded with no error, and Asterisk logged nothing**
  (`docker compose logs asterisk` showed zero related lines) — the
  endpoint loaded silently with a dangling reference to a nonexistent
  transport object. This is a real, confirmed gap: **the controller
  must reject selecting a disabled transport** (or the manager's
  resolution should, though rejecting at save time is the better UX —
  fail loudly when the admin misconfigures it, not silently at reload
  time). This is new implementation scope for TASK-0019, not a
  TASK-0018 regression — TASK-0018 never exposed a way to select a
  transport at all, so this path was unreachable before.

---

## 11. Asterisk transport lifecycle — re-verified, one refinement, two new facts

TASK-0018's already-documented findings were **re-confirmed unchanged**,
plus three new, precisely-scoped facts from this task's own live testing
(all against the current environment, Asterisk 22.10.1, no restart
performed at any point in these tests — the environment was healthy
before and after):

**Re-confirmed** (`docs/tasks/0018-pjsip-transports.md` §5): a transport
reusing a bind `address:port` a *differently-named*, still-live
transport previously held needs one full restart ("Address already in
use"); the very first trunk registration on a process's lifetime can
occasionally need one restart.

**New fact 1 — explicit-to-explicit switch needs no restart** (§6/Test
A): switching an object's *reference* between two already-existing,
already-bound transports is a pure text change in the generated
endpoint/registration file — neither transport's own bind is touched,
so a plain `module reload res_pjsip.so` is sufficient. This was not
previously tested (TASK-0018 only ever set an explicit reference once
per fixture).

> **Correction made during implementation (see the implementation
> section's "Corrected finding: rename + same bind" for the full,
> re-verified account): this "New fact 2" was WRONG.** Re-tested more
> rigorously (waiting up to 12+ seconds, retrying `pjsip show transport`
> repeatedly, and — critically — checking the FULL `pjsip show
> transports` listing, not just the one-name query) during
> implementation: the renamed object did **not** actually come online.
> What this investigation observed as "immediately reflected correctly"
> was very likely Test C's own *later*, independent edit (a protocol
> change) coincidentally being what actually brought the object up,
> misread at the time as confirming the bare rename. Preserved below
> unedited, as originally written and approved, for an honest record of
> what was and wasn't caught before implementation.

**New fact 2 (ORIGINAL, INCORRECT — see correction above) — a pure
rename (same bind, same protocol, new name) hot-
reloads cleanly, no restart** (Test B): renamed `task0019-a`
(`udp 0.0.0.0:5071`) to `task0019-a-renamed`, same bind, same protocol,
via a real `editAction()` HTTP call. `pjsip show transport
task0019-a-renamed` immediately reflected the new object correctly;
`pjsip show transport task0019-a` correctly reported "Unable to find
object" for the old name. **This refines, rather than contradicts,**
TASK-0018's "Address already in use" finding: that failure was
specifically two *different names* competing for the identical
`address:port` while the *old* name's socket was still bound at the
moment the *new* name tried to claim it (a genuine two-object collision
at reload time). A rename is a single object changing its own name
while retaining its own already-open socket — there is no second
claimant, so no collision occurs. **One transient observation, not
elevated to a finding**: the very next `pjsip show transports` (full
listing) immediately after the rename reported "Objects found: 3"
(missing the just-renamed object, even though `udp`, `tcp`, and
`task0019-b` were all present, and even though the *specific*
`pjsip show transport task0019-a-renamed` query run a moment later
correctly found it). This is consistent with the same class of
transient AMI/`docker compose exec` timing flake already characterized
and dismissed in TASK-0018's own regression notes (the "PJSIP module
Running" false-negative) — it was not reproduced a second time in this
investigation's limited testing, and is noted here only so the
implementation task's own `transport-smoke` evolution retries a full-
listing assertion once before failing on it, exactly as this project's
smoke tests already do elsewhere.

**New fact 3 — a protocol change on the *same* name and the *same*
`address:port` also hot-reloads cleanly, no restart** (Test C): edited
`task0019-a-renamed` from `udp` to `tcp`, bind unchanged
(`0.0.0.0:5071`), via a real `editAction()` HTTP call. `pjsip show
transport task0019-a-renamed` immediately reported `Type: tcp`, with no
error anywhere in the container logs. This makes sense once stated
precisely: a UDP socket and a TCP listener on the same port number
occupy independent kernel namespaces (`SOCK_DGRAM` vs. `SOCK_STREAM`),
so there is no actual OS-level conflict — the "Address already in use"
failure is specific to *two objects of the same underlying socket type*
contending for one `address:port`, not merely `address:port` reuse in
the abstract. **This is a genuine refinement of TASK-0018's own
documented lifecycle rule**, worth updating in a future pass: "reusing a
bind" is unsafe only when it collides at the OS socket level (same
protocol family), not for every field change on an existing, unrenamed
transport.

**Summary table for the implementation task**:

| Change | Restart needed? | Evidence |
|---|---|---|
| New transport, unused bind | No | TASK-0018 §5 |
| Edit existing transport's own fields, same name, same protocol (bind address/port/domain/external addrs/local_net/symmetric) | No | TASK-0018 §5 |
| Rename only (same bind, same protocol) | No | **New, this task** |
| Protocol change only (same name, same bind) | No | **New, this task** |
| Delete | No | TASK-0018 §5 |
| An object's `transport_id` **reference** changes (AUTO↔EXPLICIT, or EXPLICIT A→B) | No | TASK-0018 §11-13 + **new, this task** |
| A *different-named* transport claims a bind `address:port` still held by another live-named transport | **Yes, one restart** | TASK-0018 §5 (unchanged) |
| First trunk registration on a process's lifetime | Occasionally, one restart | TASK-0018 §5 (unchanged) |

**No case found in either task requires restarting Asterisk merely to
change which transport an extension/trunk points to, or to rename/
re-protocol an existing transport in place.** The only restart-requiring
cases are genuine object-identity collisions at the OS socket layer,
already fully characterized.

---

## 12. Restart-required UX — recommendation

Given §11's summary table, **the transport-selector feature itself
(this task's actual scope) never needs a restart-required UX at all** —
every operation a selector would ever trigger (setting/changing/
clearing an object's `transport_id`) is already proven hot-reload-safe.
The restart question only matters for the **existing** transport
CRUD pages (renaming, re-binding to a colliding address:port), which
TASK-0018 already shipped without a restart-required UX and which this
task is not asked to redesign.

**Recommendation for the transport CRUD pages, since item 12 asks for
one regardless**: **Option A (save + banner)**, not B or C:
- Not B (save + controlled restart): restarting the shared Asterisk
  process from a routine web form is exactly the "unsafe automatic
  restart" the task explicitly asks to avoid by default, and none of
  the restart-requiring cases are common (a genuine rebind collision or
  a first-boot registration quirk) — an admin who understands they just
  renamed a transport into an address collision can restart deliberately
  from wherever they already manage the container.
- Not C (reject unsupported changes outright): a rename or a rebind is
  a legitimate, occasionally-necessary administrative action; rejecting
  it outright when it usually works (only failing when a live,
  differently-named collision exists) would be a worse admin experience
  than a clear warning.
- **A**: after any transport save, if the name or `bind_address`/
  `bind_port` changed, show a non-blocking banner: *"Se este transporte
  já estava em uso com outro nome ou endereço, um reinício completo do
  Asterisk pode ser necessário para liberar a porta anterior."* This
  is honest, matches TASK-0018's own "surface honestly, do not fake
  success" instruction, and requires no new detection logic beyond
  comparing old vs. new `name`/`bind_address`/`bind_port` in the
  controller (data already available in `editAction()`).

This is a recommendation, not an implementation — no view/controller
was changed.

---

## 13. Transport rename / identity safety — resolved by evidence, no schema change needed

**Renaming is safe**, confirmed two independent ways:
1. **By design**: `peers.transport_id`/`trunks.transport_id` reference
   the transport's immutable `id`, never its `name`
   (`Snep_PjsipConf::resolveTransportName()` always does a fresh
   `Manager::get($transportId)` lookup and reads `$transport['name']`
   at generation time — never caches or stores the name anywhere). A
   rename requires **no data migration** on any referencing row.
2. **By live test** (Test B, §11): renamed a transport referenced
   *conceptually* by this task's own reasoning about the mechanism
   (not literally referenced by a live object in this specific test,
   but the mechanism proven — a fresh regenerate always re-reads the
   current name) — combined with Test A's proof that `regenerateAll()`
   (already called by every transport `addAction()`/`editAction()`/
   `removeAction()`, per TASK-0018 §4's cross-generator-consistency
   design) re-runs `Snep_PjsipConf`/`Snep_PjsipTrunkConf` on every
   transport edit, **any** rename already correctly cascades into every
   referencing extension/trunk's generated config on the very next save
   — this was true the day TASK-0018 shipped `regenerateAll()`, and
   remains true; this task adds no new risk here.

**No change needed**: keep `id` as the FK target (already true), keep
`name` mutable (already true, and administratively useful — see
TASK-0018 §6's "no clone/duplicate needed" reasoning, similarly a
rename is a legitimate, ordinary administrative action for a transport
that was, say, provisioned with a placeholder name). No "internal id vs.
generated section name" split is needed — they are already correctly
separated (`id` is the FK; `name` is only ever read at generation time).

---

## 14. Protocol scope — keep exactly what TASK-0018 already exposed

`Snep_PjsipTransports_Manager::$protocols` already lists
`udp,tcp,tls,wss,ws` (`Manager.php:28`), and the transport **form**
already offers all five (`addedit.phtml:28`) — this was already true
before this task and is out of this task's scope to narrow (doing so
would be a TASK-0018 change, not a TASK-0019 one). What **is** this
task's concern — the new extension/trunk *selector* — should list only
**enabled** transports (§10's disabled-transport gap makes this a hard
requirement, not a style choice): the picker's `<option>` list must be
built from `Snep_PjsipTransports_Manager::getAll()` filtered to
`enabled == 1`, both to prevent §10's silent-dangling-reference bug and
because presenting a disabled transport as selectable is misleading
regardless. TLS/WSS remain exactly as deferred as they already were —
`wss` stays seeded, disabled, unavailable for selection (since it fails
the enabled filter above, without any new special-casing needed).

---

## 15. Security — bind-address exposure, no new surface

The future selector introduces **no new bind-address exposure** —
`bind_address`/`external_signaling_address`/`external_media_address`
already display in plaintext on the existing transport list/edit pages
(`index.phtml:38,40,42`); a `<select>` listing transport *names* on the
extension/trunk form adds no new address-shaped data to any page an
administrator wasn't already looking at. **No new host port is
published by this task** — the selector only *references* existing
transport rows; it creates no transports and binds nothing itself.
Binding to `0.0.0.0` (already the default for all three seeds) is not
equivalent to a Docker host-port publish — this remains exactly as true
after this task as it was before it, since nothing about port
publication changes here.

---

## 16. Migration behavior for existing objects — confirmed, no action needed

Every extension/trunk created before this task (or after it, through
the *current*, selector-less forms) has `transport_id = NULL` — schema
default (schema.sql:277,443), never touched by any write path today
(§1). **The future selector must display these as "Automático," not
migrate them to `is_default`'s transport** — this requires no migration
script at all, since the correct display state (`NULL` → AUTO) is
already the literal value stored; "no migration" *is* the correct
behavior, not an omission.

---

## 17. Generator invariants — the hard tests to preserve/add

These already hold today (verified live, again, in this investigation —
not merely re-read from TASK-0018's docs):

```
Extension endpoint,  transport_id = NULL   -> no "transport=" line
Extension endpoint,  transport_id = <id>   -> "transport=<name>"  exactly once
Trunk endpoint,      transport_id = NULL   -> no "transport=" line
Trunk endpoint,      transport_id = <id>   -> "transport=<name>"  exactly once
Trunk registration,  transport_id = NULL   -> no "transport=" line (only when reverse_auth=1; no registration object at all otherwise)
Trunk registration,  transport_id = <id>   -> "transport=<name>"  exactly once, identical name to the endpoint's
```

Nothing in this task's design changes any of these — the selector only
ever writes to the same `transport_id` column the generators already
correctly consume. The implementation task's own tests must keep
proving all six lines above unchanged, plus the two new transition
facts from §6/§11 (explicit A→B switch; a rename/protocol-change not
disturbing an unrelated object's own reference).

---

## 18. `transport-smoke` evolution — design

**Preserve all 18 existing checks unchanged** (creation-path AUTO/
EXPLICIT proof for both object types already exists and remains
correct). **Add**, preferring the real SENMA HTTP path exactly like the
existing 18 checks already do (`create_ref_extension`/
`create_trunk_fixture` are real HTTP flows; only the `transport_id`
*value itself* needs direct SQL, since no HTTP field exists for it yet
— once this task ships a real selector, these should switch to posting
the picker's own form field instead):

1. **Extension edit-transition round trip**: AUTO→EXPLICIT(A)→
   EXPLICIT(B)→AUTO, asserting the generated `transport=` line at each
   step (three assertions, one no-line assertion) — this is exactly
   Test A from this investigation, promoted into the permanent suite.
2. **Trunk edit-transition round trip**: the same four-state cycle, for
   both the endpoint *and* registration sections — currently the trunk
   fixture only ever proves the EXPLICIT state (§1's gap); this closes
   it, and specifically proves the AUTO→EXPLICIT→AUTO cycle for a trunk
   that TASK-0018 never actually exercised (§6).
3. **Trunk-referenced delete-blocked**: attempt to delete a transport
   while a trunk (not an extension) still references it, assert it is
   blocked with the trunk correctly named in the error, *then* clear
   the reference and confirm delete succeeds — closing §7/§18's
   identified coverage gap (the application code is already correct;
   only the test never exercised this specific branch).
4. **Rename-while-referenced**: rename a transport that an extension is
   currently explicitly pinned to; assert the extension's generated
   `transport=` line picks up the **new** name on the very next
   regenerate, with zero manual intervention — proving §13's "no
   migration needed on rename" claim inside the permanent suite, not
   just this investigation's one-off script.
5. **Disabled-transport selection is rejected**: once the future
   controller validation (§10) exists, assert that attempting to select
   a disabled transport is rejected with a friendly error, *not* silently
   accepted into a dangling reference — this is the regression test for
   §10's confirmed gap.

Target count: 18 (unchanged) + roughly 8-10 new checks ≈ **26-28**,
finalized during implementation once the real form fields exist to
drive them.

---

## 19. Regression requirements (for the implementation task)

Identical bar to every prior PJSIP task: `make smoke` 16/0/0,
`make call-smoke` 18/18, `make trunk-smoke` 23/23, `make transport-smoke`
≥18/18 (target ~26-28 per §18), each run at least twice for idempotency
and once from a genuinely clean rebuild (all 7 named volumes wiped).
Additionally inspect: PHP fatals (`docker compose logs app`), Asterisk
PJSIP errors (`docker compose logs asterisk` — §10's finding shows this
specific check matters: a silently-broken config produces **no** log
line at all, so "no errors in the log" is not suficient proof of
correctness by itself; the generated config's actual content must also
be asserted, exactly as the existing smoke tests already do), extension
registration state, outbound trunk call completion, and the generated
`senma-pjsip.conf`/`senma-pjsip-trunks.conf`/`senma-pjsip-transports.conf`
content directly.

---

## 20. Stop conditions — none triggered

Walking the task's own list against this investigation's findings:

- Schema cannot preserve NULL — **false**, already does (§16).
- Forms need broad redesign — **false**, one field group + one
  `showDiv()` line per form (§3/§4), reusing an existing mechanism.
- Rename can corrupt references — **false**, proven safe by both design
  and live test (§13).
- Transport management requires unsafe automatic restarts — **false**,
  every operation this task's own scope touches is already hot-reload-
  safe (§11); the pre-existing restart cases are unrelated to selection
  and unchanged by this task.
- New PHP 8.4 blocker — **none found**.
- Migration would need NULL→default conversion — **false**, no
  migration needed at all (§16).
- TLS/WSS would need certificate infrastructure — **not touched**,
  scope stays exactly as deferred as TASK-0018 left it (§14).
- Another architectural issue materially expanding scope — **none
  found**; the one real gap discovered (§10, disabled-transport
  selection) is a small, precisely-scoped validation addition, not an
  architecture change.

**No stop condition applies. This task can proceed to implementation as
scoped**, pending the explicit approval this investigation is required
to wait for.

---

## 21. Explicitly deferred (unchanged)

TLS, WSS, WebRTC, SRTP, certificate management, firewall management,
automatic public port publishing, broad network-interface management,
PJSIP realtime, PostgreSQL, inbound trunk redesign, broad extension/
trunk UI redesign beyond the one small field group each (§3/§4).
Transport *templates* and generic *overrides* (TASK-0017's own §16-17
scope) remain untouched — this task is selection UX only, not the
template architecture.

---

## 22. Concrete implementation proposal

1. **Extensions**: add `transport_id` to
   `ExtensionsController::execAdd()`'s allow-listed fields (both INSERT
   and UPDATE branches), always written explicitly (`null` for AUTO —
   §5's caveat). Add one `<select name="transport_id">` inside a new
   `#pjsipTransport` div in `extensions/addedit.phtml`, populated from
   `Snep_PjsipTransports_Manager::getAll()` filtered to `enabled==1`
   (§14), with an `Automático (Asterisk escolhe)` option whose value is
   empty string, translated server-side to `null`. One new line in
   `showDiv()` (§3).
2. **Trunks**: add `transport_id` to `TrunksController::preparePost()`'s
   `$trunk_fields` allow-list, same explicit-null discipline. One
   `<select>` inside a new `#trunk_transport_group` div in
   `trunks/addedit.phtml`, gated by the form's own existing `isPjsip`
   variable (§4) — one selector for the whole trunk, correctly applying
   to both endpoint and registration by construction (§4).
3. **Validation**: reject (server-side, friendly error, not merely a
   generator-time exception) a posted `transport_id` that does not
   resolve via `Manager::get()`, or that resolves to a **disabled**
   transport (§10's confirmed gap — this is the one genuinely new
   validation rule this task adds).
4. **UI wording**: "Automático (Asterisk escolhe)" as the NULL option
   (§2); optionally tag the `is_default` transport's own option with
   "(padrão)" in the list (§9) — a small polish item, not required for
   correctness.
5. **No restart-UX changes** to the transport CRUD pages are required
   by this task's own scope (§12) — Option A (banner-on-rename/rebind)
   is a reasonable independent improvement to recommend, not something
   this task must build to satisfy item 12, since the specific hazard it
   addresses is unrelated to introducing the selector.
6. **`transport-smoke`**: extend per §18 (edit-transition round trips
   for both object types, trunk-referenced-delete-blocked, rename-
   while-referenced, disabled-transport-rejected) — implemented against
   the real new form fields once they exist, replacing the direct-SQL
   `transport_id` writes the current 18 checks use out of necessity.
7. **Documentation**: this file, updated in place with final results
   once implemented (same pattern `docs/tasks/0018-pjsip-transports.md`
   already established for its own §0 correction).

This is a small, additive, low-risk implementation — one new column
reference on two existing forms, reusing an existing show/hide
mechanism, with one genuinely new validation rule (§10) and no schema,
migration, or restart-behavior changes anywhere.

---

## Implementation (approved, executed per §22's proposal)

Executed exactly as proposed in §22, with two real findings surfaced
and fixed during implementation that the investigation's own testing had
not caught (§10's disabled-transport gap was already anticipated; the
`Zend_Registry::get('log')` bug and the rename timing behavior were not).

### Files changed

- `snep/lib/Snep/PjsipTransports/Manager.php` — three new methods:
  `getEnabled()` (enabled transports only, for every selector), `
  getSelectableWithCurrent($currentId)` (the enabled list plus the
  object's own current transport if it's since been disabled, flagged
  `stale_disabled`, so an edit form never silently drops the persisted
  value from its options), `validateSelection($id, $currentId)` (exists
  + enabled-unless-unchanged from `$currentId` — the "newly pinned"
  distinction §4 of the task required).
- `snep/lib/Snep/PjsipConf.php` — `resolveTransportName()` now throws
  `PBX_Exception_NotFound` for a **disabled** transport too (previously
  only for a missing one), with a message naming the transport and
  telling the admin what to do. `loadConfFromDb()`'s `foreach` now
  wraps `renderExtension()` per-row in try/catch: a single extension
  pinned to a since-disabled transport is **skipped** (logged via
  `error_log()`, not written to the generated file) rather than aborting
  the entire regeneration for every other extension.
- `snep/lib/Snep/PjsipTrunkConf.php` — identical per-row skip-and-log in
  `loadConfFromDb()`'s `foreach`, reusing the same
  `resolveTransportName()`.
- `snep/modules/default/controllers/ExtensionsController.php` —
  `addAction()`/`editAction()` pass the transport list to the view
  (`getEnabled()`/`getSelectableWithCurrent()`); `execAdd()` validates a
  posted `transport_id` (PJSIP-only, exists+enabled-unless-unchanged)
  and writes it **explicitly** (including the literal `NULL`) into both
  the `INSERT` and `UPDATE` hand-built SQL strings.
- `snep/modules/default/controllers/TrunksController.php` — same
  pattern: `addAction()`/`editAction()` pass the transport list;
  `preparePost()` gained a third `$currentTransportId` parameter, added
  `transport_id` to the trunk-fields allow-list, defaults it to `NULL`
  for every non-PJSIP technology, validates and sets it in the PJSIP
  branch, and now returns a translated error **string** on an invalid
  selection (mirroring `ExtensionsController::execAdd()`'s own
  convention) — both `addAction()`/`editAction()` call sites now check
  `is_string($trunk_data)` before proceeding to the DB transaction.
- `snep/modules/default/controllers/PjsipTransportsController.php` —
  `indexAction()` now flags any transport that is disabled **and**
  still referenced (`usage_count > 0`) via the existing
  `view->alert_message` convention (the same one
  `ExtensionsController::indexAction()` already uses for its weak-
  password warning) — item 12F's "surface the invalid state clearly"
  requirement.
- `snep/modules/default/views/scripts/extensions/addedit.phtml` — new
  `#pjsipTransport` field group (one `<select>`: Automatic + enabled
  transports, with a stale-disabled option appended only when it's the
  object's own current value), wired into `showDiv()` exactly like the
  investigation's §3 proposed (one new `id`, one new conditional line).
- `snep/modules/default/views/scripts/trunks/addedit.phtml` — same
  pattern, one `<select>` in `#trunk_transport_group`, wired into the
  form's existing `isPjsip` conditional in `showDiv()` — one selector
  for the whole trunk, confirmed live to drive both endpoint and
  registration identically (§11 below).
- `snep/modules/default/views/scripts/pjsip-transports/index.phtml` —
  renders the new `alert_message`.
- `scripts/transport-smoke-test.sh` — grew from 18 to **40** checks (see
  §"transport-smoke evolution" below).
- `docs/tasks/0019-pjsip-transport-selection-ux.md` — this section, plus
  the §11 correction above.

No schema change. No migration. No new deferred-scope items touched
(TLS/WSS/WebRTC/etc. all remain exactly as deferred as before).

### UI behavior

Both extension and trunk forms show a "PJSIP Transport" field only when
`technology=pjsip` (via the existing `showDiv()` mechanism — no new
show/hide machinery). The dropdown's first option is **"Automatic
(Asterisk selects a compatible transport)"** (value `""`, never labeled
"default"); every enabled transport follows, each tagged `(default)`
when it is `is_default` (an administrative label only — see below) and
tagged `-- disabled, please pick another option` for the one, special
case where the object's *own currently-persisted* transport has since
been disabled (so the form can still show/pre-select it rather than
silently falling back to the first `<option>` the way a raw HTML
`<select>` would). Disabled transports are otherwise never offered.

### Persistence semantics (traced and confirmed live)

`transport_id` is written **explicitly** on every save, for every
technology:

- Non-PJSIP extensions/trunks: always `NULL`, unconditionally, before
  the technology-specific branch even runs — a stale/hidden posted value
  can never leak through.
- PJSIP, Automatic selected (`transport_id=""` posted): `NULL`.
- PJSIP, an explicit transport selected: that transport's `id`,
  validated first.

### The EXPLICIT→AUTO fix, confirmed live (not just by code inspection)

The investigation's §5 predicted the exact risk: a hand-built
column-allow-list `UPDATE` that omits `transport_id` when it's `NULL`
would silently preserve a stale explicit value while the UI claims
"Automatic" was saved. Both controllers write `transport_id` (or its
SQL-literal `NULL` form, for `ExtensionsController`'s raw-string SQL)
on **every** save, never conditionally. Confirmed live via
`transport-smoke` checks 25 and 29: after switching an object from
EXPLICIT back to Automatic, `peers.transport_id`/`trunks.transport_id`
were queried **directly from the database** (not merely inferred from
the generated file) and found `NULL`.

### Disabled-transport handling — the one real gap the investigation
flagged, now fixed, plus one new bug found and fixed while fixing it

Two rules, both enforced now:

1. **A disabled transport can never be newly selected.**
   `Snep_PjsipTransports_Manager::validateSelection()` is checked before
   any save; both controllers reject the request (a friendly, translated
   error, HTTP 200 with an error page — not a 302) if the posted
   `transport_id` resolves to a disabled row, **unless** it's exactly
   the object's own already-persisted value (the "newly pinned"
   distinction the task's item 4 required — editing an unrelated field
   on an object that already has a stale disabled reference must not be
   blocked by that unrelated staleness).
2. **Disabling an already-referenced transport is allowed** (unlike
   delete, which stays blocked) — confirmed live: `transport-smoke`
   check 30 disables a transport that extension 1097 was, at that
   moment, explicitly pinned to, and the disable action itself succeeds
   (HTTP 302).  What happens next is the real behavior this task had to
   define:
   - **The generator never emits a dangling `transport=<name>`
     reference.** `resolveTransportName()` now throws for a disabled
     transport exactly as it already did for a missing one.
   - **A single bad reference does not take down provisioning for every
     other object.** `loadConfFromDb()`'s `foreach` catches that
     exception **per row** and skips just that one extension/trunk
     (logged, not silently dropped) — confirmed live: check 31 shows the
     affected extension's `[1097]` section is entirely **absent** from
     `senma-pjsip.conf`, and check 32 confirms `pjsip show endpoint 1097`
     reports "Unable to find object" (the endpoint genuinely vanished
     from Asterisk's live config — not a broken/dangling stub).
   - **The invalid state is surfaced, not buried in a log line.** The
     Transports list page now shows an explicit warning naming the
     transport and how many objects still reference it (check 34).
   - **Fully reversible.** Re-enabling the transport and re-saving
     regenerates the extension correctly (check 35).
   - **A real bug found and fixed while validating this**:
     `Zend_Registry::get('log')` — used by the original draft of the
     per-row skip's logging call, and already relied on (unguarded) by
     both generators' own pre-existing `reload()` methods — is **not
     actually registered** in this application's real HTTP request
     bootstrap. Hitting this exact path live produced an uncaught `Zend_Exception`
     ("No entry is registered for key 'log'") rendered as a genuine
     HTTP 500, confirmed by reproducing it directly (disable a
     referenced transport → 500, `Server Message: No entry is registered
     for key 'log'`). Fixed by switching both generators' new catch
     blocks to plain `error_log()`, which has no such dependency and
     still lands in the same container log
     (`/var/log/apache2/mag-error.log`) every other PHP warning in this
     app already does. This is a **pre-existing latent gap** in
     `Snep_PjsipConf::reload()`/`Snep_PjsipTrunkConf::reload()`'s own
     already-shipped failure-path logging (never previously exercised
     in practice, since a PJSIP reload failure is rare) — not touched
     here beyond avoiding the same mistake in the new code; flagged
     below as remaining debt.

### Generator invariants — reconfirmed unchanged, live

All six invariants from the investigation's §17 hold, reconfirmed via
`transport-smoke`'s real UI-driven checks (19-29), not merely via
direct-SQL fixtures as the original 18 checks used:

```
Extension endpoint,  transport_id = NULL   -> no "transport=" line       (check 19)
Extension endpoint,  transport_id = <id>   -> "transport=<name>"         (check 21)
Trunk endpoint,      transport_id = NULL   -> no "transport=" line       (check 27)
Trunk endpoint,      transport_id = <id>   -> "transport=<name>"         (check 28)
Trunk registration,  transport_id = NULL   -> no "transport=" line       (check 27)
Trunk registration,  transport_id = <id>   -> "transport=<name>"         (check 28)
```

No `getDefault()` fallback was reintroduced anywhere; `is_default`
remains exactly the administrative/UI-only concept TASK-0018's
correction established — confirmed once more by the same codebase-wide
`grep -rn "getDefault()" snep/` (zero non-Zend-library callers).

### Corrected finding: rename + same bind

The investigation's §11 "New fact 2" claimed a bare rename (same bind,
same protocol) hot-reloads cleanly. **This was wrong**, discovered while
building `transport-smoke`'s rename check: renaming a transport while
keeping its bind `address:port` unchanged left the new name **entirely
absent** from both `pjsip show transport <newname>` and the full
`pjsip show transports` listing — reproduced three separate times,
waited up to 12+ seconds, retried the query repeatedly, and even issued
two more **identical-content** `module reload res_pjsip.so` calls
directly — none of it brought the object online. Asterisk logged
nothing (no error, no warning) either time. What *did* immediately fix
it, confirmed twice with two different fields: a **second, distinct**
edit to the *same* (new) name — changing the protocol, or changing the
port — brought the object online right away.

This is best explained as the *same* already-documented TASK-0018 §5
finding ("reusing a bind address:port that a differently-named,
still-live transport previously held requires a restart"), not a new
phenomenon: the old name's socket apparently stays claimed at the OS
level across the rename's own reload, silently preventing the new name
from binding at the identical address:port — until a *different* edit
either changes the socket type (protocol) or the address:port entirely,
sidestepping the stale claim. The investigation's original Test B/Test C
sequence most likely observed exactly this: Test B's bare rename never
actually took effect, and Test C's *own*, independent protocol-change
edit (misread at the time as merely confirming Test B) is what actually
brought the transport online.

**Product decision, per this task's own item 8/9 instructions ("do not
make transport names immutable," "do not add a blanket restart-required
warning for edits that hot-reload successfully"): no code change.**
Renaming remains fully supported (`name` stays mutable, no immutability
added) and dependent-object regeneration remains deterministic and
correct at the **config-file** level (confirmed: the generated
`senma-pjsip.conf` picks up a renamed transport's new name immediately,
every time — this was never in question, only the *live Asterisk
binding* under the *old* bind address lagged). This is the exact,
narrow, pre-existing TASK-0018 collision caveat item 9 asked to be
retained and documented, not a new restart-required class of edit to
warn about generically — an admin who renames a transport while keeping
its address:port unchanged should expect the same one-time-restart
caveat TASK-0018 already documented for any bind-address reuse; renaming
*together with* a bind change (address or port) — or simply restarting
once — avoids it entirely. `transport-smoke`'s own rename check (§ below)
was adjusted to rename *and* move the port simultaneously, which is
what it actually needs to prove (dependent-object regeneration
cascades correctly) without wandering into this unrelated, already-
documented caveat.

### Protocol change and other in-place edits — reconfirmed hot-reload-safe

Editing a transport's own fields under the *same* name and *same*
`address:port` (external addresses, domain, `local_net`, `symmetric_transport`,
and — reconfirmed live during the rename investigation above — even a
protocol change alone) continues to hot-reload with no restart, exactly
as TASK-0018 and this task's own investigation already established. No
blanket restart warning was added anywhere in this implementation.

### Deletion/reference lifecycle — reconfirmed, one real gap closed

- An explicitly-referenced transport still cannot be deleted (checks 3,
  10-11's extension case; **check 39's trunk case, closing the exact gap
  the investigation identified**: checks 1-18's own trunk fixture was
  always removed *before* the transport-delete was attempted, so that
  branch of `getUsageDetails()` — already correct in the shipped code —
  had never actually been exercised by the automated suite).
- Clearing all references (switching to Automatic, or removing the
  referencing object) removes that protection; delete then succeeds
  (checks 17, 40).
- No dependent object is ever silently rewritten to point elsewhere —
  confirmed by construction (nothing in this implementation ever writes
  `transport_id` except the explicit save path a human/HTTP request
  drives) and live (checks 24-26, 29, 35's re-enable/recovery path).

### HTTP lifecycle validation (real SENMA flows, not SQL)

Full extension round trip (checks 19, 21-26): create Automatic → verify
no `transport=` line and `peers.transport_id IS NULL` → edit to
EXPLICIT(A) → verify exact `transport=A` → edit to EXPLICIT(A) again
(no-op) → unchanged → edit to EXPLICIT(B) → verify exact `transport=B`,
A reference gone → rename B (+ port) → verify the extension picks up the
new name with zero manual intervention → edit to Automatic → verify
`transport=` line gone **and** `peers.transport_id` is `NULL` in the
database.

Full trunk round trip (checks 27-30), validating **both** endpoint and
registration at every step: create Automatic → both objects omit
`transport=` → edit to EXPLICIT(A) → both objects show the identical
`transport=A` → edit to Automatic → both objects revert, DB confirms
`NULL`.

### Disabled-transport validation (checks 33-38)

Both scenarios from item 12 were tested (not just one branch of the
"and/or"): (A/B) a transport created disabled is absent from the
selector; (C-F) an enabled, referenced transport is then disabled —
generation skips the affected object cleanly, the endpoint disappears
from Asterisk's live runtime with no dangling reference, and the
Transports list page surfaces the problem explicitly. Newly *selecting*
a disabled transport is separately rejected at save time (check 33).

### `transport-smoke` evolution: 18 → 40 checks

All 18 original checks preserved **byte-for-byte unchanged** (still
proving TASK-0018's own creation-path AUTO/EXPLICIT invariants via
direct-SQL fixtures, exactly as before). 22 new checks appended as a
self-contained "PART 2," using its own independent fixtures
(`task0019-*` transports, extension `1097`, its own trunk fixture) so
neither part can interfere with the other's ordering or state:

19. UI-driven create, Automatic — `peers.transport_id IS NULL` **and**
    no `transport=` line (the first check in this whole suite to query
    `transport_id` from the database directly rather than only inspect
    the generated file).
20. Two explicit transports created via the real UI.
21. Extension AUTO → EXPLICIT(A).
22. Extension EXPLICIT(A) → EXPLICIT(A) (no-op re-save).
23. Extension EXPLICIT(A) → EXPLICIT(B).
24. Transport rename (+ port change) cascades to the dependent
    extension's generated config.
25. Renamed transport's live runtime reload succeeds, no restart (using
    a bind change, per the corrected finding above).
26. Extension EXPLICIT → AUTO, confirming `NULL` is **written**, not
    omitted.
27. Trunk UI-driven create, Automatic — neither endpoint nor
    registration gets `transport=`.
28. Trunk AUTO → EXPLICIT(A), both endpoint and registration pinned
    identically.
29. Trunk EXPLICIT → AUTO, both objects revert, DB confirms `NULL`.
30. Disabled transport absent from the extension edit form's option
    list.
31. Newly pinning a disabled transport is rejected.
32. Disabling an already-referenced transport is allowed (HTTP 302, not
    blocked like delete).
33. Generator skips (does not dangle) the affected extension.
34. Endpoint disappears from Asterisk's live runtime — no dangling
    reference.
35. UI surfaces the disabled-but-referenced state clearly.
36. Re-enabling the transport fully recovers the extension.
37. Delete blocked while referenced by a **trunk** (closing the checks
    1-18 coverage gap).
38. Trunk fixture removed; delete then succeeds.
39. All three remaining fixture transports (A, renamed-B, disabled)
    delete successfully once unreferenced.

Total: **40/40**, run twice consecutively against the long-lived dev
environment (idempotent) and twice more from a fully clean rebuild (all
7 named volumes wiped) — 40/40 every time.

Two real test-script bugs were found and fixed while building this
(both in `transport-smoke-test.sh`, not the application):
`save_transport()`'s conditional `enabled` flag used a bash array
expanded with `"${arr[@]}"` under `set -u`, which is an "unbound
variable" fatal on bash 3.2 (macOS's shipped `/bin/bash`) when the array
is still empty — rewritten as two full, explicit curl invocations; and
every UX transport fixture initially omitted `allow_reload=1` (the
`create_transport()`/`edit_transport()` helpers checks 1-18 already use
correctly include it), which was the original, misleading trigger for
investigating the rename behavior above before the real, narrower
same-bind-collision explanation was found.

### Regression (final baseline)

| Suite | Long-lived dev environment | Clean rebuild (all 7 volumes wiped) |
|---|---|---|
| `make smoke` | 16/0/0 | 16/0/0 (after dismissing the ITC first-run prompt once, exactly as TASK-0015/0018 already documented — not a regression) |
| `make call-smoke` | 17/18 | 17/18 |
| `make trunk-smoke` | 21/23 | 21/23 |
| `make transport-smoke` (×2, idempotency) | 40/40, 40/40 | 40/40, 40/40 |

**The `call-smoke`/`trunk-smoke` shortfalls are a single, pre-existing,
already-documented, unrelated issue, not a regression**: the app
container's PHP runs with `date.timezone=UTC` (confirmed via `php -i`)
while `cdr.calldate` is written in that same UTC time, but each smoke
test's own "today" boundary is computed from the container's OS `date`
command, which reports the host's local `-03` time zone. During the
~3-hour daily window before local midnight, these two disagree by
exactly the UTC offset, so the CallsReport API's date-range filter
excludes a same-instant CDR row. This is not a new discovery —
`docs/tasks/0015-pjsip-trunk-provisioning.md` §"Regression" already
documented the identical `calldate` vs. wall-clock discrepancy
("container/DB timezone-handling difference not worth chasing further")
during that task's own validation. Reproduced identically, twice, in
both the long-lived and clean-rebuild environments, entirely
independent of any TASK-0019 code (neither `call-smoke-test.sh` nor
`trunk-smoke-test.sh` nor the CDR/report code path was touched by this
task) — every other check in both suites (endpoint/registration/call
placement/AGI routing/CDR-row-itself-is-correct) passes cleanly.

### Logs (item 15)

Zero new PHP Fatal Errors across the entire validation session
(`grep -c "Fatal error" /var/log/apache2/mag-error.log` = 0, checked
before and after, both environments). Zero unexpected Asterisk PJSIP
errors or registration failures caused by any AUTO/EXPLICIT transition —
the only Asterisk-log-visible events across the whole session were the
already-known ITC first-run prompt (clean rebuild only) and the
already-known res_odbc/cdr_adaptive_odbc boot race (did not occur on
this particular clean-rebuild run — consistent with it being an
occasional, not-every-time characteristic, as already noted in prior
tasks' docs). The disabled-transport skip path logs one clear,
actionable `error_log()` line per skipped object, confirmed present.

### Remaining transport debt (not fixed, flagged for a future task)

- `Snep_PjsipConf::reload()`/`Snep_PjsipTrunkConf::reload()`'s own
  **pre-existing** failure-path logging still calls
  `Zend_Registry::get('log')` unguarded — this was never fixed (only
  avoided in the new code added by this task), since it's an
  independent, pre-existing gap outside this task's scope (it only ever
  fires when a PJSIP reload itself fails to report success, a separate,
  rarer condition than a disabled-transport reference). A future task
  should apply the identical `error_log()` fix there, or properly
  register `'log'` in the application's bootstrap.
- The already-documented, pre-existing `trunk-smoke-test.sh`
  `delete_trunk()` hardcoded-name bug (TASK-0018 §14) remains unfixed,
  out of scope here too.
- The `call-smoke`/`trunk-smoke` timezone-boundary artifact documented
  above is now confirmed across three separate tasks' validation runs
  (TASK-0015, and this task twice) — worth a small, dedicated fix
  (either make each smoke test compute "today" the same way PHP/MySQL
  do, or align the container's `date.timezone` with its OS time zone)
  in a future, unrelated task.

---

Stopping here at a commit checkpoint. Not beginning TASK-0020.
