# TASK-0010 — PJSIP extension provisioning architecture

## Status

**Investigation/design only.** No runtime code, database schema, Docker
configuration, or Asterisk configuration was changed. All findings below
are sourced from direct inspection of the current tree
(`ExtensionsController.php`, `Snep_Extensions_Manager`, `Snep_InterfaceConf`,
`schema.sql`, the extensions form view/JS) and live Asterisk 22.10.1
evidence already captured during TASK-0009 (`pjsip show endpoint`'s full
parameter dump, the `res_pjsip.so` reload behavior, the AOR-naming
registrar requirement). `git status` is clean; `make smoke` (16/0/0) and
`make call-smoke` (13/13) are unaffected — nothing here was exercised
against a running stack beyond what TASK-0009 already validated.

## Baseline this design builds on (TASK-0009)

Asterisk 22.10.1, PJSIP runtime built and working, two **static,
hand-written** development endpoints (1000/1001) register and complete a
real call through SENMA's existing AGI/rule engine, `cdr_adaptive_odbc`
writes a real CDR, SENMA's report endpoint reads it back.
`PBX_Asterisk_Interface_PJSIP` + `PBX_Usuarios::get()`'s `PJSIP` branch
already exist and work. None of that is provisioning — it's three
hand-written `pjsip.conf` sections, not generated from the `peers` table.
This task designs how to close that gap.

---

## 1. End-to-end current provisioning trace

### Create

```
ExtensionsController::addAction()                                [controller]
  -> renders addedit.phtml (action="add")                        [view]
  -> POST back to addAction()
  -> ExtensionsController::execAdd($data, update=false)           [controller, protected]
       - SELECT peers WHERE name=$exten  (duplicate-name guard)
       - builds $channel = "SIP/$exten" | "IAX2/$exten" | "KHOMP/bXcY"
         | "VIRTUAL/$trunkId" | "MANUAL/$manual"    (from technology + exten)
       - builds $nat (comma-joined nat_* checkboxes), $qualify (yes/no),
         $allow (";"-joined codec1;codec2;codec3)
       - raw string-interpolated SQL:
         INSERT INTO peers (name, password, callerid, context, mailbox,
           qualify, secret, type, allow, defaultuser, fullcontact,
           dtmfmode, email, `call-limit`, incominglimit, outgoinglimit,
           usa_vc, pickupgroup, canal, nat, peer_type, authenticate,
           trunk, callgroup, time_total, cancallforward, directmedia,
           time_chargeby, blf, accountcode, amaflags, defaultip, host,
           insecure, language, deny, permit, mask, port, restrictcid,
           rtptimeout, rtpholdtimeout, musiconhold, regseconds, ipaddr,
           regexten, setvar, disallow) VALUES (...)
       - if voicemail checked: INSERT INTO voicemail_users (...)
       - Snep_ExtensionsGroups_Manager::updateGroupsExtension($id, ..., $extenGroup)
       - Snep_InterfaceConf::loadConfFromDb()                      [full regen, see §3]
  -> Snep_Audit_Manager::SaveLog("Added", 'peers', $exten, ...)
  -> redirect /extensions/
```

**Inputs**: `name`/`exten` (number), `callerid` display name, `password`
(-> `secret` column, the SIP auth secret), `passwordpadlock` (-> `password`
column, a separate numeric PIN unrelated to SIP auth), `technology`,
per-technology fields (`manual`, `board`/`channel` for Khomp/Virtual),
`nat_*` checkboxes, `qualify` checkbox, `type` (friend/peer/user),
`codec`/`codec1`/`codec2`, `directmedia`, `dtmf`, `email`, `calllimit`,
`voicemail` checkbox, `authenticate` checkbox (padlock feature, unrelated
to SIP auth), `cancallforward`, `minute_control`/`timetotal`/`controltype`,
`pickup_group`, `exten_group`, `blf`.

**Persisted fields**: one `peers` row (`peer_type='R'`) + optionally one
`voicemail_users` row + `core_peer_groups` membership rows.

**Generated configuration**: a full rewrite of `snep-sip.conf` (or
`snep-iax2.conf`) + matching `-trunks.conf` + `-hints.conf`, covering
*every* `peer_type='R'`/`'T'` row of that tech, not just the one just
created (see §3 — there is no per-row incremental write anywhere in this
codebase).

**Side effects**: `Snep_Audit_Manager` log row; three AMI `Command()`
calls (`sip reload`, `dialplan reload`, `iax2 reload`) fired
unconditionally regardless of which tech was actually touched.

**Asterisk commands**: `sip reload`, `dialplan reload`, `iax2 reload` (via
AMI `Command` action, `PBX_Asterisk_AMI::getInstance()->Command(...)`).

### Edit

Same `execAdd($postData, update=true)` path. One structural detail with
real migration relevance: **`editAction()` unconditionally overwrites the
posted `exten` with the URL's `id` parameter**
(`$postData["exten"] = $this->_request->getParam("id");`) *before* calling
`execAdd`. The extension number is therefore **not actually changeable
through today's edit flow**, regardless of what the form might submit —
`execAdd`'s `$update` branch runs a plain `UPDATE ... WHERE id=$idExten`
that never touches `name`. This removes "extension-number change" as a
live concern for the create/edit UI (see §6); it would only become
relevant if some other code path writes `peers.name` directly.

### Delete

```
ExtensionsController::removeAction()
  -> Snep_Extensions_Manager::getValidation($id) + getValidationRules($id)
       (blocks delete if any regras_negocio row references this extension
        by id via origem/destino LIKE 'R:<id>' or an actions_config value)
  -> on POST confirm:
       Snep_Binds_Manager::removeBondByPeer($exten)
       Snep_Extensions_Manager::remove($exten)            DELETE peers WHERE name=$exten
       Snep_Extensions_Manager::removeVoicemail($exten)   DELETE voicemail_users WHERE customer_id=$exten
       Snep_ExtensionsGroups_Manager::deleteExtensionGroups($idExten)
       Snep_InterfaceConf::loadConfFromDb()
```

`disableAction()`/`enableAction()` are simpler: they only flip
`peers.disabled` (`Snep_Extensions_Manager::disable()`/`enable()`, a plain
`UPDATE`) and then call the same `loadConfFromDb()`. There is no separate
"soft delete leaves the Asterisk object in place" state — disabling an
extension makes it **disappear entirely** from the next regenerated
config (see §3's SQL filter), not just get marked unreachable.

### Reload

There is no reload operation independent of create/edit/delete/disable/
enable — `Snep_InterfaceConf::loadConfFromDb()` *is* the reload, invoked
identically and unconditionally from every one of those five actions. It
is a full, stateless regeneration from the current `peers` table, not a
targeted per-row update.

---

## 2. Legacy field matrix

Derived from `schema.sql`'s `peers` table (`snep/install/database/
schema.sql:172-239`), `ExtensionsController::execAdd()`, and
`Snep_InterfaceConf::loadConfFromDb()` (which fields the generator
actually *reads*, separately from which fields are merely stored).

| DB column | UI field | chan_sip meaning | Emitted by generator today? | PJSIP mapping |
|---|---|---|---|---|
| `name` | extension number | peer section name / `defaultuser` | Yes (`[name]` section header, `defaultuser=`) | Endpoint **and** AOR object name (§6) |
| `secret` | "password" field | plaintext auth secret | Yes (`secret=`) | `auth` object's `password=` (`auth_type=userpass`) |
| `password` | "passwordpadlock" field | **not a SIP field at all** — a separate numeric PIN (padlock/portal use) | No | No PJSIP relevance; unrelated feature, carries over unchanged |
| `callerid` | display name | `callerid=` | Yes | Endpoint `callerid=` (identical option name/format in PJSIP) |
| `context` | (always `'default'`, not user-editable) | `context=` | Yes | Endpoint `context=` |
| `host` | (always `'dynamic'`, not user-editable) | `host=dynamic` (register-based peer) | Yes (`host=`) | **No PJSIP equivalent as a single field** — PJSIP has no `host=` on the endpoint; dynamic registration is the *absence* of a static `contact=`/`identify` and is what `aor`'s registrar-populated dynamic contact already does. Structurally obsolete for endpoint/aor; not carried forward. |
| `type` | friend/peer/user radio | chan_sip's incoming-match-vs-outgoing-auth mode | Yes (`type=`) | **No PJSIP equivalent.** PJSIP always has separate endpoint+auth+aor; there is no "type" concept. Structurally obsolete. |
| `qualify` | checkbox (yes/no) | enable OPTIONS keepalive at Asterisk's default interval | Yes (`qualify=`) | AOR `qualify_frequency=<seconds>` — a **boolean-to-interval** translation, not 1:1 (§9) |
| `nat` | `nat_{no,comedia,force_rport,auto_comedia,auto_force_rport}` checkboxes, comma-joined | chan_sip's combined NAT-handling flag | Yes, verbatim (`nat=`) — **but only for trunks**; the extension branch also writes it verbatim, untranslated, since it's still chan_sip-only today | Splits into `force_rport`, `rtp_symmetric`, (`rewrite_contact` has no direct chan_sip source field) — see §9, explicit interpretation required |
| `directmedia` | yes/nonat/no/outgoing/update radio | chan_sip 5-way direct-media mode | Yes, verbatim | Splits into `direct_media` (bool) + `direct_media_method` + `disable_direct_media_on_nat`; `outgoing`-only has **no PJSIP equivalent** (§9) |
| `dtmfmode` | rfc2833/inband/info radio | `dtmfmode=` | Yes | PJSIP `dtmf_mode=` — same 3 values plus `auto`/`auto_info`; direct rename, values unchanged |
| `allow`/`disallow` | 3 codec `<select>`s, `;`-joined in DB | codec list | Yes — **generator already converts `;`→`,` before writing chan_sip's `allow=`** (`Snep_InterfaceConf.php:83-90`) | Same transformation reused verbatim for PJSIP `allow=`/`disallow=` — chan_sip and PJSIP use identical comma-separated codec-name syntax. **No new codec logic needed** (§8) |
| `callgroup` | (silently set equal to `pickupgroup`'s value in `execAdd`) | Asterisk call-group feature | **No** — never emitted by the generator for extensions | Dead/unused for provisioning either way; not a PJSIP concern |
| `pickupgroup` | pickup-group `<select>` | — | **No** — never emitted as static peer config | Consumed entirely at **dialplan runtime**, not provisioning: `DiscarRamal::execute()` calls `$asterisk->set_variable('__PICKUPMARK', $ramal->getPickupGroup())` per-call. Technology-agnostic already; unaffected by PJSIP migration |
| `language` | (not exposed in this form) | — | No | Language is applied globally per-call (`CHANNEL(language)=${SNEP_LANGUAGE}` in `extensions.conf`), not per-peer. Unaffected |
| `mailbox` | (auto-set = extension number, not user-editable) | — | **No** — chan_sip stanza never emits `mailbox=` either | Voicemail is invoked directly as a dialplan action (`VoiceMail($mailbox,"u")`), not via the channel driver's native mailbox/MWI option. Not required for behavior parity; PJSIP's `mailboxes=` (native MWI subscription) is an **optional future enhancement**, not a migration requirement |
| `insecure` | (defaulted `''` on create, not exposed for extensions) | chan_sip's auth-bypass matching flag | **No** — never emitted for `peer_type='R'` (only appears in the trunk branch, and only if `trunks.insecure` is set) | Not needed for extension parity |
| `deny`/`permit`/`mask` | (not exposed for extensions) | chan_sip ACL | **No** — never emitted for extensions anywhere in the generator | PJSIP equivalent is an `[identify]`/`acl` object if ever needed; **out of scope**, dead for extensions today |
| `usa_vc` | voicemail checkbox | (SENMA-internal flag, drives `voicemail_users` row) | No (not a chan_sip field) | Unaffected |
| `authenticate` | "padlock" checkbox | (SENMA-internal, `PBX_Usuarios::get()`: `if ($usuario->authenticate) $user->lock();`) | No | Application-level feature, orthogonal to SIP tech |
| `cancallforward` | checkbox | `cancallforward=` | Yes | Direct rename possible in PJSIP dialplan logic if ever read there — not currently read by `Snep_InterfaceConf` for anything beyond writing it back; no functional generator dependency either way |
| `call-limit` | numeric field | `call-limit=` (concurrent-call cap) | Yes | PJSIP has no single equivalent option; nearest is `Set(CHANNEL(dialgroup))`-style dialplan enforcement or per-endpoint call counting via `max_contacts`/dialplan logic — **no direct config-level equivalent**, flagged, not solved here |
| `blf` | checkbox | drives a `[hints]` stanza (`exten => name,hint,canal`) | Yes, but only the **hints** file, keyed off `peer['canal']` verbatim | Works unchanged once `canal` is `PJSIP/<name>` — hint syntax (`exten => X,hint,PJSIP/X`) is technology-string-based, not chan_sip-specific |
| `secret`'s round-trip | edit form | value round-tripped **in plaintext** into the rendered `<input type="password" value="...">` | n/a | See §7 |
| `md5secret` | (never written by `execAdd`, defaults `''`) | precomputed MD5 digest alternative to plaintext secret | No | Dead column; `auth_type=userpass` (plaintext) is the only mode SENMA has ever used, confirmed by `execAdd` never populating it |
| `regseconds`/`ipaddr`/`regexten` | (defaulted, not exposed) | chan_sip's own realtime registration-state bookkeeping | No | PJSIP tracks equivalent live state in `ps_contacts`/its own registrar internals, not a DB column SENMA owns either way — not needed |
| `disabled` | Enable/Disable action | — | Yes — **filters the row out of generation entirely** (`WHERE ... disabled != true ...`) | Same filter to reuse for PJSIP: disabling = the endpoint/auth/aor disappear from the next generated file, exactly like today |

**Net finding**: of the ~48 columns `execAdd` touches, only 10 are ever
actually *read* by `Snep_InterfaceConf` for extensions
(`name`,`type`,`context`,`host`,`secret`,`callerid`,`dtmfmode`,`nat`,
`qualify`,`disallow`,`allow`,`defaultuser`,`cancallforward`,`directmedia`,
`call-limit`,`canal`,`blf`,`disabled`) — the rest are either
runtime/dialplan-consumed (`pickupgroup`), SENMA-internal
(`usa_vc`,`authenticate`), or genuinely dead for extensions
(`insecure`,`deny`,`permit`,`mask`,`callgroup`,`md5secret`). This
narrows the actual PJSIP-generator surface considerably.

---

## 3. `Snep_InterfaceConf` architectural assessment

Full file read: `snep/lib/Snep/InterfaceConf.php`, 219 lines, one public
static method, `loadConfFromDb()`.

- **Internal representation of a peer: none.** There is no intermediate
  object or array shape — the raw `$peer` DB row (an associative array
  from `SELECT * FROM peers`) is read and string-concatenated directly
  into config text inside the loop body. No `Snep_Peer`/`Snep_Endpoint`
  class exists.
- **Generation is hardcoded to chan_sip/chan_iax2 syntax**, not generic.
  The method iterates a literal `array("sip", "iax2")`, and every line of
  output text is a hand-written chan_sip/IAX2 directive
  (`type=`, `host=`, `nat=`, `directmedia=`, ...). There is no templating
  layer, no per-technology strategy object, no abstraction point where a
  third technology could plug in without adding a third hardcoded branch
  to the same function.
- **Template/section selection**: none — a single `foreach` over the tech
  array, with a nested `if ($peer['peer_type'] === 'T') { ... } else { ... }`
  for trunk-vs-extension, and inside the trunk branch a further
  `if/elseif` on `$trunk->type` (SNEPSIP/SNEPIAX2/other). No selection
  mechanism exists beyond this literal branching.
- **Multiple interfaces**: extensions and trunks are handled by the
  *same* method and the *same* per-tech SQL query (`peer_type='R'` vs
  `'T'` is just a runtime branch, not a separate code path). Both
  `ExtensionsController` and `TrunksController` call the identical
  `loadConfFromDb()` — confirmed the only two call sites in the codebase.
- **Writes**: `file_put_contents()` directly, no atomicity (no
  write-to-temp-then-rename), no locking, no partial-write protection.
  Six files are written per invocation (`snep-{sip,iax2}.conf`, `-trunks`,
  `-hints`), unconditionally, on *every* single create/edit/delete/
  disable/enable of *any* extension or trunk, regardless of which one
  changed.
- **Reload**: three unconditional AMI `Command()` calls
  (`sip reload`, `dialplan reload`, `iax2 reload`) after every write, with
  **no return-value checking at all** — a reload failure today is
  silently swallowed; SENMA has no existing failure-detection pattern to
  preserve, only a baseline to at least match (§10).
- **Delete/rename safety**: safe, *because* generation is a full
  stateless rewrite from the current DB state every time, not an
  incremental diff. A deleted or renamed row simply doesn't appear in the
  next SQL result set — there is no leftover/stale-section risk the way
  there would be with an incremental generator. This property is
  architecturally valuable and worth preserving deliberately, not an
  accident to work around.
- **One logical interface -> multiple Asterisk sections**: **not
  supported today, and not designed for.** The entire method assumes
  "one DB row -> one `[section]`" (or, for IAX2 trunks, one row -> one
  section with a few conditionally-appended lines). There is no loop-
  within-a-loop, no per-row multi-section emission anywhere in the file.

### Explicit answer: extend, or build new behind the existing abstraction?

**There is no existing abstraction to extend.** `Snep_InterfaceConf` is
not an interface with chan_sip and IAX2 as implementations behind it —
it is one hardcoded procedure with an internal `if` per technology. There
is nothing "clean" to extend, because extension means adding a third
`if`-branch to a method that already conflates concerns (SQL fetch +
codec-format transform + trunk/extension branching + text formatting +
reload) for two unrelated technologies in one 219-line function.

**Recommendation: build the PJSIP generator as a new, separate
implementation, called from the same two existing controller call
sites, not as a branch bolted onto `loadConfFromDb()`.** Concretely:

- Add `Snep_PjsipConf::loadConfFromDb()` (name chosen only for
  discussion; final naming is an implementation detail) as its own class,
  with its own SQL fetch, its own per-row-to-multi-section emission logic,
  and its own reload call (`module reload res_pjsip.so`, §10) — because a
  PJSIP row already needs a fundamentally different internal shape (one
  row -> three linked sections, not one row -> one flat stanza), forcing
  it through chan_sip's flat-stanza-shaped code would either (a) require
  restructuring `loadConfFromDb()`'s loop into something generic enough
  for both models — a real refactor of working, validated, chan_sip/IAX2
  code that has nothing to do with PJSIP correctness — or (b) bolt PJSIP
  logic into chan_sip's function via more conditionals, deepening exactly
  the kind of chan_sip-model contamination CLAUDE.md's Phase 6 guidance
  explicitly warns against ("Do not simply map sip.conf sections
  mechanically... preserve the user-facing abstraction... while allowing
  the internal telephony layer to manage the PJSIP objects").
- `ExtensionsController`/`TrunksController` call *both* generators after
  a write (`Snep_InterfaceConf::loadConfFromDb()` for SIP/IAX2 rows,
  `Snep_PjsipConf::loadConfFromDb()` for PJSIP rows) — each generator
  internally filters to its own `canal LIKE` prefix, so calling both
  unconditionally is harmless (a PJSIP-prefixed row is already invisible
  to `Snep_InterfaceConf`'s `LIKE 'SIP%'`/`'IAX2%'` filters today, and
  vice versa — confirmed by reading the exact SQL). This is the smallest
  change to the two controllers (two static calls instead of one) and
  requires zero changes to the proven chan_sip/IAX2 code path.
- The full-stateless-rewrite property (§3, "delete/rename safety") is
  deliberately preserved in the new class, for the same reason it works
  well today.

This is not a line-count-minimization choice (a bolted-on `if` branch
would be fewer lines); it is chosen because it keeps chan_sip's flat
peer-stanza assumptions (one row, one section, `type=friend`-style
matching) from leaking into the PJSIP object model, per the explicit
instruction to prefer that separation.

---

## 4. Configuration strategy

| | A. Flat `pjsip.conf` files | B. Included SENMA-specific PJSIP tree | C. PJSIP realtime (`res_config_odbc`) | D. Hybrid |
|---|---|---|---|---|
| Matches existing SENMA architecture | Yes — literally the same pattern as `Snep_InterfaceConf` today (regenerate-and-reload text files) | Yes, same pattern, one more level of file indirection | No — a fundamentally different model (no generation step, Asterisk queries live) | Partial |
| Atomicity | `file_put_contents()` only, same weak guarantee chan_sip already has (§3) — improvable (write-temp-then-rename) without changing the model | Same as A | Per-row DB transaction is atomic at the SQL level; but Asterisk's own read-and-cache timing around a mid-call config change is a new, unsolved question this project has no precedent for | Same as A/B for the generated part |
| Reload behavior | `module reload res_pjsip.so`, evidence-backed (§10) | Same | Realtime reads happen per-lookup (endpoint identification, registration) without an explicit "reload" for *new rows* in many configurations, but AORs/some cached objects can still require a reload/cache-clear depending on `sorcery.conf` caching — materially less predictable than the file model this project already understands | Same as A/B |
| Rollback | Regenerate from DB = self-healing; a bad write is fixed by writing again from a known-good DB state | Same | Rollback means reverting DB rows directly; a runtime PJSIP realtime bug is harder to reproduce/inspect than a text file diff | Same as A/B |
| Debugging | `cat`/`diff` a plain text file — matches how every other Asterisk config in this project is already debugged | Same, plus an extra include hop to trace | Requires ODBC tracing / `pjsip show endpoint` cache introspection — a materially higher-friction debugging path than TASK-0007/0009 established for this project | Same as A/B |
| Docker filesystem model (TASK-0009) | Fits directly: same `/etc/asterisk/snep/` writable-subtree design already built and validated (senma-config group, setgid) | Fits directly, same subtree, one more subdirectory | No filesystem write needed at all for the generated data — but the *static* transport/global config underneath it still needs the same file model, so the filesystem work from TASK-0009 isn't avoided, only partially bypassed | Fits — reuses the subtree for the static/hybrid parts |
| DB/schema changes required | **None.** `peers` already has every needed column (§2) | **None** | **Significant.** PJSIP realtime's canonical schema (`ps_endpoints`, `ps_auths`, `ps_aors`, ...) is a completely different table family — `ps_endpoints` alone has 60+ possible columns, none of which exist in `peers`. Reusing `peers` directly as a realtime source for `ps_endpoints` isn't how PJSIP realtime works (it expects specific table/column names via `sorcery.conf` mappings) — this would mean designing new tables from scratch, not reusing the queues/queue_members precedent (TASK-0007 §8, which needed *zero* schema changes because those tables *already* matched Asterisk's expected column names by coincidence; PJSIP's realtime schema does not match `peers` at all) | Only for the realtime part, if included |
| Migration risk | Low — mirrors a pattern already proven twice (chan_sip/IAX2 today, and implicitly validated again by TASK-0009's static file success) | Low, marginally more moving parts than A | High — new schema design, new object-lifecycle questions (cache invalidation, see §6 "stale objects"), no existing precedent in this codebase to build on | Medium |
| Future trunk provisioning | Same generator pattern extends naturally (a trunk needs `endpoint`+`auth`+`aor`+possibly `identify`, same building blocks) | Same | Realtime trunk provisioning is a second, separate realtime schema design exercise | Same as A/B |
| Eventual chan_sip-assumption removal | Fully decoupled — a new class, no shared code with `Snep_InterfaceConf` | Same | Same | Same |

**Recommendation: A — a generated flat file, included from the static
`pjsip.conf`** (effectively A+the include-hierarchy already implied by
§5; not meaningfully distinct from B once §5's structure is applied, so
naming it "A" rather than "B" is just which side of a thin line this
falls on). **Not C.** Realtime is explicitly not chosen "merely because
ODBC now works" (per the instruction) — the queues/queue_members
precedent that made realtime attractive in TASK-0007 doesn't transfer:
that precedent's entire value was "zero schema changes needed because the
column names already matched," and that is specifically **not** true for
PJSIP's `ps_endpoints`/`ps_auths`/`ps_aors` schema. Choosing realtime here
would mean taking on a new schema design *and* a new object-lifecycle
model simultaneously, on top of the already-nontrivial one-row-to-three-
objects change (§3) — compounding two hard problems where the file-based
approach only requires solving one, using a reload mechanism already
proven in TASK-0009. Realtime remains a legitimate *future* optimization
once the flat-file generator is proven correct in production, exactly the
same staging TASK-0008 already recommended and TASK-0009 already followed
for the runtime side.

---

## 5. Configuration ownership

```
/etc/asterisk/pjsip.conf                         <- project-owned, static, ships in docker/asterisk-config/
    #include pjsip_transports.conf                <- project-owned, static (transport-udp, and any future transport-tls/wss)
    #include snep/snep-pjsip.conf                  <- SENMA-generated, written by the new PJSIP generator
    #include snep/snep-pjsip-trunks.conf           <- SENMA-generated (future trunk work, not this milestone)
```

- **Project-owned/static**: the top-level `pjsip.conf` and a small
  `pjsip_transports.conf` (or equivalent) holding `[transport-udp]`
  (and, later, TLS/WSS transports — explicitly deferred, §15). These ship
  from `docker/asterisk-config/` exactly like today's `modules.conf`/
  `res_odbc.conf`, copied in by `asterisk-entrypoint.sh`'s existing
  first-boot block.
- **SENMA-generated**: `snep-pjsip.conf` (extensions) and
  `snep-pjsip-trunks.conf` (future), living in `/etc/asterisk/snep/` —
  the *exact* subtree TASK-0009 already made group-writable
  (`senma-config` group, GID 3000, setgid `2775`) for precisely this
  purpose. No new filesystem work is required; TASK-0009 built this
  ahead of schedule for this reason.
- **Include hierarchy**: matches the diagram above. `#include` is
  Asterisk's own native config-file mechanism (already used by
  `extensions.conf` for `custom/preagi.conf` etc., and by the legacy
  chan_sip files for `snep-sip-trunks.conf`) — no new mechanism to
  introduce.
- **File paths**: `/etc/asterisk/pjsip.conf` (static, entrypoint-deployed,
  same as today's other `docker/asterisk-config/*.conf` files),
  `/etc/asterisk/pjsip_transports.conf` (static, same origin),
  `/etc/asterisk/snep/snep-pjsip.conf` (generated, SENMA-writable
  subtree).
- **Ownership/permissions**: unchanged from TASK-0009. `asterisk-
  entrypoint.sh` owns the static files (asterisk:asterisk); the app
  container's `www-data` (via the shared `senma-config` group) writes
  only inside `/etc/asterisk/snep/`.
- **Reload mechanism**: `module reload res_pjsip.so` (§10) picks up
  changes from the whole include tree in one pass — no per-include
  reload granularity is needed or available in PJSIP's sorcery config
  loader.

**TASK-0009's test endpoints removability**: today they live directly in
`docker/asterisk-config/pjsip.conf` (§4 of TASK-0009's own doc explicitly
marks that file test/bootstrap-only). Once this include hierarchy exists,
the 1000/1001 `[endpoint]`/`[auth]`/`[aor]` stanzas move out of the
top-level static file entirely — either deleted outright once TASK-0011's
SENMA-provisioned endpoints replace them in `make call-smoke` (§14), or,
if kept temporarily for manual debugging, moved to a separately-named,
clearly-marked static include (e.g. `pjsip_dev_endpoints.conf`) that is
easy to delete as one file, never mixed into the generated file. Either
way, **production provisioning must not depend on anything defined in a
static file** — the generated file must be a fully self-sufficient source
of every real endpoint.

---

## 6. Object identity

**Recommendation: endpoint, aor, and (for auth only) a suffixed name,
derived deterministically from `peers.name`:**

```
endpoint: <peers.name>          e.g. 1000
aor:      <peers.name>          e.g. 1000    (MUST equal the endpoint name)
auth:     <peers.name>-auth     e.g. 1000-auth
```

This is not arbitrary — it is the exact pattern already implemented and
proven working in TASK-0009 (`docker/asterisk-config/pjsip.conf`'s
`[1000]` used for both `type=endpoint` and `type=aor`), for a load-bearing
reason discovered empirically during that task: **`res_pjsip_registrar`
looks up the AOR to register a contact against by matching the REGISTER
request's URI username directly against an AOR object's own sorcery
name** — not merely "any AOR listed in the endpoint's `aors=`". Naming the
AOR anything other than the endpoint/extension name (e.g. the originally-
tried `1000-aor`) produced a real, reproduced `404 Not Found` /
`"AOR '' not found for endpoint '1000'"`. So `aor == name` is not a style
preference, it is a functional requirement for registration to work at
all. `auth` has no such constraint (it's referenced by name via the
endpoint's own `auth=`/`outbound_auth=`, looked up directly, not by
URI-matching), so suffixing it avoids any possible collision with the
endpoint/aor namespace while staying human-readable and consistent with
what's already deployed.

Also matches `peers.name`'s existing role as the chan_sip section name
today (`Snep_InterfaceConf.php:177`, `'[' . $peer['name'] . "]\n"`) — so
this is a continuation of an existing naming convention, not a new one.

### Behavior

- **Create**: emit all three new sections named from `peers.name`.
- **Rename**: not reachable through the current UI (§1 — `editAction()`
  always forces `exten` back to the original `id`). If ever exposed
  (direct API, future UI change), the full-stateless-regeneration model
  (§3) handles it for free — the old-named sections simply don't appear
  in the next generated file, and new ones do, with no explicit
  "rename" logic needed in the generator itself.
- **Delete**: same — the deleted row's sections stop being emitted on the
  next regeneration. No explicit cleanup step needed, by the same
  full-rewrite property.
- **Extension-number change**: not currently possible via the UI (§1);
  if ever added, it is identical to rename above.
- **Stale objects**: cannot occur with the flat-file, full-rewrite model
  (§3/§4) — every regeneration reflects exactly the current `peers` table,
  with nothing left over from a previous run. This is one of the concrete
  reasons §4 recommends the file-based approach over realtime, where
  stale-object/cache-invalidation is a real, currently-unsolved question
  for this codebase.
- **Duplicate usernames / duplicate endpoint IDs**: already structurally
  prevented, for free, by `peers.name`'s existing `UNIQUE KEY` (schema.sql)
  *and* `execAdd`'s own pre-check (`SELECT * FROM peers WHERE name =
  '$exten'`, returning a friendly translated error before any write is
  attempted). Since the recommended endpoint/aor name is `peers.name`
  verbatim, no *new* duplicate-checking logic is required — the existing
  guard already fully covers it, including preventing a PJSIP extension
  "1000" from being created while a SIP extension "1000" still exists
  (same `name` value, same guard, technology-agnostic).

---

## 7. Password/secrets

Traced through `ExtensionsController::addAction()`/`execAdd()` and
`addedit.phtml`:

- **Generated**: client-side only, via `password.js`'s JS RNG (a "generate
  password" convenience button described in `ExtensionsController::
  generatorPassword()`, which — note — is dead server-side code; the
  actual generation the UI uses is the JS function around
  `addedit.phtml:495-500`, not a PHP call). No server-side generation path
  exists for the SIP secret at all; whatever the browser submits (typed or
  JS-generated) is what gets stored.
- **Stored**: `peers.secret`, `VARCHAR(80)`, **plaintext, no hashing**.
  `execAdd`: `$secret = $formData["password"]`, written verbatim into the
  raw SQL INSERT/UPDATE string.
  `peers.md5secret` exists in the schema but is **never populated** by
  `execAdd` — confirmed dead, `auth_type=userpass` (plaintext) is the only
  mode this codebase has ever actually used.
- **Displayed**: **round-tripped in plaintext** back into the edit form —
  `addedit.phtml:99`, `value="<?php echo $this->extension['secret'];?>"`
  inside an `<input type="password">` (browser-side masking only; the
  literal plaintext secret is present in the rendered HTML source on
  every edit-page load). Pre-existing behavior, not something this task
  changes or needs to change.
- **Edited**: same `execAdd()` path as create — a plaintext value fully
  overwrites the stored plaintext value, no "leave unchanged if blank"
  special case was found (worth flagging separately if that's ever a
  desired edit-UX improvement — out of scope here).
- **Written to config**: verbatim, `secret=` in the chan_sip stanza today.

### Can the existing storage feed PJSIP auth without a schema change?

**Yes.** PJSIP's `auth_type=userpass` mode needs exactly what `peers.secret`
already stores: a plaintext password, server-side, no digest
precomputation. This is a direct, zero-translation mapping:
`[<name>-auth] type=auth auth_type=userpass username=<name>
password=<peers.secret>`. No schema change, no re-authentication redesign,
matching the explicit instruction not to redesign authentication unless
required — it is not required.

---

## 8. Codec mapping

Traced: `PBX_Interfaces::getCodecs()` (`snep/lib/PBX/Interfaces.php`) is
the **live** codec source both the add and edit forms already use — it
runs AMI `core show codecs` against the real, currently-running Asterisk
and parses the result, so the extensions form's codec dropdowns already
only ever offer codecs the actual running build supports. This is
technology-agnostic (`core show codecs` lists Asterisk's core format
registry, not a per-channel-driver list) and **needs no change for
PJSIP** — confirmed by the TASK-0009 boot log, which registered the same
core codec set (`ulaw`, `alaw`, `gsm`, `g726`, `g722`, `ilbc`, `g729`,
`speex`, `opus`, etc.) independent of which channel driver is loaded.

**DB representation**: `peers.allow`/`peers.disallow`, `;`-separated
(`ulaw;alaw;gsm`), populated from the 3 codec `<select>`s
(`$formData['codec']`, `codec1`, `codec2`).

**chan_sip config syntax**: comma-separated (`allow=ulaw,alaw,gsm`).
**PJSIP config syntax**: also comma-separated, **identical** to chan_sip's
own syntax — codec/format names are core Asterisk identifiers, not
channel-driver-specific.

**The translation SENMA needs already exists and is already correct**:
`Snep_InterfaceConf.php:83-90` already explodes the DB's `;`-joined string
and rejoins it with `,` before writing chan_sip's `allow=` line. That
exact logic is reused verbatim for a PJSIP generator — **no new codec
mapping code is required**, only calling the same transformation from the
new class.

**Ordering**: preserved as-is — codec preference order in both chan_sip's
and PJSIP's `allow=` is the order codecs are listed, and the DB's 3-slot
`codec;codec1;codec2` ordering already encodes SENMA's own preference
order; nothing about PJSIP changes this.

**Defaults**: unchanged — `ulaw;alaw;gsm` default at DB level (schema.sql),
alaw/ulaw/gsm pre-selected in the add form.

**Legacy codec values that should no longer be emitted**: none identified
as PJSIP-incompatible. The audit found no chan_sip-only codec name in use
anywhere in this codebase (no `g723`/proprietary/video-only values
hardcoded in the extensions form); whatever `core show codecs` reports on
a given build is what's offered, and that already excludes anything not
actually compiled in. No UI change needed here, matching the instruction
not to change the UI for this item.

---

## 9. NAT/direct-media mapping

Live PJSIP endpoint defaults, captured directly from `pjsip show endpoint
1000`'s full parameter dump during TASK-0009 validation (Asterisk
22.10.1, this project's exact build) — used here as the authoritative
option-name/default source, not assumed from general PJSIP knowledge:

```
force_rport                   : true    (endpoint default)
rewrite_contact               : false   (endpoint default)
rtp_symmetric                 : false   (endpoint default)
direct_media                  : false   (endpoint default)
direct_media_method           : invite  (endpoint default)
disable_direct_media_on_nat   : false   (endpoint default)
```

### Evidence-backed mappings (direct option-name or well-established conceptual correspondence)

| SENMA `nat` value (any of, comma-combinable) | PJSIP mapping | Basis |
|---|---|---|
| `force_rport` | `force_rport=yes` | **Identical option name** in both chan_sip and PJSIP — a direct rename, not an interpretation |
| `comedia` | `rtp_symmetric=yes` | Well-established Asterisk-wide correspondence: chan_sip's "comedia" (COMEDIA RFC 4961 symmetric-RTP learning) *is* what `rtp_symmetric` implements in PJSIP; both are documented as solving the same NAT-traversal mechanism |
| `no` (or absent) | `force_rport=no`, `rtp_symmetric=no` | Direct — no NAT handling requested |

### Explicit, flagged interpretive choices (not silently invented, but not a literal 1:1 either)

- **`auto_force_rport` / `auto_comedia`**: chan_sip's "auto" variants mean
  "decide based on whether the incoming request already carries an
  `rport` parameter." PJSIP's `force_rport`/`rtp_symmetric` are plain
  booleans with **no "auto" mode**. Recommended treatment: collapse
  `auto_force_rport` into `force_rport=yes` and `auto_comedia` into
  `rtp_symmetric=yes` (i.e., treat "auto" as "yes" for these two flags) —
  this is a **deliberate application-level simplification**, not a
  discovered equivalence, and is called out as such rather than presented
  as fact.
- **`rewrite_contact`**: has **no source field in `peers` at all** — no
  existing SENMA NAT checkbox maps to it conceptually or by name. Since
  Asterisk's own PJSIP documentation generally recommends
  `rewrite_contact=yes` alongside `force_rport`/`rtp_symmetric` for
  typical NAT'd endpoints (rewriting the registered Contact to the
  packet's actual source), the **explicit new choice** proposed here is:
  set `rewrite_contact=yes` whenever *any* `nat_*` checkbox was set (i.e.
  whenever the resulting `nat` value isn't `no`), and `no` otherwise. This
  is a genuinely new mapping this task is introducing, not one "derived"
  from existing data — flagged plainly as a product decision for
  TASK-0011 to confirm before implementing, not assumed here.
- **`directmedia=nonat`**: chan_sip's documented meaning is "allow direct
  media, but disable it specifically when NAT is detected." Maps
  cleanly to `direct_media=yes` + `disable_direct_media_on_nat=yes`.
- **`directmedia=update`**: maps to `direct_media=yes` +
  `direct_media_method=update` — a direct, named correspondence.
- **`directmedia=yes`**: maps to `direct_media=yes` (no NAT-disable, no
  method override).
- **`directmedia=no`**: maps to `direct_media=no`.
- **`directmedia=outgoing`** (only allow direct media on outgoing legs):
  **has no PJSIP equivalent.** PJSIP's `direct_media` is not
  direction-scoped. Recommended treatment: **do not silently approximate
  this one** — either (a) map it to `direct_media=no` (the conservative,
  behavior-preserving-by-omission choice, since "sometimes allow" ⊄
  "always allow") and document the feature loss explicitly, or (b) require
  an explicit product decision before TASK-0011 implements it. This
  document does not choose between (a)/(b) — it flags the gap rather than
  picking silently, per the instruction.
- **`qualify=yes`/`no`** (§2): boolean-to-interval translation.
  `qualify=no` -> `qualify_frequency=0` (disabled, a direct/literal
  translation — 0 means "off" in PJSIP exactly as it does conceptually in
  chan_sip). `qualify=yes` -> a *chosen* interval, since chan_sip's
  boolean carries no interval value to reuse. **60 seconds** is proposed
  (Asterisk's own long-standing conventional default for OPTIONS
  keepalive), but this is an explicit new application-level choice, not a
  value derived from any existing DB field — flagged as such rather than
  presented as evidence-backed.

---

## 10. Reload strategy

Traced current mechanism: `PBX_Asterisk_AMI::getInstance()->Command("sip
reload")` / `Command("iax2 reload")` — chan_sip/chan_iax2-specific CLI
commands with no PJSIP equivalent (there is no `pjsip reload` command at
all).

**Directly tested during TASK-0009 validation** (not a documentation
lookup — an actual live command against this exact Asterisk 22.10.1
build):

```
$ asterisk -rx "pjsip reload"
No such command 'pjsip reload' (type 'core show help pjsip reload' for other possible commands)

$ asterisk -rx "module reload res_pjsip.so"
Module 'res_pjsip.so' reloaded successfully.
```

The `module reload` correctly picked up a real config change during that
same validation (the AOR-naming fix, §6) — confirmed by `pjsip show
endpoints` reflecting the corrected AOR name immediately afterward, with
no process restart. **`module reload res_pjsip.so` is the smallest,
evidence-backed, already-proven mechanism.** It reloads the entire PJSIP
config tree in one pass (transports, endpoints, auths, aors, identifies)
— there is no more granular reload unit available in Asterisk's PJSIP
sorcery config loader, so "smallest safe mechanism" here means "smallest
available," not a sub-file-level reload.

A full Asterisk reload (`core reload`/restart) is unnecessary and not
recommended — it would also reload chan_sip/dialplan/every other
subsystem for a PJSIP-only config change, a strictly larger blast radius
than today's chan_sip pattern already avoids (today's `sip reload` is
itself scoped to chan_sip only, not a full reload; a PJSIP generator
should hold the same discipline).

**Failure detection — a real, pre-existing gap, not something to silently
match-and-forget**: `Snep_InterfaceConf::loadConfFromDb()` **never checks
any of its three `Command()` return values today** (§3) — a reload
failure is currently invisible to SENMA entirely. This is documented here
as the honest baseline, not held up as a pattern to imitate uncritically.
For the PJSIP generator, `PBX_Asterisk_AMI::Command()`'s response
(`['data']`, per TASK-0006B's parsing fix) contains Asterisk's own CLI
output text (`"Module 'res_pjsip.so' reloaded successfully."` on success;
a distinct string on failure, e.g. `"No such module 'res_pjsip.so'"` if
the module were somehow unloaded). **Proposed minimum improvement** (an
explicit new choice, not inherited from existing code): check the
returned text for the known success substring and log (at minimum) if it
doesn't match, so a broken PJSIP reload is at least visible in SENMA's own
logs — matching or modestly exceeding today's baseline, never silently
worse.

---

## 11. Migration compatibility

**Coexistence is already proven safe, not just theoretically possible.**
`PBX_Usuarios::get()`'s tech dispatch (`substr($usuario->canal, 0,
strpos($usuario->canal, '/'))`) already branches on `SIP`/`PJSIP`/`IAX2`/
`MANUAL`/`VIRTUAL`/`KHOMP` as fully independent, coexisting cases — this
is exactly what TASK-0009 already validated live (a `PJSIP/1000` row
alongside an empty `peers` table otherwise; nothing about adding it
required touching or disrupting any SIP-row code path).

**What does *not* yet coexist**: only the *generator*.
`Snep_InterfaceConf::loadConfFromDb()`'s per-tech loop is
`array("sip","iax2")` — a `peers` row with `canal='PJSIP/...'` matches
neither `LIKE 'SIP%'` nor `LIKE 'IAX2%'` (confirmed by reading the exact
SQL, not assumed — `'PJSIP/1000' LIKE 'SIP%'` is false, it doesn't start
with `SIP`), so such a row is **silently, harmlessly ignored** by today's
generator — no error, no corruption, just no generated config for it
until §3's new class exists. This confirms a staged rollout needs no
"flag day": the new PJSIP generator can be introduced, called
additionally (not instead) from the same two controllers, with zero risk
to existing SIP/IAX2 rows or their generated config.

**Where `canal`/tech assumptions would block coexistence, found and
already resolved or explicitly not blocking**:

- `IpStatusController`'s `canal LIKE 'SIP%'` filter (flagged already in
  TASK-0008 §8) — a **display/status gap only** (a PJSIP extension simply
  won't show up on that status page yet), not a functional blocker to
  provisioning or calling. Fixing it is a small, independent, low-risk
  follow-up, not a prerequisite for TASK-0011.
- `snep/includes/AMI.php`'s `get_sippeer()` (TASK-0008 §8) — same
  category, status/monitoring only, not a provisioning blocker.
- `peers.name`'s `UNIQUE KEY` — **prevents**, by design, a SIP row and a
  PJSIP row from ever sharing the same extension number simultaneously.
  This is correct, desired behavior (one physical extension = one
  technology at a time), not a defect to work around.
- `DiscarRamal`'s diff-ring `SIPAddHeader` branch (TASK-0008 §3/§8) —
  already confirmed in TASK-0009's own validation to be a **safe no-op**
  for PJSIP rows (the `if ($tech == "SIP")` gate simply doesn't fire; the
  call succeeds without the distinctive-ring header). Not a coexistence
  blocker, a feature gap already known and accepted.

No schema change, no new coexistence flag, and no "migration mode" switch
are needed. A staged migration is simply: (1) ship the PJSIP generator
additively, (2) let new/converted extensions use it, (3) leave every
existing SIP/IAX2 row and code path completely untouched, indefinitely if
desired.

---

## 12. UI impact

Traced against `addedit.phtml` and its `showDiv()` JS (technology
`<select>` currently offers exactly `sip`/`iax2`/`khomp`/`virtual`/
`manual` — no `pjsip` option exists yet).

| Field/group | Classification | Notes |
|---|---|---|
| Extension number, callerid, email | **A — reusable unchanged** | No tech dependency |
| "password" (secret), "passwordpadlock" | **A — reusable unchanged** | §7 — same storage, same form fields |
| Codec selects (`codec`/`codec1`/`codec2`) | **A — reusable unchanged** | §8 — identical syntax, identical live-codec source |
| `qualify` checkbox | **B — reusable, different mapping** | UI stays a checkbox; server-side maps to `qualify_frequency` (§9) instead of chan_sip's `qualify=` |
| `nat_*` checkboxes (the `siponly` div) | **B — reusable, different mapping** | Same checkboxes, shown for `pjsip` too (extend `showDiv()`'s `div=='sip'` condition to include `'pjsip'`); server-side splits into `force_rport`/`rtp_symmetric`/`rewrite_contact` (§9) instead of a combined `nat=` string |
| `directmedia` radio | **B — reusable, different mapping** | Same 5 radio options; server-side splits per §9, with `outgoing` needing the explicit decision flagged there before it can be wired up |
| `dtmf` radio | **A — reusable unchanged** | Same 3 values, same option names in PJSIP (`dtmf_mode=`) |
| `type` (friend/peer/user) radio | **C — hide/remove for PJSIP** | No PJSIP equivalent (§2); hide this control block entirely when `technology=pjsip` |
| `host`-related concepts (always `dynamic`, not directly exposed) | **C — hide/remove for PJSIP** | No PJSIP equivalent as a field; nothing to hide in the UI since it was never a visible field, but the hidden `'dynamic'` default in `execAdd`'s insert must not be carried into the PJSIP generator's assumptions |
| `insecure`/`deny`/`permit`/`mask` | **C — already not exposed** | Confirmed dead for extensions already (§2); no UI work needed either way |
| Everything else (voicemail, groups, pickup group, follow-me, cancallforward, minute control, BLF, khomp/virtual/manual-specific fields) | **A — reusable unchanged** | None of these are chan_sip/PJSIP-specific; they operate identically regardless of channel technology (§2, §11) |
| Technology `<select>` itself | **D — new field required (an added option, not a new field)** | Add a `pjsip` `<option>`; extend `showDiv()` so `div=='pjsip'` shows the same `sipiax` and `siponly` divs `sip` already shows (reusing the existing field groups per the table above, not building new ones) |

**No new field is required beyond the one new `<option>` in the existing
technology dropdown.** This is deliberately not a UI redesign — matching
the instruction — because §2's field-by-field trace found that PJSIP
extensions need a subset of fields chan_sip extensions already collect,
mapped differently server-side, not new data collected from the user.

---

## 13. Proposed TASK-0011 scope (smallest next milestone)

```
Create extension 1002 through SENMA's existing ExtensionsController (real
  HTTP POST to addAction, technology=pjsip)
  -> peers row persisted (canal='PJSIP/1002')
  -> new PJSIP generator (§3) emits [1002]/[1002-auth] endpoint/auth/aor
     into snep-pjsip.conf
  -> module reload res_pjsip.so (§10) succeeds
  -> 1002 registers (a disposable baresip container, same pattern as
     TASK-0009's call-smoke tooling)
Create/provision extension 1003 the same way
1002 calls 1003 through the existing, unmodified AGI/rule engine
  (the already-seeded "Internas - Ramal para Ramal" rule; PBX_Usuarios,
  PBX_Asterisk_Interface_PJSIP already exist and are unmodified)
Real cdr_adaptive_odbc CDR row written
SENMA's existing CallsReport endpoint reads it back
```

**In scope for TASK-0011**: the new PJSIP generator class (§3) covering
exactly the field set in §2's matrix for `peer_type='R'` rows only (no
trunk branch yet); the `technology=pjsip` UI addition (§12); the reload
call + minimal failure logging (§10); wiring both generators into
`ExtensionsController` (§3's "call both" recommendation); removing (or
relocating to an explicitly separate dev-only file, §5) the TASK-0009
static test endpoints once SENMA-provisioned 1002/1003 replace them in
validation.

**Explicitly not in TASK-0011** (mirrors §15 exactly): PJSIP trunks
(`TrunksController`'s own generator branch is a separate, later task),
outbound registrations, inbound trunk identification, voicemail-over-
PJSIP specifics beyond what already works technology-agnostically,
queues beyond what TASK-0007 already validated, IVR, WebRTC, TLS/WSS
transports, PostgreSQL, and any schema change (§2/§4 found none
necessary).

---

## 14. Automated validation evolution

`make call-smoke` (TASK-0009) currently depends on two permanently
static, hand-written `pjsip.conf` stanzas and directly-inserted `peers`
fixture rows (clearly marked, `secret='task0009-fixture'`, create-if-
absent-else-stop-on-conflict). Once TASK-0011 exists, the test should
prove **provisioning**, not just calling.

**Recommendation: drive fixture creation through
`ExtensionsController`'s real HTTP flow** (a `curl`/session-cookie POST
to `addAction`, exactly matching how `scripts/smoke-test.sh` already
authenticates and drives the app for its own HTTP checks), not the
internal API (`modules/default/api/...` has no extension-write endpoint
today, only `CallsReport`-style read services — confirmed by inspection,
introducing a new write-capable API surface purely for testing would be
scope creep) and not direct DB insertion (that proves the generator can
render *a* row, not that the actual user-facing create flow — the thing
TASK-0011 is supposed to prove — works end-to-end).

Concretely, `call-smoke` should evolve to:

1. Log in as the existing smoke-test admin account (same pattern as
   `scripts/smoke-test.sh`).
2. POST to `/index.php/default/extensions/add` with
   `technology=pjsip` and the minimum required fields for extensions
   1002/1003, asserting the redirect indicates success (mirroring how
   `execAdd`'s caller already distinguishes success from a string error
   message).
3. Assert the generated `snep-pjsip.conf` contains the expected sections
   (or, preferably, assert behavior rather than text: proceed directly to
   registration).
4. Everything from "endpoint 1002 registered" onward is unchanged from
   today's `call-smoke` structure (§14 of TASK-0009's own doc) — same
   baresip container pattern, same CDR/report-readback checks.
5. Cleanup: delete extensions 1002/1003 through the same
   `ExtensionsController::removeAction()` HTTP flow (proving delete-then-
   regenerate also works, not just create), falling back to direct DB
   cleanup only if the HTTP delete flow itself is what's under test and
   fails.

This is a deliberately higher-friction test than a direct DB insert, by
design — the instruction is explicit that the goal is proving
provisioning actually works, and the highest-value, highest-fidelity way
to prove that is the same interface a real administrator uses.

---

## 15. Explicitly deferred scope

Unchanged from the instruction, restated for completeness as this
document's own scope boundary:

- PJSIP trunks (a separate `TrunksController`/trunk-generator design
  exercise; `Snep_InterfaceConf`'s trunk branch is materially more
  complex than its extension branch, §3, and deserves its own task).
- Outbound registrations.
- Inbound trunk identification.
- Voicemail migration beyond what already works technology-agnostically
  (§2 — voicemail was never wired through the channel driver's own config
  either way).
- Queues migration beyond the already-working realtime
  `queues`/`queue_members` (TASK-0007).
- IVR changes.
- WebRTC.
- TLS/WSS transports.
- PostgreSQL.
- Schema redesign — **not needed anywhere in this design** (§2, §4, §7
  each independently confirm the existing `peers` schema is sufficient).

---

## 16. Explicit architectural recommendation

**Build a new, standalone PJSIP configuration generator
(tentatively `Snep_PjsipConf`) that emits a flat, SENMA-generated
`snep-pjsip.conf` file included from a small, static, project-owned
`pjsip.conf` — reusing the existing `/etc/asterisk/snep/` writable
subtree TASK-0009 already built, reusing `peers.name` as the deterministic
endpoint/AOR identity (with a `-auth` suffix for the auth object),
reloading via `module reload res_pjsip.so`, and called additively
alongside the existing, completely untouched `Snep_InterfaceConf` from
both `ExtensionsController` and (later) `TrunksController`. Do not extend
`Snep_InterfaceConf` itself, and do not use PJSIP realtime for this
milestone.**

This follows directly from the evidence gathered: `Snep_InterfaceConf` is
a single hardcoded procedure with no abstraction to extend cleanly (§3);
the `peers` schema already contains everything a PJSIP extension needs
with zero schema changes, for provisioning (§2), codecs (§8), and
authentication (§7) alike; the flat-file model is the only option of the
four compared that avoids compounding the one-row-to-three-objects change
with a second, independent hard problem (a new realtime schema and
object-lifecycle model, §4); the reload mechanism is already
experimentally proven (§10); the filesystem/permission architecture is
already built and validated (§5, TASK-0009); and coexistence with every
existing SIP/IAX2 row requires no flag day, no schema change, and no new
runtime branch beyond what TASK-0009 already added (§11). The two areas
where mechanical translation would be genuinely dangerous — NAT/direct-
media (§9) and the `type`/`host` chan_sip-only concepts (§2) — are called
out with explicit, separately-flagged interpretive choices rather than
silently folded into "just works," so TASK-0011 can implement from a
design that already knows exactly which parts are evidence and which
parts are a deliberate new product decision.

---

Stopping here for approval. No PJSIP provisioning was implemented.
