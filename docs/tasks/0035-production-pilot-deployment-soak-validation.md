# TASK-0035 — Production Pilot Deployment & Soak Validation

## Status

**CLOSED — operational validation / closure review.**

**Final decision: `PILOT_DEPLOYMENT_BLOCKED`**

This task attempted a real production-pilot deployment using the 0034-series
release/pilot contract. The shared Cursor cloud agent host is **not** an
authorized real pilot host with public DNS and a trusted WSS certificate.
That gap is a concrete pilot blocker under the 0034R acceptance contract
(fixture/self-signed WSS is not acceptable for pilot PASS).

No closed 0034 architectural decision was reopened. No product redesign
was performed.

---



## TASK-0035A amendment (WSS TLS termination)

**SUPERSEDED BY TASK-0035A** for the WSS/certificate ownership assumption only:

- Old assumption: Asterisk `:8089` must present the trusted public WSS certificate.
- New supported model: public WSS TLS terminates at the SENMA reverse proxy
  (Apache in `app`); Asterisk receives private `ws://asterisk:8088/ws`.
- See `docs/tasks/0035a-reverse-proxy-wss-tls-termination-pilot-realignment.md`.

Unrelated TASK-0035 evidence (release/provenance/topology/migrate/secrets/
reconcile/doctor-non-WSS/backup/restart/lint/regressions) remains **STILL_VALID**.
The operational need for a non-fixture public certificate + DNS hostname remains,
but that certificate now belongs on the reverse proxy, not on Asterisk HTTP TLS.

## Starting state

```text
branch: cursor/cloud-agent-1789228026971-noiwv
HEAD:   51d4c7ab5f3c2ab488a0934bc7e00d71519befd8
        (docs: close TASK-0034R final release readiness review)
git status --short: (clean)
```

## Routing

| Role | Specialist |
|---|---|
| Lead | workflow / orchestration |
| Docker / platform | deployment, topology, health, host lifecycle |
| Telephony | PJSIP, registration, calls, WSS |
| Application / security | app, secrets, migrations, auth |
| Product designer | not required (blocker is environmental/contract, not UX) |

---

## Pilot host

| Fact | Value |
|---|---|
| Hostname | `cursor` (Cursor cloud agent VM) |
| OS | Ubuntu 24.04.4 LTS (not Debian 14 target) |
| Kernel | 6.12.x |
| Docker | 29.x |
| Compose | v2.40.x |
| CPU | 4 |
| RAM | ~15 GiB |
| Disk | ~225 GiB free at `/workspace` |
| Timezone | Etc/UTC (host); app `.env` TZ=`America/Sao_Paulo` |
| Public DNS / WSS hostname | **absent** (`WSS_PUBLIC_HOSTNAME` empty) |
| Trusted WSS certificate | **absent** (dev fixture only) |
| External carrier / trunk | **not provisioned** |
| Host reboot authorization | **not granted** for this shared agent |

This is the same class of environment TASK-0034H already classified as
unsuitable for closing the real-host certificate gate.

---

## Environment contract vs 0034

| Expectation (0034 contract) | Observed | Classification |
|---|---|---|
| Dedicated real pilot host | Shared cloud agent VM | **MUST_FIX_BEFORE_DEPLOY** |
| Debian 14 host (runbook) | Ubuntu 24.04 | **ACCEPTABLE_PILOT_VARIATION** for Docker-only topology (OS not blocking by itself) |
| Public WSS hostname configured | empty | **MUST_FIX_BEFORE_DEPLOY** |
| Trusted WSS cert (not fixture) | fixture `senma-wss-test` | **MUST_FIX_BEFORE_DEPLOY** |
| Non-placeholder DB/AMI secrets | local-dev placeholders (MATCH among themselves) | **MUST_FIX_BEFORE_DEPLOY** for real pilot |
| Provider fixture off | removed for pilot-up; later reintroduced by regression profile | **ACCEPTABLE** during gates; must stay off on real pilot |
| AMI/DB not published | confirmed on pilot compose (AMI absent; DB internal-only) | OK |
| SIP/WSS/RTP published via pilot overlay | 5060/tcp+udp, 8089/tcp, 10000-10199/udp | OK on this host |
| External trunk/carrier | none | **PILOT_CONSTRAINT** if host/cert existed; here subsumed by blocker |
| Backup destination | `/workspace/backups` created; artifact produced | OK for this host |

Silent architecture adaptation was **not** performed to pretend this host
is a production pilot.

---

## Release identity

Built with supported tooling:

```text
make release-build VERSION=v0.1.0-rc.1 RC=1
```

Recorded identity (evidence copy retained under `/tmp/0035-evidence/`):

| Field | Value |
|---|---|
| Release version | `v0.1.0-rc.1` |
id4c7ab5f3c2ab488a0934bc7e00d71519befd8` |
| Dirty build | `false` (clean tree at build) |
| Tag | none (RC mode — explicit version+commit pairing) |
| App image | `senma-app:v0.1.0-rc.1` |
| App image id (recorded) | `sha256:37aab48560054e4b2b8b3bea01c00b53a9fc68804d9496cd4cad39b85650c1fd` |
| Asterisk image | `senma-asterisk:v0.1.0-rc.1` |
| Asterisk image id (recorded) | `sha256:181aab5e9c1575591f2ef45b9bb27e344af0d1dc2e7e8b9f0801e3ce65ea484d` |
| OCI labels | `org.opencontainers.image.version` / `.revision` / `.created` present |
| Manifest | `release-manifest.json` (gitignored build receipt) |
| DB image | third-party `mariadb:10.11` (inventory only) |

`make release-info` reported **MATCH** immediately after `make pilot-up`
with `RELEASE_VERSION=v0.1.0-rc.1`.

### Provenance process finding (non-blocking for product architecture)

Several `Makefile` check targets depend on `up` (`--build`). When
`RELEASE_VERSION` is exported, those rebuilds can **overwrite** the
release-tagged images and produce doctor `DRIFT` against the recorded
manifest. Evidence captured; release images were rebuilt once to restore
MATCH for pilot proofs. Follow-up debt: avoid `--build` on check targets
when a release tag is active (proposed TASK-0035A process hardening).
This is **not** used to reopen 0034D’s release contract.

---

## Deployment result

```text
make pilot-up   # with RELEASE_VERSION=v0.1.0-rc.1
```

Observed:

- Services: `app`, `asterisk`, `db` healthy
- Provider fixture: **absent** after explicit stop/remove + pilot-up
- Published ports match pilot overlay contract
- AMI and DB not host-published
- Healthchecks converged without blind long sleeps

---

## Preflight checks (on pilot release stack)

| Check | Result | Notes |
|---|---|---|
| `migrate-check` / schema | **PASS** (`SCHEMA_CURRENT`) | Prefer script/`exec` path to avoid `--build` |
| `secrets-check` | **PASS** (`OVERALL: MATCH`) | Values are still local-dev placeholders — unsafe for real pilot |
| `reconcile-check` | **PASS** (`IN_SYNC`) | DB → generated PJSIP → runtime |
| `doctor` | **PASS** (exit 0) | WARN: fixture TLS/WSS cert |
| `cert-check` / `wss-cert-check --pilot` | **FAIL** for pilot acceptance | `PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT` |
| `release-info` | **PASS** (MATCH) right after pilot-up | Later DRIFT if check targets rebuild tags |

### WSS certificate evidence

- Fixture path: `/etc/asterisk/keys/wss-test-cert.pem`
- Subject/Issuer: `CN=senma-wss-test` (self-signed)
- SAN: `DNS:asterisk,DNS:localhost` — no public hostname
- Key mode: `600` / safe
- Runtime fingerprint matches configured file
- TLS handshake to `:8089` succeeds (TLSv1.3)
- HTTP WebSocket upgrade to `/ws` returns `101 Switching Protocols`
- **Pilot acceptance: NOT_ACCEPTABLE_FOR_PILOT** (no public hostname; known fixture)

Per TASK-0034R / 0034H: fixture/self-signed is **not** acceptable for
`PILOT_DEPLOYMENT_PASS`.

---

## Asterisk / PJSIP runtime

| Check | Result |
|---|---|
| Asterisk healthy | PASS (22.x) |
| `res_pjsip` loaded | PASS |
| `chan_sip` loaded | PASS (0 modules — not part of supported runtime) |
| Transports | PASS — `udp`/`tcp` `:5060`, `wss` `:8089` |
| HTTP/WSS listener | PASS — HTTPS bound `0.0.0.0:8089`, `/ws` enabled |
| Endpoints at pilot moment | 0 configured endpoints |

---

## SIP registration / real calls / WSS client REGISTER

| Item | Result | Classification |
|---|---|---|
| Real extension REGISTER (UDP/TCP) | **NOT_RUN** | No pilot endpoints provisioned; no authorized pilot SIP client |
| Outbound/inbound carrier calls | **NOT_RUN** | No carrier/trunk provisioned |
| WSS SIP REGISTER with trusted cert | **NOT_RUN** / blocked by cert contract | TLS+WS upgrade proven only against fixture |
| Extension↔extension call | **NOT_RUN** | Depends on registration |

Simulator-only success would not satisfy “real carrier validation”; here
even that was not claimed as pilot PASS.

---

## Application validation

| Item | Result |
|---|---|
| Login page HTTP 200 | PASS |
| Login markers present | PASS |
| Authenticated dashboard / CRUD | **NOT_RUN** | No pilot admin secret supplied in-task; avoid printing secrets |
| ITC standalone (`itc_enabled=false`) | PASS (contract retained; not reopened) |
| System Status / Calls Report deep UI | **NOT_RUN** (auth-gated) |

---

## Backup / rollback readiness

| Item | Result |
|---|---|
| `scripts/backup.sh` | PASS |
| Artifact | `/workspace/backups/senma-backup-*.tar.gz` (~34M, mode `600`) |
| Path gitignored | PASS (`/backups/`) |
| Destructive live restore | **NOT_RUN** — environment not disposable production; use existing backup-smoke/DR suites for restore proof |

Rollback information: retain release images `senma-*:v0.1.0-rc.1` +
backup tarball; `make pilot-up` consumes recorded release tags; restore
via supported `make restore FROM=...` when authorized.

---

## Soak

| Item | Value |
|---|---|
| Start (UTC) | `2026-09-13T14:31:18Z` (approx.) |
| End (UTC) | `2026-09-13T14:32:44Z` (short window before gates) |
| Duration | **short / insufficient for soak PASS** |
| Restarts during window | 0 |
| Channels stuck | 0 |
| Memory | stable/low in window |
| Classification | **NOT_RUN** as meaningful soak — blocked early by cert/host contract |

Controlled **service restarts** (app, asterisk) during the pilot stack
window: health reconverged; secrets MATCH; reconcile IN_SYNC; doctor
PASS with cert WARN.

**Host reboot:** `NOT_RUN` — operational authorization required on this
shared agent; not faked with container restart.

---

## Incidents / failures

| ID | Class | Summary | Disposition |
|---|---|---|---|
| I1 | **ENVIRONMENTAL** | No real pilot host / DNS / trusted WSS cert | **PILOT blocker** |
| I2 | **PILOT_CONFIG_DEFECT** | Local-dev placeholder secrets | Must rotate on real pilot |
| I3 | **ENVIRONMENTAL / PROCESS** | `make <check>: up --build` overwrote release tags while `RELEASE_VERSION` set → doctor DRIFT | Evidence preserved; proposed 0035A |
| I4 | **ENVIRONMENTAL** | First counted regression contaminated by leftover release-manifest DRIFT (doctor-smoke FAIL) | Decontaminated; not a product defect |
| I5 | **ENVIRONMENTAL** | `transport-smoke` FAIL once mid-suite (delete-blocked-by-trunk assertion); isolated re-run PASS 65/65 | Flake/race; not treated as product reopen of 0034 |

No PRODUCT_DEFECT was proven that reopens a closed 0034 decision.

---

## Canonical repository gates

Run against the same Git revision on this host (authoritative for this
agent; no separate CI host used).

| Gate | Result | Notes |
|---|---|---|
| `make lint` | **PASS** (5/5) | Recreates containers via `up` |
| Regression (contaminated) | **FAIL** | doctor-smoke DRIFT — discarded (env contamination) |
| Regression A (post-decontam) | **FAIL** | transport-smoke 64/65 — discarded; isolated re-run PASS |
| Regression B1 | **PASS** | counted consecutive #1; no repair after |
| Regression B2 | **PASS** | counted consecutive #2; immediately after B1 |

`git diff --check` / `git status --short` evaluated at documentation time
(docs-only changes expected).

---

## Pilot constraints (explicit)

Even if a future real host clears the blocker, retain 0034R constraints:

1. Real trusted WSS cert + `WSS_PUBLIC_HOSTNAME`
2. Concurrent trunk-name collision avoidance
3. Cert expiry watch (manual)
4. TLS/WSS cert rotation requires Asterisk restart
5. AMI single-CIDR topology
6. RTP published range capacity (~100 calls)
7. External carrier cutover is soak/ops work
8. Release-build required before `pilot-up` (never deploy `*:dev`)
9. Provider profile must stay off

---

## Final decision

```text
PILOT_DEPLOYMENT_BLOCKED
```

### Why not PASS / PASS_WITH_CONSTRAINTS

- Trusted WSS cannot work on this environment (`NOT_ACCEPTABLE_FOR_PILOT`).
- No real public pilot hostname/DNS.
- Host is not an authorized production-pilot machine.
- Real SIP registration and call paths were not exercisable as a pilot.
- Meaningful soak was not completed.

These are concrete, reproducible blockers — not historical speculation.

### Recommended follow-ups

1. **TASK-0035A** — Provision real pilot host (Debian 14 or approved), DNS,
   trusted WSS certificate, non-placeholder secrets; re-run 0035 checklist
   through soak.
2. **TASK-0035B** (optional process) — Harden check targets so
   `migrate-check` / `secrets-check` / `reconcile-check` / `lint` do not
   `--build` over an active release tag.
3. Do **not** reopen 0034O–Q / 0034D architecture without new product
   evidence.

---

## Evidence index

- `/tmp/0035-evidence/release-manifest.json`
- `/tmp/0035-*-*.log` (release-build, pilot-up, doctor, cert, secrets, migrate, reconcile, lint, regressions)
- Backup path under `/workspace/backups/` (gitignored; sensitive)

## Commit note

Documentation only for this task’s closure. **No commit/push in this
task** unless explicitly authorized later.
