# TASK-0026Z-R1 — Final security gate re-evaluation

## Status

```text
SECURITY_GATE = GO
```

This is a **re-evaluation**, not a new audit. It reconciles
`docs/tasks/0026z-security-audit-closure.md` (the historical first closure
attempt, which correctly emitted `SECURITY_GATE = NO-GO`) against every
remediation/audit task completed since — TASK-0026J through TASK-0026S —
and confirms the gate now closes. `docs/tasks/0026z-security-audit-closure.md`
is left unmodified as the historical record of that first, correctly-NO-GO
attempt; this document is the current operative gate state.

`make lint` PASS, 5/5. Two consecutive full `make regression` runs both
PASS, 23/23 suites each, byte-identical result, no code changes between
them. Environment healthy. No file was modified by this task except this
document and a targeted currency update to `docs/SECURITY-BASELINE.md`
(§11 below) — this is a documentation/verification task, not a
remediation task, per its own scope boundary.

---

## 1. Executive summary

TASK-0026Z's own static sweep (Phase 9 of that document) found two
SQL-injection sinks — `Snep_InterfaceConf.php`'s legacy chan_sip/iax2
trunk lookup and `CallsReportController.php`'s report-filter query
construction — outside every finding TASK-0026A–I/F1 had already closed,
and correctly emitted `SECURITY_GATE = NO-GO` on that basis alone (every
other Phase 6 criterion in that document already read SATISFIED).

The chain that followed closed that gap and then kept finding (and
closing) further siblings of the same root cause, one static sweep at a
time, until an independent full-surface audit (TASK-0026Q) found none
left, and a subsequent post-remediation sweep (TASK-0026R) confirmed
zero:

```text
0026J -> Snep_InterfaceConf + CallsReportController (the original Z findings)
0026K -> RankingReportController / ServicesReportController
0026L -> PickupGroups / Queues Managers
0026M -> 9 further Manager-layer families (31 sites)
0026N -> PBX_Rule / PBX_Usuarios / PBX_Rules
0026O -> RouteController type filter / Snep_Binds_Manager
0026P -> Snep_ModuleSettings_Manager
0026Q -> full 336-file supported-surface audit -> Q-SQL-001..004 (NEEDS_MANUAL_REVIEW = 0)
0026R -> Q-SQL-001..004 remediated; post-fix sweep -> 0/0/0/0
0026S -> the one NON-SQL finding TASK-0026R's own sweep surfaced
          (unauthenticated web-reachable DB-mutating maintenance scripts)
          contained at the web-server layer
```

Every task in this chain re-verified the prior fixes intact before adding
its own (each document's own re-verification section confirms this) — a
strict, monotonically-closing chain with zero regressions. `focused
residual-sql-security-smoke-test.sh` grew from a new 17-check suite
(TASK-0026J) to 270 checks (TASK-0026R), covering every one of these
findings permanently, still 270/270 today.

This document's own Phase 3 re-confirms none of that work reopened any
original F1–F28 finding. Phase 9 classifies every remaining piece of
previously-deferred security-relevant debt; none rises to a pilot
blocker. Every Phase 10 GO criterion is satisfied.

```text
SECURITY_GATE = GO
```

---

## 2. Original TASK-0026Z NO-GO reasons — reconciliation

TASK-0026Z's Phase 6 table had exactly **one** unsatisfied criterion
("known SQL injection = 0 in supported surfaces"), driven by exactly two
named findings (its §5 "Newly discovered security debt" table). Both are
now closed:

```text
Blocker:            Snep_InterfaceConf.php raw SQL sink (legacy
                     chan_sip/iax2 trunk lookup, where("name =
                     {$peer['name']}")) -- requires trunk-write
                     permission + a chan_sip/iax2 trunk.
-> Follow-up task:   TASK-0026J
-> Current state:    CLOSED -- parameterized (quoteInto()/bound where()),
                     same pattern as every other fix in this program.
-> Regression proof: residual-sql-security-smoke-test.sh (TASK-0026J's
                     own new checks, still present and passing in the
                     270-check suite); re-verified live, still 403/clean
                     behavior in this task's own two regression runs
                     (§8 below).

Blocker:            CallsReportController::getselect()/getAnalytic() raw
                     SQL construction (main web UI Reports feature --
                     selectContactGroupSrc/Src/Dst, groupSrc/groupDst +
                     order_src/order_dst, duration_init/duration_end,
                     costs_center, all unparameterized).
-> Follow-up task:   TASK-0026J
-> Current state:    CLOSED -- parameterized, same pattern.
-> Regression proof: residual-sql-security-smoke-test.sh (TASK-0026J's
                     own new checks, still present and passing).

Every other TASK-0026Z Phase 6 criterion already read SATISFIED at that
task's own checkpoint and has not been touched by any later task in a way
that could regress it (J-S's own scope was exclusively SQL-injection
sinks, plus S's own narrow, unrelated web-exposure fix -- neither authz,
CSRF, session, password-hashing, RCE, or config-injection code was
modified by any task in this chain). No original TASK-0026Z blocker
remains open.
```

---

## 3. Post-Z security discoveries — reconciliation

Every security-relevant finding discovered by any task after the original
TASK-0026Z checkpoint, tracked to closure:

| Finding | Discovery task | Remediation task | Current state | Permanent regression proof |
|---|---|---|---|---|
| `Snep_InterfaceConf.php` legacy trunk lookup | 0026Z (§5) | 0026J | CLOSED | residual-sql-security-smoke, 270/270 |
| `CallsReportController.php` report-filter SQL | 0026Z (§5) | 0026J | CLOSED | residual-sql-security-smoke, 270/270 |
| `RankingReportController`/`ServicesReportController::getData()` | 0026J's own closing sweep | 0026K | CLOSED | residual-sql-security-smoke, 270/270 |
| `Snep_PickupGroups_Manager`/`Snep_Queues_Manager` (2 headline + 14 sibling sites) | 0026K's own closing sweep | 0026L | CLOSED | residual-sql-security-smoke, 270/270 |
| 9 further Manager-layer families (Contacts, ContactGroups, DatesAlias, ExpressionAlias, CostCenter, ExtensionsGroups, SoundFiles, Billing, Telcos — 31 sites) | 0026L's own closing sweep | 0026M | CLOSED | residual-sql-security-smoke, 270/270 |
| `PBX_Rule`/`PBX_Usuarios`/`PBX_Rules` (10 sites) | 0026M's own closing sweep | 0026N | CLOSED | residual-sql-security-smoke, 270/270 |
| `RouteController::indexAction()` type filter; `Snep_Binds_Manager` (3 sites) | 0026N's own closing sweep | 0026O | CLOSED | residual-sql-security-smoke, 270/270 |
| `Snep_ModuleSettings_Manager::getConfig()` + 2 siblings | 0026O's own closing sweep | 0026P | CLOSED | residual-sql-security-smoke, 270/270 |
| Q-SQL-001 — `Snep_Cnl` (CNL upload column parsing, 4 sites) | 0026Q (full audit) | 0026R | CLOSED | residual-sql-security-smoke, 270/270 |
| Q-SQL-002 — `Snep_Permission_Manager` (3 sites) | 0026Q | 0026R | CLOSED | residual-sql-security-smoke, 270/270 |
| Q-SQL-003 — `PBX_Trunks::get()` (2 direct entry points + 1 second-order) | 0026Q | 0026R | CLOSED | residual-sql-security-smoke, 270/270 |
| Q-SQL-004 — `estados.php`/`cidades.php` (blocked-then-real via removed `mysql_*`) | 0026Q | 0026R | CLOSED | residual-sql-security-smoke, 270/270 |
| Unauthenticated web-reachable DB-mutating maintenance scripts (`snep/install/database/update/{betha/convert-data-rc3.php,3.01/updateCallerid.php}`) | 0026R's own post-remediation sweep (non-SQL, disclosed prominently) | 0026S | CLOSED | legacy-maintenance-exposure-security-smoke, 16/16 |

Every one of the eleven residual-SQL rows above maps 1:1 onto
TASK-0026Q's own pre-remediation tally (4 direct exploitable + 1
second-order + 1 vulnerable-but-unreachable = 6 total distinct sink
groups it inventoried as Q-SQL-001..004, after J–P had already closed the
other seven families listed above) and TASK-0026R's own post-remediation
tally (`EXPLOITABLE_DIRECT=0, EXPLOITABLE_SECOND_ORDER=0,
VULNERABLE_BUT_CURRENTLY_UNREACHABLE=0, NEEDS_MANUAL_REVIEW=0`). No
post-Z security discovery is missing from this table, and none remains
open.

---

## 4. F1–F28 non-regression confirmation

TASK-0026Z's own F1–F28 reconciliation table (its §3) was independently
re-checked against the original `docs/tasks/0026-pre-pilot-security-release-audit.md`
this task's own Phase 3 required — spot-checking finding IDs, names, and
severities for every group (F1, F6, F7–F11, F12–F15, F16, F17, F18–F20,
F21–F24, F25, F26, F27, F28): every one matches Z's table exactly, no
discrepancy.

None of TASK-0026J through TASK-0026S touched any file that any F1–F28
finding's own remediation task modified (J–P/Q/R's scope was exclusively
newly-discovered residual SQL sinks in files never part of the original
28; S's scope was exclusively `snep/install/.htaccess` and its own test
infrastructure). Every focused suite covering F1–F28 (`preauth-security`,
`sql-security`, `shell-security`, `pjsip-config-security`, `api-security`,
`session-csrf-security`, `auth-hardening-security`,
`disclosure-path-security`, `authorization-coverage`,
`authorization-smoke`) passed in both of this task's own two official
regression runs (§8).

```text
F1-F28 reopened = 0
```

---

## 5. SQL security closure evidence

```text
TASK-0026Q NEEDS_MANUAL_REVIEW              = 0   (0026Q §1/§16, re-confirmed this task)
Q-SQL findings open                          = 0   (all 4 closed by 0026R)
EXPLOITABLE_DIRECT (SQL)                     = 0   (0026R §9 post-remediation sweep)
EXPLOITABLE_SECOND_ORDER (SQL)               = 0   (0026R §9)
VULNERABLE_BUT_CURRENTLY_UNREACHABLE (SQL)   = 0   (0026R §9)
RESIDUAL_SQL_GATE                            = CLOSED (0026R §13, re-confirmed by
                                                        residual-sql-security-smoke
                                                        270/270 in both of this
                                                        task's own regression runs)
```

No new exploratory SQL audit was launched, per this task's own governing
instruction — current regression evidence (both official runs, §8) does
not contradict TASK-0026Q/R's completed closure.

---

## 6. Maintenance-exposure closure evidence

```text
UNAUTHENTICATED_WEB_REACHABLE_DB_MUTATING_SCRIPTS = 0
```

Re-verified live, non-destructively, this task:

```text
GET /install/database/update/betha/convert-data-rc3.php  -> HTTP 403
GET /install/database/update/3.01/updateCallerid.php     -> HTTP 403
GET /                                                      -> HTTP 200 (ordinary route unaffected)
```

No PHP migration code and no destructive SQL was executed by this
verification — both blocked requests are rejected by Apache's own
access-control phase (`snep/install/.htaccess`, `Require all denied`)
before mod_php ever runs, exactly as designed in TASK-0026S. The focused
`legacy-maintenance-exposure-security-smoke-test.sh` suite (16 checks)
additionally passed in both of this task's own two official regression
runs (§8), re-confirming whole-tree containment, no schema/data
mutation, no disclosure, and filesystem/CLI availability preserved.

---

## 7. Security-suite results

Every suite the task instructions named by role, mapped to its actual
current name in this repository, all PASS in both official regression
runs (§8):

| Named role | Actual suite | Result |
|---|---|---|
| preauth security | `preauth-security` | PASS |
| SQL security | `sql-security` | PASS |
| residual SQL security | `residual-sql-security` | PASS |
| shell security | `shell-security` | PASS |
| PJSIP/config security | `pjsip-config-security` | PASS |
| standalone API security | `api-security` | PASS |
| API SQL security | `api-sql-security` | PASS |
| session/CSRF security | `session-csrf-security` | PASS |
| authentication hardening | `auth-hardening-security` | PASS |
| disclosure/path security | `disclosure-path-security` | PASS |
| maintenance exposure security | `legacy-maintenance-exposure-security` | PASS |
| authorization coverage | `authorization-coverage` | PASS |

(Plus every non-security-named suite in the canonical 23: `lint`,
`harness-lib-selftest`, `authorization-smoke`, `http-smoke`,
`cdr-window-selftest`, `call-smoke`, `trunk-smoke`, `transport-smoke`,
`restart-smoke`, `external-failure-smoke`, `external-content-smoke` — all
PASS, both runs.)

---

## 8. Canonical validation

```bash
make lint          # PASS, 5/5
make regression    # run 1
make regression    # run 2, no code changes, no manual cleanup in between
```

- `make lint`: **PASS, 5/5** (271 PHP files, 0 syntax errors; 25 shell
  scripts; 3 `resources.xml` files well-formed; clean `git diff --check`).
- `make regression`, run 1: **PASS — 23/23 suites.**
- `make regression`, run 2 (immediately after, no code changes, no manual
  cleanup): **PASS — 23/23 suites, byte-identical result to run 1.**

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

No FAIL, no BLOCKED, no INCONCLUSIVE, in either official run. No transient
was observed in either official run (a prior, unofficial ad hoc
invocation during TASK-0026S's own validation had hit a since-explained,
non-product-defect shell-invocation mistake and a separate transient
inter-suite PJSIP-timing flake — both already fully disclosed in
`docs/tasks/0026s-legacy-maintenance-web-exposure-hardening.md` §8, not
this task's own finding, and both were resolved by re-running correctly
before that task's own checkpoint. Neither recurred in this task's two
official runs.).

---

## 9. Health proof

Checked after the second official regression run:

- `docker compose ps`: `app`/`asterisk`/`db`/`provider` all `Up
  (healthy)`.
- Asterisk **22.11.0** — matches the repository's pinned version
  (`docker/asterisk.Dockerfile`, unchanged).
- `res_pjsip.so` — 1 module, **Running**.
- `pjsip show transports`: 3 baseline transports intact (`tcp`, `udp`,
  `wss`).
- AMI: `manager show connected` responsive, 0 connected users.
- ODBC: `snep` DSN, 1/1 active connection.
- `core show channels count`: 0 active channels, 0 active calls.
- `core_peer_groups` = 0 rows; `peers` foreign-key count = 0 — unchanged
  from the TASK-0026R/S baseline, re-verified directly against the live
  database (the exact object involved in both prior tasks' own
  accidental/probed triggers).
- No new security-related PHP Fatal Error signature: the fatal-error
  count observed after this task's own two regression runs is consistent
  with the same pre-existing, already-documented signatures every prior
  TASK-0026x health check has recorded (CnlController/
  `Zend_Validate_File_Upload` PHP 8.4 `TypeError`, `updateCallerid.php`'s
  pre-existing `mysql_connect()` bug, and each suite's own intentional,
  signature-verified proof fatals) — each suite's own before/after delta
  check (part of its own PASS) already confirms no *new* unexplained
  fatal was introduced.
- No leftover smoke-test/baresip processes or containers, host or
  container side. The only non-SENMA containers present on this host
  (`evo-crm-community-*`, `qflow-*`) belong to unrelated projects, not
  touched.
- No migration/test fixtures or residue left by this task (this task
  changed no application code and created no test fixtures of its own).

---

## 10. Remaining known security-relevant debt

Every explicitly deferred security-relevant item carried across the
TASK-0026 program, classified:

| Item | Status |
|---|---|
| `Snep_InterfaceConf.php` / `CallsReportController.php` residual SQL (original Z findings) | CLOSED (0026J) |
| Every subsequent residual-SQL family (0026K–R's own findings, Q-SQL-001–004) | CLOSED (0026K–R) |
| Unauthenticated web-reachable DB-mutating maintenance scripts (0026R's own disclosed finding) | CLOSED (0026S) |
| Per-controller `getMessage()`→`sneperror.phtml` disclosure (`DatesAliasController`, `ExpressionAliasController`, `SimulatorController`, `ExtensionsController`) | PRODUCT_READINESS_SECURITY_DEBT — narrower pattern than F25's audited global handler; no exploitable disclosure demonstrated, not reachable-and-mutating; unchanged since 0026Z |
| Potential stored XSS via unescaped log content (`logs/view.phtml`'s `echo trim($buffer)`) | PRODUCT_READINESS_SECURITY_DEBT — flagged 0026D, reachability never confirmed; unchanged since 0026Z |
| Reachable `chan_sip`/`iax2` legacy technology selection (architecture question, independent of the SQL sink already closed at that boundary) | PRODUCT_READINESS_SECURITY_DEBT — unchanged since 0026Z; the SQL-injection instance at this exact boundary (`Snep_InterfaceConf.php`) is CLOSED (§2), the broader "should this remain selectable" question is a Product Readiness architecture decision, not a security defect |
| Standalone API has no rate limiting / no per-service authorization tier | PRODUCT_READINESS_SECURITY_DEBT — explicitly out of scope for every task that touched that file, unchanged since 0026Z |
| Full HTTP security-header rollout (CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, HSTS) beyond `expose_php=Off` | PRODUCT_READINESS_SECURITY_DEBT — explicitly out of the original audit's own scope, unchanged since 0026Z |
| `snep/agi/*.php` web-reachable (no `.htaccess`, same `AllowOverride All` document root as the now-closed `snep/install/` finding) but non-productive — a plain HTTP request hangs on `Asterisk_AGI`'s constructor blocking on a stdin protocol-handshake read that never arrives (confirmed live by TASK-0026Q, a distinct subtree from TASK-0026S's own fix, never remediated) | PRODUCT_READINESS_SECURITY_DEBT — a defense-in-depth hardening opportunity TASK-0026Q itself recommended (Apache-level deny for `/agi/`, matching TASK-0026S's own pattern), not a confirmed exploitable defect: no SQL injection reaches it (0026Q's own audit), and it does not execute meaningful mutating logic synchronously in response to a plain HTTP request the way `convert-data-rc3.php` did (it blocks, it does not run) — different risk shape from the finding TASK-0026S closed. Candidate for a small, dedicated future task using the same `.htaccess` pattern. |
| Various non-security functional bugs (PR-01–15 and the "additional items" list in `docs/tasks/0026z-security-audit-closure.md` §12) | PRODUCT_READINESS_SECURITY_DEBT or NOT_SECURITY_BLOCKING, per that document's own classification — unchanged, not re-litigated by this task |

**Zero items above are classified `PILOT_SECURITY_BLOCKER`.** Per this
task's own governing instruction, the existence of generic hardening
opportunities does not itself block GO — none of the items above
describes a *known, currently exploitable* security defect on a
supported/reachable surface.

---

## 11. GO criteria — final evaluation

```text
Original P0 OPEN                                        = 0        SATISFIED (§4)
Original P1 security OPEN (unless explicitly accepted)   = 0        SATISFIED (§4)
Known unauthenticated RCE                                = 0        SATISFIED (unchanged since 0026Z)
Known SQL injection on supported/reachable surfaces      = 0        SATISFIED (§5)
Known shell injection                                    = 0        SATISFIED (unchanged since 0026Z)
Known config injection                                   = 0        SATISFIED (unchanged since 0026Z)
Known authorization bypass                               = 0        SATISFIED (unchanged since 0026Z)
Known pass-the-hash                                       = 0        SATISFIED (unchanged since 0026Z)
Known supported-browser CSRF                             = 0        SATISFIED (unchanged since 0026Z)
Known universal default credential                       = 0        SATISFIED (unchanged since 0026Z)
Known path traversal                                     = 0        SATISFIED (unchanged since 0026Z)
Known unauthenticated DB-mutating maintenance endpoint    = 0        SATISFIED (§6)
All security regression suites                            = PASS     SATISFIED (§7/§8)
Canonical regression, twice consecutively                = PASS     SATISFIED (§8)
```

Every criterion satisfied.

```text
SECURITY_GATE = GO
```

---

## 12. Product Readiness boundary

> TASK-0026 security remediation is formally closed. The project may
> proceed to Product Readiness.

This does **not** mean: release ready; pilot ready overall; PJSIP-only
migration complete; UI complete; translations complete; operations
complete. Those remain separate, later milestones. The Product Readiness
debt table in `docs/tasks/0026z-security-audit-closure.md` §12, plus this
document's own §10, is the current combined handoff list for that
follow-on work — none of it is started by this task.

---

## 13. Files changed by this task

- `docs/tasks/0026z-r1-final-security-gate-re-evaluation.md` (new, this
  file)
- `docs/SECURITY-BASELINE.md` (currency update only — the "Security gate
  expectations" and "Deferred Product Readiness security debt" sections
  referenced the now-superseded TASK-0026Z NO-GO state; updated to point
  at this document's GO state and to remove the two now-closed SQL sinks
  and the now-closed maintenance-exposure item from the "still open"
  list, replacing them with the §10 debt table above). No historical
  document was rewritten — `docs/tasks/0026z-security-audit-closure.md`
  and every TASK-0026A–S document remain exactly as they were.

No application/product/test-harness code was modified. `.nexus/` remains
untouched. Product Readiness work was not started.
