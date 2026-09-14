# TASK-0035B — WebRTC Endpoint Contract & Real Media Validation

## Status

**IMPLEMENTED / EVIDENCE CAPTURED — awaiting explicit commit authorization**

**Final decision: `WEBRTC_CONTRACT_PASS_WITH_CONSTRAINTS`**

## Starting state

```text
HEAD: e186a562f2c8f986aae6ce899c78daed531f802d
      (docs(wss): record TASK-0035A proxy termination architecture)
git status --short: ?? tmp-0035a/   (unrelated; left untouched)
```

## Routing

| Role | Specialist |
|---|---|
| Lead | Asterisk / PJSIP engineer |
| Reviewer | Telephony architect |
| Application | Extension template persistence (`peers.webrtc`) |
| Product designer | Minimal Advanced checkbox only |
| Docker / platform | `libsrtp2` for `res_srtp.so` (media blocker without it) |

## Relationship to TASK-0035A

TASK-0035A owns public signaling:

```text
Client --WSS/TLS--> app:443 /asterisk/ws --plain WS--> asterisk:8088/ws
```

This task owns the endpoint/media contract on top of that path:

```text
WebRTC endpoint (webrtc=yes)
  → DTLS-SRTP media (endpoint lifecycle, NOT the public WSS cert)
  → ICE / AVPF / RTCP-mux (implied by webrtc=yes)
```

Native SIP TLS remains a separate transport/certificate lifecycle.

## Current generation before this task

`Snep_PjsipConf` emitted generic PJSIP endpoint/auth/AOR only:

- codecs from `peers.allow`
- NAT `force_rport` / `rtp_symmetric`
- `direct_media` from form
- AOR `max_contacts=1` + `remove_existing=yes`
- **no** `webrtc=` / DTLS / ICE / AVPF / RTCP-mux

Confast reference (AOR `max_contacts=1` / `remove_existing=yes`, endpoint `webrtc=yes`, `allow=!all,alaw,ulaw`, `dtls_auto_generate_cert=yes`) used as pattern only — not copied blindly.

## Effective Asterisk behavior (`webrtc=yes`)

Asterisk 22.11.0 built-in help (`config show help res_pjsip endpoint webrtc`):

When `webrtc=yes`:

- enables: `rtcp_mux`, `use_avpf`, `ice_support`, `use_received_transport`
- defaults: `media_encryption=dtls`
- defaults: `dtls_auto_generate_cert=yes` (if `dtls_cert_file` unset)
- defaults: `dtls_verify=fingerprint`
- defaults: `dtls_setup=actpass`

Therefore SENMA emits **only** `webrtc=yes` for WebRTC extras (plus forced `direct_media=no`). It does **not** restate implied knobs.

`remove_existing_unavailable` is **not** present on this Asterisk build (`config show help` → no such option). Not added.

## Supported WebRTC endpoint contract

### Persistence / UX

- Column: `peers.webrtc` `TINYINT(1) NOT NULL DEFAULT 0` (migration `0003-webrtc-endpoint-flag`)
- UX: Advanced checkbox **“WebRTC endpoint”** on the existing extension form (not a new template product)
- Server-side: when checked, force `directmedia=no` before persist

### AOR

| Parameter | Value | Why |
|---|---|---|
| `max_contacts` | `1` | Single active WebPhone/browser session (same as all SENMA AORs) |
| `remove_existing` | `yes` | New REGISTER replaces stale contact (proven) |
| `remove_existing_unavailable` | N/A | Not in this Asterisk |
| `qualify_frequency` | from form | Unchanged; smoke uses qualify off to avoid OPTIONS races in WSS test client |

### Endpoint

| Parameter | Value | Why |
|---|---|---|
| `webrtc` | `yes` | High-level WebRTC contract; implies DTLS/ICE/AVPF/RTCP-mux |
| `direct_media` | `no` (forced) | Media must hairpin for DTLS-SRTP |
| `transport` | pin to `wss` (protocol=`ws`) when selected | Maps to private Asterisk WS behind proxy |
| `media_encryption` / `dtls_*` / `ice_support` / `use_avpf` / `rtcp_mux` | **implied** | Not restated |
| `force_rport` / `rtp_symmetric` | from NAT form | Unchanged; ICE primary for WebRTC |
| `rewrite_contact` | omit (default no) | Existing SENMA policy |

### Codec baseline

**Supported WebRTC baseline: `ulaw,alaw` (PCMU/PCMA), optionally `g722`.**

Evidence:

- Browser WebRTC offers PCMU/PCMA/G722/Opus
- Asterisk image **had no `codec_opus` transcoder** (opus listed but no translation paths; `codec_opus.so` absent)
- Confast’s alaw/ulaw-only is therefore a viable browser baseline here
- Smoke defaults WebRTC fixtures to `ulaw;alaw;g722`

**FOLLOW_UP_DEBT:** build/package Opus (`codec_opus`) if product wants Opus-first WebRTC quality.

### DTLS contract

- Owned by endpoint (`webrtc=yes` → `dtls_auto_generate_cert`)
- **Not** coupled to public reverse-proxy WSS certificate renewal
- Requires `res_srtp.so` Running (TASK-0035B image change: `libsrtp2-dev` / `libsrtp2-1`)

Without `res_srtp.so`, INVITE fails with:

```text
SRTP support module is not loaded
Attempted to set an invalid DTLS-SRTP configuration
SIP/2.0 488 Not Acceptable Here
```

### ICE / NAT

- `ice_support` implied by `webrtc=yes`
- Focused media proof ran **on the Docker Compose network** (client ↔ Asterisk ICE candidates reachable)
- Host/dev topology does **not** publish Asterisk RTP by default (`make up`); pilot overlay publishes `10000-10199/udp`
- **No TURN** deployed; not required for the proven topology
- **PILOT_CONSTRAINT:** general internet NAT / symmetric NAT / browser-behind-CGNAT not validated; TURN may become necessary — classify as follow-up if pilot clients need it

### Signaling transport

Unchanged from 0035A:

```text
Client → public WSS (app TLS) /asterisk/ws → private Asterisk WS :8088
```

Asterisk `8088`/`8089` remain unpublished on the host.

## Test client

| Client | Role |
|---|---|
| `docker/wss-test-client` (SIP-over-WSS) | REGISTER / contact / failure cases over public proxy path |
| `docker/webrtc-test-client` (aiortc + SIP-over-WSS) | Real WebRTC SDP offer/answer, ICE, DTLS-SRTP, INVITE |
| `docker/baresip-test` | Normal SIP endpoint for WebRTC → SIP call |

No in-repo SENMA WebPhone product was available; aiortc is the media-capable harness.

## Evidence summary

Focused suite: `make webrtc-endpoint-contract-smoke` / `scripts/webrtc-endpoint-contract-smoke-test.sh`

Observed (non-secret):

- Generated stanza includes `webrtc=yes`, `direct_media=no`, `transport=wss`
- Normal SIP extension has **no** `webrtc=` line
- AOR `max_contacts=1` / `remove_existing=yes`
- Runtime `pjsip show endpoint` reports WebRTC / DTLS / ICE
- Public WSS REGISTER_OK on `/asterisk/ws`
- Second overlapping REGISTER leaves exactly one contact
- Invalid password → no REGISTER_OK; invalid path → no HANDSHAKE_OK
- WebRTC → SIP: `180`/`200`, answer SDP with fingerprint, `pc.state=connected` / `ice=completed`, `MEDIA_OK`

## Changes (implementation)

| Area | Change |
|---|---|
| Migration | `0003-webrtc-endpoint-flag.sql` + `schema.sql` |
| Generator | `Snep_PjsipConf` emits `webrtc=yes`, forces `direct_media=no` |
| Controller / UI | `peers.webrtc` persist + Advanced checkbox |
| Asterisk image | `libsrtp2` so `res_srtp.so` builds/loads |
| Tests | `webrtc-endpoint-contract-smoke` + Makefile/regression wiring |
| Client | `docker/webrtc-test-client` |

## Known constraints

1. **Internet NAT / TURN** not validated (PILOT_CONSTRAINT / FOLLOW_UP_DEBT).
2. **Opus** not in supported baseline (no `codec_opus` in image) — FOLLOW_UP_DEBT.
3. **One automated WebRTC client** (aiortc), not a production WebPhone / multi-browser matrix.
4. **RTP host publish** not part of default `make up`; Docker-network proof used for media.
5. Dev/public WSS still uses fixture/self-signed proxy cert (TASK-0035A operational constraint unchanged).

## Operational recommendations

1. Mark browser extensions WebRTC=yes and pin transport to `wss`.
2. Prefer codecs `ulaw`/`alaw` (add `g722` if desired).
3. Ensure `res_srtp.so` is Running after Asterisk image upgrades.
4. Do not point endpoint DTLS at the public WSS certificate files.
5. For internet clients behind restrictive NAT, plan TURN separately.

## Canonical gates

| Gate | Result |
|---|---|
| `make doctor` | PASS (WARN: fixture public WSS cert — expected) |
| `make secrets-check` | PASS / OVERALL MATCH |
| `make migrate-check` | PASS / SCHEMA_CURRENT (`0003-webrtc-endpoint-flag`) |
| `make reconcile-check` | PASS / IN_SYNC |
| `make lint` | PASS |
| `make regression` #1 | PASS (`EXIT1:0`) |
| `make regression` #2 | PASS (`EXIT2:0`) consecutive, no repair between |
| `git diff --check` | PASS |
| Focused `webrtc-endpoint-contract-smoke` | PASS (31/0) including MEDIA_OK |

## Final decision

**`WEBRTC_CONTRACT_PASS_WITH_CONSTRAINTS`**

Template contract defined; WSS registration works; DTLS-SRTP + ICE connect proven on Docker-network topology; contact replacement proven; normal SIP endpoints unaffected. Constraints: internet NAT/TURN not validated; Opus not packaged; single automated WebRTC client; RTP host publish not default in `make up`.
