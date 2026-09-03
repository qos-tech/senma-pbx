# TASK-0026S — Legacy web-exposed migration endpoint hardening

## Status

Implementation complete and validated. `snep/install/` (the entire
installer/schema-migration subtree, not just the one known script) is no
longer reachable over HTTP. `make lint` PASS. Two consecutive full `make
regression` runs both PASS, 23/23 suites each (up from 22 — this task adds
`legacy-maintenance-exposure-security` to the canonical suite), no code
changes between them. Environment healthy. Database integrity re-verified
unchanged from TASK-0026R's own documented baseline.

```text
UNAUTHENTICATED_WEB_REACHABLE_DB_MUTATING_SCRIPTS = 0
```

Not committed — this is the validated TASK-0026S checkpoint, awaiting
explicit authorization to commit.

**A second accidental live trigger occurred during this task's own Phase 1
reachability reconnaissance, disclosed here transparently per this
project's own safety discipline (matching how TASK-0026R disclosed the
first one).** A `curl -I` (HEAD) reachability probe against
`convert-data-rc3.php`, issued before remediation, executed the script for
real a second time — Apache/PHP do not special-case HEAD for a plain PHP
script, so the full script body ran up to its first statement exactly as
GET would. It reproduced the *identical* pre-existing failure signature
TASK-0026R already documented (`SQLSTATE[42000]: 1091, Can't DROP FOREIGN
KEY 'peers_ibfk_1'; check that it exists`, script dies on line 22, before
ever reaching any `SELECT`/`INSERT`/`UPDATE`). Verified immediately,
directly against the database (not merely re-citing TASK-0026R's own
finding): `core_peer_groups` = 0 rows, `peers` has zero foreign-key
constraints, and `peers` has no `group` column / no `groups` table exists
at all in this schema (this script's final section, "drop the legacy
`group` column and `groups` table," could never have run even if the
first `ALTER` had succeeded — the schema this script assumes and the
schema in this repository have already diverged). No new mutation
occurred. This is exactly the risk this task exists to close, and it
underscores why containment had to happen at the web-server layer before
any further live reachability testing of this specific script was safe
— every check after the fix landed relies on Apache's access-control
phase rejecting the request before PHP ever runs, which is inherently
non-destructive by construction (see Phase 5 below).

---

## 1. Phase 1 — deployment exposure reconstruction

**Document root**: `docker/apache-mag.conf` sets
`DocumentRoot /var/www/html/snep` — i.e. the entire `snep/` application
tree, including `snep/install/`, is the web root. There is no separate
public/ subdirectory boundary.

**Exact HTTP path reaching the known finding**:

```text
http://<host>/install/database/update/betha/convert-data-rc3.php
```

(and, in this dev environment, `http://localhost:8080/install/...`).

**Why it is reachable**: `<Directory /var/www/html/snep>` grants
`Require all granted` with `AllowOverride All` and no `Options -Indexes`/
access restriction scoped to `install/`. No URL rewriting affects it — no
`.htaccess` existed anywhere under `snep/install/` before this task,
unlike `snep/includes/.htaccess` (denies `*.conf`) and
`snep/lib/linfo/*/.htaccess` (deny-all), which already protect their own
subtrees. The whole `snep/install/` tree was exposed, not merely one
script.

**Direct execution, not installer-mediated**: there is no installer
wizard/entrypoint controller in this codebase that gates access to these
scripts — Apache serves each `.php` file directly via mod_php, exactly
like any other file under the document root. `grep -rn "install/"` across
`snep/modules`, `snep/lib`, `snep/agi` found zero application code
referencing `install/` at all (the one `install/` hit,
`PermissionPlugin.php`'s `'default_register' => true`, is an unrelated
resource-name coincidence — a registration-status display action, nothing
to do with the installer directory).

---

## 2. Phase 2 — dangerous executable script inventory

`find snep/install -type f` enumerates the complete deployed subtree. Only
two files are PHP (everything else is `.sql`, Asterisk `.conf` templates,
`.tar.gz`/`.tgz` sound archives, `index.html`, `snep.apache2`,
`socket.modelo.txt` — all `STATIC_RESOURCE`, non-executable):

```text
File:            snep/install/database/update/betha/convert-data-rc3.php
Classification:  MIGRATION_SCRIPT / DB_MUTATING_SCRIPT
Before this task: WEB_REACHABLE, UNAUTHENTICATED
Details:         Real PDO connection (setup.conf-derived credentials).
                 First statement: ALTER TABLE peers DROP FOREIGN KEY
                 (destructive DDL). Zero request-derived SQL values (every
                 interpolated value is DB-derived -- confirmed by
                 TASK-0026R's own SQL audit, re-confirmed here) --
                 NOT a SQL-injection finding. Zero call sites anywhere in
                 the tree (no CLI script, no Makefile target, no
                 application controller invokes it).

File:            snep/install/database/update/3.01/updateCallerid.php
Classification:  UPGRADE_SCRIPT / DB_MUTATING_SCRIPT
Before this task: WEB_REACHABLE, UNAUTHENTICATED
Details:         Uses mysql_connect()/mysql_query() -- removed from PHP 8,
                 so it fatals on its very first statement under this
                 project's PHP 8.4 runtime (confirmed live, identical HTTP
                 500 signature to Q-SQL-004's pre-fix state, TASK-0026R
                 §9). Currently DEAD IN PRACTICE due to the PHP-version
                 environment, not due to any access control -- exactly the
                 kind of accidental, non-durable "protection" Phase 4's
                 own instruction warns against relying on. Zero call sites
                 anywhere in the tree.
```

No other executable/mutating file exists under `snep/install/`,
`snep/install/database/`, or `snep/install/database/update/`. This task's
own answer to its Phase 2 question: **the known finding is not isolated —
it has exactly one PHP sibling, and both share the identical root cause
(the whole subtree has no access boundary), which this task's chosen fix
(§4) closes for both simultaneously.**

---

## 3. Phase 3 — call-site / operational necessity audit

Searched for any dependency on these two scripts or on `snep/install/`
being web-reachable:

- Application UI / controllers / AJAX / internal includes: **none**
  (`grep -rn "install/"` across `snep/modules`, `snep/lib`, `snep/agi` —
  zero real references).
- Makefile targets: **none** (`grep -n "update\|migrat\|convert-data\|updateCallerid" Makefile`
  — no hits beyond an unrelated comment about password migration).
- `INSTALL_GUIDE.md` / top-level docs: **none** reference `install/` as a
  browser-driven step.
- Docker Compose / entrypoints: `compose.yaml` bind-mounts
  `./snep/install/database` into the `db` service's
  `docker-entrypoint-initdb.d/snep-install` (read-only) and
  `./snep/install/etc/asterisk/*` into the `asterisk`/`provider` services
  — **filesystem access only**, read directly off the host bind mount by
  those containers' own entrypoints, never through Apache/HTTP. An
  HTTP-layer access-control rule cannot affect this path at all.

**Conclusion**: both PHP scripts are dead in every currently supported
installation/upgrade/CLI/UI path. The only real, current requirement on
`snep/install/` is filesystem presence (for the two bind mounts above),
never HTTP reachability. Per this task's own instruction ("prefer removing
web reachability over inventing authentication for dead maintenance
scripts"), no authenticated workflow was built — reachability itself is
removed.

---

## 4. Phase 4 — containment architecture chosen

**Option A (remove from web root) was not viable as a physical deletion**:
`DocumentRoot` is `snep/` itself, and `snep/install/database` /
`snep/install/etc/asterisk/*` are genuinely required on disk for the
Docker bind mounts identified in Phase 3. Deleting the directory would
break `db`/`asterisk`/`provider` provisioning.

**Option B (web-server deny rule) was chosen** — the broadest safe layer
available: a single `snep/install/.htaccess` denies all HTTP access to
the entire subtree, while leaving the filesystem fully intact for the
Docker bind mounts and any future CLI/internal use:

```apache
Require all denied
```

This is the exact Apache 2.4-native pattern already established in this
codebase (`snep/includes/.htaccess`'s own comment: "so this rule works
without mod_access_compat"), extending the same deny-the-whole-directory
intent `snep/lib/linfo/cache/.htaccess`, `snep/lib/linfo/tests/.htaccess`,
and `snep/lib/linfo/lib/.htaccess` already use (those predate the Apache
2.4-native rewrite `snep/includes/.htaccess` received, so the native
`Require all denied` spelling was used here directly rather than the
Apache 2.2 `Deny from all` spelling).

One file closes the known finding, its one PHP sibling, and every current
and future file placed under `snep/install/` — not a per-script patch,
and not a query-string password/shared-secret/IP-check workaround.

**Option C (application-mediated authenticated workflow) was not used** —
Phase 3 confirmed no supported functionality actually requires direct web
operation of these scripts.

---

## 5. Phase 5 — safe live proof

No destructive migration operation was deliberately executed by this
task's own validation (the one real execution, disclosed in Status above,
was an accidental pre-remediation reachability probe, not a deliberate
proof step). Every post-remediation check below relies on Apache's access
control rejecting the request in its own access-control phase, before
mod_php is ever invoked — a 403 response is inherently proof that PHP did
not run, by construction, not by inference.

```text
GET  /install/database/update/betha/convert-data-rc3.php  -> 403 (before: 200, executed)
POST /install/database/update/betha/convert-data-rc3.php  -> 403
GET  /install/database/update/3.01/updateCallerid.php     -> 403 (before: 200, fataled under PHP 8)
POST /install/database/update/3.01/updateCallerid.php     -> 403
GET  /install/index.html                                  -> 403 (whole-tree proof, not per-script)
GET  /install/database/schema.sql                         -> 403 (whole-tree proof)
GET  /install/                                             -> 403 (directory not browsable)
GET  /                                                      -> 200 (ordinary application route unaffected)
```

Blocked-response body: generic Apache 403 page only (`<title>403
Forbidden</title>` / "You don't have permission to access this
resource.") — no PHP source, no absolute filesystem path, no SQL error
text, no stack trace. (Apache's own default `ServerSignature` line
discloses the Apache version and virtual-host name in the page footer —
a separate, pre-existing, much lower-severity disclosure item already
tracked as out-of-scope Product Readiness debt in
`docs/SECURITY-BASELINE.md`'s "Full HTTP security-header rollout" line;
not a path/source/stack disclosure and not addressed by this narrow
task.)

Filesystem/CLI availability, proven directly (not merely asserted):

```text
docker compose exec app test -f install/database/update/betha/convert-data-rc3.php  -> present
docker compose exec app php -l install/database/update/betha/convert-data-rc3.php    -> no syntax errors
docker compose exec db   test -f /docker-entrypoint-initdb.d/snep-install/schema.sql -> present (bind mount unaffected)
```

---

## 6. Phase 6 — focused security suite

New: `scripts/legacy-maintenance-exposure-security-smoke-test.sh` (15
checks + the harness's own container-health check = 16 rows), wired into
`make legacy-maintenance-exposure-security-smoke`. Uses
`scripts/lib/harness.sh` (same PASS/FAIL/BLOCKED/INCONCLUSIVE contract as
every other focused suite).

```text
make legacy-maintenance-exposure-security-smoke
PASS: 16   FAIL: 0
```

Coverage:

1. known script HTTP GET blocked (403)
2. known script HTTP POST blocked (403)
3. sibling script (`updateCallerid.php`) HTTP GET blocked (403)
4. sibling script HTTP POST blocked (403)
5. a non-PHP static asset under `install/` also blocked (whole-tree proof)
6. a raw `.sql` fixture under `install/` also blocked (whole-tree proof)
7. `install/` directory itself not browsable
8. blocked response discloses no source/path/SQL-error detail
9. `core_peer_groups` row count unchanged by this suite's own probing
10. `peers` table foreign-key state unchanged (0, matching the pre-existing
    schema)
11. no new PHP Fatal Error produced by this suite's own probing
12. ordinary application route (`/`) still returns 200
13. known script remains present on disk (filesystem/CLI availability)
14. known script remains syntactically valid (`php -l`)
15. `db` container's `install/database` bind mount is unaffected

No destructive SQL is ever deliberately executed — every reachability
check expects (and gets) a 403 before PHP would run at all.

---

## 7. Phase 7 — exact sibling audit (post-remediation)

Repeated Phase 2's inventory after remediation:

```text
snep/install/database/update/betha/convert-data-rc3.php   NOT_WEB_REACHABLE (403)
snep/install/database/update/3.01/updateCallerid.php      NOT_WEB_REACHABLE (403)
snep/install/*                                            NOT_WEB_REACHABLE (403), all files
```

No other exposed maintenance tree sharing this deployment root cause
(DocumentRoot == full application tree, no per-subtree access control)
was found outside `snep/install/` within this task's scope. (This task
did not perform a repository-wide unrelated security audit, per its own
scope boundary — only the install/update tree named in the task and its
deployment-root cause.)

```text
UNAUTHENTICATED_WEB_REACHABLE_DB_MUTATING_SCRIPTS = 0
```

---

## 8. Phase 8 — canonical validation

```text
make legacy-maintenance-exposure-security-smoke  -- PASS, 16/16
make lint                                        -- PASS, 5/5
make regression (run 1)                          -- PASS, 23/23 suites
make regression (run 2, no code changes between) -- PASS, 23/23 suites, identical suite-result table to run 1
```

No FAIL, no BLOCKED, no INCONCLUSIVE in either official regression run.
(One BLOCKED cascade was observed during this task's own validation
process on an *unofficial* intermediate regression invocation, caused by
this task's own shell mistake — `source .env` without `set -a`, so
`DB_USER`/`DB_PASSWORD`/`DB_NAME` were not exported to the child
`bash scripts/regression.sh` process. That run was discarded, not counted
as one of the two official runs, and re-run correctly with the same
invocation pattern the Makefile itself uses. `trunk-smoke` was also
separately observed BLOCKED once, standalone, on an initial ad hoc
back-to-back invocation outside the two official runs — re-run standalone
immediately after, it PASSed cleanly 23/23 [sic, 23 checks within that one
suite], consistent with the pre-existing, already-documented PR-06
transient inter-suite PJSIP-reload-timing race, not a regression
introduced by this task.)

```text
SUITE                          RESULT
----------------------------------------------------------------
lint                           PASS
harness-lib-selftest           PASS
preauth-security               PASS
sql-security                   PASS
residual-sql-security          PASS
shell-security                 PASS
pjsip-config-security          PASS
api-security                   PASS
api-sql-security               PASS
session-csrf-security          PASS
auth-hardening-security        PASS
disclosure-path-security       PASS
legacy-maintenance-exposure-security PASS
authorization-coverage         PASS
authorization-smoke            PASS
http-smoke                     PASS
cdr-window-selftest            PASS
call-smoke                     PASS
trunk-smoke                    PASS
transport-smoke                PASS
restart-smoke                  PASS
external-failure-smoke         PASS
external-content-smoke         PASS
----------------------------------------------------------------
REGRESSION                     PASS
```

(Identical in both official runs.)

---

## 9. Phase 9 — security regression integration

`legacy-maintenance-exposure-security` is wired into
`scripts/regression.sh` immediately after `disclosure-path-security` and
before `authorization-coverage` — the security-suite block this task's own
instruction named ("near disclosure/path or authorization coverage"), and
the same placement rationale every other independent trust-boundary suite
in this block already uses (an independent proof, no shared fixture
dependency with what follows, ahead of the authorization/http-smoke/
telephony suites).

`make legacy-maintenance-exposure-security-smoke` was also added to the
Makefile, alongside every other focused suite, deliberately kept out of
`make smoke` (matching every prior TASK-0026x focused-suite convention).

---

## 10. Phase 10 — health and integrity

- `docker compose ps`: `app`/`asterisk`/`db`/`provider` all `Up (healthy)`.
- Asterisk **22.11.0** (unchanged, matches the repository's pinned
  version).
- `res_pjsip.so` — 1 module, **Running**.
- `pjsip show transports`: 3 baseline transports intact (`tcp`, `udp`,
  `wss`).
- AMI: `manager show connected` responsive, 0 connected users.
- ODBC: `snep` DSN, 1/1 active connection.
- `core show channels count`: 0 active channels, 0 active calls.
- **Database object involved in the original TASK-0026R accidental
  request, explicitly re-verified**: `core_peer_groups` = 0 rows;
  `information_schema.TABLE_CONSTRAINTS` shows 0 foreign keys on `peers`
  (the exact constraint the script's first statement targets does not
  exist, matching TASK-0026R's own finding and this task's own second
  accidental trigger, both non-mutating); `peers` has no `group` column
  and no `groups` table exists (the script's final DDL section, dropping
  both, could never have executed even had the first `ALTER` succeeded —
  confirmed as a genuine, pre-existing, unrelated schema-mismatch, not
  something either accidental trigger caused).
- No migration/test fixtures or smoke processes left running; the only
  extra containers present on the host (`evo-crm-community-*`,
  `qflow-*`) belong to unrelated projects on this machine, not SENMA PBX.
- `git diff --check`: clean.

---

## 11. Files changed

```text
snep/install/.htaccess                                        new -- denies all HTTP access to the installer/migration subtree
scripts/legacy-maintenance-exposure-security-smoke-test.sh     new -- focused regression suite (16 checks)
Makefile                                                        +14/-1 -- new PHONY entry + legacy-maintenance-exposure-security-smoke target
scripts/regression.sh                                           +6 -- wires the new suite into the canonical regression, after disclosure-path-security
docs/tasks/0026s-legacy-maintenance-web-exposure-hardening.md   new, this file
```

`.nexus/` remains untouched. No SQL-injection code was reopened. No
Product Readiness milestone was started. No file outside the above list
was modified.

---

## 12. Root cause summary

`docker/apache-mag.conf` sets `DocumentRoot` to the entire `snep/`
application tree, with no per-subtree access boundary for
`snep/install/`. Every file under it — including two PHP scripts capable
of destructive, unauthenticated DDL/DML against the live database — was
therefore served exactly like any other application file, with zero
authentication and zero access control. Neither script has any current
call site (CLI, Makefile, controller, or documented maintenance
procedure); both are dead maintenance artifacts kept on disk only for
historical reference and (for the parent `install/database` /
`install/etc/asterisk` directories generally) Docker bind-mount
provisioning. The fix closes the boundary at its root — the whole
`snep/install/` subtree, not the one discovered script — with a single
web-server-layer deny rule that leaves filesystem/CLI/Docker-bind-mount
access completely unaffected.

---

## 13. Final gate state

```text
UNAUTHENTICATED_WEB_REACHABLE_DB_MUTATING_SCRIPTS = 0
```

This task closes the specific, narrow finding TASK-0026R disclosed. It
does not reopen or re-evaluate `SECURITY_GATE` as a whole (still `NO-GO`
per `docs/tasks/0026z-security-audit-closure.md` pending TASK-0026J-style
work on `Snep_InterfaceConf.php`/`CallsReportController.php`, which this
task's scope explicitly excludes) and does not begin Product Readiness.

Stopping at the validated TASK-0026S checkpoint, as instructed. Not
committed — awaiting explicit authorization.
