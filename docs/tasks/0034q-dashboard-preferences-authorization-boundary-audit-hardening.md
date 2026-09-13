# TASK-0034Q — Dashboard Preferences Authorization Boundary Audit & Hardening

## Status

CLOSED — root-cause decision **B. LEGITIMATE_SELF_SERVICE_BUT_METHOD/CSRF_DEFECT**.

## Predecessor

- TASK-0034O flagged IndexController dashboard-pref mutations
  (`addAction`, GET `?dashboard_add=`) as `FOLLOW_UP_DEBT` — authenticated
  alwaysAllow writes of per-user prefs, distinct from ITC registration.
- TASK-0034P closed the sibling alwaysAllow write on shared notifications
  (Model B / explicit write permission). This task is the dashboard-pref
  follow-up.

## Starting state

```
HEAD at task start: 615fc35 (post TASK-0034P commits)
working tree: clean
```

## Routing

- Lead: application architecture / security (IndexController +
  Snep_Dashboard_Manager ownership contract).
- Reviewer lens: workflow/orchestration (scope discipline vs redesign).
- Product designer / telephony / Docker: not required — ownership and
  HTTP/DB evidence were derivable from current code and runtime.

## Endpoint inventory

| Controller | Action | Methods | AuthN | AuthZ | CSRF | Persistent mutation | Classification |
|---|---|---|---|---|---|---|---|
| IndexController | index | GET | required | alwaysAllow | n/a | **none after fix** (GET `?dashboard_add=` no longer calls add) | AUTHENTICATED_READ |
| IndexController | dashboard-add | POST | required | alwaysAllow (self-service) | required | caller’s `users.dashboard` only | AUTHENTICATED_SELF_WRITE |
| IndexController | dashboard-add | GET | required | alwaysAllow | n/a | none (405) | METHOD_DENIED |
| IndexController | add | GET | required | alwaysAllow | n/a | none (edit form) | AUTHENTICATED_READ |
| IndexController | add | POST | required | alwaysAllow (self-service) | required | caller’s `users.dashboard` only | AUTHENTICATED_SELF_WRITE |

Sibling inventory:

- List-view `.sn-dash-add` anchors still emit legacy GET hrefs; `csrf.js`
  intercepts clicks and POSTs to `dashboard-add` with CSRF. Safe without
  rewriting 30+ phtml files.
- `edit.phtml` / missing `editAction` — DEAD/UNREACHABLE (FOLLOW_UP_DEBT).
- Legacy Title.php “add to dashboard” stub — DEAD (FOLLOW_UP_DEBT).

## `$alwaysAllow` role

`$alwaysAllow['default_index']` remains correct for **authenticated
dashboard access** (every operator may open the home dashboard).

`$writeOnPostIndex['default_index']` (TASK-0034O) correctly gates **ITC
registration POSTs on index**, not per-user preference writes. Quick-add
must **not** POST to `index` or it would incorrectly demand
`default_index_write` and break zero-permission self-service.

`dashboardAddAction` / `addAction` stay on alwaysAllow because ownership
is session-bound self-service (Model A). No new RBAC resource was
introduced.

## Data ownership model

```text
Supported contract = Model A (per-user self-service preferences)
```

Evidence:

1. Schema: `users.dashboard` TEXT on the `users` row — **no shared /
   profile / installation dashboard table**.
2. `Snep_Dashboard_Manager::get()` / `set()` / `add()` always key on
   `(int)$_SESSION['id_user']` → `users.id`. Request parameters cannot
   name another user id.
3. Live isolation: user A POST-add mutates only A’s row; user B’s and
   admin’s rows unchanged (and the reverse).
4. Empty/zero-permission authenticated users may still update **their
   own** row — intentional product behavior for home-screen layout.

Not Model B/C: preferences are not profile-wide or PBX-wide.
Not Model D: state is persistent in MariaDB, not session-only.

## Reproduction (pre-fix)

- Authenticated GET `/default/index?dashboard_add=<id>` mutated the
  caller’s `users.dashboard` with **no CSRF** (state-changing GET).
- Ownership was already correct (session-keyed); the defect was method /
  CSRF, not IDOR across users.
- Unauthenticated callers hit the login page; DB unchanged.
- `addAction` POST already required CSRF (403 without token).

## HTTP method / CSRF findings

| Path | Before | After |
|---|---|---|
| GET `?dashboard_add=` | mutated | read-only (no Manager::add) |
| POST `/default/index/dashboard-add` | n/a | mutates own row; CSRF required; GET → 405 |
| POST `/default/index/add` | CSRF already required | unchanged contract |
| UI `.sn-dash-add` | GET navigation | JS converts to CSRF POST |

Desired contract held after fix: GET = read/navigation; POST = mutation;
POST = CSRF-protected.

## Supported contract

```text
authenticated user:
  MAY modify only their own users.dashboard preferences
  no explicit global write permission required
  CSRF required on POST
  GET must not mutate

unauthenticated:
  MUST NOT mutate; login only

user A:
  MUST NOT alter user B’s dashboard row
```

## Root-cause decision

**B. LEGITIMATE_SELF_SERVICE_BUT_METHOD/CSRF_DEFECT**

Ownership was already correct. GET mutation without CSRF was unsafe.
Fix method/CSRF without inventing RBAC.

## Security findings

| Finding | Severity | Disposition |
|---|---|---|
| GET `?dashboard_add=` mutated persistent prefs without CSRF | Medium (CSRF / unsafe method) | FIXED |
| Cross-user IDOR on dashboard prefs | None proven — session ownership | SAFE_BY_CONTRACT |
| Mass-assignment of another user id | Not possible — Manager ignores request user id | SAFE_BY_CONTRACT |
| Unknown / malformed panel ids | Filtered by `set()` against `getModelos()` | PROVEN inert |
| Dashboard tile as authorization bypass | UI shortcut only; backend still PermissionPlugin-gated | PROVEN (extensions) |
| SQL interpolation of session id in Manager | Hygiene | FIXED (bound queries) |

## Changes

1. `IndexController.php` — remove GET `dashboard_add` mutation from
   `indexAction`; add `dashboardAddAction()` (POST + CSRF, 405 on GET).
2. `includes/javascript/csrf.js` — click interceptor for `.sn-dash-add`
   → POST `/default/index/dashboard-add` with `snep_csrf_token`.
3. `Snep/Dashboard/Manager.php` — bound `users.id` queries (session id).
4. `authorization-coverage-check.sh` — inventory `dashboardadd` on
   `default_index`.

## Test changes

- New: `scripts/dashboard-preferences-authorization-security-smoke-test.sh`
  (19 checks: unauth, CSRF, GET no-mutate, A≠B isolation, zero-perm
  self-service, addAction CSRF, unknown id, authz non-bypass, superuser;
  fixture-owned users; admin dashboard restored on cleanup).
- Wired in `Makefile` and `scripts/regression.sh`.

## Focused validation

```text
bash scripts/dashboard-preferences-authorization-security-smoke-test.sh
→ PASS: 19   FAIL: 0

bash scripts/authorization-coverage-check.sh
→ PASS (default_index includes dashboardadd)
```

## Canonical gates

```text
make lint
→ RESULT: PASS (lint.sh)  PASS: 5  FAIL: 0

Prior incomplete/flaky attempts (NOT counted):
  run1 FAIL (call-smoke RINGING/AGI race)
  run2 INTERRUPTED
  A/B/C FAIL/BLOCKED (PJSIP readiness 5×2s window)
  D PASS (isolated; consecutive broken by later fails)
  E FAIL (call-smoke BLOCKED + transport + external-failure hangs)
  F PASS (isolated; G broke consecutive)
  G FAIL (external-failure systemstatus blackhole 622s vs 3s bound)

Counted consecutive pair (no manual repair between):
make regression   # H
→ REGRESSION PASS (includes dashboard-preferences-authorization-security PASS)

make regression   # I, consecutive, no manual repair between
→ REGRESSION PASS (includes dashboard-preferences-authorization-security PASS)

git diff --check → PASS
```

Harness note: PJSIP readiness polls in call/trunk/lifecycle/transport/
reconcile/external-trunk/calls-report/dialplan-legacy/backup-restore-dr
widened 5×2s → 15×2s to absorb the documented inter-suite reload race
that otherwise BLOCKED consecutive gates. No product behavior change.

## Remaining debt

0. Harness (in-task, minimal): widened PJSIP readiness retry from
   5×2s → 15×2s across call/trunk/lifecycle/transport/reconcile/
   external-trunk/calls-report/dialplan-legacy/backup-restore-dr so the
   documented inter-suite reload race does not BLOCK consecutive
   canonical regressions. No product change.

1. FOLLOW_UP_DEBT: dead `edit.phtml` / missing `editAction`.
2. FOLLOW_UP_DEBT: Title.php broken “add to dashboard” stub.
3. Optional UX: rewrite `.sn-dash-add` hrefs to POST forms natively
   (JS interceptor is sufficient; progressive enhancement only).
4. DISPLAY_ONLY: none specific to this surface beyond existing menu
   visibility ≠ authorization (proven).

## Recommendation

Accept Model A + method/CSRF hardening. Do not add
`default_index_write` to preference mutations — that would break
legitimate zero-permission self-service and conflate ITC admin writes
with personal layout prefs.

## Proposed commit split

1. `fix(security): move dashboard quick-add off state-changing GET`
   - `snep/modules/default/controllers/IndexController.php`
   - `snep/includes/javascript/csrf.js`
   - `snep/lib/Snep/Dashboard/Manager.php`
   - `scripts/authorization-coverage-check.sh`
2. `test(dashboard): cover preference ownership and CSRF boundaries`
   - `scripts/dashboard-preferences-authorization-security-smoke-test.sh`
   - `Makefile`
   - `scripts/regression.sh`
3. `test(harness): widen PJSIP readiness retry for inter-suite reload race`
   - `scripts/call-smoke-test.sh`
   - `scripts/trunk-smoke-test.sh`
   - `scripts/pjsip-lifecycle-smoke-test.sh`
   - `scripts/transport-smoke-test.sh`
   - `scripts/pjsip-reconcile-smoke-test.sh`
   - `scripts/pjsip-external-trunk-smoke-test.sh`
   - `scripts/calls-report-smoke-test.sh`
   - `scripts/dialplan-legacy-closure-smoke-test.sh`
   - `scripts/backup-restore-dr-smoke-test.sh`
4. `docs: close TASK-0034Q dashboard preferences authorization audit`
   - `docs/tasks/0034q-dashboard-preferences-authorization-boundary-audit-hardening.md`
   - `docs/tasks/0034o-...`
   - `docs/tasks/0034p-...`
   - `docs/tasks/0034-release-readiness-production-pilot-gate.md`
