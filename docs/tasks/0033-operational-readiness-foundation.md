# TASK-0033 — Operational Readiness Foundation

Status: architecture/audit — review only, no implementation performed.
Lead: senma-application-architect. Reviewers: senma-docker-platform-engineer,
senma-telephony-architect. senma-product-designer not invoked (no
user-facing workflow/state changed by this task itself; see TASK SPLIT for
where a future task may need it).

This document is the FASE 5 (Operations) foundation. It inventories the
current runtime stack against the full install→boot→ready→operate→
degrade→restart→recover→backup→restore→diagnose→upgrade lifecycle, and
converts the findings into a concrete implementation roadmap. All findings
below come from direct inspection of the live dev stack (`docker compose
ps` showed `app`, `asterisk`, `db`, `provider` all healthy throughout this
audit) and the current repository checkout — not from historical
documentation alone, per the project's evidence hierarchy.

---

## SERVICE TOPOLOGY

Four services, one Compose network (`mag`, pinned `172.28.0.0/16`), no
resource limits configured anywhere (confirmed via `docker inspect
.HostConfig.Memory`/`.NanoCpus` = 0 on all four containers).

| Service | Image/build | Ports | Volumes | depends_on | Healthcheck | Restart |
|---|---|---|---|---|---|---|
| **app** | `docker/app.Dockerfile` | `8080→80` | bind `./snep`→`/var/www/html/snep` (rw); vol `asterisk-etc`→`/etc/asterisk` (ro from app) | `db`(healthy), `asterisk`(healthy) | `curl -f http://localhost/` (10s/5s/10r/15s) | unless-stopped |
| **asterisk** | `docker/asterisk.Dockerfile` | none published (AMI 5038 internal only) | vol `asterisk-etc`, `mag-asterisk-var`, `mag-asterisk-spool`, `mag-asterisk-log`; bind `docker/asterisk-config`(ro), `snep/install/etc/asterisk*`(ro), `./snep`(ro) | none | `asterisk -rx "core show version"` (10s/5s/10r/15s) | unless-stopped |
| **provider** | `docker/asterisk.Dockerfile`, custom entrypoint | none | vol `mag-provider-etc`, `mag-provider-var`; bind entrypoint+config(ro) | none | same as asterisk | unless-stopped |
| **db** | `mariadb:10.11` | none published (3306 internal) | vol `mag-db`→`/var/lib/mysql`; bind 3 init-script sources (ro) | none | `mariadb-admin ping ... --silent` (5s/3s/30r/20s) | unless-stopped |

`provider` is a second, independent Asterisk 22/PJSIP instance used as a
deterministic local trunk peer for outbound-trunk testing (TASK-0015) — it
never runs SENMA's PHP/AGI/ODBC stack and has no relationship to `asterisk`
in Compose beyond both being on the `mag` network; they reach each other
only via SIP registration.

No PostgreSQL, ODBC-external, or background-worker service currently
exists in the topology beyond MariaDB (accessed by Asterisk via
`res_odbc`/`cdr_adaptive_odbc`) and no reverse proxy is present (Apache in
the `app` container serves directly on the published port).

---

## SERVICE STATE MODEL

Current Docker health status conflates RUNNING with READY for both
stateful services that matter most:

- **app**: `curl -f http://localhost/` only proves Apache/PHP answer an
  HTTP request and render the static SNEP login page — live-verified (HTTP
  200, `<title>SNEP - Login</title>`, no DB round-trip in that response
  path). It does **not** prove DB connectivity, session storage health, or
  that `bootstrap-admin.php` succeeded. A DB-down app can report `healthy`
  while unusable for anything beyond the login page render.
- **db**: `mariadb-admin ping` proves the MariaDB process accepts TCP
  connections. It does not, by itself, prove the SENMA schema/tables exist
  — schema import runs once via `docker-entrypoint-initdb.d/*` scripts
  before MariaDB's official entrypoint starts accepting connections on
  first boot (so first-boot ordering is *believed* safe based on the
  upstream image's documented behavior, but was not independently
  re-verified against MariaDB's own source in this audit — see READINESS).
  The real gap is not first-boot ordering; it is that **nothing verifies
  the import actually completed successfully** — see BOOTSTRAP LIFECYCLE.
- **asterisk / provider**: `core show version` proves the CLI/AMI socket
  answers. It is answerable before PJSIP modules finish loading or
  transports bind (confirmed structurally: `docker/asterisk-entrypoint.sh`
  `exec`s Asterisk directly with no wait-for-PJSIP-init logic; confirmed
  historically by `docs/tasks/0028v-transport-smoke-t20-restart-race.md`,
  which documents a real, previously-reproduced instance of `pjsip show
  transport` failing with "No such command" immediately after a restart
  because `res_pjsip.so` was still loading). A live restart trial run
  during this audit did **not** reproduce the race (see READINESS) — the
  underlying condition is real and documented, but intermittent.
- **app "admin bootstrap" sub-state**: `docker/entrypoint.sh` runs `php
  bootstrap-admin.php` on every start and explicitly treats failure as
  non-fatal (logged, not blocking). There is no observable state for "HTTP
  up, DB up, but admin bootstrap is broken" beyond a single log line at
  container-start time — which, per LOGGING/DIAGNOSTICS below, is not
  reliably visible through the documented diagnostic path anyway.

No service currently exposes a distinct READY signal separate from its
container healthcheck.

---

## STARTUP DEPENDENCIES

| Edge | Enforcement | Classification |
|---|---|---|
| `app → db` (service_healthy) | Compose `condition: service_healthy`, genuinely blocking | **SAFE** |
| `app → asterisk` (service_healthy) | Compose `condition: service_healthy`, but asterisk's healthcheck only proves CLI-socket liveness, not PJSIP readiness | **FRAGILE** |
| `asterisk ↔ provider` | No `depends_on` edge at all; no wait/retry logic in either entrypoint | **SAFE** — PJSIP outbound registration retries indefinitely on its own schedule; this is an eventual-consistency relationship by design, not a boot-time hard dependency, and no wait-loop is needed |
| `db`, `provider` | Roots of the graph, no upstream dependency | N/A |

No dependency in the stack is currently enforced by a bare `sleep` or
timing luck — Compose's `condition: service_healthy` is used correctly
where a dependency exists. The FRAGILE classification on `app → asterisk`
is about the *content* of the healthcheck (see HEALTHCHECKS), not the
wiring mechanism.

---

## BOOTSTRAP LIFECYCLE

### App (`docker/entrypoint.sh`)

| Operation | Classification | Evidence |
|---|---|---|
| `includes/setup.conf` generation from `.dist` + `.env` | FIRST_BOOT_ONLY | Gated on `[ ! -f "$SETUP_CONF" ]`; deliberate, per the script's own comment, so app-written settings survive restarts |
| `chown/chmod` on `setup.conf` | EVERY_BOOT, IDEMPOTENT | Unconditional, naturally idempotent |
| `bootstrap-admin.php` | EVERY_BOOT, IDEMPOTENT BY DESIGN, NON-FATAL ON FAILURE | Self-guarded on an install-time sentinel value in the admin row; deliberately not gated to first boot so a DB that becomes reachable later still gets bootstrapped |

### Database (`docker/db-init/00-import-snep-schema.sh`)

| Operation | Classification | Evidence |
|---|---|---|
| `schema.sql` → `system_data.sql` → billing `schema.sql` import | FIRST_BOOT_ONLY | Standard `docker-entrypoint-initdb.d` semantics: runs only when MariaDB's data directory is empty; script itself uses `set -euo pipefail` |

**HIGH — no partial-failure recovery.** If the second or third import
fails, the script aborts, but the data directory is already non-empty from
the earlier successful import(s) — so `docker-entrypoint-initdb.d` will
**never run again** on that volume. No automatic retry, no distinct
"bootstrap incomplete" state (the healthcheck still passes on plain
connectivity). Recovery today requires manual SQL surgery or a full `make
reset` (which destroys every volume, not just `mag-db`). This has not been
observed to actually occur in this environment.

### Asterisk (`docker/asterisk-entrypoint.sh`)

| Operation | Classification | Evidence |
|---|---|---|
| `/etc/odbc.ini` generation | EVERY_BOOT, IDEMPOTENT | Deliberately unguarded — carries no user-editable state |
| `/var/lib/asterisk/documentation` seed | FIRST_BOOT_ONLY per-volume | Gated on directory absence |
| AGI symlink farm | EVERY_BOOT, IDEMPOTENT | `ln -sfn`, safe to re-run |
| Self-signed WSS TLS cert | FIRST_BOOT_ONLY, independently guarded | Explicitly commented as TEST-ONLY; TASK-0029A was expected to supply real cert management — confirmed no production override path exists |
| `http.conf` seed | FIRST_BOOT_ONLY, independently guarded | Added post-TASK-0028Z so pre-existing dev volumes still get seeded once |
| Main `/etc/asterisk` assembly (static `.conf` copy, dialplan, PJSIP placeholder `touch`es, `manager.conf`/`res_odbc.conf` secret templating) | FIRST_BOOT_ONLY, single gate on `asterisk.conf` existing | Once satisfied, this entire block never runs again for the volume's life |

**Crash-mid-boot safety: UNKNOWN, not proven.** If the container is killed
between `asterisk.conf` being copied and the rest of the block (secret
templating, placeholder file creation) completing, the first-boot gate is
already satisfied and the remainder never runs again — silently leaving
`manager.conf`/`res_odbc.conf` un-templated or PJSIP placeholders missing.
Not tested live (judged too disruptive for this audit); a dedicated
recovery-proof test is needed.

**HIGH — credential rotation is silently ineffective, identically, on
both entrypoints.** Because `setup.conf` (app) and `manager.conf`/
`res_odbc.conf` (asterisk) are only ever templated inside a first-boot
guard, changing `DB_PASSWORD`/`AMI_PASSWORD`/`DB_ROOT_PASSWORD` in `.env`
and recreating the containers does **not** propagate the new value to an
existing volume/bind-mounted file. No error or warning is surfaced on
either side. This is one gap pattern discovered independently by two
different domain audits, not two separate gaps.

**HIGH — PJSIP config never regenerates from DB except as a side effect of
a web-UI write.** `senma-pjsip.conf` / `senma-pjsip-trunks.conf` /
`senma-pjsip-transports.conf` are `touch`ed empty on first boot and are
otherwise written only by `Snep_PjsipConf::loadConfFromDb()` /
`Snep_PjsipTrunkConf::loadConfFromDb()` /
`Snep_PjsipTransportConf::loadConfFromDb()`, called only from
`PjsipTransportsController::regenerateAll()` (`protected`, invoked from
transport create/edit/delete) and equivalent extension/trunk controller
paths. No standalone, operator-invokable reconciliation operation exists
anywhere in `scripts/` or `docker/`. This is the still-real gap a prior
review captured only as an inline code comment referencing "TASK-0028W" in
`snep/lib/Snep/PjsipStatus/Manager.php:24` — no such task document was
ever actually filed under `docs/tasks/`. If the `asterisk-etc` volume is
lost or a restore lands on a fresh volume while the database still holds
provisioning rows, Asterisk boots with empty PJSIP config and stays that
way until an operator manually re-saves every extension/trunk/transport
through the UI (an undocumented workaround, not a supported recovery
path).

---

## PERSISTENT STATE

| Item | Classification | Physical storage |
|---|---|---|
| MariaDB data (schema, all rows, **including CDR** — see CONFIG REGENERATION) | MUST_BACKUP | Named volume `mag-db` (238 MB observed) |
| `snep/includes/setup.conf` (DB/AMI credential echo, web base path, app-writable recording-path settings) | MUST_BACKUP / CUSTOMER_OWNED | **Host bind mount** (`./snep`), gitignored — **not a named Docker volume** |
| `snep/arquivos/` (recording/upload storage — `path_voz`/`path_voz_bkp`) | MUST_BACKUP / CUSTOMER_OWNED | **Host bind mount**, gitignored — **not a named Docker volume** |
| Asterisk-generated PJSIP config (`asterisk-etc` volume, `senma-*.conf`) | DB_REGENERABLE (in principle; no supported regeneration operation exists today — see BOOTSTRAP LIFECYCLE) | Named volume `asterisk-etc` (43 kB) |
| Asterisk `manager.conf`/`res_odbc.conf` (secret-templated) | SECRET_REFERENCE, FIRST_BOOT_ONLY | Named volume `asterisk-etc` |
| WSS TLS cert/key | RUNTIME_GENERATED, TEST-ONLY | Named volume `asterisk-etc` |
| `astdb.sqlite3` (Asterisk internal key/value store) | LOW-priority MUST_BACKUP-if-anything | Named volume `mag-asterisk-var` (1.6 MB) — no voicemail directory present (voicemail not currently a live feature) |
| `/var/spool/asterisk` (call-file drop + tmp only) | RUNTIME_EPHEMERAL | Named volume `mag-asterisk-spool` (0 B — no MixMonitor/recording feature currently active; would need reclassification if enabled) |
| `/var/log/asterisk/full` | MUST_BACKUP-for-forensics but currently unbounded (see STORAGE) | Named volume `mag-asterisk-log` (**263 MB**, larger than the database) |
| App Apache/PHP logs (`mag-error.log`, `mag-access.log`, `snep/lib`'s `ui.log`) | RUNTIME_EPHEMERAL by accident, not by design | **Container writable layer only** — no volume/bind mount covers `/var/log/apache2` or `/var/log/snep` in the app service |
| Docker image layers | REGENERABLE | Rebuildable from `docker/*.Dockerfile` + git source |

**Two MUST_BACKUP paths (`setup.conf`, `arquivos/`) are host bind mounts,
not named Docker volumes.** Any backup approach that only snapshots named
volumes would silently miss both. **App logs live only in the container
writable layer** and are lost on every recreate, independent of the
backup question.

---

## BACKUP CONTRACT

**No supported backup mechanism exists for the current Docker topology.**
Confirmed by two independent checks converging on the same conclusion:

1. The Makefile has no `backup` or `restore` target (full target
   enumeration confirmed: `dev, up, down, restart, logs, ps, shell,
   db-shell, asterisk-cli, test, smoke, doctor, reset, config` plus ~25
   security/feature smoke suites).
2. A legacy vendored script (`snep/scripts/backup/backup.sh`, third-party,
   GPL) exists but is not wired into Docker/Compose anywhere, assumes a
   bare-metal filesystem layout (`/home/backup`, `/etc/asterisk` on the
   host, etc.) that no longer matches this project, hardcodes a stale
   wrong-for-this-project DB password, has no error handling, an
   interactive-only restore path that cannot be scripted, and —
   critically — **explicitly excludes `arquivos/`**, the one MUST_BACKUP
   customer-data path this audit identified as most likely to be missed.
   This script must not be treated as SENMA's backup mechanism.

**What a complete backup must capture**: `mag-db` (mysqldump or volume
snapshot — this is also the CDR backup, see CONFIG REGENERATION),
`snep/includes/setup.conf`, `snep/arquivos/`. Whether it must also capture
`asterisk-etc` (generated PJSIP config, secrets, TLS cert) depends on a
decision this task surfaces but does not resolve: **is "backup" defined as
DB-truth-consistent (regenerate Asterisk config from DB on restore) or
bit-identical (snapshot the generated state directly)?** Given no
supported DB→config reconciliation operation exists yet (see BOOTSTRAP
LIFECYCLE), the safe near-term contract is **bit-identical**: include
`asterisk-etc` (config + secrets + cert) directly in the backup, rather
than depending on a reconciliation mechanism that doesn't exist yet.
DB-truth-consistent backup becomes viable once TASK-0033B (below) lands.

Classify: **BLOCKER** — no provable backup/restore path exists at all,
tested or untested, legacy or modern, for this Docker topology.

---

## RESTORE CONTRACT

**Not defined, not tested.** No restore tooling exists beyond the
non-functional legacy script. A conceptual restore to a fresh environment
would need, at minimum: (1) restore `mag-db` before or in place of the
normal first-boot schema import (order needs to be proven, not assumed —
importing the base schema via the normal first-boot path and then
overlaying a customer dump is one plausible approach, not validated here);
(2) place a restored `setup.conf` at its bind-mounted path **before** the
app's first boot, so the first-boot generation guard doesn't clobber it
with fresh defaults; (3) restore `snep/arquivos/` to its bind-mounted
path; (4) restore or regenerate `asterisk-etc` (see BACKUP CONTRACT
decision above). None of this was exercised end-to-end. Per the parent
task's own Phase 27, this needs a real proof (create known state → backup
→ destroy/recreate → restore → verify → place/receive a test call), which
this audit defers rather than fabricating an untested procedure as
validated.

---

## RESTART/RECOVERY

| Operation | Classification | Evidence |
|---|---|---|
| `docker compose restart asterisk` | DISRUPTIVE but self-recovering | Live-tested: container reported `healthy` again ~6.4s after restart in this trial; PJSIP transports (3/3) were actually loaded by t≈1.55s, well before the healthcheck's own 10s-interval/15s-start_period timing reported healthy — no dangerous gap observed *in this specific trial*, but this dev instance has zero provisioned endpoints/trunks, so only transport-level (not endpoint/registration) warm-up was exercised. The `docs/tasks/0028v` race is real and documented as intermittent, not deterministic — not reproduced today, not closed either. |
| `docker compose restart app` | Inferred SAFE/DISRUPTIVE (brief HTTP outage) | Not executed live this session; no state loss expected since `setup.conf` is bind-mounted, not in the container |
| `docker compose restart db` | UNKNOWN | Not executed live; whether the app's DB layer reconnects gracefully or surfaces a fatal error mid-request was not verified |
| `docker compose down && up` (full stack) | Ordering SAFE (enforced by `service_healthy` conditions); cold-start timing unmeasured | Not executed live this session |
| Asterisk active calls on restart | **DISRUPTIVE, REQUIRES_OPERATOR_WARNING** | No graceful-drain (`core stop gracefully`) used anywhere in the entrypoint, Makefile, or smoke scripts inspected — restarts are hard restarts; any restart drops active calls unconditionally |
| PJSIP registration recovery after restart | UNKNOWN, standard PJSIP retry behavior expected | No fixture with a real registered trunk was live during this audit; no smoke test asserts bounded re-registration time after a restart |
| PJSIP/WSS transport recovery after restart | UNKNOWN (inferred safe from config structure, not observed) | Cert and transport config both persist in `asterisk-etc`; no live restart with a cert-bearing transport configured was performed |
| AMI reconnection after Asterisk restart | Not independently verified | Flagged as an open cross-domain question; no reconnect-handling code was located or ruled out in this audit |

`make restart` restarts the whole stack at once with no per-service
granularity and no confirmation prompt — coarser than a defined
per-service restart contract. `make reset` (by contrast) already has a
correct typed-confirmation safeguard (`Type RESET to continue`) before its
destructive `down -v` — a positive precedent to extend to any future
destructive operational tooling.

---

## HEALTHCHECKS

| Service | What it proves | False-positive risk | Classification |
|---|---|---|---|
| app | Apache+PHP answer `/` (login page render) | **Yes** — can be healthy with DB unreachable | TOO_SHALLOW |
| asterisk | CLI/AMI socket answers | **Yes** — can be healthy before PJSIP modules/transports finish loading (documented race, TASK-0028V) | TOO_SHALLOW |
| provider | Same as asterisk, for the peer instance | Same, plus: a degraded provider is invisible to `asterisk`'s own health status (by design — they're independent instances) | TOO_SHALLOW |
| db | MariaDB accepts TCP connections | Believed gated behind init-script completion on first boot (upstream image behavior), not independently re-verified against MariaDB's own source in this audit | GOOD for reachability; open question for schema-readiness |

None of the four healthchecks mutate state, leak secrets, or are
expensive. All are cheap `curl`/CLI probes with reasonable intervals.

---

## READINESS

Health and readiness are **not** currently distinct for either app or
asterisk. The gap that matters most in practice is the PJSIP one: `docs/
tasks/0028v-transport-smoke-t20-restart-race.md` documents a real,
previously-reproduced instance of the Asterisk CLI answering before
`res_pjsip.so` finished loading. That was fixed **only in one test
script** (`scripts/transport-smoke-test.sh`, via a bounded retry gate) —
**no change was made to the production healthcheck or the app→asterisk
dependency condition.** Any production tooling or automation that queries
`pjsip show ...` immediately after observing container-healthy is exposed
to this race today. A live restart trial in this audit did not reproduce
it (structurally consistent with the race being timing-dependent, not
absent).

---

## DEGRADATION

| Dependency lost | Current behavior | Evidence |
|---|---|---|
| Asterisk/AMI unavailable | **GOOD, already solid.** `Snep_PjsipStatus_Manager` wraps every AMI call in try/catch and degrades every row to `UNKNOWN` (never a false positive/negative), per its own explicit design comment ("an observation failure must never be confused with an entity failure"). Config-apply paths (`PjsipTransportConf::reloadHttp()` etc.) explicitly throw a caught, translated exception if a runtime reload doesn't report success — DB writes never silently claim runtime success. Controllers wrap these in generic `catch (Exception $e)` — no raw AMI stack traces were found leaking to the user in the paths inspected. Full admin-CRUD-while-Asterisk-is-down behavior was not exercised live (avoided colliding with a concurrent restart test), but the code-level evidence strongly implies a translated error, not a raw failure. | `snep/lib/Snep/PjsipStatus/Manager.php`, `snep/lib/Snep/PjsipTransportConf.php` |
| PostgreSQL/MariaDB unavailable | Not independently verified this session | Cross-domain open question — does the app surface a clear failure or a misleading partial success on DB loss? |
| Provider (test trunk peer) unreachable | Not independently verified this session; expected to surface as a registration/qualify failure visible via the same `Snep_PjsipStatus_Manager` degradation path used for any trunk | Inferred from architecture, not observed |

---

## LOGGING/DIAGNOSTICS

**HIGH, live-verified — the app's documented diagnostic path cannot see
PHP application errors at all.** `docker/apache-mag.conf` defines its own
named vhost log files (`mag-error.log`, `mag-access.log`) as real files on
disk, unlike the base Debian Apache image's own default vhost logs, which
*are* symlinked to `/dev/stdout`/`/dev/stderr`. Confirmed live:
`mag-error.log` contained **50,005** lines matching "PHP Fatal"/"PHP
Warning" at check time, while `docker compose logs app` (`make logs`)
showed **zero**. An operator following this project's own documented
diagnostic command cannot answer "why is the application unavailable?"
from PHP-level errors without an ad-hoc `docker exec` into the log file —
directly contradicting the Phase 13 goal. These logs are also
unpersisted (container writable layer only — lost on every recreate).

`/var/log/asterisk/full` is the sole Asterisk log sink (`logger.conf`
defines only `full => notice,warning,error,verbose`) — currently **263
MB**, growing, with **no rotation configured anywhere in the repository**
(confirmed by grep — no logrotate integration, no `logger rotate`
invocation).

`make doctor` exists and does something real (docker/compose presence,
`.env` existence, `compose config` validity, a single shallow `asterisk
-rx "core show version"` probe) but is a **pre-flight/prerequisite
checker, not an operational diagnostic bundle** — it does not check DB
schema state, app HTTP/DB reachability, PJSIP transport/endpoint/
registration counts, disk usage, log sizes, or certificate expiry. The
underlying CLI vocabulary for a real bundle already exists and is proven
across ~15+ smoke scripts (`pjsip show transports/endpoints/
registrations`, `http show status`, `odbc show all`, `core show uptime`,
etc.) — building a consolidated command is a low-risk composition
exercise, not new discovery.

---

## STORAGE

| Path | Size (live) | Rotation? |
|---|---|---|
| `mag-asterisk-log` (`/var/log/asterisk/full`) | **263 MB** | **None** — confirmed unbounded, production-critical, always-write path |
| `mag-db` | 238 MB | N/A (DB-internal) |
| App Apache/PHP logs (container layer) | ~12 MB combined | None, and not persisted at all |
| `mag-asterisk-var` | 1.6 MB | N/A |
| `mag-provider-var` | 1.6 MB | N/A |
| `asterisk-etc` | 43 kB | N/A |
| `mag-asterisk-spool` | 0 B | N/A (currently unused — no recording feature active) |

Docker's own container log driver (`json-file`) has an **empty Config
`{}`** on all four containers — no `max-size`/`max-file` caps set at the
daemon or Compose level either.

---

## DATABASE OPERATIONS

Fresh-install schema provisioning is deterministic (see BOOTSTRAP
LIFECYCLE). **Schema upgrade for an already-provisioned installation is
UNDEFINED.** `snep/install/database/update/` contains a legacy
version-by-version SQL chain (`3.01` through `3.07`, `betha`), but
`docker/db-init/00-import-snep-schema.sh`'s own header comment confirms
this chain is deliberately **not** wired into the Docker bootstrap — only
the (presumed cumulative) `schema.sql` + `system_data.sql` + billing
`schema.sql` are imported. No SENMA-native migration runner (versioned
migrations table, `make migrate`-equivalent) exists. This is not a defect
in current behavior (no existing installation has yet needed an upgrade),
but it will become operationally blocking the first time a future SENMA
code change needs a schema change against a real installation. Classify
**HIGH**, not BLOCKER, today.

---

## CONFIG REGENERATION

Contrary to `compose.yaml`'s own inline comment ("`Snep_InterfaceConf`
(future work, not invoked by this task)"), **DB→Asterisk PJSIP config
generation is live today** via a separate, newer set of classes
(`Snep_PjsipConf`, `Snep_PjsipTrunkConf`, `Snep_PjsipTransportConf`, all
implementing `loadConfFromDb()`) than the one that comment refers to.
`Snep_InterfaceConf` is a distinct, older class that still writes legacy
`chan_sip`/`iax2` config and remains reachable from `ExtensionsController`/
`TrunksController` when a legacy technology is selected — a known,
separately-tracked architecture question (`docs/SECURITY-BASELINE.md`),
not new to this audit. The `compose.yaml` comment is accurate for that one
specific class but is easy to misread as "no DB→Asterisk generation exists
yet," which is false for the PJSIP path — worth a small, low-risk
documentation correction as follow-up debt (not performed here, out of
this audit's scope).

**CDR lives entirely inside `mag-db` via ODBC** (`cdr_adaptive_odbc.conf`,
`connection=snep`, explicit `alias start => calldate` mapping from
TASK-0007/0009) — there is no separate Asterisk-side CDR artifact. The
database backup **is** the CDR backup.

The central gap — no first-class, operator-invokable "reconcile all PJSIP
config from DB" operation — is documented in full under BOOTSTRAP
LIFECYCLE above; it is listed here again only because Phase 19 of the
parent task frames it as a config-regeneration question specifically.

---

## UPGRADE/ROLLBACK

Not exercised as a scenario in this audit beyond what DATABASE OPERATIONS
and BOOTSTRAP LIFECYCLE already establish. Code/image upgrade
(`git pull` + rebuild) is structurally straightforward given the bind-
mounted source tree and named-volume persistent state; the open question
is entirely on the **schema and generated-config** side: an upgrade that
requires a schema change has no defined migration path (UNDEFINED, see
DATABASE OPERATIONS), and a rollback of a schema change is not reversible
by anything in this repository today. Certificate/secret rollback is
constrained by the same first-boot-only templating gap already documented
(BOOTSTRAP LIFECYCLE). No rollback classification beyond UNDEFINED can
honestly be given without dedicated implementation work.

---

## OPERATIONAL SECURITY

- `.env.example` ships `DB_PASSWORD`, `DB_ROOT_PASSWORD`, `AMI_PASSWORD`,
  `TRUNK_TEST_SECRET` with obvious dev placeholder values
  (`change-me-for-local-development`) and **no warning banner** about
  production use. Since no production deployment topology is currently
  defined at all, this is a **latent (MEDIUM), not active** risk today —
  nothing yet stops these placeholders from being copied verbatim into a
  first production `.env`.
- `docker compose config`/`docker inspect`/`docker exec env` on `app`/`db`
  containers show these secrets in plain text — expected Docker behavior,
  exposure surface limited to host/Docker-socket access. **INFORMATIONAL.**
- `make db-shell` passes the DB password on a command line inside the
  container's own `exec` invocation — not visible to the host's process
  list. **INFORMATIONAL.**
- `make doctor` does not touch or echo credentials in its current form.
- Pre-existing, separately-tracked security debt (`docs/
  SECURITY-BASELINE.md`) touching the same "logs" surface as this audit's
  diagnostics finding (a flagged, unconfirmed stored-XSS concern in
  `logs/view.phtml`, TASK-0026D) is noted for awareness, not re-audited
  here.

---

## TEST HARNESS

Reviewed `docs/tasks/0027-regression-harness-reliability.md` §5 in full:
**already solid, no new gap found.** Fixture ownership is proven via a
unique marker captured into the real persisted row id immediately after
creation (never broad pattern deletion); cleanup is dependency-aware and
routed through the same `Snep_*_Manager`/`PBX_Rules::delete()` paths the
product itself uses, never raw SQL. This was live-tested against a real
SIGKILL mid-run in a prior task, not just designed on paper, and a
deliberate SIGKILL-during-run reproduction in that same prior work
recovered cleanly on the next run. No new test-harness-operational debt
was identified in this audit.

---

## BLOCKERS

1. **BLOCKER** — No provable backup/restore path exists for this Docker
   topology. The only backup script present targets a pre-Docker
   filesystem layout, hardcodes a wrong password, and explicitly excludes
   the one MUST_BACKUP customer-data path (`arquivos/`) it should cover.
   No `make backup`/`make restore` targets exist, and restore has never
   been tested.

## HIGH

2. Two MUST_BACKUP data paths (`setup.conf`, `arquivos/`) live on host
   bind mounts, not named Docker volumes — any volume-only backup
   approach silently misses both.
3. Credential rotation (`DB_PASSWORD`/`AMI_PASSWORD`/`DB_ROOT_PASSWORD`)
   is silently ineffective on an existing app or Asterisk volume — only a
   fresh volume re-templates secrets, with no error or warning either way.
4. No first-class, operator-invokable "reconcile PJSIP config from DB"
   operation exists — the only path is a `protected` side effect of
   transport CRUD. Directly blocks a clean restore-to-preserved-state
   story if `asterisk-etc` isn't itself part of the backup.
5. `docker compose logs app` / `make logs` cannot surface PHP application
   errors at all (0 vs 50,005 matching lines, live-verified); the
   underlying log is also unpersisted (container-layer only).
6. `/var/log/asterisk/full` grows unbounded (263 MB observed, live), no
   rotation configured anywhere in the repository.
7. DB bootstrap has no partial-failure recovery: a mid-import failure
   permanently half-provisions the volume with no automatic retry, and
   the healthcheck cannot detect it.
8. No schema upgrade path exists for an already-provisioned installation
   (legacy chain present but disconnected from the Docker bootstrap; no
   SENMA-native migration runner). Not urgent today; becomes blocking the
   first time a real schema change ships against a live install.
9. Asterisk's healthcheck and the `app → asterisk` dependency condition
   do not prove PJSIP readiness; the documented TASK-0028V restart race
   is only defended against in one test script, not in production.

## MEDIUM

10. App healthcheck proves only that Apache/PHP answer a static page, not
    DB connectivity or bootstrap completeness.
11. App's own Apache/PHP/UI logs live only in the container writable
    layer — lost on every recreate, unrotated.
12. `.env.example` secrets carry no production-unsafe warning (latent,
    since no production topology is yet defined).
13. `make doctor` is a pre-flight checker, not a consolidated operational
    diagnostic bundle.
14. No graceful-drain (`core stop gracefully`) before any Asterisk
    restart — active calls are unconditionally dropped.

## LOW / INFORMATIONAL

15. No CPU/memory limits configured on any service (recorded per the
    parent task's own instruction not to tune limits blindly).
16. `make restart` restarts the whole stack at once with no per-service
    granularity or confirmation, unlike `make reset`'s correct
    typed-confirmation pattern.
17. Minor `*.dpkg-new` chmod/mv noise visible in `docker compose logs app`
    at container start/stop — cosmetic.
18. Secrets visible via `docker inspect`/`exec env` — expected Docker
    behavior, host-operator-only exposure.
19. CDR lives entirely in `mag-db` via ODBC — informs the backup contract,
    not a defect.
20. Test-harness DB-fixture reliability already solid (TASK-0027),
    live-tested against SIGKILL — confirmed strength, not a gap.
21. AMI-failure degradation and explicit-failure-on-apply are already
    well-designed — confirmed strength, not a gap.

---

## TASK SPLIT

See the checkpoint below for the full roadmap (`TASK-0033A`–`F`) with
leads, reviewers, dependency order, and acceptance boundaries.
