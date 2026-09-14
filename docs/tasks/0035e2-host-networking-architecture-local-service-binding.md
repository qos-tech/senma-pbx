# TASK-0035E2 — Host Networking Architecture & Local Service Binding

## Status

**Final decision: `HOST_NETWORKING_ARCHITECTURE_PASS_WITH_CONSTRAINTS`**

Constraints:

- Real dedicated pilot host (`10.60.40.40`) migration / SIP / WebRTC /
  bidirectional media proofs are **`NOT_RUN`** from this Cursor
  pre-pilot agent (bridge stack is the regression authority here).
- Release tag creation (`v0.1.0-rc.4` / next RC) is **not** authorized
  by this task; do not mutate `v0.1.0-rc.3`.
- Live `ss -lntup` host-mode binding proof on a dedicated Linux pilot
  remains operator-gated (`HOST_NETWORK_RUNTIME=1` / migration plan).

## Architecture decision

**Model B:**

```text
bridge = dev/regression
host networking = pilot/production Linux
```

| Mode | Compose | Audience |
|---|---|---|
| Bridge + service DNS | `compose.yaml` | Dev / `make regression` |
| Linux host networking | `compose.yaml` + `compose.host.yaml` (`compose.pilot.yaml` alias) | Pilot / production on a dedicated PBX host |

Assumption: SENMA runs on a dedicated Linux PBX host; core runtime
services (`app`, `asterisk`, `db`) share the host network namespace.
Docker Desktop (macOS/Windows) is **not** an equivalent host-network
runtime.

## Target topology

```text
Dedicated SENMA PBX host
10.60.40.40

app / Apache
  HTTP backend        0.0.0.0:8080
Asterisk
  SIP UDP/TCP         0.0.0.0:5060
  RTP                 0.0.0.0:10000-10199
  HTTP/WS             127.0.0.1:8088
  AMI                 127.0.0.1:5038
MariaDB
  DB                  127.0.0.1:3306

Internal:
  app -> DB            127.0.0.1:3306
  app -> AMI           127.0.0.1:5038
  Apache -> Asterisk   ws://127.0.0.1:8088/ws

External:
  client -> NPM :443 -> http://10.60.40.40:8080 -> /asterisk/ws
  SIP/RTP via cloud NAT 45.231.134.104 <-> 10.60.40.40
```

## Configuration contract

| Variable | Host-mode value | Notes |
|---|---|---|
| `SENMA_NETWORK_MODE` | `host` | set by compose overlay |
| `TLS_TERMINATION_MODE` | `external` (pilot default in overlay) | closes I6 |
| `DB_HOST` | `127.0.0.1` | overrides `.env` `db` |
| `ASTERISK_HOST` | `127.0.0.1` | replaces `senma-ami` |
| `ASTERISK_AMI_ACL_SUBNET` | `127.0.0.1/32` | loopback ACL |
| `ASTERISK_HTTP_BIND` | `127.0.0.1` | WS loopback |
| `ASTERISK_AMI_BIND` | `127.0.0.1` | AMI loopback |
| `APACHE_HTTP_PORT` | `8080` | host listen |
| `ASTERISK_WS_BACKEND` | `ws://127.0.0.1:8088/ws` | ProxyPass target |
| `PJSIP_EXTERNAL_*` / `PJSIP_LOCAL_NET` | operator | optional NAT overrides |

Pilot NAT example (never hard-coded in PHP):

```text
PJSIP_EXTERNAL_SIGNALING_ADDRESS=45.231.134.104
PJSIP_EXTERNAL_MEDIA_ADDRESS=45.231.134.104
PJSIP_LOCAL_NET=10.60.40.0/24
```

Trusted proxy (0035E1) remains:

```text
TRUSTED_PROXY_CIDRS=10.60.20.20/32
```

## Security exposure model

LAN/public (intentionally):

```text
8080/tcp, 5060/tcp, 5060/udp, 10000-10199/udp
```

Loopback only:

```text
3306/tcp, 5038/tcp, 8088/tcp
```

Host/cloud firewall remains defense-in-depth. Docker `ports:` is no
longer the pilot exposure boundary.

## I6 / I5 / I7 / I4

```text
I4 OPEN

I5 IMPLEMENTATION_CLOSED
I5 PILOT_RUNTIME_PROOF_PENDING

I6 IMPLEMENTATION_CLOSED
I6 PILOT_RUNTIME_PROOF_PENDING

I7 IMPLEMENTATION_CLOSED
I7 PILOT_RUNTIME_PROOF_PENDING
```

| ID | Status | Notes |
|---|---|---|
| I4 | OPEN | avoid `--build` over immutable release tags |
| I5 | **IMPLEMENTATION_CLOSED** (external mode) | `TLS_TERMINATION_MODE=external` + cert-check public endpoint; local fixture not pilot-blocking |
| I5 | **PILOT_RUNTIME_PROOF_PENDING** | real NPM public cert/SAN not proven here |
| I6 | **IMPLEMENTATION_CLOSED** | `/asterisk/ws` on HTTP vhost; external TLS mode |
| I6 | **PILOT_RUNTIME_PROOF_PENDING** | NPM → :8080 WSS 101 on real pilot |
| I7 | IMPLEMENTATION_CLOSED / PILOT_RUNTIME_PROOF_PENDING | unchanged from 0035E1 |

## Operator migration plan (real pilot)

1. `make backup`
2. Stop bridge stack (`docker compose down` — keep volumes)
3. Set `.env`: `TLS_TERMINATION_MODE=external`, NAT vars, `TRUSTED_PROXY_CIDRS`, `WSS_PUBLIC_HOSTNAME`
4. Deploy new RC images (do **not** mutate `v0.1.0-rc.3`)
5. `make pilot-up` (host overlay)
6. Verify `ss -lntup` exposure model
7. `make migrate-check secrets-check reconcile-check doctor`
8. NPM → `http://10.60.40.40:8080`; prove HTTPS 200 + WSS 101
9. SIP REGISTER / WebRTC REGISTER / calls
10. Rollback: `docker compose -f compose.yaml up -d` (bridge) with prior release images + restore backup if needed

## Validation

Focused: `make host-networking-architecture-smoke` (static Model B proofs).

**Live host-network binding proof (this Linux agent, 2026-09-14):**

After `compose.yaml` + `compose.host.yaml` up:

```text
ss -lntp:
  127.0.0.1:3306  MariaDB
  127.0.0.1:5038  AMI
  127.0.0.1:8088  Asterisk HTTP/WS
  *:8080          Apache HTTP
  0.0.0.0:5060    SIP TCP
ss -lunp:
  0.0.0.0:5060    SIP UDP
rtp.conf / `rtp show settings`: 10000-10199
HTTP / → 200 (SNEP Login)
HTTP /asterisk/ws WebSocket upgrade → 101
```

Dedicated pilot host (`10.60.40.40`) NPM / SIP / WebRTC media proofs remain
**NOT_RUN**.

Canonical gates run against the **bridge** development topology (same
Git revision) so regression remains authoritative after restoring
Model B default `compose.yaml`.

## Files

- `compose.host.yaml`, `compose.pilot.yaml` (alias)
- `docker/mariadb-host.cnf`
- `docker/apache-mag.conf`, `docker/entrypoint.sh`, `docker/app.Dockerfile`
- `docker/asterisk-entrypoint.sh`, `docker/asterisk-config/http.conf`
- `docker/healthcheck-app.sh`, `docker/healthcheck-asterisk.sh`
- `docker/apply-pjsip-nat-from-env.php`
- `scripts/wss-cert-check.sh`, `scripts/doctor.sh`
- `scripts/host-networking-architecture-smoke-test.sh`
- `.env.example`, Makefile, regression.sh
- ops docs + this file
