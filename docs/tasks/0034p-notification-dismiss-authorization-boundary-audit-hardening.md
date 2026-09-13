# TASK-0034P — Notification Dismiss Authorization Boundary Audit & Hardening

## Status

CLOSED — root-cause decision **C. GLOBAL_WRITE_REQUIRES_EXPLICIT_PERMISSION**.

## Predecessor

- TASK-0034O flagged `default_notifications` as `DIFFERENT_RISK / NEEDS_FOLLOW_UP`
  ("dismiss under alwaysAllow — intentional self-service; document-only
  unless a future audit reclassifies vendor-notice writes").
- This task is that audit. Evidence reclassified dismiss as shared
  installation-scoped write, not per-user self-service.

## Starting state

```
HEAD at task start: 0dd71a3 (merge tip after TASK-0034O commits)
working tree: clean
```

## Routing

- Lead: application architecture / security (PermissionPlugin +
  NotificationsController ownership contract).
- Reviewer lens: workflow/orchestration (scope discipline vs redesign).
- Product designer / telephony / Docker: not required — ownership and
  HTTP/DB evidence were derivable from current code and runtime.

## Endpoint inventory

| Controller | Action | Methods | AuthN | AuthZ (before) | AuthZ (after) | CSRF | Persistent mutation | Classification |
|---|---|---|---|---|---|---|---|---|
| NotificationsController | index | GET | required | alwaysAllow | alwaysAllow (unchanged) | n/a | none (GET no longer calls setRead — TASK-0026G) | AUTHENTICATED_READ |
| NotificationsController | mark-read | POST | required | alwaysAllow (any auth user) | `default_notifications_write` via `$writeActionsOnAlwaysAllow` | required | vendor PUT (installation uuid) + local `core_notifications.read` | AUTHENTICATED_GLOBAL_WRITE |
| NotificationsController | mark-read | GET | required | alwaysAllow | write-gated (same list) but action returns 405 | n/a | none | INTERNAL_ONLY / method-denied |
| NotificationsController | remove | GET | required | alwaysAllow | `default_notifications_write` | n/a | none (confirm form only) | AUTHENTICATED_GLOBAL_WRITE (form gated with mutation) |
| NotificationsController | remove | POST | required | alwaysAllow | `default_notifications_write` | required | vendor DELETE + local row delete by `id_itc` | AUTHENTICATED_GLOBAL_WRITE |

Sibling actions: none beyond the three above. No further same-controller
debt required for boundary consistency.

## `$alwaysAllow` role

`$alwaysAllow['default_notifications']` remains correct for **read**:
every authenticated operator may view the shared vendor-notice feed
without a per-resource grant (profiles_permissions is typically empty
on fresh installs).

It was **incorrect** as a blanket cover for mark-read/remove. Those
actions mutate installation-scoped shared state. TASK-0034P adds
`$writeActionsOnAlwaysAllow['default_notifications']` so named mutating
actions fall through the alwaysAllow short-circuit and demand
`default_notifications_write` (same shape as TASK-0034O's
`$writeOnPostIndex` for index/register POSTs).

Unauthenticated callers never reach the controller: AuthPlugin forwards
to the login page before PermissionPlugin runs.

## Data ownership model

```text
Supported contract = Model B (global notification administration)
  with authenticated-open READ retained via alwaysAllow.
```

Evidence:

1. `core_notifications` schema has **no user_id / owner column** — only
   `id`, `id_itc`, `title`, `from`, `message`, `creation_date`, `read`,
   `reading_date` (live DESCRIBE).
2. Local cache is PBX-wide: `replaceCachedNotifications()` deletes and
   reinserts the whole table.
3. `setRead()` / `removeNotification()` call the vendor API as
   `host_notification / $_SESSION['uuid'] / $id` — `uuid` is the
   installation ITC identity seeded at login, **not** the acting user id.
4. Therefore one authenticated operator's dismiss changes the unread /
   presence state observed by every other operator after local cache
   update (and after vendor sync).

Not Model A (per-user acknowledgement): no per-user ack table exists.
Not Model C (global source + per-user ack): dismiss updates the shared
row itself, it does not insert a separate ack.

## Reproduction (pre-fix)

With fixture rows in `core_notifications` and a zero-permission
authenticated session:

- GET `/default/notifications?id=all` → HTTP 200 (alwaysAllow read).
- POST `/default/notifications/mark-read` with valid CSRF → HTTP 200
  (mutation allowed for zero-perm — defect under Model B).
- POST `/default/notifications/remove/id/<id_itc>` with CSRF → HTTP 302
  success redirect (same).
- Unauthenticated POST → login page; local DB unchanged.
- POST without CSRF → HTTP 403; local DB unchanged.
- GET mark-read → HTTP 405 (already fixed by TASK-0026G).

Pre-fix `setRead()`/`removeNotification()` only called the vendor and
did **not** update local `core_notifications`, despite docblocks claiming
a local update. Badge convergence depended on the next vendor sync.

## CSRF / HTTP method findings

- Desired contract already mostly held: GET index is read-only;
  mark-read is POST-only (405 on GET); remove uses GET confirm + POST
  mutate; CsrfPlugin enforces `snep_csrf_token` on authenticated POSTs.
- No state-changing GET remains on this controller.
- Browser session credentials could previously abuse cross-site dismiss
  only if CSRF were missing; CSRF was already required. The remaining
  gap was **authorization**, not CSRF.

## Supported contract

```text
authenticated user:
  MAY view the shared notification feed (alwaysAllow GET index)

authenticated user with default_notifications_write (or superuser):
  MAY mark-read / remove shared notifications (CSRF required on POST)

authenticated user without that write grant:
  MUST be denied; DB state unchanged

unauthenticated:
  MUST NOT mutate; login page / redirect only
```

## Root-cause decision

**C. GLOBAL_WRITE_REQUIRES_EXPLICIT_PERMISSION**

`$alwaysAllow` itself is not the vulnerability. Using it to cover shared
write actions without a write resource was the defect. Smallest fix:
gate mark-read/remove on `default_notifications_write` while keeping GET
index authenticated-open.

## Security findings

| Finding | Severity | Disposition |
|---|---|---|
| Any authenticated zero-grant user could mark-read/delete shared vendor notices for the whole PBX | Medium (integrity / shared-state) | FIXED |
| alwaysAllow comment claimed "self-service" for a non-owned shared cache | Spec/docs defect | FIXED (comment + contract) |
| setRead/removeNotification did not update local cache (docblock lie; badge depended on vendor sync) | Reliability / testability | FIXED (local-first cache update) |
| CSRF on dismiss POSTs | Already correct | PRESERVED |
| GET mark-read mutation | Already closed (0026G) | PRESERVED |
| IDOR across users | N/A as per-user ownership — state is intentionally shared; unknown ids must not disturb unrelated rows | PROVEN by suite |

## Changes

1. `PermissionPlugin.php` — `$writeActionsOnAlwaysAllow` for
   `default_notifications` (`mark-read` / `markread` / `remove`);
   alwaysAllow short-circuit updated; comment corrected.
2. `resources.xml` — register `notifications` + `write` child so
   `default_notifications_write` exists.
3. `Snep/Notifications.php` — local-first `core_notifications` update on
   setRead / delete on removeNotification; ownership documented in
   docblocks; vendor call remains best-effort.

## Test changes

- New: `scripts/notification-dismiss-authorization-security-smoke-test.sh`
  (19 checks: unauth, zero-perm, read-only, writer, CSRF, GET 405,
  shared-row DB proofs, unknown-id isolation, superuser).
- Wired in `Makefile` and `scripts/regression.sh`.

## Focused validation

```text
bash scripts/notification-dismiss-authorization-security-smoke-test.sh
→ PASS: 19   FAIL: 0
RESULT: PASS
```

## Canonical gates

```text
make lint
→ RESULT: PASS (lint.sh)  PASS: 5  FAIL: 0

Focused suite (post-lint recreate):
→ PASS: 19  FAIL: 0

make regression   # run 1
→ REGRESSION PASS (includes notification-dismiss-authorization-security PASS)

make regression   # run 2, consecutive, no manual repair between
→ REGRESSION PASS (includes notification-dismiss-authorization-security PASS)

git diff --check → PASS
```

## Remaining debt

1. DISPLAY_ONLY: Delete / mark-read UI still rendered for users who will
   be denied on POST (same class as Register menu when ITC disabled).
2. FOLLOW_UP_DEBT (carry-forward from 0034O): IndexController dashboard
   pref mutations (`addAction`, GET `?dashboard_add=`) still alwaysAllow
   authenticated writes of per-user prefs — different asset, not this
   task.
3. Vendor `host_notification` reachability / timeout behavior is
   unchanged (TASK-0024 isolation). Local cache now converges without it.

## Recommendation

Accept Model B + write gate. Do not introduce a per-user acknowledgement
table unless product later requires true per-operator dismiss without
affecting peers (would be a new task / Model C migration).

## Proposed commit split

1. `fix(security): gate shared notification dismiss behind write permission`
2. `test(notifications): cover dismiss ownership and authorization boundaries`
3. `docs: close TASK-0034P notification dismiss authorization audit`
