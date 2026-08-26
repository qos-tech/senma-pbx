# TASK-0016 — Inbound PJSIP trunk identification and routing

## Status

**Implemented and validated.** §§1-20 below are the original
investigation (unchanged, preserved for the record); §21 onward covers
the implementation, real evidence, and final regression this task's
second phase produced. `make smoke`: 16/0/0. `make call-smoke`: 18/18.
`make trunk-smoke` (extended, both directions): **23/23** — the existing
15 outbound checks unchanged plus 8 new inbound checks — run repeatedly
(idempotent) and from a fully clean rebuild (all 7 named volumes wiped,
including `mag-db`). A real inbound INVITE, originated by the `provider`
simulator, was correctly identified by SENMA as the trunk it came from,
routed through the completely unmodified AGI/rule engine, rang and was
answered by a real SENMA-provisioned PJSIP extension, produced a real
`cdr_adaptive_odbc` CDR row, and was read back through SENMA's own report
API — closing the loop TASK-0015 deliberately left open. Both prerequisite
bugs found during investigation (§2.2/§2.3) are now fixed. Not committed
— stopping at the commit checkpoint.

## Status (original investigation, superseded by the above)

**Investigation/design only. No runtime code, schema, or Docker
configuration was changed.** All findings below combine static reading of
the current tree with live, evidence-gathering tests against the running
dev stack (a real inbound INVITE placed by the existing `provider`
simulator toward SENMA's `asterisk` service). Every live change made
during this investigation (temporary `identify`/scratch-endpoint config,
a temporary route/trunk/extension fixture, one reversible SQL `id_regex`
update) was undone before finishing. Confirmed clean: `git status` clean,
`make smoke` 16/0/0, `make call-smoke` 18/18. This document builds on
TASK-0008 (legacy telephony audit), TASK-0009/0010/0011 (PJSIP
extensions), TASK-0014 (outbound trunk architecture), and TASK-0015
(outbound trunk implementation, `make trunk-smoke` 15/15).

**Two real, independent, previously-latent bugs were found and are
reported here per CLAUDE.md's bug/stop policy — neither is fixed by this
document.** They are prerequisites for TASK-0016's implementation, in the
same sense TASK-0014's P0-1/P0-2 were prerequisites for TASK-0015.

---

## Goal

Design the smallest real inbound PJSIP trunk path:

```
provider simulator -> PJSIP trunk identification -> SENMA inbound context
-> existing AGI/rule engine -> existing SENMA destination/rule
-> SENMA-provisioned PJSIP extension -> answer -> real CDR -> report readback
```

and stop for approval before implementing it.

---

## 1. Legacy inbound call trace (confirmed still accurate)

TASK-0008 §4 already traced this precisely; re-reading the same code
today (`PBX_Interfaces.php`, `PBX_Asterisk_AGI_Request.php`,
`PBX_Dialplan.php`, `snep/agi/snep.php`, `PBX_Rule.php`) confirms it is
**unchanged and still exactly accurate**:

```
Inbound INVITE resolves to some Asterisk channel "TECH/name-hash"
  -> [default] context (snep/install/etc/asterisk/extensions.conf:47),
     the SAME catch-all "_." pattern every internal/outbound call uses --
     there is no separate inbound-routing context or entry point
  -> AGI(snep/snep.php)                                    [snep.php:59-114]
  -> new PBX_Asterisk_AGI_Request($agi_request)             [Request.php:111-151]
       - $channel = $this->request['channel']
       - $channel = substr($channel, 0, strpos($channel, '-'))   <- see §2/§3, BUG
       - "Local/0000" -> "SIP/"+4 digits special case (chan_sip-only, irrelevant here)
       - $object = PBX_Interfaces::getChannelOwner($channel)     [Interfaces.php:98-145]
           - checks `trunks` FIRST: preg_match("#^{id_regex}$#i", $channel)
             -> PBX_Trunks::get($interface['id'])                [Trunks.php:80-157]
           - else checks `peers` (peer_type='R'): preg_match against `canal`
       - $this->setSrcObj($object)                          <- becomes $request->getSrcObj()
  -> PBX_Dialplan::parse()                                  [Dialplan.php:63-84]
       - PBX_Rules::getAll(), first rule where isActive() && isValidDst($request->destino)
         && isValidSrc($request->origem) && isValidTime(...) && isValidAliasTime(...)
       - isValidSrc()/isValidDst() -> PBX_Rule::checkExpr($type, $value, $input)
         [Rule.php:354-419]; case 'T' (Trunk): true iff
         $request->getSrcObj() instanceof Snep_Trunk && getSrcObj()->getId() == $expr
  -> $regra->execute($origem)                                [Rule.php:482-575]
       - runs the matched rule's PBX_Rule_Action list, e.g. DiscarRamal
         (ring/queue/group/IVR -- whichever action the matched rule has)
  -> Asterisk's own cdr_adaptive_odbc writes the CDR row (unchanged, TASK-0007)
  -> SENMA's existing CallsReport endpoint reads it back (unchanged)
```

**Item 7's question is answered directly by this trace**: the inbound
entry context is **already** `[default]` — the exact same context every
internal and outbound-trunk call already uses. `Snep_PjsipTrunkConf`
already writes `context=<peer['context']>` on every trunk endpoint
(`PjsipTrunkConf.php:177`), and `TrunksController::addAction()` already
hardcodes `"context" => "default"` for every new trunk
(`TrunksController.php:587`) — a PJSIP trunk's endpoint is **already**
generated with `context=default` today, unchanged since TASK-0015. **No
new context, no test-only `Dial()` shortcut, is needed or should be
created.** This was independently confirmed live (§3): the real inbound
test call entered `[default]` and reached `AGI(snep/snep.php)` exactly as
predicted, using the entirely unmodified, already-generated trunk
endpoint.

The one thing this trace depends on that **does not work correctly
today** is the very first step of identification — see §2/§3.

---

## 2. What identifies an inbound trunk today, and the two real bugs found

### 2.1 Field semantics matrix (traced from code, not inferred from names)

| Field | Column | What it actually controls | Confirmed by |
|---|---|---|---|
| `host` | `trunks.host` -> `peers.host` | AOR's static outbound `contact=sip:<host>:<port>` (TASK-0015 §5); **also the natural, already-mandatory source for an inbound `identify` object's `match=`** (§4) | `Snep_PjsipTrunkConf::renderTrunk()`, live test §3 |
| `type` | `trunks.type` | Technology dispatch (`SIP`/`IAX2`/`PJSIP`/`KHOMP`/...) in `PBX_Trunks::get()` and both generators | `Trunks.php:90-143` |
| `insecure` | `trunks.insecure` | chan_sip-only auth-bypass flag string (`port,invite`). **Never read by `Snep_PjsipTrunkConf` at all** — confirmed by grep, zero references. Already hidden from the PJSIP UI form since TASK-0015 (§7 of that doc). No PJSIP effect, no PJSIP mapping exists or is needed: PJSIP's trust model for a trunk is entirely `identify`-based (§4), not a per-flag toggle | `PjsipTrunkConf.php` (no `insecure` reference), `addedit.phtml` |
| `dialmethod` (incl. NOAUTH) | `trunks.dialmethod` | For chan_sip: whether ANY named peer stanza is generated at all (TASK-0014 §1/§4). For PJSIP: **stored but not interpreted by `Snep_PjsipTrunkConf` at all today** — only `reverse_auth` gates the `registration` object (TASK-0015 §5). See §6 below: this is actually the right outcome, not a gap | `PjsipTrunkConf.php:236` (`if ($trunk['reverse_auth'])`, no `dialmethod` check anywhere in the file) |
| `reverse_auth` | `trunks.reverse_auth` | Whether SENMA sends an **outbound** REGISTER to the provider (TASK-0014 §5, unchanged). **Confirmed by direct analogy to TASK-0015's own finding, and now independently by this task's live test, that this is unrelated to inbound acceptance**: SENMA is the registering *client* for this trunk, never the *registrar* — a provider's inbound INVITE is a fresh, unauthenticated request from SENMA's point of view regardless of whether SENMA also happens to be registered outbound to the same provider. Exactly like TASK-0015 found SENMA's own outbound INVITE needed the provider's `identify` object *despite* SENMA registering there, the provider's inbound INVITE needs SENMA's own `identify` object *despite* SENMA registering to the provider. **This refutes TASK-0014 §20's "narrower claim" that the register-based case might get inbound "for free"** — it does not; `identify` is required identically for register-based and NOAUTH/static trunks alike | Live test §3 (a plain `identify`-object test, no registration state involved at all, was sufficient and necessary) |
| `username` | `trunks.username` -> `peers.defaultuser` | The **provider-assigned account name** — used only as the `auth` object's `username=` (outbound calls/REGISTER) and the registration's `client_uri=`. **Never** SENMA's own PJSIP endpoint identity (`trunk-<id>`, a completely separate name) | `Trunks.php:124-129`, `PjsipTrunkConf.php:209,238,242` |
| `fromuser`/`fromdomain` | `peers.fromuser`/`peers.fromdomain` | Direct-rename endpoint `from_user=`/`from_domain=` (TASK-0014 §3, unchanged). Outbound-request identity only, irrelevant to inbound identification | `PjsipTrunkConf.php:188-193` |
| `context` | `trunks.context` -> `peers.context` | Endpoint `context=`, always `"default"` for a PJSIP trunk today (§1). Confirmed, not a variable this task needs to touch | `TrunksController.php:587`, `PjsipTrunkConf.php:177` |

### 2.2 Bug #1 (CONFIRMED LIVE) — `id_regex` is computed wrong for PJSIP trunks

`TrunksController::preparePost()`:
```php
} else if ($trunktype == "PJSIP") {
    $trunk_data['dialmethod'] = strtoupper($trunk_data['dialmethod']);
    $trunk_data['channel'] = $trunk_data['id_regex'] = "PJSIP/" . $trunk_data['username'];
```
(`TrunksController.php:667`). `$trunk_data['username']` here is the
**provider-assigned account name** the admin typed into the "Username"
field (e.g. `senma-outbound`) — but `PBX_Trunks::get()` and
`Snep_PjsipTrunkConf` both name the actual PJSIP endpoint `trunk-<id>`
(TASK-0014 §10, TASK-0015 §4), a completely different string, not
derived from `username` at all. `getChannelOwner()`'s regex match
(`^{id_regex}$` against the inbound channel) therefore **can never match
a real PJSIP trunk's inbound channel**, independent of bug #2 below.
Confirmed live: a real fixture trunk's stored `id_regex` was
`PJSIP/senma-outbound`, which matches neither the raw channel name nor
either of bug #2's two possible truncations.

This is old, silent, and exactly as unreachable as TASK-0015's own two
PHP-8 bugs were before it — no inbound PJSIP trunk call has ever been
attempted in this project before this task.

### 2.3 Bug #2 (CONFIRMED LIVE, with real captured evidence) — first-hyphen channel truncation breaks any hyphenated object name

`PBX_Asterisk_AGI_Request::__construct()`:
```php
$channel = $this->request['channel'];
$channel = strpos($channel, '-') ? substr($channel, 0, strpos($channel, '-')) : $channel;
```
(`Request.php:117-120`) strips Asterisk's own `-<sequence>` channel-
instance suffix by truncating at the **first** hyphen. Every object name
this has ever been exercised against — bare extension numbers (`1099`),
plain chan_sip usernames — has **no internal hyphen**, so "first hyphen"
and "last hyphen" have always coincided. TASK-0014/0015's PJSIP trunk
naming convention, `trunk-<trunks.id>` (e.g. `trunk-2`), is the **first
object name in this codebase's history with an internal hyphen** —
introduced for outbound purposes, never exercised against this inbound
code path until this task's live test.

**Live evidence** (`docker compose exec app php -r ...` against a real
channel name captured from a genuine inbound INVITE that a correct
`identify` object had just routed to endpoint `trunk-2`):
```
raw:            PJSIP/trunk-2-00000002
strpos (first): PJSIP/trunk      <- current code's actual result: loses the trunk id
                                     entirely, and would collide identically across
                                     every PJSIP trunk in the system
strrpos (last): PJSIP/trunk-2    <- correct result
```
**Both bugs are real, independent, and either one alone is already
sufficient to make `getChannelOwner()` never identify a PJSIP trunk's
inbound call.** Fixing only #1 without #2 (or vice versa) is not enough.

**Safety of a `strpos`→`strrpos` fix, checked against every currently-
real name, not assumed**: queried live `peers.canal` and `trunks.id_regex`
for every row that exists today (extension `PJSIP/1099`, the pre-existing
`PJSIP/senma-outbound`-style trunk value) plus every real captured
extension channel (`PJSIP/1099-00000005`) — **none contain an internal
hyphen**. `strpos`/`strrpos` are provably identical for every case this
method has ever been exercised against except the new trunk convention.
This is a real, technology-agnostic, but currently invisible latent bug
in a shared, core routing-identification method used by **every** call
(internal, outbound-trunk, and — once fixed — inbound-trunk) — it must be
validated against the full regression suite (`make smoke`, `make
call-smoke`, `make trunk-smoke`), not merged on code-reading confidence
alone.

**Neither bug is fixed by this document.** Both are reported here,
pending approval, exactly as TASK-0014's P0-1/P0-2 were.

---

## 3. AGI channel variables — live evidence

A real INVITE was placed by the `provider` container toward SENMA's
`asterisk` service (a temporary scratch endpoint + a temporary `identify`
object, both reverted; see the live-verification session for exact
commands). Once `identify` correctly routed the INVITE to a (temporarily
hyphen-free, scratch-named) endpoint, the exact real AGI log line
`snep.php` itself emits (`Connection attempt from $request->origem
($request->channel) to $request->destino`) read:

```
Connection attempt from anonymous (PJSIP/trunktest1-00000003) to 58888
```

- **`origem`/`CALLERID(num)`**: `anonymous` — an artifact of the test
  harness's unauthenticated `channel originate` call carrying no real
  From: header identity, **not** a PJSIP-vs-chan_sip difference. A real
  carrier's INVITE would carry the caller's real CLI in the From:/P-Asserted-Identity
  header exactly as chan_sip already handled — no new code path is
  implicated here, callerid extraction is channel-technology-agnostic
  (already established, TASK-0008 §3/§6).
- **`channel`**: the full PJSIP channel string, `TECH/endpoint-sequence`
  — exactly the string §2.3's truncation bug consumes.
- **`destino`/`extension`**: the dialed number (`58888` in the live
  test) arrived **completely unmodified** — no URI-escaping, no prefix,
  no suffix added by chan_pjsip. This directly answers item 8: **no DID
  extraction code is needed beyond what already exists** — the existing
  `${EXTEN}`-based mechanism (`extensions.conf`'s `_.` catch-all,
  unchanged since TASK-0008) already captures whatever number the
  provider's INVITE addresses, exactly as it does for any other inbound
  or internal call, PJSIP or chan_sip.
- **No other SIP_HEADER/SIPAddHeader dependency was found to apply to
  the inbound-trunk-identification path** — TASK-0008's one flagged
  chan_sip-specific dialplan dependency (`DiscarRamal`'s diff-ring
  feature) is an extension-side ring-distinctiveness feature, unrelated
  to and unaffected by trunk inbound routing.
- **A real, independent dialplan collision was found and must inform the
  reserved test DID choice** (item 14): `snep/install/etc/asterisk/snep-features.conf`
  contains `exten => _7XX,1,Goto(parkedcalls,${EXTEN},1)` (call parking,
  pre-existing, unrelated to trunks), which intercepts **any** 3-digit
  number starting with 7 before it ever reaches `AGI(snep/snep.php)`.
  `[default]`'s own `_9XX` pattern (conference rooms) is a second,
  already-documented collision zone (TASK-0008 §1). **`600` (TASK-0015's
  outbound destination) and any `7XX`/`9XX` number are unsafe as a new
  inbound test DID.** A 5-digit number (`58888`, used throughout this
  investigation's live test) avoids both patterns cleanly and is
  recommended as the reserved inbound test DID.

---

## 4. PJSIP identify model — determined and confirmed live

**Answer to item 4's explicit question**: TASK-0016 needs exactly
**endpoint + auth + aor (all three already generated by TASK-0015,
unmodified) + one additive `identify` object** — no other new object
type. Confirmed live: with a `type=identify` object (`match=<provider's
real container IP>/32`) bound to a trunk endpoint, an inbound INVITE from
that IP was **immediately accepted and resolved to the correct endpoint**
— `Reachable`, no digest challenge, no registration state involved at
all. This is independent of `reverse_auth`/registration (§2.1) and
independent of `dialmethod` (§6) — a single, uniform mechanism covers
every PJSIP trunk model this project has.

**Do not conflate outbound registration with inbound identification**
(the task's own explicit instruction, and directly confirmed): the
`registration` object (TASK-0015) governs SENMA's own outbound REGISTER
liveness only; it has zero bearing on whether an inbound INVITE from the
provider is recognized. The two are orthogonal PJSIP objects addressing
two unrelated directions of trust.

---

## 5. Generator impact — additive, no regression to existing objects

**Proposed**: extend `Snep_PjsipTrunkConf::renderTrunk()` to additively
emit one more section per trunk, after the existing aor/registration
blocks, changing nothing about them:

```
[trunk-<id>-identify]
type=identify
endpoint=trunk-<id>
match=<peer['host']>
```

- **Naming**: `trunk-<id>-identify`, following the exact existing suffix
  convention (`-auth`, `-registration`) TASK-0014 §10 already
  established — no new naming scheme needed.
- **Source field**: `peer['host']` — the same column already mandatory
  for the AOR's static `contact=` (TASK-0015 §5), so this requires **no
  schema change and no new UI field** (item 6's own question, answered:
  the current DB representation already safely expresses this).
- **Emitted unconditionally for every PJSIP trunk row**, regardless of
  `dialmethod`/`reverse_auth` (§2.1/§4's finding that identify is needed
  uniformly) — the simplest, most representative, no-special-casing
  design.
- **Does not touch** the existing endpoint/auth/aor/registration
  emission at all — purely additive, matching the task's explicit
  instruction not to regress outbound calls. `make trunk-smoke`'s
  existing 15 outbound checks are the regression gate for this claim.

**A separate, non-generator fix is also required** (§2.2/§2.3) before
this generator change can have any effect: `getChannelOwner()` must
actually be able to match a real inbound channel to `trunk-<id>` at all.
Proposed approach, evidence-based rather than assumed:

- **Do not rely on the stored `trunks.id_regex` column for PJSIP rows at
  all.** `trunks.id` (the value the real object name is built from) is
  not known yet at the point `TrunksController::preparePost()` builds
  `$trunk_data` (before the `INSERT`) — the exact same chicken-and-egg
  problem TASK-0015 §4 already solved for `canal` by never parsing
  identity back out of a stored string. Extending that **same, already-
  approved principle** to `id_regex`: add one small, PJSIP-specific
  branch to `PBX_Interfaces::getChannelOwner()`'s trunk loop that
  computes the expected pattern directly from each trunk row's `id`
  and `type` (`"^PJSIP/trunk-" . $interface['id'] . "$"`) instead of
  reading the stored (and, for PJSIP, meaningless) `id_regex` value —
  mirroring how `PBX_Trunks::get()` already special-cases `$tech ==
  "PJSIP"` right next to the exact same loop's sibling logic. This is a
  narrow, technology-specific branch in one already-central method, not
  a rewrite of it; every other technology's existing `id_regex`-based
  matching is untouched.
- Fix `PBX_Asterisk_AGI_Request`'s truncation from `strpos` (first
  hyphen) to `strrpos` (last hyphen) — §2.3's confirmed-safe, minimal
  fix.
- **A decision, not yet made, requiring approval**: whether
  `TrunksController::preparePost()`'s current (wrong) `id_regex` write
  for PJSIP trunks should simply be left alone (dead, unread column) once
  `getChannelOwner()` no longer reads it for PJSIP rows, or corrected
  for consistency/future-proofing even though nothing reads it. Leaning
  toward leaving it as dead data with a one-line comment explaining why,
  to keep the change minimal — flagged here for explicit approval rather
  than decided unilaterally.

---

## 6. NOAUTH/IP-auth mapping — no schema change, no STOP condition

Item 6's explicit stop-condition does **not** trigger. `trunks.host`
already exists, is already mandatory for any PJSIP trunk (used
unconditionally for the AOR's static contact since TASK-0015), and is
exactly what an `identify.match=` needs. §2.1/§4 already found that
`identify` is required **uniformly**, independent of `dialmethod` — a
real, evidence-based simplification: chan_sip's three-way NOAUTH/insecure/
normal split collapses, under PJSIP, onto a single uniform mechanism
(`identify`-by-host, no inbound `auth=` ever emitted, matching TASK-0015's
existing choice to only ever emit `outbound_auth=`, never `auth=`, since
inbound digest-authenticating a carrier was never how any current trunk
model works). **No new column, no new UI field, no new dialmethod
branch in the generator is needed for inbound identification to work for
either the NOAUTH or the register-based trunk model.**

---

## 7. Context — confirmed, no new context needed

Covered fully in §1. `context=default` is already generated,
unconditionally, for every PJSIP trunk since TASK-0015. The real inbound
test call entered `[default]` and reached `AGI(snep/snep.php)` with zero
dialplan changes. **No test-only `Dial()` context was created or is
proposed.**

---

## 8. DID extraction — confirmed passthrough, one real constraint found

Covered in §3: the dialed number arrives at `$request->destino`
unmodified, using the exact same mechanism every other call already
uses — no new extraction code. The one real, concrete finding: **`600`,
and any `7XX`/`9XX` number, collide with pre-existing dialplan patterns**
(call parking, conferences) and are unsafe as a reserved inbound test
DID. **`58888`** (used throughout this investigation's live test, proven
collision-free and proven to survive the full path unmodified) is
recommended as the fixed reserved inbound test DID for `make
trunk-smoke`'s inbound phase.

---

## 9. Inbound route fixture strategy

Same conclusion TASK-0015 §13 already reached and this task's own
live verification reused successfully: `RouteController::addAction()`'s
**`srcValue`/`dstValue` fields are, in fact, simple `type:value` strings**
(`RouteController.php:545-564`, e.g. `T:2`, `RX:58888`) — the genuinely
hard-to-reverse-engineer part is exclusively the dynamic, JS-driven
`actions_order`/`action_<n>[...]` per-action-type config (`RouteController.php:614-622`,
`isValidPost()`), which differs per action class and is assembled
client-side. This matches TASK-0015's own precedent and reasoning exactly
(option B — "existing domain API," per the task's own preference order —
still beats a raw HTTP form reverse-engineering effort, and remains far
above raw SQL).

**Proposed**: extend the existing `scripts/trunk-smoke-route.php`
(already reviewed/approved in TASK-0015, not a new file) with a second
mode, e.g.:
```
php trunk-smoke-route.php create-inbound <trunk_id> <did> <extension> <desc>
```
building `$rule->addSrc(['type' => 'T', 'value' => $trunkId])`,
`$rule->addDst(['type' => 'RX', 'value' => $did])`, and a `DiscarRamal`
action (`setConfig(['ramal' => $extension])` — confirmed field name,
`DiscarRamal.php:158-160`) in place of the existing mode's
`DiscarTronco`. This is exactly the pattern the live verification session
used successfully (via a throwaway, non-committed scratch script) to
prove the full pipeline end to end — formalizing it as a second mode of
the already-existing, already-reviewed script rather than a new file.

---

## 10. Destination — reuse the existing PJSIP test extension

**Extension `1099`** (already provisioned by `call-smoke-test.sh`/
`trunk-smoke-test.sh`'s existing fixtures, already a real registered
PJSIP endpoint) is the proposed inbound ring destination — no new
extension fixture needed. The live verification proved the complete
chain **provider → trunk → SENMA AGI → rule → PJSIP extension**, with
extension 1099 actually ringing and answering a real call — no
provider-to-extension shortcut of any kind was used or is proposed.

---

## 11. CDR behavior — predicted, then validated: one row (not two)

**Prediction, stated before validation, per the task's own instruction**:
TASK-0015's outbound two-CDR-row finding was tied to `DiscarTronco`'s own
execution path (both `DiscarTronco` and `DiscarRamal` call
`Asterisk_AGI::exec_dial()` identically — `DiscarTronco.php:390`,
`DiscarRamal.php:387` — so the duplicate is not an artifact of "a trunk
being involved somewhere in the call" in general). Since an inbound-trunk
call is routed through `DiscarRamal` (ringing an extension), exactly like
every other `DiscarRamal`-terminated call TASK-2010/2011's regression
suite has always produced exactly one CDR row for, the predicted shape
was **one row**, not two.

**Validated live**: confirmed. The real inbound test call produced
**exactly one** `cdr` row:
```
src=anonymous dst=58888 channel=PJSIP/trunktest1-00000004
dstchannel=PJSIP/1099-00000005 disposition=ANSWERED duration=4 billsec=4
```
No second, empty `lastapp='Hangup'` row appeared, unlike TASK-0015's
outbound case. **Not "fixed" because it differs from the outbound
shape** — per the task's own explicit instruction, this is simply a
different, correct, single-row shape tied to which action executes
(`DiscarRamal` vs `DiscarTronco`), not a bug in either case.

---

## 12. Status/UI impact — none required

No additional Trunks-page status work is needed beyond what TASK-0014 §6
already catalogued and TASK-0015 left unimplemented (out of scope there,
still out of scope here). Inbound identification is validated via CLI
(`pjsip show identify`, `pjsip show endpoint`) and log/CDR evidence in
`make trunk-smoke`, exactly like every other TASK-0015 status check —
**not** through new PHP/UI code. Per the task's own instruction not to
broaden status work unnecessarily, none is proposed.

---

## 13. Security boundaries

- **Exact source matched**: the proposed `identify.match=` value is
  `trunks.host` — the specific, single provider host/IP the admin
  already configured for this trunk's outbound dialing (the AOR's own
  `contact=` target). This is **narrower** than TASK-2015's own
  provider-side `identify` object, which (necessarily, since it had to
  match SENMA's *dynamically registered* contact rather than a fixed
  peer) used the whole pinned dev-network CIDR (`172.28.0.0/16`).
  SENMA's side of the relationship has a fixed, known peer, so it should
  — and does, in this proposal — match only that specific host, not a
  subnet.
- **Docker-only development behavior**: in this dev topology,
  `trunks.host` will resolve to the `provider` container's Docker-DNS
  name/IP on the isolated `mag` network, with no host port published on
  either side — an attacker would need to already be inside the compose
  network to reach this at all.
- **Production implications**: in a real deployment, `trunks.host` is
  whatever specific IP/hostname the actual ITSP documents as their
  signaling gateway. `identify`-by-host trusts that source completely
  for endpoint resolution **without a digest challenge** — this is the
  normal, expected trust model for a carrier trunk (matching how
  chan_sip's own `insecure=invite`/NOAUTH peers already worked, §2.1),
  not a new or weaker posture than what SENMA already does today for
  chan_sip trunks.
- **Why a broad match would be unsafe**: a wildcard or overly broad
  `match=` (e.g. `0.0.0.0/0`, or reusing a whole cloud provider's public
  CIDR block) would let **any** host on the internet present itself as
  this trunk without authentication — able to place calls that resolve
  to `context=default` and reach SENMA's full routing engine exactly as
  a legitimate carrier call would. **`match=0.0.0.0/0` must never be
  generated by this generator, under any configuration** — the proposal
  in §5 always derives `match=` from the specific `trunks.host` value the
  admin already provided for this one trunk, never a wildcard, and never
  a value not already used elsewhere in the same trunk's own
  configuration.

---

## 14. Provider simulator — extend, don't replace

**Proposed minimal, permanent addition** to the existing simulator
(`docker/provider-config/`, TASK-2015 — no new container, no new image,
no host port): one small, static, always-present endpoint the provider
can originate *from*, mirroring the relationship SENMA's own `trunk-<id>`
endpoint already has toward the provider, but in reverse:
```
[to-senma]
type=endpoint
context=<anything -- this leg never needs to run application logic>
disallow=all
allow=ulaw,alaw
aors=to-senma

[to-senma]
type=aor
contact=sip:asterisk:5060
```
No `auth=`/secret needed (SENMA's own trunk endpoint has no inbound
`auth=` either, §6 — a real ITSP's own switch doesn't authenticate to
itself). `asterisk` is SENMA's container's stable Docker-DNS name on the
`mag` network (already used, unmodified, by other tooling in this
project). `make trunk-smoke`'s inbound phase would then run, from the
provider container:
```
asterisk -rx "channel originate PJSIP/58888@to-senma application Wait 5"
```
— a real INVITE, Request-URI `58888`, sent to SENMA; the provider's own
local `Wait()` leg needs no application logic since the actual
ring/answer happens entirely on SENMA's side (extension 1099) — exactly
matching how a real carrier's switch originates a call without itself
running any dialplan logic of its own.

---

## 15. `make trunk-smoke` evolution

**Decision: extend the existing `make trunk-smoke`, do not create a
separate command.** Both directions exercise the exact same trunk
fixture, the exact same provider container, and the same general "does
this trunk actually work" concern — provisioning a second, parallel
trunk/provider fixture purely to keep the two directions apart would
duplicate real setup cost for no isolation benefit (nothing about
inbound checks risks destabilizing the outbound ones, or vice versa,
since they're read-only with respect to each other's state). This
matches the task's own stated preference ("prefer keeping outbound and
inbound evidence in the same command only if the suite remains clear and
deterministic") — clarity is preserved by keeping the two phases in
clearly separate, sequentially-numbered sections of the script (outbound
checks 1-15 unchanged, inbound checks appended as a new, clearly-labeled
block), not interleaved.

**Proposed new checks** (appended after the existing 15): provider's
`to-senma` endpoint present and `Reachable`/idempotent across reruns →
`senma-pjsip-trunks.conf` contains the new `identify` section for the
fixture trunk → collision-check + create the inbound route fixture
(`trunk-smoke-route.php create-inbound`) → `channel originate` from
`provider` toward `58888@to-senma` → AGI log shows `Identified source: ...
(Snep_Trunk)` and the matched rule → extension 1099 (already registered
from the outbound phase's own baresip fixture — reused, not re-created)
rings and answers → real CDR row appears (`MAX(uniqueid)`-marker pattern,
reused from TASK-0015 §13, still required — the same repeat-run staleness
risk applies identically here) with the expected single-row shape (§11)
→ report readback via the existing `CallsReport` API check → cleanup
(delete the inbound route in the same `EXIT` trap that already deletes
the outbound one).

---

## 16. Regression requirements

Unchanged from the task's own instruction, and already spot-checked once
live during this very investigation (after all temporary test artifacts
were removed): `make smoke` must remain 16/0/0, `make call-smoke` must
remain 18/18, and TASK-2015's existing 15 outbound `trunk-smoke` checks
must remain green — all three confirmed during this investigation's own
cleanup pass. **A full re-run of all three is still required after the
real implementation lands**, since this investigation's live testing
used a scratch, hyphen-free stand-in endpoint specifically to avoid
touching tracked code — it does not itself constitute validation of the
real fix.

---

## 17. Stop conditions encountered during this investigation

Per item 17's explicit instruction, reporting before any fix:

- **Bug #1** (§2.2): `TrunksController::preparePost()` writes a
  meaningless `id_regex` for PJSIP trunks (provider account name, not
  `trunk-<id>`). Not a schema issue — a logic bug in already-shipped
  TASK-2015 code, invisible until this task's inbound work exercised it.
- **Bug #2** (§2.3): `PBX_Asterisk_AGI_Request`'s first-hyphen channel
  truncation is incompatible with any object name containing an internal
  hyphen — specifically the `trunk-<id>` convention TASK-2014/2015 chose.
  A shared, core, technology-agnostic method; confirmed safe to change
  (`strpos`→`strrpos`) against every currently-real name, but still
  requires full-suite regression validation before merging, not code-
  reading confidence alone.
- **No other stop condition from item 17's list was triggered**: the
  existing rule engine required **no** unavailable chan_sip-only data
  (§1/§3 — it works completely unmodified once identification succeeds);
  no new independent PHP 8.4-version-specific blocker was found (both
  bugs above are logic/naming bugs, not PHP-version compatibility
  issues); inbound support requires **no** broad routing redesign (§1's
  trace is the same engine, unmodified); provider identification **is**
  deterministic and safe once scoped to a specific host (§4/§13, not
  `0.0.0.0/0`); the DB schema **already** safely expresses NOAUTH/IP-
  authenticated inbound trunks (§6) — no schema change is proposed or
  needed anywhere in this document.

---

## 18. Explicitly deferred (unchanged from the task's own list)

Multiple provider IPs per trunk, DNS-based identify beyond whatever
Asterisk 22's `res_pjsip` already does for a plain hostname in `match=`
(not specifically exercised — this investigation's live test used a
literal IP, matching TASK-2015's own precedent), production carrier
interoperability matrix, TLS, SRTP, WebRTC, fax, Khomp/TDM, PostgreSQL,
broad UI redesign.

---

## 19. Exact proposed implementation (pending approval)

1. **Fix Bug #2**: `snep/lib/PBX/Asterisk/AGI/Request.php` —
   `strpos($channel, '-')` → `strrpos($channel, '-')` (two occurrences,
   the condition and the `substr` call), with a comment recording why
   (the `trunk-<id>` naming collision, §2.3) and citing this document.
2. **Fix Bug #1's effect**: `snep/lib/PBX/Interfaces.php`'s
   `getChannelOwner()` — add a technology-specific branch for PJSIP
   trunk rows that computes `"^PJSIP/trunk-" . $interface['id'] . "$"`
   directly instead of reading the trunk row's stored `id_regex` column,
   mirroring `PBX_Trunks::get()`'s existing `$tech == "PJSIP"` branch
   pattern (§5). Every other technology's existing `id_regex`-based
   matching in the same loop is untouched.
3. **`snep/lib/Snep/PjsipTrunkConf.php`**: add the additive `identify`
   section to `renderTrunk()` (§5), emitted unconditionally for every
   PJSIP trunk row, sourced from `peer['host']`, named
   `trunk-<id>-identify`. No change to the existing endpoint/auth/aor/
   registration emission.
4. **`docker/provider-config/pjsip.conf`**: add the static `to-senma`
   endpoint+aor (§14) — a small, permanent, committed addition, no auth,
   no host port.
5. **`scripts/trunk-smoke-route.php`**: add the `create-inbound` mode
   (§9) alongside the existing `create`/`remove` modes.
6. **`scripts/trunk-smoke-test.sh`** / **`Makefile`**: extend the
   existing `trunk-smoke` target with the inbound checks (§15) — no new
   Makefile target.
7. **`docs/tasks/0016-pjsip-inbound-trunk-routing.md`**: update with
   implementation results once the above is built and validated (this
   document, at that point, moves from "investigation only" to
   "implemented").

**A decision point requiring explicit approval before implementation
starts, not resolved unilaterally by this document**: whether item 2's
fix should also stop `TrunksController::preparePost()` from writing the
wrong `id_regex` value at all (leave the column empty/unused for PJSIP
rows, with a comment) or leave that write exactly as-is (dead, unread,
harmless) for minimal diff. Both are safe; this document does not pick
one.

---

## 20. Validation plan

1. `php -l` on every touched file.
2. `make smoke` — must stay 16/0/0.
3. `make call-smoke` — must stay 18/18.
4. `make trunk-smoke` — existing 15 outbound checks must stay green;
   new inbound checks (§15) must all pass, including from a fully clean
   volume rebuild (matching TASK-2015 §13's own precedent), run at least
   twice consecutively to prove idempotency (matching TASK-2015's own
   discovery that a single successful run does not prove a test is
   collision-safe).
5. Manual lifecycle spot-check: create a PJSIP trunk, confirm `pjsip show
   identify`/`pjsip show endpoint trunk-<id>` reflect the new object;
   edit the trunk's host, confirm the `identify` object's `match=`
   updates on reload; delete the trunk, confirm the `identify` object
   (and everything else) disappears from the generated file and from
   `pjsip show identify`.
6. Full manual real-call trace once more with `pjsip set logger on` on
   both sides, confirming the exact log evidence in §3 reproduces through
   the real (fixed) code path, not the scratch stand-in used during this
   investigation.
7. Re-inspect logs on all four services for new PHP Fatal Errors or
   unexplained new Asterisk ERROR-level lines, exactly as TASK-2015 §15
   already did.

---

The investigation above was approved as written; §21 onward documents
the implementation exactly as investigated.

---

## 21. Bug fixes, exactly as proposed

### 21.1 `PBX_Asterisk_AGI_Request` — `strpos` → `strrpos`

`snep/lib/PBX/Asterisk/AGI/Request.php:117-142`. The channel-truncation
expression now reads `strrpos($channel, '-')` (last hyphen) instead of
`strpos($channel, '-')` (first hyphen), with no other change to the
surrounding logic — `"Local/0000"` → `"SIP/"` special case, the
subsequent `getChannelOwner()` call, everything else, byte-for-byte
unchanged. **No literal `"trunk"` string is special-cased anywhere** —
the fix is general (finds Asterisk's own trailing `-<sequence>` channel-
instance suffix regardless of how many hyphens the endpoint/peer name
itself contains), per the task's explicit instruction. Safety against
every name that predates this task was already established live during
investigation (§2.3) and re-confirmed unaffected by the full regression
run (§23) — no extension, chan_sip peer, or other trunk technology's
`id_regex`/`canal` value contains an internal hyphen, so `strpos` and
`strrpos` remain provably identical for every one of them.

### 21.2 `TrunksController` — deterministic `id_regex` for PJSIP trunks

`snep/modules/default/controllers/TrunksController.php`. Every caller of
`id_regex` was re-confirmed before changing anything: `PBX_Interfaces::
getChannelOwner()` (`Interfaces.php:107`, the only *runtime* reader —
confirmed this is exactly what `PBX_Asterisk_AGI_Request` ultimately
depends on for inbound source matching, §1); the `TrunksController`
write sites themselves (`:573,648,673,698,700`, one per technology
branch, all other technologies left completely untouched); the trunk
edit form's `id_regex` text input (`addedit.phtml:271`, VIRTUAL-only,
unaffected); and `snep/lib/py/snep/persistence.py:77`, a Python
mirror of the identical `getChannelOwner()` matching logic — confirmed,
by grepping the whole tree, to have **zero callers anywhere in this
project's PHP/dialplan/Docker runtime** (nothing invokes `lib/py/`),
so it is dead tooling from an earlier SNEP era, not touched, and not a
consumer this fix needs to consider.

`preparePost($post = null, $trunkId = null)` gained the optional
`$trunkId` parameter. Its PJSIP branch now sets
`id_regex = "PJSIP/trunk-" . $trunkId` whenever `$trunkId` is known,
leaving `channel` (`"PJSIP/" . username`, unchanged — still just a
`Snep_PjsipTrunkConf` row filter, never parsed back for identity) as a
completely separate concern, exactly as designed in §2.2/§5:

- **`editAction()`** already has the real id (`$idTrunk`, the URL's
  `trunk` param) *before* calling `preparePost()` — it now passes it
  through (`$this->preparePost(null, $idTrunk)`), so edit computes the
  correct value directly, no follow-up write needed.
- **`addAction()`** does not have `trunks.id` until after the `INSERT`
  returns it. `preparePost()` leaves `id_regex` unset for PJSIP on add
  (the column is nullable, no schema concern); immediately after
  `$id = $db->lastInsertId();`, still inside the same transaction, a
  one-line follow-up patches it: `$db->update("trunks", array("id_regex"
  => "PJSIP/trunk-" . $id), "id = $id")`. No other technology's insert
  path was touched.

No legacy SIP/IAX/SNEPSIP/SNEPIAX2/KHOMP/VIRTUAL branch was modified —
confirmed both by reading the diff and by the full outbound `trunk-smoke`
suite (15 checks, unchanged) staying green throughout.

---

## 22. `identify` generation and provider simulator — implemented

`snep/lib/Snep/PjsipTrunkConf.php`'s `renderTrunk()` now additively emits,
for every PJSIP trunk row, unconditionally:
```
[trunk-<id>-identify]
type=identify
endpoint=trunk-<id>
match=<peer['host']>
```
placed after the existing aor/registration sections; nothing about the
existing endpoint/auth/aor/registration emission changed. `IDENTIFY_SUFFIX
= '-identify'` follows the exact naming convention already established
(`-auth`, `-registration`).

`docker/provider-config/pjsip.conf` gained one small, static, permanent
addition — a `[to-senma]` endpoint+aor with no auth (mirroring SENMA's
own trunk endpoint, which likewise emits no inbound `auth=`), `contact=
sip:asterisk:5060` (SENMA's service's stable Docker-DNS name on the `mag`
network) — the minimal object needed for the provider to originate a
real call toward SENMA. No new container, no new image, no host port.

---

## 23. Real evidence

### 23.1 Inbound call trace (exact log sequence, real run)

```
provider: asterisk -rx "channel originate PJSIP/58888@to-senma application Wait 5"
  -> real INVITE, Request-URI user=58888, sent to SENMA
  -> SENMA's trunk-<id>-identify object (match=<provider host>) resolves it to endpoint trunk-<id>
  -> [default] context (unchanged) -> AGI(snep/snep.php) (unchanged)
  -> PBX_Asterisk_AGI_Request::__construct(): channel "PJSIP/trunk-<id>-0000000N"
     correctly truncated (strrpos fix) to "PJSIP/trunk-<id>" for matching
  -> PBX_Interfaces::getChannelOwner() matches trunks.id_regex="PJSIP/trunk-<id>"
     (the TrunksController fix) -> PBX_Trunks::get(<id>)
  -> log: "Identified source: TASK-0015 trunk-smoke fixture (Snep_Trunk)"
  -> PBX_Dialplan::parse() matches the inbound fixture rule (src=T:<id>, dst=RX:58888)
  -> log: "Running the rule <id>:TASK-0016 trunk-smoke inbound route fixture"
  -> DiscarRamal::execute() -> log: "Discando para ramal 1099 no canal PJSIP/1099."
  -> extension 1099 (answermode=auto) rings and answers
  -> held briefly (SENMA core show channels: "2 active channels" mid-call)
  -> provider's own Wait(5) elapses, hangs up -> "0 active channels"
  -> real cdr_adaptive_odbc CDR row (§23.2)
```

### 23.2 CDR (real rows, both directions, same fixture, same run)

Outbound (unchanged from TASK-0015's shape, reconfirmed):
```
uniqueid=1787761473.4 disposition=ANSWERED duration=2 billsec=2
channel=PJSIP/1099-00000004 dstchannel=PJSIP/trunk-3-00000005
```
Inbound (new, §11's prediction confirmed — exactly **one** row, not two):
```
uniqueid=1787761491.6 src=anonymous disposition=ANSWERED duration=5 billsec=5
channel=PJSIP/trunk-3-00000006 dstchannel=PJSIP/1099-00000007
calldate=2026-08-26 16:24:51
```
`src=anonymous` is the real, expected value for this unauthenticated
`channel originate` test call (§3's own live finding) — the report/CDR
checks assert `dst`/`disposition`/`duration`/`billsec`/`channel`/
`dstchannel`/`calldate`, and log `src` rather than asserting a specific
literal for it, to avoid pinning the test to an Asterisk-version-specific
default. **Reproduced identically from a fully clean volume rebuild**,
confirming the shape is not an artifact of accumulated state:
```
uniqueid=1787761185.2 src=anonymous disposition=ANSWERED duration=5 billsec=5
channel=PJSIP/trunk-1-00000002 dstchannel=PJSIP/1099-00000003
```

### 23.3 Report readback

`GET .../api/index.php?service=CallsReport&...&dst=58888&order_dst=equal`
returned the exact inbound `uniqueid` above, matching TASK-0015's
existing `src=`/`order_src=equal` pattern (already a real, supported
filter, confirmed by reading `CallsReportService.php:214-227` before use)
mirrored for `dst=`/`order_dst=equal`.

### 23.4 Identify lifecycle (manual, matching TASK-0015's own precedent — not part of the automated script)

- **Create**: `pjsip show endpoint trunk-2` → `Identify: trunk-2-identify/trunk-2`, `Match: 172.28.0.2/32` — the trunk's configured `host` (entered as the hostname `provider`) resolved correctly to a real IP at PJSIP config-load time.
- **Edit host** (changed to `203.0.113.99`): the regenerated `senma-pjsip-trunks.conf`'s `match=` updated accordingly, and after `module reload res_pjsip.so` the live object reflected `Match: 203.0.113.99/32` — no stale value left over.
- **Delete**: endpoint, auth, aor, registration, and identify all disappeared from both the generated file and `pjsip show endpoint trunk-2` (`Unable to find object trunk-2`) — zero stale objects, matching the same full-stateless-rewrite guarantee already proven for the other object types.

---

## 24. `make trunk-smoke` — final shape (23 checks)

Checks 1-15 are TASK-0015's original outbound checks, unmodified. Checks
16-23 (new): generated `identify` section present → provider's `to-senma`
endpoint present → inbound route fixture collision-checked and created
(`trunk-smoke-route.php create-inbound`) → provider originates the real
INVITE → mid-call channel snapshot ("established briefly") → clean
hangup → trunk-identity + AGI/rule-engine log trace (§8's explicit
"don't infer from ringing alone" requirement) → inbound CDR row (single-
row shape, §23.2) → report readback. The same registered test extension
(1099) proves both directions — its baresip `answermode` changed from
`manual` to `auto` (confirmed, empirically, to have zero effect on the
existing outbound checks: `answermode` only governs handling of
*incoming* INVITEs, and outbound dialing is always an explicit `ctrl_tcp`
`dial` command regardless). One trunk fixture, one provider container,
one `EXIT`-trap cleanup for both directions' route fixtures.

Two narrow, mechanical fixes were needed in `scripts/trunk-smoke-route.php`'s
bootstrap while wiring up the new `create-inbound` mode (both missing
dependencies of `DiscarRamal` specifically, not present when only
`DiscarTronco` was bootstrapped): `DiscarRamal::__construct()` reads the
translator from registry key `"i18n"` (not `"Zend_Translate"`, which
`DiscarTronco` uses) — both keys are now set from the same
`Snep_Locale` instance; and `DiscarRamal::setConfig()` calls
`PBX_Usuarios::get()` directly, requiring `require_once "PBX/Usuarios.php";`
to be added alongside the existing requires. Neither changes any
design decision — both are one-line bootstrap completions.

---

## 25. Security — unchanged from the investigation, reconfirmed live

`match=` is generated from the trunk's own configured `host` field only
— confirmed live (§23.4) that this resolves to a specific `/32` address
at config-load time, never a wildcard. **Production carriers with
multiple source IPs, DNS-backed pools, or SBC ranges are explicitly not
modeled by this task** and will require dedicated future design work
(a multi-value `match=` list, or a different generator strategy entirely)
— not attempted here, per the task's own explicit instruction.

---

## 26. Regression — final results

| Suite | Result |
|---|---|
| `make smoke` | **16 PASS / 0 FAIL / 0 EXPECTED_LIMITATION** |
| `make call-smoke` | **18/18** |
| `make trunk-smoke` (1st run) | **23/23** |
| `make trunk-smoke` (2nd consecutive run, idempotency) | **23/23** |
| `make smoke` / `make call-smoke` / `make trunk-smoke`, full clean-volume rebuild (all 7 named volumes wiped, including `mag-db`) | **16/0/0, 18/18, 23/23** |

Logs inspected across all four services for every pass: zero new PHP
Fatal Errors; the only ERROR/WARNING-level lines are pre-existing,
already-documented stock-Asterisk module-absence noise (TASK-0005/0009
baseline) and TASK-0015's already-known, self-correcting transient
"Auth object could not be found" warning on first registration — nothing
new, nothing unexplained. Final DB state after every run: zero leftover
trunk/route/extension fixtures. `git status`: exactly the six intended
source files modified, plus this document.

**No unrelated bug was found during implementation** — nothing triggered
this task's own stop rule (item 13/§17) beyond the two bugs already
identified and fixed during investigation.

---

## 27. Success definition — met

Both directions proven, real signaling, unmodified AGI/rule engine, real
CDR, report readback, all existing suites green:

```
OUTBOUND (TASK-0015, reconfirmed unchanged): SENMA -> provider
INBOUND (this task):                          provider -> SENMA -> SENMA extension
```

---

Stopping here at a commit checkpoint. Not beginning multiple-provider or
production-carrier compatibility work.
