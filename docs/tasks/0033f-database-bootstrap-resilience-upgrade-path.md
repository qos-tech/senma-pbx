# TASK-0033F — Database Bootstrap Resilience & Upgrade Path

Status: implemented and validated. Lead: `senma-application-architect`.
Reviewer: `senma-docker-platform-engineer`. `senma-telephony-architect`
not invoked -- the one shipped content migration (an index) does not
change PJSIP/telephony semantics. `senma-product-designer` not invoked
-- no new admin-facing workflow was created; `make migrate`/`make
migrate-check` are operator CLI commands, matching every other TASK-0033
lifecycle tool (backup, restore, rotate-secrets, reconcile, doctor).

---

## CURRENT BOOTSTRAP (before this task)

Traced end to end, live behavior confirmed, not inferred from comments:

```text
compose.yaml (db service)
  -> mariadb:10.11 official image, MariaDB's own docker-entrypoint.sh
  -> /docker-entrypoint-initdb.d/ (only on a truly EMPTY /var/lib/mysql):
       00-import-snep-schema.sh
         -> snep-install/schema.sql   (all CREATE TABLE)
         -> snep-install/system_data.sql  (seed INSERTs, INSERT-once)
         -> snep-billing/schema.sql   (billing module's own schema)
  -> mariadbd starts serving; docker/healthcheck-db.sh gates readiness
     (TASK-0033E: root+app auth, `core_config` table present)
```

`docker/entrypoint.sh` (the `app` container) has its OWN, entirely
separate "bootstrap" concept (`setup.conf` generation,
`bootstrap-admin.php` replacing the seeded admin sentinel password) --
it has zero visibility into or coordination with the DB schema
bootstrap above.

**No schema version tracking existed at all** before this task --
`core_config` (a generic key/value settings table) was the closest thing
to a marker, and TASK-0033E's own `docker/healthcheck-db.sh` merely
checked that this table *exists*.

---

## ROOT CAUSE

**Bootstrap invariant violation, reproduced live** (isolated Compose
project, main dev stack never touched): a deliberate failure injected
between `schema.sql` (creates `core_config`, empty) and
`system_data.sql` (seeds it, 5 rows) produces this sequence:

1. The container exits (`docker-entrypoint-initdb.d` script failure ->
   MariaDB's own official entrypoint aborts the whole container start).
2. Docker's `restart: unless-stopped` policy (already declared on every
   service in `compose.yaml`, pre-existing) restarts it almost
   immediately -- `RestartCount` confirmed >=1, but the transient
   `exited` state itself is sub-second and not reliably observable by
   polling.
3. On this and every subsequent restart, `docker-entrypoint-initdb.d`
   never runs again (`/var/lib/mysql` is no longer empty) -- the
   container just starts `mariadbd` directly, with `core_config`
   PRESENT but EMPTY (0 rows), `users` present but empty (no admin
   seed), `pjsip_transports` never seeded, the billing schema never
   imported.
4. **The pre-existing `docker/healthcheck-db.sh` (table-existence-only
   check) reported READY regardless** -- a failed bootstrap was
   misclassified as initialized, exactly the invariant this task exists
   to close.

Classification: `REAL_PRODUCT_BUG` (a real gap in the production
readiness contract, not a test-harness artifact) -- confirmed via
`scripts/db-migration-failure-smoke-test.sh` Phase B, in an isolated
Compose project, main dev stack untouched.

---

## SCHEMA BASELINE

Compared fresh-install schema (current `schema.sql`) against
`snep/install/database/update/{3.01..3.07,betha}/*.sql`: **they do not
converge, and this is intentional, not a defect to fix.**

The `update/` chain was authored for a bare-metal SNEP install predating
this project's Docker-first architecture entirely; it was never wired
into `docker-entrypoint-initdb.d`, no known install reaches this schema
baseline via that chain, and it stops at SNEP 3.07 -- while `schema.sql`
has since gained TASK-0018's `pjsip_transports`, TASK-0026H's password
hardening + `login_attempts`, and TASK-0029A's TLS certificate fields,
**added by direct edits to `schema.sql` itself, with no migration file
of any kind**. This is the actual gap TASK-0033 identified: this
project's own SENMA-era schema growth had no version tracking at all.

Classification: `update/*` = `HISTORICAL_ONLY` (SNEP 3.01-3.07,
Docker-era-irrelevant) / `MANUAL_ONLY` (`update/betha/*`, a
customer-specific one-off never part of the supported install path).
No critical `UNKNOWN` remains -- every file's relationship to the
current schema is now classified.

---

## VERSION MODEL

One dedicated ledger table, created idempotently wherever it doesn't
yet exist (fresh-install marker script OR the migration runner's own
first-run bootstrap):

```sql
CREATE TABLE IF NOT EXISTS schema_migrations (
  id VARCHAR(64) NOT NULL,
  applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum VARCHAR(64) NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
```

Not inferred from table/column/file existence as the long-term tracker
(Phase 4's own explicit instruction) -- structural fingerprinting is
used ONLY once, to onboard a pre-existing install (see EXISTING-INSTALL
BASELINE below), never as an ongoing substitute for this table.

---

## MIGRATION METADATA / NAMING / ORDER

`NNNN-description.sql`, sequential, in
`snep/install/database/migrations/`:

- `0000-baseline.sql` -- intentionally inert (`SELECT 1` + documentation
  comment only). Represents everything `schema.sql`/`system_data.sql`
  already create; never executed on a fresh install (see FRESH-INSTALL
  PROOF), only ever recorded.
- `0001-add-cdr-uniqueid-index.sql` -- the one real, shipped content
  migration: `ALTER TABLE cdr ADD INDEX IF NOT EXISTS uniqueid
  (uniqueid);`. Chosen deliberately narrow and evidence-backed (every
  CDR-writing regression suite already queries `cdr` by `uniqueid`;
  index-only, no semantic change, safe to retry) specifically to prove
  the runner end to end without inventing a fake business column
  (Phase 22's own instruction). **Mirrored directly in `schema.sql`**
  (same `KEY` added to the `cdr` table there) so a fresh install lands
  on it natively -- see FRESH-INSTALL CONVERGENCE.

Historical `update/*` files were **not** renamed or absorbed into this
numbering (Phase 5's own instruction against gratuitous renaming that
breaks provenance) -- they remain exactly where they are, documented as
out of this tracker's scope.

---

## EXISTING-INSTALL BASELINE

`BASELINE_IF_SCHEMA_MATCHES`, live-validated against this project's own
main dev database (provisioned before this task existed, `git show
HEAD:...schema.sql` shows no `schema_migrations` table was ever
created for it): `docker/migrate.php`'s first-ever run against a
database with no `schema_migrations` table walks the shipped
migrations in order; for each one that predates the tracker
(`0000-baseline`, `0001-add-cdr-uniqueid-index`), it checks that
migration's own structural fingerprint (see below) before recording it
-- the FIRST migration whose fingerprint does NOT match stops the
baselining walk and is applied for real instead. **Never blindly marks
an unverified schema as current.**

Live proof against this project's own main dev install (created before
this task, missing only the `cdr.uniqueid` index): `0000-baseline`
baselined by fingerprint, `0001-add-cdr-uniqueid-index` correctly
detected as genuinely pending, applied for real (`ALTER TABLE`
executed), confirmed `SCHEMA_CURRENT` afterward.

---

## STRUCTURAL FINGERPRINT

`0000-baseline`'s fingerprint (representative, not exhaustive, per
Phase 7's own instruction): `core_config`, `users`, `pjsip_transports`,
`cdr`, `peers`, `trunks`, `login_attempts` tables exist, AND
`pjsip_transports.cert_file` column exists, AND `users.password` is
`VARCHAR(>=255)`. `0001-add-cdr-uniqueid-index`'s fingerprint: does
`SHOW INDEX FROM cdr WHERE Key_name='uniqueid'` return a row.

If the CORE (`0000`) fingerprint does not match at all, the runner
reports `SCHEMA_UNKNOWN` and refuses to act (see UNKNOWN-SCHEMA HANDLING
below) -- no known install currently in this state, but the contract
exists and is proven live (Phase 35/36).

---

## BOOTSTRAP STATE MACHINE

```text
EMPTY         -- no application tables at all (unreachable in normal
                 operation: app's depends_on: db: condition:
                 service_healthy already gates on core_config having
                 rows, so migrate.php never runs against a truly empty
                 DB in practice)
INITIALIZING  -- not independently observable from outside the
                 container (Docker exposes no such signal); treated as
                 "not yet reachable", not a persisted state
INITIALIZED   -- schema_migrations exists, >=1 row (bootstrap-
                 completion marker present)
FAILED        -- core_config exists but is EMPTY (the proven partial-
                 failure signature) -- docker/healthcheck-db.sh now
                 detects this explicitly and reports FAIL, permanently,
                 until a genuine re-bootstrap
UNKNOWN       -- tables exist but match neither EMPTY nor any known
                 baseline/migration fingerprint -- migrate.php refuses
                 to guess, exit 2
```

---

## BOOTSTRAP COMPLETION INVARIANT

`docker/db-init/99-bootstrap-marker.sh` -- a NEW file, lexically last
among `/docker-entrypoint-initdb.d/` scripts (after
`00-import-snep-schema.sh`). MariaDB's official entrypoint executes
initdb.d scripts in sorted order and aborts the ENTIRE container start
on the first failing script (live-confirmed) -- so this script only
ever runs if every earlier import step already succeeded. It creates
`schema_migrations` and records every shipped migration as baselined.

`docker/healthcheck-db.sh` was changed from "`core_config` table
exists" to "`core_config` has `COUNT(*) > 0`" -- **deliberately NOT**
gated on `schema_migrations` existing (see the dedicated note in that
file, and DEADLOCK AVOIDANCE below). One table (`schema_migrations`)
serves both the fresh-install completion marker AND the ongoing
migration ledger -- no second, competing readiness truth was invented
(Phase 11's own instruction).

### Deadlock avoidance (a real bug found and fixed during this task)

The FIRST implementation gated `healthcheck-db.sh` on
`schema_migrations` existing. This deadlocks any install provisioned
*before* this task: `schema_migrations` never exists for such an
install (its `/var/lib/mysql` is non-empty, so
`docker-entrypoint-initdb.d` never runs again), `db` would report
`unhealthy` forever, `app`'s hard `depends_on: db: condition:
service_healthy` (TASK-0033E) would then never start `app`, and `make
migrate`'s own baselining logic -- which runs *inside* `app` -- would
never get the chance to run. Caught by running the ACTUAL suite against
this project's own real pre-task dev database, not a simulation. Fixed
by keeping the healthcheck on the `core_config` row-count signal only
(a table that predates this task, present on every install regardless
of migration-tracker awareness) and leaving schema *version* status
entirely to `make doctor`/`make migrate-check` (non-blocking, see
READINESS/DOCTOR INTEGRATION).

---

## SEED-DATA OWNERSHIP CONTRACT

`system_data.sql` classified per Phase 12, by inspection (not run
twice against a live DB -- several rows have no unique constraint at
all, e.g. `expr_alias_expression` already contains literal duplicate
key values by design):

| Data | Classification |
|---|---|
| `expr_alias`, `expr_alias_expression`, `sounds`, `ccustos`, `regras_negocio*` | `INSERT_ONCE` -- fresh-install-only reference/seed data, never re-run |
| `core_groups`, `contacts_group`, `grupos` (pickup group) | `INSERT_ONCE` -- default rows, immediately customer-mutable after install |
| `users` (admin row) | `INSERT_ONCE` seed, `CUSTOMER_MUTABLE` immediately after -- the sentinel password (`!SENMA-BOOTSTRAP-PENDING!`) is replaced by `bootstrap-admin.php` on first `app` boot, itself idempotent (TASK-0026H) |
| `pjsip_transports` (`udp`/`tcp`/`wss` seeds) | `INSERT_ONCE`, `CUSTOMER_MUTABLE` immediately after -- `is_seed` flag already distinguishes these from operator-created transports (TASK-0018) |
| `core_config` (`host_notification`, `update_server`, ...) | `INSERT_ONCE`, `CUSTOMER_MUTABLE` -- generic settings table, already writable via the admin UI |

No `MIGRATION_OWNED` seed rows exist yet (the one shipped migration is
index-only). **This task does not re-run or touch `system_data.sql`
under any circumstance** -- it is fresh-install-only, exactly as before.
Future migrations that need to seed/adjust rows must use `INSERT ... ON
DUPLICATE KEY UPDATE` or an explicit existence check, never a blind
`INSERT`, to respect already-customer-mutated rows (Phase 19's own
authoring rule).

---

## MIGRATION RUNNER

`docker/migrate.php`, PHP (raw PDO, no Zend/MVC bootstrap -- same
convention as `docker/bootstrap-admin.php`), baked into the `app` image
(`docker/app.Dockerfile`), invoked via `docker compose exec app php
/usr/local/bin/migrate.php [--check]`.

**Why PHP, not bash+`mysql -N`** (Phase 14, "small SENMA-native
runner"): the fingerprint/baseline/lock/checksum logic involves enough
conditional branching and string/data handling that a bash
reimplementation would need substantially more machinery (associative
result parsing, manual escaping) than this project's own precedent
(`bootstrap-admin.php`, `reconcile-pjsip.php`) already establishes for
comparable CLI tools. No new dependency was introduced -- `mysqli`/`pdo_mysql`
were already installed in the `app` image.

**Why the `app` container, not `db` or a dedicated one-shot service**
(Phase 14): DB client availability (already present), file access
(migrations ship inside `snep/`, already bind-mounted into `app`),
secret handling (reads the same `DB_USER`/`DB_PASSWORD`/`DB_NAME` env
vars `setup.conf` already uses -- TASK-0033C's post-rotation model, no
separate credential path), and operational simplicity (no new
container/service, matching Phase 14's explicit preference).

---

## AUTOMATIC/MANUAL POLICY

**HYBRID**, per Phase 15:

- Fresh-install baseline recording is AUTOMATIC (`99-bootstrap-marker.sh`,
  no operator action, no `migrate.php` invocation needed at all on a
  fresh install -- live-proven).
- Every migration after the baseline is EXPLICIT operator action:
  `make migrate`. Nothing was added to `docker/entrypoint.sh`'s own
  startup sequence -- `app` boots exactly as before, whether or not a
  migration is pending.

Rationale: this project's own established pattern for every other
lifecycle operation (backup, restore, secret rotation, PJSIP
reconciliation) is explicit `make <verb>`, never automatic-at-boot
mutation. Automatic forward migrations at every `docker compose up`
would risk silently applying schema changes during an unattended
restart -- directly at odds with Phase 27's destructive-migration
caution and this project's own "explicit operator action" precedent.

---

## LOCKING

`SELECT GET_LOCK('senma_schema_migrations', 10)` -- a real MariaDB
advisory lock, bounded 10s wait, never unbounded. Live-proven: a
lock held by a separate connection causes a concurrent `migrate.php`
invocation to fail with `FAIL: migration already in progress (could not
acquire the schema migration lock within 10s)`, exit 5, after
~10 seconds (not instantly, not indefinitely). The lock is released via
`register_shutdown_function` (best-effort) and also auto-releases when
the PHP process's own DB connection closes, whichever comes first.

---

## SCHEMA COMPATIBILITY STATES

`migrate.php --check` distinguishes, by comparing `schema_migrations`
against the migration files actually shipped in this codebase:

- `SCHEMA_CURRENT` (exit 0) -- nothing pending, nothing orphaned.
- `SCHEMA_BEHIND` (exit 3) -- pending migration(s) exist; lists them by
  id, flags any marked `SENMA-DESTRUCTIVE`.
- `SCHEMA_AHEAD` (exit 4) -- `schema_migrations` records an id with no
  matching file in this codebase (rolled-back app code against an
  already-migrated database). Apply mode REFUSES to act at all in this
  state (Phase 16: "do not let old code run unknowingly against a newer
  schema").
- `SCHEMA_UNKNOWN` (exit 2) -- structural fingerprint matched neither
  empty nor any known baseline; refuses to guess, names exactly what is
  missing.

**Scope boundary, deliberately not built**: the running PHP web
application itself does not yet self-check `SCHEMA_AHEAD`/`BEHIND`
per-request. Phase 17 explicitly instructed "keep changes narrow, do
not redesign readiness generally" -- wiring this into the application's
own request bootstrap (`Bootstrap.php` or equivalent) is a materially
larger, riskier change than this task's own operator-facing tooling.
Recorded as REMAINING DEBT, not silently skipped.

---

## READINESS/DOCTOR INTEGRATION

- `docker/healthcheck-db.sh`: strengthened (row-count, not table-
  existence) to close the proven bootstrap-invariant gap. Runs every
  5s, one indexed `SELECT COUNT(*)` -- no measurable cost change.
- `docker/healthcheck-app.sh`: **unchanged**. Schema *version* status
  is deliberately NOT part of any Docker healthcheck (Phase 39: "do not
  run full migration discovery every few seconds") -- it is a doctor/
  `migrate-check` concern, matching TASK-0033E's own precedent for ODBC
  (DEGRADED-not-NOT_READY, surfaced via `doctor`, not the healthcheck
  loop).
- `scripts/doctor.sh`: one new check, `check_db_migration_status`, which
  SHELLS OUT to the exact same `migrate.php --check` command `make
  migrate-check` runs (Phase 38's own instruction: "do not duplicate
  migration detection logic inside doctor") and maps its exit code to
  `PASS`(0)/`WARN`(3, BEHIND)/`FAIL`(4 AHEAD, 2 UNKNOWN).

---

## ROLLBACK POLICY

**FORWARD_ONLY**, per Phase 28's own suggested safest baseline: no down
migrations were implemented (none proven safe -- Phase 28 explicitly
warns against "fake down migrations that have not been proven safe").
Rollback = restore a pre-migration backup (TASK-0033A, `make restore`)
followed by `migrate.php --check` correctly reporting `SCHEMA_BEHIND`
against the restored (older) database -- not a silent, undetected
mismatch. This project's own migration history to date (the `update/`
chain) was never designed with down-migrations either, so this is
consistent with prior practice, not a new limitation introduced here.

---

## BACKUP INTEGRATION

Contract, documented rather than a built classifier (Phase 26's own
explicit instruction: "do not invent a complex classifier unless
needed"): `make migrate` does NOT automatically invoke `make backup`.
A migration whose file header contains the literal marker
`SENMA-DESTRUCTIVE` triggers a printed warning banner
("ensure a recent backup exists (make backup) before proceeding")
before it applies -- the runner detects the marker (`grep`-equivalent
over the first 4KB of the file) but never blocks on it. The one shipped
migration (`0001-add-cdr-uniqueid-index`) carries no such marker (it is
index-only, non-destructive). Recommended operator sequence for any
future destructive migration: `make backup && make migrate`.

---

## RECONCILIATION INTEGRATION

`make reconcile-check` was run after applying the migration during this
task's own validation and reported `IN_SYNC` -- the one shipped
migration does not touch any PJSIP-managed table, so no drift was
expected or found. Documented as the operator contract for any FUTURE
migration that does touch `pjsip_transports`/`peers`/`trunks`: run
`make reconcile-check` (and `make reconcile` if it reports drift) after
`make migrate`. Not wired in automatically -- Phase 30's own explicit
instruction against making every migration auto-reconcile.

---

## SECRET-ROTATION INTEGRATION

`docker/migrate.php` reads `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USER`/
`DB_PASSWORD` from the `app` container's own environment -- the exact
same, currently-declared credential `setup.conf` already uses
(TASK-0033C's post-rotation model). No separate or stale credential
path exists. Verified live: the migration runner correctly connects and
operates on this project's already-rotated-at-least-once dev
installation throughout this task's own validation.

---

## FRESH-INSTALL PROOF

Isolated Compose project, empty volume:
`schema.sql`/`system_data.sql`/billing schema import (unchanged) ->
`99-bootstrap-marker.sh` runs last -> `schema_migrations` created with
**2 rows, automatically, before `migrate.php` is ever invoked** ->
`migrate.php --check` reports `SCHEMA_CURRENT` immediately -> `db`
restarted -> `schema_migrations` unchanged (still 2 rows). Matches
Phase 32's "fresh baseline, then migration runner confirms no pending"
option -- `schema.sql` is kept in sync with every shipped migration's
cumulative effect (the `cdr.uniqueid` index is declared directly in
`schema.sql` too), so a fresh install never needs to actually execute
`0001-add-cdr-uniqueid-index.sql`, only record it.

---

## UPGRADE PROOF (older-schema fixture)

Per Phase 34's own suggested approach ("a fresh baseline intentionally
missing the latest migration"): `git show HEAD:snep/install/database/schema.sql`
(the schema as it existed immediately before this task, missing the
`cdr.uniqueid` index) bind-mounted over the isolated project's own
schema.sql, WITH `99-bootstrap-marker.sh` also replaced by a no-op
(simulating a real pre-TASK-0033F install that never had this task's
own automatic marker at all). Result, live: `schema_migrations` absent
at boot (correctly simulating a genuine pre-existing install) ->
`migrate.php --check` baselines `0000-baseline` by fingerprint, detects
`0001-add-cdr-uniqueid-index` as genuinely pending (`SCHEMA_BEHIND`,
exit 3) -> `make migrate`-equivalent applies it for real (`ALTER TABLE`
executed against the live database) -> `SHOW INDEX` confirms the index
now exists -> `migrate.php --check` reports `SCHEMA_CURRENT`.

---

## FAILURE PROOF

**Partial bootstrap** (isolated project): schema.sql succeeds, deliberate
failure before `system_data.sql` -> container crashes (Docker
`RestartCount` >=1, proving a real crash, not a silent partial success)
-> `restart: unless-stopped` brings it back "Up" almost immediately,
but `docker-entrypoint-initdb.d` never runs again -> `core_config`
present, 0 rows -> `healthcheck-db.sh` reports `FAIL: bootstrap
incomplete` -- permanently, correctly, never falsely READY ->
`schema_migrations` confirmed never created -> genuine repair (`down
-v` + clean re-bootstrap) succeeds and is recognized READY.

**Mid-migration failure + retry** (isolated project, purpose-built
test-only migrations never shipped in the real `migrations/` directory
-- Phase 22's own instruction against polluting real schema with fake
content): migration A applied+recorded, migration B fails deliberately
(invalid SQL) -> B NOT recorded, migration C never attempted (its own
marker table confirmed absent) -> B's file content repaired -> retry ->
B and C both apply correctly, in order -> `SCHEMA_CURRENT`.

---

## SECRET NON-DISCLOSURE

`scripts/db-migration-smoke-test.sh` grep-checks `migrate.php`'s own
`--check` and apply-mode output for all three live secret values
(`DB_PASSWORD`, `DB_ROOT_PASSWORD`, `AMI_PASSWORD`) -- none found. PDO
exception messages contain SQLSTATE/driver text, never a credential
(no migration's SQL body embeds one). No SQL file content or file dump
appears in normal output -- only migration ids and short human-readable
status lines (Phase 41).

---

## REMAINING DEBT

1. **Application-level `SCHEMA_AHEAD`/`BEHIND` self-check is not
   wired into the running PHP app's own request bootstrap.**
   Deliberate scope boundary (Phase 17: "keep changes narrow"). Visible
   today via `make doctor`/`make migrate-check` only.
   `FOLLOW_UP_DEBT` if a real incident ever demonstrates old code
   silently misbehaving against a newer/older schema mid-request.
2. **Historical `update/3.01-3.07`/`update/betha` SQL remains
   unabsorbed into the new tracker**, by design (Phase 5). If a real,
   verified pre-3.07 install is ever discovered to exist, onboarding it
   is a dedicated follow-up, not automatic.
3. **Three pre-existing, unrelated test failures were discovered
   during this task's own regression validation, root-caused with
   direct evidence, and deliberately NOT fixed** (out of scope, "do not
   fix unrelated legacy bugs opportunistically"):
   - `legacy-maintenance-exposure-security-smoke-test.sh` check 10 and
     `pjsip-reconcile-smoke-test.sh`'s dangling-transport-reference
     setup both assume `peers.transport_id` has no enforced foreign
     key. It does (`peers_ibfk_2 -> pjsip_transports`, confirmed present
     in `git show HEAD:snep/install/database/schema.sql`, added by
     TASK-0018 -- unrelated to this task). `pjsip-reconcile-smoke`'s own
     raw-SQL fixture setup for that one check now fails with a real
     `ERROR 1452` FK violation before the application-level assertion
     it exists to test can even run.
   - `scripts/smoke-test.sh`'s "dashboard" check (`GET /index.php/`)
     assumes a fresh session renders the dashboard directly.
     `IndexController::indexAction()` actually gates on
     `$_SESSION['registered']`/`$_SESSION['noregister']` (a legacy
     SNEP/ITC product-registration prompt), which a genuinely fresh
     session never has set -- confirmed by direct code inspection, has
     nothing to do with database schema/migrations.
   Both reproduced identically and deterministically across two
   independent, full regression runs -- not flaky, not caused by this
   task's changes (neither touches PHP session handling, routing, or
   the `peers` table). Each needs its own dedicated
   `fix/`-classified task: correct the two tests' stale FK assumption,
   and either fix or intentionally accept-and-update the ITC
   registration-gate assumption in `smoke-test.sh`.
