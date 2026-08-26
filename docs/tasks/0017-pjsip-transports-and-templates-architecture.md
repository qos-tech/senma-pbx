# TASK-0017 — PJSIP transports and templates architecture

## Status

**Investigation/design only. No runtime code, database schema, Docker
configuration, or Asterisk configuration was changed.** All findings
below are sourced from direct reading of the current tree
(`Snep_PjsipConf`, `Snep_PjsipTrunkConf`, `docker/asterisk-config/pjsip.conf`,
`schema.sql`'s `peers`/`trunks` tables, `TrunksController`/
`ExtensionsController`) and the full documented history of TASK-0010,
TASK-0011, TASK-0014, TASK-0015, TASK-0016. `git status` is clean;
`make smoke` (16/0/0), `make call-smoke` (18/18), `make trunk-smoke`
(23/23) are unaffected — nothing here was implemented or exercised
against the running stack.

---

## 1. Current-state audit

### 1.1 The two generators, traced precisely

| | `Snep_PjsipConf` (TASK-0011) | `Snep_PjsipTrunkConf` (TASK-0015/0016) |
|---|---|---|
| Reads | `peers WHERE peer_type='R' AND canal LIKE 'PJSIP/%'` | `peers WHERE peer_type='T' AND canal LIKE 'PJSIP/%'`, joined to `trunks` by `name` |
| Emits per row | `[name]` endpoint, `[name-auth]` auth, `[name]` aor | `[trunk-<id>]` endpoint, `[trunk-<id>-auth]` auth, `[trunk-<id>]` aor, `[trunk-<id>-registration]` (if `reverse_auth`), `[trunk-<id>-identify]` (always) |
| Object identity | `peers.name` verbatim (dial-plan-relevant) | `trunk-<trunks.id>` (namespaced, never dialed by name) |
| Writes | `snep/senma-pjsip.conf` | `snep/senma-pjsip-trunks.conf` |
| Reload | `module reload res_pjsip.so`, checks `"reloaded successfully"` | Same, independently implemented (identical logic, second copy) |
| Called from | `ExtensionsController` (4 call sites) | `TrunksController` (4 call sites) |

Both are **full-stateless-rewrite** generators (the entire file is
rebuilt from the current DB state on every call) — this property is
explicitly worth preserving in whatever this task designs next, for the
exact reasons TASK-0010 §3/§6 already established (delete/rename safety
comes for free, no incremental-diff logic needed anywhere).

### 1.2 `pjsip.conf` today

```
/etc/asterisk/pjsip.conf                 <- static, project-owned
    [transport-udp]                       <- the ONLY transport that exists, hardcoded
    type=transport
    protocol=udp
    bind=0.0.0.0:5060

    #include snep/senma-pjsip.conf         <- Snep_PjsipConf
    #include snep/senma-pjsip-trunks.conf  <- Snep_PjsipTrunkConf
```

**There is no transport object model at all today.** Every endpoint
implicitly uses whatever Asterisk's own transport-matching heuristic
selects (in practice, the single UDP transport, since it's the only one
that exists) — no `transport=` line is ever emitted by either generator.
Nothing in `peers`/`trunks` references a transport in any way.

### 1.3 Hardcoded values (never configurable today)

| Value | Where | Generator |
|---|---|---|
| `disallow=all` | endpoint | both |
| `auth_type=userpass` | auth | both |
| `max_contacts=1`, `remove_existing=yes` | aor | extensions only |
| `qualify_timeout` | — | **not emitted at all, anywhere** — only `qualify_frequency` exists |
| `retry_interval=60` | registration | trunks only |
| DTMF map (`rfc2833`→`rfc4733`, `inband`, `info`) | endpoint | both (two identical copies) |
| `;`→`,` codec-list transform | endpoint | both (two identical copies — already flagged as a future shared-helper candidate in TASK-0014 §9, never acted on) |

### 1.4 Global vs. extension-specific vs. trunk-specific (current reality)

- **Global** (same for every row of a type, by construction of the code, not by DB value): the DTMF map, the codec transform, `disallow=all`.
- **Extension-specific** (`peers` columns actually read for PJSIP: `name`, `context`, `callerid`, `language`, `allow`, `dtmfmode`, `nat`, `qualify`, `directmedia`, `secret`, `disabled`): all per-row, no sharing mechanism exists.
- **Trunk-specific** (`peers`+`trunks` columns actually read: `host`, `port`, `defaultuser`, `secret`, `fromuser`, `fromdomain`, `callerid`, `context`, `allow`, `dtmfmode`, `nat`, `trunks.id`, `trunks.reverse_auth`): same — all per-row.

### 1.5 Duplicated logic

The NAT-token-splitting logic and the codec `;`→`,` transform are
**byte-for-byte duplicated** between `Snep_PjsipConf::renderExtension()`
and `Snep_PjsipTrunkConf::renderTrunk()`. Neither the reload method nor
the header-comment generation is shared either. This is exactly the kind
of duplication a shared low-level parameter/rendering layer (§5, §9)
would eliminate as a side effect — not the primary goal of this task,
but a real, concrete benefit worth naming.

### 1.6 Currently impossible to express (the actual gap list)

- **Any transport other than the single static UDP one** — no TCP, no TLS, no WSS, no per-object transport choice.
- **`external_media_address`/`external_signaling_address`/`local_net`/`symmetric_transport`** — not modeled anywhere; a NAT'd Asterisk (the overwhelmingly common real-world case) cannot currently advertise a correct public address.
- **`qualify_timeout`** — only the frequency exists; the OPTIONS-ping timeout is Asterisk's compiled default always.
- **Custom `max_contacts`** — hardcoded to 1 for extensions; not a concept at all for trunks (which use a static AOR contact, no registration acceptance).
- **`call_group`/`pickup_group` as native PJSIP endpoint options** — `pickupgroup` exists only as a *dialplan runtime* variable (`DiscarRamal`'s `__PICKUPMARK`), never emitted into the generated endpoint config at all. `callgroup` is dead entirely (TASK-0010 §2).
- **`rtp_timeout`/`rtp_timeout_hold`** — **a genuinely surprising finding**: `peers.rtptimeout`/`peers.rtpholdtimeout` **already exist as real DB columns** (`schema.sql`, chan_sip-era) but **neither PJSIP generator reads them at all**. Not a design gap requiring a new column — an implementation gap where an already-persisted value is silently ignored for PJSIP rows.
- **`message_context`, `inbound_progress`** — no concept exists at all.
- **Registration tuning** (`expiration`, `fatal_retry_interval`, `forbidden_retry_interval`, `max_retries`) — `retry_interval` is the only knob, and it's hardcoded to `60`, not even DB-backed.
- **`contact_user`** on the registration object — not supported; the registration's `client_uri=` always uses the auth username directly as the URI user part.
- **A real, live bug, not a gap**: `trunks.domain` — a real DB column, exposed in the trunk UI's "Domain" field, stored on every trunk — **is never read by `Snep_PjsipTrunkConf` at all**. TASK-0014 §3's own design doc explicitly proposed mapping it to `from_domain=`, but TASK-0015's actual implementation only reads `peers.fromdomain` (a *different*, also-real column). For a PJSIP trunk, filling in "Domain" in the UI today has **zero effect** — it's live, silently dead data. This is the single clearest piece of evidence for this task's own "important real-world observation": the current architecture has already, accidentally, conflated/dropped independent identity concepts (signaling host, identify source, and now domain) precisely because there is no structured place for each of them to live independently.
- **Identify match independent of the signaling host**: `Snep_PjsipTrunkConf`'s `identify.match=` is **hardcoded to the exact same `$host` variable** that also drives the AOR's `contact=` (`snep/lib/Snep/PjsipTrunkConf.php`, both derived from `$peer['host']`). There is no way today to accept inbound calls from a different IP/CIDR than the one SENMA dials outbound to — a real, common carrier topology (SBC pools, geographically redundant signaling, a provider whose inbound gateway differs from its registrar) is **structurally unrepresentable** in the current schema, not merely unconfigured.

These last two findings are not hypothetical: they are exactly the
"important real-world observation" the task states as a product
requirement, already violated by the current implementation.

---

## 2. Transport entity — model

### Persistent fields (implement now)

| Field | Type | Notes |
|---|---|---|
| `name` | string, unique | user-facing identity, also the generated sorcery object name |
| `protocol` | enum: `udp`,`tcp`,`tls`,`wss`,`ws` | |
| `bind_address` | string | IP or `0.0.0.0` |
| `bind_port` | int | |
| `domain` | string, nullable | real PJSIP transport option (outbound identification, most relevant for TLS/WSS, valid generically) |
| `external_signaling_address` | string, nullable | |
| `external_signaling_port` | int, nullable | |
| `external_media_address` | string, nullable | |
| `local_net` | **multi-value** (§18 — child table, not a delimited string) | Asterisk supports repeated `local_net=` lines; modeled the same way, not string-packed |
| `symmetric_transport` | boolean | |
| `allow_reload` | boolean, default true | |
| `is_default` | boolean | exactly one transport must carry this at all times (§3) |
| `enabled` | boolean, default true | lets a transport row exist without being emitted/active yet — see §3's WSS handling |

### Future-only fields (persisted now, inert until TLS/WSS work begins)

`cert_file`, `priv_key_file`, `ca_list_file`, `ca_list_path`,
`verify_client`, `verify_server`, `require_client_cert`, `method`,
`cipher` (multi-value, same child-table pattern as `local_net`). Storing
these columns now costs nothing and means the eventual TLS/WSS task adds
*behavior* (making the generator actually emit them, and building the
cert-upload UI), not a schema migration. This satisfies the task's
explicit instruction ("do not implement TLS/WSS yet, but ensure the
model does not block it") precisely: the model is complete now; only the
generator's conditional emission and the UI's cert-handling are deferred.

---

## 3. Seed transport strategy

**Seed exactly three rows**, matching the task's own minimum:

| name | protocol | bind | is_default | enabled |
|---|---|---|---|---|
| `udp` | udp | `0.0.0.0:5060` | **yes** | yes |
| `tcp` | tcp | `0.0.0.0:5060` | no | yes |
| `wss` | wss | `0.0.0.0:8089` | no | **no** |

- `udp`'s bind is byte-identical to today's static `[transport-udp]` — this row *is* the migration target for every existing object (§17).
- `wss` is seeded as a row (so templates/UI can reference it by name and the eventual TLS task doesn't need a schema/seed change) but seeded **disabled** — a WSS transport with no certificate configured cannot actually bind; emitting it into `pjsip.conf` would either fail to load or silently do nothing useful. The generator (§4) must skip `enabled=false` transports entirely when writing the file, not emit a broken stanza. Enabling it becomes possible the moment the deferred TLS work adds cert fields — no schema change needed then either.
- **Editable**: yes, including bind address/port of the seeded ones — a real deployment may need to move off 5060, and there is no product reason to freeze the seeds specifically.
- **Deletable**: only when usage count (§12) is zero. The current `is_default` transport additionally cannot be deleted until another transport is promoted to default first (never a "zero defaults" state).
- **System/default marking**: exactly one `is_default=true` transport at all times, enforced at the application layer (promoting a new default demotes the old one in the same transaction) and defended by DB constraint where practical (a partial unique index on `is_default=true` if the target RDBMS supports it; otherwise an application-level check, matching this project's existing precedent of PHP-layer invariants over exotic constraints).
- **Migration for existing extensions/trunks**: **nothing to migrate**. `peers.transport_id`/`trunks.transport_id` (§18) are nullable, and `NULL` means "use whichever transport is currently `is_default`." Since the seeded `udp` default is byte-identical to the static transport every existing object already implicitly uses, every pre-existing row's real, generated behavior is unchanged with zero data backfill. This is the cleanest possible migration outcome and is reused as the template for the harder templates/overrides migration in §17.

---

## 4. Transport ownership and generation

**New class, same established pattern: `Snep_PjsipTransportConf`**, a
third sibling of `Snep_PjsipConf`/`Snep_PjsipTrunkConf` — not folded into
either. Own table (`pjsip_transports` + its two child tables, §18), own
generated file (`senma-pjsip-transports.conf`), own UI CRUD controller,
own reload call (the same `module reload res_pjsip.so`, since there is
still only one whole-tree PJSIP reload command in this Asterisk build —
already established fact, TASK-0010 §10/TASK-0014 §12).

```
pjsip.conf
  #include snep/senma-pjsip-transports.conf   <- NEW: Snep_PjsipTransportConf
  #include snep/senma-pjsip.conf              <- Snep_PjsipConf (extensions)
  #include snep/senma-pjsip-trunks.conf       <- Snep_PjsipTrunkConf (trunks)
```

This ordering is **not chosen for aesthetics** (the task's own explicit
instruction): Asterisk's config-file loader merges every `#include`d file
into one in-memory config before sorcery resolves any object references,
so *include order does not affect whether a `transport=<name>` reference
resolves correctly* — this was verified against how PJSIP config loading
actually works, not assumed. The ordering is chosen instead for
**operational/debugging clarity** (reading the merged file top-to-bottom
mirrors dependency order: transports, then the objects that reference
them) and to match this project's own established convention of listing
the most foundational/static concern first (compare `pjsip.conf`'s
existing `[transport-udp]`-then-includes shape).

**Cross-generator consistency requirement**: because `peers.transport_id`/
`trunks.transport_id` reference a transport **by ID**, and the generated
endpoint/registration text embeds the transport's **current name**
(`transport=<name>`), a transport **rename** requires the transport
generator to run — but does **not** require touching any `peers`/`trunks`
row (the FK never changes). It **does** require `Snep_PjsipConf`/
`Snep_PjsipTrunkConf` to regenerate too, since their output text
embeds the pre-rename name. **Any transport create/edit/delete must
therefore trigger all three generators**, not just its own — the same
"call every generator additively, let each filter itself" pattern
already used today when `TrunksController`/`ExtensionsController` each
call both existing generators unconditionally.

---

## 5. Template model

**Recommendation: Option C — separate template *entities*, sharing a
common low-level parameter *model* (validation/catalog logic), not a
shared database table.**

- **Not Option A** (one table + type discriminator): an admin-facing
  "Templates" list mixing extension and trunk templates together would
  actively confuse the two distinct UI surfaces the task itself asks for
  (`Extension Templates` and `Trunk Templates` as separate nav items,
  §19) and would force every query/foreign key to filter by type,
  buying no real schema simplicity in exchange for worse product clarity
  — exactly what the task's instruction to "prefer clear product
  semantics over schema minimalism" argues against.
- **Not Option B** (fully separate models, independently designed): the
  actual *parameter storage shape* (object type + parameter name + value,
  §8/§9) is identical for both template kinds and for both override
  kinds. Independently designing four different key-value shapes buys
  nothing and would require four separate validation/catalog
  implementations to stay in sync by hand.
- **Option C, concretely**: two real header tables
  (`pjsip_extension_templates`, `pjsip_trunk_templates`) with genuine
  identity/lifecycle columns (name, description, usage), each with its
  own real-FK parameter child table (`pjsip_extension_template_params`,
  `pjsip_trunk_template_params`) that share an **identical column shape**
  (`object_type`, `param_name`, `param_value`) and are validated through
  **one shared PHP-side parameter catalog** (§9) — the sharing happens in
  application logic, not by forcing two conceptually different template
  kinds through one polymorphic table. This also directly answers the
  override-model question the same way (§9), for the same reason.

---

## 6. Extension templates — parameter classification

**Never inherited from a template, under any circumstances** (per the
task's explicit instruction): extension number (`peers.name`), `secret`,
`callerid`, mailbox/voicemail identity. These remain exactly what they
are today — real, always-per-object columns, never touched by the
template mechanism.

**Template-level (the "general NAT/media profile," Example A)**:

| AOR | Endpoint |
|---|---|
| `max_contacts` | `allow`/`disallow` (codecs — see migration note, §17) |
| `qualify_frequency` | `direct_media` |
| `qualify_timeout` (new) | `dtmf_mode` |
| `remove_existing` | `force_rport` |
| | `rewrite_contact` |
| | `rtp_symmetric` |
| | `language` |
| | `message_context` (new, inert until MESSAGE/SMS work exists) |
| | transport (a *suggested default*, §12) |

**Per-extension structured fields, available for override on top of
whatever the template supplies (Example B)**: `call_group`, `pickup_group`.
These are **not** identity fields (they don't identify *which* extension
this is) and **not** excluded from templating in principle — a
"Reception intercom" template could reasonably set a default
`pickup_group`. They are ordinary catalog parameters, classified here as
"commonly overridden per-object" rather than "always identical within a
template," which is exactly the override mechanism's job (§9) — not a
new, third kind of field.

---

## 7. Trunk templates — parameter classification

**Template-level (the provider-*class* policy, not the provider's
identity)**:

| Endpoint | Registration | Auth |
|---|---|---|
| `allow`/`disallow` | `enabled` (yes/no — see below) | `auth_type` |
| `dtmf_mode` | `expiration` | |
| `direct_media` | `retry_interval` | |
| `force_rport` | `fatal_retry_interval` | |
| `rewrite_contact` | `forbidden_retry_interval` | |
| `rtp_symmetric` | `max_retries` | |
| `rtp_timeout` | | |
| `rtp_timeout_hold` | | |
| `inbound_progress` | | |

`registration.enabled` (yes/no) is deliberately modeled as an ordinary
template parameter, not a special schema column — it is exactly what
distinguishes the two acceptance-example templates in §13 ("REGISTER/
auth" vs. "IP-auth/no-register"), so it belongs in the same uniform
catalog as everything else, not hand-coded as a boolean on the template
header table.

**Explicitly per-trunk, never templated** (the task asks this be decided
plainly — here is the decision, per field):

| Field | Stays per-trunk because |
|---|---|
| `host` | the entire reason a trunk exists is to reach one specific remote party |
| `username` | provider-assigned account identity |
| `password`/`secret` | provider-assigned credential |
| `from_user` | usually a specific DID/account identifier, provider-specific |
| `from_domain` | the "important observation" itself: a real carrier's From-domain is an independent fact about *that* provider, not a class-wide default — confirmed necessary by §1.6's own dead-`trunks.domain` finding |
| `contact_user` | account-specific registration identity (a new field, §7 introduces it formally — currently unsupported at all, §1.6) |
| `identify_match` | the literal IP/CIDR of *this* provider's signaling source — never shared, ever |

---

## 8. Parameter ownership matrix

`T` = transport, `ET`/`TT` = extension/trunk template, `E`/`Tr` = extension/trunk object column, `O` = override-eligible.

| Parameter | Object | Owner | Override? |
|---|---|---|---|
| `protocol`, `bind_address`, `bind_port`, `domain`, `external_signaling_address`, `external_signaling_port`, `external_media_address`, `local_net`, `symmetric_transport`, `allow_reload`, TLS/WSS future fields | transport | **T** | n/a (transport is selected, not merged) |
| `context` | endpoint | E / Tr (always `default` today, §1; stays object-level — see §17) | — |
| `callerid` | endpoint | E / Tr | — |
| `language` | endpoint | **ET** | O |
| `allow`/`disallow` | endpoint | **ET/TT**, with a per-object stored value used as a migration-safety override when it differs (§17) | O |
| `direct_media` | endpoint | **ET/TT** | O |
| `dtmf_mode` | endpoint | **ET/TT** | O |
| `force_rport` | endpoint | **ET/TT** | O |
| `rewrite_contact` | endpoint | **ET/TT** | O |
| `rtp_symmetric` | endpoint | **ET/TT** | O |
| `rtp_timeout`/`rtp_timeout_hold` | endpoint | **TT** | O |
| `inbound_progress` | endpoint | **TT** | O |
| `message_context` | endpoint | **ET** | O |
| `call_group`/`pickup_group` | endpoint | **O** (no template default by default; settable at template or object level, §6) | O |
| `transport=` (selection) | endpoint/registration | template suggests, object overrides, system default is the final fallback (§12) | O |
| `max_contacts` | aor | **ET** | O |
| `qualify_frequency`/`qualify_timeout` | aor | **ET/TT** | O |
| `remove_existing` | aor | **ET** | O |
| `auth_type` | auth | **TT** (extensions: always `userpass`, hardcoded, no template control needed — no evidence any other mode is ever used, TASK-0010 §7) | O (trunk only) |
| `username`, `password` | auth | E / Tr (identity, §6/§7) | — |
| `host`, `port` (aor `contact=`) | aor | **Tr** (identity) | — |
| `from_user`, `from_domain` | endpoint | **Tr** (identity) | — |
| `contact_user` | registration | **Tr** (identity, new field) | — |
| `registration.enabled` | registration | **TT** | O |
| `expiration`, `retry_interval`, `fatal_retry_interval`, `forbidden_retry_interval`, `max_retries` | registration | **TT** | O |
| `client_uri`/`server_uri` | registration | computed from `Tr` identity fields, never templated/overridden directly | — |
| `identify.match` | identify | **Tr** (identity, §1.6/§7) | — |

Every parameter above has exactly one canonical owner plus, where
marked, one explicit override path — no ambiguous ownership remains.

---

## 9. Override architecture

**Explicitly not an opaque multiline text field** (per the task's own
instruction) — a structured row per (object, object-type, parameter):

```
pjsip_extension_overrides(peer_id, object_type, param_name, param_value)
pjsip_trunk_overrides(trunk_id, object_type, param_name, param_value)
```
`object_type` ∈ `{endpoint, aor, auth, registration, identify}` (identify/
registration only meaningful for trunks — enforced by the catalog, §below,
not by a separate schema per type).

**Example rows, matching the task's own worked example exactly**:

| owner | object_type | param_name | param_value |
|---|---|---|---|
| trunk 12 | endpoint | rtp_symmetric | yes |
| trunk 12 | registration | max_retries | 9999 |
| trunk 12 | identify | match | 200.155.48.248/29 |

**Validation — a code-owned parameter catalog, not a DB-editable
whitelist**: a single PHP array (per object_type) declaring every
supported `param_name`, its value type (`boolean`, `enum[...]`,
`integer`, `decimal`, `cidr`, `string`), and which object kinds
(extension/trunk) it applies to. This catalog is:
- the single source of truth for override/template validation (an
  override row can only name a `param_name` present in the catalog for
  its `object_type` — this **is** the "no arbitrary raw PJSIP directive"
  protection the task's security section asks for, not a separate
  mechanism);
- the source for the UI's "Advanced/Overrides" available-parameter list
  (§19);
- code-owned (versioned with the generator, not admin-editable data) —
  deliberately **not** a database table, since the set of parameters
  this project supports is a code/generator concern, not configuration
  data. A DB table would let an admin "add" a parameter the generator
  doesn't actually know how to render — a worse failure mode than a
  fixed, reviewed catalog.

**Duplicates**: a `UNIQUE(owner_id, object_type, param_name)` constraint
— at most one value per parameter per object; changing an override is an
`UPDATE`, not a second row. **Precedence**: the last stage in §10.
**Deletion**: clearing an override field in the UI simply deletes its row
(reverting to the template/default) — no soft-delete, consistent with
this project's full-stateless-rewrite philosophy.

---

## 10. Effective configuration precedence

```
1. System/code default        (Asterisk's compiled default, or a SENMA fallback constant)
2. Transport                  (SELECTED object, referenced by transport_id — never a source
                                of endpoint/aor/auth field values, only of the transport=
                                reference itself)
3. Template                   (extension or trunk template, selected via *_template_id)
4. Object-specific structured fields  (the object's own real columns/identity — host,
                                        secret, callerid, from_domain, identify_match, ...)
5. Explicit per-object override        (pjsip_*_overrides row for this exact parameter)
```
Later stages win. Per the task's explicit instruction, **transport
selection is itself governed by this same precedence** (template
suggests a `transport_id`, the object's own `transport_id` can override
it, §12) — but a transport's *own* fields (bind address, external
addresses, `local_net`, ...) never leak into stage 3/4/5 as generic
defaults for anything else. A transport is referenced, never merged.

---

## 11. Effective configuration preview

A read-only view/API (`effective config for extension <id>` /
`trunk <id>`), walking the §10 chain **per parameter** and reporting the
winning value plus its source label:

```
endpoint trunk-12
  direct_media = no         [template: Advance]
  from_user = 1836092627    [trunk]
  rtp_symmetric = yes       [template: Advance]
```

**Implementation-time constraint worth fixing now, even though nothing
is implemented yet**: the preview must call **the same rendering
function** the real generator uses (fed the resolved effective values),
not a second, independently-written renderer — otherwise the preview and
the real generated config can drift apart, which would be worse than no
preview at all. This is a design requirement for whichever future task
implements §11, not optional.

**Secrets**: `password`/`secret`/any credential-typed catalog parameter
is rendered masked (`password = ******** [trunk]`) — the *source* label
is still shown (useful for debugging "why is this trunk's secret what it
is"), the *value* never is, in either the annotated-precedence view or
the raw-generated-object view.

---

## 12. Transport selection

- `pjsip_extension_templates.transport_id` / `pjsip_trunk_templates.transport_id`: nullable, a **suggested default**.
- `peers.transport_id` / `trunks.transport_id`: nullable, an **explicit override** of the template's suggestion.
- Final resolution: object's own `transport_id` → else template's `transport_id` → else the transport currently marked `is_default`. The generator **always emits an explicit `transport=<name>`** on every endpoint/registration it writes — never relies on Asterisk's own implicit transport-matching heuristic, for the same "explicit over implicit" reasoning already applied throughout this project's PJSIP work (e.g., TASK-0015's AOR `contact=` decision).
- **Transport deleted while in use**: **hard blocked**, not silently orphaned — enforced by an `ON DELETE RESTRICT` foreign key (§18) as a backstop, with an application-level check first that reports exactly which templates/objects reference it (mirroring the existing, already-proven pattern: `Snep_Trunks_Manager::getValidation()`/`getRules()` already blocks trunk deletion the same way for route references).
- **Transport renamed**: safe by construction (§4) — references are by immutable `id`, not name. Requires re-running all three generators (§4) so the newly-generated text reflects the new name.
- **Transport reload fails**: same `PBX_Exception_IO`-throwing, response-text-checking discipline already proven in both existing generators (§1) — the UI should additionally warn that a transport failure has a wider blast radius than an endpoint/trunk failure (every object referencing it is potentially affected), a UX addition, not a new mechanism.

---

## 13. Real carrier example mapping

### A — REGISTER/auth trunk

| Field | Owner |
|---|---|
| `direct_media=no`, `force_rport=yes`, `rewrite_contact=yes`, `rtp_symmetric=yes` | Trunk Template: "Register/Auth" |
| `registration.enabled=yes`, expiration/retry_interval/fatal_retry_interval/forbidden_retry_interval/max_retries | same template |
| `auth_type=userpass` | same template |
| specific transport | template suggests, or trunk overrides |
| `host`, `username`, `password`, `from_user`, `from_domain`, `contact_user` | trunk identity (per-trunk) |

### B — IP-auth/no-register trunk

| Field | Owner |
|---|---|
| Same media/NAT block as A, or a distinct "IP-Auth" template if the provider's media needs genuinely differ | Trunk Template: "IP-Auth/No-Register" |
| `registration.enabled=no` | same template (no registration object emitted at all) |
| `identify.match` = a CIDR, possibly different from `host` | trunk identity — this is exactly why `identify_match` must be its own independent field (§1.6, §7), not derived from `host` |
| `host`, `from_domain` | trunk identity, independent values |

### C — fully independent fields (signaling destination ≠ identify CIDR ≠ From domain ≠ transport domain ≠ external media/signaling addresses)

| Field | Owner |
|---|---|
| Remote signaling destination (`host`) | trunk identity |
| Inbound identify source (`identify.match`) | trunk identity, **independent column from `host`** — the core fix this task's whole design exists to make possible |
| From domain (`from_domain`) | trunk identity, independent from both of the above |
| Transport `domain=` | the trunk's **selected transport's** own field — if this provider genuinely needs a distinct SIP domain identity at the transport layer, it gets its **own transport object** (§4/§14), not a fourth ad-hoc field bolted onto the trunk |
| External media/signaling addresses | the trunk's selected transport's own fields, same reasoning |

This is the direct, concrete proof that the transport-as-a-selectable-
object design (§2/§4) and the identity/template split (§6-§8) together
satisfy the task's central "must be modeled as independent concepts"
requirement — every one of the four independent facts in example C has
its own unambiguous, non-derived home in this architecture.

---

## 14. RTP/media architecture

Three genuinely distinct concepts, deliberately kept distinct, per the
task's own explicit instruction not to invent a generic "RTP IP" field:

1. **Remote RTP address learned from SDP**: negotiated per-call by
   Asterisk's own RTP stack from the SDP offer/answer. **Not a SENMA
   concept at all** — no column, no template field, nothing to design
   here. Confirmed nothing in the current codebase models this, and
   nothing in this proposal should.
2. **`external_media_address`/`external_signaling_address`**: what
   Asterisk *advertises* (in SDP `c=`/`o=` lines and Via/Contact headers)
   when it knows it's behind NAT. **Transport-level only** (§2) — this is
   a property of the network path a transport binds to, shared by every
   object using that transport. A provider needing a genuinely different
   advertised address gets its own transport (§13, example C) — never a
   per-endpoint/per-trunk field.
3. **RTP NAT *policy*** (`rtp_symmetric`, `direct_media`): a *behavioral*
   decision — "learn the real source dynamically regardless of what was
   advertised," "let two NAT'd endpoints try to bridge media directly."
   Endpoint-level, template-owned, per-object overridable (§6-§8) —
   complementary to, but architecturally independent of, what a
   transport advertises. A NAT'd endpoint on a correctly-configured
   transport can still want `rtp_symmetric=yes`; the two mechanisms
   solve different halves of the same real-world problem and must not be
   collapsed into one field.

---

## 15. NAT architecture (extension templates)

Three seeded, **ordinary, admin-editable/deletable** extension templates
— no special application logic branches on their names anywhere:

| Template | `direct_media` | `force_rport` | `rewrite_contact` | `rtp_symmetric` |
|---|---|---|---|---|
| LAN | yes | no | no | no |
| Remote NAT | no | yes | yes | yes |
| ATA/Intercom | no | yes | yes | yes (same NAT profile as Remote NAT; a genuinely distinct ATA-specific tuning, if one is ever needed — e.g. a shorter `qualify_frequency` for faster failure detection on embedded devices — is a *product* decision for the implementing task, not invented here) |

"Remote NAT" is exactly Example A from the task's own acceptance
examples. These are pure data rows; the seed migration (§17) is the only
place they're referenced by name, and only to populate their initial
values — deleting or renaming them after seeding has no special-cased
consequence anywhere in the design.

---

## 16. Template lifecycle

- **Create/edit**: standard CRUD against the header table + its params child table.
- **Delete**: blocked while usage count (`SELECT COUNT(*) FROM peers/trunks WHERE *_template_id = ?`) is greater than zero — enforced by `ON DELETE RESTRICT` (§18) as the hard backstop, with a friendly pre-check in the UI.
- **Duplicate/clone**: copy the header row (new name, e.g. "Copy of X") plus every params row — a plain, un-clever copy, matching this project's existing "duplicate route" precedent (`RouteController::duplicateAction()`).
- **Usage count**: shown on the template list page, computed live (not cached/denormalized — this project has no precedent for denormalized counters, and the query is cheap).
- **Edit propagation — default: YES, apply immediately on next regeneration.** This requires **zero new mechanism**: templates are read live by the generator on every `loadConfFromDb()` call (§1's full-stateless-rewrite property), so editing a template and then triggering the relevant generator (exactly as any extension/trunk edit already does today) makes every referencing object pick up the new effective values automatically. **Implication, documented plainly rather than silently accepted**: editing a widely-used template changes the live config of every object referencing it, immediately, with no per-object confirmation step. The recommended mitigation is a UI/UX safeguard, not a technical gate — show the usage count prominently on the template edit form ("this template is used by 47 extensions") before save, matching how this project already surfaces trunk/extension delete-blocking counts elsewhere, rather than inventing an approval workflow this product has no other precedent for.

---

## 17. Migration of existing data — no flag day

**The general algorithm, applied identically to extensions and trunks**:

1. Seed one default template per object type capturing today's *actual, currently-generated* hardcoded/derived values (§1) as the template's own values — e.g. the extension template's `direct_media`/`force_rport`/`rtp_symmetric`/`rewrite_contact` defaults are whatever `Snep_PjsipConf::renderExtension()` currently computes for the *most common* real input (today's actual, evidence-backed default path: no NAT checkboxes set → `force_rport=no, rtp_symmetric=no`; `rewrite_contact` always unset today → template default `no`).
2. Set every existing PJSIP `peers`/`trunks` row's new `*_template_id` to this seeded default (a single `UPDATE ... WHERE canal LIKE 'PJSIP/%'`).
3. **For every row whose current, already-stored/derived value differs from the new template's default, write an explicit override row** (`pjsip_extension_overrides`/`pjsip_trunk_overrides`) capturing that row's *existing* value for that exact parameter. This is not a special migration-only mechanism — it is the **same override table** §9 already designs, used here as the safety net that makes the migration lossless by construction: any extension that already had, say, `nat_comedia` checked keeps exactly `rtp_symmetric=yes` after migration, expressed as an override rather than losing that distinction to the shared template.
4. `transport_id` stays `NULL` for every row (§3) — no write needed, since `NULL` already means "use the current default transport," which is byte-identical to what every row already implicitly uses.
5. Regenerate both files once at the end of the migration and diff the output against the pre-migration generated files — **byte-for-byte identity (modulo the `; Generated:` timestamp line) is the migration's own acceptance test**, proving "preserve current effective behavior exactly" empirically, not just by design argument.

**What must be captured before migration for this to be lossless**
(directly answering the task's own question): every column §8's
ownership matrix marks as "ET/TT with per-object override" — i.e.
`allow`, `direct_media`, `dtmf_mode`, `force_rport`, `rewrite_contact`,
`rtp_symmetric`, `qualify_frequency`/`qualify_timeout`. `rtp_timeout`/
`rtp_timeout_hold`/`inbound_progress`/`message_context`/registration
tuning need **no** override capture, since they are *newly introduced*
concepts the current generator never emitted at all — there is no
existing behavior to preserve for a value that was never generated
before.

**A necessary consequence, stated plainly**: for a *templated* PJSIP
object, `peers.allow`/`nat`/`dtmfmode`/`directmedia` (the legacy,
chan_sip-shared columns) become **non-authoritative** for what
`Snep_PjsipConf` generates — the template (plus any override) is
authoritative instead. These columns are **not removed or repurposed**
— `Snep_InterfaceConf` (chan_sip, `Snep_InterfaceConf.php`) still reads
them unchanged for every non-PJSIP row, and pre-migration/un-templated
PJSIP rows (§19's explicit "None (legacy/manual)" template option) keep
reading them exactly as today. This is an additive capability, not a
column deprecation — consistent with every prior PJSIP milestone in this
project's history.

---

## 18. Schema design (proposed, not created)

### New tables

```
pjsip_transports
  id, name UNIQUE, protocol ENUM(udp,tcp,tls,wss,ws),
  bind_address, bind_port, domain NULL,
  external_signaling_address NULL, external_signaling_port NULL,
  external_media_address NULL, symmetric_transport BOOL DEFAULT FALSE,
  allow_reload BOOL DEFAULT TRUE, is_default BOOL DEFAULT FALSE,
  enabled BOOL DEFAULT TRUE,
  cert_file NULL, priv_key_file NULL, ca_list_file NULL, ca_list_path NULL,
  verify_client BOOL NULL, verify_server BOOL NULL,
  require_client_cert BOOL NULL, method NULL,
  created_at, updated_at

pjsip_transport_networks        -- local_net, repeatable
  id, transport_id FK -> pjsip_transports.id ON DELETE CASCADE, network (CIDR)

pjsip_transport_ciphers          -- cipher, repeatable, TLS-only/future
  id, transport_id FK -> pjsip_transports.id ON DELETE CASCADE, cipher

pjsip_extension_templates
  id, name UNIQUE, description NULL, is_seed BOOL DEFAULT FALSE,
  transport_id NULL FK -> pjsip_transports.id ON DELETE RESTRICT,
  created_at, updated_at

pjsip_extension_template_params
  id, template_id FK -> pjsip_extension_templates.id ON DELETE CASCADE,
  object_type ENUM(endpoint, aor), param_name, param_value,
  UNIQUE(template_id, object_type, param_name)

pjsip_trunk_templates
  id, name UNIQUE, description NULL, is_seed BOOL DEFAULT FALSE,
  transport_id NULL FK -> pjsip_transports.id ON DELETE RESTRICT,
  created_at, updated_at

pjsip_trunk_template_params
  id, template_id FK -> pjsip_trunk_templates.id ON DELETE CASCADE,
  object_type ENUM(endpoint, aor, auth, registration), param_name, param_value,
  UNIQUE(template_id, object_type, param_name)

pjsip_extension_overrides
  id, peer_id FK -> peers.id ON DELETE CASCADE,
  object_type ENUM(endpoint, aor), param_name, param_value,
  UNIQUE(peer_id, object_type, param_name)

pjsip_trunk_overrides
  id, trunk_id FK -> trunks.id ON DELETE CASCADE,
  object_type ENUM(endpoint, aor, auth, registration, identify), param_name, param_value,
  UNIQUE(trunk_id, object_type, param_name)
```

### New columns on existing tables

```
peers.extension_template_id  NULL FK -> pjsip_extension_templates.id ON DELETE RESTRICT
peers.transport_id           NULL FK -> pjsip_transports.id          ON DELETE RESTRICT
trunks.trunk_template_id     NULL FK -> pjsip_trunk_templates.id     ON DELETE RESTRICT
trunks.transport_id          NULL FK -> pjsip_transports.id          ON DELETE RESTRICT
```

### FK behavior summary (the task's own explicit ask)

| FK | ON DELETE | Why |
|---|---|---|
| `*_overrides.*_id → peers/trunks.id` | CASCADE | deleting the extension/trunk itself should delete its own overrides — nothing else references an override row |
| `*_template_params.template_id → *_templates.id` | CASCADE | a template's params have no meaning without the template |
| `peers/trunks.*_template_id → *_templates.id` | **RESTRICT** | "do not silently orphan objects" (item 12) and "protection against deleting a template in use" (item 16) — the DB itself is the backstop even if application-layer checks are ever bypassed |
| `peers/trunks.transport_id → pjsip_transports.id` | **RESTRICT** | same reasoning, for transports (item 12) |
| `*_templates.transport_id → pjsip_transports.id` | **RESTRICT** | a template's *suggested* transport must not silently vanish either |

**Why two real-FK'd template/override table pairs instead of one
polymorphic pair**: the task's own instruction emphasizes showing "key
constraints and foreign-key behavior" — a genuine FK (`peer_id → peers.id`,
`trunk_id → trunks.id`) is stronger and more debuggable than a
polymorphic `(owner_type, owner_id)` pair with no DB-enforced reference
at all. The *sharing* the task asks for (§5/§9) happens in the PHP-side
catalog/validation/rendering code, not by forcing a single ambiguous
table — normalized without becoming unqueryable, per the task's own
explicit preference.

---

## 19. UI architecture

```
PJSIP
├── Transports              (list, create/edit, usage count, delete-blocked message)
├── Extension Templates      (list, create/edit, duplicate, usage count, delete-blocked message)
└── Trunk Templates          (list, create/edit, duplicate, usage count, delete-blocked message)
```

**Extension create/edit** gains: a template selector (including an
explicit **"None (legacy/manual)"** option — critical for gradual
adoption and for the migration's own un-templated fallback, §17); a
transport selector (defaulting to the template's suggestion, editable);
an **Advanced / Overrides** collapsible section listing the parameter
catalog (§9) with each field's current effective value, its source label
(§11), and an input to set/clear an override.

**Trunk create/edit** gains the same template + transport selectors,
plus the identity/auth/host fields (§7 — unchanged, still directly on
the form, never templated) and the same Advanced/Overrides section.

**Both** gain an **effective-config preview** (a button/tab rendering
§11's precedence-annotated table plus the raw generated-object text,
secrets masked).

This is deliberately not a broader redesign — three new list pages plus
targeted additions to two already-existing forms, matching exactly the
scope TASK-0010/0011/0014/0015 already used for every prior PJSIP UI
change (one new `<option>`/one new selector at a time, never a page
rewrite).

---

## 20. Security

- **Secrets never appear in the effective-config preview or the raw
  generated-object preview** in plaintext — masked in both, per §11.
  This is a **stricter** standard than the existing edit-form behavior
  (TASK-0010 §7 already documents the existing extension/trunk edit form
  round-tripping secrets in plaintext HTML — a pre-existing, unrelated,
  out-of-scope behavior this task does not touch or need to touch), applied
  deliberately to the **new** preview surface because it is a wider,
  more casually-reachable view than an edit form an admin explicitly
  opened to change a password.
- **Template visibility**: templates/transports are global configuration
  objects with no existing multi-tenant scoping concept in this
  single-install architecture — visible to whatever role already has
  Trunks/Extensions access; no new access-control model is proposed or
  needed.
- **No arbitrary raw PJSIP directive injection**: the override/template
  parameter catalog (§9) is the enforcement mechanism — a `param_name`
  not present in the code-owned catalog for its `object_type` cannot be
  written, by construction, not by input sanitization after the fact.
- **Identify CIDR validation**: `identify.match` is typed `cidr` in the
  catalog — validated as a real IPv4/IPv6 address or CIDR block before
  being accepted (rejecting free text), both for template/override
  values and for the per-trunk `identify_match` identity field.
- **Secrets never logged**: the existing reload-failure log line already
  only logs Asterisk's own response text, never file content (TASK-0011
  §2) — the transport generator and the effective-config computation
  must follow the identical discipline; neither should ever log a full
  rendered object (which could contain a `password=` line) or a resolved
  override/template value for a credential-typed parameter.

---

## 21. Validation strategy (future automated coverage)

Not built now — designed for whichever future task implements this.

- **Extension, default/LAN profile**: create via a template-driven HTTP
  flow, assert the generated endpoint reflects the LAN template's values
  (`pjsip show endpoint` output), place a real call (reuse `call-smoke`'s
  existing baresip pattern).
- **Extension, remote-NAT profile**: same, asserting `force_rport=yes`/
  `rewrite_contact=yes`/`rtp_symmetric=yes` actually appear in the live
  endpoint — proving the template's values, not merely the object's
  existence, took effect.
- **Trunk, REGISTER/auth**: extends `trunk-smoke`'s existing outbound
  registration check (already proven, 23/23) to a template-driven trunk
  instead of raw per-trunk fields.
- **Trunk, IP-auth/no-register**: a **genuinely new** acceptance case —
  today's `trunk-smoke` only exercises the register-based model
  (TASK-0015 §1's own explicit scope choice). Needs a provider-simulator
  variant (or a second static endpoint on the existing simulator, per
  TASK-0016's `to-senma` precedent) with no registration relationship at
  all, proving `identify`-only inbound acceptance and outbound calling
  work with `registration.enabled=no`.
- **Custom transport with independent identify/signaling/media
  settings**: the **hardest** future test to build, flagged honestly
  rather than hand-waved — a flat Docker bridge network has no real NAT
  translation across the path the way a genuine remote deployment does,
  so "external_media_address differs from the bind address and calls
  still work" cannot be proven with real cross-NAT media the way
  TASK-0015/0016 proved real signaling. The most honest available proof
  without a commercial carrier (explicitly disallowed by the task) is
  **configuration-level**: assert via `pjsip show transport <name>` and
  the generated file's content that a second, distinctly-configured
  transport with its own `external_media_address`/`identify` binding
  loads correctly and is referenced by the correct trunk — proving the
  *architecture* wires correctly, not proving real NAT traversal, which
  this project has no current way to test without real external network
  conditions. This limitation should be stated in whichever future task
  builds this test, not silently treated as solved.

---

## 22. Implementation sequencing

```
TASK-0018 -- Transports
  pjsip_transports + child tables, Snep_PjsipTransportConf, seed
  udp/tcp/wss, Transports UI CRUD, reload. No peers/trunks column
  changes yet -- transports exist and are manageable, but nothing
  references them.
↓
TASK-0019 -- Templates + overrides schema
  pjsip_{extension,trunk}_templates(+_params), pjsip_{extension,trunk}
  _overrides, the shared parameter catalog, Extension/Trunk Templates
  UI CRUD (create/edit/duplicate/usage-count/delete-blocked). No
  generator wiring yet -- schema and UI are independently validatable
  via make smoke-style HTTP checks before touching what actually gets
  generated, the same staged-risk discipline TASK-0010/0011 already
  used (design/schema before runtime wiring).
↓
TASK-0020 -- Extension-template integration
  Snep_PjsipConf reads extension_template_id + overrides + transport_id,
  computes effective config (§10), generates from it. Migration per §17
  (seed default template, backfill overrides, byte-for-byte regenerated-
  file diff as the acceptance test). Effective-config preview UI for
  extensions (§11).
↓
TASK-0021 -- Trunk-template integration
  Same for Snep_PjsipTrunkConf + trunks, including seeding the two
  acceptance templates (REGISTER/auth, IP-auth/no-register, §13) and
  fixing the trunks.domain dead-column bug (§1.6) as part of wiring
  from_domain through the new model. Effective-config preview UI for
  trunks.
↓
TASK-0022 -- Validation/regression hardening
  New profile-based smoke coverage (§21), full make smoke/call-smoke/
  trunk-smoke regression, documentation.
```

**Why this order and not another**: transports first because both
template kinds reference `transport_id` (§8) — the table must exist
before anything can suggest a default. Schema/CRUD (0019) before
generator wiring (0020/0021) so each layer is independently testable
before the higher-risk step of changing what real Asterisk objects get
emitted — matching TASK-0010-then-0011's own design-then-implement
staging. Extensions (0020) before trunks (0021): extensions are the
already-proven simpler case (fewer object types — no registration/
identify) and de-risk the effective-config/override mechanism itself
before applying it to trunks' larger object set. Validation/hardening
(0022) last, as its own dedicated task, matching this project's existing
pattern of a closing regression task rather than folding final
validation into the last feature task.

---

## 23. Explicitly deferred

Unchanged from the task's own list: TLS certificate management, WebRTC,
SRTP, provider-specific presets beyond the seeded example templates,
PostgreSQL, broad frontend redesign, carrier auto-detection,
configuration import from arbitrary `pjsip.conf`.

---

## 24. Explicit architectural recommendation

**Build three new, deliberately separate generator classes
(`Snep_PjsipTransportConf`, and templated/override-aware evolutions of
the existing `Snep_PjsipConf`/`Snep_PjsipTrunkConf`), backed by six new
tables plus four new nullable, `ON DELETE RESTRICT` foreign-key columns
on `peers`/`trunks` — never a single generic "PJSIP settings" table, and
never a free-text override field.** Model transport, template, and
override as three genuinely distinct concerns with one shared, code-owned
parameter catalog gluing template and override validation/rendering
together, resolved through an explicit five-stage precedence chain
(system default → transport selection → template → object identity →
override) whose *transport* stage is a reference, never a source of
merged defaults. Keep the two template kinds and two override kinds as
real, separately-FK'd tables (extension vs. trunk) rather than one
polymorphic pair, and keep every provider/extension *identity* fact
(host, secret, from_domain, identify_match, callerid, mailbox) as a
real, always-per-object column, never template material — precisely
because this project's own current implementation already shows what
goes wrong when that line blurs (`trunks.domain`'s silent dead-column
bug, `identify.match` hardcoded to the same field as the outbound
`host`). Migrate with zero flag day by exploiting the same nullable-FK
pattern already proven for transports: every existing object keeps
working unchanged because `NULL` means "use today's implicit default,"
and any per-row value that would otherwise be lost by adopting a shared
template becomes an explicit override row instead — the exact same
mechanism real day-two administrators will use for their own
exceptions, not a separate migration-only code path.

---

Stopping here for approval. No transports/templates were implemented.
