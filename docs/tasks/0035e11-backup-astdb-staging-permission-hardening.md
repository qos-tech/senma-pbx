# TASK-0035E11 — Backup astdb Staging Permission Hardening

**Status:** `BACKUP_ASTDB_PERMISSION_PASS_WITH_CONSTRAINTS`
**Depends on:** TASK-0033A (backup/restore foundation), TASK-0035E4/E4A
(immutability), TASK-0034I-R1 (discovered the blocker during validation)
**Does not:** mutate `v0.1.0-rc.10`, deploy, change live astdb ownership,
reopen recording/admin/System Status scope

## Origin

During TASK-0034I-R1 validation, canonical regression hit:

```text
backup-smoke -> astdb.sqlite3: Permission denied
KNOWN_EXTERNAL_GATE_BLOCKER: backup staged astdb host-readable
```

The astdb staging fix was prototyped then **intentionally excluded** from
the 0034I-R1 PR to preserve System Status scope. This task lands that fix.

## Failure reproduction (pre-change)

`make backup-smoke` → BLOCKED:

```text
sha256sum: .../fs/astdb.sqlite3: Permission denied
tar: .../fs/astdb.sqlite3: Cannot open: Permission denied
ERROR: assembling final archive failed
```

## astdb backup flow

| Stage | Path | Actor |
|---|---|---|
| Live source | `/var/lib/asterisk/astdb.sqlite3` (named volume `mag-asterisk-var`) | Asterisk container uid `997` |
| Copy | `docker compose run … asterisk` → `cp` into bind-mounted `STAGE_DIR/fs` | container user `asterisk` (997) |
| Staging | `$STAGE_DIR/fs/astdb.sqlite3` on host | owner 997, mode preserved from source |
| Manifest / checksums | host `scripts/backup.sh` + `blib_sha256` | host operator uid (here `1000`) |
| Final archive | `tar czf` of staging tree → `blib_secure_path` → `0600` | host operator |

### Evidence (this environment, before fix)

| Item | Value |
|---|---|
| Source mode/owner | `0640` `997:997` (`asterisk:asterisk`) |
| Staged mode/owner after bare `cp` | `0640` `997:997` |
| Host assembler | uid `1000` (`ubuntu`) — not in group 997 |
| Host `sha256sum` on staged file | `Permission denied` |
| Live hash after bare `cp` | unchanged (copy does not mutate live) |

Root cause: `cp` preserves `0640` owned by uid 997 onto the host bind mount;
the host-side assembler cannot read group/other-denied bits.

## Implementation

`scripts/backup.sh` `copy_astdb()`:

```sh
if test -f /var/lib/asterisk/astdb.sqlite3; then
  cp /var/lib/asterisk/astdb.sqlite3 /backup-output/astdb.sqlite3 \
    && chmod 0644 /backup-output/astdb.sqlite3
else
  echo "[backup] astdb.sqlite3 not present yet -- skipping ..."
fi
```

- chmod applies **only** to `/backup-output/astdb.sqlite3` (staged)
- live `/var/lib/asterisk/astdb.sqlite3` is never chmod'd
- astdb remains optional when absent
- final archive still `blib_secure_path` → mode `0600`
- no `chmod -R 777` / `666` introduced

## Proofs

| Proof | Result |
|---|---|
| Live mode/owner/hash identical before vs after backup | PASS |
| Staged mode `644`; staged sha256 == live sha256 | PASS |
| Final archive mode `600` | PASS |
| `tar -tzf` shows exactly one `astdb.sqlite3` when present | PASS |
| `restore.sh --validate-only` accepts archive | PASS |
| Static: staged-only chmod; no broad weakening | PASS |

## Tests

- Extended `scripts/backup-smoke-test.sh` with the proofs above
- Primary gate: `make backup-smoke` → **PASS (19/19)**
- Also: restore-runtime-topology, release-immutability, recording-storage,
  admin-bootstrap → PASS
- Canonical `make regression` × 2 consecutive → **PASS / PASS** (no
  manual repair between runs). The previous
  `KNOWN_EXTERNAL_GATE_BLOCKER: backup staged astdb host-readable` is closed.
- `make backup-restore-smoke` → FAIL on **host-side `snep/arquivos/` restore
  under E8 mode 2770** (`Permission denied` on mkdir/chmod), **not** on astdb.
  Debt name: **`BACKUP_RESTORE_ARQUIVOS_HOST_PERMS_DEBT`**.
  **Intentionally excluded from E11** (task forbids changing recording
  storage / restore topology / `scripts/restore.sh`). Non-destructive astdb
  acceptance remains covered by `--validate-only`.

## Missing astdb

Unchanged optional semantics: if live file absent, copy step skips; manifest
omits `asterisk_astdb`; backup continues.

## Pilot / E7

No deploy in this task. No tag and **no release candidate created here**.
After E10 + E11 + 0034I-R1 are merged, create the next combined RC.
`v0.1.0-rc.10` remains intact and must not be mutated.
TASK-0035E7 remains paused.

## Decision

`BACKUP_ASTDB_PERMISSION_PASS_WITH_CONSTRAINTS`

Constraint: `BACKUP_RESTORE_ARQUIVOS_HOST_PERMS_DEBT` (E8 host restore of
`snep/arquivos` under 2770 — separate task; deliberately out of this PR).
