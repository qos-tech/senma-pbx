# TASK-0035C — Real Browser WebRTC, Internet NAT & TURN Requirement Validation

## Status

**EVIDENCE CAPTURED — awaiting explicit commit authorization**

**Final decision: `REAL_BROWSER_WEBRTC_PASS_WITH_CONSTRAINTS`**

**TURN decision: `TURN_REQUIREMENT_INCONCLUSIVE`**

## Starting state

```text
HEAD: fa56be57d1f5b5cabdce67f3650844687c726df2
      (docs(webrtc): close TASK-0035B endpoint and media contract)
git status --short: ?? tmp-0035a/   (intentional temp; left untouched)
```

## Routing

| Role | Specialist |
|---|---|
| Lead | Telephony architecture / WebRTC |
| Asterisk / PJSIP | RTP range, ICE/NAT, media diagnostics |
| Docker / platform | Pilot RTP publish, network isolation |
| Application | Disposable browser harness wiring |
| Security | Exposure / credentials / DTLS-SRTP |
| Product designer | Browser behavior notes only (not WebPhone UI) |

## Preserve 0035B contract

Unchanged:

```text
SIGNALING   browser → public WSS reverse proxy → private Asterisk WS
ENDPOINT    webrtc=yes ; direct_media=no
AOR         max_contacts=1 ; remove_existing=yes
MEDIA       DTLS-SRTP + ICE
CODECS      ulaw/alaw baseline ; g722 optional ; Opus not packaged
```

No endpoint-contract redesign was required by browser evidence.

## Test client

Disposable harness (NOT the SENMA WebPhone):

| Path | Role |
|---|---|
| `docker/webrtc-browser-test-client/` | Static page + vendored JsSIP browser bundle |
| `run.cjs` + `puppeteer-core` | Headless Chromium driver (system Chrome) |
| Fixture secrets | `task0035c-browser-*` only (not production) |

Capabilities exercised: WSS REGISTER, digest auth, INVITE, getUserMedia (fake device), WebRTC SDP, ICE, DTLS-SRTP, audio send/receive, hangup. Inbound auto-answer is implemented in the harness but SIP→browser media was **not** proven end-to-end in this environment (see below).

## Browser / OS

| Field | Value |
|---|---|
| Browser | Google Chrome `148.0.7778.96` (Chromium-family) |
| OS | Linux (cloud agent host) |
| Mic permission | Fake UI/device flags (`--use-fake-ui-for-media-stream`, `--use-fake-device-for-media-stream`) — real mic prompt not exercised |
| Secure context | Page served from `http://127.0.0.1` harness; WSS to `https`/`wss` public proxy with fixture cert (`ignore-certificate-errors` for self-signed) |
| Firefox | **NOT_RUN** (not installed; snap-only candidate) |

Multi-browser PASS is **not** claimed.

## External network topology

### PBX side (this environment)

```text
Host eth0 private 172.30.0.2/24 ; observed egress public 18.118.243.20
App publishes :8080 HTTP and :8443 HTTPS/WSS
Asterisk private WS 0.0.0.0:8088 (Docker mag network only; unpublished)
Pilot overlay: SIP 5060 + RTP 10000-10199/udp published
Asterisk container IP on mag: 172.28.0.4
Global STUN: disabled
Transport NAT fields (wss): external_media/signaling empty by default
```

### Browser side (validated)

```text
Chromium on the SAME cloud-agent host as Docker
WSS URL: wss://127.0.0.1:8443/asterisk/ws
ICE: host candidates on Docker bridge / host private addresses only
Selected pair: host ↔ host (private ↔ private)
```

### What this is / is not

- **Is** a real Chromium + JsSIP proof of the 0035A/0035B signaling and media contract.
- **Is not** a browser behind a remote ISP / CGNAT / mobile network.
- Public inbound `https://18.118.243.20:8443` returned **no TCP accept** from this host (`HTTP 000`) — the environment cannot accept arbitrary internet clients to the published ports.

Therefore internet-NAT / TURN requirement remains **inconclusive** (not invented).

## Public WSS proof

PASS:

- TLS + WebSocket upgrade on `/asterisk/ws` via app reverse proxy
- SIP REGISTER OK from Chromium/JsSIP
- Browser does **not** connect to Asterisk `:8088`/`:8089` (host path unreachable; private IP unreachable from non-mag bridge)

## Registration proof

PASS:

- Contact visible in `pjsip show contacts` / `pjsip show endpoint` while registered (`transport=ws` via proxy path)
- Disconnect/unregister clears contact
- Overlapping second REGISTER leaves **exactly one** contact (`max_contacts=1` + `remove_existing=yes`)

## ICE candidates (sanitized)

Local browser candidates observed (types only): **host** (multiple private address classes on host/docker bridges). **No srflx. No relay.**

Selected candidate pair (successful MEDIA_OK call):

| Side | Type | Address class | Protocol |
|---|---|---|---|
| local | host | private | udp |
| remote | host | private | udp |

No full SDP committed. Fingerprints / ice-ufrag / ice-pwd redacted in harness logs.

## STUN findings

- `rtp show settings`: ICE support yes; **STUN disabled**
- `rtp.conf` does **not** enable a public `stunaddr`
- Browser harness default `iceServers: []` (no client STUN)
- Result: host-only candidates; media succeeded only because browser and Asterisk shared private reachability on the Docker host

Do **not** auto-add Google STUN. For non-host clients, the supported next knob is operator-configured `external_media_address` / `local_net` on PJSIP transports (already modeled in SENMA), not an undeclared public STUN dependency.

## RTP exposure

| Topology | RTP publish | Asterisk RTP range (runtime) |
|---|---|---|
| Default `make up` | **not** published | must be 10000–10199 after fix |
| Pilot `compose.pilot.yaml` | **10000–10199/udp** | must match |

### Defect closed in this task

TASK-0034B narrowed `snep/install/etc/asterisk/rtp.conf` to 10000–10199, but the Asterisk container **never deployed** that file (`docker/asterisk-entrypoint.sh` only seeds `docker/asterisk-config/*.conf`). Live before fix: `rtp show settings` → **5000–31000** defaults while pilot published only 10000–10199.

Fix:

- Add `docker/asterisk-config/rtp.conf` (runtime source of truth)
- Entrypoint seeds `/etc/asterisk/rtp.conf` when missing on existing volumes
- Keep `snep/install/etc/asterisk/rtp.conf` as documentation mirror (no public STUN)

## NAT / external address contract

Seeded transports leave `external_media_address` / `external_signaling_address` empty. That is correct for Docker-network-only media; it is **insufficient** for clients that cannot route to Asterisk's private Docker IP.

Operator contract for pilot internet clients (when inbound is actually reachable):

1. Publish pilot RTP (`compose.pilot.yaml`)
2. Set `external_media_address` (and `local_net` as appropriate) on the relevant transport(s) to a client-reachable host/public address
3. Re-evaluate ICE; add TURN only if still required

No blind NAT parameter was added to production defaults.

## Browser → SIP call

**PASS** (host Chromium topology):

- INVITE to normal SIP extension (baresip auto-answer)
- Answer + DTLS `connected`
- Codec negotiated: `audio/PCMU`
- Bidirectional counters (pre-hangup): ~439040 bytes sent / ~439200 bytes received; ~2744/2745 packets
- Teardown clean (`hangupOk`)

One-way audio was **not** observed on this successful path.

## SIP → browser call

**NOT_RUN / NOT_PROVEN** for bidirectional media.

Harness supports `--wait-inbound` + auto-answer. An Asterisk `channel originate PJSIP/<webrtc>` attempt did not yield `inboundInvite`/`MEDIA_OK` in the captured run. Do not mark PASS.

## DTLS-SRTP proof

PASS on browser→SIP path: `dtlsState=connected`, SDP profile `UDP/TLS/RTP/SAVPF`, `res_srtp.so` Running, no plain-RTP downgrade.

## Bidirectional media proof

PASS on host Chromium path (bytes/packets both directions). Topology constraint: private host ICE pair.

## Network transition

**NOT_RUN** (single host / single network namespace; no Wi-Fi↔mobile ISP transition available).

## Failure matrix

| Case | Result |
|---|---|
| Invalid WSS path | PASS — no upgrade (HTTP 404) |
| Wrong SIP password | PASS — no REGISTER_OK |
| Microphone permission denied | NOT_RUN (fake media flags; real deny UX not exercised) |
| Media/NAT failure class | Documented: without shared private reachability / external_media, host-only ICE will not serve remote NATs |
| RTP blocked | NOT_RUN as a separate firewall experiment; default `make up` omits RTP publish by design |
| Browser abrupt close | PARTIAL — process kill observed; contact may linger until expire (AOR policy unchanged) |

## TURN decision

**`TURN_REQUIREMENT_INCONCLUSIVE`**

Reasons:

- Environment cannot place a real browser on an external ISP path that reaches this PBX (public inbound blocked)
- Successful media used **host/private** ICE only — no srflx/relay evidence
- Do not invent `TURN_REQUIRED` without a failed direct/STUN path on a meaningful external topology
- Product implication (non-binding): broader internet WebPhone support will likely be topology-dependent without TURN — candidate follow-up **TASK-0035D** only after a real external FAIL without relay

## Root cause of any media failure

No media failure on the proven host Chromium path after RTP range alignment.

Pre-fix RTP mismatch (defaults 5000–31000 vs pilot publish 10000–10199) would have been a silent pilot media footgun for host-published ports; closed by deploying `rtp.conf`.

## Changes

| Area | Change |
|---|---|
| Asterisk config | `docker/asterisk-config/rtp.conf` |
| Entrypoint | seed `rtp.conf` when missing |
| Vendored mirror | `snep/install/etc/asterisk/rtp.conf` comments + no public STUN |
| Browser harness | `docker/webrtc-browser-test-client/` |
| Smoke | `scripts/webrtc-browser-nat-smoke-test.sh` |
| Wiring | Makefile + `scripts/regression.sh` |
| Docs | this file + light 0035/0035B pointers |

## Automated test changes

Deterministic:

- RTP file deployed + runtime range 10000–10199
- Repo sync with `compose.pilot.yaml`
- 8088/8089 unpublished
- Generator contract still opt-in WebRTC
- Invalid WSS path / wrong password
- Private Asterisk IP not reachable from non-mag bridge

Conditional (Chrome present): real Chromium REGISTER + MEDIA_OK on host→proxy path.

Internet connectivity itself is **not** a flaky canonical gate.

## Security review

- Asterisk 8088/8089 remain unpublished
- RTP publish limited to pilot 10000–10199 when overlay active
- No diagnostic TURN deployed
- No production passwords in committed browser source (fixtures only)
- Public WSS remains TLS at proxy; media remains DTLS-SRTP
- Fixture cert still self-signed (0035A operational constraint)

## WebPhone readiness assessment

| Area | Status |
|---|---|
| WSS signaling | READY (0035A + browser REGISTER) |
| Endpoint provisioning | READY (0035B) |
| DTLS-SRTP | READY (browser media proof) |
| ICE/NAT | CONSTRAINED (host/private proven; internet NAT inconclusive; external_media operator contract) |
| Codec baseline | CONSTRAINED (ulaw/alaw; Opus not packaged) |
| Inbound calls | NOT_PROVEN |
| Browser notifications / background | NOT_IN_SCOPE |
| Mobile push | NOT_IN_SCOPE |

The WebPhone **product** is not ready; the backend contract is ready with constraints.

## Canonical gates

| Gate | Result |
|---|---|
| Focused `wss-proxy-termination-smoke` | PASS |
| Focused `webrtc-endpoint-contract-smoke` | PASS (31/0) |
| Focused `webrtc-browser-nat-smoke` | PASS (base topology + Chromium MEDIA_OK) |
| `make doctor` | PASS (WARN: fixture public WSS cert — expected) |
| `make secrets-check` | PASS / OVERALL MATCH |
| `make migrate-check` | PASS / SCHEMA_CURRENT (`0003-webrtc-endpoint-flag`) |
| `make reconcile-check` | PASS / IN_SYNC |
| `make lint` | PASS |
| `make regression` #1 | PASS (`EXIT1:0`) |
| `make regression` #2 | PASS (`EXIT2:0`) consecutive, no repair between |
| `git diff --check` | PASS |

## Final decision

**`REAL_BROWSER_WEBRTC_PASS_WITH_CONSTRAINTS`**

**`TURN_REQUIREMENT_INCONCLUSIVE`**

Real Chromium/JsSIP REGISTER + bidirectional DTLS-SRTP media proven on the
host→public-proxy path with private host ICE. RTP runtime range aligned to
the pilot publish window. True internet-NAT / TURN requirement cannot be
settled in this environment (public inbound blocked; no remote-ISP browser).
Inbound SIP→browser media and multi-browser matrix remain unproven.
