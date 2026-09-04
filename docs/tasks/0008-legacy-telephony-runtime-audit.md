# TASK-0008 — Legacy telephony runtime audit

## Status
**Audit only.** No application, Asterisk, Docker, database, AGI, dialplan,
or PJSIP configuration was changed. All findings below are sourced from
direct inspection of the current tree, the current running stack, and the
vendored `snep/install/etc/asterisk/` config, cross-checked against
Asterisk 22.10.1's own source/behavior where relevant. `git status` is
clean; `make smoke` remains 16/0/0.

## Central architectural finding (governs the whole audit)

SENMA does **not** generate per-extension/per-route Asterisk dialplan
text. `snep/install/etc/asterisk/extensions.conf` is a small, fixed,
hand-authored skeleton — the same file for every deployment — whose only
real job is to funnel every call into a single AGI script,
`snep/agi/snep.php`. That script instantiates `PBX_Dialplan`, which loads
**every** business rule from the database (`PBX_Rules::getAll()`) and
picks the first one whose `isValidSrc()`/`isValidDst()`/`isValidTime()`
conditions match the call's origin/destination/time — then executes that
rule's ordered list of `PBX_Rule_Action` objects (`DiscarRamal`,
`DiscarTronco`, `Queue`, `GoContext`, `Playback`, ...) by issuing AGI
`EXEC` commands (`Dial`, `Queue`, `VoiceMail`, ...) over the live AGI
channel. **Internal, outbound, and inbound calls all flow through this
exact same mechanism** — they differ only in which DB rule matches, not
in a different code path. This has two large consequences for the whole
audit:
- Extension/trunk **channel-technology strings** ("SIP/1000") are
  resolved once, centrally, by `PBX_Asterisk_Interface_SIP::getCanal()`
  (and its `IAX2`/`VIRTUAL`/`KHOMP` siblings) — not scattered across
  dialplan text. A PJSIP migration's *runtime* surface is small and
  concentrated.
- The chan_sip migration's real complexity is almost entirely in
  **provisioning** (how the DB → static Asterisk peer config generator
  works), not in dialplan logic.

## 1. Dialplan architecture map

| Source | Generator | Runtime destination | SENMA UI writes it? | Required for current call routing? |
|---|---|---|---|---|
| `snep/install/etc/asterisk/extensions.conf` | Hand-authored, vendored, static — **not** generated per-deployment | `/etc/asterisk/extensions.conf` (not currently deployed in this Docker topology — `pbx_config` declines, no file provided, TASK-0005's deliberate minimal scope) | No | Yes — this is the only entry point into `PBX_Dialplan` |
| `[default]` context | same file | catch-all `_.`  pattern → `AGI(snep/snep.php)` | No | **Yes — the actual call path for every call** |
| `[khomp-fxs]` context | same file | Khomp hardware only | No | No — no Khomp hardware in this topology |
| `[transferencias]` context | same file | call-transfer re-entry into `snep.php -x` | No | Yes, for transfers |
| `[ramais-agentes]` / `[macro-dialpeer]` | same file | uses `Macro()` (see §6) | No | **No evidence it's reachable** — nothing in SENMA's DB-writing code (`Snep_InterfaceConf`) ever sets a peer's `context` to `ramais-agentes`; would require manual out-of-band DB editing |
| `[monitor]` context | same file | `AGI(snep/monitor.php)` for recording control | No | Feature-specific (call recording toggle) |
| `snep/snep-features.conf`, `custom/{preagi,posagi,eof}.conf` | vendored hook files, `#include`d by `extensions.conf` | parking/local customization hooks | No (`posagi.conf`/`eof.conf` are comment-only; `preagi.conf` is **not** empty — see correction below | Parking feature only |
| `snep/snep-conferences.conf`, `snep/snep-parkedcalls.conf` | `#include`d; **written by `ConferenceRoomsController.php`** | conference room / parked-call dialplan stanzas | **Yes** — the one real exception to "no generated dialplan" | Yes, for the Conference Rooms feature specifically |
| `snep/lib/Snep/Locale.php` (`setExtensionsLanguage()`) | rewrites (sed) `extensions.conf`'s `SNEP_LANGUAGE` global | same file | Yes (language switch in Settings) | Yes, for the language-switch feature |
| Realtime/DB-driven dialplan | **none** | — | — | Confirmed: no `extensions`/`ael`-family realtime mapping exists anywhere (`extconfig.conf` never mapped it, legacy or current) |
| AGI entrypoints referenced by dialplan | `snep/agi/*.php` (16 files, see §5) | invoked via `AGI(snep/X.php, args)` lines in `extensions.conf` and from within `PBX_Rule_Action::execute()` via AGI `EXEC` | No | See §5 per-file classification |

## 2. Outbound call trace (extension → external number)

```
PJSIP/SIP endpoint (extension)
  → [default] context, catch-all `_.` pattern
  → AGI(snep/snep.php)                                  [snep.php]
  → PBX_Dialplan::parse()                                [DB: reads every row PBX_Rules::getAll() returns]
  → matches a Route rule (Snep_Route / route table) whose isValidDst() matches the dialed number
  → PBX_Rule::execute() walks the rule's ordered PBX_Rule_Action list
  → (typically) DiscarTronco::execute()                  [modules/default/actions/DiscarTronco.php]
      - PBX_Trunks::get($trunkId)                         [DB: trunks table]
      - trunk time-limit check                            [DB: trunks + time_history tables]
      - $tronco->getInterface()->getCanal()                [PBX_Asterisk_Interface_SIP/IAX2/VIRTUAL/KHOMP]
      - $asterisk->exec_dial($destiny, timeout, flags)     [AGI EXEC of Dial(), AMI-independent — this is the AGI protocol, not AMI]
      - reads DIALSTATUS via AGI get_variable
  → back in snep.php: reads CDR(billsec)/CDR(duration)/CDR(uniqueid)/etc. via AGI get_variable
  → if Billing module present: Billing_Manager->rate($bill)  [DB: billing/telcos/rated_calls tables]
  → Asterisk's own native CDR engine writes the row (cdr_adaptive_odbc, TASK-0007) — SENMA does not
    write CDR itself; it only *reads back* CDR channel variables for billing/logging purposes
```
Filesystem dependency: call recording path built from `path_voz`
(`setup.conf`) + `core_config` DB table's `userfield` naming template,
independent of the trunk's channel technology.
No AMI interaction on this path at all — everything is AGI (a different
protocol/connection than AMI, per-call, not the persistent AMI socket
used by the web app).

## 3. Internal call trace (Extension A → Extension B)

Same entry (`[default]` → `snep.php` → `PBX_Dialplan::parse()`), matching
a rule whose action is `DiscarRamal` instead of `DiscarTronco`
(`modules/default/actions/DiscarRamal.php`):
- **Destination resolution**: `PBX_Usuarios::get($exten)` — DB: `peers`
  table, `WHERE name=... AND peer_type='R'`.
- **Channel technology assumed**: whatever `peers.canal`'s prefix says
  (`SIP/`, `IAX2/`, `MANUAL/`, `VIRTUAL/`, `KHOMP/`) — resolved once via
  `PBX_Asterisk_Interface_*::getCanal()`, not hardcoded per-call.
- **Dial() construction**: `$asterisk->exec_dial($canal, $timeout,
  $flags)` — plain AGI EXEC, technology-agnostic.
- **DND**: `$ramal->isDNDActive()` short-circuits before dialing (DB
  column, technology-independent).
- **Follow-me**: recursively re-invokes a *new* `PBX_Dialplan::parse()`
  against a synthetic request pointing at the follow-me destination —
  same generic mechanism, not a special case.
- **Distinctive ring** (`diff_ring`): the one place internal dialing is
  chan_sip-specific — `if ($tech == "SIP") { $asterisk->exec('SIPAddHeader', 'Alert-Info: Bellcore-r3'); }`
  — silently does nothing for any other technology today, including a
  future PJSIP tech (needs a `PJSIP_HEADER`-based branch to keep working).
- **Busy/no-answer/unavailable**: standard `DIALSTATUS` switch
  (`ANSWER`/`CANCEL`/`NOANSWER`/`BUSY`) — channel-technology-agnostic,
  works identically under PJSIP.
- **Voicemail**: `$asterisk->exec('voicemail', [mailbox, "u"])` — only
  reached if `DIALSTATUS` isn't `ANSWER`/`CANCEL`, `$ramal->hasVoiceMail()`
  is true, and the rule's `allow_voicemail` config allows it. Standard
  `VoiceMail()` application, technology-agnostic.
- **CDR**: same as outbound — Asterisk's own CDR engine, not SENMA.

## 4. Inbound call trace (Trunk → destination)

There is **no separate inbound-routing mechanism**. An inbound call
enters through whatever `context=` was written into the trunk's peer
stanza (`Snep_InterfaceConf::loadConfFromDb()`, always `default` for
everything SENMA's own UI generates — confirmed by reading that
generator: every branch writes `'context=' . $peer['context']`, and
`peer['context']` is a DB column with no evidence of any non-`default`
value used by the standard flow). So an inbound call from a trunk enters
`[default]` exactly like an internal call, reaches `AGI(snep/snep.php)`,
and `PBX_Dialplan::parse()` matches a rule by `isValidSrc()` recognizing
the **trunk** as the origin (`$request->origem` is the trunk's identity
for an inbound call, an extension number for an internal one — same
field, same matching engine). Representative destinations (extension,
queue, group, IVR) are just whichever `PBX_Rule_Action` the matched rule
executes — `DiscarRamal` (extension/ring group — `Snep_ExtensionsGroups_Manager`-
driven groups are a DB-side membership concept, not a distinct dialplan
mechanism), `Queue` (queue), or an IVR module action if the `ivr` module
is installed (not inspected in depth here — same generic
`PBX_Rule_Action` mechanism applies).
**How the inbound trunk is identified**: purely by which peer/trunk name
the inbound `Channel` string matches, resolved via `PBX_Interfaces::getChannelOwner()`
(used by `PBX_Asterisk_AGI_Request`'s constructor) — technology-agnostic
in principle, but see §7 for one narrow hardcoded `SIP/`-prefix special
case in that exact code path.

## 5. AGI inventory (16 first-party entrypoints)

| File | Dialplan caller | Purpose | DB deps | Reachable in target arch? | PHP 8.4 addressed? | Runtime tested? | Class |
|---|---|---|---|---|---|---|---|
| `snep.php` | `[default]`, `[transferencias]` | Main rule-matching/execution entry point | `PBX_Rules`, `core_config`, billing tables | Yes | Yes (TASK-0002/0004) | **No** — never exercised by a real call | **A** |
| `get_raw_channel.php` | `[khomp-fxs]` macro, `[transferencias]` | Reads the raw AGI channel name | none | Yes (transfer path) | Not specifically verified | No | **A** (transfer) |
| `resolv_extension.php` | `[khomp-fxs]` macro | `PBX_Interfaces::getChannelOwner()` → resolve caller's extension | `peers` | Khomp-context only in current dialplan | Not specifically verified | No | **C** (only reached via Khomp context) |
| `resolv_interface.php` | called from PHP (`DiscarRamal`-adjacent paths), not directly from `extensions.conf`'s main path | Extension → channel string (`getCanal()`) | `peers` | Yes | Not specifically verified | No | **A** |
| `resolv_pickup_group.php` | `[macro-dialpeer]` | Pickup-group resolution | `peers`/pickup-group tables | Only if `[macro-dialpeer]` reached (see §1) | Not specifically verified | No | **C** |
| `resolv_group.php` | not found in current `extensions.conf` | Group resolution (ring groups?) | unknown, not traced further | Unclear — no direct dialplan reference found | Not specifically verified | No | **D** (unreferenced in current static dialplan; may be invoked dynamically from PHP — not confirmed either way in this audit) |
| `peer_services.php` | `[macro-dialpeer]` | DND/follow-me service check for an extension | `peers` | Only if `[macro-dialpeer]` reached | Not specifically verified | No | **C** |
| `padlock.php` | not found in current `extensions.conf`; likely a feature-code entry (lock/unlock extension) invoked directly, not traced to a static dialplan line | `AUTHENTICATE` against extension password | `peers` | Feature-specific | Not specifically verified | No | **B** |
| `dnd.php` | not found in current `extensions.conf`; likely a feature-code entry | Toggle DND | `peers` | Feature-specific | Not specifically verified | No | **B** |
| `followme.php` | not found in current `extensions.conf`; likely a feature-code entry | Toggle follow-me | `peers` | Feature-specific | Not specifically verified | No | **B** |
| `agenda.php` | not found in current `extensions.conf` | Scheduled-callback/reminder phone number lookup | unknown, not traced further | Feature-specific | Not specifically verified | No | **B** |
| `monitor.php` | `[monitor]` context | Recording control | `core_config` | Feature-specific | Not specifically verified | No | **B** |
| `serviceslog.php` | not found in current `extensions.conf` | Logs a "service" (feature usage) event for an extension | `peers` | Feature-specific | Not specifically verified | No | **B** |
| `voicemail-notify.php` | called by Asterisk directly via `voicemail.conf`'s `externnotify=` (not from `extensions.conf`) | Emails a notification when voicemail arrives | `Snep_Sendmail`, DB via `Snep_Db` | Untestable without real voicemail + a working mail transport | Not specifically verified | No | **B**, deferred with voicemail generally |
| `agi_base.php`, `Bootstrap.php`, `Bootstrap-script.php` | not dialplan-invoked — shared bootstrap code `require_once`d by the other AGI scripts | AGI environment/bootstrap setup | — | Yes (infrastructure) | Yes (TASK-0004 batch 5 fixed `Asterisk_AGI`'s curly-brace parse fatal, which this bootstrap chain loads) | **Partially** — parse-level fix validated (`php -l`), zero real AGI protocol execution tested | **A** (infrastructure) |

**Overall**: every AGI script's PHP syntax is confirmed PHP 8.4-clean
(TASK-0002/0004's curly-brace and static-call sweeps covered `snep/agi/`
and `lib/Asterisk/AGI.php`), but **zero AGI script has ever executed
against a real Asterisk channel** — this whole subsystem is
parse-verified only, runtime-untested, which is precisely the gap the
proposed real-call milestone (§11) closes.

## 6. Asterisk application/function compatibility matrix

| App/Function | Used where | Asterisk 22 status | Classification |
|---|---|---|---|
| `Dial` | `DiscarTronco`, `DiscarRamal`, `[macro-dialpeer]` (via AGI EXEC and dialplan) | Works unchanged | Works unchanged |
| `Queue` | `Queue.php` action | Works unchanged (confirmed: `app_queue.c` realtime column names unchanged, TASK-0007) | Works unchanged |
| `VoiceMail` | `DiscarRamal.php` | Works unchanged (application itself unaffected; realtime *config* untested — TASK-0006/0007 deferred) | Works unchanged (app), config path deferred |
| `VoiceMailMain` | not found in current dialplan/actions | N/A — not currently used | N/A |
| `MeetMe` | **not used** — `ConferenceRoomsController.php` generates `ConfBridge(${EXTEN})` (confirmed TASK-0005) | `app_meetme` never built in this image | chan_sip-adjacent legacy app, already correctly not used |
| `ConfBridge` | `ConferenceRoomsController.php`-generated dialplan | Works unchanged, current mainstream app | Works unchanged |
| `Macro` | `extensions.conf`: `[macro-identifyExtension]` (Khomp-only path), `[macro-dialpeer]`/`[ramais-agentes]` (not reached by current SENMA-generated config, see §1) | **Removed entirely in Asterisk 21+** (deprecated since 1.6, confirmed via direct source check: `apps/app_macro.c` returns 404 on the 22.10.1 tree; confirmed absent from this project's built module list) | **Removed** — but confined to paths not exercised by the standard SENMA-generated flow (Khomp hardware / unreached agent context). Needs Macro→Gosub conversion only if either path is ever actually needed. |
| `Gosub`/`Return` | not currently used anywhere | Core PBX functionality, always available, the standard Macro replacement | Available, unused today |
| `ChanIsAvail` | not found anywhere in first-party code | N/A | N/A — not a dependency |
| `SIP_HEADER`/`SIPAddHeader` | `DiscarRamal.php` ×2 (diff-ring feature), `[ramais-agentes]` context | chan_sip-specific; **removed along with chan_sip** (Asterisk 21+) | chan_sip-specific, replacement required (`PJSIP_HEADER`) if diff-ring is kept |
| `SIPPEER()` | not found anywhere in first-party code | chan_sip-specific, unavailable | Not a current dependency |
| `CHANNEL()` | `extensions.conf` (`CHANNEL(language)=...`) | Works unchanged, technology-agnostic | Works unchanged |
| `GROUP`/`GROUP_COUNT` | not found anywhere in first-party code or dialplan | N/A | N/A — not a dependency |
| `DB()`/`DB_EXISTS()` | not found anywhere in first-party code or dialplan | N/A | N/A — not a dependency (SENMA uses its own MariaDB tables directly via ODBC/PHP, not Asterisk's internal astdb) |
| `MixMonitor` | `queues.conf`'s `monitor-type = MixMonitor` | Works unchanged, current mainstream app | Works unchanged |
| `Monitor` (legacy recording app) | not found in current dialplan (superseded by `MixMonitor` per `queues.conf`) | Deprecated in favor of MixMonitor, but not the blocker here | Not a current dependency |
| `System`/`TrySystem` | not found anywhere in first-party dialplan | N/A | N/A — not a dependency |
| `AGI` | pervasive (see §5) | Works unchanged | Works unchanged |
| `DeadAGI` | not found anywhere | N/A | N/A — not a dependency |
| `AUTHENTICATE` | `padlock.php` (AGI EXEC) | Works unchanged | Works unchanged |
| `UserEvent` | `extensions.conf`, `Queue.php` | Works unchanged | Works unchanged |

## 7. Complete chan_sip dependency inventory

| Location | Dependency | Subsystem |
|---|---|---|
| `snep/lib/PBX/Asterisk/Interface/SIP.php` | `$this->tech = 'SIP'`, `getCanal()` returns `"SIP/" . username` | Extensions (and trunks — same class reused, see §2) |
| `snep/lib/PBX/Asterisk/Interface/SIP/NoAuth.php` | Same pattern, IP-authenticated trunk variant | Trunks |
| `snep/lib/PBX/Usuarios.php:61-65` | `if ($tech == "SIP") { new PBX_Asterisk_Interface_SIP(...) }` — the central DB-tech-string dispatch table | Extensions/trunks provisioning↔runtime bridge |
| `snep/lib/Snep/InterfaceConf.php` | Generates **classic `chan_sip` flat-peer-stanza syntax** (`type=friend`, `host=`, `nat=`, `qualify=`, `insecure=`, `dtmfmode=`, `disallow=`/`allow=`, `call-limit=`, `directmedia=`, `register =>`, `exten => X,hint,SIP/X`) into `snep-sip.conf`/`snep-sip-trunks.conf`/`snep-sip-hints.conf`, then `AMI Command("sip reload")` | Provisioning (the single largest chan_sip dependency in the codebase) |
| `snep/lib/PBX/Rule/Action/DiscarRamal.php` + `snep/modules/default/actions/DiscarRamal.php` | `if ($tech == "SIP") $asterisk->exec('SIPAddHeader', ...)` (diff-ring) | Routing/runtime dialplan (narrow, isolated) |
| `snep/install/etc/asterisk/extensions.conf` `[ramais-agentes]` | `SIPAddHeader(Alert-Info: Bellcore-r2)` | Dialplan (unreached path, §1) |
| `snep/lib/PBX/Asterisk/AGI/Request.php:120-122` | `if ("Local/0000" === substr($channel,0,10)) { $channel = "SIP/".substr($channel,10,4); }` — narrow special-case channel remapping | Routing (channel-owner resolution) |
| `snep/modules/default/controllers/IpStatusController.php` | `canal LIKE 'SIP%'` — a DB query filter, not an Asterisk-side call | Status/monitoring |
| `snep/install/etc/asterisk/{sip.conf,sip.conf.sample}` | Vendored sample static config, matches `chan_sip` syntax | Provisioning (reference only, not currently deployed) |
| `snep/scripts/migra_peers.sh` (community script, per TASK-0001) | Generates classic `chan_sip` peer stanzas from DB | Provisioning tooling (third-party, not core app) |
| `snep/includes/AMI.php:194-216` (`get_sippeer()`) | AMI `Action: "Peer"` — queries `chan_sip`-style peer status | Status/monitoring (this whole class is separately confirmed low-usage — only `ip_status_queues.php` references it, per TASK-0001) |
| UI help text / labels (`extensions.conf`, `trunks.conf` help HTML, `.phtml` comments) | Cosmetic "SIP/IAX" text | UI copy only, not a functional dependency |

No `SIPPEER()`, `SIP_HEADER()` dialplan function, `sip show`/`sip peers`/`sip registry`/`sip set` CLI/AMI usage, `canreinvite`/`reinvite`, or `host=dynamic` peer generation logic was found anywhere in first-party code beyond what's listed above (the `host=` value the generator writes is a plain DB column passthrough, not hardcoded to `dynamic`).

## 8. PJSIP migration boundary

| Dependency (from §7) | Category |
|---|---|
| `PBX_Asterisk_Interface_SIP`/`SIP/NoAuth` classes | **A — provisioning translation.** Add sibling `PBX_Asterisk_Interface_PJSIP` class(es); `getCanal()` returns `"PJSIP/" . username`. |
| `PBX_Usuarios::get()`'s tech dispatch | **A — provisioning translation.** Add a `PJSIP` branch alongside `SIP`/`IAX2`/`MANUAL`/`VIRTUAL`/`KHOMP`. |
| `Snep_InterfaceConf::loadConfFromDb()` | **A + C — provisioning translation *and* an application-model change.** Not a syntax swap: chan_sip's one flat `[peer]` stanza must become PJSIP's linked `[endpoint]`/`[auth]`/`[aor]` (and `[identify]` for trunks) sections — a genuine object-model change in the generator, not a search-and-replace. This is the largest, riskiest single piece of the whole migration. |
| `DiscarRamal.php`'s `SIPAddHeader` diff-ring branch | **B — runtime translation.** Add an `else if ($tech == "PJSIP") { $asterisk->exec('PJSIP_HEADER', ...); }` branch, or accept the feature silently no-ops for PJSIP extensions (a product decision, not purely technical). |
| `extensions.conf`'s `[ramais-agentes]`/`SIPAddHeader` | **D — removal candidate**, pending confirmation nothing depends on it (§1: no evidence anything sets `context=ramais-agentes` today). |
| `PBX_Asterisk_AGI_Request`'s `Local/0000`→`SIP/` remap | **B/C — needs investigation**, not resolved by this audit: unclear what currently sets a `Local/0000XXXX`-style channel name or whether it's still relevant; flag for the implementer to trace before touching. |
| `IpStatusController`'s `canal LIKE 'SIP%'` filter | **A — provisioning translation** (trivial: add a matching `'PJSIP%'` filter once `canal` values can start with `PJSIP/`). |
| `snep/includes/AMI.php`'s `get_sippeer()` | **D — removal candidate** (already low-usage per TASK-0001; a PJSIP status query would use `PJSIPShowEndpoint`, a materially different AMI action, not a rename). |
| `[macro-identifyExtension]`/`Macro()` removal generally | **B — runtime translation**, only if the Khomp or `ramais-agentes` paths are ever actually needed — convert to `Gosub()`/`[sub-...]`. Not required for the milestone in §11. |
| Vendored `sip.conf`/`sip.conf.sample` | **D — removal candidate** once a `pjsip.conf` equivalent exists; harmless to leave as historical reference until then. |

## 9. Generated configuration architecture

```
Web UI (ExtensionsController / TrunksController)
  → Snep_Extensions_Manager / DB write (peers/trunks tables)
  → Snep_InterfaceConf::loadConfFromDb()           [text-concatenation generator, not a templating engine]
  → file_put_contents() to /etc/asterisk/snep/snep-{sip,iax2}{,-trunks,-hints}.conf
  → PBX_Asterisk_AMI Command("sip reload") / Command("dialplan reload") / Command("iax2 reload")
```
This is a plain-text generator, not Asterisk realtime — `extconfig.conf`
has never mapped `sippeers`/`sipusers` to a DB table in this codebase
(confirmed §1, and originally already commented out in the legacy
install per TASK-0001/0005's earlier findings).

**Recommendation for the first PJSIP milestone's architecture**: extend
`Snep_InterfaceConf` (or a new sibling class following the identical
pattern) to generate a **static `pjsip.conf`-style file**, reloaded via
AMI — **not** Asterisk realtime PJSIP (`ps_endpoints`/`ps_aors`/etc. DB
tables). Reasoning, based on the current architecture rather than
preference: (1) this is the exact pattern already proven working for
chan_sip/chan_iax2 today — same risk profile, same reload mechanism,
same file-ownership/permissions model already solved in TASK-0005; (2)
realtime PJSIP would require designing an entirely new schema
(`ps_endpoints` alone has 60+ possible columns) *and* a new object model
*and* a new reload/cache-invalidation story, all at once — compounding
the already-significant object-model risk identified in §8's `Snep_InterfaceConf`
entry; (3) TASK-0007 already demonstrated the realtime pattern works
well for `queues`/`queue_members`, which are far simpler, single-table,
already-existing-schema cases — PJSIP's realtime tables are a
materially bigger design exercise, better attempted as a *later*
optimization once the static-file version is proven working end-to-end.

## 10. Filesystem coupling matrix (current evidence, not copied from TASK-0001)

| Path (legacy) | Docker path today | Producer | Consumer | Currently shared? |
|---|---|---|---|---|
| `path_voz` = `/var/www/html/snep/arquivos/` (recordings) | Exists as a plain directory inside the bind-mounted `snep/` source tree; **confirmed live**: `ls` shows a real directory, but it is a plain subfolder of the app's own bind mount, not a volume Asterisk has any access to | Asterisk (`MixMonitor`/`Monitor`, if/when configured) would need to write here; PHP reads/serves recordings from here | PHP (`SoundFilesController`, reports) | **No** — Asterisk container has no mount pointing at this path at all. Confirmed via `compose.yaml`: the `asterisk` service's volumes are `asterisk-etc`, `mag-asterisk-var`, `mag-asterisk-spool`, `mag-asterisk-log` only — none of them map to anything the app's `arquivos/` directory could be. **Real, current, unresolved gap.** |
| `path.asterisk.sounds` = `/var/lib/asterisk/sounds` | `mag-asterisk-var` volume, mounted **only** in the `asterisk` service | Asterisk ships/writes sound prompts here | PHP (`SoundFilesController`/`MusicOnHoldController`, sound-file management pages) expects to read/write here directly | **No** — confirmed live: the `app` container's `compose.yaml` volumes are only `./snep:/var/www/html/snep` and `asterisk-etc:/etc/asterisk:ro`; `/var/www/html/snep/sounds` doesn't even exist in the app container (`ls` → "No such file or directory"). **Real, current, unresolved gap** — this predates and is independent of the PJSIP migration, but blocks any sound-file-management feature from working correctly regardless. |
| `path.asterisk.moh` = `/var/lib/asterisk/moh` | Same volume as above, same gap | Asterisk MOH files | `QueuesController`/`MusicOnHoldController` | **No**, same reason |
| `path.asterisk.conf` = `/etc/asterisk` | `asterisk-etc` named volume | Asterisk (owns, read-write) | PHP (reads `snep-musiconhold.conf` etc., read-only) | **Yes** — the one path TASK-0005 already solved correctly |
| AGI scripts (`snep/agi/*.php`) | Not currently mounted into the `asterisk` container's `astagidir` (`/var/lib/asterisk/agi-bin`) at all | — | Asterisk would need to read these to actually invoke them | **No** — confirmed: `asterisk`'s volumes don't include the app's `snep/` tree anywhere. AGI scripts cannot currently be invoked by Asterisk even if a dialplan reached an `AGI(...)` line, since Asterisk has no filesystem visibility into `/var/www/html/snep/agi/` at all. **This is a P0 blocker for the real-call milestone**, distinct from and in addition to the recordings/sounds gaps above. |
| Generated configs (`snep-sip.conf` etc.) | Would land in `asterisk-etc` (shared, writable by `app`... but `app`'s mount is `:ro`!) | PHP writes (`Snep_InterfaceConf`) | Asterisk reads | **Currently mismatched**: `app`'s `/etc/asterisk` mount is read-only (`asterisk-etc:ro` in `compose.yaml`) — `Snep_InterfaceConf::loadConfFromDb()` would fail its own `is_writable()` check today. **A real blocker for provisioning**, not just AGI. |
| Logs | `mag-asterisk-log` volume, `asterisk`-only | Asterisk | Nothing in PHP reads Asterisk's own log directly (uses AMI/CLI for status instead) | Not needed cross-container |

TASK-0001's symlink-farm finding (app/Asterisk sharing a single host
filesystem via symlinks) is **confirmed still directionally correct** —
the *need* for shared recordings/sounds/AGI visibility is real and
current — but the *mechanism* obviously can't be symlinks across
containers; each of the four real gaps above needs an explicit named
volume or bind mount, mirroring the `asterisk-etc` pattern TASK-0005
already established, with the read/write direction corrected for
`Snep_InterfaceConf` and AGI's needs specifically.

## Blockers

**P0 — prevents any real call:**
- AGI scripts are not visible to the Asterisk container's filesystem at
  all (no shared volume for `snep/agi/` → `astagidir`). Without this,
  `AGI(snep/snep.php)` cannot execute, and the entire `PBX_Dialplan`
  mechanism (which is how *every* call is routed, per §1) is
  unreachable.
- No PJSIP endpoint provisioning exists at all yet (`Snep_InterfaceConf`
  only generates chan_sip/IAX2 syntax; no `PBX_Asterisk_Interface_PJSIP`
  class exists) — nothing to register a test extension against.
- `extensions.conf` itself is not currently deployed into the running
  Asterisk container (TASK-0005's deliberate minimal scope — `pbx_config`
  currently declines for lack of a config file).
- `/etc/asterisk`'s `app`-side mount is read-only, but `Snep_InterfaceConf`
  needs to write into it — a real, current mismatch, not just a missing
  feature.

**P1 — prevents production-grade extension calling:**
- `Snep_InterfaceConf`'s object-model gap (chan_sip flat stanza → PJSIP
  linked endpoint/auth/aor sections) — §8/§9.
- Recordings (`arquivos/`) and sounds/MOH filesystem sharing — real
  features (call recording, MOH, sound management) silently don't work
  without this, independent of PJSIP itself.
- `DiscarRamal`'s diff-ring `SIPAddHeader` → needs a PJSIP branch or a
  deliberate decision to drop the feature for PJSIP extensions.

**P2 — required for trunks/routing/features:**
- PJSIP trunk support in `Snep_InterfaceConf` (separate from extension
  support — trunks have their own generator branches, §7).
- `Macro()`/`[macro-dialpeer]`/`[ramais-agentes]` → `Gosub()` conversion,
  only if that context turns out to be needed (not evidenced as reachable
  today).
- `PBX_Asterisk_AGI_Request`'s `Local/0000`→`SIP/` special case — needs
  tracing before it can be classified further.
- `IpStatusController`'s `SIP%` filter needs a `PJSIP%` counterpart.
- `snep/includes/AMI.php`'s `get_sippeer()` — low-usage, needs a
  `PJSIPShowEndpoint`-based replacement if kept.

**P3 — legacy debt that can wait:**
- Vendored `sip.conf`/`sip.conf.sample` cleanup.
- `snep/scripts/migra_peers.sh` (third-party, chan_sip-specific tooling).
- Khomp-context (`[khomp-fxs]`) Macro→Gosub conversion — irrelevant
  without Khomp hardware.

## 11. Proposed minimum real-call milestone

```
PJSIP extension 1000  →  Asterisk 22  →  PJSIP extension 1001
        (real two-way internal call, CDR written through cdr_adaptive_odbc)
```
To achieve this, the audit indicates the following must be implemented
(not implemented by this task):
1. **Filesystem**: share `snep/agi/` (or the whole `snep/` tree) into the
   Asterisk container's `astagidir`; make `/etc/asterisk`'s `app`-side
   mount read-write (or split into a separate read-write sub-mount for
   just the generated files) so `Snep_InterfaceConf` can write.
2. **Deploy `extensions.conf`** into the running Asterisk container (it
   already exists, vendored, unchanged — TASK-0005 simply never deployed
   it, by deliberate scope).
3. **A minimal `PBX_Asterisk_Interface_PJSIP` class** (`getCanal()` →
   `"PJSIP/" . username`) and the corresponding branch in
   `PBX_Usuarios::get()`.
4. **A minimal PJSIP section generator** — does not need `Snep_InterfaceConf`'s
   full trunk/hints complexity for this milestone; two static
   endpoint/auth/aor stanzas (extensions 1000/1001) are enough to prove
   the architecture, with the full generator rewrite deferred to P1/P2.
5. **`res_pjsip`/`chan_pjsip` enabled** in `modules.conf` (currently
   `noload`ed, TASK-0005) — their build dependencies (`pjproject`) are
   not currently installed in `docker/asterisk.Dockerfile` either
   (`--without-pjproject-bundled` was used deliberately in TASK-0005) —
   this needs a real Dockerfile change to add pjproject.
6. Two extensions in the `peers` table with `canal='PJSIP/1000'`/`'PJSIP/1001'`,
   created either directly in the DB or (better, more representative)
   through the real `ExtensionsController` UI once it supports a PJSIP
   technology option.

**Explicitly not included**, per instruction and because the audit found
no evidence they're required for this specific milestone: trunks,
inbound routes, queues, voicemail, IVR.

## 12. CDR validation for the milestone

The milestone must prove, in order: (1) a real `PJSIP/1000` and
`PJSIP/1001` channel exist (`pjsip show endpoints` / `pjsip show
contacts` showing both registered); (2) a real call completes between
them (`channel originate` or a real UA placing the call — the audit
found `chan_local` is not compiled, so this milestone's own scope must
also add it, or use two real registered PJSIP UAs, which is more
representative anyway — see §13); (3) `cdr show active`/a post-call
`SELECT` against the `cdr` table shows a genuine new row with real
`src`/`dst`/`duration`/`billsec`/`uniqueid` values, written by
`cdr_adaptive_odbc` (already registered and proven connecting correctly,
TASK-0007) — not inserted by any PHP/SQL script; (4) `CallsReportController`/
`RankingReportController` (the real, existing SENMA report pages) can
display that exact row through the normal web UI — closing the loop back
to the application, not just the database.

## 13. Testing strategy

Prefer automation. Two options investigated (not installed):
- **SIPp** — a scriptable SIP traffic generator (XML call-flow
  scenarios: REGISTER/INVITE/183/200/ACK/BYE), the standard tool for
  exactly this kind of repeatable, CI-friendly signaling test. Doesn't
  produce real audio by default, but proves registration, call setup,
  answer, hangup, and (combined with a DB check) CDR — matches most of
  item 13's required proof points with the least moving parts. Available
  as a Debian package; would run as its own throwaway container on the
  same `mag` network as `asterisk`.
- **A lightweight scriptable softphone** (e.g. `baresip`, or `pjsua` from
  pjproject, which Asterisk's own PJSIP stack is already built on) — a
  heavier but more representative option: two containers, each
  registering as `PJSIP/1000`/`PJSIP/1001`, capable of a real two-way RTP
  audio path, scriptable via CLI/config for automated call placement and
  hangup. Better fidelity for the "media if practical" requirement, more
  setup/scripting complexity than SIPp.

**Recommendation**: SIPp for the repeatable, `make smoke`-adjacent
automated regression test (registration + call setup + answer + hangup +
CDR-presence check via a DB query, all scriptable, fast, CI-friendly); a
real UA pair (baresip/pjsua) as an occasional, more manual "does audio
actually flow" sanity check, not part of the automated suite. Neither
was installed or configured by this audit.

The automated test must also assert `make smoke` stays at 16 PASS / 0
FAIL / 0 EXPECTED_LIMITATION — i.e., the telephony test is additive, not
a replacement for the existing HTTP regression suite.

## Recommended TASK-0009 scope

Implement exactly the minimum real-call milestone from §11-12: add
`pjproject`/`res_pjsip`/`chan_pjsip` to the Asterisk build, fix the two
filesystem-sharing gaps that are genuine P0 blockers (AGI visibility,
writable `/etc/asterisk` for the app), deploy `extensions.conf`, add the
minimal `PBX_Asterisk_Interface_PJSIP` class + `PBX_Usuarios::get()`
branch, generate two static PJSIP endpoint stanzas for extensions
1000/1001, and validate with a real registered call and a real CDR row
read back through SENMA's own reports — nothing else. Explicitly out of
that task's scope, per this audit's own findings: trunks, inbound
routing, queues-over-PJSIP, voicemail, IVR, `Snep_InterfaceConf`'s full
object-model rewrite (a minimal two-stanza generator is enough for the
milestone; the full generator rewrite is P1/P2 debt, not part of proving
a real call), Macro→Gosub conversion, and the recordings/sounds
filesystem gaps (real, but not P0 for a basic call — MixMonitor isn't
exercised by this milestone).

Stopping here for approval. No runtime code was edited.

## Correction (TASK-0028, 2026-09-03 / TASK-0028C, 2026-09-04)

§1's table row for `custom/{preagi,posagi,eof}.conf` described all three
as "intentionally-empty extension points." That is factually wrong for
`preagi.conf` specifically: direct inspection (TASK-0028's own audit, then
confirmed again live in TASK-0028C) shows it has always shipped a real,
concrete, dialable extension (`1234`, originally `Dial(SIP/1003,60,twg)`)
— forgotten SNEP-upstream example/test content, not a placeholder.
`posagi.conf`/`eof.conf` are correctly comment-only, as originally stated.
This also means the reachability claim for `[ramais-agentes]`/
`macro-dialpeer` in the same table stands independently and is unaffected.
See `docs/tasks/0028-pjsip-only-architecture-audit.md` §14.5 for the full
provenance investigation and
`docs/tasks/0028c-pjsip-legacy-runtime-closure.md` for the runtime fix
(a separate context-bleed bug had, until TASK-0028C, coincidentally kept
this extension unreachable anyway).
