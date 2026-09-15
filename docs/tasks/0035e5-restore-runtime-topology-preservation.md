# TASK-0035E5 — Restore Runtime Topology Preservation

**Status:** `RESTORE_RUNTIME_TOPOLOGY_PASS_WITH_CONSTRAINTS`
**Incident:** I8 — Restore does not preserve pilot/production runtime topology
**I8 implementation:** `I8 IMPLEMENTATION_CLOSED`
**I8 operational:** `I8 PILOT_RUNTIME_PROOF_PENDING` (not `I8 CLOSED` / not `RESTORE PASS`)
**Depends on:** TASK-0033A (backup/restore REPLACE), TASK-0035E2 (host networking), TASK-0035E4 (release immutability)
**Does not:** create tags, push, merge, or touch `tmp-0035a/`

## Contract summary

| Context | Compose | Rule |
|---|---|---|
| pilot / release restore | `compose.yaml` + `compose.pilot.yaml` | host networking |
| dev restore | `compose.yaml` | bridge networking |
| ambiguous runtime | — | **FAIL CLOSED** |
| restore recreate | — | **NO BUILD** (`--no-build`) |

Do **not** mark `I8 CLOSED` or operational `RESTORE PASS` until a real-pilot
destructive restore (without manual `make pilot-up`) proves:

- host topology preserved after restore
- bindings: `127.0.0.1:3306`, `127.0.0.1:5038`, `127.0.0.1:8088`, `*:8080`, `:5060` TCP/UDP
- `release-info` MATCH
- application/data integrity
- SIP/WebRTC after restore

## Starting state

| Item | Value |
|---|---|
| Branch context | post-E4 (`cursor/release-immutability-0035e4` / main after merge) |
| Pilot evidence | `v0.1.0-rc.5` restore recreated bridge topology; manual `make pilot-up` fixed host mode |
| I8 | OPEN at task start → `IMPLEMENTATION_CLOSED` / `PILOT_RUNTIME_PROOF_PENDING` |

## Root cause

`scripts/restore.sh` used:

```bash
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
```

Destructive recreate (`up -d --no-build`) therefore always targeted **base `compose.yaml` (bridge)** unless an undocumented `SMOKE_COMPOSE` override was set.

`make restore` did not wire `COMPOSE_FILES` / pilot overlay the way `make pilot-up` does.

Data REPLACE semantics from TASK-0033A succeeded; **runtime topology was lost**.

## Final restore runtime contract

| Mode | Selection | Compose |
|---|---|---|
| **host / pilot** | `SENMA_RUNTIME_MODE=host`, or `COMPOSE_FILES` includes `compose.pilot.yaml`/`compose.host.yaml`, or `RELEASE_VERSION != dev` | `docker compose -f compose.yaml -f compose.pilot.yaml` |
| **bridge / dev** | `SENMA_RUNTIME_MODE=bridge`, or `RELEASE_VERSION=dev` (default), or explicit bridge `SMOKE_COMPOSE` | `docker compose` |

Resolution lives in `scripts/lib/compose-runtime.sh` (single authority).

**Fail closed:**

- host mode + missing release images → ERROR (never build)
- host mode + `RELEASE_VERSION=dev` → ERROR (unless `SENMA_ALLOW_HOST_DEV=1` test-only)
- mixed running host/bridge services when inference is required → ERROR
- ambiguous topology with no release/dev signal → ERROR

**Precedence (high → low):**

1. explicit `SENMA_RUNTIME_MODE` / `RESTORE_RUNTIME_MODE`
2. `COMPOSE_FILES` / qualified `SMOKE_COMPOSE`
3. `RELEASE_VERSION != dev` → host (beats stale bridge containers after a broken restore)
4. infer from running containers
5. `RELEASE_VERSION=dev` → bridge
6. fail closed

## Make restore contract

```make
make restore FROM=... [CONFIRM=RESTORE]
```

- If `RELEASE_VERSION` is a release tag → automatically sets `SENMA_RUNTIME_MODE=host` and pilot `COMPOSE_FILES` (same files as `pilot-up`)
- If `RELEASE_VERSION=dev` → bridge
- Never builds (`--no-build` inside restore.sh)
- Preserves `RELEASE_VERSION` for image tags (`senma-*:$RELEASE_VERSION`)

## Direct script contract

```bash
scripts/restore.sh backup.tar.gz --confirm
scripts/restore.sh --print-runtime
```

Same resolver. Operators must not rely on silent bridge default for production.

Supported pilot path:

```bash
export RELEASE_VERSION=vX.Y.Z
make restore FROM=./backups/senma-backup-….tar.gz CONFIRM=RESTORE
```

## Post-restore verification

After readiness checks, restore verifies:

- **host:** `NetworkMode=host` for app/asterisk/db; no `PortBindings`
- **bridge:** services are not host-networked
- SENMA image IDs for `senma-app` / `senma-asterisk` at `$RELEASE_VERSION` unchanged (E4)

## Data restore

Unchanged REPLACE semantics from TASK-0033A (DB, setup.conf, arquivos/, asterisk-etc, astdb, MOH/sounds, checksums, readiness).

## Tests

`make restore-runtime-topology-smoke` / `scripts/restore-runtime-topology-smoke-test.sh`

Wired into `make regression`.

## Real pilot revalidation (after next RC)

1. backup → validate
2. capture topology
3. destructive restore **without** manual `make pilot-up`
4. prove host mode + bindings + release-info MATCH + secrets/doctor/reconcile + REGISTER + audio

Only then mark operational `RESTORE PASS` on the live pilot. Implementation/regression closure does not replace that host proof.

## Decision (filled after gates)

**`RESTORE_RUNTIME_TOPOLOGY_PASS_WITH_CONSTRAINTS`**

I8: **IMPLEMENTATION_CLOSED** / **PILOT_RUNTIME_PROOF_PENDING**

### Gate evidence

| Gate | Result |
|---|---|
| `make restore-runtime-topology-smoke` | **PASS** (11/11) |
| `make lint` | **PASS** |
| `make regression` A | **PASS** (`REGRESSION_A_EXIT:0`, 2026-09-15T17:49:49Z–18:08:32Z) |
| `make regression` B | **PASS** (`REGRESSION_B_EXIT:0`, 2026-09-15T18:08:32Z–18:27:18Z) |
| Consecutive A→B | **PASS** — no manual repair/restart between runs |
| `restore-runtime-topology` in A+B | **PASS** both |
| `git diff --check` | **PASS** |

Earlier interrupted sequence (`/tmp/e5-regression1.out` PASS,
`/tmp/e5-regression2.out` FAIL) is **not** the consecutive gate pair.
R2 failed only on `transport-smoke`: config stanza present (`AUTO
extension has no transport= line` PASS) but immediate
`pjsip show endpoint 1098` returned unload (`endpoint did not load`).
Focused `make transport-smoke` afterward **PASS** (65/65). Classified
**unrelated transient Asterisk reload race** (not E5 / not restore
topology). Subsequent consecutive A+B both had `transport-smoke` PASS.

### Constraints

- Live destructive restore on a host-networked pilot (without manual
  `make pilot-up`) remains the authoritative I8 closure proof — schedule
  on the next RC after merge.
- Loopback binding probes (`127.0.0.1:3306/5038/8088`, `*:8080`, SIP
  `:5060`) are required on that pilot revalidation; this task proves
  compose selection + `network_mode=host` + no PortBindings + no-build.
- `backup-restore-smoke` (destructive DR) remains outside canonical
  regression; data REPLACE contract unchanged from TASK-0033A.
