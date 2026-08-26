# TASK-0018 — First-class PJSIP transport management

## Status

**Implemented and validated.** `make smoke`: 16/0/0. `make call-smoke`:
18/18. `make trunk-smoke`: 23/23 (run twice for idempotency). `make
transport-smoke` (new): 13/13. All four validated from the current
long-lived dev environment and, independently, from a **fully clean
rebuild** (all 7 named volumes wiped, including `mag-db`). Templates and
overrides are explicitly out of scope (TASK-0019+). Not committed —
stopping at the commit checkpoint.

## Goal

Replace the single hardcoded static `[transport-udp]` stanza every PJSIP
extension/trunk implicitly depended on with a first-class,
UI-managed `pjsip_transports` model, exactly as designed in
docs/tasks/0017-pjsip-transports-and-templates-architecture.md — while
changing nothing about existing extension/trunk behavior.

---

## 1. Schema

Two new tables, four new nullable FK columns, added directly to
`snep/install/database/schema.sql` (defined before `peers`/`trunks`,
since both reference `pjsip_transports` via FK):

```sql
pjsip_transports
  id, name UNIQUE, protocol, bind_address, bind_port,
  domain, external_signaling_address, external_signaling_port,
  external_media_address, symmetric_transport, allow_reload,
  is_default, enabled, is_seed, created_at, updated_at

pjsip_transport_networks        -- local_net, one row per network
  id, transport_id FK -> pjsip_transports.id ON DELETE CASCADE, network

peers.transport_id   NULL FK -> pjsip_transports.id ON DELETE RESTRICT
trunks.transport_id  NULL FK -> pjsip_transports.id ON DELETE RESTRICT
```

`local_net` is a **real child table**, one row per CIDR — not a
delimited string — per TASK-0017 §2/§18's explicit instruction not to
flatten an already-normalized concept back into opaque text. Asterisk
itself supports repeating `local_net=` lines; the generator (§3) emits
one line per row, in insertion order.

**TLS/WSS-only columns (`cert_file`, `priv_key_file`, `verify_client`,
...) were deliberately NOT added in this task** — a small, considered
deviation from TASK-0017 §2's "store them now" suggestion. Since WSS is
seeded disabled (§2) and never actually emitted while disabled, these
columns would be dead weight with zero present value; adding them is a
trivial `ALTER TABLE` for whichever future task implements real
TLS/WSS behavior (item 16's explicit deferral), not a blocked path.

`ON DELETE RESTRICT` on both new FK columns is the hard backstop for
"do not silently allow deletion of an in-use transport" (item 2) — the
application-layer check (§8) is the primary UX, the FK is what makes it
impossible to bypass.

---

## 2. Seed transports

Added to `snep/install/database/system_data.sql`:

| name | protocol | bind | is_default | enabled |
|---|---|---|---|---|
| `udp` | udp | `0.0.0.0:5060` | **yes** | yes |
| `tcp` | tcp | `0.0.0.0:5060` | no | yes |
| `wss` | wss | `0.0.0.0:8089` | no | **no** |

`udp` is byte-identical to the static `[transport-udp]` stanza it
replaces — the actual migration mechanism (§5). `wss` is seeded as a
placeholder row only, `enabled=false`: a WSS transport with no TLS
certificate configured cannot bind; the generator (§3) skips disabled
rows entirely rather than emit a broken stanza. This satisfies item 16's
constraint precisely ("WSS may exist as a seeded transport record only
to the extent the current build can represent it safely") without
broadening into WebRTC.

**Protection semantics, as implemented**:
- **Editable**: yes, every field, on all three seeds — they are ordinary
  rows (`snep/lib/Snep/PjsipTransports/Manager.php`), not application
  constants.
- **Deletable**: only when usage count is zero (§8) AND, for the current
  default, only after a different transport is promoted to default
  first (`PjsipTransportsController::removeAction()` blocks deleting the
  `is_default` row while more than one transport exists).
- **Default marker**: `is_default` boolean; setting it on one row
  demotes every other row in the same transaction
  (`Snep_PjsipTransports_Manager::clearDefault()`), so exactly one
  default always exists.

---

## 3. Transport generator

New class, third sibling of `Snep_PjsipConf`/`Snep_PjsipTrunkConf`:
`snep/lib/Snep/PjsipTransportConf.php`. Same established shape: own SQL
fetch (`pjsip_transports WHERE enabled=1`, joined to
`pjsip_transport_networks`), own per-row rendering, own file write, own
`module reload res_pjsip.so` (checked for the `"reloaded successfully"`
substring, throwing `PBX_Exception_IO` otherwise — identical discipline
to the other two generators). It generates **only** `type=transport`
sections — no endpoint/aor/auth/registration logic was moved into it,
and nothing in `Snep_PjsipConf`/`Snep_PjsipTrunkConf`'s own NAT/codec/
DTMF translation logic was touched.

Field mapping is a direct, verbatim 1:1 — transports have no chan_sip-era
legacy field to interpret (unlike endpoint/aor mapping), so there is no
ambiguous-translation decision anywhere in this generator.

---

## 4. Generated file / include hierarchy

```
/etc/asterisk/pjsip.conf                          <- static, include-only now
    #include snep/senma-pjsip-transports.conf      <- NEW: Snep_PjsipTransportConf
    #include snep/senma-pjsip.conf                 <- Snep_PjsipConf (extensions, unchanged)
    #include snep/senma-pjsip-trunks.conf          <- Snep_PjsipTrunkConf (trunks, unchanged)
```

Transports first — chosen for operational/debugging clarity (reading the
merged file top-to-bottom mirrors dependency order), **not** because
include order affects functional resolution: Asterisk's config loader
merges every `#include` into one in-memory tree before sorcery resolves
any `transport=` reference, confirmed by reading how PJSIP config
loading actually works, not assumed.

**Deterministic, safe regeneration, no duplicates**: same full-stateless-
rewrite property as the other two generators — every write reflects
exactly the current `pjsip_transports` table, verified live across every
create/edit/delete cycle in §12/§13.

**Cross-generator consistency**: `peers.transport_id`/`trunks.transport_id`
reference a transport by immutable `id`; the generated text embeds the
transport's *current name*. A rename therefore requires the extension/
trunk generators to re-run too (their output text would otherwise embed
a stale name). `PjsipTransportsController`'s create/edit/delete actions
all call `regenerateAll()`, which runs all three generators in sequence
— the same "call every generator additively, let each filter itself"
pattern already established since TASK-0011.

**A real gap found and fixed during clean-rebuild validation**:
`ExtensionsController`/`TrunksController` only ever called their own
respective generator (`Snep_PjsipConf`/`Snep_PjsipTrunkConf`), never the
new transport generator. On a genuinely fresh install, this meant
`senma-pjsip-transports.conf` stayed empty (no `[udp]`/`[tcp]` sections
ever written) until an admin happened to visit the new Transports page
— even though every generated extension/trunk endpoint already emitted
`transport=udp`, referencing an object that didn't exist in Asterisk's
live config at all. Reproduced live: a freshly-created extension showed
`transport=udp` in its endpoint config while `pjsip show transports`
reported "No objects found." Fixed by adding
`Snep_PjsipTransportConf::loadConfFromDb();` immediately before every
existing `Snep_PjsipConf::loadConfFromDb()`/`Snep_PjsipTrunkConf::
loadConfFromDb()` call site (4 in each controller, 8 total) — the same
additive-call pattern, extended one more generator deep. Re-verified:
the very first extension created on a fresh install now correctly
produces both `[udp]` and `[tcp]` transport sections before anything
else is generated.

---

## 5. Migration from the static transport

`docker/asterisk-config/pjsip.conf`'s `[transport-udp]` stanza is
removed entirely; the file now holds only include structure (matching
TASK-0011's "production provisioning must not depend on anything defined
in a static file" principle, extended to transports). The seeded `udp`
row (§2) is byte-identical in `protocol`/`bind`, so every extension/
trunk's actual wire behavior is unchanged. `peers.transport_id`/
`trunks.transport_id` are `NULL` for every existing row — **no data
backfill is needed or performed**: `Snep_PjsipConf::resolveTransportName()`
(shared by both generators) resolves `NULL` to whichever transport is
currently `is_default`, which is `udp`.

### A real, empirically-characterized reload/lifecycle finding (item 8)

Migrating from the static `[transport-udp]` object to the generated
`[udp]` object (same bind, different sorcery name) is **not** a clean
hot-reload:

```
$ asterisk -rx "module reload res_pjsip.so"
ERROR res_pjsip/config_transport.c: Transport 'udp' could not be started: Address already in use
ERROR res_sorcery_config.c: Could not create an object of type 'transport' with id 'udp'
```

The *old* `transport-udp` object's OS-level UDP socket stays bound in
the live process even though it no longer exists in the merged config
(`module reload` recreates config objects; it does not appear to
proactively unbind a transport whose name changed) — `pjsip show
transports` showed the surviving old-named object still holding the
port. **A full Asterisk process restart (`core restart now`, or a
container restart) is required once**, after which both `udp` and `tcp`
bind cleanly and stay that way permanently. This is a one-time
migration-day operational step, not a recurring one — confirmed by
repeatedly creating/editing/deleting transports afterward with zero
further restarts needed (§12/§13).

**A second, independent, also-restart-requiring finding**, discovered
during clean-rebuild validation (a genuinely fresh install, no prior
`transport-udp` object ever existed, so it is not the same phenomenon
as above): the **very first PJSIP trunk registration created on a given
Asterisk process's lifetime** can get stuck indefinitely
(`No response received from 'sip:provider:5060'`, retrying every
`retry_interval` seconds, never reaching `Registered`) even though the
transport itself loaded correctly and a direct call through the trunk's
static AOR contact also produced no response. Root-caused via `pjsip
set logger on` packet capture on both sides: **no REGISTER packet is
ever actually transmitted** for the stuck attempt (contrast with a
working exchange, which logs a full `res_pjsip_logger.c: <---
Transmitting SIP request...`/`<--- Received SIP response...` pair) — an
internal PJSIP outbound-registration transport-resolution state issue,
not a network problem (confirmed: sockets bound correctly on both
containers, DNS resolved correctly, and the *reverse* direction —
provider originating toward SENMA — worked perfectly throughout).
**One full process restart resolves it permanently**: immediately after
restarting, the same trunk registered within seconds, and two
subsequently-created trunks (on the same, now-settled process) both
registered normally within the already-documented few-second
self-correcting window (TASK-0015 §10's "Auth object could not be
found" transient) — confirming this is a **one-time, first-trunk-after-
boot settling requirement**, not a per-trunk or per-reload recurring
cost.

**Operational guidance, documented honestly rather than silently
engineered around** (per the task's own explicit instruction: "if
Asterisk refuses a transport change while active, surface that honestly
in SENMA, do not fake success"): if outbound trunk registration does not
reach `Registered` within the normal ~15s window on a freshly-deployed
or freshly-migrated environment, **one Asterisk restart** (`make
restart`, or a container restart) resolves it, permanently, for the
life of that process. No code change was made to paper over this — a
genuine engineering investigation into eliminating it entirely would
require changes to PJSIP's own outbound-registration/transport internals
beyond this task's scope (transports only, item 16).

**What *is* safely hot-reloadable, confirmed empirically, no restart
ever needed**:
- Creating a **new** transport on a previously-unused bind (no restart).
- **Editing** an existing transport's own fields — including its bind
  address/port — under the *same* name (no restart; confirmed via a
  direct edit from port 5070→5075 that took effect immediately).
- Editing any of `domain`/`external_signaling_address`/
  `external_signaling_port`/`external_media_address`/`local_net`/
  `symmetric_transport` on an existing transport (confirmed via
  `transport-smoke`'s own edit check, §13).
- **Deleting** a transport (no restart).
- Creating additional trunks/extensions *after* the one-time settling
  above has occurred.

**What is NOT safely hot-reloadable without a restart**:
- Reusing a bind address:port that a *differently-named*, still-live
  transport object previously held (a rename, or two transports briefly
  swapping addresses).
- The very first trunk registration created on a given Asterisk process
  lifetime, in rare cases (self-corrects within seconds most of the
  time, per TASK-2015's own precedent; on this task's specific
  clean-rebuild validation run it did not self-correct and needed one
  restart).

---

## 6. Transport CRUD UI

```
PJSIP
└── Transports
```

Added as a new top-level nav group in `snep/modules/default/resources.xml`
(the existing declarative resource-to-menu/ACL mechanism every other
SENMA page already uses — no new menu framework). New controller
`PjsipTransportsController` (`snep/modules/default/controllers/`), new
views under `snep/modules/default/views/scripts/pjsip-transports/`
(`index.phtml`, `addedit.phtml`), reusing the exact bootstrap/table/
form conventions already established by `trunks`/`route`. List page
columns: name, protocol, bind, external signaling, external media,
status (enabled/disabled + default badge), usage count, actions
(edit/delete). No unrelated SENMA page was touched.

Duplicate/clone was evaluated per TASK-0017 §16 but **not implemented**
for transports specifically — TASK-0017's clone recommendation was
scoped to *templates* (§16 there), and only 3 transports exist by
design in this milestone; cloning a transport is not a requirement item
2/6 of this task actually asks for. Not built, not missing — correctly
out of this task's scope.

---

## 7. Validation

`snep/lib/Snep/PjsipTransports/Manager.php` provides the type/format
validators, called from `PjsipTransportsController::validatePost()`
before any write:

| Field | Rule |
|---|---|
| `name` | `^[A-Za-z0-9_-]{1,80}$`, unique — this string becomes a literal `[name]` sorcery section header, so it must never contain characters that could break out of that context |
| `protocol` | must be one of `udp,tcp,tls,wss,ws` |
| `bind_address` | valid IP or hostname |
| `bind_port` | integer 1-65535 |
| `domain`, `external_signaling_address`, `external_media_address` | optional; if set, valid IP or hostname |
| `external_signaling_port` | optional; integer 1-65535 |
| `local_net` (each line) | valid IPv4/IPv6 address or CIDR block — free text rejected |
| `symmetric_transport`/`allow_reload`/`is_default`/`enabled` | checkboxes, coerced to 1/0 |

**No raw PJSIP directive injection is possible**: every persisted field
is an explicit, individually-validated column
(`PjsipTransportsController::buildData()`'s allow-list) — there is no
free-text field that gets written verbatim into the generated config
anywhere in this model.

---

## 8. Usage tracking

`Snep_PjsipTransports_Manager::getUsageCount()`/`getUsageDetails()`
query `peers.transport_id`/`trunks.transport_id` directly — no
templates exist yet to also check (TASK-0019+). `removeAction()` blocks
deletion with a friendly message listing every referencing extension/
trunk by id and label (mirroring `TrunksController::removeAction()`'s
own "list what's using it" pattern for route references), backed by the
`ON DELETE RESTRICT` FK (§1) as the unconditional final backstop.

---

## 9-10. Extension/trunk transport reference — the minimum, no UI selector

Per item 10's explicit scope limit, **no transport picker was added to
the extension/trunk create/edit forms**. The only change is the
generators' new resolution step (§4): `peers.transport_id`/
`trunks.transport_id` stay `NULL` for every object created through the
existing, unmodified UI, resolving to the system default transport —
exactly the migration behavior TASK-0017 §3/§17 designed. Setting a
non-default transport on a specific object is possible today only at
the data layer (used deliberately by `transport-smoke`'s own lifecycle
test, §13, and available to a future task that adds the picker) — this
is the correct, minimal scope for a "transports only" milestone.

---

## 11-13. Sercomtel-style acceptance case, runtime proof, lifecycle

New `scripts/transport-smoke-test.sh` (`make transport-smoke`, 13
checks), mirroring the established smoke-test conventions exactly. The
acceptance fixture models the task's own Sercomtel-style example with
one deliberate, reasoned adaptation: `bind_port=5070`, not the literal
`0.0.0.0:5060` the example illustrated — port 5060/udp is already bound
by the real seeded default transport for the entire test run, so
reusing it would be a genuine port conflict, not a fixture choice. Every
other field is exactly as specified:

```
protocol = udp
bind = 0.0.0.0:5070
domain = sercomtel.example.test
external_media_address = 203.0.113.10        (RFC 5737 TEST-NET-3 -- reserved
external_signaling_address = 203.0.113.11     for documentation, never a real
external_signaling_port = 5070                carrier's address)
local_net = 172.28.0.0/16, 192.168.0.0/16     (two independent CIDRs)
symmetric_transport = yes
```

**Proven, in order**:
1. Created via the real `PjsipTransportsController::addAction()` HTTP
   flow (not SQL, not hand-written config).
2. Every field appears in the generated `senma-pjsip-transports.conf`
   with its own distinct value — `domain`, `external_signaling_address`/
   `port`, `external_media_address`, and both `local_net` lines are all
   independently present, none collapsed into another (the task's own
   "do not equate remote SIP server / identify match / domain / external
   signaling / external media" requirement, verified structurally).
3. `pjsip show transport sercomtel-smoke` (Asterisk's own real runtime,
   not just the generated file) reflects every field.
4. Edited (`external_media_address` changed) — reflected live via a
   plain reload, no restart (§5's confirmed-safe case).
5. A controlled reference extension fixture (`peers.transport_id` set
   directly, per §9/§10's scope) causes `Snep_PjsipConf` to emit
   `transport=sercomtel-smoke` instead of the system default.
6. Deletion is **blocked** while referenced (HTTP 200, error page names
   the referencing extension) — the transport survives unchanged.
7. Reference cleared → the extension reverts to `transport=udp`
   (`NULL` resolving to the default, confirmed live) → deletion now
   succeeds (HTTP 302) → no stale transport remains in either the
   generated file or Asterisk's live runtime.

Run twice consecutively: 13/13 both times (idempotent). Run again from
a fully clean rebuild: 13/13.

---

## 14. Regression

| Suite | Long-lived environment | Clean rebuild (all 7 volumes wiped) |
|---|---|---|
| `make smoke` | 16/0/0 | 16/0/0 |
| `make call-smoke` | 18/18 | 18/18 |
| `make trunk-smoke` (×2, idempotency) | 23/23, 23/23 | 23/23, 23/23 |
| `make transport-smoke` (×2, idempotency) | 13/13, 13/13 | 13/13, 13/13 |

**Findings during clean-rebuild validation, investigated to a
confirmed, unrelated root cause, not silently worked around**:

- **A truly virgin `mag-db` triggers SNEP's own ITC "register your
  product" prompt** on first dashboard load — the exact same,
  already-documented (TASK-0015 §15) pre-existing behavior, dismissed
  once (`POST save=noregister`) exactly as a real first-run
  administrator would. Not a regression.
- **A one-time ODBC/CDR module-loading race on fresh boot**: on this
  validation run, `res_odbc`'s DSN pre-connect and `cdr_adaptive_odbc`'s
  connection lookup both failed once at Asterisk's very first boot
  (`db` not fully ready yet at that exact moment), leaving 0 active
  ODBC connections and CDR writes silently no-op'ing. `module reload
  res_odbc.so` followed by `module reload cdr_adaptive_odbc.so` cleared
  it permanently. Pre-existing Docker Compose startup-ordering
  characteristic, unrelated to transports — not present in every clean
  rebuild this project has done (TASK-0011/0015 did not report it), not
  chased further here.
- **The two transport-specific reload findings already documented in
  full in §5** (transport rename requires one restart; first-trunk-
  after-boot registration may require one restart) — both real, both
  transport-related, both now precisely characterized and permanently
  resolved by a single restart per process lifetime.
- **A real, pre-existing, unrelated bug found in `scripts/trunk-smoke-test.sh`**
  (TASK-0015, not touched by this task): `delete_trunk()`'s cleanup call
  hardcodes the literal string `"1"` as the trunk's `name` parameter
  (`TrunksController::removeAction()`'s `Snep_Trunks_Manager::
  removePeers($name)` deletes `peers WHERE name=$name` using whatever
  the request parameter says, not the trunk's actual DB `name` column).
  This has never been caught in this project's history because a
  standalone `trunk-smoke` run always starts from an empty `trunks`
  table, so the computed next name (`MAX(name)+1`) is coincidentally
  always `'1'`. It was exposed here only because this task's own manual,
  out-of-band debugging (§5's investigation) created and deleted several
  extra trunks in between, at one point leaving a stray `peers` row
  (`name='1'`, no matching `trunks` row) that collided with a
  subsequent `trunk-smoke` run's own auto-computed name. **Not fixed**,
  per CLAUDE.md's bug policy and this task's own item 13 stop-rule
  (independent, pre-existing, discovered only through this task's own
  debugging activity, not through any code TASK-0018 changed) — the
  stray row was deleted directly (a debug-session cleanup, not a
  product fix) and `trunk-smoke` was re-verified 23/23 twice from a
  genuinely empty `trunks` table. **Flagged here for a future,
  dedicated fix**: `delete_trunk()` should look up the trunk's real
  `name` from the DB before calling the HTTP delete endpoint, or
  `TrunksController::removeAction()` should ignore the posted `name`
  entirely and look it up server-side from `id` — either fix is a
  one-line change, out of scope for this transports-only task.

No new PHP Fatal Errors were introduced by any TASK-0018 change, in
either environment.

---

## 15. Security

- **Transports never contain auth credentials** — confirmed by the
  schema (§1): no password/secret-shaped column exists anywhere in
  `pjsip_transports`/`pjsip_transport_networks`. Credentials remain
  exactly where they already were (trunk/extension `auth` objects).
- **Network fields strictly validated** (§7) — CIDR/IP/hostname/port
  typed validation on every field, free text rejected.
- **No raw `pjsip.conf` injection**: every field is an individually
  validated, individually-emitted column (§3/§7) — there is no
  multiline/opaque text field anywhere in this model, matching
  TASK-0017 §9's override-architecture principle applied here to
  transports specifically.

---

## 16. Explicitly deferred

Unchanged from the task's own list: extension templates, trunk
templates, generic overrides, TLS certificate upload/management,
WebRTC, SRTP, provider presets, automatic NAT discovery, PostgreSQL.
WSS exists only as a seeded, disabled placeholder row (§2) — no TLS
behavior was implemented or made to appear functional.

---

## Files changed

- `snep/install/database/schema.sql` — `pjsip_transports`,
  `pjsip_transport_networks`, `peers.transport_id`, `trunks.transport_id`.
- `snep/install/database/system_data.sql` — seed `udp`/`tcp`/`wss` rows.
- `snep/lib/Snep/PjsipTransportConf.php` (new) — the generator.
- `snep/lib/Snep/PjsipTransports/Manager.php` (new) — persistence/validation.
- `snep/modules/default/controllers/PjsipTransportsController.php` (new) — CRUD.
- `snep/modules/default/views/scripts/pjsip-transports/{index,addedit}.phtml` (new).
- `snep/modules/default/resources.xml` — PJSIP > Transports nav/ACL entry.
- `snep/lib/Snep/PjsipConf.php` — `resolveTransportName()` (shared,
  public), `transport=` emission on the extension endpoint.
- `snep/lib/Snep/PjsipTrunkConf.php` — `transport=` emission on the
  trunk endpoint and registration object.
- `snep/modules/default/controllers/ExtensionsController.php` /
  `TrunksController.php` — added `Snep_PjsipTransportConf::
  loadConfFromDb()` at every existing generator call site (§4's fix).
- `docker/asterisk-config/pjsip.conf` — static `[transport-udp]` removed,
  new include added first.
- `docker/asterisk-entrypoint.sh` — pre-create/chmod block for
  `senma-pjsip-transports.conf`.
- `Makefile` — `transport-smoke` target.
- `scripts/transport-smoke-test.sh` (new) — 13-check automated suite.

---

Stopping here at a commit checkpoint. Not beginning TASK-0019.
