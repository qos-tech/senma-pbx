# TASK-0035E9 — Secure Initial Admin Credential Bootstrap

## Decision

`ADMIN_BOOTSTRAP_PASS_WITH_CONSTRAINTS`

Constraint:

`FRESH_INSTALL_ADMIN_BOOTSTRAP_PROOF_PENDING`

(Pilot/current install must not be reset; disposable fresh-install proof
on a throwaway stack remains recommended before TASK-0035 final closure.
Focused `admin-bootstrap` / `auth-hardening` smokes cover the engineering
contract.)

## Root cause

TASK-0026H removed the ship-time `admin`/`admin123` credential and
replaced it with a sentinel + first-boot random password. The plaintext
was printed once to **container stdout** (`make logs`). That meant:

- the only durable copy of the initial password lived in log aggregators
  / journald / operator scrollback;
- there was no operator-local secret file with mode `0600`;
- entropy was 128 bits (`random_bytes(16)`), below the 192-bit target.

## Admin identity

| Field | Value |
|---|---|
| Table | `users` |
| Username | `admin` |
| Seed password | `!SENMA-BOOTSTRAP-PENDING!` (non-authenticating sentinel) |
| Profile | `profile_id = 1` |

## Canonical password normalization

Unchanged. Bootstrap calls only:

`Snep_Security_Password::hash($plaintext)`

which applies `normalize()` = `base64_encode(hash('sha256', $plaintext, true))`
before `password_hash(..., PASSWORD_DEFAULT)`. Login uses
`Snep_Security_Password::verify()` via `Snep_Auth_Adapter_Password`.

No independent hashing path was added.

## Fresh-install detection

Durable condition (not “container just started”):

```text
users.name = 'admin'
AND users.password = '!SENMA-BOOTSTRAP-PENDING!'
```

Any other stored password (bootstrap hash, operator change, restore) is
a hard no-op.

## RNG

`bin2hex(random_bytes(24))` — 192 bits, hex shape equivalent to
`openssl rand -hex 24`.

## Bootstrap secret

| Role | Path |
|---|---|
| Host (canonical) | `./secrets/bootstrap-admin-password` (repo root) |
| Container | `/run/senma/secrets/bootstrap-admin-password` |
| Lock | `/run/senma/secrets/bootstrap-admin.lock` |

- Mode: `0600` (refused if not)
- Owner: matched to the `./secrets` directory owner (operator UID on the
  bind mount)
- Gitignored (`/secrets/*`, keep `secrets/.gitkeep`)
- Excluded from Docker build context (`.dockerignore`)
- Not under webroot
- Not included in `scripts/backup.sh`

## Failure atomicity

1. Exclusive `flock` on the lock file
2. Transaction + `SELECT ... FOR UPDATE` on the admin row
3. Ensure secret file exists (reuse if recovering a prior partial write;
   else generate + temp/rename publish at 0600)
4. `UPDATE ... WHERE password = SENTINEL` (one row)
5. Path-only success banner (no plaintext)

If the secret directory/mount is missing, bootstrap **fails without**
updating the DB (sentinel remains). Entrypoint failure is non-fatal to
Apache, so the operator is never left with an unknown DB password and
no secret file from this path.

## Concurrency

`flock(LOCK_EX)` on the shared bind-mounted lock file +
`UPDATE ... AND password = SENTINEL` ensures a single winner.

## Existing install / restart / upgrade / restore

| Event | Effect on admin password |
|---|---|
| docker restart / recreate / pilot-up / up | none (non-sentinel) |
| migrate / doctor / reconcile / backup | none |
| restore of existing DB | none (restored hash kept; no new secret) |
| fresh seed with sentinel | bootstrap once |

## Backup

Bootstrap plaintext is **not** part of backup. The DB dump already
contains the password hash. Plaintext is temporary/operator-local.

## Operator commands

```bash
make bootstrap-admin-credentials        # print Username/Password
make bootstrap-admin-credentials-clear  # rm plaintext only; DB unchanged
```

## Password-change / stale secret

No automatic correlation between UI password change and the secret file
(avoids fragile coupling). Documented operator procedure: after first
login and password change, run
`make bootstrap-admin-credentials-clear`. Doctor WARNs while the file
exists.

## Doctor

- `Administrator account` — PASS when admin is past the sentinel
- `Bootstrap admin secret file` — WARN while plaintext file exists;
  PASS when absent
- Never prints plaintext/hash/secret contents

## Default credential removal

Install seed already uses the sentinel (TASK-0026H). This task keeps
that contract and adds regression coverage against reintroduction of
`admin123` MD5 / `admin`/`admin` literals in non-comment SQL.

## Pilot plan

Do **not** reset TEXTE-PBX-001 admin. Confirm on upgrade that no new
bootstrap secret appears and the existing admin still works.

Mark: `FRESH_INSTALL_ADMIN_BOOTSTRAP_PROOF_PENDING` until a disposable
fresh install on real hardware/VM is exercised.

Isolated `make fresh-install-smoke` on a host that already runs the
primary stack may still fail health waits (Docker FORWARD/iptables cold
start, shared bind mounts). HTTPS port remap
(`FRESH_INSTALL_PROOF_HTTPS_PORT`, default 18443) avoids the 8443 bind
collision. Focused `admin-bootstrap` / `auth-hardening` smokes remain
the authoritative engineering proof for this task.

## E7 impact

TASK-0035E7 remains paused. Do not mutate `v0.1.0-rc.9`. Expected next
candidate after merge: `v0.1.0-rc.10`.

## Files

| File | Role |
|---|---|
| `docker/bootstrap-admin.php` | secret-file bootstrap |
| `compose.yaml` | `./secrets` bind mount |
| `docker/entrypoint.sh` | comments |
| `scripts/bootstrap-admin-credentials.sh` | retrieval |
| `scripts/bootstrap-admin-credentials-clear.sh` | clear |
| `scripts/admin-bootstrap-smoke-test.sh` | lifecycle smoke |
| `scripts/auth-hardening-security-smoke-test.sh` | F27 update |
| `scripts/doctor.sh` / `doctor-smoke-test.sh` | doctor checks |
| `Makefile` / `scripts/regression.sh` | targets + suite |
| `.gitignore` / `.dockerignore` / `secrets/.gitkeep` | secret hygiene |
| `docs/SECURITY-BASELINE.md` / runbook | operator contract |
| `snep/install/database/system_data.sql` | comment only |
| `scripts/fresh-install-proof-smoke-test.sh` | HTTPS port remap |
