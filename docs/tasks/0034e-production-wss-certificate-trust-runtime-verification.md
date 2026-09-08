# TASK-0034E — Production WSS Certificate Trust & Runtime Verification

Status: Resolved. Two consecutive full `make regression` PASS runs
(41/41 each, including the new `wss-certificate-runtime-smoke` suite),
`make lint` PASS, `make doctor` 0 FAIL, `make secrets-check` MATCH, `make
migrate-check` SCHEMA_CURRENT, `make reconcile-check` IN_SYNC, `git diff
--check` PASS. Not committed — awaiting authorization per CLAUDE.md's
commit policy.

Lead: `senma-telephony-architect`. Reviewers: `senma-docker-platform-engineer`,
`senma-application-architect` (consulted via their domain rules/lenses;
no separate agent sessions were spawned — the change is a diagnostic/
tooling extension of TASK-0029A's own existing certificate-reference
model, not a new controller/persistence/API surface or a container
lifecycle change). `senma-asterisk-pjsip-engineer` was **not** invoked —
no Asterisk/PJSIP implementation change was required (no new PJSIP
config generation, no dialplan change; `module reload http` is the same
mechanism TASK-0029A already established and this task re-verifies, not
replaces). `senma-product-designer` was **not** invoked — no user-facing
certificate workflow changed; the admin UI's transport edit form is
unchanged.

## ORIGINAL CH-2

Exact wording from `docs/tasks/0034-release-readiness-production-pilot-gate.md`
(FINDINGS section, preserved verbatim there per this project's
documentation policy):

> **CH-2 — `wss` transport ships enabled on a dev-fixture certificate;
> `doctor`'s cert check doesn't validate what's actually configured.**
> `snep/install/database/system_data.sql` seeds the `wss` PJSIP transport
> `enabled=true`, pointed at `/etc/asterisk/keys/wss-test-cert.pem`/
> `wss-test-key.pem` — a self-signed certificate
> `docker/asterisk-entrypoint.sh` generates at container first boot. This
> is deliberate (TASK-0029A) so `make dev` works out of the box. But
> `scripts/doctor.sh`'s certificate check is hardcoded to that same
> literal dev-fixture path — it never reads the `wss` transport's actual
> configured `cert_file`/`priv_key_file` from the database — so there is
> currently **no automated way to detect** whether a pilot has actually
> replaced the fixture certificate before going live. Mitigated in the
> runbook (explicit manual step + explicit manual check), but the
> underlying automated gap remains. Recommend a small follow-up: have
> `doctor` read the live `pjsip_transports.cert_file` value and flag it
> if it still matches the known fixture path.

## CURRENT CERTIFICATE FLOW (Phase 2 inventory)

Traced end to end, live, before any change:

- **DB/config model**: `pjsip_transports` (schema from TASK-0018/0029A)
  carries `cert_file`, `priv_key_file`, `ca_list_file`, `verify_client`,
  `verify_server`, `method` — path/metadata references only, never
  certificate bytes. Exactly one `wss`/`ws` row may be `enabled=1` at a
  time (0029A's own save-time invariant — Asterisk's built-in HTTP
  server has exactly one TLS listener).
- **Generated `senma-http-tls.conf`**: `Snep_PjsipTransportConf::
  loadConfFromDb()` rewrites this file in full on every transport
  create/edit/delete, sourcing `tlscertfile`/`tlsprivatekey` directly
  from that one enabled row, and unconditionally runs `module reload
  http` at the end of the same call. Confirmed live (`docker compose exec
  asterisk cat /etc/asterisk/snep/senma-http-tls.conf`).
- **`http.conf` includes**: `docker/asterisk-config/http.conf` (static,
  FIRST_BOOT_SEED) sets `[general]`/loopback-plain-listener lines and
  `#include`s the generated file above. Unchanged by this task.
- **Docker volume/path mapping**: `/etc/asterisk/keys/` lives in the
  persistent `asterisk-etc` named volume, mounted read-write into both
  `asterisk` and `app`. Unchanged by this task.
- **Fixture certificate generation/bootstrap**: `docker/
  asterisk-entrypoint.sh` generates `wss-test-cert.pem`/`wss-test-key.pem`
  (self-signed, `CN=senma-wss-test`, SAN `DNS:asterisk, DNS:localhost`,
  10-year validity) exactly once, at first boot, guarded independently of
  the main `asterisk.conf` first-boot check. Unchanged by this task.
- **Compose/pilot overlay**: `compose.pilot.yaml` publishes `8089:8089/tcp`
  — the pilot-reachable WSS port this task's live proofs target.
  Unchanged by this task.

Live evidence gathered before any change (fresh `make dev` state):

```
$ SELECT cert_file, priv_key_file, ca_list_file FROM pjsip_transports WHERE name='wss';
/etc/asterisk/keys/wss-test-cert.pem  /etc/asterisk/keys/wss-test-key.pem  NULL

$ openssl x509 -in wss-test-cert.pem -noout -subject -issuer -dates -fingerprint -sha256 -ext subjectAltName
subject=CN=senma-wss-test
issuer=CN=senma-wss-test
notBefore=Sep  7 15:11:51 2026 GMT
notAfter=Sep  4 15:11:51 2036 GMT
sha256 Fingerprint=A8:87:49:CC:...:F7:D6
X509v3 Subject Alternative Name:
    DNS:asterisk, DNS:localhost

$ (from the app container) openssl s_client -connect asterisk:8089 -servername asterisk
depth=0 CN=senma-wss-test
Verify return code: 18 (self-signed certificate)
sha256 Fingerprint=A8:87:49:CC:...:F7:D6   <- byte-identical to the configured file
```

Configured fingerprint and live runtime fingerprint already matched in
this dev environment (no drift existed) — but **nothing in the product
proved that**, which is exactly CH-2's own point: a correct-looking
`cert_file` value is not evidence the live listener presents it.

## FIXTURE CERTIFICATE BEHAVIOR (Phase 3)

Classification: **DEVELOPMENT_ONLY / DEFAULT_ONLY, never
PRODUCTION_SUPPORTED.**

- A fresh `make dev` install DOES get the fixture certificate
  automatically — confirmed by construction (`docker/
  asterisk-entrypoint.sh`'s first-boot generation + `system_data.sql`'s
  seed row referencing it, `enabled=true`).
- Nothing in the product blocks Asterisk from starting or serving real
  WSS traffic on this certificate — by design (TASK-0028Z/0029A: a
  zero-config working default for `make dev`).
- Before this task, nothing distinguished "the dev fixture is still
  live" from "a real certificate is live" at the release-gate level. This
  task's fixture identification (below) is exactly that missing
  distinction.

## PRODUCTION CERTIFICATE TRUST CONTRACT (Phase 6/17 — DECISION)

Reaffirms, does not change, TASK-0029A's ownership model: certificate/key
files are externally provisioned by an operator at
`/etc/asterisk/keys/`; SENMA stores/references **paths**, never bytes;
SENMA does not become a CA or certificate issuer; no ACME/Let's Encrypt
automation is added (explicitly out of scope, per this task's own
boundary and per TASK-0029A's REMAINING DEBT).

Pilot acceptance for WSS (`--pilot` / `PILOT=1`) requires **all** of:

1. certificate and private key files exist and are readable by Asterisk;
2. certificate parses as valid X.509;
3. certificate/key **pair matches** (public-key hash comparison only —
   see PAIR VALIDATION);
4. certificate is **currently valid** (not expired, not not-yet-valid);
5. `WSS_PUBLIC_HOSTNAME` is **configured** and the certificate's SAN (or
   CN, only if no SAN extension exists at all) **covers** it;
6. the **live runtime** presents exactly this certificate (fingerprint
   match — see RUNTIME FINGERPRINT VALIDATION);
7. the certificate is **not** the known dev fixture (see FIXTURE
   CLASSIFICATION);
8. the private key's file mode is not broader than `600`/`400`.

Any single failure is reported by name (never collapsed into a generic
`NOT_ACCEPTABLE_FOR_PILOT` with no reason) and blocks the gate.

**Public CA vs. private/enterprise CA**: both are explicitly supported.
`pjsip_transports.ca_list_file` (an existing TASK-0029A column, previously
used only for `verify_client`/`verify_server` mTLS) is reused, without
schema change, as the trust anchor `make cert-check` verifies the
server's own certificate against when set; when unset, the check falls
back to the container's system CA trust store (covers a public-CA-issued
certificate). This satisfies "support a private enterprise CA explicitly,
do not hardcode public-CA-only" without inventing a second field.

## HOSTNAME CONTRACT (Phase 7)

No `PUBLIC_HOSTNAME`/`WSS_HOSTNAME`-shaped setting existed anywhere in
this repository before this task (confirmed: grepped `.env.example`,
`compose.yaml`, `compose.pilot.yaml`, the PJSIP transport schema's
`domain`/`external_signaling_address` columns — the latter two are
NAT-facing PJSIP signaling-address concepts unrelated to what a browser/
WSS client verifies a certificate's SAN against, and are never populated
for the seeded `wss` row).

**Decision**: a new `.env` setting, `WSS_PUBLIC_HOSTNAME` (empty by
default), is the smallest appropriate addition — the smallest possible
surface (one optional environment variable, matching this project's
existing `.env`-as-deployment-configuration convention) rather than a new
database column or admin-UI field. Precedence in `scripts/lib/
wss-cert-lib.sh`'s `wcl_public_hostname()`: an explicit test-only
override (used by isolated negative-test fixtures) > `WSS_PUBLIC_HOSTNAME`
> the wss transport's own `external_signaling_address` > its own `domain`
column (both already-existing, currently-unpopulated fallbacks, kept for
completeness, not the primary path) > empty ("not configured", never
silently treated as a pass).

## SAN/HOSTNAME VALIDATION (Phase 9)

SAN is checked first; CN is used **only** as a fallback when the
certificate carries no SAN extension at all (`wss-cert-check.sh`'s
`HOSTNAME_MATCH` logic) — matching modern TLS client behavior (RFC 6125),
which ignores CN entirely once a SAN extension is present. Both DNS and
IP SAN forms are recognized (`DNS:host`, `IP Address:host`/`IP:host`).

Proven live:
- hostname present in SAN → `HOSTNAME_MATCH: yes`;
- hostname absent from SAN (and no CN fallback match) →
  `HOSTNAME_MATCH: no` → overall `TRUST_STATE: HOSTNAME_MISMATCH` →
  `PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT`.

## PAIR VALIDATION (Phase 8)

`wcl_cert_pubkey_hash`/`wcl_key_pubkey_hash` (`scripts/lib/
wss-cert-lib.sh`) derive the **public**-key SHA-256 hash from the
certificate (`openssl x509 ... -pubkey | openssl pkey -pubin`) and from
the private key (`openssl pkey ... -pubout`) — the private key's own
bytes are never read into a shell variable or printed; only its
derived public-key hash is. Equal hashes → `PAIR_MATCH: yes`; different
→ `PAIR_MATCH: no` → `TRUST_STATE: PAIR_MISMATCH`. A read/parse failure
on either file is distinguished from a real mismatch by checking the
underlying command's exit status explicitly (`set -o pipefail` inside
the remote command) — a naive "is the output non-empty" check would
otherwise mistake `sha256("")`'s fixed hash for a real one on failure;
this was caught and fixed during this task's own validation (see
VALIDATION FINDINGS below).

Proven live (Phase 20's required negative test): certificate A + private
key B (individually valid, wrong pairing) → `PAIR_MATCH: no` →
`TRUST_STATE: PAIR_MISMATCH` → `NOT_ACCEPTABLE_FOR_PILOT`, with the
tool's own output grepped for `BEGIN.*PRIVATE KEY` and confirmed absent.

## EXPIRY VALIDATION (Phase 10)

Three distinguished states, never collapsed: `NOT_YET_VALID` (now <
notBefore, compared via the container's own current time — `openssl
-checkend` has no notBefore equivalent), `EXPIRED` (`openssl x509
-checkend 0`), and `EXPIRING_SOON` (valid now, but `-checkend <N days>`
fails — default 30 days, matching the pre-existing `doctor.sh`
threshold, overridable via `--warn-days`). `EXPIRING_SOON` is a qualifier
on an otherwise-good state (`TRUST_STATE: TRUSTED (EXPIRING_SOON)`), not
a separate top-level trust state, and blocks pilot acceptance in
`--pilot` mode only as informational (not one of the 8 gate reasons
above — it is surfaced but not itself a `NOT_ACCEPTABLE_FOR_PILOT`
reason, since a still-valid-but-soon-expiring certificate is a WARN-class
watch item, not a broken one; TASK-0034 Phase 39/§39 already established
"certificate expiry" as a manual pilot watch item — unchanged here).

Proven live via backdated (never system-clock-touching) fixture
certificates: `openssl req -x509 ... -not_before 20200101000000Z
-not_after 20200201000000Z` → `EXPIRED`; `-not_before 20991231000000Z
-not_after 21001231000000Z` → `NOT_YET_VALID`.

## CHAIN VALIDATION (Phase 14)

`wcl_runtime_peek` connects with `-showcerts` and counts every
`-----BEGIN CERTIFICATE-----` block the server actually sends, reporting
it as `CHAIN_DEPTH`. Proven live: a real ephemeral test CA (see WSS
TRUSTED-CLIENT PROOF below) issues a leaf certificate; `cert_file` is set
to the **fullchain** (leaf + CA certificate concatenated, the format
Asterisk's `tlscertfile` expects for an intermediate-bearing certificate
— Asterisk serves exactly the bytes at that path, verbatim, with no
separate chain-file directive); the live listener was confirmed to serve
both certificates (`CHAIN_DEPTH: 2`). This proves a normal client can
validate the served chain without needing to fetch a missing intermediate
out-of-band, satisfying Phase 14's requirement.

## FIXTURE CLASSIFICATION (Phase 16)

Two independent signals, either sufficient (deliberately **not** "any
self-signed certificate is a fixture" — a private-CA-issued or an
admin-generated self-signed native-`tls`-transport certificate must never
be misclassified):

1. the configured path is exactly the known dev-fixture path
   (`/etc/asterisk/keys/wss-test-cert.pem`, the literal path
   `docker/asterisk-entrypoint.sh` generates into); **or**
2. the certificate's subject carries the fixture marker (`CN=
   senma-wss-test`, the fixed CN that entrypoint script's `openssl req`
   always uses).

`FIXTURE: yes/no` is reported as its own field, independent of
`TRUST_STATE` (a fixture certificate is also, correctly, classified
`SELF_SIGNED`) — `--pilot` mode treats `FIXTURE: yes` as its own,
separately-named `NOT_ACCEPTABLE_FOR_PILOT` reason, satisfying Phase
47's explicit requirement that fixture rejection be provable even though
the WSS protocol itself works.

## CONFIGURED FINGERPRINT / RUNTIME FINGERPRINT / MATCH PROOF (Phase 11 —
mandatory)

This is the core of what CH-2 actually required: a certificate path in
`http.conf`/the database is not proof of what a client actually receives.

`wcl_runtime_peek` performs a real TLS connection (`openssl s_client
-showcerts`, no `-CAfile`, no verification-disabling flag needed — this
is a metadata PEEK of a certificate any anonymous client can already see,
not a trust decision) and extracts the leaf certificate's own SHA-256
fingerprint, compared byte-for-byte against the fingerprint independently
computed from the configured file. Default target: `asterisk:<bind_port>`
reached from **inside the asterisk container itself** via its own Docker
Compose service DNS name (a real network round-trip, not `localhost`
loopback-only, and zero-config for `make dev`); `--connect host:port`
overrides this to hit a real externally-reachable pilot hostname/port
directly from wherever the operator runs the tool (the genuine
"prove the actual live pilot listener" path).

Live evidence, dev default: `CONFIGURED_FINGERPRINT_SHA256` and
`RUNTIME_FINGERPRINT_SHA256` were confirmed identical
(`A8:87:49:CC:...:F7:D6`), `RUNTIME_MATCH: MATCH`.

## RUNTIME_MISMATCH PROOF + RELOAD/RECOVERY BEHAVIOR (Phase 23/24/48)

Sequence proven live, twice (once standalone, once inside the full
regression suite): the live `wss` transport is rotated (through the real
HTTP edit-form flow) to a real ephemeral-test-CA-issued certificate at
path `P`; an operator then replaces the certificate **bytes at that same
path `P`** directly (simulating an out-of-band renewal that bypasses
SENMA entirely — no edit-form call, no `Snep_PjsipTransportConf` write,
no automatic reload) — this is the realistic production scenario Phase
23 describes, distinct from TASK-0029A's own rotation proof (which always
goes through the edit form and therefore always auto-reloads).

```
configured file (fresh read)  → new certificate, fingerprint F2
live runtime (fresh TLS peek) → still presents the OLD certificate, F1
→ RUNTIME_MATCH: RUNTIME_MISMATCH, TRUST_STATE: RUNTIME_MISMATCH

$ asterisk -rx "module reload http"
Module 'http' reloaded successfully.

configured file  → F2
live runtime     → F2
→ RUNTIME_MATCH: MATCH
```

**`module reload http` remains sufficient on the current Asterisk version
(22.11.0)** for this exact scenario — re-tested per Phase 24's own
instruction not to assume TASK-0029A's evidence still holds, and
confirmed it does. See VALIDATION FINDINGS below for a real, separate
methodological pitfall this task's own regression-suite development hit
and fixed while investigating an apparent (but ultimately non-existent)
slow-convergence symptom.

**Native SIP TLS distinction preserved (Phase 25)**: this entire section
is about the `wss`/`ws` transport's certificate, which lives in Asterisk's
global `http.conf`/HTTP-server TLS context. A native `tls` PJSIP
transport's own certificate lifecycle is unrelated (its cert/key are
emitted directly onto the PJSIP transport object) and is NOT reloadable
in place on an already-bound address:port (TASK-0029A's own Finding 4,
unchanged, untouched by this task) — a full Asterisk restart remains that
case's own documented recovery, not `module reload http`.

## WSS TRUSTED-CLIENT PROOF (Phase 12/13/42 — CH-2's actual closure bar)

`docker/wss-test-client/wss_sip_register.py` (TASK-0028Z) previously only
supported `ssl.CERT_NONE` (deliberately, for the self-signed dev fixture).
This task adds an additive, opt-in verified mode — `--ca-file` (+
`--verify-hostname`) — that sets `ssl.CERT_REQUIRED`, `check_hostname =
True`, and loads the given CA file; omitting `--ca-file` preserves the
exact original behavior byte-for-byte (zero change to the existing
`wss-platform-smoke` suite, confirmed by that suite's own unmodified
regression pass).

Live proof, real ephemeral test CA (generated fresh per run, 30-day
validity, never committed — see PILOT PROOF below): TLS handshake
completes with `ssl.CERT_REQUIRED` and hostname verification against the
real SAN, immediately followed by a full SIP REGISTER transaction
(401 challenge → digest response → 200 OK) over that same verified
connection, against a real SENMA-provisioned PJSIP extension:

```
TLS_VERIFY_MODE: CERT_REQUIRED (hostname=task0034e-pilot.test, ca_file=/ca/test-ca.pem)
TLS_OK TLSv1.3 ('TLS_AES_256_GCM_SHA384', 'TLSv1.3', 256)
HANDSHAKE_OK
--- sending REGISTER #1 (unauthenticated) ---
SIP RESPONSE: SIP/2.0 401 Unauthorized
--- sending REGISTER #2 (authenticated) ---
SIP RESPONSE: SIP/2.0 200 OK
REGISTER_OK
```

No `-k`/`--insecure`/`CERT_NONE` anywhere in this path — satisfying
CH-2's own closure bar ("a trusted client can connect without disabling
verification").

## DOCTOR/PREFLIGHT INTEGRATION (Phase 26-28)

`make cert-check` (alias `make wss-cert-check`) is the one supported
operator-facing command (`scripts/wss-cert-check.sh`) — read-only,
secret-safe (never prints key bytes/PEM bodies), runtime-aware. `PILOT=1`
evaluates pilot acceptance and exits nonzero on
`NOT_ACCEPTABLE_FOR_PILOT`.

`scripts/doctor.sh`'s `check_certificate` was rewritten to call this same
script (`SMOKE_COMPOSE="$COMPOSE" bash scripts/wss-cert-check.sh`) and map
its `TRUST_STATE`/`FIXTURE` output to doctor's own PASS/WARN/FAIL/UNKNOWN
vocabulary — no second certificate-parsing implementation. Mapping:
`TRUSTED` → PASS (WARN if `EXPIRING_SOON`); `SELF_SIGNED` → WARN
(distinct wording if it is the known fixture vs. an intentional
self-signed choice); `MISSING`/`RUNTIME_MISMATCH`/`RUNTIME_UNREACHABLE`/
`HOSTNAME_MISMATCH` → WARN (recoverable/config issues, not outages);
`UNREADABLE`/`PAIR_MISMATCH`/`EXPIRED`/`NOT_YET_VALID` → FAIL (genuine
defects); no enabled row / check could not run → UNKNOWN.

Live evidence (unmodified dev environment): `make doctor` now reports —

```
[WARN   ] TLS/WSS certificate: dev-fixture certificate in use -- must be
          replaced before pilot go-live (docs/operations/
          production-release-runbook.md step 4)
```

— where previously it silently reported nothing wrong regardless of
which certificate was actually live. `make doctor` still reports **0
FAIL** on this unmodified dev environment (a WARN, not a FAIL, matching
this task's own established severity for "correct default in dev, wrong
for pilot").

No `make preflight` target exists yet (TASK-0034 §7's own finding,
unchanged) — `make cert-check PILOT=1` is documented as a mandatory
manual Preflight step in `docs/operations/production-release-runbook.md`
(both the dedicated step 4 and the Preflight section's own command list).

## SECURITY PROOF (Phase 34/35/39)

- **No certificate bytes in DB/app**: reconfirmed — `pjsip_transports`
  carries paths/metadata only (unchanged schema); `wss-cert-check.sh`
  never echoes PEM body content, only parsed metadata fields.
- **No private key disclosure**: `wcl_key_pubkey_hash` derives a public-
  key hash via `openssl pkey ... -pubout` piped directly to `sha256sum` —
  the key's own bytes never populate a shell variable, are never echoed,
  and never appear in a log line. The new regression suite explicitly
  greps its own tool's output for `BEGIN.*PRIVATE KEY` and asserts it is
  absent, for both the real (trusted-CA) and adversarial
  (cert/key-mismatch) cases.
- **File permissions**: `KEY_MODE_SAFE` (600/400 only) is reported
  explicitly, contributing to `--pilot` rejection when broader — SENMA
  does not chmod certificate/key files it does not own (TASK-0029A's own
  established boundary, unchanged).
- **Full security regression suite** (13 suites: preauth/sql/residual-
  sql/shell/pjsip-config/api/api-sql/session-csrf/auth-hardening/
  disclosure-path/legacy-maintenance-exposure security,
  authorization-coverage, authorization-smoke) — all PASS, no
  certificate-related change touches any of their assertions (see
  CANONICAL VALIDATION below).

## PILOT PROOF (Phase 29-33/46)

A test-only local CA is generated fresh, on demand, entirely inside the
`asterisk` container (matching the existing convention every other
fixture certificate in this codebase already uses — e.g.
`tls-cert-management-smoke-test.sh`'s own `gen_cert()` — no new
generation pattern invented): a self-signed CA cert/key pair (30-day
validity, `basicConstraints=critical,CA:true`), then a leaf key + CSR,
signed by that CA into a leaf certificate for a real pilot-style hostname
(`task0034e-pilot.test`), concatenated with the CA certificate into a
fullchain. The CA's public certificate alone is exported (`docker cp`,
read-only) to a host-side ephemeral scratch directory purely so the
separate, throwaway `wss-test-client` container can bind-mount and trust
it — the CA's own private key never leaves the asterisk container and is
deleted, along with every other fixture file this task's own suite
creates, at test end (`harness_register_best_effort_cleanup`). Nothing
is committed to git (verified: `git ls-files | grep -E '\.(pem|key|crt)$'`
is empty, same assertion TASK-0029A's own suite already made).

Docker/pilot path proof (Phase 31): the live `wss` transport is rotated
to this trusted certificate through the real HTTP edit-form flow (the
same mechanism a real pilot admin uses), which persists in the same
`asterisk-etc` named volume every other certificate reference already
uses — no new volume/mount path.

Restart proof (Phase 32) and force-recreate proof (Phase 33) for a
customer-managed certificate were already established by TASK-0028Z/
0029A (byte-for-byte sha256 persistence across `docker compose restart
asterisk` and `docker compose up -d --force-recreate asterisk`) and are
architecturally unaffected by this task (no new file, no new volume, no
new persistence path was introduced) — not re-run destructively here per
this project's own "don't rerun unnecessarily; justify reuse" instruction.

## FOCUSED WSS CERTIFICATE TEST (Phase 40)

`scripts/wss-certificate-runtime-smoke-test.sh` (new), **20/20 PASS**, run
standalone twice consecutively (idempotency confirmed). Covers, each with
a distinct check:

1. the current live (dev-fixture) certificate is classified `FIXTURE:
   yes` and rejected by the pilot gate;
2. missing cert/key → `MISSING`;
3. mismatched cert/key pair → `PAIR_MISMATCH`, with an explicit
   assertion that no private-key PEM material appears in the tool's own
   output;
4. hostname mismatch → `HOSTNAME_MISMATCH`; matching hostname → accepted;
5. an already-expired (backdated, clock never touched) certificate →
   `EXPIRED`; a not-yet-valid one → `NOT_YET_VALID`;
6. a real ephemeral test-CA-issued certificate, rotated onto the live
   `wss` transport through the real edit form, classified `TRUSTED`/
   `PILOT_ACCEPTABLE`, serving a full 2-certificate chain, and proven via
   a real verified (non-`CERT_NONE`) SIP-over-WSS REGISTER;
7. an out-of-band same-path certificate byte-swap → `RUNTIME_MISMATCH`,
   and `module reload http` converging it to `MATCH`;
8. restoration of the original dev-fixture certificate, confirmed live;
9. no certificate/key material committed to git.

## VALIDATION FINDINGS (methodological, worth recording)

While developing check #7 above, this task's own draft harness function
(`converged_to_match`) initially piped `check | grep -q
'^RUNTIME_MATCH: MATCH'` directly, under this script's own `set -o
pipefail`. Every manual, isolated, step-by-step reproduction of the exact
same rotate → real-client-REGISTER → byte-swap → reload sequence
converged instantly and correctly (confirmed 4 separate times, including
one with the real verified SIP-over-WSS client REGISTER in the sequence),
yet the automated suite consistently, deterministically failed at that
one step. Root cause, found via targeted tracing rather than assumption:
`grep -q` exits the instant it finds its match, closing its end of the
pipe while `check`'s own underlying process (`bash wss-cert-check.sh`,
which still had two more lines to print — `TRUST_STATE`/
`PILOT_ACCEPTANCE`) was still writing — a real SIGPIPE (exit 141) that
`pipefail` surfaces as the pipeline's own failure, which `harness_retry`
then (correctly, given that signal) treated as "not converged," on every
single attempt, regardless of the actual — already-correct — certificate
state. This is a **harness-authoring bug**, classified
`WRONG_TEST_ASSUMPTION`/`HARNESS_BUG` per this project's own test
philosophy, not a product defect, not an Asterisk timing race, and not
flakiness: fixed by capturing `check`'s full output into a variable
*first*, then matching against the captured string (no live pipe, no
possible SIGPIPE). Documented here because the same pattern (`slow
multi-line producer | grep -q` under `pipefail`) is a general hazard any
future suite in this codebase could reproduce.

While building `wcl_cert_pubkey_hash`/`wcl_key_pubkey_hash`, an initial
draft did not distinguish "the underlying `openssl` command failed" from
"it succeeded with genuinely empty output" — both can produce
`sha256("")`'s fixed hash text on stdout even though only the first case
means the hash is meaningless. Fixed before this was ever a live defect
(caught during a `--cert /nonexistent` test, which needed to distinguish
`MISSING` from a false pair-match) by having callers check the
function's own exit code (with `set -o pipefail` in the remote command),
never string emptiness alone.

## SECURITY REGRESSION (Phase 39)

All 13 security suites re-run as part of the full `make regression`
below — all PASS, no regression attributable to this task's changes.

## LINT / REGRESSION / DOCTOR / GATES

See CANONICAL VALIDATION in the shared checkpoint (final report). Summary:
`make lint` PASS; two consecutive full `make regression` runs, 41/41
PASS each; `make doctor` 0 FAIL (1 WARN, the expected dev-fixture
notice); `make secrets-check` MATCH; `make migrate-check` SCHEMA_CURRENT;
`make reconcile-check` IN_SYNC; `git diff --check` PASS.

## CHANGES

**PRODUCTION**: none (no PHP/application code changed — this task is
entirely tooling/diagnostics/test-client-extension/documentation).

**PLATFORM/TOOLING**:
- `scripts/lib/wss-cert-lib.sh` (new) — shared certificate inspection/
  classification library.
- `scripts/wss-cert-check.sh` (new) — `make cert-check`/`make
  wss-cert-check`.
- `scripts/doctor.sh` — `check_certificate` rewritten to reuse the above
  instead of a hardcoded fixture-path check.
- `docker/wss-test-client/wss_sip_register.py` — additive `--ca-file`/
  `--verify-hostname` verified-TLS mode (default behavior unchanged).
- `Makefile` — `cert-check`/`wss-cert-check`/`wss-certificate-runtime-smoke`
  targets + `.PHONY`.
- `scripts/regression.sh` — new suite wired in (40 → 41).
- `.env.example` — new `WSS_PUBLIC_HOSTNAME` setting.

**TEST**:
- `scripts/wss-certificate-runtime-smoke-test.sh` (new).

**DOCUMENTATION**:
- `docs/tasks/0034-release-readiness-production-pilot-gate.md` (UPDATE
  section, CH-2 closure).
- `docs/operations/production-release-runbook.md` (step 4 rewritten;
  Preflight section extended).
- This file.

## REMAINING DEBT

- **Native `tls` transport certificate rotation on an already-bound
  address:port** remains deterministic-but-not-hot (full Asterisk
  restart required) — unchanged, pre-existing TASK-0029A debt, explicitly
  out of this task's scope (WSS/`http.conf` certificate lifecycle only,
  per this task's own boundary — see Phase 25).
- **No `make preflight` orchestration target** — `make cert-check PILOT=1`
  is documented as a manual mandatory step in the runbook's existing
  Preflight command list, matching TASK-0034 §7's own already-accepted
  precedent (`release-info` was integrated the same way).
- **No automated certificate-expiry alerting/monitoring** — `EXPIRING_SOON`
  is surfaced by `make doctor`/`make cert-check` on-demand; TASK-0034
  §39's own "manual watch item" policy is unchanged and sufficient for
  this pilot's scope (no monitoring platform is built here, per every
  prior task's same instruction).
- **`wcl_runtime_peek`'s default connect target is the Docker-internal
  service DNS name (`asterisk:<port>`)**, not the pilot's real public
  hostname/port — sufficient to prove the mechanism and to catch
  RUNTIME_MISMATCH/fixture/expiry issues in any environment (dev or
  pilot), but a pilot operator wanting to prove the *externally*-reachable
  endpoint specifically must pass `--connect <public-host>:8089` (already
  supported, documented in the tool's own `--help`) rather than relying
  on the zero-config default. Not a gap in capability, just an operator
  action worth calling out explicitly here.
- **`WSS_PUBLIC_HOSTNAME` is optional in `.env`** — a pilot that never
  sets it gets `NOT_ACCEPTABLE_FOR_PILOT` (correct, fail-closed) rather
  than a friendlier "you forgot to set this" first-boot nudge; acceptable
  given this is a one-line, well-documented `.env.example` entry, not a
  hidden requirement.

## RECOMMENDATION

`APPROVE`.

## PROPOSED COMMIT

A single coherent commit — the library, the operator tool, the doctor
integration, the test-client extension, the new regression suite, and
the documentation are one indivisible feature (the check has no meaning
without the tool that computes it, and vice versa):

```
feat(wss): add production WSS certificate trust and runtime verification

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01FP7YzWTLhPbMEVgpGAsNdv
```

The runbook/TASK-0034 documentation updates could be split into their own
`docs:` commit if preferred, but since they exist to document exactly
this feature's own new contract, bundling them with the feature commit is
the more coherent, reviewable unit (matching TASK-0029A's own precedent).
