# TASK-0035D — Production Pilot Final Execution & Closure

## Status

**EVIDENCE CAPTURED — awaiting explicit commit authorization**

**Final decision: `PILOT_DEPLOYMENT_BLOCKED`**

This task re-executed the production-pilot closure protocol on the
**corrected** 0035A/B/C architecture (reverse-proxy WSS, WebRTC contract,
RTP range alignment). The environment remains a Cursor cloud-agent
**PRE_PILOT_VALIDATION_HOST**, not an authorized real pilot host with
public DNS, a trusted CA certificate, or non-placeholder secrets.

Architecture readiness under the corrected model is strong. Final
production-pilot PASS is still blocked by host/certificate/secret
contract gaps that 0035A–C did not (and could not) close.

Do not treat this document as a go-live authorization.

## Starting state

```text
HEAD: c36f5a19fb5bdcfe590015271ce7edde9beaa4d9
      (docs(webrtc): record TASK-0035C browser NAT and TURN findings)
git status --short: ?? tmp-0035a/   (known temp; parked only during clean release-build)
```

## Routing

| Role | Specialist |
|---|---|
| Lead | workflow / orchestration |
| Docker / platform | release, pilot-up, soak, networking |
| Telephony | PJSIP / WSS / WebRTC compact proofs |
| Application / security | app, secrets, migrate, backup |
| Product designer | not required (blocker is environmental) |

## Pilot host classification

**`PRE_PILOT_VALIDATION_HOST`**

| Fact | Value |
|---|---|
| Host role | Shared Cursor cloud agent VM (`cursor`) |
| OS | Ubuntu 24.04.4 LTS (not Debian 14 target) |
| Docker | 29.1.3 |
| Compose | 2.40.3 |
| CPU / RAM / disk | 4 vCPU / ~15 GiB / ~220 GiB free |
| Public IP (egress) | observed `18.118.243.20` — inbound HTTPS not accepted |
| Private net | `172.30.0.2/24` |
| DNS / `WSS_PUBLIC_HOSTNAME` | **empty** |
| Certificate | **fixture** `CN=senma-public-wss-dev` (self-signed) |
| Carrier / trunk | **not provisioned** |
| Host reboot authorization | **not granted** |

Per task rules: this classification forbids claiming final production
pilot `PILOT_DEPLOYMENT_PASS`.

## 0035-series evidence matrix

| Item | Classification | Notes |
|---|---|---|
| Release provenance tooling (0034D/0035) | `STILL_VALID` + `SUPERSEDED_AND_REVALIDATED` | Rebuilt `v0.1.0-rc.2` at HEAD `c36f5a1` |
| Pilot Compose topology | `SUPERSEDED_AND_REVALIDATED` | 0035A: no Asterisk 8089 public; app `:443`/host `:8443` |
| Network exposure (AMI/DB unpublished) | `STILL_VALID` + revalidated | Confirmed on `pilot-up` |
| WSS architecture | `SUPERSEDED_AND_REVALIDATED` | Public TLS at reverse proxy → private `ws:8088` |
| Certificate ownership | `SUPERSEDED_AND_REVALIDATED` | Public cert on app `/etc/senma/certs/`; fixture still not pilot-acceptable |
| PJSIP runtime | `STILL_VALID` + revalidated | Asterisk 22.11; `chan_sip` 0 modules |
| WebRTC endpoint contract (0035B) | `STILL_VALID` | Compact post-deploy MEDIA_OK revalidated on release images |
| Real browser WebRTC (0035C) | `STILL_VALID` | Host Chromium proof; TURN inconclusive |
| RTP range | `SUPERSEDED_AND_REVALIDATED` | Runtime `10000–10199` matches pilot publish |
| migrate / secrets / reconcile / doctor | `SUPERSEDED_AND_REVALIDATED` | Pass on pilot release stack; secrets still placeholders |
| Backup | `SUPERSEDED_AND_REVALIDATED` | New artifact on pilot stack |
| Restart resilience | `SUPERSEDED_AND_REVALIDATED` | App + Asterisk during soak |
| Meaningful soak | `MUST_RETEST` → executed | ~45 min wall-clock with samples + workload |
| Host reboot | `NOT_RUN_CONSTRAINT` | No operational authorization |
| External trunk / carrier calls | `NOT_RUN_CONSTRAINT` | No carrier |
| Real trusted public cert | `MUST_RETEST` → still FAIL for pilot acceptance | Fixture only |

## Release identity

```text
make release-build VERSION=v0.1.0-rc.2 RC=1
# tmp-0035a/ temporarily parked outside the tree for dirty=false
```

| Field | Value |
|---|---|
| Version | `v0.1.0-rc.2` |
| Git revision | `c36f5a19fb5bdcfe590015271ce7edde9beaa4d9` |
| Dirty | `false` |
| Build time | `2026-09-14T14:07:03Z` |
| App image | `senma-app:v0.1.0-rc.2` (`sha256:3769ec50…e5ea`) |
| Asterisk image | `senma-asterisk:v0.1.0-rc.2` (`sha256:69716841…2ff2`) |
| Manifest | `release-manifest.json` (gitignored) |
| `make release-info` after `pilot-up` | **MATCH** (no drift) |

## Deployed topology

```text
export RELEASE_VERSION=v0.1.0-rc.2
make pilot-up
# provider fixture stopped/removed
```

| Surface | Observed |
|---|---|
| Services | `app`, `asterisk`, `db` healthy |
| Provider | **absent** |
| App HTTP/HTTPS | `:8080`→80, `:8443`→443 |
| Asterisk SIP | `:5060` udp/tcp |
| Asterisk RTP | `:10000–10199/udp` |
| Asterisk 8088/8089 | **unpublished** |
| DB / AMI | **not host-published** |

## Public certificate

| Check | Result |
|---|---|
| Path | `/etc/senma/certs/public-wss.crt` (+ `.key` mode `600`) |
| Pair / validity | MATCH / valid dates |
| Runtime fingerprint | MATCH on proxy listener |
| Fixture / self-signed | **yes** |
| `WSS_PUBLIC_HOSTNAME` | empty → hostname match skipped |
| `PILOT_ACCEPTANCE` | **`NOT_ACCEPTABLE_FOR_PILOT`** |

Disposition: **PILOT_BLOCKER** for final production pilot closure.

## Placeholder secrets

`secrets-check` → `OVERALL: MATCH`, but values remain documented local-dev
placeholders (`change-me-for-local-development`).

Disposition: **PILOT_BLOCKER** for a real pilot host (unsafe to operate
with known defaults). Acceptable only on this pre-pilot validation host.

## Compact WSS / WebRTC post-deploy proof

On release images (same revision as 0035B/C artifacts):

| Check | Result |
|---|---|
| Public TLS + WSS 101 `/asterisk/ws` | PASS |
| Private Asterisk WS `:8088` | PASS |
| `webrtc-endpoint-contract-smoke` (31/0) incl. MEDIA_OK | PASS |
| RTP runtime `10000–10199` | PASS |
| `res_srtp.so` Running | PASS |

Full Chromium matrix from 0035C was **not** re-run end-to-end; artifact
revision matches the already-tested HEAD and compact telephony media
proof passed.

## Application validation

Authenticated navigation (fixture admin, no secret printed):

| Path | Result |
|---|---|
| Login | PASS (302) |
| Dashboard / extensions / trunks / calls-report / cnl / notifications | PASS HTTP 200, no Fatal |
| System Status (`systemstatus`) | PASS HTTP 200 |
| IP status | PASS HTTP 200 |
| ITC standalone | retained (`itc_enabled=false` contract; not reopened) |

## Backup / rollback

| Item | Result |
|---|---|
| `make backup` | PASS |
| Artifact | `backups/senma-backup-20260914-141103Z.tar.gz` (~34M, mode `600`) |
| Structure | manifest, checksums, db dump, setup.conf, asterisk-etc, sounds/moh |
| Destructive restore | **NOT_RUN** (host not disposable production) |
| Rollback identity | retain `senma-*:v0.1.0-rc.2` + backup tarball |

## Soak

| Item | Value |
|---|---|
| Start (UTC) | `2026-09-14T14:07:42Z` |
| End (sample window) | `2026-09-14T14:51:51Z` (~44.2 min real elapsed) |
| Monitor done | `2026-09-14T14:52:51Z` |
| Samples | 45 × 60s (health / mem / disk / restart counts / channels) |
| Workload | WSS proxy smoke; WebRTC contract+MEDIA_OK; 5× app navigation; controlled app+Asterisk restart mid-soak |
| Host reboot | **NOT_RUN** |

### Soak observations

| Signal | Result |
|---|---|
| Unhealthy/exited rows | 0 |
| Transient `starting` | 1 sample (during intentional app restart) |
| Stuck channels | 0 throughout |
| Disk use | stable ~9% |
| Mem available | ~5.2–5.8 GiB (STABLE / EXPECTED_GROWTH noise) |
| Asterisk full log | ~41M → ~42M (EXPECTED_GROWTH) |
| Container crash loops | none |

### Resource trend (pre → post)

| Metric | Pre-soak | Post-soak | Class |
|---|---|---|---|
| App RSS | ~45 MiB | ~29 MiB (after restart) | STABLE |
| Asterisk RSS | ~56 MiB | ~43 MiB (after restart) | STABLE |
| DB RSS | ~85 MiB | ~87 MiB | STABLE |
| Swap | 0 | 0 | STABLE |
| Disk `/workspace` | ~9% | ~9% | STABLE |

## Post-soak health

| Check | Result |
|---|---|
| migrate-check | PASS / SCHEMA_CURRENT |
| secrets-check | PASS / OVERALL MATCH (placeholders remain) |
| reconcile-check | PASS / IN_SYNC |
| doctor (functional) | PASS except release identity |
| Release identity immediately after soak checks | **DRIFT** then restored |

### Incident I4 — release image DRIFT after `make backup`

**Class:** PILOT_CONFIG_DEFECT / process debt (known from TASK-0035)

`make backup` depends on `up` (`docker compose up -d --build`). With
`RELEASE_VERSION=v0.1.0-rc.2` exported, that rebuild **retagged**
`senma-*:v0.1.0-rc.2` to new image IDs, causing doctor
`Release artifact identity: DRIFT` while containers still carried the
new tags.

**Recovery:** clean `make release-build VERSION=v0.1.0-rc.2 RC=1` +
`make pilot-up` restored `release-info` **MATCH** (new manifest IDs).
No product code change. Follow-up debt remains: check/backup targets
must not `--build` over an active release tag.

## Incidents

| ID | Class | Symptom | Recovery | Manual? |
|---|---|---|---|---|
| I1 | HOST_ENVIRONMENT | Leftover `senma-0035c-baresip` at pilot start | Removed | yes |
| I2 | PILOT_CONFIG_DEFECT | Fixture public WSS cert; no hostname | None — blocker | n/a |
| I3 | PILOT_CONFIG_DEFECT | Placeholder DB/AMI secrets | None — blocker | n/a |
| I4 | PILOT_CONFIG_DEFECT | Release tag rewritten by `backup→up --build` | Rebuild+pilot-up | yes |

No unexplained product crash loops during soak samples.

## Pilot constraint review

| Constraint | Final state |
|---|---|
| Real public WSS certificate | **PILOT_BLOCKER** |
| Hostname / DNS | **PILOT_BLOCKER** |
| Placeholder secrets on real pilot | **PILOT_BLOCKER** |
| External trunk / carrier | **PILOT_CONSTRAINT_ACCEPTED** (not provisioned) |
| WebRTC browser path | **CLOSED** for host topology (0035C); internet NAT/TURN **POST_PILOT_DEBT** |
| Inbound browser call | **POST_PILOT_DEBT** |
| Host reboot | **PILOT_CONSTRAINT_ACCEPTED** (not authorized) |
| Release artifact | **CLOSED** after intentional rebuild; process anti-`--build` debt remains **POST_PILOT_DEBT** |
| Backup readiness | **CLOSED** (create/validate); live restore auth-gated |
| RTP capacity/range | **CLOSED** (`10000–10199` aligned) |

## Canonical gates

Run against Git revision `c36f5a1` in this authoritative environment
**after** pilot soak observations.

| Gate | Result |
|---|---|
| `make lint` | **PASS** |
| Interrupted regression (leftover `release-manifest.json` → doctor DRIFT) | **FAIL** (`doctor-smoke`) — classified as process contamination from pilot manifest vs rebuilt test images; not a product defect |
| After parking gitignored `release-manifest.json` | |
| `make regression` #1 (`EXITA:0`) | **PASS** |
| `make regression` #2 (`EXITB:0`) | **PASS** consecutive, no repair between |
| `git diff --check` | **PASS** |

Doctor WARN (fixture cert) remains accepted on this host (`WARN_ACCEPTED`).

## Final decision

**`PILOT_DEPLOYMENT_BLOCKED`**

Reason (concrete):

1. Validation host is not a real pilot host.
2. Trusted public reverse-proxy certificate is absent (fixture only; `NOT_ACCEPTABLE_FOR_PILOT`).
3. Public hostname / DNS is absent.
4. Secrets remain known local-dev placeholders (MATCH among themselves, unsafe for real pilot).

What is **not** blocking product architecture after 0035A/B/C:

- reverse-proxy WSS model;
- WebRTC endpoint + DTLS-SRTP + RTP alignment;
- release provenance + pilot compose exposure;
- migrate / reconcile / doctor (non-cert) / backup create;
- controlled service restart recovery;
- ~44 min continuous soak without crash/stuck channels.

## Next recommendation

On an authorized **REAL_PILOT_HOST** (Debian 14 preferred):

1. Provision DNS + trusted public cert on the reverse-proxy paths.
2. Install non-placeholder secrets; `make secrets-check` → MATCH.
3. `make release-build` from the intended tag/commit; `make pilot-up`.
4. Avoid `make backup`/`make up --build` while a release tag is active (or harden those targets).
5. Re-run compact WSS/WebRTC + carrier calls + authorized host reboot.
6. Close with **TASK-0035E** using this document as the pre-pilot baseline.

Do **not** open TURN implementation until a real external NAT failure proves it.

## Documentation updates

- This file is the authoritative 0035D closure.
- `docs/tasks/0035-production-pilot-deployment-soak-validation.md` points here for final status.
