# TASK-0035E8 — Shared Call Recording Storage & Permissions Hardening

**Status:** implementation complete — awaiting checkpoint authorization
**Decision:** recorded in agent checkpoint (`RECORDING_STORAGE_*`)
**Depends on:** TASK-0035E2 (host networking), TASK-0035E4/E4A (immutability), TASK-0035E5 (restore topology)
**Does not:** commit, push, tag, deploy, mutate `regras_negocio.record`, touch `tmp-0035a/`

## Final decision (checkpoint)

```text
RECORDING_STORAGE_PASS_WITH_CONSTRAINTS
```

Constraints:

1. Pilot live MixMonitor proof is deferred (`PILOT_RECORDING_PROOF_PENDING`).
2. Asterisk waits up to 60s for app entrypoint to finish directory init
   (`depends_on app service_started` can race first-line chown).
3. Host operators not in GID 3000 cannot list `snep/arquivos` (mode 2770);
   backup archives via the app container for that reason.
4. Next RC after merge must be `v0.1.0-rc.9` (do not mutate rc.8).
5. During gate runs, a pre-existing intermittent `transport-smoke` check
   (`AUTO endpoint remains valid`) failed once between otherwise clean
   consecutive PASS pairs; classified unrelated to recording storage
   (same check PASS on adjacent runs; no E8 touch of PJSIP transport load).

## Real gap

Before this task:

- App bind: `./snep` → `/var/www/html/snep` (rw)
- Asterisk bind: `./snep` → `/var/www/html/snep` (**:ro**)
- MixMonitor target via AGI: `path_voz` = `/var/www/html/snep/arquivos/`
- `/var/spool/asterisk/monitor` did not exist / was not shared
- Host `snep/arquivos` often `755` owned by the checkout user — Asterisk
  UID could not write

Result: even with `regras_negocio.record = 1`, recordings could not land
on the canonical host path.

## Business-rule semantics (unchanged)

Recording remains a business-rule flag:

```text
regras_negocio.record = 0  →  no MixMonitor (policy)
regras_negocio.record = 1  →  MixMonitor to shared store
```

This task does **not** flip defaults or pilot rule rows. Absence of a
file when `record=0` is not a storage failure.

## Canonical storage contract

```text
HOST
./snep/arquivos
    │
    ├── app container
    │   /var/www/html/snep/arquivos   (path_voz)
    │
    └── asterisk container
        /var/spool/asterisk/monitor
        /var/www/html/snep/arquivos   (rw override of :ro ./snep tree)
```

One host directory. No anonymous recording volume. No sync/copy job.

Defined in `compose.yaml` (base). `compose.pilot.yaml` does not override
recording mounts (host-network overlay only).

## UID/GID model

| Identity | UID/GID (live) | Notes |
|---|---|---|
| www-data (app) | 33:33 + group 3000 | Debian `php:8.4-apache` |
| asterisk | system UID (live 997) + group 3000 | `useradd -r` (not pinned) |
| senma-config | **GID 3000** (pinned both images) | shared group |

## Permission model

Directory-level only (no recursive archive rewrite):

```text
owner: www-data
group: senma-config (3000)
mode:  2770 (setgid)
```

- Asterisk creates recordings via **group write**
- App reads / lists / deletes (`Manutencao::removeBackup`) via owner+group
- **No 0777 / world-write**
- Unprivileged host users not in GID 3000 cannot list recordings (intentional)
- New process umask in Asterisk entrypoint: `0007` (group-readable files)
- Dated subdirs created by AGI with mode `0770` when missing

## Initialization

| Component | Role |
|---|---|
| `docker/entrypoint.sh` (app, root) | `mkdir -p`, `chown www-data:senma-config`, `chmod 2770`, refuse world-write — **first lines** |
| `docker/asterisk-entrypoint.sh` | require monitor mount; bounded wait for writability; refuse world-write; `umask 0007` |
| Compose ordering | `asterisk depends_on app: service_started`; app no longer waits on asterisk |
| `scripts/restore.sh` | after `arquivos` extract, re-apply `chgrp 3000` + `chmod 2770` |

## AGI / monitor.php

- `monitor.php` — filename + CDR `userfield` only (unchanged)
- `snep/agi/snep.php` — prefers writable `/var/spool/asterisk/monitor` for
  MixMonitor path when present; creates `YYYY-MM-DD` subdirectory; filename
  / format / CDR linkage preserved

## Backup / restore

- Backup archives `snep/arquivos` as mandatory component `arquivos`
- TASK-0035E8: archive runs **via the app container** (`senma_compose_run`)
  because host mode `2770` blocks unprivileged host-side `tar`
- Restore extracts to the same host path and reapplies the 2770 contract
- No second recording backup component

## Tests

```bash
make recording-storage-smoke
```

Also wired into `make regression`.

## Pilot validation plan

Status: **`PILOT_RECORDING_PROOF_PENDING`**

After future RC (`v0.1.0-rc.9`):

1. Verify mounts on host/pilot
2. Verify `snep/arquivos` mode 2770 / group 3000
3. Temporarily use a rule with `record=1`
4. Place a controlled internal call
5. Confirm file on host, under monitor, and via app/UI
6. Restore original `record` policy if changed manually

## E7 impact

```text
TASK-0035E7 remains paused
TASK-0035 not closed
next RC after E8 merge: v0.1.0-rc.9
pilot recording proof required before E7 resumes
```

## Proposed commit split

1. `fix(recording): share canonical recording storage safely`
2. `test(recording): cover shared storage and permissions`
3. `docs(recording): record TASK-0035E8 storage contract`
