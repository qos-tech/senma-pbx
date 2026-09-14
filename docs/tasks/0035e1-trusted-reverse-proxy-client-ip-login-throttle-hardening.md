# TASK-0035E1 — Trusted Reverse Proxy Client IP & Login Throttle Hardening

## Status

**IMPLEMENTATION COMPLETE — commit-authorized**

**Final decision: `TRUSTED_PROXY_CLIENT_IP_PASS_WITH_CONSTRAINTS`**

Constraints:

- Real NPM pilot runtime proof (distinct public clients writing distinct
  `login_attempts.ip_address` rows through live Apache) is **`NOT_RUN`**
  on this Cursor pre-pilot host — no NPM hop here.
- Release tag `v0.1.0-rc.4` is **not** created (await explicit
  authorization; do not mutate `v0.1.0-rc.3`).
- I4/I5/I6 remain open follow-up debt.
- I7 code path is closed; live pilot attribution proof remains pending:

```text
I7 IMPLEMENTATION_CLOSED
I7 PILOT_RUNTIME_PROOF_PENDING
```

## Problem

Observed real-pilot topology:

```text
client → NPM 10.60.20.20 → SENMA app
REMOTE_ADDR=10.60.20.20
X_REAL_IP=<real client>
X_FORWARDED_FOR=<real client>
```

`AuthController::loginAction()` previously keyed
`Snep_Security_LoginThrottle` on `$_SERVER['REMOTE_ADDR']` alone. Every
browser behind NPM shared one throttle source IP, so one abusive client
could push the shared per-IP bucket (`MAX_FAILURES_PER_IP = 20`) and
throttle unrelated users.

## Threat model

| Actor | Capability | Required outcome |
|---|---|---|
| Direct / untrusted client | Can send arbitrary `X-Forwarded-For` / `X-Real-IP` / `Forwarded` | Must **not** choose throttle identity; identity = `REMOTE_ADDR` |
| Trusted reverse proxy (CIDR in `TRUSTED_PROXY_CIDRS`) | Sets real client into XFF / X-Real-IP | Throttle identity = real client IP |
| Misconfigured trust-all (`0.0.0.0/0`) | Would open header spoofing | Rejected / ignored by parser |
| Attacker controlling leftmost XFF before a correctly appending proxy | Spoofed left hops | Right-to-left trusted-hop walk skips trusted proxies and returns the first untrusted hop |

Trusted proxies are a **security boundary**. If
`TRUSTED_PROXY_CIDRS=10.60.20.20/32`, direct HTTP access to the SENMA
backend should ideally be limited to that proxy/network (operational
guidance — host firewall not changed in this task).

## Trusted proxy contract

Single helper: `Snep_Security_ClientIp`
(`snep/lib/Snep/Security/ClientIp.php`).

- Reusable by future rate-limit / audit callers.
- Never embed ad-hoc XFF parsing in `AuthController`.
- Do **not** use `Zend_Controller_Request_Http::getClientIp()` (trusts
  forwarding headers unconditionally).

## Configuration contract

| Variable | Default | Meaning |
|---|---|---|
| `TRUSTED_PROXY_CIDRS` | empty | Comma-separated CIDRs of proxies allowed to supply client IP |

Examples:

```text
TRUSTED_PROXY_CIDRS=
TRUSTED_PROXY_CIDRS=10.60.20.20/32
TRUSTED_PROXY_CIDRS=10.60.20.20/32,10.60.30.0/24
```

Rules:

- Absent/empty → current direct-client behavior (`REMOTE_ADDR` only).
- Bare addresses normalized to `/32` or `/128`.
- `0.0.0.0/0`, `::/0`, and any `/0` rejected (fail-safe: no trust).
- Invalid entries ignored with a generic `error_log` line (no full env dump).
- Documented in `.env.example`; delivered via Compose `env_file: .env`.
- No hard-coded `10.60.20.20` in PHP or Compose.

Pilot required value (operator-side):

```text
TRUSTED_PROXY_CIDRS=10.60.20.20/32
```

## Client IP resolution algorithm

```text
remote = REMOTE_ADDR (validated IP) else "unknown"

if remote not in TRUSTED_PROXY_CIDRS:
    return remote

# remote IS trusted:
from X-Forwarded-For (validated hops only):
    walk right → left
    skip hops that are also in TRUSTED_PROXY_CIDRS
    return first remaining valid IP
else if X-Real-IP is a valid IP:
    return X-Real-IP
else:
    return remote
```

`Forwarded` (RFC 7239) is intentionally ignored in this task.

## XFF chain semantics

Scoped to trusted-hop semantics for the one-proxy pilot topology
`client → trusted NPM → SENMA`:

- NPM sets a single client address → that address is returned.
- If a trusted proxy **appends** (`spoofed, client`), the rightmost
  untrusted hop is the client.
- Entirely malformed XFF → fall through to X-Real-IP, else `REMOTE_ADDR`.

## Spoofing protection

```text
REMOTE_ADDR=203.0.113.10
X-Forwarded-For=1.2.3.4
TRUSTED_PROXY_CIDRS= (empty)
→ 203.0.113.10
```

Proven in unit matrix (case B) and HTTP smoke (spoof headers present;
`login_attempts.ip_address` is not the attacker-chosen value).

## Throttle semantics (unchanged)

```text
MAX_FAILURES_PER_ACCOUNT = 5
MAX_FAILURES_PER_IP      = 20
WINDOW_MINUTES           = 15
```

Still keyed by `(username, resolved client IP)` and by resolved client
IP alone. Success still clears only that `(username, client-ip)` pair.

## AuthController change

Replaced only:

```php
$ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
```

with:

```php
$ip = Snep_Security_ClientIp::resolveFromServer();
```

No changes to enumeration protections, password adapter, session
regeneration, CSRF rotation, or thresholds.

## Operational unlock (lockout inspection)

Inspect recent failures:

```sql
SELECT username, ip_address, attempted_at
FROM login_attempts
ORDER BY attempted_at DESC;
```

Targeted cleanup for an explicitly known affected pair:

```sql
DELETE FROM login_attempts
WHERE username = ?
  AND ip_address = ?;
```

No broad "clear all lockouts" admin shortcut was added.

## Pilot evidence (topology)

Documented real-pilot observation (operator-provided; not reproducible
on this Cursor host):

```text
REMOTE_ADDR=10.60.20.20
X_REAL_IP=201.89.219.213
X_FORWARDED_FOR=201.89.219.213
```

With `TRUSTED_PROXY_CIDRS=10.60.20.20/32`, resolution yields
`201.89.219.213` (unit case C).

## Carried incidents

| ID | Status after this task | Notes |
|---|---|---|
| I4 | OPEN | Operational targets may rebuild immutable release tags |
| I5 | OPEN | doctor/cert-check assumes SENMA-owned TLS termination |
| I6 | OPEN | external TLS terminator currently requires backend HTTPS :8443 |
| I7 | **IMPLEMENTATION_CLOSED** | login throttle proxy-aware via `Snep_Security_ClientIp` |
| I7 | **PILOT_RUNTIME_PROOF_PENDING** | distinct public clients behind NPM not yet proven on `REAL_PILOT_HOST` |

## Release guidance

```text
v0.1.0-rc.3 must not be mutated.

Recommended next pilot candidate:
v0.1.0-rc.4
```

Pilot NPM topology (operational example only — not hard-coded in PHP):

```text
pilot NPM:
10.60.20.20

pilot config:
TRUSTED_PROXY_CIDRS=10.60.20.20/32
```

## Validation

Focused:

```bash
make trusted-proxy-login-throttle-security-smoke
# RESULT: PASS (16/0) — unit A–G + chain + wild + AuthController wiring
# + multi-client LoginThrottle buckets + HTTP spoof ignored
```

Canonical (authoritative development/test context at Git
`9c2e1e4` + this working tree — not against an immutable pilot release
tag, due to I4):

| Gate | Result |
|---|---|
| `make lint` | **PASS** |
| `make regression` #1 | **PASS** (`EXITA:0`) |
| `make regression` #2 | **PASS** (`EXITB:0`, consecutive, no repair between) |
| `git diff --check` | **PASS** |

`trusted-proxy-login-throttle-security` is included in `scripts/regression.sh`
immediately after `auth-hardening-security`.

## Remaining debt

- **I7 PILOT_RUNTIME_PROOF_PENDING:** live NPM multi-client proof on
  `REAL_PILOT_HOST` after deploying a new RC (recommended `v0.1.0-rc.4`)
  with `TRUSTED_PROXY_CIDRS=10.60.20.20/32`. Do not mutate `v0.1.0-rc.3`.
- I4 / I5 / I6 remain **OPEN**.
- Optional future: apply `Snep_Security_ClientIp` to audit/log paths that
  still use raw `REMOTE_ADDR` (out of scope here).

## Files

- `snep/lib/Snep/Security/ClientIp.php` (new)
- `snep/modules/default/controllers/AuthController.php`
- `.env.example`
- `scripts/trusted-proxy-login-throttle-security-smoke-test.sh` (new)
- `scripts/regression.sh` / `Makefile`
- `docs/SECURITY-BASELINE.md`
- `docs/operations/production-release-runbook.md`
- this document
