# TASK-0033F1 — Regression Contract Repair After Schema and Session Evolution

## Status

Implementation complete and validated. `make lint` PASS. Two consecutive
full `make regression` runs both PASS, **37/37 suites each**, no code
changes between them, no stack reset/DB repair between them. Only
`scripts/*.sh` files changed — no production code, schema, or migration
changed. Not committed — this is the validated TASK-0033F1 checkpoint,
awaiting explicit authorization to commit.

```text
make regression -> 37/37 PASS (both runs)
```

---

## ORIGINAL FAILURES

TASK-0033F's own regression validation (two independent full runs,
`docs/tasks/0033f-database-bootstrap-resilience-upgrade-path.md`
"REMAINING DEBT") already root-caused, but deliberately did not fix,
exactly three deterministic failures out of 37 suites (34/37 PASS both
times, identical failures both times):

```text
legacy-maintenance-exposure-security-smoke-test.sh  FAIL (check 10)
smoke-test.sh ("http-smoke")                        FAIL ("dashboard")
pjsip-reconcile-smoke-test.sh                        FAIL (scenario 8, 2 checks)
```

Reproduced independently here, standalone, before any change (evidence
kept in this session's scratchpad logs):

- `legacy-maintenance-exposure-security-smoke-test.sh`: 15 PASS, 1 FAIL
  — check 10 ("peers table foreign-key state unchanged") FAILed with
  `found 2 foreign key(s) -- unexpected schema change`.
- `pjsip-reconcile-smoke-test.sh`: 32 PASS, 2 FAIL — `UPDATE peers SET
  transport_id = 999999 ...` itself failed live with `ERROR 1452 (23000)
  ... a foreign key constraint fails`, so scenario 8's two checks
  ("reconcile refuses to publish with a dangling transport reference",
  "active files left byte-identical after a refused publish") both
  FAILed.
- `smoke-test.sh`: 15 PASS, 1 FAIL — `dashboard` FAILed with `HTTP 200
  but expected content marker not found: 'var controller = "index"'`
  against `GET /index.php/`.

---

## ROOT CAUSE — LEGACY SECURITY

**Classification: `STALE_FIXTURE`.**

Check 10 hardcoded a literal assumption:

```bash
FK_COUNT="$(db_query "... peers ... CONSTRAINT_TYPE='FOREIGN KEY';")"
if [ "$FK_COUNT" = "0" ]; then harness_ok ...; else harness_bad ...; fi
```

Live evidence, `information_schema.KEY_COLUMN_USAGE` against the current
schema, confirms `peers` currently has **two** foreign keys:

```text
peers_ibfk_1  pickupgroup   -> grupos(cod_grupo)
peers_ibfk_2  transport_id  -> pjsip_transports(id)
```

Git history shows neither is new relative to when the assertion was
written:

```text
b88e196 (2026-08-24, "chore: bootstrap Claude Code development harness")
  -- pickupgroup FK present in schema.sql since this repository's very
     first commit.
6b91848 (2026-08-26, "feat: add first-class PJSIP transport management")
  -- TASK-0018 adds the transport_id FK.
57d2593 (2026-09-02, "test(security): add legacy maintenance exposure
  regression coverage") -- the FK_COUNT==0 assertion is added HERE, six
  days after both FKs already existed in schema.sql.
```

So the "0" baseline was never actually true against `schema.sql` at the
moment it was written — it reflects
`docs/tasks/0026s-legacy-maintenance-web-exposure-hardening.md`'s own
live dev-database snapshot, taken from a long-lived DB volume that
predated the FK-bearing schema.sql on disk (TASK-0033F's bootstrap/
migration lifecycle did not exist yet, so nothing enforced schema/DB
convergence). TASK-0033F's new migration/bootstrap-completion invariant
is what finally makes a dev DB volume deterministically match
`schema.sql`, and that convergence is precisely what surfaced this
latent staleness — tying this task's name ("...After Schema and Session
Evolution") together.

Neither FK is new, incidental, or a candidate for removal:
`pickupgroup` is original SNEP schema; `transport_id` is TASK-0018's
deliberate, documented, currently load-bearing PJSIP transport
association (`ON DELETE RESTRICT`, i.e. the database itself now
guarantees a peer can never dangle).

---

## ROOT CAUSE — PJSIP RECONCILE

**Classification: `WRONG_TEST_ASSUMPTION`** (the invalid state the
fixture modeled is no longer representable; the underlying reconciliation
contract itself is unaffected).

Scenario 8 modeled "dangling `transport_id`" via raw SQL:

```sql
UPDATE peers SET transport_id = 999999 WHERE name = '1094';
```

The same TASK-0018 FK from the finding above
(`peers_ibfk_2 ... transport_id ... REFERENCES pjsip_transports(id) ON
DELETE RESTRICT`) now rejects this outright:

```text
ERROR 1452 (23000): Cannot add or update a child row: a foreign key
constraint fails (`snep`.`peers`, CONSTRAINT `peers_ibfk_2` ...)
```

so the UPDATE never applies, `peers.transport_id` stays at its prior
value, `Reconciler::reconcile()` sees a perfectly valid DB state, and
both downstream assertions fail for the same reason: there was nothing
invalid to refuse.

This is not a case of the FK making the reconciliation contract
untestable — `Snep_PjsipConf::resolveTransportName()`
(`snep/lib/Snep/PjsipConf.php`) throws `PBX_Exception_NotFound` for
**two** distinct conditions, and the FK only closed off one of them:

```text
transport referenced but missing   -> now unreachable (FK, ON DELETE RESTRICT)
transport referenced but DISABLED  -> still fully reachable (enabled is
                                       just a column value; the row itself
                                       is untouched)
```

`PjsipTransportsController` (TASK-0019 item 12,
`snep/modules/default/controllers/PjsipTransportsController.php` line
116) documents disabling a referenced transport as "a deliberately
allowed admin action (unlike delete)" whose resulting invalid state
reconciliation must refuse to publish — i.e. the disabled-transport case
is not a workaround, it is the actual, current, supported second half of
this exact contract, reachable entirely through real HTTP flows (create
transport enabled -> pin an extension to it -> disable it).

---

## ROOT CAUSE — HTTP SESSION

**Classification: `WRONG_TEST_ASSUMPTION`**, refined beyond
TASK-0033F's own documented hypothesis by direct evidence gathered here.

Confirmed by direct code inspection
(`snep/modules/default/controllers/IndexController.php` line 35):

```php
if( $_SESSION['registered'] != true && $_SESSION['noregister'] != true){
    // ... legacy SNEP/ITC registration prompt, layout 'register' ...
```

A genuinely fresh authenticated session never has either flag set, so
`GET /index.php/` never unconditionally renders the dashboard — this
confirms TASK-0033F's documented hypothesis.

Going further (verified live, not assumed): the registration-gate branch
itself performs a real, synchronous HTTP ping to
`$config->system->itc_address` before rendering, and switches to a
different page layout (`register`, distinct from the normal app chrome)
whose *inner* content depends on that ping's result — success (200),
server error (500), no connectivity (`false`), or (observed live in this
dev environment) an unexpected code, which renders a generic `Erro:
Código404` state, not a clean registration form. So the exact HTML this
route returns for an unregistered session is not even a single fixed
alternative — it is one of several sub-states, all sharing one
unconditional structural wrapper (`register.phtml`'s outermost
`<body class="registerbody"><div id="registerLayout">`).

None of this is a regression introduced by TASK-0033F (no session,
routing, or `peers`-table code was touched by that task) and none of it
is a bug this task is authorized to fix in production — the gate, the
ITC ping, and the layout switch are all pre-existing legacy behavior.

---

## CURRENT SCHEMA CONTRACT

```text
peers.pickupgroup   -> grupos.cod_grupo        ON UPDATE CASCADE ON DELETE SET NULL  (original SNEP schema)
peers.transport_id  -> pjsip_transports.id     ON DELETE RESTRICT                    (TASK-0018)
```

A `peers` row can never reference a nonexistent `pjsip_transports` row
(enforced by the database itself). It CAN reference a transport row that
still exists but has been administratively disabled
(`pjsip_transports.enabled = 0`) — the FK has no opinion on `enabled`,
only on row existence. `Reconciler::generateAll()`
(`snep/lib/Snep/Pjsip/Reconciler.php`) treats any per-row generator
warning (dangling-or-disabled transport, unsafe field value, etc.) as
`INVALID_DB_STATE` for a full reconciliation, even though the same
condition is tolerated (skip-and-log) by an individual CRUD save — an
asymmetry the Reconciler's own docblock documents as deliberate.

---

## CURRENT SESSION CONTRACT

A successful login always establishes a valid authenticated session
(proven independently by every non-`/` flow: extensions, trunks, routes,
groups, queues, systemstatus, reports, settings — all reachable with
real, content-specific markers). The bare `/` route additionally
branches on legacy ITC registration state:

```text
$_SESSION['registered'] or ['noregister'] true  -> dashboard rendered directly
neither set (a genuinely fresh session)          -> ITC registration-gate
                                                     page (layout 'register',
                                                     exact sub-state
                                                     depends on a live,
                                                     non-deterministic
                                                     ITC ping)
```

Both are valid, current, supported outcomes of a successful login. Only
a response that is neither of these (an error, a redirect back to login,
a PHP fatal) indicates an actual authentication/session defect.

---

## FIXTURE REPAIR

**`scripts/legacy-maintenance-exposure-security-smoke-test.sh`** (check
10): replaced the hardcoded `FK_COUNT == 0` literal with a captured
before/after comparison, exactly mirroring how check 9 already treats
`core_peer_groups`:

```bash
FK_COUNT_BEFORE="$(db_query ...)"   # captured pre-probing, alongside PEER_GROUPS_BEFORE
...
FK_COUNT_AFTER="$(db_query ...)"    # captured post-probing
[ "$FK_COUNT_AFTER" = "$FK_COUNT_BEFORE" ]   # PASS/FAIL
```

Now schema-baseline-agnostic: correct today (2 FKs) and correct for any
future FK this schema legitimately grows, as long as this suite's own
read-only, HTTP-403-blocked probing does not change it.

**`scripts/pjsip-reconcile-smoke-test.sh`** (scenario 8): the
nonexistent-id fixture is replaced with a fully owned, real-HTTP-flow
fixture transport (name `task0033b-reconcile-fixture-transport`, port
`5099` — confirmed unused by any other `scripts/*.sh` transport
fixture):

```text
1. create_reconcile_transport_fixture()  -- POST pjsip-transports/add, enabled=1
2. UPDATE peers SET transport_id=<fixture id> WHERE name='1094'
3. reconcile() -> RECONCILED             (pin succeeds while transport is enabled)
4. reconcile_transport_set_enabled(0)    -- POST pjsip-transports/edit, disable it
   (this step's own PjsipTransportsController::editAction()->regenerateAll()
   already republishes senma-pjsip.conf, silently dropping 1094's row --
   the expected, separate, more lenient single-CRUD-save contract)
5. KNOWN_GOOD_SHA captured HERE (after step 4, not before)
6. reconcile() -> INVALID_DB_STATE       (full reconciliation refuses)
7. compare checksum -> byte-identical to KNOWN_GOOD_SHA
8. reconcile_transport_set_enabled(1)    -- re-enable -> reconcile() -> RECONCILED again
```

Step 5's placement is itself a finding, not just a mechanical fix: unlike
the retired raw-SQL fixture (which bypassed all application code), a
real HTTP transport-disable action goes through the transport's own
regeneration side effect first. The "files must stay byte-identical
across a refused full reconcile" assertion is unchanged in meaning — it
now correctly anchors to the state the system was already in immediately
before the full-reconcile attempt, rather than to a pre-disable state
that a real HTTP action was always going to change anyway.

Cleanup: the fixture transport is deleted (via the real HTTP `remove`
flow) immediately after its dependent extension (`1094`) is deleted in
scenario 10, respecting FK deletion order; a leftover-fixture check
(mirroring the existing extension/trunk checks) and a registered
best-effort safety-net cleanup were added for it.

**`scripts/smoke-test.sh`** (`dashboard`): replaced the single hardcoded
dashboard-marker assertion with one that accepts either the dashboard
marker or the ITC registration-gate page's own unconditional structural
marker (`id="registerLayout"`), and retired the separate "dashboard
(explicit route)" check — that check exercised
`IndexController::addAction()` (the unrelated "add a dashboard widget"
page, `/index.php/index/add`), which only ever coincidentally shared
layout markup with the real dashboard; it never actually tested dashboard
access, so keeping it under that name would have been misleading, not
protective.

Deliberately NOT used: POSTing the app's own `save=noregister` action to
force the dashboard open deterministically.
`Snep_Register_Manager::noregister()` persists `itc_register.noregister
= true` in the database — a permanent product setting, not a
session-scoped flag — and this task's constraints explicitly forbid
mutating production settings merely to dodge the test's own assertion.

---

## ASSERTION PRESERVATION

- **legacy-maintenance-exposure-security**: still proves the suite's own
  9 read-only, HTTP-403-blocked reachability/disclosure checks perform
  zero schema mutation. Arguably strengthened (schema-baseline-agnostic
  instead of a stale literal), not weakened.
- **pjsip-reconcile-smoke**: still proves, byte-for-byte, "invalid
  persisted DB state -> full reconcile refuses to publish -> the active,
  last-known-good generated config is left untouched -> fixing the
  invalid state lets reconcile succeed again." The invalid state itself
  changed from an unreachable one to a real, currently-supported one; the
  contract being exercised (`Reconciler::generateAll()`'s
  `INVALID_DB_STATE` path) is identical.
- **http-smoke**: still proves unauthenticated behavior is gated (no
  change), login succeeds (302, unchanged), the session cookie carries a
  genuinely authenticated session (proven by every subsequent flow using
  real, page-specific content markers, not just HTTP 200), and protected
  resources are reachable. Not weakened to a login-page-only check —
  every other flow (extensions/trunks/routes/groups/queues/systemstatus/
  reports/settings/logout) is untouched and still individually asserts
  its own specific content marker.

---

## TEST ISOLATION

Each of the three suites was run standalone twice consecutively
(PASS/PASS, no manual DB cleanup, stack reset, or session deletion
between runs — each suite owns its own fixture provisioning and
cleanup). The three were then run together in canonical regression
order (legacy-maintenance-exposure-security -> http-smoke ->
pjsip-reconcile-smoke) and in reverse order
(pjsip-reconcile-smoke -> http-smoke -> legacy-maintenance-exposure-security);
both orderings PASS end-to-end with no manual intervention between
suites, confirming no hidden state leakage. Fixture cleanup order
respects the dependent-row-before-parent rule: the fixture transport is
deleted only after its referencing extension has already been deleted.

---

## REGRESSION PROOF

```text
make lint        -> PASS
make regression  -> 37/37 PASS  (run 1)
make regression  -> 37/37 PASS  (run 2, no stack reset/DB repair between runs)
git diff --check -> clean
git status --short:
   M scripts/legacy-maintenance-exposure-security-smoke-test.sh
   M scripts/pjsip-reconcile-smoke-test.sh
   M scripts/smoke-test.sh
```

Only test/harness files changed. No production PHP, schema, or migration
file was touched by this task.

---

## REMAINING DEBT

1. **`IndexController::indexAction()`'s ITC ping is a live, synchronous
   dependency on every unregistered session's first page load**, and its
   result is not deterministic in this dev environment (observed:
   `Código404`, not a clean success/failure signal). Out of scope here
   (no production changes authorized for a test-repair task) —
   `FOLLOW_UP_DEBT` for a dedicated task if a real incident (slow/hanging
   ITC endpoint affecting a real admin's first login) ever justifies it.
2. **`Snep_Register_Manager::noregister()` has no session-scoped
   equivalent** — dismissing the ITC registration gate is only possible
   via a permanent DB write. Not fixed here; documented so a future task
   does not reach for it as a quick fix either.
3. TASK-0033F's own two pre-existing remaining-debt items are untouched
   by this task and still stand: the application-level `SCHEMA_AHEAD`/
   `SCHEMA_BEHIND` self-check is not wired into the PHP request bootstrap
   (visible only via `make doctor`/`make migrate-check`), and historical
   `update/3.01-3.07`/`update/betha` SQL remains unabsorbed into the new
   migration tracker.
