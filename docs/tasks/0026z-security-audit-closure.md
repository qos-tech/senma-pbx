# TASK-0026Z — Security audit closure

## Status

Closure/audit reconciliation complete. `make lint` PASS; two consecutive
full `make regression` runs PASS, 21/21 suites each, byte-identical
result. Environment health confirmed. Focused static sweep complete.

**This task's own static sweep discovered two new, currently-unpatched
SQL-injection sinks outside any prior TASK-0026 finding's scope.**
Per this task's own governing instructions, no code was changed to fix
them — they are documented here and handed off as a required follow-up
task. No previously-resolved F1–F28 finding was reopened.

```text
SECURITY_GATE = NO-GO
```

This does **not** mean the TASK-0026A–I/F1 remediation program failed —
every one of the 28 originally catalogued findings is resolved, verified,
and regression-covered. It means the pilot-blocker criterion "known SQL
injection = 0 in supported surfaces" (§6) is not currently met, because
of two sinks discovered during this closure task's own mandated static
sweep, never covered by TASK-0026C's or TASK-0026F1's scope.

---

## 1. Executive summary

TASK-0026's original audit (`docs/tasks/0026-pre-pilot-security-release-audit.md`)
catalogued 28 findings (F1–F28) across 11 root causes and set
**PILOT SECURITY STATUS: BLOCKED**. The subsequent remediation chain
(TASK-0026A through TASK-0026I, plus TASK-0026F1, TASK-0027, TASK-0027A)
closed every one of those 28 findings, each with a dedicated focused
regression suite and two consecutive full `make regression` passes at
its own checkpoint.

This task (TASK-0026Z) re-verified that chain against the current
repository, finding-by-finding, and additionally performed the static
sweep TASK-0026Z's own instructions require (Phase 9: "raw request → SQL
string", among other classes). That sweep — targeted verification of
items multiple prior tasks had already flagged as deferred debt, not a
fresh, unbounded audit — found two SQL-injection sinks that were never
in scope for any 0026A–I/F1 task:

1. **`Snep_InterfaceConf.php`'s legacy chan_sip/iax2 trunk lookup**
   (`where("name = {$peer['name']}")`, raw interpolation) — flagged as
   deferred debt in TASK-0026E's own document, never remediated by any
   later task. Requires trunk-write permission and a chan_sip/iax2 trunk
   (still selectable technology).
2. **`CallsReportController::getselect()`/`getAnalytic()`** (the main web
   UI's Calls Report feature, `snep/modules/default/controllers/CallsReportController.php`)
   — multiple raw, `$_REQUEST`-derived values concatenated directly into
   `$db->query($select)`. This is the same vulnerability class TASK-0026F1
   fixed in the API's `CallsReportService.php`, but that task's scope was
   explicitly limited to `snep/modules/default/api/actions/`; this MVC
   twin was never in the original F1–F28 audit and never touched by any
   remediation task. Reachable by any account with the common
   `calls-report_read` permission.

Both are confirmed by direct code tracing (not live exploitation, per
this task's own "do not implement new product/security features"
constraint), consistent with how several original F1–F28 findings were
confirmed. Neither is covered by any of the 21 suites in
`make regression` — the aggregate regression staying green does not
certify these surfaces.

Every other pilot-blocker criterion in §6 is satisfied. `make lint` and
two consecutive `make regression` runs both PASS cleanly, 21/21 suites,
with clean environment health and zero residue.

---

## 2. Original audit status

`docs/tasks/0026-pre-pilot-security-release-audit.md` remains the
immutable historical record — unmodified by this task. Its own verdict:
28 findings, 16 originally P0, **PILOT SECURITY STATUS: BLOCKED**, with
an explicit recommended remediation order (§13 of that document).

---

## 3. F1–F28 reconciliation table

| Finding | Original severity/class | Remediation task | Final status |
|---|---|---|---|
| F1 — unauthenticated RCE, language selector | CRITICAL / P0 | 0026B | RESOLVED |
| F2 — authenticated RCE, Sound Files upload | CRITICAL / P0 | 0026D | RESOLVED |
| F3 — authenticated RCE, Music on Hold, any logged-in user | CRITICAL / P0 | 0026D (shell) + 0026A (authz) | RESOLVED |
| F4 — authenticated RCE, System Logs | CRITICAL / P0 | 0026D | RESOLVED |
| F5 — CNL update RCE, reachability unconfirmed | HIGH / P1-pending | 0026D | RESOLVED (reclassified reachable, see §4) |
| F6 — unauthenticated SQLi, login form | CRITICAL / P0 | 0026B | RESOLVED |
| F7 — SQLi, Extensions | CRITICAL / P0 | 0026C | RESOLVED |
| F8 — SQLi, Users/Profiles, mass privesc | CRITICAL / P0 | 0026C | RESOLVED |
| F9 — SQLi, Trunks (second-order via edit-page read-back) | HIGH / P0 | 0026C | RESOLVED |
| F10 — SQLi, CSV import, reachability unconfirmed | HIGH / P1-pending | 0026C | RESOLVED (reclassified unreachable, fixed anyway; see §4) |
| F11 — SQLi + authz bypass, Data Export, any authenticated user | CRITICAL / P0 | 0026C (SQL) + 0026A (authz) | RESOLVED |
| F12 — PJSIP config injection, Extensions | CRITICAL / P0 | 0026E | RESOLVED |
| F13 — PJSIP config injection, Trunks | CRITICAL / P0 | 0026E | RESOLVED (section-header claim reclassified, see §4) |
| F14 — PJSIP config injection, Transports | CRITICAL / P0 | 0026E (no code change) | RESOLVED_BY_PRIOR_WORK — already mitigated by TASK-0019/0020 |
| F15 — config injection, legacy chan_sip/iax2 | CRITICAL / P1-conditional | 0026E | RESOLVED (reclassified reachable, see §4) |
| F16 — authorization action-name allowlist gap | CRITICAL / P0 | 0026A | RESOLVED |
| F17 — standalone API pass-the-hash + LFI | CRITICAL / P0 | 0026F | RESOLVED |
| F18 — session fixation | HIGH / P1 | 0026G | RESOLVED |
| F19 — cookie flags (HttpOnly/Secure/SameSite) | MEDIUM / P1 | 0026G | RESOLVED |
| F20 — no CSRF protection | HIGH / P1 | 0026G | RESOLVED |
| F21 — unsalted MD5 password hashing | MEDIUM-HIGH / P1 | 0026H | RESOLVED |
| F22 — no login rate limiting | MEDIUM / P1 | 0026H | RESOLVED |
| F23 — weak PRNG, password-reset code | LOW / P2 | 0026H | RESOLVED |
| F24 — AuthPlugin action-name-only bypass fragility | LOW / P2 | 0026H | RESOLVED |
| F25 — unconditional exception-message disclosure | MEDIUM / P1 | 0026I | RESOLVED |
| F26 — X-Powered-By / missing headers | INFO-LOW / P2 | 0026I | RESOLVED (`expose_php=Off`; full header rollout explicitly out of original audit's own scope, tracked as non-blocking PR debt) |
| F27 — default admin/admin123 credential | CRITICAL (deploy) / P0+P1 | 0026H | RESOLVED |
| F28 — path traversal, Docs viewer (contained to `.md`) | MEDIUM / P1 | 0026I | RESOLVED |

**Tally**: RESOLVED = 27, RESOLVED_BY_PRIOR_WORK = 1 (F14). Zero OPEN.
Zero NOT_APPLICABLE_CURRENT_RUNTIME. Four of the RESOLVED findings (F5,
F10, F13, F15) also carry a reclassification during remediation — see §4
for the original-assumption → new-evidence → final-classification
reasoning on each. No original finding is missing from this table.

---

## 4. Reclassifications

**F5 — CNL update RCE.** Original audit: "not linked from the current
UI... not live-verified either way," classified P1-pending-reachability.
TASK-0026D's re-trace found `resources.xml` registers a `cnl` resource
with a live sidebar entry and a 200 OK render for an authenticated user.
→ **Reclassified CONFIRMED REACHABLE**, fixed as such (REMOVE_SHELL via
`ZipArchive`).

**F10 — CSV import SQLi.** Original audit: reachability via
`Snep_CsvIE::import()` not confirmed. TASK-0026C's re-trace
(`grep -rln "new Snep_CsvIE"`) confirmed zero call sites to `->import()`
anywhere in the current tree — the only instantiation
(`ExportDataController.php`) only ever calls the separate, already-safe
`exportResult()`. → **Reclassified CONFIRMED UNREACHABLE via any current
HTTP path**, but fixed anyway per this task's own explicit scope
(the vulnerable pattern and code are real, even if currently dormant).

**F13 — PJSIP Trunk config injection, section-header claim.** Original
audit text: "name/auth/registration/identify are also used as unguarded
[section] headers." TASK-0026E's re-trace of the current
`Snep_PjsipTrunkConf::renderTrunk()` found every section name is built as
`"trunk-" . $trunk['id']` — the auto-increment primary key, never
user-controlled — a TASK-0014 design predating this claim or simply not
re-traced against the current architecture. → **Reclassified: the
section-header half of F13 does not hold for the current PJSIP
generator.** The value-position half (context/callerid/fromuser/
fromdomain/host/secret) remained fully exploitable and was fixed. This
does not rewrite the original finding — only documents which half
matches current code.

**F15 — legacy chan_sip/iax2 config injection.** Original audit: "P1 if
the pilot is confirmed PJSIP-only... reclassify P0 if any chan_sip
extension/trunk is planned." TASK-0026E's re-trace found
`technology=sip`/`iax2` remain fully selectable on both Extensions and
Trunks forms, with `Snep_InterfaceConf::loadConfFromDb()` called from
live, non-dead-code call sites in both controllers. → **Reclassified
REACHABLE**, fixed rather than deferred.

Reclassification is not resolution by itself in any of these four cases
— each was reclassified **and then independently fixed and regression-
covered**, as recorded in §3.

---

## 5. Newly discovered security debt (outside F1–F28 numbering)

| Item | Discovered by | Status | Classification |
|---|---|---|---|
| Standalone API SQL sinks (`ContactsService`, `CSV_ExportDataService`, `CallsReportService`, `RankingReportService`, `ServicesReportService`) | 0026F | Fixed by 0026F1 | RESOLVED |
| Raw `select`/`selectcont`/`selectcount` SQL text echoed in `CallsReportService`/`ServicesReportService` JSON | 0026F1 (deferred) | Fixed by 0026I | RESOLVED |
| **`Snep_InterfaceConf.php` raw SQL sink** (`where("name = {$peer['name']}")`, legacy chan_sip/iax2 trunk lookup; `name` excluded from `TrunksController::validateConfigFields()`, remains mass-assignable) | 0026E (deferred, never revisited) | **Still open** — confirmed by this task's direct code read | **REQUIRES_DEDICATED_SECURITY_TASK — pilot-blocking** |
| **`CallsReportController::getselect()`/`getAnalytic()` raw SQL construction** (main web UI Reports feature; `selectContactGroupSrc/Src/Dst`, `groupSrc`/`groupDst`+`order_src`/`order_dst`, `duration_init`/`duration_end`, `costs_center` all unparameterized) | **This task's own Phase 9 static sweep** — never previously documented anywhere in the 0026 program | **Still open** — confirmed by this task's direct code read | **REQUIRES_DEDICATED_SECURITY_TASK — pilot-blocking** |
| Per-controller `getMessage()`→`sneperror.phtml` disclosure (`DatesAliasController`, `ExpressionAliasController`, `SimulatorController`, `ExtensionsController`) | 0026I (deferred) | Still open | PRODUCT_READINESS_SECURITY_DEBT — narrower disclosure pattern than F25's audited global-handler boundary; not a pilot-blocker on its own |
| Nine dead `<controller>/error.phtml` view scripts | 0026I (deferred) | Still present, confirmed unreachable | NOT_SECURITY_BLOCKING — dead code, candidate for a future cleanup task |
| Potential stored XSS via unescaped log content (`logs/view.phtml`, `echo trim($buffer)`) | 0026D (flagged, "not evaluated further") | Reachability unconfirmed | REQUIRES_DEDICATED_SECURITY_TASK to confirm/close — not a currently-confirmed instance, and XSS is not itself one of §6's explicit gate criteria, so this does not independently drive NO-GO, but should not be left open indefinitely |
| `Snep_CsvIE::export()` dead code (same identifier-injection shape as F11) | 0026C (deferred) | Confirmed unreachable (zero call sites; would fatal on undefined properties if ever wired up) | NOT_SECURITY_BLOCKING |
| `Snep_Services::getPathService()` dead code | 0026F (deferred) | Still present, zero call sites | NOT_SECURITY_BLOCKING |
| `CallsReportService.php`'s dead `cost_center` `else` branch (API version only) | 0026F1 (deferred) | Confirmed unreachable (`count(explode())` always > 0) | NOT_SECURITY_BLOCKING |

No item above is silently dropped for being outside the original F1–F28
numbering. The two REQUIRES_DEDICATED_SECURITY_TASK / pilot-blocking
items are the sole drivers of §11's NO-GO decision.

---

## 6. Pilot-blocker criteria — evaluated

```text
P0 original findings OPEN = 0                          SATISFIED (§3)
P1 security findings OPEN = 0 unless explicitly accepted SATISFIED (§3)
known unauthenticated RCE = 0                           SATISFIED
known SQL injection = 0 in supported surfaces           NOT SATISFIED — §5, two open sinks
known shell injection = 0 in supported surfaces         SATISFIED
known config injection = 0 in supported surfaces        SATISFIED
known auth bypass = 0                                   SATISFIED
known pass-the-hash = 0                                 SATISFIED
known CSRF on supported browser mutations = 0           SATISFIED
known universal default credential = 0                  SATISFIED
known path traversal on supported surfaces = 0          SATISFIED
canonical security regression = PASS                    SATISFIED (§7)
```

One criterion fails. Per this document's own governing instructions,
that alone is sufficient for §11's NO-GO.

---

## 7. Full current regression proof

```bash
make lint
make regression   # run 1
make regression   # run 2, no code changes, no manual cleanup in between
```

- `make lint`: **PASS** — 5/5 checks (containers healthy; `php -l` across
  271 project PHP files, 0 syntax errors; `bash -n` across 23 shell
  scripts; XML well-formedness, 3 `resources.xml` files; `git diff
  --check` clean).
- `make regression`, run 1: **PASS — 21/21 suites.**
- `make regression`, run 2 (immediately after, no code changes, no
  manual cleanup): **PASS — 21/21 suites, byte-identical result to run 1.**

```text
SUITE                          RESULT
----------------------------------------------------------------
lint                           PASS
harness-lib-selftest           PASS
preauth-security               PASS
sql-security                   PASS
shell-security                 PASS
pjsip-config-security          PASS
api-security                   PASS
api-sql-security               PASS
session-csrf-security          PASS
auth-hardening-security        PASS
disclosure-path-security       PASS
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

No FAIL, no BLOCKED, no INCONCLUSIVE, in either run. No product code was
modified between the two runs, and no manual cleanup was performed.

**Classification of this result**: this is a clean regression-harness
result, not proof the application has no SQL injection anywhere — the
harness does not exercise `CallsReportController.php`'s report filters
or `Snep_InterfaceConf.php`'s chan_sip trunk lookup (§5). "21/21 PASS"
and "SECURITY_GATE = NO-GO" are both true and not in tension.

---

## 8. Health proof

Checked after the second aggregate regression run:

- `docker compose ps`: `app`, `asterisk`, `db`, `provider` all `Up (healthy)`.
- Asterisk 22.10.1; `res_pjsip.so` — 1 module loaded, **Running**.
- `pjsip show transports`: 3 baseline transports intact (`tcp`, `udp`,
  `wss`) on their expected bind addresses.
- AMI: `manager show connected` responsive, 0 stale connections.
- ODBC: `snep` DSN, 1/1 active connection.
- `core show channels count`: 0 active channels, 0 active calls.
- PHP Fatal Error count: exactly 1 in `mag-error.log`, and it is the
  same pre-existing, already-documented (TASK-0026D/E/F/F1/G/H/I)
  `CnlController` / `Zend_Validate_File_Upload::isValid()` PHP 8.4
  `TypeError`, triggered by `shell-security-smoke-test.sh`'s own
  F5-reachability check. Not attributable to any TASK-0026Z work (none
  was performed) and not a new regression.
- Fixture residue: zero stray `peers` rows for any known smoke
  extension; `trunks` table empty; `pjsip_transports` exactly the 3
  baseline rows. `users` contains only `admin` plus the documented,
  intentional persistent dev fixtures established across
  TASK-0026A/C/D/E/F/F1/G (`task0026a-restricted`,
  `task0026c-restricted`, `task0026d-restricted`, `task0026e-restricted`,
  `task0026f-restricted`, `task0026f1-restricted`, `task0026g-foreign`,
  `task0026g-target`) — not residue.
- No leftover baresip or smoke-test processes/containers, host or
  container side.

---

## 9. Static security sweep

Focused search (not a full re-audit) for the classes TASK-0026 was built
to close, prioritizing items already flagged as deferred debt across the
0026A–I/F1 documents plus a general sweep of `->query(` / raw `SELECT`
concatenation outside the already-hardened controllers:

| Class | Result |
|---|---|
| raw request → exec/system/shell | None found outside already-classified `SAFE_STATIC`/`DEFER` items (TASK-0026D §1/§10) |
| raw request → SQL string | **Two open instances — §5**: `Snep_InterfaceConf.php` (chan_sip/iax2 trunk lookup), `CallsReportController.php` (Reports filter query). Every other sink found (`CallsReportController.php`'s/`CallsReportService.php`'s static `SELECT phone FROM contacts_names ...` fragments) traced to `Snep_ExtensionsGroups_Manager::getExtensionsGroup()`, already parameterized, or to fixed string literals — classified STATIC_SAFE, no user data reaches them unparameterized |
| raw request → config syntax | None found outside the already-remediated F12–F15 boundary (TASK-0026E §9, re-confirmed: no unexplained `$value . "\n"` / `"[" . $value . "]"` construction remains) |
| raw request → require/include path | None found outside the already-remediated F17-B boundary (TASK-0026F §6) |
| state-changing GET | None found outside the already-remediated set (TASK-0026G §7 closure statement — every supported GET route classifies READ_ONLY / RENDER_CONFIRMATION / REDIRECT_WITHOUT_MUTATION) |
| MD5 production password write | None — every write path uses `Snep_Security_Password::hash()` (TASK-0026H §2) |
| `admin123` active credential | None — install seed ships the non-authenticating sentinel; bootstrap generates a random credential (TASK-0026H §10) |
| exception detail → production response | None found outside the already-remediated F25/per-controller-`getMessage()` set (TASK-0026I §9; the per-controller sinks are tracked as PRODUCT_READINESS_SECURITY_DEBT in §5, not a new unexplained instance — narrower and already documented) |
| request path → file access | None found outside the already-remediated F28 boundary (TASK-0026I §4, allowlist + `realpath()` containment, symlink-tested) |

**Conclusion**: every vulnerability class TASK-0026 targeted is closed
in every code path any 0026A–I/F1 task actually traced — except the two
SQL-injection sinks in §5, which sit in code no prior task's scope ever
covered (a legacy-generator sibling sink adjacent to F13/F15, and an
MVC-controller sibling of the already-fixed `CallsReportService.php`
API action).

---

## 10. Security regression inventory (canonical baseline)

| Suite | Purpose | Checks | Latest result |
|---|---|---|---|
| `lint` | `php -l`, `bash -n`, XML well-formedness, `git diff --check` | 5 | PASS |
| `harness-lib-selftest` | Shared PASS/FAIL/BLOCKED/INCONCLUSIVE state machine, bash 3.2 safety | 7 | PASS |
| `preauth-security` | F1/F6 — pre-auth language allowlist, login-form SQL boundary | 10 | PASS |
| `sql-security` | F7–F11 — Extensions/Users/Profiles/Trunks/CSV/Export SQL boundary | 25 | PASS |
| `shell-security` | F2–F5 — Sound Files/Music on Hold/Logs/CNL shell boundary | 28 | PASS |
| `pjsip-config-security` | F12–F15 — PJSIP/chan_sip config-injection boundary | 27 | PASS |
| `api-security` | F17 — standalone API auth normalization + service dispatch | 22 | PASS |
| `api-sql-security` | Standalone API SQL boundary (§5, resolved item) | 34 | PASS |
| `session-csrf-security` | F18–F20 — session fixation, cookie policy, CSRF | 40 | PASS |
| `auth-hardening-security` | F21–F24/F27 — password hashing, rate limiting, default credential | 32 | PASS |
| `disclosure-path-security` | F25/F26/F28 — exception disclosure, headers, docs path traversal | 21 | PASS |
| `authorization-coverage` | F16 — static controller/action inventory, default-deny gate | full inventory | PASS |
| `authorization-smoke` | F16 — live default-deny + grant/revoke lifecycle | 17 | PASS |
| `http-smoke` | Product smoke — login/dashboard/extensions/trunks/routes/groups/queues/reports/settings/logout | 16 | PASS |
| `cdr-window-selftest` | Timezone-safe CDR report-window logic (deterministic, no wall-clock dependency) | 6 | PASS |
| `call-smoke` | End-to-end call flow + reporting readback | 18 | PASS |
| `trunk-smoke` | Trunk provisioning + inbound/outbound routing + reporting readback | 23 | PASS |
| `transport-smoke` | PJSIP transport lifecycle | 63 | PASS |
| `restart-smoke` | Asterisk restart resilience, incl. mid-call | 37 | PASS |
| `external-failure-smoke` | Vendor-availability failure isolation (TASK-0024) | 27 | PASS |
| `external-content-smoke` | Vendor-content XSS containment (TASK-0025) | 14 | PASS |

**21 suites, all PASS**, twice consecutively. This is the baseline gate
for future release candidates. It does **not** cover
`CallsReportController.php`'s report-filter query construction or
`Snep_InterfaceConf.php`'s chan_sip/iax2 trunk lookup (§5) — the
follow-up task proposed in §11 should add focused coverage for both,
matching the `sql-security`/`api-sql-security` pattern.

---

## 11. Security status decision

```text
SECURITY_GATE = NO-GO
```

**Reasoning**: every P0/P1 finding from the original TASK-0026 audit
(F1–F28) is resolved, reclassified-and-resolved, or resolved by prior
work, with dedicated regression coverage and two consecutive clean
`make regression` runs. However, this task's own mandated static sweep
(§9) found two SQL-injection sinks — `Snep_InterfaceConf.php`'s legacy
trunk lookup and `CallsReportController.php`'s report-filter query
construction — that were never in scope for any TASK-0026A–I/F1 task and
are not covered by any current regression suite. Per §6, "known SQL
injection = 0 in supported surfaces" is an explicit GO criterion; it is
not currently met.

**Proposed remediation task**: **TASK-0026J — SQL boundary hardening,
Reports and legacy-trunk scope.** Both sinks should be fixed using the
exact `quoteInto()`/parameterization pattern TASK-0026C and TASK-0026F1
already established and validated — this is a small, mechanical,
low-regression-risk fix by the same precedent, not a redesign. Suggested
scope: `Snep_InterfaceConf.php` (one raw `where()` clause) and
`CallsReportController::getselect()`/`getAnalytic()` (the
`selectContactGroupSrc/Src/Dst`, `groupSrc`/`groupDst`+`order_src`/
`order_dst`, `duration_init`/`duration_end`, `costs_center`, and
`clausulepeer`/`where_exceptions` construction sites), plus a focused
`reports-sql-security-smoke` suite mirroring `sql-security-smoke`'s
structure, wired into `make regression`.

**What GO would not mean, once reached**: this gate certifies absence of
known pilot-blocking security defects in the supported surface — it does
not certify the product is release-ready, the UI is complete, the
PJSIP-only migration is complete, translations are complete, or Product
Readiness (§12) is complete. Those remain separate, later milestones
regardless of this gate's state.

---

## 12. Product Readiness handoff

Non-security (or non-blocking-security) debt discovered across the
security program, handed off without being fixed here:

| Item | Description | Status |
|---|---|---|
| PR-01 | `/var/lib/asterisk` not provisioned in the `app` container — Sound Files/MOH uploads have never been able to write in this dev environment | OPEN — Docker-bootstrap-phase fix (shared volume/bind mount) |
| PR-02 | `sounds.secao` schema mismatch (`NOT NULL`, part of primary key, never set by `Snep_SoundFiles_Manager::add()`) causes a strict-SQL insert failure on every AST-type sound upload | OPEN |
| PR-03 | `Zend_Validate_File_Upload::isValid()` PHP 8.4 `TypeError` on every file upload (`CnlController` is the only caller using this adapter) | OPEN — confirmed still firing in this task's own health check (§8) |
| PR-04 | `/var/log/snep/full` never exists in this dev environment; `Snep_Log`'s constructor also can't surface the missing-file condition to its caller (PHP constructors always return the instance) | OPEN |
| PR-05 | `MusicOnHoldController::removefileAction()` computes its target path from a MOH class's `secao` (name) rather than its independently-settable `directory`; a class where they differ silently orphans the real file | OPEN |
| PR-06 | Transient PJSIP-module-reload-not-yet-settled race between back-to-back regression suites | MITIGATED at the harness level (`harness_retry`, TASK-0027/0027A); underlying product-level timing/readiness-signal gap not itself fixed |
| PR-07 | `chan_sip`/`iax2` remain fully selectable, reachable technologies; config-injection boundary (F15) is now secured, but the broader "should this remain selectable" architecture/removal question is unresolved | OPEN — now includes the confirmed SQL sink tracked separately as pilot-blocking (§5/§11), not merely an architecture question |
| PR-08 | `Snep_InterfaceConf.php` raw SQL sink | **Elevated to pilot-blocking security debt — see §5/§11**, not merely Product Readiness |
| PR-09 | `CSV_ExportDataService.php` PHP 8.4 crash on missing parameters | RESOLVED — incidental side effect of TASK-0026F1's SQL-boundary guard logic |
| PR-10 | `ContactsService.php` PHP 8.4 crash on missing parameters | MITIGATED — minimal guard added by TASK-0026F1, not a general-purpose fix |
| PR-11 | `Snep_Services::getPathService()` dead code, zero call sites | OPEN — non-blocking cleanup candidate |
| PR-12 | Raw SQL text in `CallsReportService.php`/`ServicesReportService.php` JSON responses | RESOLVED by TASK-0026I |
| PR-13 | (see PR-12; both numbers referred to the same disclosure pattern) | RESOLVED by TASK-0026I |
| PR-14 | `CallsReportService.php`'s dead `cost_center` `else` branch (API version) | OPEN — confirmed unreachable, non-blocking, documented |
| PR-15 | Remaining `getMessage()`→`sneperror.phtml` flows (`DatesAliasController`, `ExpressionAliasController`, `SimulatorController`, `ExtensionsController`) | OPEN — tracked in §5 as PRODUCT_READINESS_SECURITY_DEBT |

**Additional items discovered across the program, not in the original
PR-01–15 list** (per this task's instruction not to assume that list
exhaustive):

- `ProfilesController::addAction()` PHP 8.4 `count(false)` fatal (TASK-0026C) — OPEN, same bug class TASK-0023 already fixed for `UsersController::addAction()`, never extended here.
- `TrunksController::editAction()`'s peers-rename-sync bug (looks up the peers row by the *newly submitted* name rather than the trunk's prior name) — OPEN (TASK-0026C), functional, not an injection defect after that task's SQL fix.
- `SoundFilesController::editAction()`'s inverted upload-success condition — OPEN (TASK-0026D), functional.
- Potential stored XSS via unescaped log content (`logs/view.phtml`) — OPEN, tracked as REQUIRES_DEDICATED_SECURITY_TASK in §5, unconfirmed reachability.
- `UsersController::addAction()`/`Snep_Users_Manager::add()` PHP 8.4/strict-SQL fatal — OPEN (TASK-0022, re-confirmed still present by TASK-0027).
- `Snep_Acl::getCaseSensitive()` now unused (absorbed into `Snep_Auth_Adapter_Password`) but left in place — OPEN, low-risk cleanup (TASK-0026H).
- Nine dead `<controller>/error.phtml` view scripts — OPEN, non-blocking cleanup (TASK-0026I).
- `Snep_CsvIE::export()` dead code, same identifier-injection shape as F11 but zero call sites — OPEN, non-blocking cleanup (TASK-0026C).
- Full HTTP security-header rollout (CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, HSTS) beyond `expose_php=Off` — OPEN, explicitly out of scope per the original audit's own §14 instruction.
- Standalone API has no rate limiting and no per-service authorization/RBAC tier — OPEN, both explicitly out of scope for every task that touched that file.
- Pre-existing dev/pilot database volumes need a manual `ALTER TABLE`/table-creation step (or `make reset`) to pick up TASK-0026H's widened `users.password` column and new `login_attempts` table — OPEN, deployment/operational note, not a fresh-install gap.

None of these block the security gate on their own (§6's criteria don't
reference them); they are Product Readiness scope.

---

## 13. Next recommended milestone

1. **TASK-0026J — SQL boundary hardening, Reports and legacy-trunk
   scope** (§11). This is the only work required to move
   `SECURITY_GATE` from NO-GO to GO. Small, mechanical, same
   `quoteInto()` pattern already twice-validated in this codebase
   (TASK-0026C, TASK-0026F1).
2. Once TASK-0026J lands and its own focused suite plus two consecutive
   `make regression` runs pass, re-run this closure task's Phase 6–11
   evaluation (no need to redo Phases 1–5's reconciliation, which does
   not change) to confirm `SECURITY_GATE = GO`.
3. Only then begin Product Readiness work (§12), per this task's own
   explicit scope boundary and CLAUDE.md's phase-ordering discipline.
   Product Readiness is a separate milestone from this security gate,
   not a continuation of it.

---

## Files changed by this task

- `docs/SECURITY-BASELINE.md` (new)
- `docs/tasks/0026z-security-audit-closure.md` (new, this file)

No application/product/test-harness code was modified. No previously
completed TASK-0026A–I/F1/0027/0027A file was touched.
`docs/tasks/0026-pre-pilot-security-release-audit.md` was read in full
and not modified.
