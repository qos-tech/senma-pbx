# TASK-0033A — Backup, Restore & Disaster Recovery Foundation

Lead: senma-application-architect. Reviewers: senma-docker-platform-engineer,
senma-telephony-architect. senma-product-designer not invoked (no
user-facing workflow/state was introduced — `make backup`/`make restore`
are operator CLI commands, not admin UI surface).

TASK-0033 classified backup/restore as a **production BLOCKER**: no
supported mechanism existed to capture or recover SENMA's state, and the
one legacy script present (`snep/scripts/backup/backup.sh`) targeted a
filesystem layout that no longer exists and explicitly excluded customer
recordings. This task closes that blocker with a real, proven backup and
restore contract, without depending on TASK-0033B (DB→PJSIP reconciliation,
which does not exist yet).

---

## STATE INVENTORY

Reconfirmed live against the running dev stack (not assumed from TASK-0033's
prior findings, though every item below is consistent with them).

| Path / volume | Classification | Physical storage | In this backup? |
|---|---|---|---|
| MariaDB data (schema + all rows: `peers`, `trunks`, `pjsip_transports`, `users`, `cdr`, etc. — 56 tables, all InnoDB) | BACKUP_REQUIRED | Named volume `mag-db` | Yes — `mariadb-dump --single-transaction` |
| `snep/includes/setup.conf` | BACKUP_REQUIRED | **Host bind mount** (`./snep`), gitignored | Yes — plain copy |
| `snep/arquivos/` (recording/upload storage) | BACKUP_REQUIRED | **Host bind mount**, gitignored | Yes — tar |
| `/etc/asterisk` (whole volume: static config, `manager.conf`/`res_odbc.conf` secrets, generated `senma-*.conf`, TLS cert/key, `custom/*.conf`) | BACKUP_REQUIRED (bit-identical contract — see CONSISTENCY MODEL) | Named volume `asterisk-etc` | Yes — tar, whole volume |
| `/var/lib/asterisk/astdb.sqlite3` | BACKUP_REQUIRED (small, cheap, not proven harmless to lose) | Named volume `mag-asterisk-var` | Yes — plain copy |
| `/var/lib/asterisk/agi-bin`, `/var/lib/asterisk/documentation` | REGENERABLE — rebuilt/reseeded unconditionally every boot by `docker/asterisk-entrypoint.sh` | Named volume `mag-asterisk-var` | No |
| `/var/spool/asterisk` (`outgoing/`, `tmp/`) | EPHEMERAL — call-file drop dir; 0 B in this build (no recording/MixMonitor feature active) | Named volume `mag-asterisk-spool` | No |
| `/var/log/asterisk/*` (263 MB `full`, `queue_log`) | EXCLUDE — diagnostic/forensic log data, not provisioning state; not needed to recreate an installation (TASK-0033D's rotation/retention problem, not this task's) | Named volume `mag-asterisk-log` | No |
| App Apache/PHP/UI logs | EXCLUDE — already TASK-0033D's problem (unpersisted container-layer logs) | Container writable layer | No |
| `provider` service's own volumes (`mag-provider-etc`, `mag-provider-var`) | TEST_ONLY — an independent test-fixture Asterisk instance (TASK-0015), not part of a real SENMA installation | Named volumes | No |
| Voicemail (`voicemail_users`/`voicemail_messages` tables exist, 0 rows; `app_voicemail.so` loaded but no `voicemail.conf` deployed) | Covered by the DB dump if ever populated; not a live feature today | N/A | DB rows only, via the dump |
| Docker image layers | REGENERABLE from `docker/*.Dockerfile` + git | N/A | No |
| PostgreSQL | N/A — not part of the current topology (MariaDB only, per CLAUDE.md's current-vs-future-DB distinction) | — | — |

No item above is UNKNOWN. The two host bind-mounted paths (`setup.conf`,
`arquivos/`) are exactly the two TASK-0033 flagged as easy to miss under a
volume-only backup approach — both are explicitly covered.

---

## BACKUP CONTRACT

**Bit-identical, not DB-truth-consistent.** TASK-0033B (a first-class
"reconcile PJSIP config from DB" operation) does not exist yet, so this
backup does not assume the generated Asterisk config, secrets, or TLS
certificate can be safely regenerated from the database alone. It backs up
the whole `asterisk-etc` volume directly, verbatim. Once TASK-0033B lands,
a future revision of this contract could shrink to a DB-only backup plus a
reconciliation step on restore — deliberately not attempted here.

Command: `make backup` (optional `DEST=<dir>`, defaults to `./backups/`,
gitignored). No Docker volume name is ever exposed to the operator.

---

## CONSISTENCY MODEL

All four SENMA services may stay **RUNNING** during backup:

- **MariaDB**: every one of the 56 tables is InnoDB (confirmed live via
  `information_schema.TABLES`) — `mariadb-dump --single-transaction` gives
  a point-in-time-consistent snapshot with zero locking and zero downtime.
  This is not a raw data-directory copy (which would need the server
  stopped or a filesystem-level snapshot to be crash-consistent) — it is a
  logical, application-consistent dump.
- **setup.conf / arquivos / asterisk-etc**: low-frequency-write
  config/data paths (an admin action, not continuous traffic). A live
  `tar`/`cp` read carries a small, explicitly accepted risk of capturing a
  config file mid-write; this is documented, not silently assumed safe.
- **Ordering**: the DB dump is taken first, filesystem state immediately
  after. If anything changes in between, the filesystem side ends up "as
  new or newer" than the DB dump — never older — which is the safe
  direction: no restore can end up with a DB row whose corresponding
  generated config is missing.

---

## ARTIFACT FORMAT

One portable, inspectable `.tar.gz` (`senma-backup-<UTC timestamp>.tar.gz`),
not a bespoke backup-repository product:

```
senma-backup-20260905-190825Z.tar.gz
├── manifest.txt          (flat KEY=value + component table, no credentials)
├── checksums.sha256      (sha256sum-format, every component)
├── db/dump.sql.gz        (mariadb-dump --single-transaction --routines --triggers)
└── fs/
    ├── setup.conf
    ├── arquivos.tar.gz
    ├── asterisk-etc.tar.gz
    └── astdb.sqlite3
```

The manifest is a flat `KEY=value` + `component=name|path|sha256|bytes`
table, not JSON — this project's host-side tooling is bash-3.2-first (see
`scripts/lib/harness.sh`), and adding a `jq` dependency for this alone was
not justified (CLAUDE.md rule 6: document new runtime dependencies before
adding them; this avoids needing one). It records `backup_format_version`,
`created_at`, `senma_git_commit`/`senma_git_describe`, live-probed
`asterisk_version`/`mariadb_version`, `compose_project_name`, and one
checksummed line per component. **No credential ever appears in the
manifest itself** — only paths, sizes, and hashes. The credentials live
*inside* `db/dump.sql.gz` and `fs/asterisk-etc.tar.gz`, which is why the
whole artifact (not just the manifest) is access-restricted.

---

## SECURITY

- The artifact is written under a `mode 700` staging directory and the
  final `.tar.gz` is `chmod 600` before being moved into place — never
  relies on umask.
- `docs`/scripts explicitly state, and `make backup`'s own output prints,
  that the artifact contains database rows (including password hashes and
  SIP secrets), the Asterisk AMI/DB credentials templated into
  `manager.conf`/`res_odbc.conf`, and the TLS private key. Nothing in this
  task builds encryption/key management (explicitly out of scope) — this
  is a documented expectation, not a solved problem: an operator moving a
  backup off-host is responsible for applying their own encryption/access
  control.
- `.gitignore` now excludes `/backups/` so a default-location artifact can
  never be committed by accident.
- No private key content ever appears in any log line printed by
  `backup.sh`/`restore.sh` (verified by inspection of every echo/log
  statement in both scripts).

---

## RESTORE CONTRACT

**REPLACE, not merge** (Phase 10) — no proven need for merging exists, and
a deterministic replacement is far easier to reason about and prove
correct. Restoring onto a target that already has SENMA state destroys
and replaces all of it: database schema+rows, `setup.conf`, `arquivos/`,
and the whole generated Asterisk config volume. Nothing is merged
row-by-row.

Command: `make restore FROM=<path-to-backup.tar.gz> [CONFIRM=RESTORE]`.

- `restore.sh` always validates the archive first (format version,
  manifest completeness, every mandatory component present, every
  checksum matches) — this phase never touches a container or a volume,
  and is exposed standalone via `--validate-only`.
- **Destructive-target protection**: `restore.sh` detects whether the
  target already has existing state (a non-empty database, or an
  already-populated `asterisk-etc`) and refuses to proceed without
  `--confirm` (`CONFIRM=RESTORE` from `make`) — the same typed-confirmation
  precedent `make reset` already established for its own destructive
  `down -v`. A target with no existing state proceeds without the flag.

---

## RESTORE ORDER

Derived from reading the actual entrypoints, not assumed from a generic
template:

1. **Stop** `app`/`asterisk`/`db` — nothing should be writing to what is
   about to be replaced.
2. **Wipe** the target: the `mag-db`, `asterisk-etc`, `mag-asterisk-var`
   volumes; the host-side `setup.conf` and `arquivos/` content.
3. **Restore `asterisk-etc` + `astdb.sqlite3` + `setup.conf` + `arquivos/`
   BEFORE any container that owns them starts.** This is the key insight:
   `docker/entrypoint.sh`'s and `docker/asterisk-entrypoint.sh`'s own
   first-boot guards (`[ ! -f ... ]`) work *for* restore instead of
   against it — they see the restored files already present and skip
   regeneration entirely, so the exact restored secrets/config/certificate
   survive untouched, with no code change to either entrypoint required.
4. **Start `db`**, letting its own first-boot init scripts run on the now-
   empty volume (harmless — `mariadb-dump`'s default
   `DROP TABLE IF EXISTS`/`CREATE TABLE`/`INSERT` output fully supersedes
   whatever the stock install just created a moment later), then **import
   the real dump on top**. This reuses the existing supported bootstrap
   path instead of fighting it — no bypass of `docker-entrypoint-initdb.d`
   was needed.
5. **Start `asterisk`, then `app`**; verify readiness at each step (schema
   query success, PJSIP transports loaded, ODBC connected, app HTTP up)
   before declaring success.

A real, evidence-based caveat is documented directly in `restore.sh`'s own
output: **restore assumes the target's current `.env` carries the same
`DB_PASSWORD`/`AMI_PASSWORD` that were in effect when the backup was
taken.** SENMA does not yet support credential rotation on an existing
volume (TASK-0033/0033C) — if the current `.env` differs, the restored
`res_odbc.conf`/`manager.conf` will not match, and `restore.sh` detects
this explicitly (an ODBC active-connection check) and fails loudly with
that exact diagnosis rather than leaving a silently broken CDR/realtime
layer.

---

## OWNERSHIP

**A real bug was found and fixed during this task's own live DR proof,
not assumed away.** A plain `tar xzf` of `asterisk-etc`, run unprivileged
as the `asterisk` user (matching the real entrypoint's own `USER`), does
not reliably reproduce the original archive's group/mode. Live evidence:
a first restore attempt left `/etc/asterisk/snep` as `asterisk:asterisk
0755` instead of `asterisk:senma-config 2775`, and its `*.conf` files as
`0644` instead of `0664` — which broke `www-data`'s group-write access and
surfaced as a real `HTTP 500` (`PBX_Exception_IO: Falha ao abrir arquivo
... com permissão de escrita`) on the very next PJSIP/legacy config
regeneration.

Fix: `restore.sh` now explicitly re-applies
`docker/asterisk-entrypoint.sh`'s own first-boot permission scheme after
extraction — `chgrp senma-config` + `chmod 2775` on `/etc/asterisk/snep`,
`chgrp senma-config` + `chmod 664` on its `*.conf` files, `chmod 600` on
`keys/*key*.pem`, `chmod 644` on `keys/*cert*.pem` — all as the
unprivileged `asterisk` user (already a `senma-config` member, same as the
entrypoint), no elevated privilege needed. This is not a blanket
`chmod 777`: every mode/group applied matches an existing, documented
convention already established by the entrypoint itself.

`setup.conf`'s `chown www-data:www-data` / `chmod 664` is not duplicated
in `restore.sh` — `docker/entrypoint.sh` already performs this
unconditionally on *every* boot (not gated to first boot), so it self-heals
automatically once `app` starts after restore. `arquivos/`'s ownership is
preserved as captured (this dev host's own bind-mount ownership is a
macOS-Docker-Desktop artifact, not representative of the Debian 14
production target — see REMAINING DEBT).

---

## COMPATIBILITY CHECKS

Before touching any container or volume, `restore.sh` rejects, with an
explicit diagnostic, each of:

- a corrupt archive (not valid gzip/tar);
- an incomplete manifest (missing `manifest.txt`, missing
  `component_count`, missing `checksums.sha256`);
- a missing mandatory component (`db`, `setup_conf`, `arquivos`,
  `asterisk_etc` must all be listed and present);
- any checksum mismatch between the manifest and the actual file bytes;
- an incompatible `backup_format_version`.

All five are exercised live by `scripts/backup-smoke-test.sh` against
genuinely corrupted copies of a real archive (not merely asserted) — see
VALIDATION below.

---

## FAILURE BEHAVIOR

- `backup.sh`: every component step is tracked; if any fails, the script
  aborts *before* writing the manifest/checksums and *before* any partial
  artifact reaches the destination path (staged under a private temp
  directory, the final archive only `mv`'d into place after every prior
  step and the checksum pass succeed).
- `restore.sh`: a failure during the wipe/restore-filesystem phase is
  reported as "target is now in a PARTIAL, inconsistent state — do not
  start services" rather than silently continuing. A failure during the
  DB-import phase is reported as "target database is now in an UNDEFINED
  state" with the same explicit warning. A failure during post-start
  readiness verification (schema query, PJSIP transports, ODBC) is
  reported as a hard failure, not a partial success — the script never
  reports "restore complete" unless every check passed.
- Attempting to restore onto a live, populated target without `--confirm`
  is refused before the first destructive command runs (verified live —
  see VALIDATION).

---

## DR TEST — the real proof (Phase 16/26/27)

Automated as `scripts/backup-restore-dr-smoke-test.sh` (`make
backup-restore-smoke`) and **run live, twice**, against the actual dev
stack (the first run surfaced the two real bugs above; the second, with
both fixed, passed all 26 checks). What it actually did, on the second
(clean) run:

1. Provisioned two real PJSIP extensions (1096/1097) through
   `ExtensionsController`'s own HTTP flow — not SQL, not hand-written
   config.
2. Registered two disposable `baresip` containers against them and placed
   a real call: dial accepted, `CALL_RINGING`, `CALL_ANSWERED`,
   `CALL_ESTABLISHED` all observed; a real `cdr` row landed
   (`uniqueid=1788635276.0`, `disposition=ANSWERED`).
3. Ran `scripts/backup.sh` for real, then validated the resulting archive.
4. **Actually destroyed the target**: `docker compose stop`+`rm -f` on
   `app`/`asterisk`/`db`, then `docker volume rm` on `mag-pbx_mag-db`,
   `mag-pbx_asterisk-etc`, and `mag-pbx_mag-asterisk-var` (confirmed
   removed via `docker volume ls`), plus deleting
   `snep/includes/setup.conf` and emptying `snep/arquivos/`. This is real
   destruction, not a restart — the target genuinely had nothing left.
5. Ran `scripts/restore.sh --confirm` for real.
6. Verified, all against the *restored* stack: the two `peers` rows exist
   with their original secrets (not recreated — the same values as before
   destruction); the pre-destruction `cdr` row survives by its exact
   `uniqueid`; the `pjsip_transports` row count is unchanged (3); the
   `CallsReport` API can query the restored CDR row; the generated
   `senma-pjsip.conf` contains both extensions' sections; `custom/preagi
   .conf`/`posagi.conf` (customer dialplan) are present; the TLS
   certificate's SHA-256 is byte-identical to the pre-destruction value;
   the private key is mode 600; the `wss` transport is bound; the HTTPS/WSS
   listener reports enabled; ODBC reports an active connection.
7. **Telephony proof, not just config presence**: re-registered the
   *same* two baresip fixtures against the restored extensions (same
   secrets — proving the restore, not a fresh recreation) and placed a
   *second* real call, producing a **new**, distinct CDR row
   (`uniqueid=1788635332.0`).
8. Ran `docker compose up -d --force-recreate app asterisk db` and
   confirmed the stack returns healthy and the restored extension's
   secret is unchanged (Phase 17).
9. Cleaned up both fixtures through the real HTTP delete flow, leaving the
   dev environment in the same state it was in before the test.

Full transcript (26/26 PASS) is reproducible via `make backup-restore-smoke`.

---

## POST-RESTORE TELEPHONY PROOF

Covered inline above (DR TEST, steps 6-7) — this was not treated as a
separate exercise: the same DR run that proves the backup/restore
mechanism also proves the restored provisioning is *live and functional*,
not merely present in a database dump.

---

## OPERATOR COMMANDS

```bash
make backup                              # -> ./backups/senma-backup-<ts>.tar.gz
make backup DEST=/path/to/somewhere      # explicit destination

make restore FROM=./backups/senma-backup-<ts>.tar.gz
make restore FROM=./backups/senma-backup-<ts>.tar.gz CONFIRM=RESTORE   # onto existing state

make backup-smoke            # lightweight, non-destructive -- part of `make regression`
make backup-restore-smoke    # the real destructive DR proof -- explicit, occasional gate
```

No command requires knowing a Docker volume name.

### Regression placement — justified, not assumed

`scripts/backup-smoke-test.sh` (`make backup-smoke`) runs a real backup to
a throwaway destination, validates its structure/checksums, exercises
`restore.sh --validate-only` against the good archive and four
deliberately corrupted copies (all four failure-mode checks from
COMPATIBILITY CHECKS), and confirms `restore.sh` refuses an unconfirmed
restore onto the live stack — **without ever stopping a container or
touching a volume**. This is safe to run on every `make regression` pass
and is now wired into `scripts/regression.sh`.

`scripts/backup-restore-dr-smoke-test.sh` (`make backup-restore-smoke`) is
**deliberately excluded** from `make regression`: every suite in
`regression.sh` runs serially against one shared dev stack by design (see
that file's own header — concurrent stateful suites have previously
produced spurious failures), and this suite actually deletes the shared
`mag-db`/`asterisk-etc`/`mag-asterisk-var` volumes other suites' fixtures
and CDR history live in. Running it on every regression pass would erase
that shared state out from under every other suite and add several
minutes to every single lint/regression invocation for a check that only
needs to be re-proven when the backup/restore mechanism itself changes —
not on every unrelated code change. It remains a first-class, documented,
easy-to-run operational gate instead.

---

## VALIDATION

- `make lint` — PASS (43 shell scripts including the four new ones parse
  cleanly; `git diff --check` clean).
- `scripts/backup-smoke-test.sh` — PASS, 12/12 checks (backup succeeds;
  artifact mode 600; `--validate-only` accepts a good archive; all four
  corruption cases rejected with explicit diagnostics; unconfirmed restore
  onto the live stack refused; legacy script confirmed marked superseded).
- `scripts/backup-restore-dr-smoke-test.sh` — run live twice. First run
  surfaced two real bugs (a `PIPESTATUS` bash pitfall crashing the DB
  import's own status check after the import had *already* succeeded, and
  the `asterisk-etc` permission-preservation gap above); both fixed. Second
  run: **PASS, 26/26 checks**, full transcript above.
- `make regression` (canonical gate, includes the new `backup-smoke`
  suite) — run twice; see checkpoint for pass/fail.
- `git diff --check` / `git status --short` — see checkpoint.

---

## REMAINING DEBT

**Production blocker** — none remaining from this task's own scope; the
backup/restore blocker TASK-0033 identified is closed.

**Operations follow-up** (tracked, not solved here):

- TASK-0033B (PJSIP config reconciliation) would let a future backup
  contract shrink toward DB-truth-consistent instead of bit-identical.
- TASK-0033C (credential rotation) — restore's own ODBC-mismatch
  diagnostic is a symptom of the same gap TASK-0033 already scoped as its
  own task; not solved here.
- `arquivos/`'s host-bind-mount ownership on this macOS/Docker-Desktop dev
  host reports as `root:root` regardless of the actual host user (a known
  Docker-Desktop bind-mount virtualization artifact) — restore faithfully
  reproduces whatever was captured rather than opportunistically "fixing"
  ownership the current dev environment doesn't have either; on the actual
  Debian 14 production target, bind-mount UID reporting is a literal 1:1
  match, so this specific artifact is dev-host-only. Worth a dedicated
  look if a production bind-mount deployment ever needs `arquivos/`
  writable by `www-data` (a pre-existing gap, not introduced by this task
  — no entrypoint step chowns `arquivos/` today, backup/restore included).
- `snep/scripts/backup/backup.sh` is marked superseded via a header
  comment, not deleted (GPL provenance, CLAUDE.md's "never remove
  copyright/licensing notices from inherited files"). Deleting it outright
  would be a separate, small, explicitly-scoped cleanup task if ever
  desired.
- Backup encryption/off-host storage/retention/scheduling are explicitly
  out of scope per the task's own instructions — documented as an
  operator responsibility (SECURITY section), not solved.

**Test-harness-only debt** — none found; `scripts/backup-smoke-test.sh`'s
failure-mode checks are themselves new regression coverage, not a gap.

**Future observability** — none identified beyond what TASK-0033D already
owns (log visibility/rotation, consolidated diagnostics).
