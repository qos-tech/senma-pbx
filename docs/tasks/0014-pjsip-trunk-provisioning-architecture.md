# TASK-0014 — PJSIP trunk provisioning architecture

## Status

**Investigation/design only. No runtime code, schema, or Docker
configuration was changed.** Two temporary rows (one `trunks`, one
`peers`) were inserted directly via SQL purely to empirically confirm
the P0-2 blocker below, then deleted in the same session — `git status`
is clean and both tables are back to their pre-audit state (verified:
`SELECT COUNT(*) FROM trunks` = 0, no stray `peers` row). `make smoke`/
`make call-smoke` were not affected or re-run (nothing here touches
extensions, base-path, or PJSIP extension provisioning). This document
builds on TASK-0007 (ODBC/CDR), TASK-0008 (legacy telephony audit),
TASK-0009 (first real PJSIP call), TASK-0010/0011 (PJSIP extension
provisioning architecture + implementation), and TASK-0012/0013
(unrelated web/PHP fixes, cited only where they establish precedent).

---

## Two independent P0 blockers found during this audit

Both were found empirically, against the running dev stack, using the
real SENMA UI/HTTP flow and (for P0-2) a minimal, reversible, directly-
deleted SQL test — not by reading code alone. **Neither is fixed by this
task.** Per CLAUDE.md's bug policy ("when a pre-existing bug unrelated to
the current migration task is discovered: do not fix it opportunistically,
document it, create or propose a dedicated future task"), both are
recorded here and assigned to the "prerequisite fixes" step in the
dependency sequence at the end of this document, before TASK-0015 can
begin.

### P0-1 — `Telcos_Manager::getAll()` called statically, not declared static

- **File/class/method**: `snep/modules/billing/lib/Telcos/Manager.php:20`
  (`Telcos_Manager::getAll()`, a plain instance method, no `static`
  keyword, uses no `$this`), called statically from
  `snep/modules/default/controllers/TrunksController.php:202`
  (`addAction()`) and `:310` (`editAction()`):
  `if (class_exists("Telcos_Manager")) { $this->view->telcos =
  Telcos_Manager::getAll(); }`.
- **Exact runtime failure**, reproduced live (`GET
  /index.php/default/trunks/add`, authenticated):
  ```
  PHP Fatal error:  Uncaught Error: Non-static method Telcos_Manager::getAll()
  cannot be called statically in
  /var/www/html/snep/modules/default/controllers/TrunksController.php:202
  Stack trace:
  #0 /var/www/html/snep/lib/Zend/Controller/Action.php(516): TrunksController->addAction()
  ...
  ```
  HTTP 500, empty body. This is the exact same class of bug already
  fixed elsewhere in this codebase under TASK-0002/0004's "non-static
  method called statically" pattern (CLAUDE.md's Phase 2 classification
  A/B) — it simply was never fixed in the billing module's trunk-facing
  code path, because nothing before this audit ever loaded the trunk
  add/edit form with the billing module active.
- **Technology-agnostic or PJSIP-specific**: **entirely
  technology-agnostic.** It fires on `addAction()`/`editAction()`'s
  initial `GET` (form render), before any technology is even selected —
  it would block creating/editing a plain chan_sip trunk exactly as much
  as a future PJSIP one.
- **Why it blocks TASK-0015**: TASK-0015's whole premise is "create a
  trunk through SENMA's real HTTP flow" (matching TASK-0011's precedent
  for extensions). The add/edit form cannot render at all today — there
  is no form to POST to, and no way to reach `preparePost()`/the DB
  insert layer through the UI until this is fixed.
- **Proposed smallest future fix**: add `static` to
  `Telcos_Manager::getAll()`'s declaration (it already uses no `$this`,
  confirmed by reading the full method body) — a one-keyword change,
  identical in shape to every other TASK-0002/0004 "declare it static, it
  already doesn't use `$this`" fix already applied elsewhere in this
  codebase. Do not also convert every other method in `Telcos_Manager`
  without individually verifying each one uses no `$this` first, per
  CLAUDE.md's "Static method migration" static-analysis rule.
- **Validation required**: `php -l` on the touched file; `GET
  /index.php/default/trunks/add` and `/trunks/edit/trunk/<id>` both
  return `200` and render the form (not `500`); `make smoke`'s existing
  `trunks` check (list page only) stays green; a real trunk add/edit
  round-trip via HTTP.
- **Why not fixed inside TASK-0014**: TASK-0014 is investigation/design
  only, explicitly forbidden from editing runtime code. This is also a
  billing-module PHP 8 compatibility bug, not a PJSIP architecture
  decision — fixing it belongs with the rest of this project's PHP
  8.4-compatibility lineage (TASK-0002/0004's pattern), not folded into a
  PJSIP task.

### P0-2 — trunk creation cannot persist under strict MariaDB (three chained `NOT NULL`-no-default columns)

- **File/class/method**: `TrunksController::preparePost()`
  (`snep/modules/default/controllers/TrunksController.php:521-664`),
  specifically its `$ip_fields` allow-list (line 534) and the loop that
  builds `$ip_data` (the array later passed to `Zend_Db::insert("peers",
  ...)` at `addAction()` line 244 / `Zend_Db::update("peers", ...)` at
  `editAction()` line 433) for any `trunktype == "I"` (SIP/IAX2/SNEPSIP/
  SNEPIAX2) trunk.
- **Exact runtime failure**: `$ip_fields` never includes `password`,
  `trunk`, or `lastms`, and no other code path in `preparePost()` sets
  any of these three keys either — so `$ip_data` never contains them, and
  the generated `INSERT INTO peers (...)` omits all three columns.
  `snep/install/database/schema.sql` declares all three `NOT NULL` with
  **no `DEFAULT` clause**:
  ```
  `password` VARCHAR(12) NOT NULL,          -- line 175
  `trunk` varchar(3) NOT NULL,               -- line 223
  `lastms` int(11) NOT NULL,                 -- line 230
  ```
  and the running dev DB's `sql_mode` includes `STRICT_TRANS_TABLES`
  (confirmed live: `SELECT @@sql_mode`). Reproduced directly via a
  minimal, immediately-deleted test insert reconstructing exactly what
  `preparePost()`'s `$ip_data` would contain for a plain SIP/`dialmethod=
  normal` trunk (full column list omitted below for brevity — see the
  session's own test SQL): the first attempt (all `$ip_fields` columns
  present, nothing else) failed with
  `ERROR 1364 (HY000): Field 'password' doesn't have a default value`;
  adding `password` next failed with
  `Field 'trunk' doesn't have a default value`; adding `trunk` next
  failed with `Field 'lastms' doesn't have a default value`. All three
  are real, all three are needed, in that order. Both test rows were
  deleted immediately after confirming the last failure; no residue in
  either table.
- **Technology-agnostic or PJSIP-specific**: **entirely
  technology-agnostic.** This is the `peers` INSERT/UPDATE for **any**
  `trunktype == "I"` row — chan_sip, chan_iax2, and (once it exists)
  PJSIP trunks would all hit it identically. It is the exact same class
  of bug TASK-0011 already found and fixed for **extensions**'
  `ExtensionsController::execAdd()` INSERT (`peers.lastms` there too,
  fixed by adding it to that INSERT's explicit column list) — that fix
  was scoped to `execAdd()` only and never touched
  `TrunksController::preparePost()`'s separate INSERT/UPDATE, so the twin
  bug survived untouched in the trunk code path, plus two *additional*
  missing columns (`password`, `trunk`) that extensions' own INSERT
  already happened to include.
- **Why it blocks TASK-0015**: even after P0-1 is fixed and the trunk
  form renders, submitting it for any IP-technology trunk
  (SIP/IAX2/SNEPSIP/SNEPIAX2 — i.e. every technology TASK-0015 cares
  about) will fail at the database layer with a `PDOException`/
  `SQLSTATE[HY000]` 1364 before a `peers` row (and thus a dial-able
  `canal`) ever exists. `Snep_PjsipConf`/`Snep_PjsipTrunkConf` (§ below)
  both key their generation off `peers` rows — no row, no generated
  config, no endpoint to reload or register.
- **Proposed smallest future fix**: add `password`, `trunk`, and
  `lastms` to `$ip_fields` (or otherwise ensure `$ip_data` always
  contains them) with the same safe placeholder values TASK-0011 already
  established for extensions (`lastms => 0`, matching "never qualified"
  chan_sip peers' own placeholder state; `password => ''`, since — like
  extensions — this column is unrelated to the SIP/IAX2 auth secret,
  it's the separate numeric-PIN/padlock feature TASK-0010 §2 already
  identified as dead/unused for extensions, and trunks have no
  padlock-equivalent UI at all; `trunk => ''`, a 3-character legacy
  column with no evidence of any current consumer for trunk rows either
  — none of the code read during this audit (`Snep_InterfaceConf`,
  `PBX_Trunks`, `Snep_Trunks_Manager`) ever reads `peers.trunk` for a
  `peer_type='T'` row). This is a data-completeness fix, not a schema
  change — the columns already exist and already have a well-understood
  safe value from the extensions precedent.
- **Validation required**: `php -l`; a real trunk create via the HTTP
  form for at least one IP technology (plain SIP) succeeds (`302`, not a
  `500`/DB exception); the resulting `peers` row is inspected directly
  (`password`/`trunk`/`lastms` all populated, no other column regressed);
  edit and delete exercised too, since `editAction()`'s `UPDATE` path
  doesn't hit the same `NOT NULL`-on-INSERT failure mode but should still
  be re-checked for consistency; `make smoke` unaffected (its `trunks`
  check only hits the list page, confirmed by reading
  `scripts/smoke-test.sh`, so this bug and its fix are both invisible to
  the existing regression suite either way — worth a note for whoever
  picks up the fix task, not this document's job to add new coverage).
- **Why not fixed inside TASK-0014**: same reasoning as P0-1 — this is a
  pre-existing, technology-agnostic legacy-schema/legacy-code gap
  unrelated to *how* PJSIP objects should be modeled, and CLAUDE.md is
  explicit that "when an unrelated bug is discovered... do not fix it
  opportunistically... create or propose a dedicated future task,"
  giving `Snep_Trunks_Manager::getTrunkLog()`'s own backtick bug
  (§ tech debt, below) as its own worked example of exactly this
  policy.

---

## Baseline this design builds on

Everything listed in the task's own "current validated baseline": PJSIP
extensions fully provisioned by SENMA (TASK-0011), real internal calls
traverse the unmodified AGI/rule engine, real CDR/report readback works,
web root deployment works (TASK-0012), `make smoke` 16/0/0, `make
call-smoke` 18/18. **Trunks are untouched by any of that** — every trunk
technology today is chan_sip/chan_iax2/hardware/manual, generated by the
same 219-line `Snep_InterfaceConf::loadConfFromDb()` TASK-0010 already
assessed for extensions (§3 there), and — per the two P0 findings above —
the trunk create/edit UI does not currently function at all in this
Docker environment, chan_sip included, independent of PJSIP.

---

## 1. Current trunk lifecycle trace (create/edit/delete/enable)

**Caveat, stated plainly per CLAUDE.md's "confidence level when findings
are incomplete" documentation rule**: the *create* and *edit* POST-time
DB-insert behavior below is derived from reading
`TrunksController::preparePost()`/`addAction()`/`editAction()` directly
(and, for the `peers`-row insert specifically, confirmed via the P0-2
reproduction's manual SQL, which reconstructs *exactly* what that code
would send). It is **not** confirmed by successfully completing a real
end-to-end HTTP create, because P0-1 prevents the form from rendering at
all. The *list*, *delete*, and *enable* flows below **were** exercised
directly against the running app (all three render/execute without
hitting either P0 blocker, since none of them call `Telcos_Manager` or
insert a new `peers` row).

### Create (`TrunksController::addAction()`)

```
addAction()
  -> renders addedit.phtml (action="add")            [BLOCKED by P0-1 before this point today]
  -> POST back to addAction()
  -> Snep_Trunks_Manager::getName($_POST['callerid']) -- duplicate-name guard, keyed on callerid, NOT trunks.name
  -> preparePost($_POST)
       - trunks.name is NOT admin-chosen: `SELECT name FROM trunks
         ORDER BY CAST(name AS DECIMAL) DESC LIMIT 1`, next name = max+1.
         Trunk identity is an internal sequential number the admin never
         sees or types -- callerid is the only user-facing label.
       - trunktype = "I" (sip/iax2/snepsip/snepiax2, gets a peers row) or
         "T" (khomp/virtual, no peers row)
       - builds trunks-table fields (allowed via $trunk_fields) and, for
         "I" trunks, a second peers-table field set (via $ip_fields) --
         see §3 for the full matrix
       - codecs: same ";"-joined-then-comma-rejoined pattern as
         extensions (TASK-0010 §8), reused verbatim
       - NAT: same nat_* checkbox pattern as extensions (TASK-0010 §9),
         reused verbatim
  -> db->beginTransaction()
       db->insert("trunks", $trunk_data)
       if trunktype=="I": db->insert("peers", $trunk_data['ip'])   [BLOCKED by P0-2 today]
     db->commit() / rollBack()
  -> Snep_Audit_Manager::SaveLog(...)
  -> if NOT trunk_disabled checkbox: Snep_InterfaceConf::loadConfFromDb()
  -> redirect /trunks
```

**Inputs**: `callerid` (display name), `technology` (sip/iax2/khomp/
virtual/snepsip/snepiax2), per-technology fields (`host`, `username`,
`secret`, `dialmethod`, `fromuser`, `fromdomain`, `qualify`+
`qualify_value`, `peer_type` radio, `reverse_auth` checkbox, `domain`,
`insecure`, `port`, `call-limit`, `board` for Khomp, `channel`+
`id_regex` for Virtual, `identifier` for SnepIAX2), `dtmfmode`,
`nat_*` checkboxes, 3 codec selects, `map_extensions`, `dtmf_dial`+
`dtmf_dial_number`, minute-control fields (`tempo`/`time_chargeby`/
`time_total`/`time_initial_date`), `telco`, `trunk_disabled`.

**Persisted fields**: one `trunks` row always; one `peers` row
additionally, only for `trunktype=="I"` (SIP/IAX2/SNEPSIP/SNEPIAX2).
KHOMP/VIRTUAL trunks are `trunks`-table-only, by design — there is
nothing for `Snep_InterfaceConf`'s `peer_type='T'` branch to generate for
them beyond the dead-code-adjacent runtime dial string built straight
from `trunks.channel` (§ interfaces, below).

**Generated configuration**: same full-stateless-rewrite property
TASK-0010 §3 already found for extensions — `Snep_InterfaceConf::
loadConfFromDb()` regenerates `snep-{sip,iax2}.conf`/`-trunks.conf`/
`-hints.conf` from the *entire* current `peers`/`trunks` state every
time, not incrementally.

**Notable, confirmed-by-reading behavior worth flagging plainly**: when
`trunk_disabled` is checked at create/edit time, `Snep_InterfaceConf::
loadConfFromDb()` is **not called at all** (`if
(!isset($_POST['trunk_disabled'])) { ...loadConfFromDb(); }`). This means
*editing an already-enabled trunk into a disabled one* leaves its old,
still-enabled config stanza in the generated file until something else
triggers a regeneration — a real, pre-existing inconsistency with how
`ExtensionsController`'s equivalent `disableAction()` calls
`loadConfFromDb()` unconditionally. Recorded as tech debt (§ below), not
fixed here, and explicitly **not** to be silently replicated by the new
PJSIP trunk generator's own call sites in TASK-0015 — the PJSIP generator
should call unconditionally, matching the extension generator's already-
correct behavior, not this trunk-specific quirk.

### Edit (`TrunksController::editAction()`)

Same `preparePost()`/two-table-write shape, via `db->update()` instead of
`db->insert()`. Unlike extensions (where `editAction()` forces
`exten` back to the original value, making the extension number
immutable — TASK-0010 §1), **trunk technology is fully editable** — the
`technology` `<select>` has no `disabled` attribute pre-set for existing
trunks the way the extension-number field does, and `preparePost()`
happily re-derives `trunktype`/`channel`/`id_regex` from whatever
technology is currently posted. A trunk can be converted from chan_sip to
IAX2, KHOMP, etc. through the existing UI today (once P0-1 is fixed) —
this is directly relevant to §16 (migration/coexistence): trunk
technology conversion is **already a reachable, existing UI flow**, not
something a PJSIP migration would need to newly expose.

### Delete (`TrunksController::removeAction()`)

```
removeAction()
  -> Snep_Trunks_Manager::getValidation($id) + getRules($id)
       (blocks delete if any regras_negocio row references this trunk,
        matched by 'T:<id>' in origem/destino OR a
        regras_negocio_actions_config row with key IN ('tronco','trunk')
        and value=<id> -- confirms routes reference trunks by trunks.id,
        never by name/callerid)
  -> on POST confirm:
       Snep_Trunks_Manager::remove($id)         DELETE trunks WHERE id=$id
       Snep_Trunks_Manager::removePeers($name)  DELETE peers WHERE name=$name
       Snep_InterfaceConf::loadConfFromDb()
```
Exercised live: renders and executes correctly (no P0-1/P0-2 dependency
— `Telcos_Manager` is never called here, and DELETE has no NOT-NULL
concern).

### Enable (`TrunksController::enableAction()`)

Flips `trunks.disabled` to `false` via `Snep_Trunks_Manager::enable($id)`
(a plain `UPDATE`), then calls `Snep_InterfaceConf::loadConfFromDb()`
unconditionally. There is **no `disableAction()`** — disabling only
happens via the add/edit form's `trunk_disabled` checkbox, which (as
noted above) skips regeneration entirely, an asymmetry with `enable`'s
unconditional regeneration. Exercised live: renders and executes
correctly.

---

## 2. Trunk-type inventory

Every technology exposed by `addedit.phtml`'s `<select name="technology">`
(`sip`, `iax2`, `khomp`, `virtual`, `snepsip`, `snepiax2`) plus the
underlying runtime dispatch in `PBX_Trunks::get()`:

| Type | UI label | Gets a `peers` row? | Runtime interface (`PBX_Trunks::get()`) | Classification | Why |
|---|---|---|---|---|---|
| SIP, `dialmethod=normal` | "SIP" | Yes | `PBX_Asterisk_Interface_SIP` (username+secret+host) | **A** | Primary PJSIP migration target — register/peer-based provider, the most common real-world case |
| SIP, `dialmethod=noauth` | "SIP" + "Without Authentication" | **No** — `Snep_InterfaceConf`'s trunk branch explicitly skips emitting *any* stanza when `dialmethod=="NOAUTH"` | `PBX_Asterisk_Interface_SIP_NoAuth` (host only) | **A** | Relevant, but with a real, flagged design gap — see §7 (NOAUTH → identify/auth) |
| IAX2 (both dialmethods) | "IAX2" | Yes (normal) / No (noauth) | `PBX_Asterisk_Interface_IAX2`/`IAX2_NoAuth` | **B** | chan_iax2 is not part of this project's PJSIP migration (CLAUDE.md's Phase 6 targets chan_sip specifically) — stays exactly as-is, indefinitely |
| KHOMP | "Khomp" | No (`trunktype="T"`) | `PBX_Asterisk_Interface_KHOMP` (hardware channel string, e.g. `KHOMP/b1c0`) | **C** | Hardware-specific TDM boards, explicitly out of scope (task item 19 / prior tasks' Khomp deferrals) |
| VIRTUAL | "Virtual" | No (`trunktype="T"`) | `PBX_Asterisk_Interface_VIRTUAL` (admin types the raw channel string directly — the form's own help text gives `[Dahdi/g1]`/`[SIP/account]` as examples) | **E** | Explicitly an escape hatch, not a first-class SENMA technology. Already trivially "PJSIP-capable" today with zero generator work: an admin can already type `PJSIP/whatever` into the Channel Technology field and it will dial exactly that literal string, unmanaged, exactly as it does for any other raw channel expression. Nothing to build. |
| SNEPSIP | "Snep SIP" | Yes, `peers.type` forced to `peer` | **Not** `PBX_Asterisk_Interface_SIP` — falls through `PBX_Trunks::get()`'s `else` branch to `PBX_Asterisk_Interface_VIRTUAL(channel: "SIP/"+username)`, since `trunks.type` holds the literal string `"SNEPSIP"`, which matches none of `get()`'s explicit `"SIP"`/`"IAX2"`/`"KHOMP"` checks | **A** | A real, reachable, distinct sub-case: a simplified SENMA-to-SENMA (or SENMA-to-any-Asterisk) IP/peer-matched trunk, no username/secret at all (`Snep_InterfaceConf` emits `type=peer`, `host=`, no `secret=`/`username=` line whatsoever). Closest existing analog to a PJSIP "identify by IP, no auth" endpoint — needs its own explicit mapping decision, not a mechanical one (§4/§7) |
| SNEPIAX2 | "Snep IAX" | Yes, `peers.type` forced to `friend` | Same VIRTUAL-passthrough pattern, `channel="IAX2/"+identifier` | **B** | IAX2-based sibling of SNEPSIP — same "not in this migration's scope" reasoning as plain IAX2 |

No trunk type was found that isn't covered by this table; no evidence of
any technology beyond these six anywhere in the schema, controller, or
generator.

---

## 3. Legacy trunk field matrix

Derived from `schema.sql`'s `trunks`/`peers` tables,
`TrunksController::preparePost()`, and `Snep_InterfaceConf::
loadConfFromDb()`'s `peer_type==='T'` branch (the authoritative source
for what's actually *read*, separately from what's merely *stored* —
same method TASK-0010 §2 used for extensions).

| Field | Table.column | UI field | chan_sip meaning today | Emitted by generator? | PJSIP target |
|---|---|---|---|---|---|
| Trunk identity | `trunks.name` (+ mirrored into `peers.name`) | *(not shown — auto-numeric, sequential, internal)* | chan_sip section name / `defaultuser=` | Yes (`[<peer.defaultuser>]` header) | Endpoint+AOR object name basis (§9 — via `trunks.id`, not `.name`) |
| Display label | `trunks.callerid` | "Name" | Not a chan_sip field — duplicate-checked instead of `name` | No | No PJSIP relevance; SENMA-internal label only |
| Technology (dup. x2) | `trunks.type` **and** `trunks.technology` (always written identically — a confirmed, harmless redundancy) | "Type" `<select>` | Drives the generator's trunk-vs-extension/SIP-vs-IAX2 branch | N/A (control field, not emitted) | Drives which PJSIP objects to emit |
| IP-vs-hardware routing | `trunks.trunktype` (`I`/`T`) | *(derived, not shown)* | Whether a `peers` row exists at all | N/A | Same routing role, unaffected |
| Dial method | `trunks.dialmethod` (`NORMAL`/`NOAUTH`) | "Dial Method" radio | Whether a named peer stanza is generated at all (NOAUTH = none) | Controls emission | §7 — the single biggest PJSIP design gap in this document |
| Username | `trunks.username` -> `peers.defaultuser` (SIP) / `peers.username` (IAX2, via generator's `$name_of_user` branch) | "Username" | Peer/friend section name for auth | Yes (dialmethod=NORMAL only) | `auth` object's `username=` |
| Secret | `trunks.secret` -> `peers.secret` | "Password" | Plaintext auth secret | Yes (dialmethod=NORMAL only) | `auth` object's `password=` (`auth_type=userpass`, same zero-schema-change fit TASK-0010 §7 found for extensions) |
| Host | `trunks.host` -> `peers.host` | "Remote Host" | `host=<ip-or-hostname>` | Yes, always (when a stanza is emitted) | AOR's static `contact=sip:<host>` (non-registering case) or nothing (registrar-populated, register-based case) |
| Port | `peers.port` (`$ip_fields` only, not on `trunks`) | "Port" | `port=` | Yes, if set | Part of the AOR's static contact URI, or irrelevant once registrar-learned |
| From User | `peers.fromuser` | "From User" | `fromuser=` | Yes, if set (NORMAL, non-SNEP branch only) | Endpoint `from_user=` — identical name/semantics, direct rename |
| From Domain | `peers.fromdomain` | "From Domain" | `fromdomain=` | Yes, if set (same branch) | Endpoint `from_domain=` — identical name/semantics |
| Domain | `trunks.domain` | "Domain" | `domain=` — **SIP only**, never emitted for IAX2 | Yes, if set and `trunk->type=="SIP"` | Endpoint `from_domain=` (same target as `fromdomain` above — chan_sip's `domain=` on a trunk section and `fromdomain=` are historically near-synonymous; PJSIP has one field, `from_domain=`, so both legacy inputs collapse onto it — an explicit, flagged simplification, not silently assumed identical) |
| Qualify | `peers.qualify` (`yes`/`no`/a raw numeric "specify" value) | "Delay Qualification" radio + "Qualification time" text | `qualify=` — **raw pass-through**, unlike SNEPSIP's forced yes/no collapse | Yes, verbatim | `qualify_frequency=<seconds>` — same boolean-to-interval translation as TASK-0010 §9, but trunks additionally support a literal numeric override today that extensions never exposed, giving a **more literal**, evidence-backed translation opportunity for the "specify" case (use the number directly, not a guessed default) |
| Type (peer/user/friend) | `peers.type` (via `peers.peer_type` — form field, confusingly named, is `name="peer_type"`, NOT `type`) | "Type" radio | chan_sip's incoming-match-vs-outgoing-auth mode | Yes (`type=`) | No PJSIP equivalent — same structurally-obsolete finding as TASK-0010 §2 for extensions |
| Insecure | `trunks.insecure` (free text, e.g. `port,invite`) | "Insecure" | Comma-combinable auth-bypass flags | Yes, if set (NORMAL, non-SNEP branch) | **No direct equivalent, not a flag translation.** PJSIP's model is "the `auth` object exists or it doesn't" — there is no per-flag insecure toggle. `insecure=invite` (accept unauthenticated INVITEs from this peer) maps conceptually to *omitting the auth object entirely* for that endpoint, not to a config line — an explicit product decision, not a mechanical rename (flagged, not solved here) |
| Reverse auth | `trunks.reverse_auth` (BOOLEAN, schema default `TRUE`, always explicitly written `true`/`false` by the app regardless) | "Force reverse authentication" checkbox | Whether Asterisk sends an outbound `register =>` line for this trunk | Controls emission of the `-trunks.conf` register line | §5 — drives whether a PJSIP `registration` object is emitted at all |
| DTMF mode | `peers.dtmfmode`/`trunks.dtmfmode` (both written, `peers` copy is what's actually emitted) | "DTMF Mode" radio | `dtmfmode=` | Yes | `dtmf_mode=` — same 3 values, direct rename (TASK-0010 §2) |
| Codecs | `trunks.allow` (`;`-joined) | 3 codec `<select>`s | codec list | Yes, `;`->`,` transform reused verbatim (same code path as extensions) | Identical PJSIP syntax — no new mapping needed (TASK-0010 §8) |
| Call limit | `peers.call-limit` | "Channel Limit" | `call-limit=` — **SIP only**, never IAX2 | Yes, if set and `trunk->type=="SIP"` | Same "no direct config-level equivalent" finding as TASK-0010 §2 |
| NAT | `peers.nat` (comma-joined `nat_*` checkboxes) | "NAT Optimization" checkboxes | Combined chan_sip NAT flag | Yes, verbatim | Same `force_rport`/`rtp_symmetric`/`rewrite_contact` split as TASK-0010 §9, reused for trunks unchanged |
| Extension mapping | `trunks.map_extensions` | "Extension Mapping" checkbox | Drives `Snep_Trunk::setExtensionMapping(true)` at runtime | Not chan_sip config at all | Application-level (AGI/PHP), technology-agnostic — unaffected by PJSIP either way. Consumer of `allowExtensionMapping()` was not traced further in this audit (flagged, not blocking) |
| DTMF dial mode | `trunks.dtmf_dial`/`dtmf_dial_number` | "DTMF dial mode" checkbox + number | Not chan_sip config — a `DiscarTronco`-runtime `Dial()` `D()`-flag behavior (dial a fixed number, then send the real destination as DTMF) | Not chan_sip config | Technology-agnostic (`Dial()`'s `D()` option works identically under any channel driver) — unaffected |
| Identify pattern | `trunks.id_regex` | "ID Regular Expression" (VIRTUAL only — auto-derived for every other type) | Regex matched against the raw Asterisk channel string in `PBX_Interfaces::getChannelOwner()` to identify *inbound* calls | Not chan_sip config — SENMA's own application-layer inbound identification | §7 — the central "identify" analog, and the field a PJSIP-under-the-hood channel-naming change would most directly threaten |
| Telco | `trunks.telco` | "Telco" `<select>` | Billing-rate association | Not chan_sip config | Technology-agnostic, unaffected |
| Minute control | `trunks.time_total`/`time_chargeby`/`time_initial_date` | "Minute Control" checkbox + fields | Balance/quota tracking, read by `DiscarTronco` | Not chan_sip config | Technology-agnostic, unaffected (identical mechanism to extensions') |
| `peers.password` | *(not exposed in the trunk UI at all)* | — | Unrelated numeric-PIN/padlock feature (same dead-for-trunks finding as TASK-0010 §2 found for extensions) | No | No PJSIP relevance — also the #2 element of the P0-2 blocker chain |
| `peers.trunk` | *(not exposed, no evidence of any reader for `peer_type='T'` rows)* | — | Unknown/dead for trunks | No | No PJSIP relevance — the #3 element of the P0-2 blocker chain |
| `peers.md5secret` | *(never populated)* | — | Precomputed-digest alternative to plaintext secret | No | Dead — same finding as TASK-0010 §2, `auth_type=userpass` is the only mode ever used |

---

## 4. Authentication-model classification

| Model | SENMA representation today | PJSIP objects required |
|---|---|---|
| IP-authenticated provider, no registration | `dialmethod=NOAUTH` — **no named stanza generated at all** (Snep_InterfaceConf skips it entirely) | endpoint (no `auth=`) + aor (static `contact=`) + **identify** (new requirement — chan_sip needed none of these three as named objects; PJSIP needs all three) — see §7 |
| Username/password outbound auth, no registration | `dialmethod=NORMAL`, `reverse_auth=false` | endpoint + auth (outbound) + aor (static `contact=<host>`, since we always dial their fixed address rather than a registrar-learned one) |
| REGISTER-based provider | `dialmethod=NORMAL`, `reverse_auth=true` | endpoint + auth (reused for both outbound calls and the registration's `outbound_auth=`) + aor (empty/dynamic, registrar-populated) + **registration** |
| Registration + separate call-time auth credentials | **Not representable today** — SENMA has exactly one username/secret pair per trunk, used for both purposes. No evidence any current provider needs this; flagged as a real model limit, not fixed | Would need a second credential pair; out of scope, no evidence it's needed |
| Provider identified by source IP | `dialmethod=NOAUTH`, or SNEPSIP's IP/peer-matched mode | **identify** object (§7) |
| Static peer without registration | Same as "username/password, no registration" above | Same |
| Inbound-only trunk | **Not an explicit concept in the schema** — every trunk is bidirectional by construction (dialable via `DiscarTronco`, matchable via `id_regex`); a trunk simply never referenced by any route is inbound-only *in practice*, not by configuration | No dedicated object; same as whichever auth model the trunk otherwise uses |
| Outbound-only trunk | Closest real case is NOAUTH: no named stanza means no inbound match is possible via a named peer at all (only IP/anonymous matching, if Asterisk-level guest calling were ever enabled — not evidenced as configured anywhere in this project) | Endpoint+aor(+identify if inbound is ever wanted); omit identify entirely for a genuinely outbound-only static destination |
| Bidirectional trunk | The default/common case for register-based and SNEPSIP trunks | Whichever combination the auth model above already specifies |

---

## 5. Registration analysis (`reverse_auth`)

Traced precisely from `Snep_InterfaceConf.php:166-170`:
```php
if ($trunk->reverse_auth && $trunk->type == 'IAX2') {
    $trunk_config .= ($trunk->dialmethod != "NOAUTH" && !preg_match("/SNEP/", $trunk->type)
        ? "register => user:secret@host:port\n" : "");
} else if ($trunk->reverse_auth) {
    $trunk_config .= ($trunk->dialmethod != "NOAUTH" && !preg_match("/SNEP/", $trunk->type)
        ? "register => user:secret@host:port/user\n" : "");
}
```
**`reverse_auth` is, precisely, "make Asterisk register outbound to this
provider as a SIP/IAX2 client."** It is not about accepting inbound
registrations from the provider — SENMA never acts as a registrar for a
trunk (only extensions register *into* SENMA; trunks, when
`reverse_auth` is set, register *out* to the provider).

- **Where registration credentials are stored**: the same
  `trunks.username`/`trunks.secret`/`trunks.host`(+`peers.port`) already
  used for outbound-call auth — there is no separate registration
  credential pair.
- **Generated separately from peer configuration?** Yes, physically —
  the `register =>` line lands in `snep-{sip,iax2}-trunks.conf` (a
  different file from the peer stanza itself, `snep-{sip,iax2}.conf`),
  but it is derived from and gated by the exact same `trunks`/`peers` row
  read in the same loop iteration — not an independently-configured
  concept.
- **Host/username/fromuser/domain representation**: host/username come
  from the same fields as the peer stanza; `fromuser`/`domain` are not
  part of the register line at all (chan_sip's `register =>` syntax has
  no such fields).
- **Multiple registrations per trunk**: **not possible today** — one
  `trunks` row has exactly one `host`/`username`/`secret`/`port` set, so
  exactly zero or one `register =>` line is ever emitted per trunk. No
  UI, no schema column, no generator loop supports more than one.
- **Can the existing schema represent PJSIP registration safely, or is a
  schema change required?** **No schema change required.** A PJSIP
  `registration` object needs exactly `client_uri` (built from
  `username`+`host`), `server_uri` (`host`), and `outbound_auth`
  (referencing the same auth object used for outbound calls) — all
  derivable from columns that already exist. The only genuinely new
  question (not a schema one) is whether one `registration` object per
  trunk, 1:1 with the endpoint, is sufficient — which it is, given no
  evidence anywhere in this codebase of a need for redundant/failover
  registrations to a single provider.

---

## 6. Trunk status monitoring and AMI command replacements

Traced through `snep/includes/ip_status_trunks.php` (the actual
live-polling AJAX endpoint the ip-status page's JS refreshes against —
confirmed in TASK-0012 as one of that page's 3 AJAX calls) and
`IpStatusController`/`Snep_IpStatus_Manager` (the plain MVC-rendered
initial page load — a separate, DB-only code path that does **not**
call AMI itself; only the standalone AJAX file does).

| Current chan_sip/chan_iax2 mechanism | Where used | PJSIP replacement | Notes |
|---|---|---|---|
| `AMI::get_sippeer($username)` (AMI `Action: Peer`) | `ip_status_trunks.php` (peer status/latency), also flagged low-usage in TASK-0008 §8 | `PJSIPShowEndpoint` (AMI action) | Not a rename — `PJSIPShowEndpoint` returns a *series* of events (`EndpointDetail`, one or more `AorDetail`/`ContactStatusDetail`) rather than one flat response; the parsing code needs a genuinely different shape, not a field-rename |
| `AMI::get_SIPshowregistry($host, $user)` (AMI `Action: SIPshowregistry`) | Same file, for outbound registration state | `PJSIPShowRegistrationsOutbound` (AMI action) | Different action name, different response shape; this is also the mechanism §5's registration-failure surfacing would read from |
| `AMI::get_IAXpeerlist()` / `get_IAXregistry()` | Same file, IAX2 branch | **Unchanged** | IAX2 stays IAX2 — not part of this migration |
| `Snep_IpStatus_Manager::getTrunks($like)`'s `canal`/`channel LIKE 'SIP%'`/`'IAX%'` filter | `IpStatusController::indexAction()` (DB-only, no AMI) | Add a `'PJSIP%'` filter alongside | Trivial, same gap TASK-0008 §8/TASK-0010 §11 already flagged for the extensions equivalent — still unresolved, now confirmed to apply to trunks too |
| `ip_status_trunks.php`'s own `channel LIKE 'SIP%'` DB filter | Same standalone AJAX file | Same — needs its own `'PJSIP%'` branch added, since this file is a separate, non-MVC code path from `IpStatusController` and was not updated by any prior task | Not currently wired to anything PJSIP; a PJSIP trunk would simply not appear in the live-refreshing status table until this is added |

No implementation is proposed here (task explicitly says design only) —
this table exists so TASK-0015/0016 know exactly which AMI actions to
call and which two files need a parallel PJSIP branch when status
display is eventually built.

---

## 7. Inbound identify behavior, and how NOAUTH maps to it

**This is the single most consequential open design question in this
document.**

`PBX_Interfaces::getChannelOwner($channel)` — the one function that
identifies *any* inbound call's origin, trunk or extension alike — checks
**trunks first**:
```php
foreach ($trunk_ifaces as $interface) {
    if (preg_match("#^{$interface['id_regex']}$#i", $channel)) {
        return PBX_Trunks::get($interface['id']);
    }
}
```
`$channel` is the raw Asterisk channel name string the AGI request
carries (e.g. `SIP/mytrunkuser-00000001`). For a register-based
(`dialmethod=NORMAL`) trunk, `id_regex = "SIP/" . username` — a simple
prefix match against the peer's own name, exactly like extension
matching. This works identically under PJSIP with zero change beyond the
prefix string (`PJSIP/<name>` instead of `SIP/<name>`), because PJSIP
also names inbound channels after the matched endpoint.

**NOAUTH is where this breaks.** Today, a NOAUTH trunk gets **no named
peer stanza at all** (§1/§4) — chan_sip resolves such an inbound call via
its own built-in anonymous/IP-matched calling behavior, and (confirmed by
reading `PBX_Asterisk_Interface_SIP_NoAuth::getIncomingChannel()`, which
is inherited unchanged from `getCanal()`) SENMA's own `id_regex` for
these trunks is `"SIP/" . host` — relying on chan_sip's own convention of
naming an unmatched/anonymous incoming channel after the caller's raw
source IP.

**PJSIP has no equivalent implicit behavior.** Every inbound PJSIP call
is resolved either to a named `endpoint` (via `identify`, matching source
IP/port to a specific endpoint object) or to Asterisk's own literal
`anonymous` endpoint convention if one is configured — there is no
built-in "name the channel after the raw source IP" behavior to lean on.
**Concretely, preserving NOAUTH's current behavior under PJSIP requires
creating a real, named endpoint (even though no authentication is
wanted) plus an `identify` object binding the provider's host/IP to that
endpoint**, so an inbound INVITE from that IP resolves to a predictable
channel name (e.g. `PJSIP/trunk-<id>-...`) — and `id_regex` generation
must change to match *that* name, not a literal source-IP string, since
PJSIP will never produce the latter.

This is stated here as an **explicit, flagged design requirement, not a
silently-assumed mechanical translation** — it is new work with no
chan_sip analog (chan_sip needed zero named objects for this case;
PJSIP needs two). It is also precisely why this document's dependency
sequence (end of doc) puts inbound trunk work in a separate task
(TASK-0016) rather than folding it into TASK-0015: this is real,
non-trivial design surface, not a rename.

**SNEPSIP** sits in between: it *does* get a named `type=peer` stanza
(IP/peer-matched, no secret) — under PJSIP this becomes an endpoint with
`identify_by=ip` and no `auth=` at all, which is a real, supported PJSIP
pattern (unlike NOAUTH's "no stanza exists" case) — closer to a normal
migration, still flagged as its own explicit decision rather than folded
silently into the register-based case.

---

## 8. Outbound runtime dial-string trace

Traced through `DiscarTronco::execute()`
(`snep/modules/default/actions/DiscarTronco.php:259-422`), the trunk
counterpart to TASK-0008's already-documented `DiscarRamal` trace:

```
PBX_Trunks::get($trunkId)                          [builds the interface object, §2/§4]
  -> trunk time-limit check (trunks.time_total + time_history)
  -> DTMF-dial-mode branch: if set, dial a FIXED number, send real
     destination as DTMF via Dial()'s D() flag (technology-agnostic)
  -> $destiny = $tronco->getInterface()->getCanal() . "/" . $dst_number . $postfix
  -> $asterisk->exec_dial($destiny, timeout, flags)   [plain AGI EXEC Dial(), technology-agnostic]
  -> DIALSTATUS switch (ANSWER/CANCEL/NOANSWER/BUSY -> stop; else -> log)
```

**A real, pre-existing dead-code bug found while tracing this**, worth
recording as tech debt (not fixed, per this task's own scope): lines
337-357 contain an `if ($tronco->getInterface() instanceof
PBX_Asterisk_Interface_SIP_NoAuth || ... IAX2_NoAuth) { $destiny =
...@host... } else { $postfix = "/..."; ... }`, but line 357
**unconditionally overwrites `$destiny`** immediately afterward
(`$destiny = $tronco->getInterface()->getCanal() . "/" . $dst_number .
$postfix;`) — so the NoAuth-specific URI-style dial string
(`SIP/<number>@<host>`) built in the `if` branch is **always discarded**,
and `$postfix` is **undefined** (PHP warning) whenever that `if` branch
was the one that ran, since `$postfix` is only initialized inside the
`else`. The *actual*, live behavior for a NOAUTH trunk today is
`getCanal() . "/" . $dst_number` = `"SIP/<host>/<destnumber>"` (chan_sip's
peer/exten dial syntax applied to a host string), not the dead branch's
intended `"SIP/<destnumber>@<host>"` (URI dial syntax) — a real,
observable behavior difference between what the code appears to intend
and what it actually does. **This matters directly for PJSIP**: PJSIP's
channel driver has no equivalent to chan_sip's "dial straight to a bare
host, no endpoint required" capability at all — `PJSIP/<destination>/
<endpointname>` always requires a real, pre-existing named endpoint to
dial through, even for a purely static, no-auth, no-registration
provider. This reinforces §7's finding from the outbound side: a NOAUTH
PJSIP trunk needs a real endpoint object to be dialable at all, not only
to be inbound-identifiable.

Everything else in this trace (minute-limit check, DTMF-dial mode, the
DIALSTATUS switch, the alert-email feature) is confirmed
technology-agnostic — no chan_sip-specific code beyond the two points
above.

---

## 9. Generator architecture recommendation — `Snep_PjsipTrunkConf`

**Recommendation: a dedicated `Snep_PjsipTrunkConf`, a sibling of
`Snep_PjsipConf`, not a trunk branch bolted onto it, and not a merge of
the two into one class.**

Justification, evidence-first:

- **Object-count complexity is a strict superset, with real conditional
  emission logic.** Extensions always emit exactly three objects
  (endpoint+auth+aor, TASK-0010 §6). Trunks may emit **two to five**
  depending on the row: endpoint+aor always; auth only when the trunk
  actually authenticates (not NOAUTH); registration only when
  `reverse_auth`; identify only for NOAUTH/IP-matched trunks (§7). This
  conditional branching has no analog in the extension case and would
  make `Snep_PjsipConf` itself branch heavily on a concept (trunk
  sub-type) it otherwise has no reason to know about.
- **Object identity source differs structurally, not just in value.**
  Extensions key off `peers.name` (admin-chosen, dial-plan-relevant —
  TASK-0010 §6). Trunks key off `trunks.id` (an internal, never-shown
  primary key — §10, below) — a different source table, different
  uniqueness guarantee, different naming convention (namespaced
  `trunk-<id>`, vs. extensions' bare number).
- **Lifecycle ownership mirrors the existing controller/manager split.**
  `TrunksController`/`Snep_Trunks_Manager` are already fully separate
  from `ExtensionsController`/`Snep_Extensions_Manager` — mirroring that
  in the generator keeps a clean 1:1 controller-to-generator mapping,
  exactly as `Snep_PjsipConf` already mirrors `ExtensionsController`
  alone (TASK-0010 §16).
- **Status/reload semantics genuinely differ.** Trunks need outbound
  registration-failure surfacing (§5/§11) — a concept extensions never
  have (extensions only ever *receive* registrations, never *send* one).
- **Avoids repeating `Snep_InterfaceConf`'s own documented mistake.**
  TASK-0010 §3 found that class became an unmaintainable 219-line
  monolith precisely *because* it conflated SQL fetch, codec transform,
  trunk/extension branching, text formatting, and reload for two
  unrelated technologies in one function. Building trunk complexity into
  `Snep_PjsipConf` (already-working code, built and validated for the
  simpler extension case) would reproduce that exact anti-pattern one
  layer up the stack — the same reasoning TASK-0010 §3 already used to
  justify a new class over extending `Snep_InterfaceConf` applies again
  here, one level deeper.

**Reusable low-level helpers** (the codec `;`->`,` transform, the
qualify boolean-to-interval translation, the NAT-flag splitter) already
exist as small, self-contained pieces of logic reused verbatim from
`Snep_InterfaceConf` by `Snep_PjsipConf`, per TASK-0010 §8/§9. If
`Snep_PjsipTrunkConf`'s implementation in TASK-0015 finds real, exact
duplication with `Snep_PjsipConf`'s equivalents, extracting a small
shared static helper class at that point is reasonable — **not decided
here**, per the explicit instruction not to force sharing prematurely
"merely to share rendering code."

`Snep_PjsipTrunkConf::loadConfFromDb()`: own SQL fetch from `trunks` (+
associated `peers` rows for `trunktype=="I"`), own per-row-to-N-sections
emission, own `module reload res_pjsip.so` call (§11). Called from
`TrunksController` only — exactly mirroring how `Snep_PjsipConf` is
called from `ExtensionsController` only (TASK-0010 §3).

---

## 10. Object identity and naming

```
endpoint:      trunk-<trunks.id>                e.g. trunk-1
aor:           trunk-<trunks.id>                e.g. trunk-1     (MUST equal endpoint name)
auth:          trunk-<trunks.id>-auth
registration:  trunk-<trunks.id>-registration   (only when reverse_auth)
identify:      trunk-<trunks.id>-identify       (only for NOAUTH/IP-matched trunks, §7)
```

**Why `trunks.id`, not `trunks.name`** (unlike extensions, which use the
bare `peers.name` with no prefix — TASK-0010 §6): `trunks.id` is the
actual auto-increment primary key — immutable, never reused, never
edited by any code path read in this audit. `trunks.name` is a
similarly-shaped but independently-computed string (next `MAX(name)+1`
at create time, §1) with no stronger uniqueness guarantee than its own
`UNIQUE KEY` — using the real primary key is strictly safer and more
idiomatic. **Why the `trunk-` namespace prefix** (unlike extensions'
bare-number convention): extensions' bare `peers.name` *is* the
dial-plan-relevant, admin-facing identity — dialing "1000" must reach
endpoint "1000", so no prefix is possible without breaking that
property. A trunk is never dialed *by* its own name (calls reach it via
`DiscarTronco`'s trunk-ID lookup, then `getCanal()` — §8) — so a
namespace prefix is free, and it guarantees a trunk object can never
collide with an extension object (e.g. a trunk `trunk-1000` can safely
coexist with an extension literally named `1000`). The `aor == endpoint
name` constraint is carried forward unchanged from TASK-0010 §6's
empirically-proven registrar requirement (`res_pjsip_registrar` matches
the REGISTER URI username directly against an AOR's own sorcery name) —
it applies identically here for register-based inbound REGISTERs, though
note trunks in TASK-0015's outbound-only scope never *receive* a
REGISTER themselves (§ dependency sequence).

**Rename/delete/duplicate**: identical reasoning to TASK-0010 §6 —
`trunks.id` never changes across an edit (confirmed: `editAction()`'s
`UPDATE` only touches the row identified by the URL's `id` parameter,
never the `id` column itself), so rename is a non-issue by construction;
delete/stale-object safety comes for free from the same full-stateless-
regeneration property (§1, §12); duplicate trunk IDs are structurally
impossible (auto-increment primary key).

---

## 11. Configuration ownership hierarchy

Extends TASK-0010 §5's diagram with one new include, nothing else
changed:
```
/etc/asterisk/pjsip.conf                          <- static, project-owned (unchanged)
    #include pjsip_transports.conf                 <- static (unchanged)
    #include snep/snep-pjsip.conf                  <- Snep_PjsipConf, extensions (UNCHANGED by this task)
    #include snep/snep-pjsip-trunks.conf            <- NEW: Snep_PjsipTrunkConf, trunks
```
Same writable `/etc/asterisk/snep/` subtree (`senma-config` group, GID
3000, setgid `2775`) TASK-0009 already built and TASK-0010/0011 already
proved sufficient — **zero new filesystem/permission work required**.
`TrunksController` gains one additional static call
(`Snep_PjsipTrunkConf::loadConfFromDb()`) alongside its existing
`Snep_InterfaceConf::loadConfFromDb()` call, mirroring exactly how
`ExtensionsController` already calls both `Snep_InterfaceConf` and
`Snep_PjsipConf` (TASK-0010 §3, TASK-0011). **This task changes nothing
about the existing, working extension-provisioning include tree or
generator** — per the explicit instruction.

---

## 12. Reload behavior

Same `module reload res_pjsip.so` command TASK-0010 §10 already proved
live (whole-tree sorcery reload, no more granular unit available) —
sufficient for endpoint/auth/aor/identify changes by the same evidence
already gathered there. Calling it a second time immediately after
`Snep_PjsipConf`'s own call (once both generators run from
`TrunksController`'s and `ExtensionsController`'s respective write
paths) is a harmless, idempotent no-op in the non-failure case — the
same command, reloading the same whole tree, twice, costs nothing
functionally different from once.

**Genuinely open question, not evidenced by this audit or any prior
one**: does `module reload res_pjsip.so` actually cause Asterisk to
*(re-)attempt* an outbound REGISTER for a newly-added or newly-changed
`registration` object, or does outbound registration have its own
separate trigger/timer independent of a config reload? **No PJSIP
`registration` object has ever been created or reloaded anywhere in this
project so far** (TASK-0009's test config had only endpoint/auth/aor for
extensions, never a registration object) — this is explicitly flagged as
something TASK-0015 must test empirically, not assumed here.

**Failure surfacing**: propose querying `PJSIPShowRegistrationsOutbound`
(§6) shortly after each reload and logging if the returned status isn't
`Registered` within a short timeout — a genuinely new capability beyond
what TASK-0010 §10 proposed for extensions (which never register
outbound, only accept inbound REGISTERs). Matches TASK-0010 §10's own
"proposed minimum improvement" spirit (check the reload's own success
text) extended to cover the registration-specific failure mode trunks
introduce.

---

## 13. Codec/NAT/direct-media mapping

**Fully reused from TASK-0010 §8/§9, unchanged** — trunks and extensions
share the identical DB representation (`;`-joined `allow` column,
`nat_*` checkbox set) and the identical generator-side transform code
(`Snep_InterfaceConf.php:83-90`'s codec join, the same NAT-flag
splitting logic). No trunk-specific semantic difference was found for
`direct_media`/`rtp_symmetric`/`force_rport`/`rewrite_contact` — every
one of TASK-0010 §9's flagged interpretive choices (the `auto_*`
collapse, `rewrite_contact`'s brand-new mapping, `qualify`'s
boolean-to-interval translation) applies identically here, with one
trunk-specific refinement already noted in §3's field matrix: trunks'
"specify" qualify value is a real, usable number today (unlike
extensions, which never exposed one), so the interval-translation for
that specific case is evidence-backed rather than an invented default.

**Trunk-specific items explicitly investigated per the task's request**:
- `qualify_frequency`: covered above (more literal than extensions'
  case).
- `contact rewriting`: no trunk-specific evidence found beyond the
  general `rewrite_contact` flag already discussed in TASK-0010 §9 —
  same flagged product decision, not newly resolved here.
- `outbound proxy`: **no field exists anywhere in the trunk schema/UI**
  for an outbound proxy/route-set concept. Not representable today, not
  needed by any current trunk type — flagged as a genuine gap only if a
  future provider ever requires one (`outbound_proxy=` exists as a
  PJSIP endpoint option; would need a new column + UI field, out of
  scope here, no evidence it's needed).

---

## 14. Migration and coexistence

Same additive-generator, zero-flag-day property TASK-0010 §11 already
established for extensions, confirmed to hold for trunks too:
`Snep_InterfaceConf`'s trunk branch already ignores `canal='PJSIP/...'`
rows (same `LIKE 'SIP%'`/`'IAX2%'` filters), so introducing
`Snep_PjsipTrunkConf`, called *additionally* from `TrunksController`,
risks nothing to any existing SIP/IAX2/KHOMP/VIRTUAL/SNEPSIP/SNEPIAX2
trunk.

- **How legacy trunks stay represented**: unchanged — same `trunks`/
  `peers` rows, same `Snep_InterfaceConf` generator, indefinitely, for as
  long as any admin leaves a trunk on a legacy technology.
- **How new PJSIP trunks are distinguished**: the same mechanism
  extensions already use — `canal`/`channel` prefix (`PJSIP/...`),
  filtered independently by each generator's own SQL, with zero new
  DB flag or "migration mode" needed.
- **Are current DB fields sufficient?** Yes — confirmed throughout §3/§5
  above; the only two things blocking a real PJSIP trunk from persisting
  *at all* today are the technology-agnostic P0-1/P0-2 bugs, not a
  schema gap.
- **Can conversion happen per-trunk?** **Yes, and — unlike extensions —
  this is already a reachable, existing UI flow today**: §1 found
  `editAction()` places no restriction on changing a trunk's technology
  (unlike the extension-number lock TASK-0010 §1 found). Once P0-1/P0-2
  are fixed and a PJSIP option exists in the technology dropdown, an
  admin could convert an existing chan_sip trunk to PJSIP through the
  *exact same edit form already in production*, no new UI mechanism
  needed.
- **What happens to routes referencing a converted trunk?** **Nothing —
  they keep working unchanged.** Confirmed via `Snep_Trunks_Manager::
  getRules()`/`getValidation()`'s SQL: routes reference a trunk
  exclusively by `trunks.id` (`regras_negocio_actions_config.value =
  '<id>'`, or `'T:<id>'` embedded in `origem`/`destino`) — never by name,
  callerid, or technology. Since `trunks.id` never changes across a
  technology edit (§10), every route pointing at a converted trunk
  continues resolving to the same trunk row, dialing through whatever
  interface `PBX_Trunks::get()` now builds for its new technology,
  automatically.
- **Do trunk IDs stay stable during migration?** Yes, confirmed — `id`
  is never written by any UPDATE path read in this audit.

**No schema change, no new coexistence flag, no "migration mode" switch
needed** — the same conclusion TASK-0010 §11 reached for extensions,
now confirmed to hold for trunks as well, and in one respect (per-trunk
technology conversion) trunks are **easier** to migrate incrementally
than extensions, since the conversion UI already exists.

---

## 15. Secrets

`trunks.secret`/`trunks.username` — plaintext, `VARCHAR(80)`, no
hashing, identical storage model to `peers.secret` for extensions
(TASK-0010 §7). Round-tripped into the edit form's `<input
type="password" value="...">` the same way. `auth_type=userpass` is
again a direct, zero-schema-change fit. **No redesign proposed or
needed** — per the task's own instruction not to redesign credential
storage unless necessary, and no evidence found that it is.

**Test fixtures**: TASK-0015's `make trunk-smoke` should reuse the exact
`secret='taskNNNN-fixture'`-style clearly-marked, create-if-absent-else-
stop-on-conflict pattern `call-smoke-test.sh` already established for
extension fixtures (TASK-0009 §6) — never a real provider credential,
per CLAUDE.md's "never commit real credentials" rule and the task's own
explicit instruction.

---

## 16. Explicitly deferred (this task and future ones)

Unchanged from the task's own instruction, restated for completeness:
production carrier credentials, TLS/WSS, SRTP, WebRTC, PostgreSQL, broad
UI redesign, voicemail migration, queue redesign, fax migration,
Khomp/TDM modernization, realtime PJSIP (no evidence anywhere in this
audit that it's needed — same file-based-generator reasoning TASK-0010
§4 already gave for extensions applies identically to trunks: PJSIP's
realtime schema still doesn't match anything in `trunks`/`peers`, and
the file-based model is still the only option that doesn't compound the
already-nontrivial object-model change with an independent new
schema-and-cache-invalidation problem).

**Tech debt recorded, not fixed, during this audit** (beyond the two P0
blockers, which are prerequisites, not "deferred debt"):
- `Snep_Trunks_Manager::getTrunkLog()` — confirmed **dead code, zero
  callers anywhere** — and its "suspected legacy backtick/shell-execution
  bug" (CLAUDE.md's own worked example) now has a precise root cause:
  `array('port', 'qualify', 'type as type_peer', `` `call-limit as
  call_limit` ``)` uses PHP **backticks** (the shell-exec operator) around
  its last element instead of quotes — PHP would attempt to execute a
  shell command literally named `call-limit as call_limit`, which would
  fail and yield `null` for that array slot. Harmless only because the
  method is never called.
- `trunks.type`/`trunks.technology` duplication (§3) — both columns
  always hold the identical value, read by different call sites
  (`type` by `PBX_Trunks::get()`/`Snep_InterfaceConf`; `technology` by
  `TrunksController::editAction()`'s form-population code) — a harmless
  but confirmed redundancy.
- The `trunk_disabled`-skips-regeneration inconsistency (§1) — editing an
  enabled trunk into a disabled one leaves a stale, still-enabled
  stanza in the generated file.
- `DiscarTronco.php`'s dead NOAUTH dial-string branch and undefined
  `$postfix` (§8).

None of these block TASK-0015/0016 the way P0-1/P0-2 do; recorded here
per CLAUDE.md's "record unrelated debt separately" rule, not assigned to
any specific future task by this document.

---

## 17. Proposed TASK-0015 — outbound PJSIP trunk provisioning

```
prerequisite: P0-1 fixed (Telcos_Manager declared static)
prerequisite: P0-2 fixed (peers.password/trunk/lastms populated in
              TrunksController::preparePost()'s $ip_data)

Create a SIP trunk through SENMA's real TrunksController::addAction()
  HTTP flow (technology=pjsip, dialmethod=normal, reverse_auth=true,
  pointing at a local provider-simulator -- see below)
  -> trunks + peers rows persisted
  -> Snep_PjsipTrunkConf emits:
       [trunk-<id>]              endpoint
       [trunk-<id>-auth]         auth
       [trunk-<id>]  type=aor    aor (dynamic, registrar-populated)
       [trunk-<id>-registration] registration
  -> module reload res_pjsip.so
  -> outbound REGISTER succeeds against the provider-simulator
     (PJSIPShowRegistrationsOutbound reports Registered)
  -> a route/rule sends an outbound-pattern-matching call through
     DiscarTronco -> this trunk (existing, unmodified routing engine)
  -> provider-simulator receives the INVITE, answers
  -> call establishes, hangs up
  -> real cdr_adaptive_odbc CDR row (channel=PJSIP/trunk-<id>-...)
  -> SENMA's existing CallsReport endpoint reads it back
```

**In scope**: `Snep_PjsipTrunkConf` covering exactly the
endpoint+auth+aor+registration case (§4's "REGISTER-based provider"
row — the simplest, most representative, most likely to work without
new design surface); the `technology=pjsip` UI addition to the trunk
form (mirroring TASK-0010 §12's extension precedent — same kind of
`<option>` addition plus `showDiv()` extension, not investigated field-
by-field here since it's a small, mechanical extension of already-solved
work); the local provider-simulator (§19); `make trunk-smoke` (§18);
verifying §12's open reload/registration-retrigger question empirically.

**Explicitly not in TASK-0015**: NOAUTH/identify-object trunks (§7 — a
separate, harder design surface, deliberately deferred to TASK-0016 per
the split decision below); SNEPSIP/SNEPIAX2 (§2, category A but not the
simplest case, defer until the core register-based path is proven);
KHOMP/VIRTUAL (categories C/E); inbound trunk identification/routing of
any kind; multiple registrations per trunk; any schema change (§5/§14
each independently found none necessary for this milestone).

---

## 18. Automated `make trunk-smoke` design

Mirrors `call-smoke-test.sh`'s proven structure (TASK-0009 §11, TASK-0010
§14) exactly, extended for a trunk instead of a pair of extensions:

1. Log in as the existing smoke-test admin account (same pattern).
2. `POST /index.php/default/trunks/add` with `technology=pjsip`,
   `dialmethod=normal`, `reverse_auth=1`, and connection details pointing
   at the provider-simulator container (resolved dynamically from the
   running container's own network, same pattern as TASK-0009's baresip
   tooling) — a clearly-marked fixture (`secret='trunk-smoke-fixture'`),
   create-if-absent-else-stop-on-conflict, matching §15.
3. Assert the redirect indicates success (not a string error message —
   same success/failure distinguishing pattern `execAdd`'s callers
   already use).
4. Assert `snep-pjsip-trunks.conf` contains the expected sections (or,
   preferably, proceed directly to behavior: registration state).
5. Poll `PJSIPShowRegistrationsOutbound` (via AMI, same
   `PBX_Asterisk_AMI` client already used throughout) until `Registered`
   or a timeout — proving §12's open question empirically as a side
   effect of the test itself.
6. Exercise a real outbound call through SENMA's existing routing (a
   route/rule pointing at this trunk, dialed by a real registered
   extension — reusing `call-smoke-test.sh`'s existing baresip-extension
   tooling as the *calling* side, with the *trunk* as the destination
   leg instead of a second extension).
7. Assert the provider-simulator answers (its own Asterisk CLI/AMI, or
   simply the call's own DIALSTATUS reaching `ANSWER`).
8. Assert a real CDR row exists and is correct (`channel=PJSIP/
   trunk-<id>-...`), and that SENMA's CallsReport endpoint reads it back
   — identical final two assertions to `call-smoke-test.sh`'s existing
   ones.
9. Cleanup: delete the trunk through the real
   `TrunksController::removeAction()` HTTP flow (proving delete-then-
   regenerate too, not just create), via an `EXIT` trap, safe even on
   early abort — same pattern as the existing script.

**Must not require real commercial-provider credentials** — satisfied by
construction, since the "provider" is the local simulator, never a real
carrier. **Deterministic/local/repeatable/idempotent/collision-safe**:
same guarantees `call-smoke-test.sh` already provides for extension
fixtures, applied to a trunk fixture instead. **Must assert `make smoke`
stays green** — same additive-not-replacement relationship TASK-0008
§13 already established for `call-smoke` itself.

---

## 19. Local provider simulator (for TASK-0015, not built by this task)

**Recommendation: a second instance of the already-built,
already-PJSIP-capable `mag-pbx-asterisk` image, given a different,
provider-flavored config mount — not a new Dockerfile, not a softphone.**
A real ITSP genuinely *is* another SIP-speaking PBX/gateway with its own
dialplan that must answer and route calls, not a single registered
device — a plain softphone (baresip, TASK-0009's pattern) is the right
stand-in for an *extension*, but the wrong shape for a *trunk's remote
party*. Reusing the existing image is also strictly cheaper than
TASK-0009's `baresip-test.Dockerfile` path, since no new build, no new
runtime dependency, and no new signaling stack need to be introduced —
the exact same `res_pjsip`/`chan_pjsip` build already proven in TASK-0009
is reused on both ends of the test call.

Concretely: a disposable container (built on demand by
`scripts/trunk-smoke-test.sh`, not part of `compose.yaml`'s permanent
topology — same "not a permanent service" precedent as
`baresip-test.Dockerfile`), running the same `mag-pbx-asterisk` image
with:
- A minimal `pjsip.conf` accepting exactly one inbound REGISTER (a
  static endpoint+auth+aor matching whatever credentials the test trunk
  fixture uses).
- A minimal `extensions.conf` context (no AGI, no SENMA app logic needed
  on this side at all — it only needs to prove genuine two-way SIP
  signaling and RTP negotiation): `Answer()` -> a short `Wait()` ->
  `Hangup()`, enough to generate a real `ANSWER` DIALSTATUS and a
  non-zero call duration on SENMA's own CDR row.

This also directly informs TASK-0016's inbound work later: the same
simulator container, configured to *originate* a call back toward
SENMA's trunk endpoint, becomes the natural way to test inbound trunk
identification without any real carrier involved either.

---

## 20. TASK-0015 vs. TASK-0016 — inbound is not "essentially free"

The task's own stated preference is confirmed by this audit, **not
overridden**: inbound trunk work does **not** come for free once outbound
provisioning exists, and belongs in a separate TASK-0016.

Reasoning: §7/§8 found that inbound identification for **NOAUTH/IP-
matched trunks requires genuinely new PJSIP objects (a real endpoint +
an `identify`) that have no chan_sip analog at all** — this is real,
unavoidable design and implementation surface, not a rename. The
*narrower* claim — that inbound might work "for free" specifically for
the **register-based** trunk TASK-0015 targets, since a provider calling
back on the same connection it registered from would already resolve to
that registered endpoint's contact — is **plausible from the evidence
gathered but not empirically tested anywhere in this codebase's history**
(no PJSIP registration object has ever existed in this project until
TASK-0015 creates one, so nothing about its inbound-matching behavior
has ever been observed). Recommending TASK-0016 also cover confirming or
refuting that narrower claim, rather than assuming it, keeps TASK-0015
cleanly scoped to what §17 already specifies (outbound only) while still
directing the very next task to close the one place this audit found
a genuine reason for optimism.

---

## 21. Dependency sequence

```
TASK-0014 complete (this document)
↓
prerequisite trunk UI/runtime blocker fixes
  (P0-1: declare Telcos_Manager::getAll() static;
   P0-2: populate peers.password/trunk/lastms in
   TrunksController::preparePost() -- both technology-agnostic,
   both independent of PJSIP, neither touched by TASK-0014)
↓
TASK-0015 -- outbound PJSIP trunk provisioning
  (Snep_PjsipTrunkConf: endpoint+auth+aor+registration only;
   register-based provider-simulator per §19; make trunk-smoke per §18;
   empirically resolve §12's reload/registration-retrigger question and
   §20's "does inbound work for free" question as side effects)
↓
TASK-0016 -- inbound PJSIP trunk identification/routing
  (identify objects for NOAUTH/IP-matched trunks per §7; id_regex
   generation update to match PJSIP's endpoint-based channel naming
   instead of chan_sip's raw-source-IP convention; confirm or refute
   whether register-based inbound truly needed no new work, per §20)
```

---

## 22. Explicit architectural recommendation

**Build a new, standalone `Snep_PjsipTrunkConf` class, a sibling of
`Snep_PjsipConf` (not a branch inside it, not a merge with it), emitting
a flat `snep-pjsip-trunks.conf` included alongside the existing
`snep-pjsip.conf` from the same static, project-owned `pjsip.conf` —
reusing the already-built `/etc/asterisk/snep/` writable subtree,
naming objects `trunk-<trunks.id>`(+`-auth`/`-registration`/`-identify`
suffixes) to avoid any collision with extension object names, reloading
via the same already-proven `module reload res_pjsip.so`, and called
additively alongside the completely untouched `Snep_InterfaceConf` from
`TrunksController` only.** Do not extend `Snep_InterfaceConf`, do not
fold trunk generation into `Snep_PjsipConf`, and do not use PJSIP
realtime.

This follows directly from the evidence gathered: trunks require a
strict superset of extensions' PJSIP objects with real conditional
emission logic (§9); their object-identity source and naming convention
are structurally different from extensions' (§10); the existing
`peers`/`trunks` schema already contains everything needed for the
register-based case with zero schema changes (§5); the flat-file
generator model already proven for extensions extends cleanly (§11/§12);
coexistence and even per-trunk technology migration require no new flag,
schema, or mechanism (§14) and are, in one respect, already easier than
extensions' equivalent story. The one area where this audit found a
genuine, non-trivial, non-mechanical design gap — inbound identification
for NOAUTH/IP-matched trunks (§7) — is deliberately **not** folded into
the same milestone as the rest: it is called out explicitly and pushed
to TASK-0016, once outbound provisioning (TASK-0015) has proven the
simpler, better-evidenced register-based case first. Two independent,
technology-agnostic, pre-existing bugs (P0-1, P0-2) must be fixed —
outside of PJSIP work entirely — before either milestone can be
validated against the real UI at all.

---

Stopping here for approval, at an audit commit checkpoint. No runtime
code, schema, or Docker configuration was changed. No PJSIP trunk
provisioning was implemented.
