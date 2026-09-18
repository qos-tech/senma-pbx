# TASK-0034I-R4 — Queue Runtime Initialization + AMI Failure Hardening

**Status:** local implementation checkpoint (see FINAL DECISION in agent report)
**Depends on:** TASK-0034I-R1/R2/R3, TASK-0007 (Realtime queues), v0.1.0-rc.14 pilot evidence
**Does not:** mutate `v0.1.0-rc.14`, deploy, create `v0.1.0-rc.15`, reopen LDAP,
duplicate Realtime queue definitions into static `queues.conf`

## Pilot evidence (TEXTE-PBX-001 / v0.1.0-rc.14)

PHP Warning:

```text
foreach() argument must be of type array|object, false given
/var/www/html/snep/includes/AMI.php:301
```

Call chain:

```text
ip_status_queues.php → AMI::get_queues() → sendrecv(Action=QueueStatus) → false/Error → foreach
```

Runtime root cause (not merely PHP):

| Check | Result |
|---|---|
| `module show like app_queue` | **Not Running** |
| `module load app_queue.so` | Unable to load / declined |
| Asterisk log | `No call queueing config file (queues.conf), so no call queues` |
| Asterisk log | `app_queue declined to load` |
| `core show application Queue` | not registered |
| `manager show command QueueStatus` | unavailable |
| `/etc/asterisk/queues.conf` | **absent** |
| `ldd app_queue.so` | PASS (no missing libs) |
| `modules.conf` | `autoload=yes` |
| `extconfig.conf` | `queues` + `queue_members` → ODBC `snep` |

`queuerules.conf` absence only produces a NOTICE (`queues will not follow
penalty rules`). SENMA does not use Asterisk queue penalty rules files;
member `penalty` columns in `queue_members` are unrelated. No
`queuerules.conf` added.

LDAP `res_config_ldap` / missing `res_ldap.conf` noise is **unrelated**
technical debt — does not affect ODBC Realtime queue init.

## Architecture findings

### A. Realtime-backed queues (intentional)

`docker/asterisk-config/extconfig.conf` (TASK-0007):

```text
queues => odbc,snep,queues
queue_members => odbc,snep,queue_members
```

Canonical tables: `queues`, `queue_members` (SENMA schema; UI via
`QueuesController` / `Snep_Queues_Manager`).

### B. Historical `queues.conf`

`snep/install/etc/asterisk/queues.conf` existed in the legacy install tree
with `[general]` defaults and **commented-out** example queue stanzas.
Docker bootstrap (TASK-0005) deliberately did **not** copy it into
`docker/asterisk-config/`, so named volumes never received it.

### C. `app_queue` startup contract (proven live)

| `queues.conf` state | `module load app_queue.so` |
|---|---|
| absent | declines / Not Running |
| empty file | Running |
| `[general]` only (no queue stanzas) | Running |

Empty file is sufficient for module startup. Canonical file still ships
historical `[general]` defaults (`persistentmembers`, `MixMonitor`, etc.)
so Realtime queues inherit legacy global behavior without becoming a
second source of truth for queue objects.

### D. Lifecycle decision

| Property | Decision |
|---|---|
| Form | Committed static minimal file under `docker/asterisk-config/queues.conf` |
| Seed | Entrypoint independent guard (like `musiconhold.conf` / `rtp.conf`) when missing |
| Overwrite | Never overwrite an already-present operator file |
| Queue objects | Realtime / DB only — no static queue stanzas |
| Fresh install | First-boot `*.conf` copy + missing-file retrofit |
| Recreate | Survives `force-recreate` via volume + seed-if-missing |
| Backup/restore | Covered by `asterisk-etc` volume archive; old backups without the file are repaired by entrypoint seed on next start |
| Secrets | None |

## PHP hardening

### `AMI::get_queues()`

Documented contract: array on success, false on failure.

Before foreach:

1. `false` / non-array → `false`
2. AMI `Response: Error` packet(s) (e.g. QueueStatus unavailable when
   `app_queue` is Not Running) → `false`
3. Otherwise parse `QueueParams` / `QueueMember` as before
4. Zero queues after successful QueueStatus → `[]` (not false)

Do not cast false to array, use `@`, or treat Error as empty success.

### `ip_status_queues.php`

- `get_queues() === false` → HTTP 503 + `null` (AJAX success path skipped;
  no fabricated rows; no foreach warning)
- success empty → HTTP 200 + `[]`
- success with queues → unchanged JSON shape

## LDAP classification

**Separate technical debt.** `res_config_ldap` NOTICE/ERROR on missing
`res_ldap.conf` does not block ODBC Realtime queues. Out of scope for R4.

## Doctor recommendation

**Recommend** adding a doctor check: `app_queue.so` Running (WARN or FAIL).
Queues are a supported SENMA feature; rc.14 pilot proved absence is a
silent runtime hole. **Not implemented in this task** — report-only per
task instruction to avoid expanding doctor scope without explicit approval.

## Release / E7

- `v0.1.0-rc.14` remains **immutable**
- Do **not** create `v0.1.0-rc.15` in this task
- Next RC after merge: **v0.1.0-rc.15**
- TASK-0035E7 remains **BLOCKED** until this queue runtime fix merges and
  a subsequent RC carries it

## Validation

Focused: `make queue-runtime-smoke` → **PASS**

Also required by task:

| Gate | Result |
|---|---|
| `make system-status-runtime-smoke` | PASS |
| `make systemstatus-dashboard-smoke` | PASS |
| `make status-detail-ux-smoke` | PASS |
| `make restart-smoke` | PASS |
| `make doctor-smoke` | FAIL — only `Release artifact identity` DRIFT (`senma-*:dev` rebuilt for this task vs immutable `release-manifest.json` for `v0.1.0-rc.14`). Not queue-related. |
| `make host-networking-architecture-smoke` | PASS |
| `make lint` | PASS |
| `make regression` #1 | FAIL (sole suite FAIL: `doctor-smoke`, same DRIFT) |
| `make regression` #2 | FAIL (sole suite FAIL: `doctor-smoke`, same DRIFT; consecutive identical) |
| `git diff --check` | PASS |

**Constraint:** While `release-manifest.json` records immutable rc.14 and the local stack runs rebuilt `:dev` images (required to pick up `asterisk-entrypoint.sh` queues.conf seed), doctor intentionally FAILs release-identity DRIFT. Do not mutate `release-manifest.json` or retag rc.14 to green the gate.

## Files touched

- `docker/asterisk-config/queues.conf` (new)
- `docker/asterisk-entrypoint.sh` (seed-if-missing)
- `snep/includes/AMI.php` (`get_queues` failure contract)
- `snep/includes/ip_status_queues.php` (false vs empty)
- `scripts/queue-runtime-smoke-test.sh` (new)
- `Makefile` / `scripts/regression.sh`
- this document
