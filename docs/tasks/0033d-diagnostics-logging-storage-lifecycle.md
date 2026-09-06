# TASK-0033D — Diagnostics, Logging & Storage Lifecycle

Status: implemented and validated against a live, already-provisioned
installation. Lead: `senma-docker-platform-engineer`. Reviewers:
`senma-application-architect` (Apache/PHP logging boundary, DB/schema
checks), `senma-telephony-architect` (Asterisk logging/rotation
boundary, PJSIP snapshot, non-disruption). `senma-product-designer` not
invoked -- `make doctor`/`scripts/doctor.sh` is an operator CLI, not an
admin-facing UI flow.

This task closes the three operational gaps TASK-0033's own audit
identified: no single supported diagnostic entrypoint, PHP/application
errors invisible through `docker compose logs`, and unbounded Asterisk/
application log growth with no rotation contract. All findings below
were reproduced live against this repository's actual Docker stack, not
assumed from the prior audit's text.

---

## LOG INVENTORY

| Log | Sink (before this task) | Classification | Growth risk (before) |
|---|---|---|---|
| Apache/PHP `mag-error.log` | Real file (`/var/log/apache2/mag-error.log`), NOT visible via `docker compose logs app` | `OPERATOR_REQUIRED` | Unbounded (1.7 MB observed, growing) |
| Apache `mag-access.log` | Real file, not visible via `docker compose logs app` | `DEBUG_ONLY` (no test/operational dependency found) | Unbounded (137 KB observed) |
| PHP non-fatal errors/deprecations (`error_log` ini directive) | Already `/dev/stderr` since TASK-0001 | `DEBUG_ONLY` | N/A (Docker-managed) |
| SENMA `ui.log` (`Snep_Logger`/Zend_Log, `path.log`) | Real file, container-writable-layer only (not a volume) | `DEBUG_ONLY` (mostly repetitive AMI `fullybooted`/`reload` event noise) | Unbounded within one container lifetime; reset on recreate |
| Asterisk `full` (logger.conf) | Real file on the `mag-asterisk-log` named volume | `OPERATOR_REQUIRED` | **Unbounded, live-confirmed at 284-297 MB with zero rotation ever run** |
| Asterisk `queue_log` | Real file, same volume (Asterisk writes this unconditionally regardless of logger.conf) | `DEBUG_ONLY` (queues are not a currently-provisioned feature in this install) | Unbounded but low-volume (56 KB observed) |
| Asterisk `messages`/`security` logger channels | Not configured (only `full` exists in `docker/asterisk-config/logger.conf`) | `NOT_CURRENTLY_USED` | N/A |
| CDR | Lives entirely in `mag-db` via `cdr_adaptive_odbc` (confirmed in TASK-0033) | `EXTERNALLY_MANAGED` (DB's own growth, not a file) | N/A here |
| Asterisk container stdout | Verbose codec-registration boot noise | `DEBUG_ONLY` | Docker-managed |
| App container stdout (entrypoint) | Bootstrap messages, cosmetic `.dpkg-new` noise (pre-existing, TASK-0033 LOW) | `DEBUG_ONLY` | Docker-managed |
| MariaDB logs | Already stdout/stderr by default (official image); `/var/log/mysql` confirmed empty | `OPERATOR_REQUIRED`, already correctly surfaced | Docker-managed |
| Docker json-file driver (all 4 services) | No `max-size`/`max-file` (confirmed via `docker inspect .HostConfig.LogConfig` = `{}`) | `OPERATOR_REQUIRED` (the transport for everything above) | Unbounded |

No critical `UNKNOWN` remains.

---

## APPLICATION LOG VISIBILITY (Phase 2)

**Reproduced live, still true at the start of this task**: a PHP fatal
error triggered via a real HTTP request appeared in `mag-error.log`
but **zero** bytes in `docker compose logs app` -- exactly TASK-0033's
finding, unresolved until now.

**Root cause**: `docker/apache-mag.conf`'s vhost defines its own
`ErrorLog`/`CustomLog` pointing at real files, unlike the base
`php:8.4-apache` image's own default vhost (confirmed live:
`/var/log/apache2/{access,error}.log` are themselves symlinks to
`/dev/stdout`/`/dev/stderr` in this image -- this project's vhost is
the one exception). PHP's own `error_log = /dev/stderr` (`docker/
php-mag.ini`, present since TASK-0001) correctly surfaces ordinary
PHP-level warnings/deprecations already (confirmed: `PHP Deprecated:
...` lines already appear in `docker compose logs app`) -- but a fatal
error under mod_php is logged via Apache's own `ErrorLog` mechanism,
not PHP's `error_log` ini directive, so it never reached stdout/stderr
at all.

**Fix, smallest correct boundary**: `docker/apache-mag.conf` only.

```apache
ErrorLog "|/usr/bin/tee -a ${APACHE_LOG_DIR}/mag-error.log"
CustomLog /dev/stdout combined
```

`CustomLog` (access log) had **zero** dependents (grepped `scripts/
*.sh`) and now goes straight to stdout, matching the base image's own
convention -- no file, no rotation concern, no duplication.

`ErrorLog` could not be pointed at `/dev/stderr` directly the same way:
**13 existing, already-validated security/regression smoke test
scripts** (`residual-sql-security-smoke-test.sh` alone has 24
occurrences) read specific byte/line windows of `/var/log/apache2/
mag-error.log` directly, for known-error-signature detection, not just
counting. Migrating all of them was judged a separate, large, risky
mechanical change against this task's own actual goal and was NOT
attempted here (see REMAINING DEBT) -- Apache's piped-logging feature
(`"|command"`) instead fans the SAME log stream out to both the
historical file path (unchanged, zero risk to those 13 scripts,
confirmed live: `scripts/smoke-test.sh`'s own `fatal_count()` check
still passes unmodified) and the container's stdout via `tee`'s own
inherited file descriptor (confirmed live: a real HTTP-triggered fatal
error now appears in `docker compose logs app` immediately).

This is a **justified** duplication (Phase 3), not an accidental one --
see PRESERVED FILE LOGS below.

---

## PRESERVED FILE LOGS (Phase 3 duplication classification)

| Duplication | Classification | Reason |
|---|---|---|
| `mag-error.log` also written to (via `tee`) in addition to `docker compose logs app` | `JUSTIFIED_DUPLICATION` | Backward compatibility for 13 existing smoke test scripts' byte/line-precise reads; tracked as `FOLLOW_UP_DEBT` to eventually migrate them off direct file access |
| PHP non-fatal errors in both `docker compose logs app` (via `error_log=/dev/stderr`) and nowhere else | Not a duplication | Fatals go through Apache's `ErrorLog`/`tee`; ordinary errors go directly through PHP's own `error_log` -- two disjoint error classes, not the same error logged twice |
| `mag-access.log` | Eliminated (not preserved) | Zero test/operational dependents found |
| `ui.log` | `DEBUG_ONLY`, preserved as-is (rotated, not eliminated) | No duplicate destination exists for it; it is SENMA's own application-level log, not a copy of anything else |

---

## LOG LIFECYCLE

No `cron`, `crond`, or `logrotate` binary exists in either the `app` or
`asterisk` image (confirmed live) -- ruling out a conventional
logrotate deployment inside either container (Phase 22's own
instruction: "If the container has no cron/systemd, choose an
architecture that actually runs").

**Chosen architecture**: a small bash watcher script, backgrounded from
each entrypoint (`&` immediately before the final `exec`), running as a
sibling process for the container's whole lifetime -- the container's
own rotation mechanism, not an external one.

### Asterisk (`docker/log-rotate-asterisk.sh`)

- Checks `/var/log/asterisk/{full,queue_log}` every `SENMA_LOG_CHECK_INTERVAL`
  (default 900s/15min).
- Rotates via Asterisk's own **native** `logger rotate` CLI command when
  either file reaches `SENMA_LOG_MAX_SIZE_BYTES` (default 100 MiB).
  Live-confirmed: reopens the file without restarting Asterisk,
  reloading PJSIP, or dropping the module load state -- `core show
  uptime` before/after showed the same running process (see LIVE
  FAILURE PROOFS).
- `logger rotate` itself only renames to the lowest unused `<name>.<N>`
  suffix and reopens -- it never deletes or compresses anything
  (confirmed live: **the numeric suffix is REUSED once a lower one is
  freed**, so unbounded rotation COUNT would just replace unbounded
  single-file SIZE if left unmanaged). The watcher closes this gap:
  after every check, it gzips any not-yet-compressed rotated file, then
  deletes all but the `SENMA_LOG_KEEP` most recent (default 5) by
  mtime.

### App (`docker/log-rotate-app.sh`)

- Checks `/var/log/apache2/mag-error.log` and `/var/log/snep/ui.log`
  every `SENMA_LOG_CHECK_INTERVAL` (default 900s/15min), rotates at
  `SENMA_LOG_MAX_SIZE_BYTES` (default **50 MiB** -- smaller than
  Asterisk's threshold since these logs grow far slower in this
  project's observed traffic).
- Rotation strategy: **copytruncate** (`cp` current content aside,
  `: > file` to truncate in place), deliberately NOT rename-based.
  `mag-error.log` is fed by a `tee` process that holds the file open
  continuously for the container's whole lifetime -- renaming out from
  under it would leave `tee` writing to a now-unlinked inode while a
  new empty file sits at the old path, invisible to `tee`. Truncating a
  file a process holds open for append-only writes is safe on POSIX.
  Live-confirmed: a fatal error triggered via HTTP immediately after a
  forced rotation still landed correctly in the now-truncated file (see
  LOG ROTATION PROOF).
- Same gzip-then-prune-to-`SENMA_LOG_KEEP` retention as the Asterisk
  watcher.

### Thresholds and rationale (Phase 21)

No single size is universally correct across installations, so these
are **conservative operational defaults** grounded in this project's
own observed data, not an invented business policy:

- Asterisk `full`: 100 MiB rotate / 15 min check / keep 5 compressed
  generations. This project's own `full` log was observed live at
  284-297 MiB with zero rotation ever having run; 100 MiB catches that
  class of runaway growth without rotating on ordinary, healthy verbose
  volume.
- App `mag-error.log`/`ui.log`: 50 MiB / 15 min / keep 5 -- app-side
  logs (PHP fatals, AMI-event noise) grow markedly slower than
  Asterisk's own verbose stream in this project's traffic.
- All three numbers are overridable via environment
  (`SENMA_LOG_MAX_SIZE_BYTES`, `SENMA_LOG_CHECK_INTERVAL`,
  `SENMA_LOG_KEEP`) for the live rotation proof in `scripts/
  doctor-failure-smoke-test.sh`, which invokes the same scripts
  directly with short thresholds instead of waiting out a real
  15-minute interval or generating hundreds of MB.

`doctor.sh`'s own log-size checks (see DOCTOR CHECKS) `WARN` at the
same thresholds, purely informational -- they never delete or rotate
anything themselves (doctor is read-only by contract).

---

## DOCKER LOGGING

Confirmed live, before this task: every service's `docker inspect
.HostConfig.LogConfig` showed `{"Type":"json-file","Config":{}}` -- no
`max-size`/`max-file`, Docker's fully unbounded default, now carrying
MORE traffic than before (Apache error/access output both now flow
through it too).

**Fix**: `compose.yaml` gains a shared `x-logging` anchor applied to
all four services:

```yaml
x-logging: &senma-default-logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "5"
```

10 MiB × 5 files = 50 MiB per container -- generous enough for hours of
even verbose troubleshooting output, small enough that four containers
together can never approach the risk the unbounded Asterisk `full` file
demonstrated on its own.

**Verified applied, not just declared** (Phase 24): `docker inspect
<container> --format '{{json .HostConfig.LogConfig}}'` was run live
against all four containers after `docker compose up -d
--force-recreate` and confirmed `{"Type":"json-file","Config":
{"max-file":"5","max-size":"10m"}}` on each -- `docker compose config`
alone was not trusted as proof.

---

## STORAGE GROWTH INVENTORY

| Path | Classification | Location | Notes |
|---|---|---|---|
| `mag-asterisk-log` (`full`, `queue_log`) | Was `UNBOUNDED`, now `BOUNDED` | Named volume | Fixed this task (see LOG LIFECYCLE) |
| `mag-error.log`/`ui.log` | Was `UNBOUNDED`, now `BOUNDED` | Container writable layer (app) | Fixed this task |
| Docker json-file logs (all 4 services) | Was `UNBOUNDED`, now `BOUNDED` | Docker's own log storage (host) | Fixed this task |
| `mag-db` | `EXTERNALLY_MANAGED` | Named volume | DB's own growth; CDR lives here (TASK-0033); no rotation/retention policy invented here (explicitly OUT OF SCOPE -- business retention) |
| `snep/arquivos/` (recordings) | `NOT_CURRENTLY_USED` | Host bind mount | No recording feature currently active (confirmed in TASK-0033); recording retention policy explicitly OUT OF SCOPE |
| Voicemail | `NOT_CURRENTLY_USED` | N/A | No voicemail directory present (TASK-0033 finding, unchanged) |
| `/var/spool/asterisk` | `NOT_CURRENTLY_USED` | Named volume (`mag-asterisk-spool`) | 0 B observed; no MixMonitor/call-file feature currently active |
| Backup artifacts (`backups/*.tar.gz`) | `EXTERNALLY_MANAGED` | Host directory | TASK-0033A's own scope owns retention/scheduling; this task only adds destination-diagnostics (see BACKUP DIAGNOSTICS), does not add a retention policy |
| `asterisk-etc` | `BOUNDED` | Named volume | Generated PJSIP config; observed at ~150 KB, inherently small |
| Docker image layers/build cache | `EXTERNALLY_MANAGED` | Host Docker storage | Regenerable from source; not this task's concern |

---

## DOCTOR CONTRACT

`make doctor` (`scripts/doctor.sh`) is READ-ONLY, SAFE, ACTIONABLE,
SECRET-SAFE, and DETERMINISTIC:

- Never reloads a module, regenerates config, restarts/recreates a
  container, rotates a secret, or applies a reconcile. It only ever
  calls the **`--check`** form of reconcile and the **check** form of
  secrets tooling (`scripts/secrets-check.sh`, never `rotate-secrets`).
- Every check is independently guarded -- no `set -e`, every function
  ends by calling `record()` with a result, never by exiting the
  script.
- `scripts/doctor-smoke-test.sh` (regression-safe) includes a
  **source-text assertion** that no mutating command pattern (`module
  reload`, `logger rotate`, `manager reload`, `rotate-secrets.sh`, a
  bare `reconcile-pjsip.php` call without `--check`, `docker compose
  restart/stop/rm`, `--force-recreate`) appears anywhere in `doctor.sh`
  itself.
- Does not depend on `make up` and tolerates a missing `.env` (reports
  it as its own finding rather than refusing to run at all).

---

## DOCTOR CHECKS

| Section | Checks |
|---|---|
| Prerequisites | Docker CLI, Docker Compose v2, `.env` file, `compose.yaml` valid |
| Docker/runtime | Docker daemon reachable; per-service container existence/running/health state (`app`, `asterisk`, `db`, `provider`) |
| Database | Reachable (raw TCP connect, credential-free); application DB authentication (reused `slib_db_user_auth_check`); expected schema present (`core_config` table) |
| Application | HTTP reachable; renders the login page (content assertion, no data modified) |
| Asterisk | CLI reachable; PJSIP module loaded; HTTP/WSS listener state; AMI reachable (reused `slib_ami_auth_check`) |
| PJSIP | Configuration IN_SYNC/DRIFTED (`reconcile-pjsip.php --check`, TASK-0033B, no reimplementation); runtime snapshot (endpoint/registration/transport/channel counts); trunk registrations (external status, separate from platform health) |
| Secrets | `scripts/secrets-check.sh` as a whole (TASK-0033C, no reimplementation) |
| Storage | Host disk free space; named volume usage (`mag-db`, `mag-asterisk-log`, `asterisk-etc`) |
| Logs | Asterisk `full` size; application `mag-error.log` size (both WARN at their rotation threshold) |
| Backup | Destination exists/writable, free space -- no backup taken |
| Certificate | WSS cert/key existence, key permission mode, X.509 parse, 30-day expiry proximity |

---

## RESULT VOCABULARY

`PASS` / `WARN` / `FAIL` / `UNKNOWN` / `SKIP`, one line per check:
`[STATE] Name: short reason`. `SKIP` means "deliberately not checked"
(a precondition, e.g. the container not running, is already known
unmet); `UNKNOWN` means "attempted but could not be determined."
`--verbose` (or `VERBOSE=1`) appends sanitized supporting detail
(e.g. the full `secrets-check.sh`/`reconcile-pjsip.php --check`
breakdown) under the relevant line -- never a secret value, never a
private key body, never raw `docker compose config`/`docker inspect`
output.

---

## EXIT CODES

`0` if no check is `FAIL`; `1` if any check is `FAIL`. `WARN`/
`UNKNOWN`/`SKIP` never affect the exit code -- deliberately, so a
routine PJSIP staleness warning or an unprovisioned `provider`
container doesn't break `make doctor` in automation/CI the way a real
`FAIL` should. Live-verified: PJSIP config drift alone (`WARN`) leaves
`doctor: no FAIL -- exit 0`; a stopped container (`FAIL`) produces
`doctor: N FAIL -- exit 1`.

---

## SECRET SAFETY

- Never prints a raw secret value, private key body, full connection
  string, or `docker compose config`/`docker inspect` dump. Every
  `docker inspect` call in this task's own tooling uses a targeted
  `--format` (e.g. `{{.State}}`, `{{.Health}}`, `{{json
  .HostConfig.LogConfig}}`), never a wholesale dump.
- `scripts/doctor-smoke-test.sh` automates this as a real assertion
  (Phase 26): greps BOTH normal and `--verbose` output for all three
  live secret values (`DB_PASSWORD`, `DB_ROOT_PASSWORD`,
  `AMI_PASSWORD`) and the WSS private key's own file content -- none
  found, confirmed passing.
- The Database/AMI checks reuse `scripts/lib/secrets-lib.sh`'s existing
  live-auth primitives, which already never print a value on either
  side of a comparison (TASK-0033C's own established contract).

---

## FAILURE ISOLATION

Every `check_*` function in `scripts/doctor.sh` independently guards
its own container-state precondition and always calls `record()` --
none of them can abort the script. Live-verified for `asterisk`, `db`,
and `app` each stopped in turn: the stopped service's own checks report
`FAIL`/`SKIP` as appropriate, while every unrelated section (storage,
backup, certificate, and the other two services) still runs and
reports a real result. See LIVE FAILURE PROOFS.

---

## PJSIP/SECRET INTEGRATION

Both reuse the existing operational contract rather than reimplementing
drift detection:

- **PJSIP**: `docker compose exec asterisk php /usr/local/bin/
  reconcile-pjsip.php --check` (TASK-0033B). Exit 0 -> `PASS`
  (`IN_SYNC`); exit 3 -> **`WARN`** (`DRIFTED`); other -> `UNKNOWN`.
- **Secrets**: `scripts/secrets-check.sh` (TASK-0033C) as a whole. Exit
  0 -> `PASS` (`MATCH`); exit 3 -> **`FAIL`** (`DRIFT`); other ->
  `UNKNOWN`.

**Why the severity differs** (a deliberate, documented choice, not an
inconsistency): PJSIP drift means generated config disagrees with the
database -- routine operational staleness with a defined, low-risk fix
(`make reconcile`), not evidence of an active security problem. Secret
drift means a credential the operator believes is active may not
actually be -- a security-relevant coherence failure with its own
documented, higher-urgency contract (TASK-0033C). Neither is
reconciled/rotated by `doctor` itself.

---

## CERTIFICATE DIAGNOSTICS

Classified `REQUIRED_NOW` (Phase 18): existence, key-file permission
mode (600/400), X.509 parse (`openssl x509 -noout`), and 30-day expiry
proximity (`openssl x509 -checkend $((30*86400))`) -- a single
additional `openssl` invocation over the existence/parse checks, not
disproportionate complexity. No certificate **monitoring** (alerting,
historical tracking) was built -- that remains a legitimate
`FOLLOW_UP_DEBT` if ever needed, well outside a read-only diagnostic
command's scope.

---

## LIVE FAILURE PROOFS

All run against the real, already-running dev stack; every service
restored and every drift reverted before moving to the next scenario
(see `scripts/doctor-failure-smoke-test.sh`'s own `restore_all`
required-cleanup function).

| Scenario | Result |
|---|---|
| `asterisk` stopped | `doctor` exits 1, `[FAIL] Container: asterisk`; `db`/`app`/storage/secrets/backup checks still ran and reported real (non-SKIP) results; recovered to exit 0 after `docker compose start asterisk` |
| `db` stopped | `doctor` exits 1; `[WARN] Application HTTP reachable: HTTP 500` (reachable, not healthy -- correctly distinct classifications) and `[FAIL] Application renders login page`; `asterisk`/storage/backup/certificate checks unaffected; recovered after restart |
| `app` stopped | `doctor` exits 1, `[FAIL] Container: app`; `db`/`asterisk`/secrets/storage checks unaffected; recovered after restart |
| Secret drift (env override only, `.env` untouched) | `[FAIL] Secrets: DRIFT`, `[FAIL] AMI reachable`; `scripts/secrets-check.sh` against the REAL environment confirmed still `MATCH` throughout -- nothing was actually rotated or left crash-looping |
| PJSIP config drift (delete one managed file, same mechanism `pjsip-reconcile-smoke-test.sh` already uses) | `[WARN] PJSIP configuration: DRIFTED`, overall `doctor` exit stayed **0** (WARN, not FAIL); `make reconcile` restored it; `doctor` confirmed `[PASS] PJSIP configuration: IN_SYNC` again |

---

## LOG ROTATION PROOF

Both watcher scripts invoked directly with short thresholds
(`SENMA_LOG_MAX_SIZE_BYTES=1 SENMA_LOG_CHECK_INTERVAL=1`) rather than
waiting out the real 15-minute interval or generating hundreds of MB
(Phase 32's own guidance) -- same script the real backgrounded watcher
runs, just parameterized for a fast, controlled proof:

- **Asterisk**: `full`/`queue_log` rotated via `logger rotate`,
  compressed, old generation count increased as expected, `/var/log/
  asterisk/full` existed and continued receiving writes immediately
  after. `core show uptime` answered immediately post-rotation (no
  restart-induced gap) -- **non-disruptive**, confirmed live.
- **App**: `mag-error.log` copytruncated and compressed; a PHP fatal
  triggered via a real HTTP request immediately after rotation was
  found in the now-truncated file -- proving `tee` kept writing
  correctly across the truncation (the specific safety property this
  rotation strategy depends on).

## ACTIVE-CALL/NON-DISRUPTION PROOF

No active-call scenario was fabricated (this dev install provisions no
real trunk/extension calls by default); the applicable non-disruption
evidence is `core show uptime` remaining continuous across every
Asterisk-side operation this task performs (log rotation, PJSIP
reconcile via `make reconcile` in the drift-restore proof) -- the same
evidence standard TASK-0033C's own AMI/DB rotation proofs used.

---

## REGRESSION SPLIT

- **`scripts/doctor-smoke-test.sh`** (`make doctor-smoke`) -- safe,
  non-mutating (asserts exit 0/no FAIL on this dev install's own
  healthy baseline, every mandatory check present, no secret
  disclosure in normal or `--verbose` output, no mutating command in
  `doctor.sh`'s own source). **Included in `make regression`.**
- **`scripts/doctor-failure-smoke-test.sh`** (`make doctor-failure-smoke`)
  -- the real destructive proof: stops `asterisk`/`db`/`app` in turn,
  injects secret and PJSIP drift, forces a live log rotation.
  **Deliberately NOT part of `make regression`** -- stopping real
  services on every regression run is unnecessary cost/risk for a
  suite whose detection CONTRACT is already proven by the 27
  non-mutating checks in `doctor-smoke-test.sh`; an operator or CI job
  that wants the full destructive proof runs it explicitly, exactly
  like `secret-rotation-smoke`/`backup-restore-smoke`.

---

## REMAINING DEBT

1. **13 existing smoke test scripts read `/var/log/apache2/
   mag-error.log` directly** (byte/line-precise, not just counting).
   Migrating them to `docker compose logs app` was judged out of this
   task's actual scope (a large, separate mechanical migration of
   already-validated security tests) -- `mag-error.log` is preserved as
   a `JUSTIFIED_DUPLICATION` via `tee` instead. `FOLLOW_UP_DEBT`.
2. **`ui.log` (`Snep_Logger`) is mostly repetitive AMI event noise**
   (`fullybooted`/`reload` events logged at ALERT level with a
   benign "no handler" message on every occurrence). Rotation is now
   bounded, but the underlying log-volume characteristic itself was not
   changed (an application-code concern, out of this task's scope per
   "do not fix unrelated legacy bugs opportunistically"). `FOLLOW_UP_DEBT`.
3. **`make support-bundle` was evaluated and NOT implemented** -- no
   evidence in this task's own investigation showed a concrete near-term
   need beyond what `make doctor --verbose` plus `docker compose logs`
   already provide. `FOLLOW_UP_DEBT`, correctly optional per this
   task's own scope boundary.
4. **Certificate expiry is existence/parse/checkend only** -- no
   historical tracking or alerting. `FOLLOW_UP_DEBT` if ever needed,
   deliberately not built now (would start turning `doctor` into a
   monitoring tool, explicitly out of scope).
5. **Backup/log storage retention policy is intentionally NOT
   invented** -- `mag-db` growth, `arquivos/` recording retention, and
   backup-artifact retention/scheduling remain TASK-0033A's and
   business-policy's scope respectively, per this task's own explicit
   OUT OF SCOPE list.
6. **The background rotation watchers have no signal handling of their
   own** -- Docker only signals a container's PID 1 (Apache/Asterisk)
   on stop; the watcher process (a separate PID under the same
   container) is simply torn down with the container's namespace, not
   gracefully. Accepted as a standard, low-risk simplification for this
   class of cron-less sidecar loop; no observed adverse effect in any
   test run.
7. **TASK-0033E boundary preserved**: this task did not touch Docker
   healthcheck definitions, `depends_on` conditions, or RUNNING-vs-READY
   semantics anywhere. No new readiness finding surfaced during this
   task's own investigation beyond what TASK-0033's original audit
   already documented for that future task.

---

## VALIDATION SUMMARY

- `bash -n` on every new/modified shell script: clean.
- `docker compose config`: valid (new `x-logging` anchor resolves
  correctly on all four services).
- Target tests: `scripts/doctor-smoke-test.sh` PASS (7/7 checks);
  `scripts/doctor-failure-smoke-test.sh` PASS (23/23 checks).
- `make lint`, `make regression` (x2), `git diff --check`, `git status
  --short`: see the checkpoint report accompanying this document.
