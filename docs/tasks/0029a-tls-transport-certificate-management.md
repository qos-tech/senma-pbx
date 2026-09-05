# TASK-0029A — TLS transport certificate management

Status: Resolved. Two consecutive full `make regression` PASS runs (27/27
each, including the new `tls-cert-management-smoke` suite), `make lint`
PASS, `git diff --check` PASS. Not committed — awaiting authorization per
CLAUDE.md's commit policy.

Lead: `senma-telephony-architect`. Reviewer: `senma-docker-platform-engineer`.
`senma-application-architect`/`senma-product-designer` were not invoked --
see SCOPE for why.

## Objective

TASK-0028Z proved the WSS platform path operational using a
test-generated self-signed certificate, but `pjsip_transports` had no
certificate-related schema fields and no product-level certificate
ownership model at all — TLS/WSS could not yet be configured safely for
a real production certificate. This task defines and implements that
model: ownership, storage, selection, validation, generation, runtime
apply, rotation, and failure behavior.

## CURRENT STATE (Phase 1 inventory)

- `pjsip_transports` (TASK-0018): no `cert_file`/`priv_key_file`/etc.
  columns at all. **Classification: this gap was ALREADY anticipated and
  scoped**, not an oversight — `docs/tasks/0018-pjsip-transports.md` §1
  explicitly deferred it ("a trivial `ALTER TABLE` for whichever future
  task implements real TLS/WSS behavior"), and
  `docs/tasks/0017-pjsip-transports-and-templates-architecture.md` §2
  already sketched a candidate field set for exactly this task.
  Classification: **PARTIAL** (architecture anticipated, not built).
- `Snep_PjsipTransportConf::renderTransport()`: emits `type`, `protocol`,
  `bind`, `domain`, `external_*`, `local_net`, `symmetric_transport`,
  `allow_reload` — no TLS fields. **REUSABLE** as the extension point.
- `snep/install/etc/asterisk/http.conf` (the LEGACY, pre-Docker
  installer's own http.conf template): already had
  `tlsprivatekey=/etc/asterisk/keys/asterisk.pem` /
  `tlscertfile=/etc/asterisk/keys/asterisk.pem` — a single combined PEM
  at a conventional path, with a comment instructing the installer to
  generate it manually via `openssl req -new -x509 ...`. No install
  script anywhere in this repository ever actually ran that command —
  **PARTIAL**: establishes the `/etc/asterisk/keys/` path convention
  (which TASK-0028Z's own entrypoint-generated fixture already reused),
  but had no real automation to reuse.
- `snep/lib/Zend/{InfoCard,Crypt/Rsa,Oauth}.php`: vendored
  Zend Framework 1 certificate/crypto code for unrelated auth protocols
  (InfoCard/OAuth). **UNRELATED**.
- No upload mechanism for binary/text file content exists anywhere in
  this codebase.

## FINDINGS (live evidence, gathered before any implementation)

1. **`cert_file`/`priv_key_file`/`ca_list_file` set directly on a
   `protocol=wss` PJSIP transport object are silently ignored by
   Asterisk.** Confirmed live: setting them (even to a nonexistent path)
   and running `module reload res_pjsip.so` reports "reloaded
   successfully", and `pjsip show transport wss` shows those fields
   still blank. `res_pjsip_transport_websocket.so` does not use them at
   all — TLS for ws/wss is controlled exclusively by Asterisk's built-in
   HTTP server (`http.conf`'s `tlsenable`/`tlsbindaddr`/`tlscertfile`/
   `tlsprivatekey`), a single, GLOBAL, process-wide listener, not a
   per-PJSIP-transport-object concept.
2. **The same fields genuinely work for `protocol=tls`** (a native
   PJSIP SIP-over-TLS transport). Confirmed live: created a `tls`
   transport with a real self-signed cert/key pair and `method=tlsv1_2`;
   `pjsip show transport <name>` reflected every field, and a real
   `openssl s_client` TLS handshake against its bind port presented
   exactly that certificate (`subject=CN=<test-cn>`).
3. **`http.conf`'s TLS certificate hot-reloads safely.** Confirmed live,
   twice, both directions: changing `tlscertfile`/`tlsprivatekey` and
   running `module reload http` (or `core reload`) immediately presents
   the new certificate to a fresh TLS connection to port 8089 — no
   Asterisk/container restart needed.
4. **A native `tls` transport's certificate does NOT reliably hot-reload
   in place** when the bind address:port is unchanged (i.e., editing an
   already-loaded transport's cert, as opposed to creating a brand-new
   one on a never-before-used bind). Reproduced twice, two different
   ways: (a) a reload after an in-place cert swap produced a TLS
   session that would not complete ANY protocol version negotiation
   (`ssl3_read_bytes:tlsv1 alert protocol version` /
   `ssl_choose_client_version:unsupported protocol`, alternating by
   which TLS version the client offered); (b) a reload after removing
   and re-adding a transport on a bind port used earlier in the same
   Asterisk process lifetime kept presenting the OLD certificate,
   unchanged, even though `pjsip show transport` correctly reported the
   NEW `cert_file` path. A brand-new bind address:port always worked
   correctly on the very first `module reload res_pjsip.so`. This
   matches this project's own already-documented TASK-0020 finding
   ("a plain reload never frees the OS socket") extended one layer
   deeper, to TLS context reuse specifically.
5. Asterisk's http.conf option set is narrower than a native PJSIP `tls`
   transport's: confirmed via `grep -a` against the compiled `asterisk`
   binary for real recognized `tls*` option identifiers. `tlscafile`/
   `tlsverifyclient` are real; there is no http.conf equivalent of a
   PJSIP transport's `verify_server`/`method`/`cipher` — Asterisk's
   built-in HTTP server has no "Asterisk dials out and verifies the
   remote server" concept, and no documented option to pin its accepted
   TLS version independent of OpenSSL's own defaults.
6. The `app` container mounts the SAME `asterisk-etc` named volume at
   `/etc/asterisk` (read-write) that the `asterisk` container does —
   confirmed in `compose.yaml`. This means SENMA's PHP code can validate
   certificate PATHS directly via the filesystem, without any new
   volume/mount work.
7. The certificate file (`wss-test-cert.pem`, TASK-0028Z) is `0644`
   (world-readable — correct, a public certificate has no
   confidentiality requirement) but the private key
   (`wss-test-key.pem`) is `0600`, owned by the `asterisk` user. The
   `app` container's `www-data` user is a DIFFERENT uid (even though
   both share the unrelated `senma-config` GROUP for `/etc/asterisk/snep`
   generated-config writability) — it can `file_exists()` the key
   (directory traversal only) but cannot read its bytes, by design.

## CERTIFICATE OWNERSHIP MODEL (DECISION)

**Model B — externally-managed certificate PATHS.** An admin places
real certificate/key material at a filesystem path inside the
persistent `asterisk-etc` volume (the same `/etc/asterisk/keys/`
convention TASK-0028Z and the legacy installer both already used); SENMA
stores and validates a PATH REFERENCE to that material, never
certificate/key BYTES. No upload UI, no certificate-inventory entity/
table.

Rejected:
- **Model A (SENMA-managed inventory with upload).** No upload mechanism
  exists anywhere in this codebase; building one is new, security-
  sensitive subsystem territory unjustified by the actual need — this
  product realistically has at most one or two TLS-capable transports at
  a time (a `wss` row and, rarely, a native `tls` trunk/registration
  transport), so a reusable many-transports-share-one-certificate entity
  (Phase 3's own explicit caution against "a large certificate-
  management subsystem" for a need "simple validated path references"
  already satisfy) buys nothing at this scale.
- **Model C (hybrid selectable bundles).** Same rejection reasoning —
  the "selectable bundle" abstraction is a certificate-inventory entity
  in different clothing, for the same non-existent multiplicity.

This also directly satisfies the task's own stated security invariant
("mounted persistent config / secret-managed path → SENMA stores
references/metadata → Asterisk reads files from controlled filesystem
paths"; "avoid private key → plaintext database blob").

### PRIVATE KEY STORAGE MODEL

Never in the database. A path string only. The file itself: `0600`,
owned by the `asterisk` user, in `/etc/asterisk/keys/` (the persistent
volume). SENMA's PHP process (a different uid, `www-data`) can prove the
path exists (`file_exists()`, needs no read permission) but cannot and
does not read its content — this is deliberate, not a gap: reading it
would require either weakening the key's own permissions (rejected) or
building a privileged exec bridge from the app container into the
Asterisk container to run `openssl` there (new, unjustified attack
surface, explicitly out of scope). Whether the key is valid, and
whether it matches its certificate, is proven by Asterisk's own runtime
apply instead (see VALIDATION / RUNTIME APPLY).

### TRANSPORT REFERENCE MODEL

New nullable columns directly on `pjsip_transports` (no new table): a
1:1 relationship between a transport row and its own certificate
reference. See DATA MODEL.

### RUNTIME APPLY MODEL

Two genuinely different mechanisms, by protocol (Finding 1/3/4 above):

- **`wss`/`ws`**: exactly one enabled row process-wide may carry
  certificate material (enforced at save time — Asterisk's built-in HTTP
  server has exactly one TLS listener). `Snep_PjsipTransportConf`
  generates a small `senma-http-tls.conf` snippet from that one row and
  triggers `module reload http` — hot, safe, proven live.
- **`tls`**: emitted directly onto the transport's own PJSIP object.
  Safe via `module reload res_pjsip.so` for a NEW bind address:port;
  NOT proven safe for an in-place certificate change on an
  ALREADY-BOUND address:port (Finding 4) — surfaced explicitly (see
  FAILURE BEHAVIOR), not silently assumed to work.

### ROTATION MODEL

- **wss/ws**: replace the referenced cert/key path(s) through the
  existing transport edit form; SENMA saves, regenerates, and hot-
  reloads automatically. Proven live, in both directions (new cert
  presented; old cert no longer presented after reverting).
- **tls**: replacing the cert/key of an EXISTING transport is
  deterministic but NOT hot — an Asterisk restart is required to
  guarantee the new certificate is actually used (Finding 4). SENMA
  detects and reports this rather than silently claiming success (see
  FAILURE BEHAVIOR); it does not attempt zero-downtime rotation for this
  case, matching the task's own "does not require zero-downtime unless
  the architecture supports it, but behavior must be deterministic and
  documented" instruction.

## SCOPE

`senma-application-architect` was **not** invoked: the schema change is
6 nullable/defaulted columns added to an existing table via the
existing `PjsipTransportsController`/`Snep_PjsipTransports_Manager`
CRUD path — no new controller, no new API surface, no authorization or
cross-entity boundary change. `senma-product-designer` was **not**
invoked: the UI change is an incremental fieldset added to the existing
transport add/edit form (same shape as prior incremental additions to
this exact form), conditionally shown/hidden by protocol — not a new
user-facing workflow.

Changed:
- `snep/install/database/schema.sql` — `pjsip_transports` new columns.
- `snep/install/database/system_data.sql` — `wss` seed now references
  the TASK-0028Z dev-fixture certificate by default, and is now seeded
  `enabled=true` (previously `false` — see WSS INTEGRATION).
- `snep/lib/Snep/PjsipTransports/Manager.php` — validators, certificate/
  key inspection helpers, the "one active WSS certificate" conflict
  check, `verifyTlsHandshake()`.
- `snep/lib/Snep/PjsipTransportConf.php` — TLS field emission for
  `protocol=tls`; new `writeHttpTlsConf()`/`reloadHttp()` for wss/ws.
- `snep/modules/default/controllers/PjsipTransportsController.php` —
  field defaults, `validateTlsFields()`, extended `reportApplyResult()`
  runtime verification, cert inspection data for the edit view.
- `snep/modules/default/views/scripts/pjsip-transports/addedit.phtml` —
  new "TLS / Certificate" fieldset, shown for `tls`/`wss`/`ws` only.
- `docker/asterisk-config/http.conf` — TLS settings extracted into a
  `#include`d generated file (was static/hardcoded since TASK-0028Z).
- `docker/asterisk-entrypoint.sh` — pre-creates the new generated file.
- `Makefile`, `scripts/regression.sh` — new `tls-cert-management-smoke`
  suite wired in.
- `scripts/tls-cert-management-smoke-test.sh` (new).

Not changed: `docker/wss-test-client*` (TASK-0028Z's client is reused
unmodified for the WSS registration proof, which stays in
`wss-platform-smoke-test.sh`'s own scope, not duplicated here).

## DATA MODEL

```sql
ALTER TABLE pjsip_transports ADD COLUMN:
  cert_file      varchar(255) default NULL,
  priv_key_file  varchar(255) default NULL,
  ca_list_file   varchar(255) default NULL,
  verify_client  BOOLEAN NOT NULL default false,
  verify_server  BOOLEAN NOT NULL default false,
  method         varchar(20) default NULL;
```

Deliberately narrower than TASK-0017 §2's original speculative sketch
(`cert_file, priv_key_file, ca_list_file, ca_list_path, verify_client,
verify_server, require_client_cert, method, cipher` + a repeatable
`pjsip_transport_ciphers` child table). Cut, each for a concrete reason:

- `ca_list_path` — a directory-based CA store, functionally redundant
  with `ca_list_file` for any realistic single-bundle deployment; two
  competing "where's my CA" fields would only confuse admins.
- `require_client_cert` — a stricter, distinct-from-`verify_client`
  mandatory-mTLS knob with zero evidenced product need.
- `cipher` / `pjsip_transport_ciphers` — no evidenced need to restrict
  cipher suites; this product does not need to expose every Asterisk
  TLS knob (the task's own explicit instruction).

Existing installations: apply the equivalent `ALTER TABLE` (same
precedent TASK-0018 itself established — SENMA's own schema changes are
edited directly into `schema.sql`/`system_data.sql`, with no separate
incremental-migration-file convention; the `snep/install/database/
update/` tree is exclusively the historical SNEP 3.01–3.07 upgrade
chain). The `wss` seed row backfills to the dev-fixture cert path,
`enabled=true`.

## FILESYSTEM MODEL

`/etc/asterisk/keys/` (already established by TASK-0028Z, itself
matching the legacy installer's own convention) inside the persistent
`asterisk-etc` named volume, mounted read-write into both the
`asterisk` and `app` containers. An admin adds real certificate/key
files there directly (e.g. `docker compose exec asterisk sh`, running as
the `asterisk` user, which already owns and can write into this
directory — no new permission engineering needed), then references the
exact path through the SENMA UI.

Recommended/expected mode: certificate `0644` (world-readable — a
public certificate has no confidentiality requirement, and the app
container must be able to read+parse it for validation feedback); key
`0600`, owned by `asterisk`. SENMA does not enforce this by force
(an admin fixing an urgent TLS outage should never be locked out by a
permission check), but the UI surfaces an explicit warning when a
private key's mode is broader than `0600` (`Manager::keyFileExists()`'s
`mode_warning`, stat-only — never reads the key's content).

Proven to survive both `docker compose restart asterisk` and
`docker compose up -d --force-recreate asterisk` byte-for-byte (sha256
compared before/after) — see REGRESSION PROOF.

## TRANSPORT CONTRACT

| Field | Classification | Applies to |
|---|---|---|
| `cert_file` | REQUIRED (if protocol=tls and enabled) / OPTIONAL (wss/ws) | tls, wss, ws |
| `priv_key_file` | REQUIRED (if protocol=tls and enabled) / OPTIONAL (wss/ws) | tls, wss, ws |
| `ca_list_file` | OPTIONAL_SUPPORTED (required only if verify_client/verify_server) | tls, wss(verify_client only) |
| `verify_client` | OPTIONAL_SUPPORTED | tls, wss/ws (via `tlsverifyclient`) |
| `verify_server` | OPTIONAL_SUPPORTED | tls only — no http.conf equivalent exists |
| `method` | ADVANCED (secure-only allow-list: '', tlsv1_2, tlsv1_3) | tls only — no http.conf equivalent exists |
| `ca_list_path`, `require_client_cert`, `cipher` | UNSUPPORTED_BY_DESIGN | none — not added |

`udp`/`tcp` reject all of the above being set at all (explicit failure,
not silent drop — `PjsipTransportsController::validateTlsFields()`).

## VALIDATION (Phase 8)

Pre-save, in `validateTlsFields()`:
- path syntax (absolute, no NUL bytes, length);
- `method` against the secure-only allow-list;
- `verify_client`/`verify_server` requires `ca_list_file`;
- protocol-appropriateness (TLS fields rejected outright for udp/tcp;
  cert+key must both be set or both empty for wss/ws; both required for
  an enabled tls transport);
- **the one-active-WSS-certificate conflict** (`findActiveWssCertConflict()`)
  — Asterisk's built-in HTTP server has exactly one TLS listener;
- `cert_file`: real existence + readability + `openssl_x509_parse()`
  success (`inspectCertificateFile()`) — file-does-not-exist and
  invalid-PEM-content both proven rejected live;
- `priv_key_file`: existence only (`file_exists()`, no content read —
  see PRIVATE KEY STORAGE MODEL for why).

**Cert/key MATCH is deliberately NOT validated pre-save** — SENMA cannot
read the private key's bytes without weakening its permissions (Finding
7/DECISION). It is caught instead at RUNTIME APPLY.

## RUNTIME APPLY

`PjsipTransportsController::reportApplyResult()`, extended:
1. existing `isRuntimeActive()` (object loaded, correct bind) — unchanged;
2. **new**: `Snep_PjsipTransports_Manager::verifyTlsHandshake()` — a
   real TLS connection (from the app container, over the Docker network,
   to the Compose service DNS name) comparing the certificate Asterisk
   actually presents against the one configured. Proven live to catch
   exactly the failure `isRuntimeActive()` cannot: a transport whose
   cert/key is broken still reports "loaded" while a real client gets a
   handshake failure.
3. Both `'mismatch'` (a different-but-valid certificate presented) and
   `'unreachable'` (the TLS connection/handshake fails outright — the
   observed shape of Finding 4's in-place-rotation hazard) surface the
   same `apply_failed` flash; `'skipped'` (the plain HTTP listener's
   deliberate loopback-only bind, TASK-0028Z) is not an error.

For wss/ws, `writeHttpTlsConf()` + `reloadHttp()` (`module reload http`)
run unconditionally at the end of every `Snep_PjsipTransportConf::
loadConfFromDb()` call — the same "full stateless rewrite, unconditional
reload" idiom this class already used for `module reload res_pjsip.so`.

## ROTATION (Phase 11 proof)

WSS: swapped to a newly-generated certificate through the real edit
form; a fresh TLS connection to port 8089 immediately presented the new
certificate (subject match); generated `senma-http-tls.conf` reflected
the new path; reverted, and the old certificate was confirmed no longer
presented. All live, no restart.

Native tls: see FAILURE BEHAVIOR — rotating an EXISTING transport's
cert in place is exactly the scenario `verifyTlsHandshake()` exists to
catch (proven live via the deliberate mismatched-pair test, which
surfaced `'unreachable'`, matching Finding 4 exactly).

## FAILURE BEHAVIOR (Phase 12 proof, all live via the real HTTP flow)

| Scenario | Result |
|---|---|
| Nonexistent certificate path | Rejected pre-save: "file does not exist" |
| Non-PEM file content | Rejected pre-save: "not a valid PEM X.509 certificate" |
| Cert set, key empty (wss) | Rejected pre-save: "must both be set" |
| Enabled `tls` transport, no cert/key | Rejected pre-save: "both required for a TLS transport" |
| Second enabled WSS row, different cert | Rejected pre-save: "already provides the active WSS/WS certificate" |
| Individually-valid but mismatched cert/key pair | **Accepted pre-save** (SENMA cannot know), then surfaced live as `apply_failed`: "its live TLS certificate could not be confirmed... an Asterisk restart is required" |

No scenario reaches "save succeeds, transport silently unusable."

## WSS INTEGRATION

The `wss` seed row is now `enabled=true` by default (previously `false`
— TASK-0018/0017 seeded it disabled specifically because "a WSS
transport with no certificate configured cannot actually bind"; now
that it has a real, working default certificate reference — the same
TASK-0028Z dev fixture, referenced through this task's own mechanism
instead of hardcoded directly into `http.conf` — leaving it disabled
would just reintroduce the exact silently-inert state TASK-0028W
originally flagged). `make dev` continues to need zero admin action for
WSS to work out of the box; a production deployment replaces
`cert_file`/`priv_key_file` with its own real certificate through the
same form.

## TASK-0028Z FIXTURE MIGRATION (Phase 14)

Classification: **REPLACE_WITH_CERTIFICATE_MODEL.** The self-signed
generation logic in `docker/asterisk-entrypoint.sh` is unchanged and
kept (still the right DEV_FALLBACK behavior — a zero-config working
default), but `docker/asterisk-config/http.conf` no longer hardcodes its
path directly: that static file now only sets the base
`[general]`/loopback-plain-listener lines and `#include`s a GENERATED
file (`senma-http-tls.conf`) sourced from the `wss` transport row's own
`cert_file`/`priv_key_file` columns — the identical mechanism a
production admin uses for a real certificate. One ownership model, not
two. (An existing dev volume that already ran TASK-0028Z keeps its old,
still-functional hardcoded `http.conf` until it is deleted or `make
reset` is run — the established first-boot-seed pattern never overwrites
an existing file, matching customer-owned-config precedent; this
session's own environment was updated by hand for continued testing.)

## SECURITY REVIEW

- Private key bytes never enter the database, never enter an HTTP
  request/response body, never enter a log line.
- `www-data` (app container) cannot read the private key file — proven
  by construction (0600, different uid), not merely assumed.
- No new port exposure, no new HTTP surface, no new container, no new
  image dependency (PHP's `openssl` extension and the runtime image's
  `openssl` CLI were already present).
- `git ls-files` confirmed to contain zero `.pem`/`.key`/`.crt` files —
  proven as a regression check, not just asserted.

## REGRESSION PROOF

New suite `scripts/tls-cert-management-smoke-test.sh`: **19/19 PASS**,
run standalone twice consecutively (idempotency confirmed — the second
run reused the exact same fixture names/ports with the leftover-fixture
recovery path exercised cleanly). Covers: valid cert accepted (both
tls and wss models) with real TLS handshake + subject match; invalid
path/PEM/incomplete-pair/conflicting-second-certificate all rejected
pre-save; genuinely mismatched cert/key surfaced live as `apply_failed`;
generated config correctness (both `senma-pjsip-transports.conf` for
tls and `senma-http-tls.conf` for wss); WSS rotation (both directions);
udp/tcp unaffected (direct inspection of their generated stanzas);
restart persistence (cert file sha256 unchanged, WSS still serves the
original certificate); no committed secrets.

Affected pre-existing suites re-run individually, no regressions:
`transport-smoke` (64/64), `wss-platform-smoke` (28/28),
`pjsip-lifecycle-smoke` (36/36).

`make lint`: PASS (5/5 — 270 PHP files 0 syntax errors, 35 shell scripts
parse cleanly, 3 `resources.xml` well-formed, clean `git diff --check`).

`make regression`: two consecutive **PASS, 27/27 suites** official runs
(three earlier attempts hit `res_pjsip.so/chan_pjsip.so not both
Running` on three DIFFERENT, unrelated, pre-existing suites in turn —
the exact, already-documented transient PJSIP-module-warmup race this
project's own `docs/tasks/0026z-security-audit-closure.md` PR-06 and
`docs/tasks/0026l-pickup-queues-sql-closure.md` both previously
encountered and classified RUNTIME_RACE, unrelated to the change under
test each time; per that established precedent, the next clean run
stands as official run 1). `git diff --check`: PASS. `git status
--short`:

```
 M Makefile
 M docker/asterisk-config/http.conf
 M docker/asterisk-entrypoint.sh
 M scripts/regression.sh
 M snep/install/database/schema.sql
 M snep/install/database/system_data.sql
 M snep/lib/Snep/PjsipTransportConf.php
 M snep/lib/Snep/PjsipTransports/Manager.php
 M snep/modules/default/controllers/PjsipTransportsController.php
 M snep/modules/default/views/scripts/pjsip-transports/addedit.phtml
?? scripts/tls-cert-management-smoke-test.sh
```

Not committed — awaiting authorization per CLAUDE.md's commit policy.

## REMAINING DEBT

Kept strictly separate from TASK-0029B (PJSIP runtime status UI — not
touched here). Genuine, explicitly out-of-scope debt:

- No certificate expiration warning/alerting in the UI (Phase 8 allowed
  this to be skipped when not part of the chosen product contract; no
  evidenced need yet — `inspectCertificateFile()` already surfaces
  `not_after` in the edit view, so a future expiry-warning banner is a
  small addition, not a redesign).
- Native `tls` transport certificate rotation on an already-bound
  address:port is deterministic but requires a full Asterisk restart —
  this is documented and detected (not silently broken), but a future
  task could investigate whether Asterisk offers any TLS-context-only
  reload primitive that avoids a full restart (not found during this
  task's own investigation; not blocking).
- Full ACME/Let's Encrypt automation, a certificate upload UI, and CA
  management remain explicitly out of scope, per the task's own
  boundary.

## RECOMMENDATION

`APPROVE`.

## PROPOSED COMMIT

A single coherent commit — schema, generator, controller, view, and
platform changes are all one indivisible feature (a transport row's
certificate reference has no meaning without the generator/controller
code that uses it, and vice versa):

```
feat(pjsip): add TLS/WSS transport certificate management

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FP7YzWTLhPbMEVgpGAsNdv
```

The new regression suite could be split into its own `test:` commit if
preferred, but since it exercises exactly (and only) this feature's own
new contract, bundling it with the feature commit is the more coherent,
reviewable unit.
