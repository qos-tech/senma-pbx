# TASK-0020 — PJSIP transport runtime lifecycle and restart semantics

## Status

**Implemented and validated** — see the implementation section at the
end of this document for files changed, evidence, and the final
regression baseline. The investigation below is preserved exactly as
originally written and approved.

---

## Investigation (approved before implementation)

**No runtime code, database schema, views, JavaScript,
generators, Docker configuration, or tests were modified** during this
phase. Every finding
below comes from reading the current committed code (`HEAD` =
`08745bf`, "feat: add PJSIP transport selection UX") and from live
experiments against the running `make dev` environment — real HTTP
saves through `PjsipTransportsController`, real `pjsip show` queries,
direct `/proc/net/{udp,tcp}` socket inspection, `/var/log/asterisk/full`
log inspection, and one real, controlled `core restart now`. All test
fixtures were created and fully removed through SENMA's own real flows
(or, for the two deliberately-malformed-content probes in §11, via a
direct SQL row insert/delete and a manually-appended, then removed,
config line — both cleaned up and confirmed via a fresh regenerate).
The environment was verified clean and healthy before and after
(`pjsip show transports` shows exactly `udp`/`tcp`; `make smoke`
16/0/0; `make transport-smoke` 40/40; all 4 containers healthy).
Stopping here — awaiting approval before any implementation.

---

## 1. Terminology

Used consistently throughout this document, per the task's own
requirement not to conflate "saved," "loaded," "active," and "applied":

- **CONFIGURED STATE** — what the `pjsip_transports` row(s) in the
  database, and the file `Snep_PjsipTransportConf::loadConfFromDb()`
  writes (`senma-pjsip-transports.conf`), say should exist. This is
  purely file/DB content; it says nothing about whether Asterisk has
  actually done anything with it.
- **RUNTIME STATE** — what Asterisk's own live PJSIP sorcery layer
  currently has loaded, observable via `pjsip show transport(s)`, and,
  at a lower level, which OS sockets are actually bound (observable via
  `/proc/net/udp`/`/proc/net/tcp` inside the Asterisk container).
  **These two observation points can disagree with each other**, not
  just with CONFIGURED STATE — this is a distinct, load-bearing finding
  of this investigation (§8/§9).
- **HOT RELOAD** — CONFIGURED STATE changes, `module reload
  res_pjsip.so` is issued, and RUNTIME STATE becomes fully consistent
  with CONFIGURED STATE, no restart involved.
- **RESTART REQUIRED** — CONFIGURED STATE is correct (the generated file
  says the right thing), but RUNTIME STATE cannot reach it via a plain
  reload; a full Asterisk process restart (`core restart now` or
  `gracefully`) is necessary and, based on every case tested, always
  sufficient.
- **FAILED APPLY** — CONFIGURED STATE changed, a reload was attempted,
  and RUNTIME STATE does **not** match CONFIGURED STATE, in a way that a
  restart cannot fix either (a genuine, ongoing conflict between two
  still-current configured rows, e.g. two enabled transports that both
  want the identical `protocol`+`bind_address`+`bind_port`) — as opposed
  to RESTART REQUIRED, where the mismatch is a runtime artifact that a
  restart cleanly resolves.

---

## 2. Current save/apply path, traced end to end

```
HTTP POST
  -> PjsipTransportsController::addAction()/editAction()/removeAction()
  -> validatePost()                     (field-level validation ONLY —
                                          no cross-row collision check, §K)
  -> Snep_PjsipTransports_Manager::create()/update()/remove()
       -> DB write, its OWN transaction, COMMITTED unconditionally
  -> $this->regenerateAll()
       -> Snep_PjsipTransportConf::loadConfFromDb()   (writes the file,
          then `module reload res_pjsip.so` via PBX_Asterisk_AMI)
       -> Snep_PjsipConf::loadConfFromDb()            (same pattern)
       -> Snep_PjsipTrunkConf::loadConfFromDb()       (same pattern)
  -> $this->_redirect("pjsip-transports")   (HTTP 302 -- the ONLY
                                              "success" signal the UI
                                              ever produces today)
```

**The critical fact, confirmed live and repeatedly (§4/§8/§K):** the DB
write happens **before** any Asterisk apply is attempted, in its own
transaction, and is **never rolled back** based on what happens next.
Each generator's own `reload()` checks the AMI `Command` response for
the substring `"reloaded successfully"` and throws `PBX_Exception_IO`
if absent — but, as established conclusively in §11, **this check
essentially never fails** for PJSIP-specific problems, because
`module reload res_pjsip.so` reports module-level success even when
individual objects inside the reloaded config fail to load. The
practical result: **the controller's HTTP 302 ("saved") is emitted in
scenarios where Asterisk's runtime does not, and by design cannot, ever
be checked against** — confirmed for create-on-a-colliding-socket,
rename-to-the-same-bind, and re-create-on-a-just-"deleted" port (§4/§K/§8).

Per-lifecycle-action breakdown (all four share the identical
`regenerateAll()` tail):

| Action | DB write | Config regenerated | Reload attempted | Success signal to admin |
|---|---|---|---|---|
| Create | `INSERT`, own transaction | Yes (all 3 generators) | Yes | HTTP 302 |
| Edit | `UPDATE`, own transaction | Yes (all 3 generators) | Yes | HTTP 302 |
| Disable | `UPDATE enabled=0` (same `editAction()` path) | Yes | Yes | HTTP 302 |
| Re-enable | `UPDATE enabled=1` (same `editAction()` path) | Yes | Yes | HTTP 302 |
| Delete | `DELETE`, blocked first if referenced | Yes | Yes | HTTP 302 |

None of these five distinguishes HOT RELOAD from RESTART REQUIRED from
FAILED APPLY today — all five produce the identical HTTP 302 regardless
of what actually happened at the Asterisk level.

---

## 3. Field inventory and mutation matrix

| Field | DB column | Generated PJSIP property | Changes section identity? | Changes socket identity? | Asterisk docs on reload restrictions | Current SENMA behavior |
|---|---|---|---|---|---|---|
| `name` | `pjsip_transports.name` | `[name]` section header | **Yes — this *is* the identity** | No, by itself | None specific to renaming; sorcery treats a name change as delete-old + create-new | Mutable, no warning at all (§6) |
| `protocol` | `protocol` | `protocol=` | No | **Yes, jointly with address+port** | `allow_reload` gates whether a reload touches this object at all (§below) | Editable, no warning |
| `bind_address` | `bind_address` | `bind=<addr>:<port>` (address half) | No | **Yes, jointly** | Same | Editable, no warning |
| `bind_port` | `bind_port` | `bind=<addr>:<port>` (port half) | No | **Yes, jointly** | Same | Editable, no warning |
| `domain` | `domain` | `domain=` | No | No | — | Editable, no warning |
| `external_signaling_address`/`_port` | same | `external_signaling_address=`/`_port=` | No | No | — | Editable, no warning |
| `external_media_address` | same | `external_media_address=` | No | No | — | Editable, no warning |
| `local_net` (child rows) | `pjsip_transport_networks` | `local_net=` (repeatable) | No | No | — | Editable, no warning |
| `symmetric_transport` | `symmetric_transport` | `symmetric_transport=` | No | No | — | Editable, no warning |
| `allow_reload` | `allow_reload` | `allow_reload=` | No | No (it's a *meta*-flag) | Asterisk's own help text: *"Allow this transport to be reloaded when res_pjsip is reloaded. This option defaults to 'no' because reloading a transport may disrupt in-progress calls."* SENMA's own form always ships this checked (`addedit.phtml`); every SENMA-created transport already opts in to reloadability by default. | Editable; TASK-0018/0019's own smoke fixtures always set it `1` — confirmed by this task that setting it `0` would make **every future edit** to that specific transport require a restart, per Asterisk's own documented semantics (not independently re-tested this round; not contradicted by anything found) |
| `is_default` | `is_default` | *(nothing — never emitted)* | No | No | — | Administrative/UI only, reconfirmed live (§4.A) |
| `enabled` | `enabled` | *(row omitted entirely from the generated file when 0)* | Equivalent to a delete, generation-wise | **Yes — behaves exactly like delete at the socket level (§9)** | — | Editable; TASK-0019 already handles the *dependent-object* fallout (skip+log) but not the *transport's own* socket fallout (new in this task, §9) |

---

## 4. Live mutation matrix — results

All tests below ran against the real environment via
`PjsipTransportsController`'s actual HTTP endpoints (never raw SQL for
the transport's own fields), with before/after captured via `pjsip show
transport(s)`, the generated file, `/var/log/asterisk/full`, and direct
`/proc/net/{udp,tcp}` inspection (matching a decimal port to its hex
form, e.g. `5081` → `:13D9`) — the OS-level ground truth, independent of
whatever `pjsip show` claims.

| # | Mutation | Classification | Evidence |
|---|---|---|---|
| A | `is_default` toggle | **Administrative only, zero runtime effect** | Toggling `is_default` between `tcp`/`udp` produced a byte-identical functional reload; `pjsip show transports` unchanged throughout |
| B | Non-identity field edit (already covered by TASK-0018, not independently re-run this round) | **HOT** | TASK-0018 §5's own evidence stands; nothing in this task's testing contradicts it |
| C | **Rename**, same protocol/address/port | **RESTART REQUIRED — always, no exception found** | See §6 |
| D | Port change, same name/protocol/address | **HOT** | `portchg` 5082→5083: old port's `/proc/net/udp` entry disappeared, new port's appeared bound, `pjsip show transport` immediately reflected 5083, no restart |
| E | Bind address change, same name/protocol/port | **HOT** | `addrchg` `0.0.0.0`→`172.28.0.2`, port 5084: `/proc/net/udp` showed the local-address half change from `00000000` to `02001CAC` (172.28.0.2, byte-reversed), immediately, no restart |
| F | Protocol change, same name/address/port, both directions | **HOT, both directions** | `protochg` udp→tcp→udp, port 5085: UDP socket closed / TCP socket opened on the switch to `tcp`; TCP socket closed / UDP socket reopened on the switch back — confirmed via `/proc/net/udp` and `/proc/net/tcp` independently, `pjsip show transport` correct at every step |
| G | Disable (unreferenced transport) | **RESTART REQUIRED to actually free the socket — new finding, §9** | `disenable` port 5086: object vanishes from `pjsip show transports`/generated file (looks clean), but `/proc/net/udp`'s inode pointer for port 5086 is **byte-for-byte identical** before and after disabling — the socket never closed |
| H | Re-enable | **HOT, but only because the socket never actually left (§9)** | Same transport, same name, same bind: re-enabling brought the object back instantly, same underlying (never-released) socket |
| I | Delete (unreferenced) | **RESTART REQUIRED to actually free the socket — corrects TASK-0018 §5's claim, §8** | `delme` port 5087: DB row deleted, generated file correctly omits it, `pjsip show transport delme` reports "Unable to find object" — **but the raw socket stayed bound** (identical `/proc/net/udp` inode before/after); a fresh transport (`delme-again`) created afterward on the *same* port **failed** with the exact Asterisk-logged error `Transport 'delme-again' could not be started: Address already in use`, reproduced twice (immediately, and again ~2 minutes later) |
| J | Create on a genuinely unused socket | **HOT** | `newone` port 5088: object appears, bind correct, `/proc/net/udp` shows it listening; a real extension (`1095`) explicitly pinned to it generates `transport=newone` and `pjsip show endpoint 1095` correctly reports `transport: newone` |
| K | Socket collision — two *different* names, same protocol+address+port | **FAILED APPLY — cannot be fixed by restart, because both configured rows still conflict** | `collide-a`/`collide-b`, both `udp 0.0.0.0:5089`: **both saves returned HTTP 302** ("saved successfully"); only `collide-a` (created first) ever became a live runtime object; `collide-b` never did, confirmed via `pjsip show transport collide-b` ("Unable to find object"), the full listing (2 objects, not 3, immediately after creating it), *and* `/var/log/asterisk/full`'s `ERROR ... Transport 'collide-b' could not be started: Address already in use` — **this error is invisible to `docker compose logs asterisk`** (confirmed: searched immediately after, found nothing) and invisible to SENMA (the reload's own AMI response still said "reloaded successfully") |

**Restart-recovery test (§19) result, folded into the table above**: a
single real `core restart now`, issued live, brought **every** stuck
case online simultaneously in one shot — `rename-dst` (case C) and
`delme-again` (case I's follow-up) both became fully live and correct
immediately after the restart (`System uptime: 8 seconds`, `pjsip show
transports` listing all of them with correct binds) — **except**
`collide-b`, which remained unresolvable even after the restart, exactly
as expected for a FAILED APPLY: two still-currently-configured rows
cannot both hold the same socket, restart or not.

---

## 5. Socket identity — precisely determined

Confirmed live, repeatedly: **socket identity = `(protocol-family,
bind_address, bind_port)`**, where "protocol-family" groups by the
underlying BSD socket type, not the PJSIP `protocol=` string verbatim.
UDP and TCP **freely coexist** on the identical port number (test F,
both directions) — `SOCK_DGRAM` and `SOCK_STREAM` are independent kernel
namespaces, confirmed via `/proc/net/udp` vs. `/proc/net/tcp` never
showing a conflict for same-port UDP/TCP pairs. **Two transports both
requesting UDP (or both TCP) on the identical `bind_address:bind_port`
collide** (test K) — the first-loaded one wins the socket; the second
never becomes a runtime object, silently (no error visible outside
`/var/log/asterisk/full`). TLS was not tested (shares TCP's socket
family conceptually, per Asterisk's general transport model, but this
was not independently verified — WSS/WS remain out of scope per every
prior task's deferral and this task's own §24).

**Do not assume all same-port transports collide — confirmed false**
(the task's own explicit caution): same-port, different-protocol-family
pairs are completely safe; same-port, same-protocol-family pairs are
not.

---

## 6. Rename semantics — the central, corrected finding

Traced precisely: `peers.transport_id`/`trunks.transport_id` reference
the transport's immutable `id` (unaffected by a rename); on the very
next `regenerateAll()`, `Snep_PjsipConf::resolveTransportName()` does a
fresh `Manager::get($id)` lookup and emits the transport's **current**
name — so **dependent extension/trunk regeneration is, and has always
been, correct on rename**: the generated file always shows the new name
immediately (confirmed again this round; not the part that was ever
broken).

**What is broken, confirmed decisively this round (correcting
`docs/tasks/0019-pjsip-transport-selection-ux.md`'s "New fact 2",
itself already flagged there as needing re-verification)**: renaming a
transport's *own* row — even with the bind `address:port` completely
unchanged — reliably fails to bring the new name online:

- Immediately after the rename, `pjsip show transport <newname>`
  reports "Unable to find object", **and so does `pjsip show transport
  <oldname>`** — neither name resolves.
- The full `pjsip show transports` listing omits the renamed transport
  entirely (not a stale old-named entry — genuinely absent).
- The underlying OS socket for the *old* bind never closes (confirmed
  via unchanged `/proc/net/udp` inode across the rename).
- Retried the direct `pjsip show transport <newname>` query 3 times over
  several seconds, and issued two more **identical-content** `module
  reload res_pjsip.so` calls directly afterward — none of it brought the
  object online. `/var/log/asterisk/full` logged nothing for this
  specific case (unlike the collision case, K, which does log an
  explicit error) — a rename-onto-your-own-old-address is apparently
  treated internally the same way a stale, still-bound socket blocks
  *any* other reload-created object from claiming it, but without even
  the courtesy of an error line.
- A full restart resolved it completely and immediately (§4's restart-
  recovery result).

**This is best explained as one instance of a single, unifying root
cause established across §4/§6/§8/§9**: a plain `module reload
res_pjsip.so` never actually closes a previously-opened transport
socket — it only adds, removes, or *appears* to remove named sorcery
objects wrapping that socket. A rename is, from sorcery's perspective,
"delete `oldname`, create `newname`" in the same reload pass; the
"create `newname`" half fails silently because the address is still
physically held by the (now nameless, from `pjsip show`'s perspective)
old socket.

**Explicit answer to item 6's question: (A) allowed, with a
restart-required state — unconditionally, not case-by-case.** Renaming
must stay allowed (`name` stays mutable — no evidence anywhere suggests
otherwise, and it remains a legitimate administrative action, e.g.
fixing a typo or adopting a new naming convention). But **every** rename
must be flagged "restart required," not just ones that happen to also
collide — this investigation found **zero** exceptions across every
rename attempted, so this is a safe, always-correct rule, not merely a
cautious one.

---

## 7. Create semantics

A brand-new transport on a genuinely unused socket hot-loads correctly,
proven concretely (test J): the runtime object appears with the exact
configured bind; `/proc/net/udp` confirms the socket is actually
listening (not merely reported by `pjsip show`); a real extension
(`1095`) explicitly pinned to it generates the correct
`transport=newone` line and `pjsip show endpoint 1095` correctly
resolves it. A live SIP `REGISTER` through this specific new transport
was not separately re-verified this round (would need a dedicated SIP
UA pointed at the custom port) — this is a reasoned extrapolation from
already-multiply-proven mechanics (the identical `resolveTransportName()`
→ `transport=<name>` → sorcery-resolved-transport path that `call-smoke`/
`trunk-smoke` already exercise successfully against the seed
transports, dozens of times, across every prior PJSIP task), not an
independent live proof for this exact scenario — flagged honestly as
such rather than overclaimed.

---

## 8. Delete semantics — corrects a prior claim

**`docs/tasks/0018-pjsip-transports.md` §5 claimed:** *"Deleting a
transport (no restart)... confirmed empirically, no restart ever
needed."* **This investigation found that claim was based on incomplete
evidence** (checking only `pjsip show transports`/the generated file —
application-level state — never checking whether the vacated
`address:port` could actually be reused). Re-tested at the OS-socket
level (test I): after deleting an unreferenced transport, the DB row is
gone, the generated file correctly omits it, `pjsip show transport`
correctly reports it missing — **but the raw socket remains bound
indefinitely** (unchanged `/proc/net/udp` inode), and a **new** transport
later created on the identical `address:port` **fails** with
Asterisk's own logged `Address already in use`, reproduced twice.

**Deleting DB/config state and removing the runtime transport are
explicitly not equivalent** (exactly the distinction item 8 asks for):
the former is instantaneous and always correct; the latter requires a
full restart to actually complete. This is corrected in this document
rather than left standing, per CLAUDE.md's "correct documentation when
later evidence disproves an earlier assumption" rule — `docs/tasks/0018-pjsip-transports.md`
itself is not rewritten here (out of this investigation-only task's
scope to edit other tasks' docs), but any future reader should treat
this document's §8 as the current, correct account.

---

## 9. Disable semantics — new finding

Disabling a transport (§4.G) behaves **identically to delete at the
socket level**: the object disappears from `pjsip show
transports`/the generated file, but the OS socket never closes
(unchanged `/proc/net/udp` inode across disable→re-enable, test H). This
explains *why* re-enabling always works instantly with no restart
needed: the "disabled" state was never truly a closed socket, just a
sorcery-object removal — re-enabling under the *same* name and *same*
bind simply lets the object "reclaim" a socket that, at the OS level,
was open the entire time.

**Impact on dependents**, split into what was already proven (TASK-0019)
and what is newly reasoned here:

- **Explicitly-referencing extensions/trunks** (already proven,
  TASK-0019): the generator's per-row skip means the referencing
  object's endpoint disappears from the generated file and from
  Asterisk entirely — loud (an `error_log()` line, a list-page banner),
  not a dangling reference.
- **AUTO extensions/trunks that happen to be using the now-disabled
  transport's protocol family** (reasoned from this task's own
  established facts, not independently re-proven live with a real SIP
  UA this round): AUTO means Asterisk itself picks "the first configured
  transport compatible with the URI" **among transports it currently has
  loaded** — if the disabled transport was the *only* enabled transport
  of its protocol family (e.g. disabling `udp` while only `tcp` remains
  enabled), Asterisk has no UDP transport object left to select at all
  for *any* endpoint, AUTO or explicit, regardless of the disabled
  transport's own socket lingering at the OS level — a lingering socket
  with no attached sorcery transport object is not routable PJSIP
  traffic. This is a real, plausible operational risk worth calling out
  explicitly in any admin-facing warning about disabling the last
  transport of a given protocol.
- **Existing, already-established calls/registrations at the moment of
  disable**: not independently tested live this round (would require
  orchestrating an active call across a disable event) — flagged as an
  open question. Given the socket itself never closes, it is plausible
  that in-flight SIP dialog state tied to that already-open socket
  continues working transiently even after its owning transport object
  is removed from sorcery's bookkeeping, but this is reasoned, not
  proven, and should not be relied upon.
- **New calls/registrations after disable**: correctly rejected/routed
  elsewhere per the already-proven generator-skip behavior for explicit
  references; for AUTO objects, subject to the protocol-family caveat
  above.

---

## 10. Endpoint/trunk dependency impact — summary

| Object type | AUTO | EXPLICIT |
|---|---|---|
| Extension | Unaffected by any transport CRUD *unless* the disabled/deleted transport was the last of its protocol family (§9) | Skipped by the generator if its pinned transport is disabled (TASK-0019, reconfirmed); silently mis-provisioned with a permanently-orphaned reference if its pinned transport is deleted-then-recreated-with-a-different-id elsewhere (not directly possible through the UI today, since delete is blocked while referenced — no new risk found) |
| Trunk (endpoint + registration) | Same as extension | Same as extension — both endpoint and registration are skipped together (single shared `resolveTransportName()` call per TASK-0019's own design), never independently |

Generators invoked today, confirmed by reading the code (unchanged from
TASK-0018/0019, reconfirmed): every transport create/edit/delete/
disable/enable calls `PjsipTransportsController::regenerateAll()`, which
runs, in order, `Snep_PjsipTransportConf::loadConfFromDb()` →
`Snep_PjsipConf::loadConfFromDb()` → `Snep_PjsipTrunkConf::loadConfFromDb()`
— all three, every time, regardless of which specific field changed.
**AUTO remains semantically independent from `is_default`** throughout —
reconfirmed: `is_default` is never read by any generator (only by
`removeAction()`'s delete-protection and the UI badge/pre-fill), and
toggling it produces zero change to any generated file (test A).

---

## 11. Existing reload implementation — audit, and the confirmed masking bug

Three near-identical `reload()` private methods exist, one per
generator (`Snep_PjsipConf::reload()`, `Snep_PjsipTrunkConf::reload()`,
`Snep_PjsipTransportConf::reload()`), each:

```php
$result = $asteriskAmi->Command("module reload res_pjsip.so");
$data = isset($result['data']) ? $result['data'] : '';
if (stripos($data, 'reloaded successfully') === false) {
    $log = Zend_Registry::get('log');
    $log->err("...");
    throw new PBX_Exception_IO(...);
}
```

**All three still use the pre-TASK-0019 `Zend_Registry::get('log')`
pattern.** TASK-0019 already proved, live, that `'log'` is **not
actually registered** in this application's real HTTP request bootstrap
— hitting that exact line produces an uncaught `Zend_Exception` ("No
entry is registered for key 'log'"), rendered as a genuine HTTP 500,
and fixed TASK-0019's own *new* skip-path code to use plain
`error_log()` instead, explicitly leaving these three pre-existing
`reload()` methods unfixed as flagged, documented debt.

**This task's own question — "whether a real reload failure can be
masked by a secondary logger exception" — is answered precisely:
yes, by direct code reading, this is a real, confirmed, reachable bug**:
if the `stripos()` check ever evaluates false (the reload genuinely
failed at the module level), the very next line throws a **different**
exception ("No entry is registered for key 'log'") before the intended,
informative `PBX_Exception_IO("Failed to reload Asterisk PJSIP
configuration: %s")` message ever gets thrown — masking the real cause
with an unrelated one.

**However, this task went further and tried, live, to actually trigger
that failure branch** — and could not, across two different kinds of
malformed input:

1. A syntactically well-formed but semantically invalid transport row
   (`protocol=garbage123`, inserted directly via SQL to bypass SENMA's
   own enum validation) — `module reload res_pjsip.so` **still reported
   "reloaded successfully"**; the malformed object simply never became a
   runtime transport (`res_sorcery_config.c: Could not create an object
   of type 'transport' with id 'badproto-test'`), logged only to
   `/var/log/asterisk/full`, invisible to `docker compose logs` and to
   the "reloaded successfully" check.
2. A **genuinely broken INI file** (an unclosed `[` bracket, manually
   appended to the generated config) — `module reload res_pjsip.so`
   **still reported "reloaded successfully"**; Asterisk's config parser
   logged a `parse error: no closing ']'` warning and simply skipped the
   malformed section, loading everything before it correctly.

**Refined conclusion**: the masking bug is real and confirmed by code
reading, but this investigation could not find any config-content-based
way to actually reach it — Asterisk's `module reload res_pjsip.so`
appears to report module-level success unconditionally for any
syntactically-parseable-enough content, pushing every failure mode
found in this entire task down to the per-object level (§4/§K/§11
above), which the "reloaded successfully" check was never designed to
catch in the first place. The masking bug therefore matters mostly for
non-content failure modes not exercised here (e.g. the AMI connection
itself failing) — still worth fixing (it is directly relevant to "safe
transport apply semantics," the item's own question, and the fix is
identical and as small as TASK-0019's own precedent), but it is not the
primary mechanism behind the dangerous "saved successfully" UX this
task set out to investigate. **§K's silent per-object failure — not
§11's masked exception — is the primary, proven mechanism.**

---

## 12. Reload command semantics — re-verified against this build

`module reload res_pjsip.so` remains the only relevant mechanism.
Checked for a more targeted alternative: `core show help pjsip` lists
every available `pjsip *` CLI command in this exact build — the only
`pjsip reload *` subcommands are `pjsip reload qualify aor` and `pjsip
reload qualify endpoint` (both scoped to AOR/endpoint qualify timers,
unrelated to transports). **No per-object or transport-specific reload
command exists in Asterisk 22.10.1.** `module reload res_pjsip.so`
remains a coarse, whole-module operation whose own AMI response
reflects "did the module accept the reload," not "did every object in
it load" — confirmed precisely in §11's two live probes. No other
supported command/API changes this; nothing here was decided from
generic Asterisk advice, only from this build's own `core show help`
output and observed behavior.

---

## 13. Restart mechanism — audited, no new privileges needed

- **AMI already supports it.** `docker/asterisk-config/manager.conf`
  grants the SENMA AMI user `write = system,call,log,verbose,command,
  agent,user,config,originate` — both the `system` and `command` write
  classes are already present, and `PBX_Asterisk_AMI::Command()`
  (already used for every `module reload` call in this codebase) is the
  exact same generic mechanism that would issue `core restart now` or
  `core restart gracefully`. No new AMI permission is needed.
- **The app container has no Docker socket, and none should be added.**
  Confirmed by reading `compose.yaml` end to end: no `docker.sock`
  mount, no `privileged: true`, no `cap_add`, anywhere. Restarting
  Asterisk from the web application requires **zero** new privileges —
  the existing AMI network connection is a complete, already-authorized
  service-control boundary for exactly this operation.
- **Verified live**: issued `core restart now` directly (functionally
  identical to what an AMI `Command` action would execute — same CLI
  command parser). Result: `docker inspect`'s `StartedAt`/`RestartCount`
  were **unchanged** — the container itself never stopped. Asterisk's
  own `core show uptime` immediately after read "System uptime: 8
  seconds," confirming a genuine, clean, **in-place** restart
  (`exec()`-based, per Asterisk's own CLI help text — see §14) with zero
  container churn, zero impact on the `app`/`db`/`provider` containers,
  and (per `restart: unless-stopped` already set on every service in
  `compose.yaml`) a Docker-level safety net even if a future Asterisk
  version's restart behavior ever changed to a hard process exit
  instead.
- **No new service-control boundary is needed.** The existing
  AMI-over-TCP channel, already relied upon for every PJSIP reload in
  this project's history, is sufficient, already authorized, and
  already proven live in this task.

---

## 14. Should SENMA restart Asterisk automatically? — evaluated, decided

Asterisk itself exposes three restart variants, their exact semantics
confirmed via this build's own CLI help (`core show help core restart
now`/`gracefully`):

```
core restart now         -- "Causes Asterisk to hangup all calls and
                              exec() itself performing a cold restart."
core restart gracefully  -- "Causes Asterisk to stop accepting new
                              calls and exec() itself performing a cold
                              restart when all active calls have ended."
core restart when convenient -- restart at empty call volume
```

`now` unconditionally drops every active call system-wide, immediately
— confirmed by Asterisk's own documentation, not assumed. `gracefully`
is materially safer (waits for existing calls to finish) but still
blocks **every** new call for the entire wait, system-wide, for a
potentially unbounded duration, triggered by an edit to **one**
transport that may be used by only a handful of endpoints.

**Decision: (C) save config and display "restart required," never (A)
automatic restart.** No evidence found in this investigation justifies
overriding the task's own stated default ("do NOT automatically restart
telephony from a routine CRUD save unless strong evidence supports
it") — quite the opposite: every piece of evidence gathered (system-wide
call-drop on `now`, unbounded system-wide new-call blocking on
`gracefully`, a shared single Asterisk process serving every extension
and trunk in the deployment) argues for *more* caution, not less. (D),
rejecting restart-required mutations outright, is also not recommended
— renaming and other restart-requiring edits are legitimate
administrative actions that this investigation proved always complete
correctly once a restart occurs; rejecting them would remove a real,
occasionally-needed capability to solve a UX-communication problem that
has a much smaller fix (§16).

A **separate, explicit, admin-triggered "Restart Asterisk" action**
(distinct from any transport save) is a reasonable *future* increment —
if ever built, it should default to `core restart gracefully`, never
`now`, and requires its own confirmation UX — but building it is **not**
part of this investigation's recommended implementation scope (§ below);
nothing in the current task requires it, and adding it now would be
scope creep beyond what evidence here demands.

---

## 15. Persistent "configured != runtime" state — no schema change needed

Evaluated every option the task lists:

- **Compare DB/generated config to `pjsip show transports`**: viable,
  and this is the approach recommended below — but note a real
  limitation found this round: **there is no structured AMI action for
  transports.** `manager show commands` lists `PJSIPShowEndpoints`,
  `PJSIPShowAors`, `PJSIPShowAuths`, `PJSIPShowContacts`,
  `PJSIPShowRegistrationsOutbound`, and others — but **no
  `PJSIPShowTransports`**. The only way to inspect live transport state
  is the same raw CLI-text `Command` action already used for reload
  (`pjsip show transport(s)`), which this task's own live testing
  confirms produces clean, reliably-parseable text (a `bind` line, an
  "Unable to find object" line) — fragile in principle, proven
  workable in practice across every test in this document.
- **Mark restart-required only in the immediate response**: this is the
  recommended primary mechanism (see §16/§ implementation scope) — no
  persistence needed at all for the case that matters most (rename,
  proven to need a restart 100% of the time, detectable synchronously
  by comparing old vs. new `name` in the same request that already has
  both values).
- **Persistent DB flag**: evaluated and **not recommended** as the
  primary mechanism — it would need to be set on save (easy) but
  correctly *cleared* only after an actual restart occurs, which SENMA
  cannot observe on its own (Asterisk does not notify anything when it
  restarts) without either polling `core show uptime` (adds a recurring
  background job, out of scope and unnecessary for what §16/§17 below
  already achieve without one) or requiring the admin to explicitly
  confirm "I restarted" (a plausible but unnecessary extra step given
  §17's derived-state list-page check achieves the same visibility with
  no persistence and no clearing logic to get wrong).
- **Generated checksum/state file**: evaluated, not recommended — would
  only tell SENMA that *configuration* changed since the file was last
  written, which the DB/generated-file pair already tells it; it cannot
  observe *runtime* state any better than directly asking Asterisk can,
  and directly asking Asterisk is already proven reliable in this task.

**Recommendation: no schema change.** Two independent, both-derived,
both-schema-free mechanisms cover everything this investigation found:
(1) an unconditional "restart required" notice whenever a save changes
`name` (§6, §16) — a same-request comparison, no persistence; (2) an
immediate post-save `pjsip show transport <name>` verification (§16) —
also same-request, no persistence; (3) an on-demand, list-page-load-time
cross-reference between enabled DB rows and the live `pjsip show
transports` listing (§17) — recomputed every page view, never stored.

---

## 16. UX specification

Matching the task's own drafted semantic distinctions to this
codebase's existing conventions (`$this->view->alert_message` /
`$this->view->error_message`, already used throughout
`PjsipTransportsController`/`ExtensionsController` for exactly this
class of non-blocking-warning-vs-hard-error distinction):

- **Hot-reloadable change, verified applied** (no name change; post-save
  `pjsip show transport <name>` confirms the expected `bind`):
  `$this->view->success_message` (or reuse the existing redirect+
  nothing-extra pattern, since this is the common case and already
  "just works" today) — *"Transporte salvo e aplicado com sucesso."*
- **Restart-required change** (name changed on this save, unconditionally,
  regardless of whether it also happens to verify): a non-blocking
  `alert_message`-style banner, exactly like the already-shipped
  disabled-but-referenced banner — *"Transporte salvo. É necessário
  reiniciar o Asterisk para que esta alteração de transporte entre em
  vigor."*
- **Failed apply** (post-save verification does **not** find the
  expected transport, and it was *not* a rename — i.e. a genuine,
  ongoing collision, §K): a harder warning, closer to `error_message`
  styling but not a rejected save (the DB write already succeeded and
  should not be silently reverted) — *"Configuração salva, mas o
  Asterisk não conseguiu aplicá-la (endereço/porta já em uso por outro
  transporte). A configuração anterior pode ainda estar em uso."*

Exact Portuguese wording is a small polish detail for the
implementation phase, not a decision this investigation needs to lock
in — the three **semantic** distinctions above are the load-bearing
part.

---

## 17. List-page visibility

**Recommended, evidence-backed, not merely a database-state guess**:
extend `PjsipTransportsController::indexAction()`'s existing
disabled-but-referenced check (TASK-0019) with a second, analogous,
equally-derived check: for every **enabled** transport row, confirm it
actually appears in a single `pjsip show transports` call issued once
per list-page load (already the same AMI mechanism the reload path
already uses) — any enabled-in-DB transport **absent** from that live
listing is flagged with a "RESTART REQUIRED" badge, distinct from the
existing "disabled but referenced" banner. This is explicitly **not**
"a runtime badge based only on database state" (the exact anti-pattern
the task warns against) — it is based on a live, same-request query
against Asterisk's own runtime, re-derived on every view, never cached
or stored. The one cost is one extra `Command` round-trip per list-page
view — reasonable, since this page is not a hot path anywhere in this
application.

---

## 18. Active-call safety

Established from Asterisk's own documented behavior (§14), not assumed:
`core restart now` unconditionally "hangs up all calls" — every active
channel, system-wide, is dropped, not just ones related to the changed
transport. `core restart gracefully` avoids dropping calls by refusing
new ones and waiting, at the cost of blocking all new call activity
system-wide for an unbounded time. Neither variant was exercised this
round against a real in-progress call (no active production call
exists in this dev environment, and constructing one purely to prove
already-documented, standard Asterisk restart semantics was judged
unnecessary scope for this investigation — the official CLI help text
is authoritative and specific to `now` vs. `gracefully`, not generic
Asterisk folklore). Registrations: **not independently tested this
round** whether outbound trunk registrations automatically re-register
after a restart without manual intervention — TASK-0018 §5 already
documented, and this task's own restart test did not contradict, that a
freshly-restarted process's first trunk registration can occasionally
need a brief settling window, self-correcting within seconds; a full
re-verification of trunk re-registration specifically after a
mid-lifetime restart (as opposed to a fresh-boot first registration) is
flagged as unverified and worth a dedicated check if a restart-capable
feature is ever built. AMI/ODBC: unaffected by an Asterisk-side restart
(they are separate connections/processes; `app`'s own DB connection and
AMI client already handle Asterisk being briefly unreachable during any
reload, since that already happens on every save today).

---

## 19. Restart recovery — proven

Performed exactly as the task requires, on the controlled dev
environment, with real accumulated stuck state (not a synthetic single
case): before the restart, `rename-dst` (§6) and `delme-again`'s
underlying port collision (§8) both existed simultaneously, proven
stuck via `pjsip show transport` and `/var/log/asterisk/full`. One
`core restart now` → `System uptime: 8 seconds` → `pjsip show
transports` immediately listed **every** previously-stuck transport
correctly (10 objects, all with correct binds) — **except** `collide-b`,
which correctly remained absent (§K's genuine, restart-proof conflict,
not a bug). Extension `1095`'s explicit `transport=newone` pin survived
the restart unchanged and correct. This is direct, live proof — not
inferred from documentation — that a full restart is both **necessary**
(nothing short of it recovered these cases) and **sufficient** (every
recoverable case recovered in one shot, no partial/flaky recovery
observed) for every RESTART REQUIRED case found in this task. A full
outbound-trunk-registration recovery specifically was not re-verified
this round (§18); everything else the task asks for was.

---

## 20. Clean rebuild vs. hot reload vs. restart — kept separate

This investigation deliberately never used a clean-volume rebuild to
draw any conclusion about reload semantics — every finding in §4-§9/§19
came from the **same long-lived environment**, using the **existing**
Asterisk process, specifically because a clean rebuild starts a
**brand-new** process with no prior socket history at all, which would
silently hide every "stuck socket from a prior operation" finding this
task exists to surface. A clean rebuild is the right tool for proving
first-boot/migration-day behavior (already TASK-0018's own domain,
untouched here); it is the wrong tool for proving reload-vs-restart
behavior, and was not used for that purpose in this document.

---

## 21. `transport-smoke` evolution — design for a future implementation

Preserve all 40 existing checks unchanged (none of them touch rename,
delete-then-recreate, or disable-then-recreate-elsewhere — the exact
gaps this task's own live testing had to fill by hand). Proposed
additions, grouped by the task's own requested categories:

**HOT** (extend the existing pattern, cheap, no restart):
- Port-only change, same name (§4.D).
- Bind-address-only change, same name (§4.E).
- Protocol-only change, same name, both directions (§4.F).

**FAILED** (no restart involved, proves rejection or safe-observable
failure):
- Attempt to create/edit a transport onto a `(protocol, bind_address,
  bind_port)` already used by a different, currently-enabled transport
  — once the pre-save validation from §"implementation scope" below
  exists, assert it is **rejected at save time** (HTTP 200, friendly
  error, no DB write) rather than silently accepted (today's actual,
  proven-dangerous behavior, §K) — this is the regression test for the
  exact finding this whole investigation is built around.

**RESTART-REQUIRED / RECOVERY** (real Asterisk restart involved —
**must** live in a clearly separate, opt-in target, never folded into
the default `make transport-smoke` run, per the task's own explicit
"must never restart the user's environment unexpectedly" instruction):
a new `make transport-lifecycle-smoke` (or similarly, unmistakably
named) target that: creates a transport, renames it, confirms the
"restart required" UI signal appears (once §16 exists), issues a real
`core restart now` itself (loudly logged in the script's own output,
never silent), confirms the renamed transport is now live, confirms a
reference extension recovers, and cleans up afterward. This must be
documented prominently as "this target restarts the shared dev Asterisk
container" wherever it's invoked from (Makefile help text, this doc),
so a developer never triggers it by accident while relying on a live
call in the same environment.

---

## 22. Regression baseline (this investigation's own validation)

No code was changed, so this is a pure environment-health check, not a
"before vs. after" regression in the usual sense — confirmed clean
before and after the entire live-testing session:

| Suite | Result |
|---|---|
| `make smoke` | 16/0/0 |
| `make transport-smoke` | 40/40 |
| `make call-smoke` | 17/18 (the already-documented, pre-existing timezone-boundary artifact — unrelated, not newly introduced, not chased further per this task's own explicit instruction not to touch CDR/report timezone behavior) |
| `make trunk-smoke` | 21/23 (same artifact) |

Zero new PHP Fatal Errors (`grep -c "Fatal error"
/var/log/apache2/mag-error.log`, checked after the full session).

---

## 23. Stop conditions — none triggered

- Safe restart requires Docker socket exposure — **false**, AMI already
  suffices, confirmed live (§13); no socket mounted anywhere in
  `compose.yaml`.
- Persistent runtime-state tracking requires schema changes — **false**,
  a fully derived approach covers every case found (§15).
- Asterisk runtime cannot reliably expose enough state to distinguish
  configured vs. active — **not quite true, but with a real, documented
  limitation**: no structured AMI action for transports exists (§15),
  but the raw CLI-text fallback is proven reliable across every test in
  this document.
- Transport mutation behavior is nondeterministic — **false**, every
  single mutation tested was 100% reproducible.
- Automatic restart would require materially broader privileges —
  **false** (§13).
- New unrelated PHP 8.4 blocker — **none found**.
- Resolving reload failure handling requires broad logging refactor —
  **false**: the fix is the identical 3-line `error_log()` substitution
  TASK-0019 already applied elsewhere, applied to 3 more call sites —
  narrow, already-precedented, not a refactor.

**No stop condition applies.**

---

## 24. Explicitly deferred (unchanged)

TLS, certificate management, SRTP, WebRTC, Docker socket exposure,
HA/failover, rolling Asterisk restart, active-call draining, cluster
coordination, firewall management, PostgreSQL, PJSIP realtime, CDR
timezone correction, broad logging redesign. Also newly, explicitly
deferred by this investigation's own findings: a dedicated admin-facing
"Restart Asterisk now" button (§14 — a reasonable future increment, not
required by anything found here); WSS/WS socket-collision behavior
(never tested, `wss` stays seeded-disabled per every prior task).

---

## 25. Concrete implementation proposal

1. **Pre-save collision validation** (new, small, in
   `PjsipTransportsController::validatePost()`, same style as the
   existing name-uniqueness check): reject a create/edit whose
   `(protocol, bind_address, bind_port)` matches a **different**,
   currently-**enabled** transport row. This is the single highest-value
   fix — it converts §K's silent, dangerous FAILED APPLY into an
   immediate, friendly, pre-emptive rejection for the most common way
   to hit it.
2. **Rename detection → unconditional restart-required notice**: in
   `editAction()`, compare the loaded row's old `name` to the posted new
   `name`; if different, set the §16 restart-required message,
   regardless of anything else.
3. **Post-save runtime verification** (create and edit, every time, not
   only renames): after `regenerateAll()`, issue one `pjsip show
   transport <name>` `Command` call (reusing `PBX_Asterisk_AMI`, the
   exact mechanism `reload()` already uses) and check for the expected
   `bind` line; missing → §16's failed-apply message instead of a bare
   redirect.
4. **Fix the pre-existing `Zend_Registry::get('log')` masking bug** in
   all three generators' `reload()` methods, applying TASK-0019's own
   `error_log()` fix to these 3 remaining call sites — small, narrow,
   already-precedented, directly relevant to this task's own "safe
   apply semantics" question (§11).
5. **List-page runtime-mismatch badge** (§17): one additional `pjsip
   show transports` call in `indexAction()`, cross-referenced against
   enabled DB rows, flagged distinctly from the existing
   disabled-but-referenced banner.
6. **UX wording** per §16, matching this app's existing
   `alert_message`/`error_message`/`translate()` conventions — no new
   view-layer mechanism needed.
7. **`transport-smoke` evolution** per §21: HOT/FAILED checks folded
   into the existing `make transport-smoke` target; a **new, separate**
   `make transport-lifecycle-smoke` target for the restart-required/
   recovery checks, never run implicitly.
8. **No schema change, no migration, no Docker socket, no automatic
   restart, no new AMI permission** — everything above works with what
   already exists.

---

## Answers to the closing questions

**1. Which mutations are hot-reloadable?** Every field edit that keeps
the transport's `name` unchanged: protocol, bind address, bind port
(individually or in combination), domain, external addresses,
local_net, symmetric_transport, allow_reload, and both `is_default` and
`enabled`→`enabled` no-op toggles. Re-enabling a previously-disabled
transport is also effectively hot (because disabling never actually
closed the socket, §9). Creating a transport on a genuinely
never-before-used socket is hot.

**2. Which require restart?** Any rename, unconditionally (§6) — the
single, always-true rule this investigation found. Also, practically:
reusing an `address:port` that *any* prior transport (renamed, disabled,
or deleted) silently left orphaned — a case SENMA cannot fully predict
in advance (Asterisk's own leaked-socket history is invisible to any
config or AMI state this task found), which is exactly why the §25
post-save verification step exists as a catch-all alongside the
always-correct rename rule.

**3. Which should SENMA reject?** Only the one case that is not
"restart required" but genuinely **unfixable by any restart**: creating
or editing a transport onto a `(protocol, bind_address, bind_port)`
already claimed by a different, currently-enabled transport row (§25
item 1). Nothing else warrants outright rejection — every other
mutation this task tested either works immediately or works fully after
one restart.

**4. Should SENMA ever restart Asterisk automatically?** No (§14) — not
from a routine transport save. No evidence gathered in this
investigation overrides the task's own stated default against it; every
finding (system-wide call-drop on `now`, unbounded system-wide new-call
blocking on `gracefully`, one shared Asterisk process for the entire
deployment) reinforces that default rather than challenging it.

**5. How should `configured != runtime` be represented?** Without any
persistent state or schema change (§15): (a) a same-request comparison
of old vs. new `name` on every edit, always correct for the rename case;
(b) a same-request `pjsip show transport <name>` verification
immediately after every save, catching the collision/FAILED-APPLY case
directly; (c) a same-page-load cross-reference between enabled DB rows
and the live `pjsip show transports` listing on the transport list page,
catching anything that slipped through (a) and (b), or arose from an
operation performed outside SENMA entirely.

**6. What exactly should TASK-0020's implementation phase change?**
Exactly the eight items in §25 above — three small, evidence-driven
validation/verification additions to `PjsipTransportsController`, one
narrow pre-existing-bug fix already precedented by TASK-0019, one
additional list-page check, matching UX wording using the app's
existing conventions, and a `transport-smoke` extension split cleanly
into an always-run part and a separate, clearly-labeled,
restart-performing part. No schema change, no new privileges, no
automatic restart, nothing from the explicitly-deferred list.

---

## Implementation (approved, executed per the investigation's own §25 proposal)

Executed exactly as proposed, with one deliberate deviation from the
investigation's own §21 recommendation, explicitly requested by the
implementation task: the restart-recovery checks were folded directly
into `make transport-smoke` itself, rather than a separate opt-in
target — documented loudly in the script's own header comment (see
below) rather than isolated behind a second command.

### Files changed

- `snep/lib/Snep/PjsipTransports/Manager.php` — two new methods:
  `socketFamily($protocol)` (maps `udp` → `'datagram'`, everything else
  → `'stream'` — the investigation's own §5 finding, with `tls`/`ws`/`wss`
  grouped with `tcp` on ordinary POSIX socket semantics, documented as
  *not* independently Asterisk-tested to the same degree as the udp/tcp
  pair that *was* live-tested) and `findCollision($protocol,
  $bindAddress, $bindPort, $excludeId)` (checks every other transport
  row, enabled **or** disabled, for the exact same family+address+port —
  disabled rows are included deliberately, since the investigation
  proved a disabled transport's socket can still be silently bound).
- `snep/lib/Snep/PjsipTransportConf.php` — two new public methods:
  `isRuntimeActive($name, $bindAddress, $bindPort)` (the post-save
  verification primitive — one `pjsip show transport <name>` `Command`
  call, checked for "Unable to find object" / the expected `bind`
  substring) and `getRuntimeTransportNames()` (parses `pjsip show
  transports`' own CLI text for the list-page runtime-mismatch check —
  no structured AMI action exists for transports, confirmed in the
  investigation, so this is the only source). `reload()`'s
  `Zend_Registry::get('log')` call replaced with `error_log()`.
- `snep/lib/Snep/PjsipConf.php` / `snep/lib/Snep/PjsipTrunkConf.php` —
  the identical `error_log()` fix applied to their own `reload()`
  methods (the three methods the investigation named explicitly).
- `snep/modules/default/controllers/PjsipTransportsController.php` —
  `validatePost()` calls `findCollision()` right after the existing
  format checks, before any DB write; `addAction()`/`editAction()` call
  a new `reportApplyResult($before, $after)` method after
  `regenerateAll()`, which determines and flash-messages one of the
  three states (§ below); `removeAction()` always flash-messages
  restart-required after a successful delete; `indexAction()` computes
  a per-row `runtime_state` (`active`/`restart_required`/`disabled`) via
  one `getRuntimeTransportNames()` call, and surfaces the previous
  request's flash messages.
- `snep/modules/default/views/scripts/pjsip-transports/index.phtml` —
  renders the two new flash-message banners (warning-style for
  restart-required, danger-style for apply-failed) and a new "Runtime"
  column with an `active`/`restart_required`/`—` badge, each carrying a
  `data-runtime-state="..."` attribute on its `<td>` for unambiguous
  machine-readability (added specifically because the Runtime column's
  own "Active" badge would otherwise share the identical
  `label-success` Bootstrap class with the pre-existing Status column's
  "Enabled" badge — an unrelated concept — discovered as a real
  ambiguity while building the smoke-test's own badge-reading helper,
  fixed at the UI layer rather than worked around in the test).
- `scripts/transport-smoke-test.sh` — grew from 40 to **63** checks (see
  below). No schema file touched anywhere.

No schema change (`21` honored). No Docker socket, no new AMI
permission, no automatic restart anywhere in application code (`6`/`8`
honored — the only `core restart now` call in this entire change lives
in the test script, clearly marked, never in `PjsipTransportsController`
or any generator).

### Collision validation

`Snep_PjsipTransports_Manager::findCollision()` is called from
`validatePost()` — server-side, unconditionally, before `buildData()`/
`create()`/`update()` ever run, exactly matching the investigation's own
evidence: UDP and TCP never collide on an identical port (confirmed
live again, `task0020-col-a` udp + `task0020-col-c` tcp both bound to
`0.0.0.0:5211` simultaneously); two UDP (or two TCP) rows on the
identical `bind_address`/`bind_port` do collide, and the second save is
now rejected with a friendly, translated error naming the colliding
transport — confirmed live: `HTTP 200` (not `302`), zero DB row created,
generated config unchanged, Asterisk's own runtime never even
attempted the collision (unlike the investigation's own §K finding,
where Asterisk itself silently rejected the second object *after*
SENMA had already claimed success — this is now caught **before**
Asterisk is ever asked). Editing a transport without changing its own
socket correctly does not self-collide (the query excludes the row's
own id) — confirmed live.

### Configured/runtime comparison logic ("never trust HTTP 302 alone")

`PjsipTransportsController::reportApplyResult()` runs after every
create/edit's `regenerateAll()` and decides among exactly three
outcomes, matching §1's terminology precisely:

1. **Name changed** (`$before['name'] !== $after['name']`) → always
   RESTART REQUIRED, unconditionally — no verification call is even
   attempted, because the investigation proved zero exceptions across
   every rename tried.
2. **`enabled` transitioned true→false** → always RESTART REQUIRED
   (disabling was proven to behave exactly like a rename/delete at the
   socket level — the old socket does not close).
3. **Neither of the above, and now enabled** → `isRuntimeActive($name,
   $bind_address, $bind_port)` is called — a real `pjsip show transport
   <name>` query, never inferred from the HTTP status, the generated
   file, the AMI command's own submission, or `module reload`'s
   "reloaded successfully" text (all four explicitly named in the task
   as *not* sufficient proof, and none of them are consulted for this
   decision anywhere in the new code). True → ACTIVE (silent, matching
   the pre-existing redirect-only behavior for the common case). False
   → APPLY FAILED / RUNTIME MISMATCH, flash-messaged.
4. **Now disabled, and wasn't freshly transitioned** (created disabled,
   or edited while already disabled) → nothing to verify; this is the
   intentionally inert state, not a failure of anything.

A plain hot-applied edit (no rename, no enable/disable transition) was
confirmed live to fall through to outcome 3 and correctly report ACTIVE
with zero spurious banners — the new logic does not turn ordinary,
already-safe edits into false alarms.

### Restart-required / runtime-mismatch semantics and UI behavior

Three flash-message states (Zend Framework 1's own, already-vendored
`FlashMessenger` action helper — never used elsewhere in this app before
this task, but exactly the framework's intended tool for a one-shot,
post-redirect message; no new pattern was invented, no session hacking,
no schema): a warning-style banner for restart-required (rename, a
disable transition, or a delete), a danger-style banner for apply-failed
(a save that unexpectedly did not verify as active), and silence for the
ordinary hot-applied case (unchanged from before this task). The
transport list's new "Runtime" column independently, and separately,
re-derives `active`/`restart_required`/`—` (disabled-and-confirmed-gone)
on every page load from a fresh `pjsip show transports` call — it never
reads a stored flag, and it is not merely "enabled=1 therefore active"
(the exact anti-pattern the task warned against): a genuinely enabled-
but-stuck row (e.g. immediately after a rename) correctly shows
`restart_required`, confirmed live, and correctly flips back to `active`
the moment the underlying Asterisk state actually changes (confirmed
both by a real restart and, implicitly, by nothing else in this
implementation ever writing to a persisted state field that could go
stale).

### Reload error-masking fix

All three `reload()` methods named by the investigation
(`Snep_PjsipConf`, `Snep_PjsipTrunkConf`, `Snep_PjsipTransportConf`)
now call `error_log()` instead of `Zend_Registry::get('log')`, identical
to TASK-0019's own precedent. A project-wide search found roughly 40
additional `Zend_Registry::get('log')` occurrences (AGI scripts, rule
plugins/actions, dialplan action handlers) — **all left untouched**, per
the task's own explicit scope limit: these run under a *different*
bootstrap (`Snep_Bootstrap_Agi.php` and similar), not the web-request
bootstrap TASK-0019 already proved lacks a `'log'` registry entry, and
none of them sit on the transport save/apply path this task is scoped
to. Documented, not fixed, exactly as instructed.

Validated live, twice (long-lived environment and clean rebuild): a
genuinely malformed transport row (`protocol='garbage123'`, inserted
directly via SQL to bypass SENMA's own enum validation, since the UI
itself already correctly rejects this) was regenerated through
`Snep_PjsipTransportConf::loadConfFromDb()` — confirmed **no** "No
entry is registered for key 'log'" exception occurred (the fix works),
confirmed `/var/log/asterisk/full` recorded the real underlying error
(`res_sorcery_config.c: Could not create an object of type 'transport'
with id 'task0020-badproto'`), and confirmed the malformed row did not
corrupt generation of anything else in the same file (a legitimate,
unrelated transport created earlier in the same test run remained
correctly present after regeneration). The malformed row was deleted
and the config regenerated cleanly immediately afterward, per the
task's own "do not intentionally leave invalid configuration behind"
instruction.

### Rename evidence (re-confirmed, now with product-level handling)

Repeated the investigation's own rename scenario end to end, this time
through the finished feature rather than raw `pjsip show` probing:
created a transport, pinned a real reference extension **and** a real
trunk (both endpoint and registration) to it explicitly, renamed it
(same bind), and confirmed: the restart-required banner appears; the
generated extension and trunk config both cascade to the new name
*immediately*, at the file level (dependent regeneration was never the
broken part — re-confirmed, not just assumed); `pjsip show transport
<newname>` still correctly reports "Unable to find object" — the
runtime is honestly **not** claimed active; and the list page's own
Runtime badge for the just-renamed row shows `restart_required`, not
`active`, at this exact moment (the single most important assertion in
this whole task — the UI does not lie).

### Delete/disable evidence

Delete: creating and then deleting an unreferenced transport always
produces the restart-required banner now (matching the investigation's
finding that the socket never actually releases via a plain reload).
Reusing that exact socket under a new name *before* a restart was
confirmed to save successfully at the DB level (no DB-level collision
exists once the old row is truly gone) but is **never** reported as
`active` — the post-save verification catches it, the apply-failed
banner appears, and the list page's badge shows `restart_required`, not
`active`. Disable: transitioning an enabled transport to disabled now
always shows the restart-required banner too, for the identical
proven reason (the old socket persists). Both are honest, evidence-
backed representations, not merely `enabled=1`/`enabled=0` read back.

### Controlled restart recovery (test harness only)

One real `core restart now`, issued **only** from
`scripts/transport-smoke-test.sh` (never from any application code
path — confirmed by reading every line changed in this task), recovered
every previously-stuck case in a single shot, re-verified end to end:
the renamed transport becomes live with the correct bind; the old name
stays correctly absent; the list-page badge flips from
`restart_required` to `active` with **no code change and no persisted
flag anywhere** — purely because the same derived check now observes a
different Asterisk reality; the dependent extension's endpoint reports
the new transport name; the dependent trunk's endpoint reports it too;
the trunk's outbound registration reaches `Registered` again within the
same ~15s window `trunk-smoke-test.sh` already established as normal;
and the previously-stuck socket reuse (the "create a new transport on a
just-deleted transport's old port" case) succeeds immediately after the
restart. This is the exact `docs/tasks/0020...md` item 13/14 validation
sequence, now proven against the finished feature rather than ad hoc
CLI probing.

### `transport-smoke` evolution: 40 → 63 checks

All 40 existing checks preserved byte-for-byte unchanged. 23 new checks
appended as "PART 3," using its own independent fixtures
(`task0020-*` transports, extension `1094`, its own trunk fixture):
pre-save collision rejection (3 assertions: A unchanged, B never
generated, B never reaches Asterisk at all), non-collision acceptance
(UDP+TCP same port), a plain hot-applied edit reported active with zero
spurious banners, dependent pinning before a rename, restart-required
reporting on rename, configured-state dependent regeneration cascading
to the new name, runtime correctly NOT reported active pre-restart, the
list-page badge correctly showing `restart_required` pre-restart,
restart-required reporting on delete, socket reuse correctly never
claimed active pre-restart, the controlled restart itself, post-restart
recovery of the renamed transport / the dependent extension / the
dependent trunk (endpoint **and** registration) / the reused socket, and
the reload-failure-masking fix validation (no secondary exception,
useful detail in `/var/log/asterisk/full`, no corruption of unrelated
config, no artifact left behind). The script's own header comment now
states plainly, in bold, that running `make transport-smoke` performs a
real, controlled Asterisk restart as part of its normal run — a
deliberate departure from the investigation's own §21 recommendation of
a separate opt-in target, made because the implementation task
explicitly asked for the restart-recovery checks to live inside `make
transport-smoke` itself.

**Two real bugs were found and fixed while building this — both in the
test script, not the application**, confirmed by direct HTML/state
inspection before concluding so: (1) the list-page badge-reading helper
initially grepped for the `label-success` CSS class, which the
pre-existing Status column's own "Enabled" badge also uses for an
unrelated concept, producing a false "active" read — fixed by adding a
`data-runtime-state="..."` attribute to the view (a genuine, small UI
improvement, not merely a test workaround) and reading that instead;
(2) the test's own final cleanup attempted to delete the rename-test
transport *before* clearing the dependent extension/trunk's references
to it, which the application's own pre-existing reference-protection
correctly blocked — reordered to clear dependents first, matching the
pattern the trap-based cleanup function already used correctly.

### Regression (final baseline)

| Suite | Long-lived dev environment | Clean rebuild (all 7 volumes wiped) |
|---|---|---|
| `make smoke` | 16/0/0 | 16/0/0 (after dismissing the ITC first-run prompt once, exactly as every prior PJSIP task has documented — not a regression) |
| `make call-smoke` | 18/18 | 18/18 |
| `make trunk-smoke` | 23/23 | 23/23 |
| `make transport-smoke` (×3 long-lived, ×2 clean, idempotency) | 63/63 every time | 63/63 every time |

`call-smoke`/`trunk-smoke` show their full, un-degraded baseline in
both environments this round — the already-documented timezone-boundary
artifact (TASK-0015/0019) is time-of-day-dependent and simply was not
inside its ~3-hour daily window during this validation pass; it was not
chased, fixed, or touched, per this task's own explicit instruction.

Zero new PHP Fatal Errors in either environment
(`grep -c "Fatal error" /var/log/apache2/mag-error.log` = 0, checked
after the full session, both environments). Zero occurrences of "No
entry is registered for key 'log'" in either environment's app log.
The already-known, pre-existing, occasional ODBC/CDR first-boot race
(TASK-0018 §14) recurred once on this clean rebuild, self-contained and
unrelated to transports, exactly as previously characterized — `make
call-smoke`/`make trunk-smoke`'s own CDR-correctness checks both passed
regardless.

### Remaining limitations (honest, not papered over)

- **`apply_failed` cannot distinguish a permanently-conflicting
  collision from a temporarily-stuck, restart-fixable socket.** Both
  produce an identical signal (`isRuntimeActive()` returns false, and
  it wasn't a rename or disable transition) because SENMA has no
  visibility into Asterisk's internal socket history — the investigation
  established this is fundamentally unobservable without either a
  structured AMI action that does not exist, or new Asterisk-side
  instrumentation, both out of this task's scope. The message wording
  is deliberately hedged ("may already be in use... previous
  configuration may still be active") rather than prescriptive, since a
  restart fixes one case and not the other and SENMA cannot tell them
  apart in advance.
- **The pre-save collision check uses exact `bind_address` string
  matching**, not a `0.0.0.0`-wildcard-overlaps-everything rule — per
  the investigation's own "do not invent, use the audit result"
  instruction, since only exact-address collisions were empirically
  proven. A specific-IP transport colliding with an existing
  `0.0.0.0`-bound one of the same family/port would not be caught by
  the pre-save check, but *would* still be caught by the post-save
  runtime verification (defense in depth, by design).
- **`tls`/`ws`/`wss` are grouped with `tcp`'s socket family by ordinary
  POSIX reasoning, not by independent Asterisk-specific live testing**
  (only `udp`/`tcp` were empirically exercised, in this task and the
  investigation both) — documented plainly in `findCollision()`'s own
  docblock, not asserted as equally evidence-backed.
- **No automated coverage of an in-progress call surviving/not-surviving
  the test-harness restart** — the investigation's own §18 already
  flagged this as unverified and out of reasonable scope; this task did
  not add it either (item 20's own instruction: no active-call draining,
  no new active-call testing beyond what already exists).

### Explicitly deferred restart controls

No admin-facing "Restart Asterisk" button was added (would require
separate approval per the task's own item 23). No automatic restart of
any kind exists in application code. No Docker socket, no new AMI
permission, no privileged mode, no new management port — the only
restart capability anywhere in this change is the test harness's own,
explicit, loudly-documented `core restart now` call.

---

Stopping here at a commit checkpoint. Not beginning TASK-0021.
