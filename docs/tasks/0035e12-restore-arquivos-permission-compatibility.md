# TASK-0035E12 — Restore Arquivos Permission Compatibility

**Status:** implementation complete — awaiting checkpoint authorization  
**Decision:** `RESTORE_ARQUIVOS_PERMISSION_PASS_WITH_CONSTRAINTS`  
**Debt closed:** `BACKUP_RESTORE_ARQUIVOS_HOST_PERMS_DEBT` (discovered in TASK-0035E11)  
**Depends on:** TASK-0035E8 (recording storage 2770), TASK-0035E11 (astdb staging), TASK-0035E5 (restore topology)  
**Does not:** commit, push, tag, deploy, mutate `v0.1.0-rc.10`, destructive restore on TEXTE-PBX-001, touch `tmp-0035a/`

## Final decision (checkpoint)

```text
RESTORE_ARQUIVOS_PERMISSION_PASS_WITH_CONSTRAINTS
```

Constraints:

1. Pilot real destructive restore proof deferred: `PILOT_RESTORE_ARQUIVOS_PROOF_PENDING`.
2. Host deploy uid remains outside GID 3000 and cannot traverse `snep/arquivos` (intentional E8).
3. TASK-0035E7 remains paused; no RC cut in this task.
4. Stale DR-smoke assertion expecting Asterisk `HTTPS Server Enabled` was realigned to TASK-0035A private WS `:8088` (masked until arquivos restore unblocked the rest of the suite).

## Origin / debt

During TASK-0035E11 validation:

```text
make backup-restore-smoke → FAIL
host-side restore of snep/arquivos → Permission denied
```

Debt name: **`BACKUP_RESTORE_ARQUIVOS_HOST_PERMS_DEBT`**. Intentionally excluded from E11 (no recording/restore topology changes there).

## E8 permission contract (unchanged)

```text
Host:     ./snep/arquivos
App:      /var/www/html/snep/arquivos   (path_voz; ./snep bind)
Asterisk: /var/spool/asterisk/monitor + /var/www/html/snep/arquivos

owner: www-data
group: senma-config (GID 3000)
mode:  2770 (setgid)
files: preferred 0660 (not world-readable)
```

Host deploy user is **not** required to join GID 3000.

## Failure reproduction (pre-change)

`make backup-restore-smoke` against live E8 tree:

| Step | Actor | Result |
|---|---|---|
| `rm -rf snep/arquivos` (smoke destroy + restore wipe) | host uid 1000 | `Permission denied` |
| `tar xzf …/arquivos.tar.gz -C snep` | host uid 1000 | `Cannot mkdir: Permission denied` |
| `chmod 2770 snep/arquivos` | host uid 1000 | `Operation not permitted` |

Evidence at failure:

| Item | Value |
|---|---|
| Host identity | uid=`1000` (`ubuntu`), groups without `3000` |
| `./snep` | `755` `ubuntu:ubuntu` |
| `./snep/arquivos` | `2770` `www-data:3000` |
| Failing ops | host `rm` / `mkdir` / `tar` extract / `chmod` |

Not an E8 bug: E8 intentionally restricts host access. Backup already archived via the app container; restore still did host-side extraction.

## Restore flow (after this task)

```text
archive fs/arquivos.tar.gz
  → STAGE_DIR (host, readable)
  → senma_compose_run app (root, --entrypoint bash, --pull never)
       wipe contents of /var/www/html/snep/arquivos
       tar xzf /restore-input/arquivos.tar.gz -C /var/www/html/snep
       chown -R www-data:senma-config  (arquivos subtree only)
       dirs 2770 / files 0660
  → same host inode ./snep/arquivos
  → app path_voz + asterisk monitor mounts
```

| Portion | Where | Identity |
|---|---|---|
| Archive assembly (backup) | app container | root ephemeral (`senma_compose_run`) |
| Wipe / extract / normalize | app container | root ephemeral |
| setup.conf copy | host | deploy uid (parent `snep/includes` is writable) |
| asterisk-etc / astdb / moh / sounds | asterisk ephemeral | as before (E5/E3) |
| Final app/asterisk runtime | running services | www-data + asterisk (+ GID 3000) |

## Architecture decision

**Chosen: A — restore arquivos through the app container** (existing `./snep` bind / path_voz).

Rejected:

| Option | Why rejected |
|---|---|
| B helper container GID 3000 | Unnecessary when app image already has root entrypoint capability + senma-config + correct mounts |
| C add deploy to senma-config | Host membership requirement; weakens E8 operator boundary |
| D weaken 2770 / world bits | Forbidden; regresses E8 |
| E privileged / root host extract / docker.sock | Excess privilege |

No archive format change. No `chmod 0777` / `2777`. No `chown -R ./snep`.

## Implementation

| File | Change |
|---|---|
| `scripts/lib/backup-lib.sh` | `blib_wipe_recording_store`, `blib_restore_recording_store`, `blib_apply_recording_dir_contract` via `senma_compose_run` app |
| `scripts/restore.sh` | Phase C/D use container wipe/restore; keep `restore_recording_dir_contract` marker |
| `scripts/backup-restore-dr-smoke-test.sh` | Container wipe on destroy; E12 R/W/same-backing/host-negative proofs; 0035A WS listener assertion |
| `scripts/recording-storage-smoke-test.sh` | Contract grep updated for container-aware helpers |

Resulting modes after restore:

| Path | Owner/mode |
|---|---|
| `snep/arquivos` root | `www-data:senma-config` `2770` |
| Nested dirs | `2770` (setgid preserved) |
| Restored files | `0660` |

## Host membership

**Not required.** Restore succeeds while host `ls snep/arquivos` remains `Permission denied`.

## Failure / cleanup / idempotency

- Ephemeral `compose run --rm` exits cleanly; staging uses existing restore extract cleanup.
- Normalization scoped to `/var/www/html/snep/arquivos` only.
- Second restore of the same archive succeeds without broadening modes (focused helper proof).

## Tests

| Gate | Result |
|---|---|
| `make backup-restore-smoke` | **PASS** (35/35) — primary closure |
| `make restore-runtime-topology-smoke` | **PASS** (11/11) |
| `make recording-storage-smoke` | **PASS** (13/13) |
| `make backup-smoke` | **PASS** (19/19; E11 remains green) |
| `make release-immutability-smoke` | **PASS** (14/14) |
| `make admin-bootstrap-smoke` | **PASS** (21/21) |
| `make lint` | **PASS** (5/5) |
| `make regression` × 2 consecutive | **PASS** / **PASS** (no repair between runs) |
| `git diff --check` | **PASS** |

## Security check

Rejected / absent:

- `chmod 777` / `666` / recursive broad weaken
- `chown -R` on entire `./snep`
- hidden deploy→senma-config membership
- privileged containers / docker.sock mounts

Final arquivos root remains **2770**.

## Pilot impact

```text
PILOT_RESTORE_ARQUIVOS_PROOF_PENDING
```

Do **not** run destructive restore on TEXTE-PBX-001 in this task. A future real pilot restore needs explicit authorization. Because E8 restore semantics changed, the old rc.6 destructive restore proof is **not** sufficient for final E7 closure.

## E7 / release

TASK-0035E7 remains **paused**. No release candidate in this task. Do not mutate `v0.1.0-rc.10`.

Expected sequence:

```text
E12 merge → E10 security → next RC → pilot validation → explicit real restore decision/proof → E7 final
```

## Proposed commit split (not committed)

1. `fix(restore): restore arquivos through permission-aware runtime`
2. `test(restore): cover E8 recording storage permissions`
3. `docs(restore): record TASK-0035E12 closure`
