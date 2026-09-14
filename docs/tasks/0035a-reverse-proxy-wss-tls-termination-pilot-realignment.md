# TASK-0035A — Reverse Proxy WSS TLS Termination & Pilot Contract Realignment

## Status

**IMPLEMENTED / EVIDENCE CAPTURED — awaiting explicit commit authorization**

Decision impact on TASK-0035:

- The TASK-0035 finding that **Asterisk itself must present the trusted public WSS certificate on `:8089`** is **SUPERSEDED BY TASK-0035A**.
- Unrelated TASK-0035 evidence (release build, provenance, topology AMI/DB unpublished, migrate/secrets/reconcile/doctor, backup, restart recovery, lint, consecutive regressions) remains **STILL_VALID**.
- Pilot go-live still requires a **non-fixture, publicly trusted certificate on the reverse-proxy public WSS endpoint** plus a real `WSS_PUBLIC_HOSTNAME` — that operational constraint remains, but its **ownership moved to Apache (`app`)**, not Asterisk HTTP TLS.

## Starting state

```text
HEAD: 51d4c7ab5f3c2ab488a0934bc7e00d71519befd8
Dirty tree: TASK-0035 documentation updates (uncommitted) plus this task's changes
```

## Routing

| Role | Specialist |
|---|---|
| Lead | telephony architecture |
| Docker / platform | reverse proxy, networking, ports, lifecycle |
| Asterisk / PJSIP | HTTP WS + PJSIP websocket transport |
| Application / security | public proxy boundary + certificate handling |
| Workflow | TASK-0035 evidence realignment |

## Previous TASK-0035 result (preserved)

### Still valid

- Release build + provenance MATCH after pilot-up
- Pilot topology: app/asterisk/db healthy; provider off; AMI/DB unpublished
- SIP/RTP publish via pilot overlay (5060 + RTP range)
- migrate-check SCHEMA_CURRENT; secrets-check MATCH; reconcile-check IN_SYNC
- doctor PASS with fixture-cert WARN (now re-pointed at public proxy fixture)
- Asterisk PJSIP udp/tcp `:5060`; `chan_sip` unloaded
- Backup artifact; app/asterisk restart recovery
- Lint PASS; two consecutive regressions PASS after decontamination

### Superseded by TASK-0035A

- Assumption that **Asterisk `:8089` is the public TLS endpoint** requiring the trusted pilot certificate
- Pilot blocker framing that required replacing the Asterisk WSS fixture cert **on Asterisk** before WSS could be architecturally correct
- `cert-check --pilot` evaluating Asterisk listener trust as the public WSS contract

### Must retest (done in this task)

- Public TLS handshake at reverse proxy
- WebSocket upgrade through public path
- SIP REGISTER over public WSS route
- Host publish matrix (8088/8089 unpublished; app HTTPS published)
- Private Asterisk WS reachability from app only

## Current → target topology

### Before (TASK-0034E / TASK-0035 assumption)

```text
Browser --wss trusted TLS--> Asterisk :8089 /ws
```

### After (TASK-0035A supported model)

```text
Browser --wss trusted TLS--> app:443 /asterisk/ws
                           |
                           +-- reverse proxy (Apache)
                           |
                           v
                    ws://asterisk:8088/ws   (Docker network only)
                           |
                           v
                    PJSIP transport protocol=ws bind=0.0.0.0:8088
```

Preferred internal hop is **plain WS**, not proxy→Asterisk WSS, so public certificate lifecycle is owned solely by the reverse proxy.

## Reverse proxy selection

Existing Apache inside the `app` image (`php:*-apache`). Enabled modules:

- `ssl`
- `proxy`
- `proxy_http`
- `proxy_wstunnel`
- `headers`
- `rewrite`

No second reverse-proxy product introduced.

Public path (SENMA-owned): `/asterisk/ws`

## Docker / network path

| Surface | Binding | Published to host? |
|---|---|---|
| App HTTP | `:80` | yes (`MAG_HTTP_PORT`, default 8080) |
| App HTTPS/WSS | `:443` | yes (`MAG_HTTPS_PORT`, default 8443) |
| Asterisk private WS | `0.0.0.0:8088` | **no** |
| Asterisk HTTP TLS 8089 | disabled when no ws/wss cert row | **no** (removed from `compose.pilot.yaml`) |
| SIP udp/tcp 5060 | asterisk | pilot overlay only |
| RTP 10000-10199/udp | asterisk | pilot overlay only |
| AMI / DB | internal only | **no** |

Networks unchanged: `mag` (general) + `senma-control` (AMI).

## Certificate ownership model

| Class | Owner | Notes |
|---|---|---|
| PUBLIC_WEB_WSS_CERT | Apache / `app` (`/etc/senma/certs/public-wss.crt`) | Public trust surface; renew → reload/restart Apache |
| NATIVE_SIP_TLS_CERT | Asterisk `protocol=tls` transport | Separate lifecycle; untouched |
| WEBRTC_DTLS_CERT | Endpoint media (`webrtc` / DTLS) | Not the public WSS cert lifecycle |
| LEGACY_UNUSED_CERT | Asterisk HTTP TLS fixture keys may still be generated | Not required for supported public WSS path |

## Native SIP TLS separation

`Snep_PjsipTransportConf` still emits `cert_file` / `priv_key_file` only for `protocol=tls`. Websocket rows no longer need Asterisk HTTP TLS material for the supported path. `senma-http-tls.conf` emits `tlsenable=no` when no enabled ws/wss row carries certs.

## WebRTC DTLS separation

Endpoint generation already uses:

- AOR `max_contacts=1`
- `remove_existing=yes`

No `webrtc=yes` / `dtls_auto_generate_cert=yes` is forced by this task. Signaling WSS/WS does not require coupling endpoint media DTLS to the public proxy certificate. **No WebRTC template change in this task** — document rather than invent Confast copies.

## Root architecture decision

```text
PUBLIC HTTPS/WSS TLS          owner: reverse proxy (Apache in app)
ASTERISK WEBRTC SIGNALING     private WS behind reverse proxy (:8088/ws)
WEBRTC MEDIA SECURITY         DTLS-SRTP / endpoint lifecycle (independent)
NATIVE SIP TLS                separate Asterisk transport/certificate lifecycle
```

This is the supported SENMA model unless runtime evidence proves it unsuitable.

## Changes (implementation)

- `docker/apache-mag.conf` — HTTPS vhost + `ProxyPass /asterisk/ws` → `ws://asterisk:8088/ws`
- `docker/app.Dockerfile` — enable `ssl`/`proxy`/`proxy_http`/`proxy_wstunnel`; expose 443; `/etc/senma/certs`
- `docker/entrypoint.sh` — mint/mount public WSS cert (`public-wss.crt` / `.key`) for Apache
- `docker/asterisk-config/http.conf` — private bind `0.0.0.0:8088` (no public TLS listener required)
- `docker/asterisk-entrypoint.sh` — refresh outdated loopback-only `http.conf` on upgrade
- `compose.yaml` — publish app HTTPS (`MAG_HTTPS_PORT`→443); do not publish Asterisk 8088/8089
- `compose.pilot.yaml` — remove Asterisk `8089` host publish for the pilot overlay
- Seed (`snep/install/database/system_data.sql`) + migration `0002-wss-proxy-private-ws-realignment.sql` — `wss` row → `protocol=ws`, port 8088, clear Asterisk cert refs
- `scripts/lib/wss-cert-lib.sh` + `scripts/wss-cert-check.sh` — public trust = proxy cert + app:443 peek
- `scripts/doctor.sh` — `Asterisk HTTP/WS backend` check (Asterisk HTTPS optional)
- `scripts/wss-proxy-termination-smoke-test.sh` — focused topology / unpublished ports / WSS upgrade proof
- `scripts/wss-platform-smoke-test.sh`, `scripts/tls-cert-management-smoke-test.sh`, `scripts/wss-certificate-runtime-smoke-test.sh`, `scripts/pjsip-runtime-status-smoke-test.sh`, `scripts/transport-shared-runtime-ux-smoke-test.sh`, `scripts/doctor-smoke-test.sh` — realigned to proxy termination
- `snep/modules/default/views/scripts/pjsip-transports/addedit.phtml` — WSS/WS cert help text describes reverse-proxy ownership

## Cert-check changes

- Reads public cert from `app:/etc/senma/certs/public-wss.crt` (not Asterisk `wss` `cert_file`)
- Runtime peek defaults to app loopback `:443` (`via-app`)
- Still requires an enabled ws/wss signaling transport row
- Fixture classification covers public-proxy dev fixture CN/path (`senma-public-wss-dev`)
- `--pilot` rejects fixture + missing `WSS_PUBLIC_HOSTNAME`
- Does **not** require Asterisk internal WS to present a trusted public certificate

## Focused tests

| Test | Result |
|---|---|
| `scripts/wss-proxy-termination-smoke-test.sh` | **PASS** (11/11) |
| `scripts/tls-cert-management-smoke-test.sh` | **PASS** (22/22) |
| `scripts/wss-certificate-runtime-smoke-test.sh` | **PASS** (20/20) |
| `scripts/wss-platform-smoke-test.sh` | **PASS** (29/29) |
| `scripts/pjsip-runtime-status-smoke-test.sh` | **PASS** (15/15) after proxy REGISTER path |
| `scripts/transport-shared-runtime-ux-smoke-test.sh` | **PASS** (24/24) |
| `scripts/trunk-smoke-test.sh` / `scripts/pjsip-reconcile-smoke-test.sh` | **PASS** after leftover fixture cleanup |
| `scripts/doctor-smoke-test.sh` | **PASS** (`Asterisk HTTP/WS backend`) |
| Public TLS handshake `:8443` | **PASS** |
| WSS upgrade `/asterisk/ws` → 101 + `sip` | **PASS** |
| SIP REGISTER over public WSS | **PASS** (`REGISTER_OK`, contact `transport=ws`) |
| `make cert-check` | **PASS** informational (`TRUST_STATE: SELF_SIGNED`, fixture) |
| `make cert-check PILOT=1` | **NOT_ACCEPTABLE_FOR_PILOT** (fixture + empty hostname) — expected on this host |

## Public TLS / WebSocket / REGISTER proofs (runtime)

Evidence captured 2026-09-13 on this agent host:

1. `openssl s_client` to `127.0.0.1:8443` presents `CN=senma-public-wss-dev`
2. Test client `HANDSHAKE_OK` on `wss://127.0.0.1:8443/asterisk/ws`
3. Authenticated SIP REGISTER → `200 OK` / `REGISTER_OK`
4. `pjsip show contacts` showed `1197/...;transport=ws` while session held
5. Asterisk `http show status`: `Bound to 0.0.0.0:8088`, no public 8089 publish
6. `docker compose ps`: app publishes 8080/8443; asterisk publishes no 8088/8089

## WebRTC call proof

**NOT_RUN** — no WebPhone/WebRTC media client in this task scope. Signaling REGISTER proven. Media DTLS remains separate follow-up when a WebRTC client exists.

## Failure isolation

| Failure | Expected behavior |
|---|---|
| Reverse proxy down | Public WSS unavailable; Asterisk UDP/TCP SIP may continue |
| Asterisk WS down | Proxy stays up; WSS registration fails |
| Public cert invalid | Browser/WSS clients fail; other PBX transports unaffected |

## TASK-0035 evidence realignment

| Item | Classification |
|---|---|
| Release build / provenance | STILL_VALID |
| Pilot service health / AMI/DB unpublished | STILL_VALID |
| SIP/RTP publish | STILL_VALID |
| migrate/secrets/reconcile/doctor (non-WSS) | STILL_VALID |
| Backup / restart recovery | STILL_VALID |
| Lint + regression B1/B2 | **RETESTED_PASS** — two consecutive `make regression` PASS (`EXIT1:0`, `EXIT2:0`) after TASK-0035A |
| Asterisk must present public WSS cert on :8089 | **SUPERSEDED_BY_0035A** |
| cert-check pilot against Asterisk :8089 | **SUPERSEDED_BY_0035A** |
| Real public CA + DNS hostname | STILL_VALID ops constraint (now on proxy) |
| Full soak redo | NOT_RELEVANT solely due to WSS termination change |
| Authenticated app flows / real carrier calls | STILL_VALID gaps from 0035 |

## Canonical gates (post-0035A)

Evidence captured 2026-09-13/14 on this agent host:

| Gate | Result |
|---|---|
| Focused WSS/proxy/cert/platform/runtime/doctor smokes | **PASS** |
| `make doctor` | **PASS** (0 FAIL; WARN: public WSS still fixture `CN=senma-public-wss-dev`) |
| `make secrets-check` | **MATCH** |
| `make migrate-check` | **SCHEMA_CURRENT** (`0002-wss-proxy-private-ws-realignment`) |
| `make reconcile-check` | **IN_SYNC** |
| `make lint` | **PASS** |
| `make regression` #1 | **PASS** (`EXIT1:0`) |
| `make regression` #2 | **PASS** (`EXIT2:0`) consecutive, no manual repair between |
| `git diff --check` | **PASS** |

Harness note: `scripts/restart-smoke-test.sh` audit window was fixed to use suite-start DB timestamp (the prior `NOW()-5 MINUTE` window aged out early Restart rows when the suite ran ~50–100 minutes).

## Operational certificate renewal

Supported target:

```text
renew public certificate files on app
→ reload/restart Apache (app container)
```

Asterisk restart is **not** required solely for public WSS certificate renewal.

Actual lifecycle on this stack: entrypoint loads certs at app start; Apache reads `SSLCertificateFile` at start/reload. Prefer `apache2ctl graceful` inside app when certs are rotated in place; full app recreate also works. **Do not claim zero downtime without measuring graceful reload on the pilot host.**

## Remaining constraints

1. Real pilot still needs a publicly trusted cert + `WSS_PUBLIC_HOSTNAME` on the **proxy**
2. Placeholder secrets unsafe for real pilot (from 0035)
3. No real carrier trunk / WebRTC media call in this environment
4. Host reboot soak still NOT_RUN (0035)

## Recommendation

Adopt reverse-proxy WSS termination as the supported architecture.

Re-score pilot WSS readiness as:

- Architecture: **UNBLOCKED** relative to the old Asterisk-direct cert assumption
- Operational trust: still **BLOCKED** until a non-fixture public cert + hostname are provisioned on the proxy

Do not invalidate the rest of TASK-0035's successful evidence.

## Follow-on: TASK-0035B (endpoint / media)

Public WSS TLS termination is owned by this task. The supported
WebRTC **endpoint/media** contract (`webrtc=yes`, DTLS-SRTP, ICE,
codecs, AOR contact policy, real media proof) is documented in
`docs/tasks/0035b-webrtc-endpoint-contract-real-media-validation.md`.

## Follow-on: TASK-0035C (real browser / NAT / TURN)

Real Chromium/JsSIP validation and the TURN requirement decision live in
`docs/tasks/0035c-real-browser-webrtc-internet-nat-turn-validation.md`.
Public signaling ownership remains this reverse-proxy model.
