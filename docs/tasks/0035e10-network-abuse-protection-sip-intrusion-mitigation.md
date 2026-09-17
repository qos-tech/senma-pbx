# TASK-0035E10 — Network Abuse Protection & SIP Intrusion Mitigation

**Status:** implementation complete — commits authorized after gate PASS
**Decision:** `SIP_ABUSE_PROTECTION_PASS_WITH_CONSTRAINTS`
**Constraint:** `PILOT_SIP_ABUSE_PROTECTION_PROOF_PENDING`
**Does not:** push, tag, deploy, mutate `v0.1.0-rc.10`, touch `tmp-0035a/`, destructive pilot restore

## Final decision

```text
SIP_ABUSE_PROTECTION_PASS_WITH_CONSTRAINTS
```

Constraints:

1. Pilot live SIP abuse proof deferred (`PILOT_SIP_ABUSE_PROTECTION_PROOF_PENDING`).
2. Bridge/dev proves filters + host firewall rule insertion; it does **not**
   claim public SIP enforcement (bridge topology does not publish 5060).
3. Host/kernel lacks usable `xt_multiport`; action uses plain
   `-p tcp|udp --dport 5060` (documented below).
4. TASK-0035E7 remains paused; next RC expected `v0.1.0-rc.11` after merge.

## Host-mode contract (mandatory for pilot/production)

Supported production topology:

| Service | `network_mode` |
|---|---|
| `app` | `host` (via `compose.host.yaml` / `compose.pilot.yaml`) |
| `asterisk` | `host` |
| `db` | `host` |
| `senma-security` | `host` (base `compose.yaml` + re-asserted in host/pilot overlays) |

Reason: direct SIP 5060 reaches the **host** network namespace. Fail2ban must
manipulate that same host firewall namespace. Bridge mode MUST NOT be used for
real pilot/production SIP enforcement and MUST NOT be presented as proof of
host SIP firewall protection.

`DOCKER-USER` does **not** apply: under host networking there is no Docker
DNAT publish path for SIP; packets hit host `INPUT` and are delivered to
Asterisk in the same netns.

## Threat model

| Path | Source IP visibility | Control |
|---|---|---|
| Internet → SIP 5060 TCP/UDP → SENMA host directly | Direct client IP | **This task (Fail2ban)** |
| Internet → HTTPS/WSS → NPM → Apache :8080 | SENMA may see NPM | **E1 login throttle only** — no firewall ban of NPM |

Do **not** ban web users by the SENMA-visible source IP behind NPM.

## Public exposure inventory (unchanged)

Public (pilot):

- SIP 5060/udp, 5060/tcp
- RTP 10000–10199/udp (NAT/firewall — not banned by this service)
- HTTPS/WSS via external NPM only

Loopback-only:

- Asterisk HTTP/WS `127.0.0.1:8088`
- AMI `127.0.0.1:5038`
- MariaDB `127.0.0.1:3306`

This task does not change exposure topology.

## Architecture choice

**Fail2ban** (not CrowdSec) for a single-node PBX:

- Smaller footprint, deterministic jail/filter files in-repo
- Sufficient for REGISTER brute-force / scanner mitigation
- Matches Debian/operator familiarity

Service name: `senma-security`

## Image pinning

```text
crazymax/fail2ban:1.1.1-debian@sha256:d4140e2848f98d600ea104cda982540b6420c164df5d559153e8e873d150e1f5
```

Fail2ban version inside image: **1.1.1**. No `latest`, no curl|sh.

## Network mode & capabilities

| Setting | Value |
|---|---|
| `network_mode` | `host` (**mandatory** pilot/production) |
| `cap_add` | `NET_ADMIN` only |
| `NET_RAW` | **removed** — not required (iptables-nft chain ops work with NET_ADMIN alone; proven live) |
| `privileged` | **no** |
| `docker.sock` | **no** |
| `SYS_ADMIN` | **no** |
| `no-new-privileges` | `true` |

## Firewall backend & packet path

- Host: **iptables-nft** (`iptables v1.8.10 (nf_tables)`), nftables available
- Action creates dedicated chains `f2b-senma-sip-auth` / `f2b-senma-sip-scanner`
- INPUT jumps **only** for `--dport 5060` tcp and udp
- Never flushes INPUT/FORWARD; never `nft flush ruleset`
- Pilot host path: WAN → host INPUT → (f2b jump on 5060) → Asterisk
- Docker `DOCKER-USER` is **not** the SIP path under host networking

## Asterisk log source

| Path | Mount |
|---|---|
| `/var/log/asterisk/full` | `mag-asterisk-log` volume, **read-only** into senma-security |

Logging adequacy (live NOTICE lines already present — no logger.conf change):

```text
res_pjsip/pjsip_distributor.c: Request 'REGISTER' ... failed for 'IP:port' - Failed to authenticate
res_pjsip/pjsip_distributor.c: Request 'REGISTER' ... failed for 'IP:port' - No matching endpoint found
```

`res_security_log.so` is loaded but distributor NOTICE lines are the
authoritative, deterministic source used here.

## Filters & jails

| Filter | Jail | maxretry | findtime | bantime |
|---|---|---|---|---|
| `asterisk-pjsip-auth` | `senma-sip-auth` | 8 | 10m | 30m |
| `asterisk-pjsip-scanner` | `senma-sip-scanner` | 6 | 10m | 30m |

Repeat offender: `bantime.increment=true`, `factor=4`, `maxtime=24h`
(30m → ~2h → … ≤24h). No permanent bans.

Fixtures under `docker/fail2ban/fixtures/` cover positive auth/scanner and
negative outbound/web/startup/malformed lines.

## Allowlist

Default (entrypoint):

- `127.0.0.0/8`, `::1`
- `172.28.0.0/16` — **only** because `compose.yaml` pins
  `networks.mag.ipam.config[0].subnet: 172.28.0.0/16` (project-controlled
  compose network). **Not** retained as blanket RFC1918.
  Not `10.0.0.0/8`, `172.16.0.0/12`, or `192.168.0.0/16`.

Env (static deployment settings, not DNS):

- `SENMA_SECURITY_IGNOREIP` — management hosts
- `SENMA_SIP_PROVIDER_ALLOWLIST` — trunk/provider source IPs/CIDRs

In pilot/host mode, public SIP does not arrive from `172.28/16`; the entry
keeps bridge/dev compose-internal peers in Asterisk logs from being banned
and keeps ignoreip identical across topologies.

## Web / NPM exclusion

No Apache/nginx/login jails. E1 remains the web brute-force control.
Documented boundary: never ban `10.60.20.20` (example NPM) for app logins.

## RTP safety

Ban action does not reference RTP 10000–10199. SIP-only.

## IPv4 / IPv6

Filters use fail2ban `<HOST>` (IPv4 + IPv6). Ban action uses iptables for
IPv4; IPv6 public SIP is not part of the current supported pilot topology
(documented). `allowipv6=auto` remains in stock fail2ban.conf.

## Persistence

| Event | Behavior |
|---|---|
| Container restart | Jails reload from repo mounts; sqlite under `senma-fail2ban-data` |
| Active bans | Persist in fail2ban db for the configured bantime while volume survives |
| Host reboot | Chains recreated on jail start when bans are re-applied from db |
| Config | Always from repository (`docker/fail2ban/`); never hand-edited in container |

## Fail-open telephony

```text
SECURITY_FAIL_OPEN_TELEPHONY
```

Asterisk has **no** `depends_on: senma-security`. Security down → doctor **WARN**,
Asterisk continues.

## Operator commands

```bash
make security-status
make security-bans
make security-unban IP=x.x.x.x
make security-reload
```

All depend on `require-runtime` (no build). Fail clearly if service absent.

### `security-unban` input safety

`make security-unban` delegates to `scripts/security-unban.sh`, which reads the
Make command-line `IP` from the process environment (GNU Make exports cmdline
vars without interpolating them into unquoted recipe text) and validates with
Python `ipaddress.ip_address()` before any `docker exec`. Injection examples
(`1.2.3.4;id`, `$(id)`, backticks, `&&`, `|`) are rejected.

## Doctor

Check name: `SIP abuse protection` — PASS when jails loaded; **WARN** when
service down (does not imply Asterisk down).

## Resource limits

`mem_limit: 128m`, `cpus: 0.25`, logging `*senma-default-logging`.

## Dev vs pilot

| Mode | Proof |
|---|---|
| Bridge/dev | Filters, jail load, host iptables rule insert/remove |
| Pilot/host | Required for real public SIP enforcement — pending |

**BRIDGE-MODE TESTS DO NOT PROVE REAL FIREWALL ENFORCEMENT.**

## Validation (checkpoint)

| Gate | Result |
|---|---|
| `make sip-abuse-protection-smoke` | **PASS** (30/30) |
| `make host-networking-architecture-smoke` | **PASS** |
| `make auth-hardening-security-smoke` | **PASS** |
| `make release-immutability-smoke` | **PASS** |
| `make doctor-smoke` | **PASS** |
| `make backup-smoke` | **PASS** |
| `make recording-storage-smoke` | **PASS** |
| `make admin-bootstrap-smoke` | **PASS** |
| `make lint` | **PASS** |
| `make regression` (run 1) | **PASS** |
| `make regression` (run 2) | **PASS** |
| `git diff --check` | **PASS** |

Pre-commit evidence: `/tmp/e10-precommit-focused.log`, `/tmp/e10-precommit-regression.log`.

## Pilot plan

```text
PILOT_SIP_ABUSE_PROTECTION_PROOF_PENDING
```

Future authorized pilot proof **must** run with `senma-security` /
`network_mode: host` and confirm: controlled failed REGISTER → threshold ban
→ SIP-only host INPUT block → unban → security stop leaves Asterisk healthy →
no NPM collateral.

---

## TASK-0035E10-R1 — Pilot startup regression

**Status:** fix implemented — awaiting checkpoint authorization (no commit yet)
**Decision candidate:** `PILOT_STARTUP_SECURITY_PASS`
**Does not:** retag/rebuild `v0.1.0-rc.11`, create `v0.1.0-rc.12`, deploy, resume E7

### Pilot evidence (TEXTE-PBX-001 / rc.11)

`make pilot-up` executed:

```text
docker compose -f compose.yaml -f compose.pilot.yaml \
  up -d --no-build app asterisk db
```

and **omitted** `senma-security`. Operators had to start it manually:

```text
docker compose -f compose.yaml -f compose.pilot.yaml \
  up -d --no-build senma-security
```

After manual start: healthy, host network, `CAP_NET_ADMIN` only, jails loaded,
real Internet attacks banned, firewall enforcement PASS, unban PASS,
fail-open PASS. Runtime implementation was correct; **orchestration was incomplete**.

### Root cause

`Makefile` `pilot-up` hardcodes an explicit service list that predated E10:

```text
up -d --no-build app asterisk db
```

`make up` with empty `SERVICES` already started `senma-security` (no Compose
profile gate). Only the pilot path omitted it.

### Corrected contract

Canonical pilot/production startup set:

- `app`
- `asterisk`
- `db`
- `senma-security`

Fail-open distinction preserved:

- Asterisk has **no** `depends_on: senma-security`
- `require-runtime` still requires only app/asterisk/db (ops remain usable if security is down; doctor WARNs)
- `pilot-up` **must** still start `senma-security` (orchestration inclusion ≠ hard dependency)

Also added:

- `make pilot-down` — stops the same four services with the same compose files
- restore stop/start includes `senma-security` (best-effort start; fail-open warning)
- host topology verify inspects `senma-security` when present

### Validation (E10-R1)

| Gate | Result |
|---|---|
| `make doctor-smoke` | **PASS** |
| `make sip-abuse-protection-smoke` | **PASS** (31/31; includes pilot-up service-set check) |
| `make host-networking-architecture-smoke` | **PASS** |
| `make release-immutability-smoke` | **PASS** (includes 2b pilot-up/pilot-down) |
| `make lint` | **PASS** |
| `make regression` A | **PASS** |
| `make regression` B | **PASS** |
| `git diff --check` | **PASS** |

Evidence: `/tmp/e10r1-clean-validation.log` (`E10R1_CLEAN_DONE`).

Earlier interrupted suite had unrelated failures (trailing whitespace in this doc — fixed; doctor DRIFT from stale `release-manifest.json` after rc.11 build — removed; transport-smoke AUTO endpoint load flake — passed on consecutive clean runs without repair).

- `v0.1.0-rc.11` remains **immutable** (do not retag/rebuild under the same version)
- Next candidate after this fix merges: **`v0.1.0-rc.12`** (not created in this task)
- TASK-0035E7 remains **paused**; do not close pilot on rc.11 as final

### E7 / release

E7 paused. After E10 merge: next RC `v0.1.0-rc.11` (do not mutate rc.10).
After E10-R1 merge: next candidate **`v0.1.0-rc.12`** (do not mutate rc.11).

## Proposed commit split (E10 original)

1. `feat(security): add SIP abuse protection service`
2. `test(security): cover fail2ban filters and firewall actions`
3. `ops(security): add status and unban commands`
4. `docs(security): record TASK-0035E10 closure`

## Proposed commit split (E10-R1)

1. `fix(ops): include security in pilot startup`
2. `test(ops): cover full pilot service set`
3. `docs(security): record E10 pilot startup regression`
