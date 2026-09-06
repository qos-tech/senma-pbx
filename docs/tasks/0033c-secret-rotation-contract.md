# TASK-0033C — Secret Rotation Contract

Status: implemented and validated against a live, already-provisioned
installation. Lead: `senma-docker-platform-engineer`. Reviewers:
`senma-application-architect` (setup.conf/DB boundary, entrypoint
fail-fast semantics), `senma-telephony-architect` (AMI/manager.conf
boundary, restart/reload semantics, active-call impact).
`senma-product-designer` not invoked -- no admin-facing UI flow is
created or changed by this task (see PRODUCT/UI BOUNDARY in the parent
prompt; the operator surface is `make secrets-check`/`make
rotate-secrets`, not a web form).

This task closes the gap TASK-0033's own operational-readiness audit
identified as **HIGH**: *"credential rotation is silently ineffective
on an existing app or Asterisk volume -- only a fresh volume re-templates
secrets, with no error or warning either way."* All findings and
commands below were exercised live against this repository's actual
Docker stack (`app`, `asterisk`, `db`, `provider`, all already
provisioned with real data before this task began), not assumed from
reading the entrypoints alone.

---

## SECRET INVENTORY

| Secret | Classification | Notes |
|---|---|---|
| `DB_PASSWORD` (application DB user, `snep`) | `ROTATABLE_RUNTIME_SECRET` | In scope |
| `DB_ROOT_PASSWORD` (MariaDB root) | `ROTATABLE_RUNTIME_SECRET` | In scope |
| `AMI_PASSWORD` (Asterisk manager user) | `ROTATABLE_RUNTIME_SECRET` | In scope |
| `AMI_USER` | `ROTATABLE_RUNTIME_SECRET`-adjacent (identity, not a secret value) | Rotated together with `AMI_PASSWORD` by the same templating calls if an operator changes it; not independently drift-checked (no installation in this project has ever changed it from `snep`) |
| `DB_USER` | Same as `AMI_USER` -- identity, not drift-checked independently | |
| TLS private-key passphrase (WSS cert) | `NOT_APPLICABLE` | The self-signed WSS cert/key (TASK-0028Z) has no passphrase; key rotation itself is TASK-0029A's scope, explicitly OUT OF SCOPE here |
| Session secret | `NOT_APPLICABLE` | SENMA's session cookie uses PHP's native session mechanism (`Snep_Security_*`, TASK-0026G) -- no separate long-lived signing secret exists to rotate |
| `TRUNK_TEST_SECRET` | `TEST_ONLY` | Dev-only PJSIP fixture credential for the `provider` trunk simulator (TASK-0015); not a production credential, not part of this contract |
| Admin/bootstrap password (web UI login) | `NOT_APPLICABLE` here | User/admin web passwords are explicitly OUT OF SCOPE (see parent prompt SCOPE) -- already covered by TASK-0026H's own password-hashing/rotation-via-UI story |
| `provider` service's own PJSIP secrets | `TEST_ONLY` | Local dev trunk simulator, never a real credential |
| SIP extension secrets (per-extension PJSIP `auth`) | `NOT_APPLICABLE` here | Explicitly OUT OF SCOPE (SIP extension password rotation UX) |
| Docker `.env` file itself | `FIRST_BOOT_SEED` for most vars, but the DECLARED SOURCE for the three secrets above | See SOURCE OF TRUTH |

No operationally relevant `UNKNOWN` remains: every credential-shaped
value in `.env.example` has been classified above.

---

## SOURCE OF TRUTH

Model: **environment declares desired secret; explicit rotation logic
reconciles persisted state** (`EXPLICIT_ROTATION_COMMAND_AUTHORITATIVE`
for the *transition*, with `.env` as the durable record of *intent*).

Editing `.env` alone is `DESIRED_STATE_CHANGED`, not
`REQUESTED_ROTATION`. The operator contract is:

```text
edit .env
→ make rotate-secrets   (or a per-secret target)
→ make secrets-check    (optional, to confirm)
```

`docker compose up`/`restart`/recreate alone never silently reconciles
a changed `.env` value into persisted state -- see STARTUP POLICY.

---

## CONSUMER MAP

| Secret | Persisted location(s) | Consumer(s) | Reload/restart needed to apply |
|---|---|---|---|
| `DB_PASSWORD` | MariaDB `snep`@`%` account (in `mag-db`); `snep/includes/setup.conf` `[ambiente] db.password` (host bind mount, `www-data:www-data 664`); `/etc/asterisk/res_odbc.conf` `[snep] password =>` (asterisk-etc volume, `asterisk:asterisk 644`) | App's `Snep_Db`/`Zend_Db` connection (setup.conf); Asterisk's `res_odbc`/`cdr_adaptive_odbc` (res_odbc.conf) | **None** -- `module reload res_odbc.so` picks it up live; app reads setup.conf per-request (no app restart needed) |
| `DB_ROOT_PASSWORD` | MariaDB `root`@`%` **and** `root`@`localhost` accounts | `make db-shell`, `scripts/backup.sh`/`scripts/restore.sh` (read `.env` at invocation time), the `db` service's own healthcheck (`mariadb-admin ping -uroot`) | **None** for the account itself; any *tooling* invocation naturally picks up the current `.env` value next time it runs |
| `AMI_PASSWORD` | `/etc/asterisk/manager.conf` `[snep] secret =` (asterisk-etc volume); `snep/includes/setup.conf` `[ambiente] pass_sock` | Asterisk's `manager.conf`-driven AMI listener; app's `Asterisk_AMI`/`PBX_Asterisk_AMI` client (via setup.conf) | **None** -- `manager reload` picks it up live, confirmed non-disruptive to a running call (see ROTATION AND ACTIVE CALLS) |

One environment variable does **not** map to one file for any of these
three secrets -- confirmed by direct inspection, not assumed.

---

## DRIFT MODEL

`scripts/secrets-check.sh` (`make secrets-check`) reports, per
(secret, consumer) pair, exactly one of `MATCH` / `DRIFT` / `UNKNOWN`
-- never a secret value, on either side, in any output line (see
LOGGING SAFETY).

Two detection strategies, chosen per consumer:

- **File-based consumers** (setup.conf, manager.conf, res_odbc.conf):
  the declared value and the value extracted from the file are each
  hashed (sha256, computed via the `printf` shell **builtin**, never a
  separate process argv) and the hashes compared. The raw values never
  leave their own scope long enough to be logged.
- **Live consumers** (the DB app account, DB root account, AMI login):
  an actual authentication attempt is made with the DECLARED value.
  `MATCH` = authentication succeeded; `DRIFT` = a distinguishable
  "access denied"/"authentication failed" response; `UNKNOWN` = any
  other outcome (container unreachable, unexpected error).

`DB_ROOT_PASSWORD` has no file consumer in this stack -- only the live
check applies, reported as `N/A` for the (nonexistent) file row.

---

## STARTUP POLICY

| Secret | Startup behavior on drift | Why |
|---|---|---|
| `DB_PASSWORD` | **FAIL_FAST** -- `docker/entrypoint.sh` (app) and `docker/asterisk-entrypoint.sh` refuse to start (`ROTATION_PENDING_EXPLICIT_ACTION`, nonzero exit) if the declared value disagrees with what's already persisted in setup.conf/res_odbc.conf | Security-critical mismatch; `unless-stopped` turns this into a clearly-visible, self-describing crash-loop rather than a silent stale-credential success |
| `AMI_PASSWORD` | **FAIL_FAST**, same mechanism, on `manager.conf`/setup.conf | Same reasoning |
| `DB_ROOT_PASSWORD` | **FAIL_FAST**, via the EXISTING mechanism -- `compose.yaml`'s own `db` healthcheck (`mariadb-admin ping -uroot -p$MARIADB_ROOT_PASSWORD`) already authenticates with the CURRENT env value on every check; a drifted value makes it fail deterministically, keeps `db` `unhealthy` indefinitely, and blocks `app`'s `depends_on: condition: service_healthy` | No new code added here deliberately -- a second, differently-timed coherence check would risk disagreeing with the healthcheck's own verdict about the exact same fact. Confirmed live: `docker compose ps` shows `db` unhealthy, `app` never starts, until root is rotated or `.env` is reverted |

`WARN_AND_CONTINUE` was considered and rejected for all three: a
security-critical credential mismatch that only logs a warning is
exactly the "silently ineffective" behavior this task exists to close.

**Crash-loop recovery is a deliberate, tested property, not an
afterthought.** Every file-touching operation in `scripts/lib/
secrets-lib.sh` (`slib_run_sh`) reaches `app`/`asterisk` via `docker
compose run --rm --no-deps --entrypoint sh`, never `docker compose
exec` against the currently-running container -- so `make
rotate-secrets` keeps working precisely when a container is
crash-looping because of the drift it exists to fix (confirmed live:
rotated `DB_PASSWORD` successfully while `app` was mid-crash-loop from
that exact drift; Docker's own `unless-stopped` restart policy then
converged the real container to healthy once the files agreed). Live
operations that genuinely need the running service (AMI login,
`manager reload`, `odbc show all`) instead check `asterisk_is_up`
(Docker's own health state, not a transient "Up" status) and bring the
container up via `docker compose up -d --no-deps asterisk` first if it
is not — confirmed live for a **stopped** (not just crash-looping)
asterisk during AMI rotation.

---

## ROTATION COMMAND

```bash
make secrets-check                 # safe, non-mutating
make rotate-secrets                # rotates every DRIFTed secret
make rotate-db-password             # per-secret equivalents
make rotate-db-root-password
make rotate-ami-password
```

`rotate-secrets.sh` (and each `make rotate-*` target) is idempotent: a
secret already `MATCH`ing is reported `ROTATED_SUCCESSFULLY` ("already
current") without touching anything, unless `--force` is given.

### ROTATION ORDERING

Fixed order: **`db-root-password` → `db-password` → `ami-password`**.

`db-password` rotation authenticates as root using the *currently
declared* `DB_ROOT_PASSWORD` (root never needs the target account's old
password to `ALTER USER` it). If an operator changes `DB_PASSWORD` and
`DB_ROOT_PASSWORD` in the same `.env` edit and root has not rotated
yet, `db-password` rotation would try to authenticate with a root
password that isn't active — confirmed live as a real, reproducible
failure (`DB_ROOT_PASSWORD (declared) does not currently authenticate
as root`) before this order was fixed. Rotating root first costs
nothing in the common single-secret-change case: root's own "already
current" check short-circuits before any prompt. `ami-password` has no
dependency on either DB secret and stays last.

---

## DB APPLICATION PASSWORD

Sequence (`rotate_db_password` in `scripts/rotate-secrets.sh`):

1. Skip (report `ROTATED_SUCCESSFULLY`, "already current") if the
   declared value already authenticates, unless `--force`.
2. `slib_validate_secret` (format precondition, see PROCESS/TEMPFILE
   SAFETY / FAILURE INJECTION) -- reject before touching anything.
3. Confirm the declared `DB_ROOT_PASSWORD` currently authenticates as
   root; reject with a clear ordering message if not.
4. Capture the CURRENT (pre-rotation) `db.password` value from
   setup.conf into a local shell variable, never printed -- needed only
   for a same-secret rollback if a later step fails (ROLLBACK).
5. `ALTER USER 'snep'@'%' IDENTIFIED BY '<new>'; FLUSH PRIVILEGES;` as
   root, via `docker compose exec db ... mariadb -uroot`, with the SQL
   body (root password + statement) delivered entirely over **stdin**.
6. Template `setup.conf`'s `db.password` line and `res_odbc.conf`'s
   `password =>` line (both via `docker compose run --rm --entrypoint
   sh`, both preserving/re-asserting correct ownership -- see
   PERMISSIONS).
7. `module reload res_odbc.so` if asterisk is already healthy;
   otherwise bring it up (crash-loop-recovery path).
8. Verify: a live DB auth check with the new password, and `odbc show
   all` reporting `Number of active connections: >=1`.
9. On success, discard both file backups. On any failure from step 5
   onward, roll back (ROLLBACK).

Live-verified: `docker compose restart`/`up -d --force-recreate` on
`app`+`asterisk` after a successful rotation preserve the new
credential (persisted files, not env-templated on every boot).

---

## DB ROOT PASSWORD

MariaDB's own entrypoint templates `MARIADB_ROOT_PASSWORD` only when
the data directory is first initialized (confirmed by design, and by
this task's own live test: the account survives unchanged across
restarts/recreates otherwise). Root has **no file consumer** in this
stack.

Sequence (`rotate_db_root_password`):

1. Skip if the declared value already authenticates as root, unless
   `--force`.
2. Format validation.
3. Obtain the CURRENT root password: an interactive, hidden
   (`read -s`) prompt in a real terminal (never read from `.env`, which
   only ever holds the desired NEW value; never stored or logged). A
   test-only environment-variable override
   (`ROTATE_SECRETS_CURRENT_ROOT_PASSWORD`) exists solely for
   `scripts/secret-rotation-smoke-test.sh`.
4. Verify the supplied current password actually authenticates before
   using it; reject cleanly if not (no state changed).
5. `ALTER USER 'root'@'%' IDENTIFIED BY '<new>'; ALTER USER
   'root'@'localhost' IDENTIFIED BY '<new>'; FLUSH PRIVILEGES;` -- both
   host-scoped root accounts (confirmed live: this image provisions
   both), in one statement batch, all via stdin.
6. Verify the new value authenticates live; on failure, attempt to roll
   back to the previous password (using the value still held from step
   3) and report accordingly.

Live-verified against the real installation: old password rejected
(`Access denied`), new password accepted, `make db-shell`-equivalent
access, `scripts/backup.sh` (`make backup`), and `scripts/restore.sh`'s
own root-based DB dump/import all confirmed working against the
rotated root password. `docker compose restart db` and
`--force-recreate` preserve the rotated value (the MariaDB volume, not
the container, owns the account).

---

## AMI PASSWORD

Sequence (`rotate_ami_password`):

1. Skip if already current, unless `--force`.
2. Format validation.
3. Template `manager.conf`'s `secret =` line and `setup.conf`'s
   `pass_sock` line (both via `docker compose run --rm --entrypoint
   sh`).
4. `manager reload` if asterisk is already healthy; otherwise bring it
   up (crash-loop-recovery path, also proven for a cleanly **stopped**
   asterisk).
5. Verify via a raw AMI login test (bash `/dev/tcp`, independent of
   SENMA's own PHP AMI client) against the container's own
   Compose-network address -- **not** `127.0.0.1`/loopback:
   `manager.conf`'s ACL (`permit=172.28.0.0/16`, `deny=0.0.0.0/0.0.0.0`)
   rejects loopback-sourced connections regardless of credential
   correctness, confirmed live as a real, otherwise-confusing false
   negative before this was corrected.
6. On success, discard both file backups. On failure, restore both
   files and reload/recover again.

## ROTATION AND ACTIVE CALLS

`manager reload` and `module reload res_odbc.so` both re-read their
config file without restarting the Asterisk process. Confirmed live:
`core show uptime` immediately before and after an AMI rotation showed
the SAME running instance (uptime kept advancing by real wall-clock
seconds only, never reset) -- **NON-DISRUPTIVE**. Neither `DB_PASSWORD`
nor `AMI_PASSWORD` rotation ever restarts Asterisk on the
already-healthy path; active calls are unaffected. The only path that
restarts/recreates a container is the crash-loop-recovery branch
(`ensure_asterisk_up`), which by definition only fires when Asterisk
was already down or about to fail its own coherence check --
**DISRUPTIVE, but only when the installation was already in that state
independent of this tool.**

---

## ROLLBACK

Every mutation is preceded by a same-filesystem `cp -p` backup
(`<file>.rotate-bak.<pid>`); every replacement writes to a same-
directory temp file and `mv`s it into place (atomic rename, never a
torn write). Concretely:

- **setup.conf write fails after the DB password already changed**:
  the DB account is rolled back to the value captured before step 5
  (DB APPLICATION PASSWORD), restoring one coherent previous state.
- **res_odbc.conf write fails after setup.conf already changed**:
  setup.conf is restored from its backup, then the DB account is rolled
  back the same way.
- **Post-rotation verification fails** (app DB auth or Asterisk ODBC
  connectivity, or AMI login): both files are restored from backup, the
  DB account (or AMI config) is rolled back, and the previous coherent
  state is re-verified live before reporting `ROTATION_REJECTED`.
- **The DB account rollback itself cannot be confirmed** (root also
  unreachable at that moment, an already-degraded scenario): reported
  explicitly as unresolved drift ("DRIFT_DETECTED, run `make
  secrets-check`") rather than a false `ROTATED_SUCCESSFULLY` or a
  silent `ROTATION_REJECTED` that hides the real state.

All of the above were exercised live, not just designed on paper (see
FAILURE INJECTION and EXISTING-INSTALL PROOF).

---

## PERMISSIONS

| File | Required owner:group | Required mode | Verified |
|---|---|---|---|
| `snep/includes/setup.conf` | `www-data:www-data` | `664` | Live-verified before/after rotation |
| `/etc/asterisk/manager.conf` | `asterisk:asterisk` | `644` | Live-verified, preserved across rotation |
| `/etc/asterisk/res_odbc.conf` | `asterisk:asterisk` | `644` | Live-verified, preserved across rotation |
| `.env` | host-default (not modified by this task) | host-default | Not a repository-workflow-touched file for this task's own operations beyond `sed -i` in place |
| Backup artifacts (`backups/*.tar.gz`) | host user | `600` (`blib_secure_path`, TASK-0033A, unchanged) | Confirmed still applies post-rotation |

**A real permission regression was found and fixed during this task's
own validation**: `docker compose run --rm --entrypoint sh app`
executes as the `app` image's default user, which is **root**
(`php:8.4-apache` sets no `USER`), unlike `asterisk` (`USER asterisk`
in `docker/asterisk.Dockerfile`). Writing setup.conf through that path
without correcting ownership left it `root:root 644` after a rotation
that never restarts the app container (so `docker/entrypoint.sh`'s own
unconditional post-boot `chown www-data:www-data`/`chmod 664` never got
a chance to re-run and fix it) -- silently breaking the web UI's own
ability to write recording-path settings back into the file
(`ParametersController`). Fixed by making `slib_remote_template_line`
accept an explicit required owner/mode for setup.conf specifically
(`www-data:www-data`/`664`, matching entrypoint.sh's own documented
invariant) rather than merely preserving whatever ownership the file
already had. `manager.conf`/`res_odbc.conf` needed no such fix --
`docker compose run --entrypoint sh asterisk` already runs as the
`asterisk` user via the image's own `USER` directive, so ownership was
correct by construction; confirmed live that a non-root process CAN
`chown`/`chmod` a file it already owns to the same owner (POSIX
same-owner exception), so the general "preserve previous owner/mode"
path used for those two files works without special-casing.

---

## LOGGING SAFETY

No script in this task ever prints a secret value. Verified two ways:

1. **By construction**: `scripts/secrets-check.sh` only ever compares
   sha256 hashes or live-authenticates; `scripts/rotate-secrets.sh`'s
   own progress/result output only ever names secrets by their
   identifier (`DB_PASSWORD`, etc.) and outcome, never a value.
2. **Live, adversarial check**: `scripts/secrets-consistency-smoke-test.sh`
   (regression-safe) and `scripts/secret-rotation-smoke-test.sh`
   (destructive) each capture the FULL stdout+stderr of every command
   they run and grep it for every live secret value involved (old and
   new, all three secrets) -- confirmed zero matches across multiple
   real runs, including runs that deliberately triggered errors
   (wrong-password rejections, invalid-format rejections, stopped-
   container errors).

No `set -x` is used anywhere in the new scripts. `docker exec`/`run`
command echo (`Container ... Creating/Started`, `No services to
build`) is Compose's own fixed chatter, never secret-bearing.

---

## PROCESS/TEMPFILE SAFETY

- **No secret ever appears as a CLI argument** to any process, on the
  host or inside a container. DB/root authentication uses `MYSQL_PWD`
  (an environment variable set for exactly one child process via a
  `read -r PW; MYSQL_PWD="$PW" mariadb ...` pattern, the value arriving
  over **stdin**, not `-p"$PASSWORD"`). The one-line diagnostic query
  earlier in this task's own investigation that used `-p"$PASSWORD"`
  directly was a throwaway verification command, not part of any
  delivered script -- grepped the final deliverables to confirm none
  use that pattern.
- Config-file templating never embeds the secret in the AWK/sed program
  text: the value is `read` from stdin into a shell variable, `export`ed,
  and referenced only via AWK's `ENVIRON[...]` at runtime -- the AWK
  program text itself (visible in `ps`/`docker top`) is always the
  same, fixed, non-secret string.
- `ALTER USER` statements embed the new password as a SQL string
  literal delivered entirely over stdin (a heredoc) -- never as a
  `mysql -e "..."` CLI argument.
- Bash here-strings/heredocs (`<<<`, `<<EOF`) are the only mechanism
  used to move a secret value into a container; these are implemented
  internally by bash writing to a private, immediately-unlinked
  temporary file, not by spawning a process whose argv contains the
  value.
- No script in this task creates a **persistent** temp file containing
  a secret. `slib_remote_backup`'s `<file>.rotate-bak.<pid>` copies
  contain a secret (they're copies of setup.conf/manager.conf/
  res_odbc.conf) but exist only inside the SAME container filesystem
  the original lives in (no more exposed than the original itself
  already was), are removed on success (`slib_remote_discard_backup`)
  or renamed back over the original on failure (`slib_remote_restore`)
  -- never left behind in either outcome. `slib_remote_template_line`'s
  own `<file>.rotate-new.<pid>` staging file is `mv`'d away (success)
  or simply orphaned-and-overwritten-next-attempt (failure before the
  `mv`) -- not otherwise cleaned up explicitly today (see REMAINING
  DEBT).

---

## PARTIAL FAILURE

`scripts/rotate-secrets.sh` reports one `ROTATED_SUCCESSFULLY` /
`ROTATION_REJECTED` line **per secret**, e.g.:

```text
SECRET               OUTCOME                  DETAIL
DB_ROOT_PASSWORD     ROTATED_SUCCESSFULLY     ...
DB_PASSWORD          ROTATED_SUCCESSFULLY     ...
AMI_PASSWORD         ROTATION_REJECTED        ...
```

The overall process exit code is nonzero if **any** secret ends
`ROTATION_REJECTED` -- there is no single global "success" line printed
on partial failure, and no code path returns 0 while any secret's own
outcome is `ROTATION_REJECTED`.

---

## BACKUP INTEGRATION

`scripts/backup.sh`'s manifest carries no secret values today (TASK-
0033A) and this task does not change that. Live-verified: `make
backup` succeeds against a freshly-rotated installation (all three
secrets rotated immediately beforehand in the same test run) with no
format change to the backup artifact. `scripts/restore.sh`'s own
`odbc_ready` failure message (previously: *"SENMA does not yet support
credential rotation on an existing volume"*) has been updated to point
at `make secrets-check`/`make rotate-secrets` now that the gap it
described is closed.

---

## RECONCILE INTEGRATION

`docker compose exec asterisk php /usr/local/bin/reconcile-pjsip.php
--check` (`make reconcile-check`, TASK-0033B) was run immediately after
a full three-secret rotation in this task's own destructive proof and
returned `IN_SYNC` (exit 0) -- reconcile's own DB connectivity (via
setup.conf, just rotated) and its AMI-dependent runtime-apply/verify
steps both function correctly against the newly-rotated credentials.

---

## EXISTING-INSTALL PROOF

Every proof in this document was run against this repository's actual,
already-running Docker stack (`app`/`asterisk`/`db`/`provider`, hours
of uptime, real persisted state, provisioned before this task started)
-- never a freshly-initialized volume. `scripts/secret-rotation-smoke-
test.sh` codifies this as a repeatable regression: it asserts the
installation starts `MATCH` (already provisioned and coherent) before
doing anything, which would `BLOCKED` the suite on a fresh/never-
provisioned install rather than produce a false pass.

---

## RESTART/RECREATE PROOF

Live-verified, both manually and via the automated suite:

- `docker compose restart app asterisk` (and `db`) after rotation:
  `secrets-check` still reports `MATCH`.
- `docker compose up -d --force-recreate --no-deps app asterisk` after
  rotation: same result -- the persisted files/DB account are the
  source of truth, never re-templated from a stale first-boot guard.

---

## FAILURE INJECTION

All of the following were run against the real stack, not simulated:

| Scenario | Result |
|---|---|
| Invalid new secret format (`|`, `"`, `'`, `\`, empty, CR/LF, >255 chars) | `slib_validate_secret` rejects before any file/DB write; `ROTATION_REJECTED`, nonzero exit, no state changed. (A `|` value is ALSO rejected for an independent reason: `.env` is sourced as literal shell by every Makefile target -- a `|` in a sourced `KEY=value` line is the shell pipe operator, not a literal character, and would corrupt `.env` parsing itself, confirmed live during this task's own test-script debugging.) |
| Malformed AWK template application (simulated apply failure) | Backup restored, original content byte-for-byte unchanged, function returns failure |
| `db` container stopped mid-rotation-attempt | `rotate-secrets.sh` exits nonzero before any write (hard precondition); `db` restarted; coherence re-confirmed `MATCH` (nothing was left partially applied) |
| `asterisk` container stopped during AMI rotation | Config is templated anyway (file op doesn't need the live process); `asterisk` is then brought up via `docker compose up -d --no-deps asterisk`; live AMI verification succeeds once it's healthy -- **recovers rather than rejects**, a deliberate, documented choice (see STARTUP POLICY) |
| Wrong CURRENT root password supplied to root rotation | Verified against a live auth check before use; rejected cleanly, no ALTER USER attempted, no state changed |
| Two secrets (`DB_PASSWORD` + `DB_ROOT_PASSWORD`) declared new simultaneously | Fixed rotation order (root first) handles this correctly; confirmed live before AND after discovering/fixing the ordering bug (see ROTATION ORDERING) |

---

## NO-SILENT-NO-OP PROOF

Reproduced the exact original bug report: an existing installation,
`DB_PASSWORD`/`AMI_PASSWORD` changed in `.env`, container recreated.
Before this task, that would boot "healthy" while silently still using
the old credential. Now: the container **crash-loops** with an explicit
`ROTATION_PENDING_EXPLICIT_ACTION` message naming the exact secret and
the exact remediation command, on both `app` and `asterisk`,
confirmed live for `DB_PASSWORD` (app), `DB_PASSWORD`/`AMI_PASSWORD`
(asterisk), and `AMI_PASSWORD` (app, via `pass_sock`). `DB_ROOT_PASSWORD`
drift is caught by the pre-existing healthcheck mechanism, confirmed to
already fail deterministically rather than silently pass. Neither
"container healthy" + "old secret still active" + "new secret silently
ignored" is reachable for any of the three secrets.

---

## SECRET NON-DISCLOSURE PROOF

See LOGGING SAFETY -- both smoke tests grep their own full captured
transcript for every secret value involved and assert zero matches;
confirmed passing across multiple real runs of both suites.

---

## REGRESSION COVERAGE

Split, matching this task's own expected approach and the
`backup-smoke`/`backup-restore-smoke` precedent (TASK-0033A):

- **`scripts/secrets-consistency-smoke-test.sh`** (`make
  secrets-consistency-smoke`) -- safe, non-mutating (asserts this dev
  install's own baseline is `MATCH`, asserts non-disclosure, asserts a
  known-wrong value correctly reports `DRIFT`). **Included in `make
  regression`.**
- **`scripts/secret-rotation-smoke-test.sh`** (`make
  secret-rotation-smoke`) -- the full destructive proof (all 20 items
  from the parent prompt's Regression coverage list). Actually rotates
  and un-rotates all three real secrets on this installation.
  **Deliberately NOT part of `make regression`** -- mutating real
  credentials (even dev placeholders) on every CI/regression run is
  unnecessary risk and cost for a suite that already proves the same
  contract through 24 independent, live-verified checks; an operator
  or CI job that wants the full destructive proof runs it explicitly,
  exactly like `backup-restore-smoke`.

Both suites were run to a clean `PASS` multiple times during this
task's own development, including after fixing two real bugs the first
full run surfaced (see REMAINING DEBT for the meta-point: the smoke
test itself needed debugging before it could safely certify the
product code -- that debugging is what found the ROTATION ORDERING and
setup.conf PERMISSIONS issues, not a static review).

---

## REMAINING DEBT

1. **`slib_remote_template_line`'s staging file
   (`<file>.rotate-new.<pid>`) is not explicitly cleaned up if the
   script is killed between the `awk` write and the `mv`.** Low risk
   (same container filesystem, overwritten by the next attempt's own
   `$$`-suffixed name colliding only in the astronomically unlikely
   case of a reused PID within the same file's lifetime), but a
   `trap ... EXIT` inside the remote script would close this fully.
   `FOLLOW_UP_DEBT`.
2. **`DB_USER`/`AMI_USER` (the identity half of the two DB/AMI
   credential pairs) are not independently drift-checked.** No
   installation has ever changed them from their `.env.example`
   defaults; if one ever does, `secrets-check`'s live-auth checks would
   still correctly report `DRIFT` (a changed username makes the
   password-based auth check fail too), but the diagnostic wouldn't
   distinguish "wrong password" from "wrong username" without reading
   the raw (non-secret) username values, which `secrets-check.sh`
   currently doesn't surface as their own row. `FOLLOW_UP_DEBT`.
3. **TLS/WSS certificate rotation remains TASK-0029A's scope**,
   unchanged by this task, as directed.
4. **A production-unsafe-default warning on `.env.example`** (TASK-
   0033's own MEDIUM finding #12) is still open -- unrelated to
   rotation mechanics, `FOLLOW_UP_DEBT`, not touched here per scope
   protection.
5. **`make doctor`/TASK-0033D integration**: `scripts/secrets-check.sh`
   is already a clean, scriptable, machine-parseable (`OVERALL: MATCH`/
   `DRIFT_DETECTED`/`UNKNOWN`, exit 0/3/1) primitive `make doctor` or a
   future consolidated diagnostic bundle can call directly -- no
   further integration work was needed for this task's own scope, but
   TASK-0033D should simply invoke `make secrets-check` rather than
   reimplementing any of this.

---

## VALIDATION SUMMARY

- `php -l`: not applicable (no PHP files changed).
- `bash -n` on every new/modified shell script: clean.
- Target tests: `scripts/secrets-consistency-smoke-test.sh` PASS (4/4
  checks); `scripts/secret-rotation-smoke-test.sh` PASS (24/24 checks),
  run to green multiple times during development.
- `make lint`, `make regression` (x2), `git diff --check`, `git status
  --short`: see the checkpoint report accompanying this document for
  the final run's output.
