# TASK-0015 — First real outbound PJSIP trunk

## Status

**Implemented and validated.** `make smoke`: 16/0/0. `make call-smoke`:
18/18. `make trunk-smoke` (new): 15/15, run repeatedly (idempotent,
collision-safe) and from a **fully clean rebuild** (all volumes wiped —
`asterisk-etc`, `mag-asterisk-var`, `mag-provider-etc`,
`mag-provider-var`, and `mag-db` itself). A real outbound INVITE was
placed by SENMA's own generated PJSIP trunk, received and answered by a
local provider simulator, bridged, hung up cleanly, and produced a real
`cdr_adaptive_odbc` CDR row that SENMA's own report API reads back.
Outbound only — inbound trunk identification/routing is explicitly
deferred to TASK-0016, per TASK-0014's own recommendation. Not
committed — stopping at the commit checkpoint.

## Goal

Prove the first real outbound trunk call provisioned by SENMA itself,
per TASK-0014's architecture and TASK-0015A's restored trunk CRUD:

```
SENMA UI -> create PJSIP trunk -> persist existing trunk model
-> generate native PJSIP trunk objects -> reload Asterisk
-> route an outbound call through the existing SENMA AGI/rule engine
-> local provider simulator receives and answers
-> real CDR written by cdr_adaptive_odbc -> SENMA report reads it back
```

---

## 1. Selected first trunk model

**REGISTER-based provider** (`dialmethod=NORMAL`, `reverse_auth=1`) —
exactly the model TASK-0014 §17/§20 recommended: the simplest model that
still proves both a real external SIP dialog *and* the one genuinely new
PJSIP object type (`registration`) this milestone needed to prove. Not
chosen because it's the only option evidenced (§4 below) — chosen
because it exercises the most of TASK-0015's own required checklist
(status/registration state, reload-affects-a-live-registration,
outbound-auth) in one milestone, while staying within "prefer the
simplest model" per the task's own instruction. Static-peer (no
registration) and NOAUTH models are not implemented in this milestone —
NOAUTH specifically requires a real `identify` object with no chan_sip
analog (TASK-0014 §7), deliberately out of this outbound-only scope.

---

## 2. Provider simulator architecture

A second, independent Asterisk 22/PJSIP instance (`provider` service,
`compose.yaml`), **reusing the same `docker/asterisk.Dockerfile` image**
already built and proven for SENMA's own `asterisk` service (TASK-0009)
— not a new image, not a new build. Only the entrypoint/config differ:

- `docker/provider-entrypoint.sh` (new) — a deliberately small,
  independent first-boot script. Does **not** reuse
  `docker/asterisk-entrypoint.sh`: that script templates AMI/ODBC
  credentials, deploys the SENMA dialplan, and sets up the
  `/etc/asterisk/snep` writable subtree — none of which this simulator
  needs (it never runs SENMA's PHP/AGI/ODBC stack at all). Copies
  `docker/provider-config/*.conf` into `/etc/asterisk` on first boot
  (empty-volume-guarded, same idiom as the SENMA entrypoint), templates
  `TRUNK_TEST_USERNAME`/`TRUNK_TEST_SECRET` into `pjsip.conf`.
- `docker/provider-config/` (new): `asterisk.conf` (minimal
  `[directories]`, no astagidir/ODBC concerns), `logger.conf` (same
  minimal shape as SENMA's), `modules.conf` (PJSIP autoloads; hardware
  technologies and the entire ODBC/CDR family explicitly `noload`ed —
  this simulator never touches a database), `extensions.conf` (one
  context, one extension: `600` → `Answer()` → `Wait(2)` → `Hangup()` —
  no AGI, no application logic, purely enough to prove real two-way SIP
  signaling), `pjsip.conf` (below).
- Own named volumes (`mag-provider-etc`, `mag-provider-var`), own
  network identity (`provider`, resolved via Docker's embedded DNS on
  the existing `mag` network — no new network needed), **no host port
  published** (only the `asterisk` service ever needs to reach it).

### Why reuse the image instead of a new Dockerfile

A real ITSP genuinely *is* another SIP-speaking PBX with its own
dialplan that must answer and route calls — the right stand-in is
another Asterisk instance, not a bare softphone (TASK-0009's baresip
pattern is the right shape for an *extension*, the wrong shape for a
*trunk's remote party*). Reusing the already-built, already-proven
PJSIP-capable image is also strictly cheaper: no new build, no new
signaling stack, no new runtime dependency.

### `pjsip.conf` — the account and the `identify` object found necessary live

```
[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:5060

[senma-outbound]
type=endpoint
context=from-senma
disallow=all
allow=ulaw,alaw
auth=senma-outbound
aors=senma-outbound

[senma-outbound]
type=auth
auth_type=userpass
username=senma-outbound
password=<TRUNK_TEST_SECRET>

[senma-outbound]
type=aor
max_contacts=1
remove_existing=yes

[senma-outbound]
type=identify
endpoint=senma-outbound
match=172.28.0.0/16
```

The account name (`senma-outbound`) is deliberately independent of
SENMA's own internal `trunk-<id>` object naming (§5) — exactly as in
real life, where a carrier assigns its own account identifier unrelated
to how the PBX names its own local trunk objects.

**The `identify` object was not in the original design — it was found
missing during the very first live call attempt.** `identify_by=
username,ip` (the endpoint's own default) does **not** match a
dynamically-registered contact's IP — that "ip" method only matches a
statically-configured `identify` object's own `match=` list, unrelated
to the registrar. Without one, SENMA's *outbound-initiated* INVITE
(dialing a number, not registering) could not be identified as coming
from `senma-outbound` at all: the Request-URI carries the dialed number,
not the account name, and there is no Authorization header yet on the
first, unauthenticated attempt. Asterisk correctly fell through to "No
matching endpoint found" and issued a decoy/anti-scan 401 that no real
credentials could ever satisfy (a legitimate Asterisk security feature
— reproduced live as a genuine INVITE → 401 → retry-with-auth → 401
loop ending in `PJSIP_EFAILEDCREDENTIAL`, confirmed via `pjsip set
logger on` packet capture on both sides, credentials confirmed
byte-identical on both sides via `od -c` before looking further). Adding
this `identify` object is exactly what a real ITSP's own platform
configuration provides for any registered customer — it belongs
entirely to this static provider-simulator config, standing in for what
a real carrier's platform does, not to SENMA's own generator or inbound
handling (TASK-0016's actual subject). `172.28.0.0/16` is the `mag`
network's own pinned subnet (`compose.yaml`, TASK-0005) — the same value
already used for the AMI ACL, not a new credential or a guess.

---

## 3. Generator architecture — `Snep_PjsipTrunkConf`

Implemented exactly as TASK-0014 §9/§22 recommended: a **dedicated
sibling of `Snep_PjsipConf`**, not a branch inside it, not a merge.
`snep/lib/Snep/PjsipTrunkConf.php` (new):

- Own SQL fetch (`peers WHERE peer_type='T' AND canal LIKE 'PJSIP/%'`,
  joined to `trunks` by `name` for `id`/`reverse_auth` — the same
  peers-then-trunks-join shape `Snep_InterfaceConf`'s own trunk branch
  already uses).
- Own per-row-to-N-object emission (`renderTrunk()`): endpoint + auth +
  aor always; a `registration` object only when `trunks.reverse_auth` is
  set. **No `identify` object is generated by this class** — inbound
  identification of a provider calling *into* SENMA is TASK-0016's
  subject, not this one's, exactly per TASK-0014's scope boundary.
- Own reload (`module reload res_pjsip.so`, success-text-checked,
  throwing `PBX_Exception_IO` on failure — identical mechanism and
  failure-surfacing discipline to `Snep_PjsipConf::reload()`, reused
  verbatim rather than reimplemented).
- Same full-stateless-rewrite property as `Snep_PjsipConf`/
  `Snep_InterfaceConf`: every call reflects exactly the current DB
  state, so create/edit/delete/enable all "just work" with no
  incremental diff/cleanup logic.

Called from `TrunksController` only (`addAction()`, `editAction()`,
`removeAction()`, `enableAction()` — all four existing
`Snep_InterfaceConf::loadConfFromDb()` call sites), alongside the
completely untouched `Snep_InterfaceConf` call, mirroring exactly how
`Snep_PjsipConf` is called from `ExtensionsController` alongside
`Snep_InterfaceConf`. **Extension provisioning
(`Snep_PjsipConf`/`ExtensionsController`) was not touched anywhere.**

---

## 4. Object identity/naming

```
endpoint:      trunk-<trunks.id>                e.g. trunk-1
aor:           trunk-<trunks.id>                e.g. trunk-1     (MUST equal endpoint name)
auth:          trunk-<trunks.id>-auth
registration:  trunk-<trunks.id>-registration   (only when reverse_auth)
```

Exactly TASK-0014 §10's recommendation: `trunks.id` (the real,
auto-increment, never-reused primary key), not `trunks.name` (a
same-shaped but independently-computed sequential string); the `trunk-`
namespace prefix (unlike extensions' bare-number convention) guarantees
no collision with any extension endpoint name, since a trunk is never
dialed *by* its own name the way an extension is.

**A real chicken-and-egg problem, resolved without restructuring the
insert order**: `trunks.id` is an auto-increment value not yet known
when `TrunksController::preparePost()` builds `peers.canal` — but the
generator never parses the endpoint name back out of `canal`. `canal`
only needs to start with `"PJSIP/"` for `Snep_PjsipTrunkConf`'s own SQL
filter to find the row; the real, authoritative object names are
computed independently from the joined `trunks.id` at generation time
(and, identically, at call time by `PBX_Trunks::get()`, §6). This let
`preparePost()`'s new PJSIP branch stay exactly as simple as its
sibling SIP/IAX2 branch (`channel = "PJSIP/" . $trunk_data['username']`)
with zero insert-order changes to `addAction()`.

---

## 5. Field mapping (generated config)

| `peers`/`trunks` field | Generated PJSIP property | Notes |
|---|---|---|
| `peer['context']` | endpoint `context=` | Unchanged from chan_sip mapping |
| `peer['allow']` (`;`-joined) | endpoint `allow=` (`,`-joined) | Identical transform to `Snep_PjsipConf` (TASK-0014 §13 confirmed no trunk-specific difference) |
| `peer['dtmfmode']` | endpoint `dtmf_mode=` | Same `rfc2833`→`rfc4733` map as extensions |
| `peer['callerid']` | endpoint `callerid=` | Verbatim, only if set |
| `peer['fromuser']`/`fromdomain'` | endpoint `from_user=`/`from_domain=` | Direct rename, only if set — TASK-0014 §3's evidenced mapping |
| `peer['nat']` tokens | endpoint `force_rport=`/`rtp_symmetric=` | Same two evidence-backed tokens as extensions |
| — | endpoint `outbound_auth=trunk-<id>-auth` | Outbound-only milestone: authenticates requests *we* send (REGISTER, and any challenged INVITE). `auth=` (authenticating requests the *provider* sends *us*) deliberately not generated — an inbound concern, TASK-0016 |
| `peer['defaultuser']` | auth `username=` | The provider-assigned account identity (`trunks.username`), distinct from the endpoint's own `trunk-<id>` name |
| `peer['secret']` | auth `password=` | Plaintext, same `auth_type=userpass` fit as extensions (TASK-0010/0014 §15 — no schema change, no redesign) |
| `peer['host']`, `peer['port']` (default 5060 if empty) | aor `contact=sip:<host>:<port>` | **Evidence-based choice, not TASK-0014's exact phrasing**: TASK-0014 §4 described the register-based case's AOR as "empty/dynamic, registrar-populated" — live testing showed this is imprecise for the *outbound* direction (there is no local registrar populating our own outbound-dial AOR; that mechanism is for accepting *inbound* registrations, as extensions do). A static `contact=` pointing at the provider's known host:port is what actually makes outbound dialing resolve a destination — standard, correct practice for a provider trunk with a known host, register-required or not. |
| `trunk['reverse_auth']` | presence of a `registration` object | TASK-0014 §5's precise reading confirmed: "make Asterisk register outbound to this provider," not an inbound-registration concept |
| `peer['defaultuser']`, `peer['host']`, `peer['port']` | registration `client_uri=sip:<user>@<host>:<port>`, `server_uri=sip:<host>:<port>` | Direct construction, `outbound_auth=trunk-<id>-auth` shared with the endpoint |

`dialmethod` is stored but **not specially interpreted** by this
generator — only `reverse_auth` controls registration emission. A
NOAUTH-style PJSIP trunk (no auth, IP-matched) has no distinct effect in
this milestone; it requires the real `identify`-object work TASK-0016
owns.

---

## 6. Runtime interface

**`PBX_Trunks::get()`** (`snep/lib/PBX/Trunks.php`) gained one new
branch, mirroring its existing SIP/IAX2 branches exactly:
```php
} else if ($tech == "PJSIP") {
    $config = array(
        "username" => "trunk-" . $rawTrunk->id,   // SENMA's own endpoint name, not the auth username
        "secret" => $rawTrunk->secret,
        "host" => $rawTrunk->host
    );
    $interface = new PBX_Asterisk_Interface_PJSIP($config);
}
```

**A genuinely new, dedicated runtime behavior was required** — TASK-0014
§7/§11 explicitly anticipated this as an open question, resolved here
with live evidence: `DiscarTronco::execute()`'s existing dial-string
construction (`$tronco->getInterface()->getCanal() . "/" . $dst_number .
$postfix`) reproduces chan_sip's "Peer/exten" syntax
(`SIP/<name>/<exten>`). chan_pjsip has **no equivalent** — its syntax is
`PJSIP/<exten>@<endpoint>` (destination *first*), and a second
`/`-delimited segment after a PJSIP endpoint name is parsed as an **AOR
selector**, not a destination number. Reusing the existing concatenation
for PJSIP would have silently misdialed (confirmed this is exactly what
was happening before the fix — the call never even reached a real dial
attempt).

**Fix**: a new `getDialStringForDestination($destination, $postfix)`
method on the base `PBX_Asterisk_Interface` class, whose **default
implementation reproduces the exact old expression byte-for-byte**:
```php
public function getDialStringForDestination($destination, $postfix = "") {
    return $this->getCanal() . "/" . $destination . $postfix;
}
```
Every existing interface (SIP, SIP/NoAuth, IAX2, IAX2/NoAuth, KHOMP,
VIRTUAL) inherits this unchanged — **zero behavior change for any
non-PJSIP trunk**, confirmed by `make call-smoke` staying 18/18
throughout (chan_sip/IAX2/KHOMP/VIRTUAL trunk dialing was never touched
or re-derived, only extracted into an overridable method).
`PBX_Asterisk_Interface_PJSIP` overrides it:
```php
public function getDialStringForDestination($destination, $postfix = "") {
    return $this->getTech() . "/" . $destination . "@" . $this->config['username'];
}
```
`DiscarTronco.php`'s only change: `$destiny = $tronco->getInterface()->
getCanal() . "/" . $dst_number . $postfix;` → `$destiny = $tronco->
getInterface()->getDialStringForDestination($dst_number, $postfix);` —
one line, no other logic touched. The already-working extension runtime
path (`PBX_Usuarios::get()`, `DiscarRamal`, `PBX_Asterisk_Interface_PJSIP
::getCanal()`) was not touched at all — extensions never call
`getDialStringForDestination()`.

---

## 7. UI/model integration

Minimum change to `snep/modules/default/views/scripts/trunks/
addedit.phtml`, per TASK-0014 §3/§12's precedent for extensions:

- One new `<option value="pjsip">` in the existing technology dropdown.
- `showDiv()` extended to route `pjsip` into the same `#ip` field group
  SIP/IAX2 already show (host, username, secret, qualify, dialmethod,
  nat, reverse_auth, domain, codecs) — reusing existing fields, no new
  ones.
- **Three fields explicitly hidden for `technology=pjsip`**, per the
  task's instruction not to expose ambiguous chan_sip fields without an
  established mapping: "Type" (peer/user/friend — TASK-0014 §3 found no
  PJSIP equivalent), "Insecure" (§3: "not a flag translation, no direct
  equivalent"), "Channel Limit" (§3: "no direct config-level
  equivalent"). Implemented via three added `id` attributes on their
  existing `.form-group` wrappers and three lines in `showDiv()` — the
  smallest change that avoids silently collecting data the generator
  would just ignore.

`TrunksController::preparePost()` gained one new technology branch
(alongside the existing SIP/IAX2/SNEPSIP/SNEPIAX2/KHOMP ones), and
`"pjsip"` was added to the existing `$ip_trunks` array so a PJSIP trunk
gets a `peers` row exactly like every other IP-technology trunk — no new
persistence concept.

---

## 8. Persistence — no schema change

Confirmed unnecessary, exactly as TASK-0014 §5/§14 concluded: every
field this milestone needed (`host`, `port`, `username`→`defaultuser`,
`secret`, `reverse_auth`, `dialmethod`, `allow`, `nat`, `dtmfmode`,
`callerid`, `fromuser`, `fromdomain`) already exists on `trunks`/`peers`.
The existing `trunks.id` primary key is what makes the naming scheme
(§4) safe. No `STOP and report before altering schema` situation arose
— nothing was found that couldn't be represented safely with the
existing columns.

---

## 9. Configuration ownership

Extends TASK-0014 §11's diagram with exactly one new include, nothing
else changed:
```
/etc/asterisk/pjsip.conf                          <- static, project-owned (unchanged)
    #include pjsip_transports.conf                 <- static (unchanged)
    #include snep/senma-pjsip.conf                  <- Snep_PjsipConf, extensions (UNCHANGED)
    #include snep/senma-pjsip-trunks.conf            <- NEW: Snep_PjsipTrunkConf, trunks
```
Same writable `/etc/asterisk/snep/` subtree (`senma-config` group, GID
3000, setgid `2775`) TASK-0009 already built — **zero new
filesystem/permission work**. `docker/asterisk-entrypoint.sh` gained one
new `touch`+`chmod 664` block for `senma-pjsip-trunks.conf`, identical
in shape to the existing `senma-pjsip.conf` block. Verified via a full
clean-volume rebuild (§13) that the file is correctly pre-created with
the right permissions on first boot, not just live-patched.

---

## 10. Reload/status behavior

`module reload res_pjsip.so` — same command, same whole-tree reload
already proven for extensions (TASK-0010 §10). **This milestone
empirically answers TASK-0014 §12's open question**: yes, reloading
*does* pick up changes to an existing outbound `registration` object
(tested live: edited a trunk's port from 5060 to a non-existent 5070,
observed the live registration object's `server_uri` update and
immediately re-attempt, correctly reporting `Unregistered`; reverted to
5060, observed it reach `Registered` again within seconds) — not merely
assumed.

**A real, reproducible, self-correcting transient warning was found**:
on every single trunk creation (confirmed across 5+ separate creations),
the very first outbound REGISTER attempt immediately following the
reload that just created *both* the auth and registration objects in
the same pass logs:
```
WARNING res_pjsip/pjsip_configuration.c: Auth object 'trunk-N-auth' could not be found
WARNING res_pjsip_outbound_registration.c: Failed to create authenticated REGISTER request...
```
This self-corrects on Asterisk's own automatic retry within a few
seconds (confirmed: every single `trunk-smoke` run's registration
still reaches `Registered` well within its 15-second poll window,
15/15 across many consecutive runs). This reads as Asterisk's own
sorcery/config-loading not having fully settled all objects from one
reload batch before the registration client's first attempt fires — an
Asterisk-internal behavior, not a SENMA code defect, and not something
this task's own generated config ordering can influence (the auth
section is already emitted textually before the registration section in
`Snep_PjsipTrunkConf`'s own output). Recorded here as an honest,
transparent finding per this project's own documentation standard, not
silently smoothed over — `trunk-smoke`'s retry-based wait loop already
tolerates it correctly without having been designed around this specific
quirk in advance.

**Status**: `pjsip show registrations outbound` (the direct PJSIP
equivalent to `pjsip show endpoint`/`pjsip show aor` already used for
extensions) is the minimum status surface this model needs — no new PHP
UI/status code was built (TASK-0014 §12 explicitly scoped a broader
trunk-status UI rewrite out of this milestone); `trunk-smoke` uses the
CLI command directly, matching how `call-smoke-test.sh` already checks
`pjsip show endpoint`.

---

## 11. Outbound runtime trace (real evidence)

```
PJSIP/1099 (test extension) dials 600
  -> [default] context, catch-all -> AGI(snep/snep.php)          [unchanged]
  -> PBX_Dialplan::parse() matches the trunk-smoke fixture rule    [unchanged engine]
  -> DiscarTronco::execute()
       - PBX_Trunks::get(1) -> PBX_Asterisk_Interface_PJSIP(username="trunk-1", ...)
       - minute-limit check (see §12, a real bug found and fixed here)
       - $destiny = getDialStringForDestination(600) = "PJSIP/600@trunk-1"
       - Dial(PJSIP/600@trunk-1, 60, TWK)
  -> chan_pjsip resolves endpoint "trunk-1" -> aor "trunk-1" -> contact sip:provider:5060
  -> real INVITE sent to the provider simulator, digest-challenged, re-sent with
     outbound_auth=trunk-1-auth credentials, accepted (once identify was added, §2)
  -> provider's [from-senma] context: NoOp -> Answer() -> Wait(2) -> Hangup()
  -> CALL_ANSWERED / CALL_REMOTE_SDP / CALL_ESTABLISHED observed on the calling
     baresip endpoint; RTP established (Strict RTP learning logged both directions)
  -> provider's own Hangup() ends the call; SENMA's DiscarTronco reads DIALSTATUS,
     throws PBX_Rule_Action_Exception_StopExecution, rule ends
  -> real cdr_adaptive_odbc CDR row (see §12)
```

Confirmed via `pjsip set logger on` packet capture and `/var/log/
asterisk/full` on both SENMA's `asterisk` and the `provider` container —
this is a real SIP dialog, not a test-only bypass.

---

## 12. Blockers found and fixed along the way

Per this task's own item 18 stop-rule, each was stopped on and reported
before being fixed; all were approved before any change was made.

### `DiscarTronco.php:272` — `count()` on `fetch()`'s `false` (trunk-specific, PHP 8)

```php
$trunk = $db->query("SELECT * FROM trunks WHERE id='$trunkId' AND time_total IS NOT NULL")->fetch();
if (count($trunk) > 1) {
```
`fetch()` returns `false` (not `count()`-able) whenever a trunk has **no
minute limit configured** — the default case for any trunk, any
technology. `count(false)` is a PHP 8 fatal `TypeError`, uncaught by
`PBX_Rule::execute()`'s `catch (Exception $ex)` (a `TypeError` is an
`Error`, not an `Exception` — a PHP 7+ hierarchy split), silently
killing the AGI script before any `Dial()` was attempted. **This is
genuinely previously-unreachable**: no trunk outbound call had ever been
exercised end-to-end in this Dockerized project before this task.
Fixed: `if ($trunk) {` (a plain existence check — the real original
intent; `count() > 1` on the found case only "worked" by counting the
row's many columns, not verifying anything meaningful).

### `PBX_Rules::register()` — PDO boolean-binding (routing engine, not a trunk file)

Building the route/rule fixture (§13) needed `PBX_Rules::register()` —
the exact same domain API `RouteController` itself uses. Found the
identical PDO-binds-`false`-as-`''` bug TASK-0015A already fixed for
trunks, here in `regras_negocio.record`:
```php
"record" => $rule->isRecording() ? 1 : 0   // was $rule->isRecording()
```
Not trunk-specific — would block creating *any* route via this API,
chan_sip or PJSIP. Reported (a different subsystem than trunks) before
fixing; approved.

### `PBX_Rule` — missing `$dates` property declaration (routing engine)

`$src`/`$dst`/`$validade` all correctly declare `= array()`; `$dates`
was never declared at all — a plain omission, not present anywhere in
the class. `addValidDates()`'s `$this->dates[] = $date` silently created
an undefined dynamic property until first appended; `getValidDatesList()`
then returned `null` (PHP 8 "Undefined property" warning) for any rule
that never called `addValidDates()` — the normal case for a rule with no
date restriction — fataling `PBX_Rules::register()`'s
`implode(',', null)`. Fixed: added `private $dates = array();`,
matching its siblings exactly. Reported and approved before fixing,
alongside the boolean fix above (found in the same investigative pass).

### `mysql_escape_string()` in `TrunksController::editAction()` (TASK-0015A, referenced for completeness)

Already fixed in TASK-0015A; not re-touched here. Confirmed still
correct (`$db->quote()`) throughout this task's editing-lifecycle
validation (§14).

---

## 13. `make trunk-smoke` design

`scripts/trunk-smoke-test.sh` (new), `scripts/trunk-smoke-route.php`
(new, a standalone CLI helper — see below), wired via `make trunk-smoke`
(depends on `up`, mirrors `make smoke`/`make call-smoke`'s structure),
kept fully separate from both.

Validates, in order: containers healthy (app/asterisk/db **and
provider**) → PJSIP modules Running on **both** asterisk instances →
collision-check trunk/extension fixtures (same create-if-absent-else-
stop-on-conflict discipline as `call-smoke-test.sh`) → provision trunk
+ extension via the real HTTP flows → generated
`senma-pjsip-trunks.conf` contains the expected sections → `pjsip show
endpoint` confirms reload → outbound registration reaches `Registered`
(15×1s poll) → collision-check + create the route fixture → build/start
a baresip test endpoint (reusing TASK-0009's existing image/templates,
no new tooling) → place the call → provider answered/established/hung
up → AGI/rule/trunk-selection trace confirmed in Asterisk's own log →
CDR correct → report readback → cleanup (HTTP delete of trunk +
extension, `PBX_Rules::delete()` for the route, via an `EXIT` trap safe
even on early abort).

### Route fixture: why a standalone PHP script, not `RouteController`'s own HTTP form

`RouteController::addAction()`'s POST contract is a dynamic, JS-driven,
multi-widget form (`actions_order` + per-action `action_<n>[...]` nested
config, assembled client-side) — reverse-engineering it reliably for a
test fixture was judged impractical (per the task's own "highest-level
stable interface *practical*" phrasing) versus using
`PBX_Rules::register()`/`PBX_Rule`/`DiscarTronco` directly — the exact
same domain objects the controller itself builds from a parsed POST, one
level above raw SQL, not a raw INSERT. `scripts/trunk-smoke-route.php`
is a small standalone CLI script (bootstraps just `Snep_Config`/
`Snep_Db`/`Zend_Registry` — not the full `Zend_Application`, which
`Snep_Db::getInstance()` doesn't require) invoked via `docker compose
exec app php -- create <trunk_id> <destination> <desc> < script.php`
(stdin, since `scripts/` isn't bind-mounted into the app container).

### Two bugs caught specifically by proving idempotency (running it twice)

- **CDR query picked a stale row from a prior run.** `src`/`dst`
  (`1099`/`600`) are identical across runs, and an unscoped `ORDER BY
  calldate ASC LIMIT 1` (see below) returned the *first ever* matching
  row, not this run's. Fixed by capturing `MAX(uniqueid)` from `cdr`
  immediately before placing the call and requiring the result to be
  strictly greater. **Not a wall-clock cutoff**: `docker compose exec
  asterisk date` and MariaDB's own `NOW()` were both tried first and
  both read several hours behind the timestamps Asterisk itself writes
  into `calldate` in this environment (confirmed: both showed `11:3x`
  while `calldate` showed `14:2x` for the same real moment — a
  container/DB timezone-handling difference not worth chasing further
  for a test-fixture marker). `uniqueid` (Asterisk's own
  `<epoch>.<sequence>` identifier) needs no timezone at all and is
  monotonically increasing call over call.
- **Route-fixture description string duplicated by coincidence.** An
  early draft hardcoded the same literal string in both the shell
  script's trunk-callerid variable and the PHP script's rule
  description, which happened to collide and made a collision-check work
  "by accident." Fixed by giving the route its own `ROUTE_DESC` and
  passing it as an explicit 4th argument to the PHP script — no more
  reliance on two independently-hardcoded strings matching.

### A real, non-obvious CDR finding

A trunk call produces **two** `cdr` rows sharing one `uniqueid` — unlike
a plain extension-to-extension call, which produces exactly one (already
relied upon by `call-smoke-test.sh`'s own `ORDER BY calldate DESC LIMIT
1`, still correct for that case since the duplicate never occurs there).
The first, written alongside the `Dial()` itself (`lastapp='Dial'`), is
fully populated (`duration=2`, `billsec=2`, real `dstchannel`); a second,
written moments later when the *calling* channel's own dialplan reaches
its explicit post-rule `Hangup()` (`lastapp='Hangup'`), is empty
(`duration=0`, `billsec=0`, blank `dstchannel`) — same `uniqueid` both
times. `trunk-smoke`'s query uses `ORDER BY calldate ASC, uniqueid ASC
LIMIT 1` (ascending, combined with the `uniqueid >` marker above) to
reliably select the meaningful row. Not investigated further — this is
an observed Asterisk CDR-engine behavior difference for this dialplan
shape, not a bug in any SENMA code path this task touched, and the
report API's own (pre-existing, unmodified) query already surfaces the
correct `duration`/`billsec` values for the same `uniqueid` regardless
(confirmed live, §14).

---

## 14. Real evidence

**SIP**: real INVITE/401/INVITE-with-auth/200-OK/ACK exchange between
SENMA's `asterisk` and `provider` containers, captured via `pjsip set
logger on` on both sides; real outbound REGISTER reaching `Registered`
on both `pjsip show registrations outbound` (SENMA) and `pjsip show
aor senma-outbound` (provider, showing a live bound contact at SENMA's
container IP).

**CDR** (the meaningful row, §13):
```
uniqueid=1787755569.0 disposition=ANSWERED duration=2 billsec=2
channel=PJSIP/1099-00000001 dstchannel=PJSIP/trunk-1-00000001
calldate=2026-08-26 14:46:09
```
`src`=test extension, `dst`=600 (the fixed test destination),
`disposition=ANSWERED`, `duration`/`billsec` > 0, `uniqueid` populated,
timestamp matches the run — all of item 14's explicit requirements, no
manual CDR insert anywhere in this task.

**Report readback**: `GET .../api/index.php?service=CallsReport&...`
(the same endpoint `call-smoke-test.sh` already validates for
extensions) returned this exact `uniqueid` with correct `duration`/
`billsec`/`disposition`.

**Lifecycle** (§10 confirms reload/registration; full round trip):
create (trunk id + peers row, generated config, live endpoint/aor/
registration, real REGISTER) → list → edit (changed `port`; regenerated
config and the *live* registration object both reflected the new value;
deliberately pointed at a wrong port to confirm `Unregistered` surfaces;
reverted and confirmed `Registered` again) → delete (generated file back
to header-only, `pjsip show endpoints`/`pjsip show registrations
outbound` show nothing left, `trunks`/`peers` tables both empty — zero
stale objects).

**Idempotency**: `make trunk-smoke` run 6+ times consecutively, 15/15
every time, plus once more from a fully clean rebuild (all volumes
wiped, including `mag-db`) with no manual patching.

---

## 15. Regression

- `make smoke`: **16/0/0**, both against the long-lived dev DB and after
  a full clean rebuild (the clean-rebuild run surfaced one unrelated,
  pre-existing, already-known behavior — a truly virgin `mag-db` volume
  triggers SNEP's own ITC "register your product" prompt on first
  dashboard load, since no prior task in this entire session had ever
  actually wiped that volume before; dismissing it once, exactly as a
  real first-run administrator would, is the correct and only action —
  not a trunk-related regression, not fixed as part of this task).
- `make call-smoke`: **18/18**, both before and after this task's
  changes — extension provisioning, internal PJSIP calls, AMI, ODBC,
  CDR/report readback all unaffected.
- `make trunk-smoke`: **15/15**, repeatedly.
- Logs inspected across all four services (app, asterisk, provider, db)
  for each validation pass: zero new PHP Fatal Errors; the only
  ERROR-level Asterisk log lines are the same pre-existing, already-
  documented "declined to load" module-absence noise (TASK-0005/0009
  baseline, present on both Asterisk instances identically); the one
  new WARNING class (§10's transient auth-lookup message) is explained,
  reproducible, and non-blocking.

---

## 16. Explicitly deferred (unchanged from the task's own list)

Inbound trunk identify/routing (TASK-0016), multiple provider IPs,
complex NOAUTH scenarios, TLS, SRTP, WebRTC, real commercial carrier
credentials, PJSIP realtime, PostgreSQL, Khomp/TDM, fax, broad trunk UI
redesign. Also, per TASK-0014's own architecture doc: SNEPSIP/SNEPIAX2/
KHOMP/VIRTUAL trunk creation was not individually re-verified live in
this task (only plain SIP/IAX2's shared code paths were touched, and
only the new `pjsip` branch is new code — no evidence-based reason to
expect a behavior change for the others, but not itself proof).

---

Stopping here at a commit checkpoint. Not beginning TASK-0016.
