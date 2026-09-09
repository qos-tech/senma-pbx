# TASK-0034H — Pilot Host WSS Certificate Provisioning & Final Go Gate

## LEAD

`senma-docker-platform-engineer`

## REVIEWERS

`senma-telephony-architect`, `senma-application-architect` — consulted via
their domain lenses for the WSS/PJSIP-transport and release-identity/
secrets portions respectively; no separate agent sessions were spawned
(single-session live investigation, matching TASK-0034G's own precedent).
`senma-asterisk-pjsip-engineer` was **not** invoked — every observed
Asterisk/PJSIP runtime behavior (certificate reload, `RUNTIME_MATCH`,
`PAIR_MATCH`, AMI ACL restart-preservation) matched the contract TASK-0034E
already proved, with no deviation requiring implementation-level Asterisk
work. `senma-product-designer` was **not** invoked, per this task's own
explicit instruction — no user-facing workflow changed.

Orchestrated by `senma-workflow-orchestrator`.

## PURPOSE

Close TASK-0034's one remaining `OPEN_CONSTRAINT` (TASK-0034G): provision
the actual pilot host with a real, trusted WSS certificate for its real
public hostname, prove the full runtime/trust chain live, and return a
final `TASK-0034` go/no-go decision. Per this task's own framing, the
implementation mechanism (TASK-0034E) is not in question — this is meant
to be an operational certification against a real pilot environment.

## SCOPE

**IN SCOPE** (as specified): real pilot hostname/DNS validation, trusted
WSS certificate provisioning, certificate/key/path configuration, runtime
reload, live runtime certificate verification, verified WSS REGISTER,
final pilot release gates, TASK-0034 closure, documentation.

**OUT OF SCOPE** (as specified, and not attempted): ACME/Let's Encrypt
automation, DNS automation, certificate-issuance product feature, native
SIP TLS redesign, AMI redesign, release-artifact redesign, application
changes, new telephony features, monitoring platform.

**Expected product code changes: NONE. None were made.**

## STOP CONDITION HIT — USER CONFIRMATION

Before Phase 1 execution, this session verified (see FINDINGS below) that:

- no real pilot host exists separately from this development machine's
  Docker Desktop stack — every "pilot" deployment through TASK-0034B–G
  has been this same local stack with `compose.pilot.yaml`'s port
  publishing layered on;
- no real public DNS hostname for a pilot is recorded anywhere in this
  repository (`.env.example`'s `WSS_PUBLIC_HOSTNAME` is documented as
  "leave empty for local development", populated only by an operator at
  actual pilot time);
- this session has no access to a public CA or an enterprise/private CA
  the organization has decided to trust, and no such access is claimed
  anywhere in the repository;
- the runbook (`docs/operations/production-release-runbook.md`, WSS
  certificate step) itself documents real-certificate provisioning as an
  **operator action outside the codebase**, not something the codebase or
  an automated session performs.

This exactly matches this task's own documented stop condition
("trusted certificate cannot be provisioned") and its own **Critical
rule** ("Do not weaken the TASK-0034E certificate gate to make the
environment pass"). Rather than assume, invent a hostname, or generate a
throwaway CA and present it as a "real" pilot certificate, this session
asked the user directly (`AskUserQuestion`) whether real pilot
infrastructure (hostname + DNS + a real public/enterprise CA-issued
certificate) already exists and should be used.

**User's answer (verbatim intent, recorded here as the authorizing
decision for this task's outcome):** no real pilot infrastructure exists
yet; do not create or simulate a production CA/certificate to satisfy this
task; return `TASK-0034H = BLOCK` and `TASK-0034 = PILOT_GO_WITH_CONSTRAINTS`,
with the remaining operational constraint stated plainly (provision real
hostname/DNS, provision a trusted certificate, run `make cert-check
PILOT=1`, prove verified WSS REGISTER, then close `TASK-0034` as
`PILOT_GO`); no product code changes; no automatic commit.

This decision governs the rest of this document. Phases 3–21 (real
hostname determination, DNS proof, real certificate sourcing/ownership/
SAN/validity/chain/pair proofs, hostname configuration, reload, runtime
fingerprint MATCH against a *real* certificate, trusted-client TLS proof
against a *real* CA, verified WSS REGISTER against a *real* certificate)
**were not executed**, because their required input — a real pilot
hostname and a real trusted certificate — does not exist in this
environment and this session was explicitly instructed not to fabricate
one.

## FINDINGS

Evidence gathered live in this session, current dev stack (this same
machine — the only "pilot-class" environment available), no product code
touched:

**Starting state (Phase 1)**
```
$ git status --short
(clean)
$ git log -1 --oneline
cdefd57 docs(release): certify RC v0.1.0-rc.1 build and deployment chain
$ git branch --show-current
main
```
`cdefd57` sits directly on top of `3d3e1c4` — the exact commit TASK-0034G
certified — and is itself documentation-only (per its own message and
confirmed by `git diff --check`/`git status` remaining clean throughout
this session). **No product/platform drift since TASK-0034G.**

**Release identity (Phase 2)**
```
$ make release-info
app        DRIFT    senma-app:dev        expected senma-app:v0.1.0-rc.1 ...
asterisk   DRIFT    senma-asterisk:dev   expected senma-asterisk:v0.1.0-rc.1 ...
db         THIRD_PARTY mariadb:10.11     not a SENMA release artifact
RESULT: DRIFT detected.
```
Expected: the stack is currently running in plain dev mode
(`senma-app:dev`/`senma-asterisk:dev`), not redeployed via `make
pilot-up` against the `v0.1.0-rc.1` artifact — a stale
`release-manifest.json` from TASK-0034G's own certification run is still
present (gitignored, `git status` unaffected). This is TASK-0034G's own
already-documented **F1** finding ("operator hygiene, not a defect"), not
a new regression. Redeploying the pilot artifact was not performed in
this session — with no real hostname/certificate to install, doing so
would not change this task's outcome and would only repeat proofs
TASK-0034G already ran fresh, same-day, on the same commit lineage.

**Actual pilot hostname (Phase 3) / DNS proof (Phase 4)**

No real public hostname exists to record. `WSS_PUBLIC_HOSTNAME` is unset
in `.env` (confirmed: `HOSTNAME: (not configured)` in the `cert-check`
output below). No DNS to prove.

**Certificate source (Phase 5) / ownership (Phase 6)**

No real certificate source (`PUBLIC_CA`/`ENTERPRISE_CA`/`OTHER_TRUSTED_CA`)
was available to this session. The only certificate present is the
known TASK-0029A/0034E dev fixture:

```
CERT_PATH: /etc/asterisk/keys/wss-test-cert.pem
KEY_PATH:  /etc/asterisk/keys/wss-test-key.pem
CA_LIST_FILE: (none configured)
KEY_MODE: 600 (KEY_MODE_SAFE: yes)
SUBJECT: CN=senma-wss-test
ISSUER:  CN=senma-wss-test
```
Ownership/path model unchanged from TASK-0029A/0034E: certificate/key
referenced by path only, never stored as bytes in the database, living in
the persistent `asterisk-etc` named volume.

**SAN / validity / chain / pair proofs (Phases 7–10) and configured/
runtime fingerprint (Phases 14–17), re-run fresh in this session:**

```
$ make cert-check PILOT=1
SAN: DNS:asterisk,DNS:localhost
NOT_BEFORE: Sep  7 15:11:51 2026 GMT
NOT_AFTER:  Sep  4 15:11:51 2036 GMT
CONFIGURED_FINGERPRINT_SHA256: A8:87:49:CC:...:F7:D6
PAIR_MATCH: yes
VALIDITY: valid
HOSTNAME_MATCH: SKIPPED (no hostname configured)
FIXTURE: yes (known dev-fixture path)
SELF_SIGNED: yes
CA_VERIFIED: no
RUNTIME_ENDPOINT: asterisk:8089 (SNI=asterisk)
RUNTIME_FINGERPRINT_SHA256: A8:87:49:CC:...:F7:D6   <- identical to configured
CHAIN_DEPTH: 1
RUNTIME_MATCH: MATCH
TRUST_STATE: SELF_SIGNED
PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT (no public WSS hostname configured (set WSS_PUBLIC_HOSTNAME); known fixture/test-only certificate)
```

Byte-for-byte identical result to TASK-0034G's own same-day reading
(same reasons, same fingerprint) — **the mechanism itself is stable and
un-regressed**; the gate is working exactly as designed, correctly
refusing pilot acceptance for a fixture certificate with no configured
hostname. Re-confirmed a second time (`cert-check PILOT=1` run again)
after `ami-acl-smoke`'s own Asterisk-restart step (below), to make sure
that restart didn't disturb WSS state — identical result both times.

**Pilot topology / reload / trusted-client / SIP REGISTER against a real
certificate (Phases 12, 13, 15–21):** not executed. There is no real
certificate to reload into place, no real hostname for a trusted client
to verify against, and generating a throwaway CA here to stand in for a
"real" one was explicitly declined by the user for this task and would
misrepresent the pilot-readiness state this document exists to record
honestly.

**Operational gates re-run fresh in this session (Phases 24–28):**
```
make ami-acl-smoke FIXTURE_PROFILE=test   -> PASS 9/9 (identical checks to TASK-0034G)
make secrets-check                         -> OVERALL: MATCH
make migrate-check                         -> SCHEMA_CURRENT
make reconcile-check                       -> IN_SYNC (all 4 generated config files)
make doctor                                -> 1 FAIL, 1 WARN:
    [FAIL] Release artifact identity: DRIFT -- expected, TASK-0034G's own
           documented F1 (stale release-manifest.json + dev-mode stack;
           not a new regression, not a WSS-certificate issue)
    [WARN] TLS/WSS certificate: dev-fixture certificate in use -- expected,
           the exact, already-known, already-documented gap this task exists to close
```

**Reused from TASK-0034G, not re-run in this session (justified reuse —
same commit lineage, same day, unrelated to the certificate gap, per this
project's own "don't rerun unnecessarily; justify reuse" precedent
TASK-0034E itself established):** two consecutive full `make regression`
runs (42/42 PASS each), `release-artifact-smoke` (12/12 PASS), restart
proof, force-recreate proof (`--force-recreate --no-build`, byte-identical
running image IDs), pilot port-exposure table (5060/udp+tcp, 8089/tcp,
RTP 10000-10199/udp published; 5038/3306 not published), provider-absence
proof. None of these are affected by, or would change with, the WSS
certificate state — they exercise release/deployment/AMI mechanics
unrelated to Phase 3–21's real-hostname/real-CA requirement.

**No private-key disclosure (Phase 33):** confirmed across all output
captured in this session — `cert-check`, `doctor`, `ami-acl-smoke`,
`secrets-check` — none print PEM bodies or private-key bytes (grepped for
`BEGIN.*PRIVATE KEY`/`BEGIN.*CERTIFICATE`, absent from tool output; only
metadata fields are ever printed, matching TASK-0034E's own established
contract).

**Git gates (Phase 40):**
```
$ git diff --check   -> clean (exit 0)
$ git status --short -> (clean)
```
Confirmed both before and after every command run in this session — the
only file this session's commands touch outside the repository's tracked
tree is the gitignored `release-manifest.json`, and even that was not
regenerated (no `release-build`/`pilot-up` was run).

## DECISION

**TASK-0034H did not close the remaining constraint.** The gap TASK-0034G
identified is exactly what it was documented as: an environment-
provisioning item requiring a real pilot host, real DNS, and a real
trusted certificate, none of which are available to this session and none
of which this session is authorized (by the task's own Critical rule, and
now explicitly by the user) to simulate or fabricate. TASK-0034E's
certificate-trust mechanism itself remains proven, stable, and
un-regressed — re-confirmed fresh above, byte-for-byte consistent with
TASK-0034G's own same-day reading. Nothing here reopens CH-2.

`TASK-0034` stays exactly where TASK-0034G left it: `PILOT_GO_WITH_CONSTRAINTS`,
carrying the same single `OPEN_CONSTRAINT` (real pilot WSS certificate
provisioning), now reconfirmed live rather than assumed stale. It is
**not** promoted to `TASK-0034 = COMPLETE` / plain `PILOT_GO` — that
requires the actual provisioning chain (Phases 3–21) to run against real
infrastructure this session does not have.

## CHANGES

**PRODUCTION**: none.

**PLATFORM/TOOLING**: none.

**TEST**: none.

**DOCUMENTATION**:
- This file.
- `docs/tasks/0034-release-readiness-production-pilot-gate.md` — new
  `UPDATE (TASK-0034H)` section (history preserved, nothing rewritten).

No `runbook` change — the runbook already documents real-certificate
provisioning as an operator action outside the codebase; this session did
not discover any missing factual operational step to add.

## VALIDATION

`make release-info`: DRIFT (expected, dev-mode stack, F1). `make
cert-check PILOT=1`: `NOT_ACCEPTABLE_FOR_PILOT`, byte-identical to
TASK-0034G's reading, run twice (stable across an AMI-triggered Asterisk
restart). `make doctor`: 1 FAIL (expected F1 DRIFT), 1 WARN (expected
dev-fixture notice), both already-documented, non-new. `make
secrets-check`: MATCH. `make migrate-check`: SCHEMA_CURRENT. `make
reconcile-check`: IN_SYNC. `make ami-acl-smoke FIXTURE_PROFILE=test`:
PASS 9/9. `git diff --check`: clean. `git status --short`: clean
throughout. Full regression / release-artifact-smoke / restart /
force-recreate proofs reused from TASK-0034G (same commit lineage, same
day) rather than re-run, per justified-reuse precedent — none bear on the
WSS-certificate gap this task investigated.

## REMAINING DEBT

- **The one `OPEN_CONSTRAINT` carried forward unchanged from TASK-0034G**:
  provision a real pilot hostname/DNS, a real trusted (public or
  enterprise) CA-issued certificate for it, and obtain `make cert-check
  PILOT=1` → `PILOT_ACCEPTABLE` plus a verified (non-`CERT_NONE`) WSS SIP
  REGISTER, on the actual pilot host. This is squarely an operator/
  infrastructure task, not a code task — no script, gate, or product
  behavior needs to change.
- F1/F2/F3 from TASK-0034G (`release-manifest.json` operator-hygiene
  DRIFT note, `ami-acl-smoke`'s missing `FIXTURE_PROFILE=test` Makefile
  wiring, `readiness-smoke-test.sh`'s standalone timing race) — unchanged,
  reconfirmed still present (F1 observed directly again this session),
  still `FOLLOW_UP_DEBT`, still unrelated to the certificate gap.
- Pre-existing, unaffected: CH-7's RTP capacity note, CH-8 (stale
  README), base-image digest pinning (still tag-only), non-atomic
  trunk-name collision, no cert-expiry UI warning — all unchanged,
  `PILOT_CONSTRAINT`/`POST_PILOT` as already carried in the main
  TASK-0034 document.

## RECOMMENDATION

**TASK-0034H = `BLOCK`** (per this task's own stop conditions: trusted
certificate cannot be provisioned in this environment — user-confirmed,
not assumed).

**TASK-0034 = `PILOT_GO_WITH_CONSTRAINTS`** (unchanged from TASK-0034G —
the one `OPEN_CONSTRAINT` is reconfirmed live, not newly discovered or
worsened; `TASK-0034` does **not** close as `COMPLETE` from this task).

Recommend the next task remains **TASK-0035 — Pilot Deployment & Soak
Validation**, carrying the real WSS certificate provisioning and `make
cert-check PILOT=1` PASS as its explicit early prerequisite (unchanged
from TASK-0034G's own recommendation) — to be picked up once a real pilot
host, DNS, and certificate actually exist.

## PROPOSED COMMIT

Documentation-only. Not created automatically per this project's commit
policy and this task's own explicit instruction. If authorized:

```
docs(release): record TASK-0034H pilot WSS certificate BLOCK, reconfirm PILOT_GO_WITH_CONSTRAINTS

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01APVko5xxm3Vbq8o7UJYK4X
```

Scope: this file plus the `UPDATE (TASK-0034H)` section in
`docs/tasks/0034-release-readiness-production-pilot-gate.md`. No other
files changed by this task.
