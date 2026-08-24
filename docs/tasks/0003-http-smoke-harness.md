# TASK-0003 — HTTP smoke test harness

## Objective
Automate the manual PHP 8.4 regression validation performed throughout
TASK-0002 into a repeatable `make smoke` command (CLAUDE.md Phase 3).

## Scope
- `scripts/smoke-test.sh` — a plain bash + curl smoke suite, no test
  framework dependency (per instruction: prefer simple/maintainable over
  a heavy framework).
- `make smoke` Makefile target (depends on `up`, so it validates/starts
  the Docker environment first).
- A dedicated, idempotently-provisioned dev-only test account
  (`smoketest`), so the suite never depends on undocumented manual DB
  state and never touches the seeded `admin` row.
- Documentation updates (this file, `README.md`).

## Explicitly out of scope
- Modifying PHP compatibility code (only touched if strictly required to
  make the harness itself work — it wasn't).
- Adding an Asterisk service.
- Curly-brace compatibility work (TASK-0002 §2).
- PJSIP / PostgreSQL / frontend architecture changes.

## What the suite validates, per flow
For each of the 10 required flows (login, dashboard, extensions, trunks,
routes, groups, queues, reports, settings, logout):
- expected HTTP status/redirect (not just "any 2xx")
- a specific rendered-content marker (e.g. `var controller = "extensions"`,
  a JS variable the legacy layout template embeds per-controller) — so a
  blank-but-200 regression is caught, not just a status-code check
- absence of PHP fatal/stack-trace text in the response body (defensive;
  `display_errors` is already `Off` per TASK-0001, so this mainly guards
  against that setting ever being flipped back)
- a before/after `Fatal error` count diff against the app container's
  `mag-error.log`, across the whole run — the authoritative fatal-error
  check, since a caught exception (500 + "Erro Interno") never appears as
  literal "Fatal error" text in the response body

Plus two checks outside the 10-flow list, both explicitly requested:
- **logout session invalidation**: re-requests `/index.php/` after logout
  and asserts the login page renders, not the dashboard.
- **protected config files stay inaccessible**: `GET /includes/setup.conf`
  and `/includes/setup.conf.dist` must both return `403` (TASK-0001's
  `.htaccess` fix).

## The queues "expected limitation"
`queues` is checked with a distinct `known_limitation` mode, not silently
skipped or treated as a pass: the suite asserts the response is *exactly*
`HTTP 500` **and** contains the specific known signature
(`parse_ini_file(/etc/asterisk/snep/snep-musiconhold.conf)`). If the
response ever stops matching that exact signature — a different error, a
different status code, or the absence of that message — the suite reports
it as a **FAIL** (possible new regression), not a limitation. This is the
mechanism CLAUDE.md's "Known runtime boundary" section asks for:
distinguishing a real regression from the documented no-Asterisk
limitation using the actual log/error content, not by assuming.

## Dev test account design
`users.name` has no `UNIQUE` constraint (verified: only `id` is a real
key), so `INSERT ... ON DUPLICATE KEY UPDATE` would silently accumulate a
new duplicate row on every re-run instead of updating one. The script
instead does `DELETE ... WHERE name = 'smoketest'` then `INSERT`, which is
genuinely idempotent. The password hash is computed via
`php -r "echo md5(...)"` **inside the app container**, not a host
`md5sum`/`md5` binary (those differ across host OSes, and the container
already has PHP) — keeping the harness Docker-only per CLAUDE.md.

## Validation performed
`make smoke` run against the live `make dev` environment — see the run
report communicated at task completion for the pass/fail table, timing,
and any newly-uncovered issue.

## Unresolved / follow-up
- The suite exercises one representative page per flow area (e.g.
  `extensions-groups` for "groups", `calls-report` for "reports"), matching
  the exact set of URLs manually validated in TASK-0002 — sibling pages
  (`pickup-groups`, `contact-groups`, `ranking-report`, etc.) are not
  separately covered. Expanding coverage is a natural follow-up, not done
  here to keep this task's scope narrow.
- No CI wiring (this is a local `make smoke` command only, per the task's
  stated scope).
