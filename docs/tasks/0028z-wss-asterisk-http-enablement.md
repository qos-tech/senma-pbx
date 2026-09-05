# TASK-0028Z — WSS / Asterisk HTTP transport enablement

Status: Resolved. Two consecutive full `make regression` PASS runs (27/27
each, including the new `wss-platform-smoke` suite), `make lint` PASS,
`git diff --check` PASS. Not committed — awaiting authorization per
CLAUDE.md's commit policy.

Lead: `senma-docker-platform-engineer`. Reviewer: `senma-telephony-architect`
(termination-model decision, invariant review).

## Objective

TASK-0028W (PJSIP Completeness Architecture Review) classified the
product's WSS transport as `BROKEN, live-confirmed`: WSS was selectable
and persistable in the SENMA transport UI, and Asterisk showed the
transport object as loaded, but the underlying WebSocket HTTP endpoint
did not exist at all. This task makes the currently-exposed WSS
transport actually operational at the platform/runtime layer, without
pulling in full certificate lifecycle management (TASK-0029A).

## CURRENT BROKEN STATE

Reproduced live, before any change, against the running `make dev`
environment:

```
$ docker compose exec asterisk asterisk -rx 'http show status'
HTTP Server Status:
Prefix:
Server:
Server Disabled

Enabled URI's:
/media/... => Media over Websocket
/ws => Asterisk HTTP WebSocket
...

$ docker compose exec asterisk asterisk -rx 'pjsip show transport wss'
Transport:  wss                       wss      0      0  0.0.0.0:8089
 ... cert_file: (empty) priv_key_file: (empty) ...

$ docker compose exec asterisk bash -c "ls -la /etc/asterisk/http.conf"
ls: cannot access '/etc/asterisk/http.conf': No such file or directory

$ docker compose exec app curl -sv --max-time 2 http://asterisk:8088/ws
* connect to 172.28.0.2 port 8088 from ... failed: Connection refused
```

`module show like websocket`/`module show like http` already showed
`res_http_websocket.so`, `res_pjsip_transport_websocket.so`, and the
built-in `http` module all `Running` — the WebSocket machinery was fully
loaded, just with no listening socket behind it.

## ROOT CAUSE

`/etc/asterisk/http.conf` never existed in this Docker topology.
`docker/asterisk-config/` (the static, project-owned Asterisk config
seeded into the persistent `asterisk-etc` volume on first boot by
`docker/asterisk-entrypoint.sh`) never included an `http.conf` — it was
never part of TASK-0005's original minimal Docker bootstrap scope, and
no later task added it before now. With no `http.conf`, Asterisk's
built-in HTTP server defaults to fully disabled (`enabled=no`), which
also disables the TLS/WSS listener the PJSIP `wss` transport
(`res_pjsip_transport_websocket.so`) depends on to accept any connection
at all. The PJSIP transport object itself (`pjsip show transport wss`)
is declarative config the PJSIP layer holds independently of whether the
HTTP server that must actually carry it is running — which is exactly
why it could show as "loaded" while being completely unreachable.

**First divergence:** `WSS configured` (pjsip_transports row, PJSIP
transport object loaded) vs. `WebSocket service operational` (a real
listening socket behind `/ws`) diverge at `/etc/asterisk/http.conf`'s
non-existence — one config file away from full function, not a deeper
architectural gap.

## TERMINATION MODEL DECISION

**Chosen: (A) TLS terminates directly in Asterisk.**

Considered and rejected:

- **(B) TLS terminates upstream, Asterisk receives plain WS internally.**
  Rejected: no reverse proxy exists anywhere in this project's Docker
  topology (`compose.yaml` has exactly `app`/`db`/`asterisk`/`provider`),
  and introducing one is explicitly out of this task's scope
  ("reverse-proxy redesign unless required"). Terminating TLS upstream
  would also mean the PJSIP transport itself becomes plain `ws`, which
  is a silent downgrade of a user-selected "wss" transport's own
  security meaning — the task explicitly forbids this without an
  enforced, documented boundary, and no such boundary is being built
  here.

Justification for (A):

- The product's already-seeded `pjsip_transports` "wss" row
  (`protocol=wss, bind=0.0.0.0:8089`, seeded by TASK-0018) already
  targets Asterisk's own conventional TLS-WebSocket port. Nothing about
  the existing data model needed to change.
- No reverse proxy exists to terminate TLS instead, and building one is
  out of scope.
- This preserves the product's own contract: a user who selects "wss"
  gets an endpoint that actually terminates TLS, not one silently
  downgraded to plain WS at the platform layer.
- Asterisk's `[general]` `enabled` switch is the single master switch for
  the whole built-in HTTP server; it cannot expose the TLS/WSS listener
  without also technically activating the plain listener (see Security
  Boundary below) — this is an Asterisk-native constraint, not a
  decision made here, and is handled by binding the plain listener to
  loopback only.

## CONFIG OWNERSHIP

`http.conf`: **PLATFORM_GENERATED / FIRST_BOOT_SEED** — the identical
classification and mechanism already used for every other file in
`docker/asterisk-config/*.conf` (`asterisk.conf`, `manager.conf`,
`modules.conf`, `pjsip.conf`, etc.): a static, project-owned source
bind-mounted read-only into the container, copied into the persistent
`asterisk-etc` named volume exactly once by
`docker/asterisk-entrypoint.sh`, and never touched again afterward
(Asterisk/an operator may edit it in place from then on, same as every
sibling file). This is the project's one existing config-lifecycle
pattern for Asterisk static config — reused as-is, not duplicated.

The TLS certificate/key pair
(`/etc/asterisk/keys/wss-test-cert.pem`/`wss-test-key.pem`): also
**FIRST_BOOT_SEED**, but generated at runtime (via `openssl`, already
present in the runtime image) rather than copied from a static source —
a real private key must never be committed to git or baked into an
image. Both files carry an explicit `wss-test-` prefix and an inline
comment marking them TEST-ONLY. See TASK-0029A boundary below.

Both are guarded by their own independent first-boot check
(`[ ! -f ... ]`), separate from the pre-existing
`[ ! -f "$ASTERISK_ETC/asterisk.conf" ]` guard — a dev volume created
before this task already has `asterisk.conf` populated, so the original
guard alone would never fire again on it and it would never receive
`http.conf`/the TLS fixture at all. Verified live: this exact case (this
project's own pre-existing dev volume) received both on its next start
with zero disruption to its existing config.

## PLATFORM CHANGES

**PLATFORM:**
- `docker/asterisk-entrypoint.sh` — two new independent first-boot
  guards: (1) generates a self-signed TEST-ONLY TLS certificate/key pair
  into `/etc/asterisk/keys/` via `openssl req -x509 -newkey rsa:2048
  -nodes ... -days 3650`; (2) seeds `http.conf` from
  `docker/asterisk-config/http.conf` independently of the main
  first-boot block, so an existing dev volume converges too. No changes
  to the pre-existing `asterisk.conf`-gated block.
- `Makefile` — new `wss-platform-smoke` target (`up` dependency, same
  pattern as every other smoke target) and `.PHONY` entry.
- `scripts/regression.sh` — `wss-platform-smoke` wired in right after
  `pjsip-lifecycle-smoke` and before `transport-smoke`.

**ASTERISK CONFIG:**
- `docker/asterisk-config/http.conf` (new) — `[general] enabled=yes`;
  plain listener `bindaddr=127.0.0.1 bindport=8088` (loopback-only, see
  Security Boundary); `tlsenable=yes tlsbindaddr=0.0.0.0:8089` (matches
  the existing seeded `wss` transport's own bind exactly);
  `tlscertfile`/`tlsprivatekey` pointing at the generated TEST-ONLY
  fixture. No `modules.conf`/`manager.conf` changes — `autoload=yes`
  already loads the built-in HTTP server and both websocket modules; no
  `webenabled` anywhere, so this change does not expose AMI-over-HTTP.

**TEST:**
- `scripts/wss-platform-smoke-test.sh` (new) — see Regression Proof.
- `docker/wss-test-client.Dockerfile` + `docker/wss-test-client/wss_sip_register.py`
  (new) — a minimal, standard-library-only (no pip installs, no network
  access needed at build or run time) SIP-over-WebSocket (RFC 7118)
  client: real TLS handshake, real WebSocket upgrade at `/ws` negotiating
  the `sip` subprotocol, and an optional full SIP REGISTER transaction
  including a digest-auth round trip. Built because no existing test
  client speaks this protocol — `docker/baresip-test`'s baresip binary
  has no SIP-over-WebSocket transport compiled in at all (confirmed: no
  `ws`/`websocket` strings anywhere in the shipped Debian binary).

**DOCUMENTATION:**
- This file.

## RUNTIME PROOF

After the change, live against the same environment:

```
$ docker compose exec asterisk asterisk -rx 'http show status'
HTTP Server Status:
Prefix:
Server: Asterisk/22.11.0
Server Enabled and Bound to 127.0.0.1:8088

HTTPS Server Enabled and Bound to 0.0.0.0:8089

Enabled URI's:
/media/... => Media over Websocket
/ws => Asterisk HTTP WebSocket
...

$ docker compose exec asterisk bash -c "ls -la /etc/asterisk/keys/"
-rw-r--r-- 1 asterisk asterisk 1172 ... wss-test-cert.pem
-rw------- 1 asterisk asterisk 1704 ... wss-test-key.pem
```

Real client proof (`docker/wss-test-client`, run as a disposable
container on the same Docker network as `asterisk`, matching
`call-smoke-test.sh`'s own baresip convention):

```
TLS_OK TLSv1.3 ('TLS_AES_256_GCM_SHA384', 'TLSv1.3', 256)
UPGRADE RESPONSE:
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: ...
Sec-WebSocket-Protocol: sip
HANDSHAKE_OK
--- sending REGISTER #1 (unauthenticated) ---
SIP RESPONSE: SIP/2.0 401 Unauthorized
--- sending REGISTER #2 (authenticated) ---
SIP RESPONSE: SIP/2.0 200 OK
REGISTER_OK
```

...against a real SENMA-provisioned PJSIP extension pinned to the "wss"
transport via the existing `transport_id` selector, with Asterisk's own
runtime independently confirming the live contact while the WebSocket
session was held open:

```
$ docker compose exec asterisk asterisk -rx 'pjsip show contacts'
  Contact:  1196/sip:1196@172.28.0.6:...;transport=ws;x-... ... NonQual  nan
```

...and confirming the contact disappears once the WebSocket session
ends — the correct, expected lifecycle for a transport-bound WS contact
(Asterisk has no other path back to a WS client once its one connection
closes), not a defect:

```
$ docker compose exec asterisk asterisk -rx 'pjsip show contacts'
(no 1196/... row)
```

This is the full preferred proof chain: client → TLS/WSS handshake →
`/ws` → SIP over WebSocket → real PJSIP registration, all against the
product's own real HTTP-provisioned extension and real Asterisk runtime
— no TASK-0029A blocker was hit; the self-signed test certificate
generated above was sufficient to prove the platform contract end to
end.

## RESTART/RECREATE PROOF

```
$ docker compose restart asterisk
 Container mag-pbx-asterisk-1 Restarting
 Container mag-pbx-asterisk-1 Started
```
→ container reports `healthy` again; `http show status` shows the HTTPS
listener enabled again; `pjsip show transport wss` bound to
`0.0.0.0:8089` again; a fresh real TLS+WebSocket handshake succeeds.

```
$ docker compose up -d --force-recreate asterisk
 Container mag-pbx-asterisk-1 Recreate
 Container mag-pbx-asterisk-1 Recreated
 Container mag-pbx-asterisk-1 Started
```
→ same four checks pass again after a full container recreation (a new
container, same named volume).

Persistence, not just re-convergence, was explicitly proven by hashing
both fixtures before and after both operations:

```
TLS cert identity preserved   sha256 unchanged across restart+recreate
                               (d8f2570263311a788cef3b9dd91f0e6cc2b600ae7efa41ba444822c3d76ebaf9)
http.conf preserved           sha256 unchanged across restart+recreate
                               (aec60e0a8ea421fb7dee5f239c42ca8f2097aab0ba2170985bf03ed5c5b3b215)
```

The certificate is generated exactly once and never regenerated by a
restart or recreate — an operational requirement for any real WSS client
that might otherwise need to re-trust a rotating fixture on every
container cycle.

## SECURITY BOUNDARY

- **Bind scope:** the TLS/WSS listener binds `0.0.0.0:8089` (required —
  it must be reachable by real WebSocket clients on the Docker network,
  and matches the product's own pre-existing `wss` transport row
  exactly). The plain (non-TLS) HTTP/WS listener Asterisk's own
  `[general] enabled` switch cannot avoid also turning on is bound to
  `127.0.0.1` only — confirmed live unreachable from another container
  on the same network (`app` → `asterisk:8088`: connection refused). The
  product exposes/supports "wss" only; no `ws` (plain) transport row is
  seeded, so nothing in the current product needs the plain listener
  reachable from anywhere.
- **No unnecessary HTTP surface:** `http show status`'s "Enabled URI's"
  lists exactly `/media/...` (Media over Websocket) and `/ws` (the PJSIP
  websocket transport) — both already registered by modules that were
  already `Running` before this task; nothing new was added. No
  AMI-over-HTTP: `manager.conf` carries no `webenabled` (and never did).
- **Port exposure:** no new port publishing to the host. Every consumer
  proven in this task's own regression suite is another container on the
  same Docker network (matching the project's existing convention: no
  SIP port at all — UDP or TCP — is currently published to the host
  either; `call-smoke-test.sh`'s baresip fixtures already run as
  disposable containers on the same internal network, not from the
  host). A real browser-facing WebRTC deployment would need its own
  explicit host/reverse-proxy exposure decision later — that is a
  distinct, separate decision from "is the platform operational," which
  is this task's actual scope, and is not made here.
- **No secrets in config/git:** `docker/asterisk-config/http.conf` (the
  only new file committed to git) contains no key material, only fixed
  paths to a runtime-generated file. The private key itself
  (`wss-test-key.pem`) is generated at container first boot directly
  into the persistent volume, mode `0600`, and is never written to git,
  never baked into any image layer.

## TASK-0029A REMAINING BOUNDARY

This task deliberately stops at proving the WSS **platform** path is
operational using a temporary, self-signed, TEST-ONLY certificate. It
does **not** build any part of the real certificate-management product
contract. Left entirely for TASK-0029A:

- customer-supplied certificate upload/management UI;
- CA configuration (public CA, private/internal CA, or a customer's own
  chain);
- certificate rotation (this task's fixture is generated once, at first
  boot, and never rotates — acceptable for a dev/test fixture, not for a
  production certificate lifecycle);
- any schema for storing/referencing certificate material (none exists
  today — `pjsip_transports` has no `cert_file`/`priv_key_file`/
  `ca_list_file` columns at all, confirmed against
  `snep/install/database/schema.sql`);
- real client trust validation — this task's own test client
  (`wss_sip_register.py`) deliberately uses `ssl.CERT_NONE` since the
  fixture certificate is self-signed and test-only; a real browser/
  WebRTC client would (correctly) refuse to trust it as-is.

None of the above blocks WSS from being genuinely operational today: the
full client → TLS/WSS handshake → `/ws` → SIP-over-WebSocket → PJSIP
registration chain was proven live and real, end to end, in this task,
using a test-only certificate this task generated itself. The remaining
work is a distinct, larger product surface (real certificate lifecycle),
not a blocker to calling this task's own contract complete.

## REGRESSION PROOF

New suite `scripts/wss-platform-smoke-test.sh`, run standalone twice
consecutively for idempotency: **28/28 PASS both times.** Covers
(Phase 8's checklist, each with a distinct check):

1. `http.conf` exists in the runtime config path;
2. TLS cert/key fixture exists with correct permissions;
3. Asterisk HTTP server reports enabled (plain + TLS, exact bind
   addresses);
4. `/ws` is registered and a real TLS+WebSocket handshake to it
   succeeds;
5. the PJSIP `wss` transport remains loaded, correct bind;
6. no accidental `chan_sip` dependency introduced;
7. the plain HTTP/WS listener is confirmed unreachable from another
   container (minimal-exposure proof);
8. a real end-to-end SIP REGISTER over WSS against a real
   SENMA-provisioned extension, with Asterisk's own live contact list as
   independent proof, plus the extension's full create/generated-config/
   delete-cleanup lifecycle through the real HTTP flow;
9. `docker compose restart asterisk` and
   `docker compose up -d --force-recreate asterisk` both converge to the
   same ready state, with the TLS cert's and `http.conf`'s own identity
   (sha256) proven unchanged across both operations.

Affected pre-existing suites re-run individually, no regressions:
`transport-smoke` (64/64 PASS), `pjsip-lifecycle-smoke` (36/36 PASS),
`call-smoke` (18/18 PASS).

`make lint`: PASS (5/5 checks — 270 PHP files 0 syntax errors, 34 shell
scripts parse cleanly (including the two new ones), 3 `resources.xml`
files well-formed, clean `git diff --check`).

`make regression` run 1: **PASS, 27/27 suites** (including
`wss-platform-smoke`). `make regression` run 2: **PASS, 27/27 suites**
(identical matrix). `git diff --check`: PASS, no whitespace errors.

`git status --short` at the time of this report:

```
 M Makefile
 M docker/asterisk-entrypoint.sh
 M scripts/regression.sh
?? docker/asterisk-config/http.conf
?? docker/wss-test-client.Dockerfile
?? docker/wss-test-client/
?? scripts/wss-platform-smoke-test.sh
```

Not committed — awaiting authorization per CLAUDE.md's commit policy.
