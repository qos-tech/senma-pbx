# TASK-0011 — First SENMA-provisioned PJSIP extensions

## Status

**Implemented and validated.** `make smoke`: 16 PASS / 0 FAIL / 0
EXPECTED_LIMITATION (re-verified after a full clean rebuild). `make
call-smoke`: 18/18 PASS, re-verified after a full clean rebuild, run twice
in a row for idempotency, and against a simulated real-data collision to
confirm the safety stop path. No manual DB/config patching remained in
the final state — everything below reflects what the committed code
actually produces from a fresh `make dev`.

## Goal

Replace TASK-0009's static bootstrap PJSIP endpoints (1000/1001,
hand-written directly into `pjsip.conf`) with real SENMA-generated
provisioning: an extension created through SENMA's own UI persists,
generates native PJSIP config, reloads Asterisk, registers, and can call
another SENMA-provisioned extension through the existing, unmodified
AGI/rule engine — closing the loop TASK-0010 designed.

## Result summary

```
HTTP POST /index.php/default/extensions/add (technology=pjsip)
  -> peers row persisted (canal='PJSIP/1002')
  -> Snep_PjsipConf::loadConfFromDb() generates [1002]/[1002-auth]/[1002]
     (endpoint/auth/aor) into /etc/asterisk/snep/senma-pjsip.conf
  -> module reload res_pjsip.so (checked, not assumed)
  -> 1002 registers (baresip test harness)
  -> 1003 provisioned identically
  -> 1002 calls 1003 through the real, unmodified extensions.conf ->
     snep/snep.php -> PBX_Dialplan -> the pre-seeded "Internas - Ramal
     para Ramal" rule -> DiscarRamal -> PBX_Asterisk_Interface_PJSIP ->
     Dial(PJSIP/1003)
  -> real cdr_adaptive_odbc CDR row (src=1002, dst=1003, ANSWERED,
     duration/billsec > 0)
  -> SENMA's existing CallsReport API reads it back
  -> HTTP POST /index.php/default/extensions/remove cleans up; the
     generated file and Asterisk's own runtime both go back to
     containing nothing for 1002/1003, with no stale objects
```

Static 1000/1001 test endpoints are gone from `pjsip.conf` entirely --
production provisioning does not depend on them.

## 1. New generator architecture: `Snep_PjsipConf`

`snep/lib/Snep/PjsipConf.php` (new class), one public static method,
`loadConfFromDb()`, deliberately **not** a branch added to
`Snep_InterfaceConf` -- per TASK-0010 §3's explicit recommendation. A
chan_sip peer is one flat stanza; a PJSIP extension is three linked
objects sharing one identity. Reusing `Snep_InterfaceConf`'s per-tech
flat-stanza loop would have required either restructuring its
already-working chan_sip/IAX2 code to accommodate a fundamentally
different per-row shape, or bolting PJSIP logic into it via more
conditionals -- both contaminate the PJSIP model with chan_sip
assumptions, which CLAUDE.md's Phase 6 guidance explicitly warns against.

Responsibilities, matching TASK-0010 §1's spec exactly:
- Reads only `peer_type='R' AND canal LIKE 'PJSIP/%'` rows (trunks
  excluded -- deferred, §15 below).
- Generates one `[name]` endpoint + `[name-auth]` auth + `[name]` aor
  per row (§3 below).
- Writes only inside `/etc/asterisk/snep/` -- the exact subtree TASK-0009
  already made group-writable for this purpose.
- Triggers `module reload res_pjsip.so` and checks the response text for
  success before returning (§7).

Called from `ExtensionsController` at the same four points
`Snep_InterfaceConf::loadConfFromDb()` already is (`execAdd()`,
`removeAction()`, `disableAction()`, `enableAction()`) --
**unconditionally**, matching TASK-0010's recommendation: each generator
filters to its own `canal` prefix internally, so calling both on every
write is harmless regardless of which technology the touched extension
actually uses (confirmed: a PJSIP row is invisible to `Snep_InterfaceConf`'s
`LIKE 'SIP%'`/`'IAX2%'` filters, and vice versa).

Full-stateless-rewrite property preserved, same as `Snep_InterfaceConf`:
every call reflects exactly the current `peers` table, so create/edit/
delete/disable all "just work" with no incremental diff/cleanup logic --
verified live (§8).

## 2. Generated file ownership

Exactly the architecture TASK-0010 §5 recommended:

```
/etc/asterisk/pjsip.conf                  <- static, project-owned
    [transport-udp]
    #include snep/senma-pjsip.conf        <- generated, SENMA-owned
```

`docker/asterisk-config/pjsip.conf` now holds only the transport (and
would hold any future global PJSIP settings) -- no endpoint/auth/aor of
any kind. The generated file lives in `/etc/asterisk/snep/`, the same
writable subtree (setgid, `senma-config` group, GID 3000) TASK-0009 built
ahead of schedule for exactly this. `docker/asterisk-entrypoint.sh`
pre-creates `senma-pjsip.conf` (`touch` + `chmod 664`) on first boot --
`is_writable()` returns false for a path that doesn't exist yet, so the
generator would fail its own write check on a brand new volume otherwise.

The generated file:
- **Deterministic**: same `peers` state always produces byte-identical
  output (only the `; Generated: <timestamp>` header line varies).
- **Human-readable**: plain PJSIP ini syntax, one blank-line-separated
  section per object.
- **Clearly marked as generated**: an explicit header states it is
  rewritten in full on every write and manual edits are lost.
- **Safe to regenerate**: verified live -- deleting an extension and
  reloading leaves the file containing only the remaining extensions'
  sections, byte-for-byte what a fresh generation from the current DB
  produces.
- **Free of secrets in comments/logs**: the only place any secret
  appears is the actual `password=` line inside the real `[name-auth]`
  section (the same place chan_sip's own generated `secret=` line has
  always put it) -- never in the header, never in the reload-failure log
  message (which logs Asterisk's own response text, never file content).

### A real, pre-existing filesystem gap this task also had to fix

TASK-0009's `asterisk-entrypoint.sh` `chgrp`+`chmod 2775` on
`/etc/asterisk/snep` only affects the directory's own attributes and
files created *after* that point via the setgid bit -- it does **not**
retroactively fix the permissions of files the entrypoint's own earlier
`cp "$SNEP_ASTERISK_CONFIG_SRC"/*.conf` step had already placed inside
that directory moments before. `snep-sip.conf`/`snep-sip-trunks.conf`
were sitting at `0644 asterisk:asterisk` -- not group-writable, not even
group-owned by `senma-config`. This meant `Snep_InterfaceConf::
loadConfFromDb()` (chan_sip provisioning) has been silently unable to
write from the `app` container since TASK-0009, a gap nothing had
exercised yet (TASK-0009 only *called* a PJSIP extension, it never
*provisioned* anything through the UI). Reproduced live
(`SQLSTATE`-free but a plain "Falha ao abrir arquivo ... com permissão de
escrita" from `Snep_InterfaceConf`'s own `is_writable()` check) the first
time this task tried to create an extension through the real UI. Fixed
by explicitly `chgrp`+`chmod 664`-ing the already-copied files right
after the `cp`, in addition to the directory-level fix TASK-0009 already
had.

## 3. Object naming

Exactly TASK-0010 §6's recommendation, using `peers.name` deterministically:

```
endpoint: <name>          e.g. 1002
aor:      <name>          e.g. 1002   (MUST equal the endpoint name)
auth:     <name>-auth     e.g. 1002-auth
```

`aor == name` is not a style choice -- `res_pjsip_registrar` matches the
REGISTER URI's username directly against an AOR object's own sorcery
name, confirmed as a hard requirement during TASK-0009. `Snep_PjsipConf`
literally reuses the DB row's own `name` column for both the `[name]`
endpoint section and the `[name]` aor section (two separate sorcery
namespaces, `type=endpoint` vs `type=aor`, legal and idiomatic, same
pattern already proven in TASK-0009's static config).

### Lifecycle, verified live (not just designed)

- **Create**: POSTed extension 1002 -> `[1002]`/`[1002-auth]`/`[1002]`
  appear in the generated file and in `pjsip show endpoint 1002`/
  `pjsip show aor 1002`.
- **Edit**: changed 1002's secret and caller ID through the real edit
  flow -> the generated file's `[1002-auth]` `password=` line updated;
  a baresip instance still configured with the *old* secret got a real
  `401 Unauthorized` from Asterisk on its next REGISTER attempt; updating
  it to the *new* secret got `200 OK`. Proves the reload is real, not
  cosmetic.
- **Delete**: removed extension 1002 through the real delete flow ->
  the generated file no longer contains any `[1002...]` section at all
  (confirmed byte-for-byte against what remained: only 1003's sections);
  `pjsip show endpoint 1002`/`pjsip show aor 1002` both returned
  `Unable to find object 1002` -- fully gone from Asterisk's live runtime,
  not just the file.
- **Rename / extension-number change**: not reachable through the
  current UI at all -- confirmed by reading `ExtensionsController::
  editAction()`, which unconditionally overwrites the posted `exten`
  with the URL's `id` parameter before calling `execAdd()`, exactly as
  TASK-0010 §1/§6 found. Not implemented here (nothing to implement --
  the full-rewrite generator would handle it for free if the UI ever
  allowed it, per TASK-0010 §6).
- **Stale objects**: none possible by construction -- every write is a
  full regeneration from the current `peers` table (§1), not an
  incremental diff.
- **Duplicate usernames/endpoint IDs**: already prevented for free by
  `peers.name`'s existing `UNIQUE KEY` and `execAdd()`'s own pre-check
  (unchanged, untouched) -- no new duplicate-checking logic was needed or
  added.

## 4. Field mapping

Implemented exactly the fields TASK-0010 classified as safe, using the
exact translations it specified, tightened by this task's own explicit
"do not invent ambiguous mappings" instruction (narrower than what
TASK-0010's own doc had tentatively floated for the NAT `auto_*` case --
see below):

| Field | Mapping | Evidence |
|---|---|---|
| `secret` | `[name-auth]` `password=` (`auth_type=userpass`) | Direct, zero translation -- PJSIP's plaintext userpass mode needs exactly what's already stored (TASK-0010 §7) |
| `context` | endpoint `context=` | Passthrough, identical option name in both technologies |
| `callerid` | endpoint `callerid=` | **Verbatim**, not reassembled -- the DB value is already the full `"Display Name <exten>"` string (composed once in `addAction()`), exactly how `Snep_InterfaceConf`'s own chan_sip `callerid=` line already treats it |
| `language` | endpoint `language=` | Direct, identical option name/semantics in both technologies. **Also fixed a real, pre-existing, technology-agnostic bug found while wiring this up**: `execAdd()`'s default-fields array hardcoded `'pt_BR'` (5 chars) for a `CHAR(2)` column (`schema.sql`), which has *always* overflowed under strict SQL mode (`SQLSTATE[22001]`) -- silently made creating *any* extension via the real UI impossible, for any technology, never caught because nothing exercised the create flow before. Fixed to the column's own correct native default, `'br'`, in both `execAdd()` and `Snep_PjsipConf`'s fallback |
| `dtmfmode` | endpoint `dtmf_mode=` | Translated, not passthrough: `rfc2833` -> `rfc4733` (confirmed against `res_pjsip.c`'s `ast_sip_str_to_dtmf()` -- `"rfc2833"` is **not** a recognized PJSIP value, only `"rfc4733"` is; passing it through verbatim would have been silently wrong). `inband`/`info` are identical in both |
| `allow`/`disallow` | endpoint `allow=`/`disallow=all` | **Zero new logic** -- reused the exact `;`-split/`,`-join transformation `Snep_InterfaceConf.php` already uses for chan_sip (TASK-0010 §8: codec names/syntax are shared between the two technologies) |
| `qualify` | aor `qualify_frequency=` | Boolean-to-interval: `no` -> `0` (literal/direct -- 0 means disabled in both models); `yes` -> `60` (a *chosen* default, not derived from any DB value -- documented as such, not asserted as evidence-backed, per TASK-0010 §9) |
| `nat` (force_rport/comedia tokens) | endpoint `force_rport=`/`rtp_symmetric=` | Direct: literal `force_rport` token -> `force_rport=yes` (identical option name in chan_sip and PJSIP); literal `comedia` token -> `rtp_symmetric=yes` (well-established Asterisk-wide conceptual correspondence) |
| `directmedia` | endpoint `direct_media=` (+ `disable_direct_media_on_nat=`/`direct_media_method=` where applicable) | `yes`->`direct_media=yes`; `no`->`direct_media=no`; `nonat`->`direct_media=yes`+`disable_direct_media_on_nat=yes`; `update`->`direct_media=yes`+`direct_media_method=update` -- all named, direct correspondences per TASK-0010 §9 |

### Deliberately NOT mapped (ambiguous, per explicit instruction)

- **`rewrite_contact`**: no source field in `peers` at all. TASK-0010's
  own doc had tentatively suggested inferring it from whether any NAT
  checkbox was set; this task's explicit instruction ("Do NOT invent
  mappings for ... rewrite_contact semantics") overrides that. Left
  unset -- Asterisk's own compiled endpoint default (`no`) applies by
  omission. **Deferred product decision**: if NAT'd PJSIP endpoints need
  Contact-rewriting, a UI field or a different inference rule needs an
  explicit decision, not an inferred one.
- **`nat_auto_force_rport`/`nat_auto_comedia`**: chan_sip's "auto" NAT
  variants have no PJSIP equivalent (`force_rport`/`rtp_symmetric` are
  plain booleans, no "auto" mode). TASK-0010's doc had tentatively
  suggested collapsing "auto" into "yes"; this task's explicit
  instruction ("Do NOT invent mappings for ... auto_* NAT modes")
  overrides that too. An extension whose only selected NAT checkboxes are
  the `auto_*` ones gets **no** PJSIP NAT accommodation at all
  (`force_rport=no`, `rtp_symmetric=no`) -- the safe, explicit,
  documented default, not a silent approximation. **Deferred product
  decision**: whether "auto" should map to anything at all needs an
  explicit choice, not an inference.
- **`directmedia=outgoing`**: no PJSIP equivalent (`direct_media` isn't
  direction-scoped in PJSIP). Falls back to the same conservative default
  as `directmedia=no` (`direct_media=no`) rather than an invented
  approximation. **Deferred product decision**, per TASK-0010 §9.
- **`type` (friend/peer/user)**, **`host`** (`'dynamic'`): both
  structurally obsolete for PJSIP (TASK-0010 §2) -- not read by the
  generator at all, matching chan_sip's own field usage already (`type`
  is stored but this doesn't change what the generator emits).
- **`callgroup`/`pickupgroup`**: **not** emitted as PJSIP config, matching
  chan_sip parity exactly -- TASK-0010 §2 confirmed `pickupgroup` is
  consumed entirely at dialplan runtime (`DiscarRamal`'s
  `set_variable('__PICKUPMARK', ...)`), technology-agnostic already and
  unaffected by this task; `callgroup` is dead for extensions in both
  technologies.
- **`mailbox`**: **not** emitted (no `mailboxes=` on the endpoint) --
  chan_sip's own generated stanza never emits `mailbox=` either
  (voicemail is invoked as a dialplan action, not via the channel
  driver's native mailbox option, TASK-0010 §2). Emitting it now would be
  *new* native-MWI behavior, not preserved behavior -- deliberately not
  added. **Deferred, optional future enhancement**, not a migration
  requirement.

## 5. UI/model integration

Minimum change, per TASK-0010 §12's classification -- no field redesign,
one new `<option>` plus targeted show/hide wiring:

- `snep/modules/default/views/scripts/extensions/addedit.phtml`: added
  `<option value="pjsip">PJSIP</option>` to the existing technology
  `<select>`. Wrapped the `type` (friend/peer/user) radio group in
  `id="typeSelector"` (previously unwrapped) so it can be hidden
  specifically for PJSIP without affecting SIP/IAX2, which still use it.
  `showDiv()` (JS) extended: PJSIP now shows the same `siponly`
  (NAT/direct-media) and `sipiax` (codecs/DTMF/qualify) field groups SIP
  already shows -- reusing existing fields, not building new ones, per
  TASK-0010's explicit recommendation -- while hiding `typeSelector`
  (shown only for `sip`/`iax2`, which still have a real PJSIP-incompatible
  `type` concept).
- `ExtensionsController::editAction()`: added `case "pjsip":` alongside
  `case "sip":` in the switch that populates view state for the edit
  form -- PJSIP reuses the exact same field population logic.
- `ExtensionsController::execAdd()`: extended three existing
  `$techType == 'sip' || $techType == 'iax2'` conditions (NAT checkbox
  parsing, qualify checkbox, codec assembly) to also include `'pjsip'` --
  without this, a PJSIP submission would have silently fallen through to
  the `else` branches meant for khomp/virtual/manual (codec forced to
  `"ulaw"`, `nat`/`qualify` left unset).

No chan_sip-only option is exposed with false PJSIP semantics: `type`
is hidden for PJSIP in the view; `host`/`insecure`/`deny`/`permit`/`mask`
were never exposed in this form for any technology and remain that way.

## 6. Persistence

No schema change -- confirmed unnecessary by TASK-0010 (§2/§4/§7) and
re-confirmed here by actually shipping the feature without one. PJSIP
extensions live in the existing `peers` table exactly like SIP/IAX2 rows,
distinguished only by `canal='PJSIP/<name>'`, which the already-existing,
unmodified `PBX_Usuarios::get()`/`PBX_Asterisk_Interface_PJSIP` (both from
TASK-0009) already dispatch on correctly.

### Two more real, pre-existing, technology-agnostic bugs found and fixed while making the create flow work at all

Both blocked creating **any** extension (any technology) through the
real UI under this project's strict SQL mode, and both were only ever
surfaced now because this is the first task to actually exercise
`ExtensionsController::execAdd()` via a real HTTP POST rather than direct
SQL or `make smoke`'s read-only GET checks:

- **`lastms`** (`schema.sql`: `int(11) NOT NULL`, no column default) was
  entirely absent from `execAdd()`'s `INSERT` column list ->
  `SQLSTATE[HY000]: 1364`. Fixed by adding it to the existing
  `$defFielsExten` default-fields mechanism (`lastms => 0`, matching the
  placeholder value a never-yet-qualified chan_sip peer already shows).
- **`language`** (§4 above) -- the `CHAR(2)` vs `'pt_BR'` overflow.

Also found, and fixed for the same "blocks the current milestone" reason
(CLAUDE.md's bug policy: document and defer unless it blocks; this
blocked reaching the point where TASK-0010's actual object-model design
could even be exercised): a stray `<?php//` (missing space) in
`addedit.phtml` tokenized as the bareword constant `php` under PHP 8,
fataling the *entire* add/edit page for every technology
(`docs/tasks/0001-docker-bootstrap.md`'s original audit already flagged
this exact file/line as known-but-unfixed debt; TASK-0006's project
memory recorded it too). One-character fix (`<?php //`), matching the
established bareword-constant fix pattern from TASK-0002/0004.

## 7. Reload behavior

`module reload res_pjsip.so` -- the exact mechanism TASK-0010 §10
validated against this Asterisk 22.10.1 build (`pjsip reload` is not a
real command; a full Asterisk reload was explicitly rejected as
unnecessarily broad). `Snep_PjsipConf::reload()` (private method) issues
this via the existing `PBX_Asterisk_AMI::getInstance()->Command(...)`
path and, **unlike** `Snep_InterfaceConf`'s three reload calls (which
have never checked their return value, a real pre-existing gap TASK-0010
§10 documented rather than silently matched), inspects Asterisk's own
response text for the `"reloaded successfully"` substring and throws
`PBX_Exception_IO` (after logging the actual response via
`Zend_Registry::get('log')`) if it isn't present -- surfacing failure
instead of silently claiming success, per this task's explicit
instruction. `ExtensionsController` does not additionally catch this
exception (matches the exact same, already-existing, unmodified pattern
`Snep_InterfaceConf::loadConfFromDb()`'s own `PBX_Exception_IO` already
has at every one of these call sites -- not a new gap introduced here).

## 8. `call-smoke` fixture strategy

**Highest-level stable interface used: the authenticated HTTP controller
flow (option B from the instruction's own list), not the internal API
(option A) and not the manager/service layer directly (option C).**

Why B, not A: inspected `snep/modules/default/api/actions/` --  every
existing service there (`CallsReportService`, `RankingReportService`,
`ServicesReportService`, ...) is **read-only**. There is no
write-capable "create/edit/delete an extension" API endpoint at all.
Introducing one purely to make this test easier would itself be new
scope this task doesn't need.

Why B, not C: calling `Snep_PjsipConf`/the manager classes directly would
prove the *generator* can render a row correctly -- something already
exhaustively verified manually (§3) -- but not that the actual
user-facing create/edit/delete flow, the thing this entire task exists to
prove, works end to end. `ExtensionsController::addAction()`/
`removeAction()` contain real logic (duplicate-name checking, NAT/codec/
qualify assembly, voicemail/group side effects, the `Snep_InterfaceConf`
+ `Snep_PjsipConf` dual-generator call) that a direct manager-layer call
would bypass entirely.

`scripts/call-smoke-test.sh` (rewritten):
- Logs in as the existing smoke-test admin account (same idempotent
  password-reset pattern `scripts/smoke-test.sh` already uses).
- **Test range**: `1002`/`1003` (per the instruction's own suggested
  range) -- clearly outside TASK-0009's now-removed `1000`/`1001` and any
  plausible real low-numbered production extension range.
- **Collision detection** (still a read-only DB check, not a mutation):
  queries `peers` for `1002`/`1003` before touching anything. A row that
  matches this run's own fixture-secret prefix pattern
  (`task0011-fixture-*`) is treated as a leftover from a previous
  incomplete run and removed **via the same HTTP delete flow**, then
  recreated fresh. A row that exists and does **not** match the fixture
  pattern **STOPs** the script immediately (no write, no HTTP call at
  all) with an actionable message -- verified live by pre-inserting a
  real-looking `SIP/1002` row and confirming the script refused to touch
  it, leaving the row completely intact.
- **Provisioning**: `create_extension()` POSTs to
  `/index.php/default/extensions/add` with `technology=pjsip` and every
  field `execAdd()` reads (NAT checkboxes, qualify, codecs, directmedia,
  dtmf, etc.), exactly matching what the real browser form submits.
  Success is a `302` redirect to the extensions list (the same signal
  `execAdd()`'s own caller already uses to distinguish success from a
  returned error string).
- **New checks added** (item 11 of the task spec, beyond what TASK-0009's
  version of this script had): after provisioning, before attempting
  registration, the script now asserts the generated file actually
  contains `[1002]`/`[1002-auth]`/`[1003]`/`[1003-auth]`, and separately
  that `pjsip show endpoint <ext>` / `pjsip show aor <ext>` both find the
  object in Asterisk's live runtime -- config-file generation alone is
  never treated as success.
- **Call/CDR/report checks**: structurally unchanged from TASK-0009's
  version (same baresip harness, same ctrl_tcp dial/event-stream
  approach, same AGI-log-trace assertion, same CDR field checks, same
  report-readback check), only the extension numbers and secrets
  changed.
- **A real timing issue found and fixed while re-validating this flow**:
  hanging up via `channel request hangup all` immediately after
  `CALL_ESTABLISHED` raced with the dialplan's own
  `GET VARIABLE DIALSTATUS` AGI read (the channel could already be torn
  down by the time `snep.php` tried to read it, since `channel request
  hangup all` initiates an asynchronous teardown, not a synchronous one).
  The script now waits 5s after `CALL_ESTABLISHED` before issuing the
  hangup, matching the settled `Up` state confirmed via `core show
  channels` before proceeding.
- **Cleanup**: `delete_extension()` POSTs to
  `/index.php/default/extensions/remove` for both fixtures in an `EXIT`
  trap (self-disarming against double-invocation, matching TASK-0009's
  pattern) -- proving the delete lifecycle on every single run, not just
  once manually. No raw SQL fallback for cleanup; a failed HTTP delete
  logs a warning for manual follow-up rather than silently reaching for
  SQL.
- **Idempotency**: run twice back-to-back, both 18/18 -- the second run's
  own collision-detection-and-self-heal path (against the first run's own
  fixture markers, which shouldn't normally still exist post-cleanup, but
  the mechanism was exercised and confirmed correct regardless) and full
  cleanup both worked identically.

## 9. Registration and real-call evidence

Live output from the final, clean-rebuild `make call-smoke` run:

```
PASS: PJSIP modules Running -- res_pjsip.so and chan_pjsip.so both Running
PASS: test fixtures available -- 1002/1003 provisioned through SENMA's real create-extension HTTP flow
PASS: generated endpoint/auth/aor sections exist -- senma-pjsip.conf contains [1002], [1002-auth], [1003], [1003-auth]
PASS: pjsip show endpoint 1002 -- endpoint exists in the live Asterisk PJSIP config (reload succeeded)
PASS: pjsip show aor 1002 -- aor exists in the live Asterisk PJSIP config
PASS: pjsip show endpoint 1003 / pjsip show aor 1003 -- same
PASS: endpoint 1002 registered -- contact bound to AOR 1002 within 15s
PASS: endpoint 1003 registered -- contact bound to AOR 1003 within 15s
PASS: call placed / destination receives call / destination answers / call remains established
PASS: hangup succeeds -- 0 active channels after hangup
PASS: AGI/rule path was exercised -- snep.php ran, matched the seeded rule, dialed PJSIP/1003
PASS: CDR row exists and is correct -- uniqueid=1787684505.0 disposition=ANSWERED duration=15 billsec=15 channel=PJSIP/1002-00000000
PASS: SENMA reporting path can read it -- CallsReport API endpoint returned this exact CDR
================================================================
PASS: 18   FAIL: 0
```

Asterisk's own dialplan trace for that call (confirming the real,
unmodified AGI/rule engine ran -- **not** a test-only
`Dial(PJSIP/1003)` bypass):

```
Executing [1003@default:10] AGI(..., "snep/snep.php")
Launched AGI Script .../snep/snep.php
snep.php: 1002 -> 1003 INFO: Identified source: 1002 (Snep_Exten)
snep.php: 1002 -> 1003 INFO: Running the rule 1:Internas - Ramal para Ramal
snep.php: 1002 -> 1003 INFO: Discando para ramal 1003 no canal PJSIP/1003.
AGI Script Executing Application: (Dial) Options: (PJSIP/1003,60,twk)
...
End of running the rule 1:Internas - Ramal para Ramal -> billsec: 15 -> duration: 15
```

### A third real, pre-existing bug found and fixed to get a clean trace at all

The first several attempts at this exact call produced garbage:
`get_variable("DIALSTATUS")` came back as the literal string
`"Invalid or unknown command"` instead of `"ANSWER"`, even though the
call had genuinely been answered and bridged for 9+ seconds (confirmed
via `core show channels verbose` showing both legs `Up`). Root cause,
found via `agi set debug on`: `snep.php`/`agi_base.php` both set
`ini_set('display_errors', 1)` -- and **STDOUT is the AGI protocol
channel** back to Asterisk. Any PHP notice/warning/deprecation printed
there gets read by Asterisk as if it were a malformed AGI command
(logged as `AGI Tx >> 510 Invalid or unknown command`), which then also
corrupts the *next* real command in the same exchange. PHP 8.4
introduced a new deprecation (`Zend_Db_Statement::execute(): Implicitly
marking parameter $params as nullable is deprecated`) that fires on
effectively every database query this Zend 1-based codebase makes --
this had presumably always been silently corrupting *something* in every
AGI call since TASK-0009, just never observably, because TASK-0009's
raw-SQL-inserted 1000/1001 fixtures had `mailbox=NULL`
(`Snep_Exten::hasVoiceMail()` returns `false`), so a misread `DIALSTATUS`
harmlessly fell through `DiscarRamal`'s `switch` default case. Extensions
created through the *real* UI always get `mailbox=<exten>` (`execAdd()`),
so `hasVoiceMail()` returns `true` regardless of whether voicemail was
actually enabled -- **a fourth real, pre-existing bug**, noted below but
not fixed (out of scope) -- which meant the misread DIALSTATUS instead
triggered a live, disruptive `voicemail()` app call on an
already-answered/already-hanging-up channel, which is what made the
corruption visible as a complete CDR failure rather than a harmless log
line.

Fixed by changing `display_errors` from `1` (stdout) to `0` (fully off)
in both `snep/agi/snep.php` and `snep/agi/agi_base.php`, and adding
`log_errors = On` / `error_log = /dev/stderr` to `docker/php-agi.ini` --
the same `display_errors=Off` + `log_errors=On` pattern
`docker/php-mag.ini` already uses for the web app, for the exact
equivalent reason (there: notices breaking HTTP headers; here: notices
breaking the AGI protocol). `display_errors='stderr'` was tried first
and rejected: confirmed empirically that php-cgi (unlike CLI) does not
reliably honor it -- the HTML-formatted deprecation text still leaked to
stdout even with `'stderr'` set.

## 10. CDR and report-readback evidence

```sql
calldate             src   dst   disposition duration billsec uniqueid        channel            dstchannel
2026-08-25 18:59:25  1002  1003  ANSWERED    15       15      1787684365.2    PJSIP/1002-...     PJSIP/1003-...
```

```json
{"status":"ok","data":[{"disposition":"ANSWERED","billsec":15,"src":"1002","dst":"1003",
  "uniqueid":"1787684365.2","calldate":"2026-08-25 18:59:25","dstchannel":"PJSIP/1003-...", ...}]}
```

Both from the real, unmodified `cdr_adaptive_odbc` backend (TASK-0007)
and the real, unmodified `CallsReportService.php` API endpoint
(TASK-0009 fixed its one PHP 8.4 `count()` bug; untouched here) -- no
manual DB insert, no SQL-only proof.

## 11. Cleanup/delete evidence

Covered in full in §3 (object naming/lifecycle) and §8
(`call-smoke`'s own HTTP-based cleanup, exercised on every run).

## 12. Regression

`make smoke`: 16 PASS / 0 FAIL / 0 EXPECTED_LIMITATION, re-verified after
a full clean rebuild (both `asterisk-etc` and `astvarlibdir` volumes
wiped) and again immediately after a `make call-smoke` run (to rule out
cross-contamination from the create/edit/delete cycle) -- `before=0/
after=0` new PHP Fatal Errors both times.

`make call-smoke`: 18/18, re-verified after the same full clean rebuild,
run twice back-to-back for idempotency, and once against a simulated
real-data collision (confirmed the script stops immediately with no
write and the real row left byte-for-byte intact).

Logs inspected per the task's explicit requirement: app/PHP error log
(only pre-existing, already-known warning patterns --
`compact(): Undefined variable $extras`, a few `systemstatus`/
`CallsReportController` array-key notices -- zero new fatals); AGI logs
(now correctly routed to `docker compose logs asterisk` via
`error_log=/dev/stderr` instead of corrupting the AGI stream, §9);
Asterisk's own log (only the pre-existing, harmless
`res_pjsip_config_wizard.c: Unable to load config file 'pjsip_wizard.conf'`
decline -- an optional feature this project has never configured, not a
regression); no new ODBC/CDR errors.

## Files changed

- `snep/lib/Snep/PjsipConf.php` (new) -- the generator, §1-§4.
- `docker/asterisk-config/pjsip.conf` -- static transport only, 1000/1001
  removed, §2.
- `docker/asterisk-entrypoint.sh` -- pre-creates `senma-pjsip.conf`;
  fixes the chan_sip file-permission gap (§2); the now-unused
  `PJSIP_TEST_*` templating removed.
- `.env.example` -- `PJSIP_TEST_1000_SECRET`/`1001_SECRET` removed (no
  longer used by anything).
- `docker/php-agi.ini` -- `log_errors`/`error_log` added, §9.
- `snep/agi/snep.php`, `snep/agi/agi_base.php` -- `display_errors` fix,
  §9.
- `snep/modules/default/controllers/ExtensionsController.php` --
  `Snep_PjsipConf` calls; NAT/qualify/codec conditions extended to
  `pjsip`; `case "pjsip":` in `editAction()`; `lastms`/`language`
  fixes, §6.
- `snep/modules/default/views/scripts/extensions/addedit.phtml` -- PJSIP
  option, `typeSelector` id, `showDiv()` update, the `<?php//` fix, §5-§6.
- `scripts/call-smoke-test.sh` -- rewritten for HTTP-driven fixtures,
  §8-§9.

## 13. Remaining trunk/provisioning debt (explicitly deferred)

Unchanged from TASK-0010 §15, restated as this task's own scope boundary:

- **PJSIP trunks**: `Snep_InterfaceConf`'s trunk branch is materially
  more complex than its extension branch (multiple sub-types keyed on
  `trunks.type`) and was not touched; `Snep_PjsipConf` explicitly
  excludes `peer_type='T'` rows. A separate task.
- Outbound registrations, inbound trunk identification -- both trunk
  concerns, not reached.
- `rewrite_contact`, the NAT `auto_*` modes, and `directmedia=outgoing`
  -- three explicit, documented product decisions still needed (§4), not
  silently resolved.
- `mailboxes=` native MWI on the PJSIP endpoint -- optional future
  enhancement, not a migration requirement (§4).
- `Snep_Exten::hasVoiceMail()` returning `true` whenever `mailbox` is
  non-null (regardless of `usa_vc`) -- a real, pre-existing, entirely
  technology-agnostic logic bug (§9) that predates PHP 8.4 and predates
  PJSIP entirely. Documented here as found; not fixed (unrelated to this
  migration, per CLAUDE.md's bug policy -- it doesn't block this
  milestone once `display_errors` no longer corrupts the DIALSTATUS
  read, since a correctly-read `"ANSWER"` never reaches the buggy branch
  in the first place).
- `snep/agi/voicemail-notify.php`'s identical `display_errors=1` --
  same bug class as §9, but this script is invoked by Asterisk as a
  plain `externnotify=` external command, not over the AGI stdin/stdout
  protocol, so it cannot corrupt an AGI exchange the way `snep.php`/
  `agi_base.php` could. Left unfixed -- out of the tested call path,
  voicemail is explicitly deferred scope.
- Voicemail migration, queue migration beyond TASK-0007, IVR changes,
  WebRTC, TLS/WSS, PostgreSQL, broad frontend redesign -- none touched.
- Schema redesign -- confirmed unnecessary throughout (§6); none made.

---

Stopping at a commit checkpoint. Trunk migration not started.
