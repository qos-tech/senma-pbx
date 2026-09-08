# TASK-0034C — Production Fixture & Compose Profile Isolation

## LEAD

senma-docker-platform-engineer

## REVIEWERS

senma-application-architect (Makefile/regression fixture-ownership implications), senma-telephony-architect (provider fixture is telephony-sensitive -- trunk/call regression must keep working under the new opt-in)

## SCOPE

Close TASK-0034 Finding CH-3 (`provider` fixture has no Compose profile
gate) for real: TASK-0034B had already mitigated the specific reproduced
footgun (its own `up`-target exposure-reversal finding, fixed with the
`COMPOSE_FILES`/`SERVICES` opt-in variables) but explicitly left CH-3's
own underlying gap open, and said so in its own REMAINING DEBT section.
This task makes development/test-only services structurally impossible
to start through the supported production/pilot Compose workflow, rather
than relying on an operator remembering a service list.

**In scope**: Compose service/profile isolation for `provider`; fixture
inventory across the whole repository (not just `provider`); Makefile
wiring so the opt-in is available exactly where needed (`dev-up`, and
the three suites that actually require it) without being available
everywhere; a focused regression suite proving the isolation; runbook
and TASK-0034 documentation updates.

**Out of scope** (per task instructions): new telephony features,
provider fixture redesign, WSS certificate replacement (CH-2), AMI ACL
redesign (CH-6), release artifact/versioning (CH-9), RTP capacity/load
testing, Docker Desktop networking redesign.

---

## ORIGINAL CH-3 (verbatim, TASK-0034)

> **CH-3 — `provider` fixture service has no Compose profile gate.**
> The `provider` service (a full second Asterisk instance simulating a
> SIP trunk provider, purely for regression testing) starts
> unconditionally with plain `docker compose up`/`make up` — there is no
> `profiles:` key and no production override file in the repository.
> Mitigated in the runbook (explicit `docker compose up -d app asterisk
> db` service list for production). Recommend a small follow-up to add a
> Compose profile so this can't be started by accident — deferred here
> because it would touch every Makefile target that currently relies on
> `provider` starting implicitly (regression, smoke, etc.), a broader
> blast radius than this task's small-fix mandate.

TASK-0034B's own REMAINING DEBT section reconfirmed this was still open
after its own, narrower fix:

> `FOLLOW_UP_DEBT`: CH-3's own pre-existing gap (`compose.yaml` has no
> `profiles:` gate to stop `provider` from starting on a plain, non-
> pilot `make up`) is unchanged by this task — `pilot-up`'s explicit
> service list already avoids it for the documented pilot path, and the
> `COMPOSE_FILES`/`SERVICES` fix closes the specific way it could leak
> through the check targets, but the underlying compose-level gate
> itself remains a documented, not-yet-implemented improvement.

---

## CURRENT COMPOSE BEHAVIOR (before this task)

Reproduced live, on this repository's own long-running dev stack
(`docker compose ps -a` showed all four containers already `Up` from a
prior session, confirming the baseline claim directly rather than by
inference):

```
$ docker compose config --services
provider
db
asterisk
app
$ docker compose ps -a --format '{{.Service}}: {{.State}}'
app: running
asterisk: running
db: running
provider: running
```

`compose.yaml` declared exactly four services (`app`, `asterisk`,
`provider`, `db`) with no `profiles:` key anywhere and no test-specific
Compose override file in the repository (only `compose.pilot.yaml`
existed, and it is additive/production-facing, not a fixture gate). A
plain `docker compose up` or `make up` created and started all four.

---

## SERVICE INVENTORY

| Service | Classification | Evidence |
|---|---|---|
| `app` | `PRODUCTION_REQUIRED` | Only service publishing a host port by design (`MAG_HTTP_PORT`); the SENMA web application itself |
| `asterisk` | `PRODUCTION_REQUIRED` | The SENMA telephony runtime; `compose.pilot.yaml` publishes its SIP/WSS/RTP ports for a pilot |
| `db` | `PRODUCTION_REQUIRED` | MariaDB, persistent application/CDR data |
| `provider` | `DEVELOPMENT_ONLY` / `TEST_ONLY` | A second, independent Asterisk 22/PJSIP instance (TASK-0015) simulating an external SIP trunk provider, purely for local development/regression. Never part of the product; no production code path references it |

No `UNKNOWN` remains: these four are the only services `docker compose
config --services` can ever return for this project (confirmed by
reading `compose.yaml` in full, not just grepping).

Two Dockerfiles exist for other test-only images —
`docker/baresip-test.Dockerfile` and `docker/wss-test-client.Dockerfile`
— but **neither is a Compose service**. They are built and run directly
via `docker build`/`docker run --network mag ...` by the test scripts
that use them (`scripts/call-smoke-test.sh`,
`scripts/wss-platform-smoke-test.sh`, and others), entirely outside
Compose's service model. No `docker compose up`/`up -d` invocation
anywhere in this repository's Makefile or scripts can ever create a
container from either image — they are already structurally isolated
from the production/pilot Compose workflow by construction, and require
no profile gate. This is worth stating explicitly rather than leaving it
implicit: they were never a CH-3-class risk.

---

## FIXTURE INVENTORY

### `provider` (compose.yaml service)

- **Purpose**: deterministic local SIP trunk simulator so outbound/
  inbound PJSIP trunk provisioning can be proven with a real SIP dialog,
  without any commercial carrier credentials (TASK-0015).
- **Dependencies**: reuses `docker/asterisk.Dockerfile` (same image as
  the real `asterisk` service) with a dedicated entrypoint
  (`docker/provider-entrypoint.sh`) and its own small config
  (`docker/provider-config/`). Never runs SENMA's own PHP/AGI/ODBC
  stack.
- **Network exposure**: no host port published in either `compose.yaml`
  or `compose.pilot.yaml`; reachable only from `asterisk` over the
  internal `mag` network. Unaffected by this task.
- **Volumes**: own named volumes (`mag-provider-etc`, `mag-provider-var`)
  — independent from `asterisk-etc`/`mag-asterisk-var`. Regenerated
  entirely from `docker/provider-config/` at container boot; holds no
  customer data.
- **Credentials**: `TRUNK_TEST_USERNAME`/`TRUNK_TEST_SECRET` (`.env`,
  `TEST_ONLY`/`DEVELOPMENT_ONLY` per TASK-0034 §3). Consumed only by
  `docker/provider-entrypoint.sh` (which never runs unless `provider`
  itself runs) and by the test scripts that create matching trunk rows
  in the database for the duration of their own run. No production
  bootstrap path reads them.
- **Can it place/register calls?** Yes — that is its entire purpose: it
  accepts outbound REGISTER/INVITE from `asterisk` and originates
  inbound INVITE toward it, over the real SIP protocol.
- **Does it persist data?** Only its own regenerable PJSIP runtime state
  in its own volumes; never SENMA application/CDR data.
- **Production risk if left running**: real (this is exactly CH-3) — a
  full second Asterisk instance with test-fixed credentials reachable
  from the `asterisk` container, on a network whose subnet is also
  trusted by the AMI ACL (TASK-0034 CH-6's own already-accepted
  constraint). Structurally closed by this task.

### `TRUNK_TEST_USERNAME`/`TRUNK_TEST_SECRET` (`.env`)

Tied entirely to `provider` — see above. Not a separate risk once
`provider` cannot start by accident.

### baresip/WSS test-client Dockerfiles

See SERVICE INVENTORY above — not Compose services, not reachable
through any `docker compose up` path, no gate needed.

---

## ISOLATION ARCHITECTURE

**Selected: Docker Compose profiles**, exactly the mechanism the task
instructions proposed, adapted to this repository's actual topology:

```yaml
services:
  provider:
    profiles:
      - dev
      - test
```

Compose only creates a profiled service when one of its listed profiles
is active (`COMPOSE_PROFILES` env var, or `--profile`) at the moment
`up` runs — never by default, never merely because it is named as a
dependency elsewhere, and never merely because it happened to be running
from a previous session (a fresh `up`/`--force-recreate` with no profile
active will not (re)create it; see PRODUCTION-LIKE PROOF).

**Two profile names, not one**, because this repository's own Makefile
already distinguishes two different callers with different intent:

- `dev` — an interactive developer explicitly asking for the fixture
  (`make dev-up`).
- `test` — a regression/smoke suite that owns the fixture's lifecycle
  for the duration of its own run (`trunk-smoke`,
  `pjsip-runtime-status-smoke`, `readiness-smoke`, `regression`).

Both activate the identical service (there is only one `provider`
definition) — the split is about which caller and why, not two
different configurations. This matches Phase 6's own vocabulary
(`dev`/`test`) and avoids the "avoid many overlapping profile names"
anti-pattern: exactly one service carries exactly two profile labels,
not many services each with their own bespoke name.

**Alternatives considered and rejected**:

- *Separate development override file* (`compose.dev.yaml` adding
  `provider`): rejected — would require every developer/regression
  command to remember an extra `-f` flag, exactly the "operator must
  remember the right service list" failure mode this task exists to
  eliminate. Profiles are additive at the *service* level and need no
  extra file for the common case.
- *Separate test compose file*: rejected for the same reason, and
  because `provider` genuinely serves both an interactive-developer use
  case and a regression-owned use case with identical configuration —
  a second file would either duplicate the service definition or need
  to be combined with the base file via `-f` anyway, adding complexity
  the profile mechanism doesn't need.

---

## PROFILE/MODE CONTRACT

| Invocation | `provider` created? |
|---|---|
| `docker compose up` (no `-f`, no `COMPOSE_PROFILES`) | No |
| `make up` / `make dev` (default `FIXTURE_PROFILE` empty) | No |
| `make pilot-up` / `make pilot-config` (`COMPOSE_PROFILES=` hardcoded empty) | No, even if the shell exports `COMPOSE_PROFILES=dev`/`=test` |
| `docker compose ... up -d --force-recreate` (no profile active) | No — re-verified live, does not (re)create an absent `provider`, does not disturb an already-running one |
| `make dev-up` (`FIXTURE_PROFILE=dev`) | Yes |
| `make trunk-smoke` / `make pjsip-runtime-status-smoke` / `make readiness-smoke` / `make regression` (`FIXTURE_PROFILE=test` on each) | Yes |
| `COMPOSE_PROFILES=dev` or `=test` set directly (any other `docker compose` invocation) | Yes |

---

## BASE COMPOSE CONTRACT

**`compose.yaml` is the PRODUCTION-SAFE BASE**, stated explicitly in its
own header comment as of this task. With no `-f compose.pilot.yaml`
overlay and no `dev`/`test` profile activated, it starts exactly `app`,
`asterisk`, `db` and publishes nothing beyond the app's own HTTP port —
true for a bare `docker compose up`, not only for this repository's own
Makefile wrapper, so the guarantee holds even for an operator who
bypasses `make` entirely. This was chosen over "common base requiring an
explicit mode" because, after this task, no explicit mode is actually
required to get a safe result — safety is now the unconditional default,
and `compose.pilot.yaml`/`FIXTURE_PROFILE` are the two ways to
*additively* opt into more (host exposure, or a fixture), never the way
to opt into less.

---

## PILOT CONTRACT

`compose.pilot.yaml` remains a pure additive production/pilot overlay
(TASK-0034B) — it adds SIP/WSS/RTP host-port publication to `asterisk`
and nothing else. It does not need to enumerate an exclusion for
`provider` (Phase 11 was concerned this task might have to); the base
file's own profile gate already keeps it out regardless of which overlay
is layered on top, so the pilot overlay carries no development semantics
of its own, before or after this task. `make pilot-up`/`make
pilot-config` additionally hardcode `COMPOSE_PROFILES=` empty in their
own recipes, so an operator's shell already exporting `COMPOSE_PROFILES=
dev`/`=test` (an unrelated project, a forgotten session) cannot change
that — see ENVIRONMENT CONTAMINATION PROOF.

---

## DEVELOPMENT CONTRACT

One new, explicit, documented command: `make dev-up`
(`FIXTURE_PROFILE=dev` on its own `up` prerequisite). Plain `make dev`/
`make up` remain fixture-free — a deliberate behavior change from before
this task (previously, plain `make up` always started `provider`,
because there was no gate at all). This is Phase 7's own explicit
instruction ("do not preserve an unsafe default solely for convenience")
applied to the *development* default, not only the production one: a
developer who never touches trunk/telephony work no longer gets a second
Asterisk instance they didn't ask for, and one who does gets it via one
documented command, or automatically the moment they run a suite that
needs it (see TEST/REGRESSION CONTRACT) — never by manually listing
services.

---

## TEST/REGRESSION CONTRACT

Exactly three suites, out of the full 38 pre-existing suites, actually
require `provider` (confirmed by grepping every suite's own
`harness_require_containers` call, not assumed):
`trunk-smoke-test.sh`, `pjsip-runtime-status-smoke-test.sh`,
`readiness-smoke-test.sh`. Each carries its own `FIXTURE_PROFILE = test`
target-specific Makefile variable, which GNU Make also applies when
building that target's own `up` prerequisite — so `make trunk-smoke` (or
any of the other two) run standalone starts `provider` automatically,
with no separate command and no manually-typed service list.

`regression` itself also carries `FIXTURE_PROFILE = test` on its own
`up` prerequisite, because `scripts/regression.sh` invokes each suite's
underlying script directly (`bash scripts/trunk-smoke-test.sh`, not
`make trunk-smoke`) — the three suites' own individual
`FIXTURE_PROFILE` settings do not apply on that path, so `regression`'s
own setting is what actually matters there, and does the same job once,
up front, for all three.

The dev/test profile is deliberately **not** enabled globally (e.g. by
making `up` itself default to `FIXTURE_PROFILE=test`) — Phase 9's own
instruction — because 35 of the 38 pre-existing suites, `lint`, `dev`,
`doctor`, `secrets-check`, `migrate-check`, `reconcile-check`, `backup`,
`restore`, and every other Compose-invoking target never need
`provider` at all.

**Fixture ownership** (Phase 10): the three suites above already
required `provider` to be `Up` via `harness_require_containers` (which
only checks — with a bounded retry — that the container is already
running; it never starts one itself, and BLOCKs with an explicit
actionable message if it is not). Before this task, that container was
provided implicitly by `make regression`'s own `up` prerequisite, which
started *everything* by default; there was no fixture-specific
ownership at all. After this task, the exact same mechanism
(`harness_require_containers`) is preserved unchanged inside each
script, but the thing that guarantees `provider` is `Up` before it runs
is now an explicit, named `FIXTURE_PROFILE = test` line on each
consuming target (and on `regression` itself) — ownership is now
attributable to a specific, readable line in the Makefile, not an
accident of what the default topology happened to include.

`db-migration-failure-smoke-test.sh` runs a completely separate,
isolated Compose project (`-p senma-dbmigtest-$$`) and only ever issues
`up -d db` / `up -d app` with named services — it never relied on
`provider` starting by default and is unaffected by this task.

---

## MAKEFILE AUDIT

Every Compose-invoking target was reviewed and classified:

| Target(s) | Class | `provider` reachable? | Notes |
|---|---|---|---|
| `config`, `up`, `dev` | BASE | No (default `FIXTURE_PROFILE` empty) | `config` now also reads `FIXTURE_PROFILE`, so its preview matches what `up` would actually do |
| `dev-up` (new) | DEV | Yes (`FIXTURE_PROFILE=dev`) | The one supported developer opt-in (Phase 8) |
| `trunk-smoke`, `pjsip-runtime-status-smoke`, `readiness-smoke`, `regression` | TEST | Yes (`FIXTURE_PROFILE=test`) | Own the fixture's lifecycle for their own run |
| `pilot-config`, `pilot-up` | PILOT | No, unconditionally (`COMPOSE_PROFILES=` hardcoded) | Resists shell contamination even if `dev`/`test` targets ran earlier in the same session |
| Every other `*-smoke`/security/lint/backup/restore/reconcile/migrate/secrets target | BASE | No | Unaffected; none of them declared `provider` as a required container |
| `down`, `restart`, `reset` | BASE (lifecycle) | N/A — operate on whatever containers already exist, regardless of current profile activation; unchanged by this task | `docker compose down`/`restart` are not gated by profiles at all (Compose's own documented behavior); a `provider` container left running from an earlier `dev-up`/`regression` is still torn down by `make reset`/`make down`, exactly as before |
| `db-migration-failure-smoke` | Isolated project, named services only | No | Never relied on the default topology; unaffected |

No unrelated target's semantics changed. `COMPOSE_FILES`/`SERVICES`
(TASK-0034B) are untouched and remain required for the pilot port-
exposure half of the `up`-prerequisite risk; `FIXTURE_PROFILE` is a
new, independent variable solely for the fixture-start half.

---

## ACCIDENTAL-START PREVENTION PROOF

All reproduced live, in this order, on the project's own dev stack:

1. Stopped and removed the pre-existing `provider` container
   (`docker compose stop provider && docker compose rm -f provider`) to
   start from a clean slate.
2. `make up` (plain, no variables) → `docker compose ps -a` showed only
   `app`/`asterisk`/`db`; `make doctor` reported `[SKIP] Container:
   provider: no container for this service -- expected unless
   'dev'/'test' was explicitly opted into...`, zero `FAIL` lines.
3. `make pilot-config` → zero `provider:` service blocks in the merged
   config (`grep -c "provider:"` → `0`), even with `provider` running
   live under an active `dev` profile at the time (step 6 below) —
   config generation does not depend on current container state.
4. `make pilot-up` → `docker compose ps -a` after convergence showed
   `app`/`asterisk`/`db` only (at that point in the sequence, before
   step 6); `docker port mag-pbx-asterisk-1` showed exactly 406 lines
   (5060 udp/tcp ×2 families + 8089 tcp ×2 + 200 RTP ports ×2 families),
   matching TASK-0034B's own established figure exactly; zero lines
   contained `5038` (AMI) or `3306` (DB).
5. `COMPOSE_PROFILES= docker compose -f compose.yaml -f
   compose.pilot.yaml up -d --build --force-recreate app asterisk db`
   (the literal pilot recipe) → `provider` still absent afterward.
6. Removed `provider` again, then ran the identical `--force-recreate`
   command a second time from a clean slate → `provider` still not
   created.

---

## EXPLICIT OPT-IN PROOF

- `make dev-up` → `docker compose ps -a` showed `provider` `Created`
  then `Started`; once healthy, `make doctor` reported `[PASS]
  Container: provider: running, healthy -- DEVELOPMENT_ONLY/TEST_ONLY
  fixture (TASK-0034C); confirm this is intentional before a
  production/pilot release`.
- `docker compose config --services` with `COMPOSE_PROFILES=dev` and,
  separately, `COMPOSE_PROFILES=test` both included `provider` (verified
  live and by the automated suite below).
- `make trunk-smoke` (and `pjsip-runtime-status-smoke`, `readiness-smoke`
  individually) each bring `provider` up automatically via their own
  `FIXTURE_PROFILE = test` target-specific variable — confirmed via
  `make -n trunk-smoke`:
  ```
  COMPOSE_PROFILES="test" docker compose  up -d --build
  set -a; . ./.env; set +a; bash scripts/trunk-smoke-test.sh
  ```

---

## PROVIDER FUNCTIONAL PROOF

`trunk-smoke`, `pjsip-runtime-status-smoke`, and `readiness-smoke` all
passed in both full regression runs below with `provider` started
exclusively through the new `FIXTURE_PROFILE=test` opt-in (no manual
service list, no pre-existing implicit `up` fallback) — the same real
SIP REGISTER/INVITE dialog against the `provider` simulator these suites
have always exercised (TASK-0015/0016 lineage) is unaffected by *how*
the container came to exist. The fixture itself was not redesigned.

---

## CREDENTIAL ISOLATION

`TRUNK_TEST_USERNAME`/`TRUNK_TEST_SECRET` remain classified `TEST_ONLY`/
`DEVELOPMENT_ONLY` (unchanged from TASK-0034 §3). They are consumed only
by `docker/provider-entrypoint.sh`, which cannot run unless `provider`
itself runs — and `provider` cannot run through any production/pilot
path (see above). No change to `.env.example`'s own warning banner was
needed; the risk these credentials posed was always downstream of
`provider` starting, which is now the thing structurally closed.

---

## NETWORK EXPOSURE PROOF

With `provider` disabled (default/pilot mode): `docker compose ps`
showed no `provider` container at all; `docker compose config`/
`docker port mag-pbx-asterisk-1` (pilot mode) confirmed AMI (5038) and
the database (3306) remain absent from every published-port list, and
the RTP range remained exactly `10000-10199` (200 ports) — no
regression toward the 10,001-port dev-default range TASK-0034B's own
incident record warns against (Phase 34). See ACCIDENTAL-START
PREVENTION PROOF above for the exact commands/output.

---

## VOLUME/PERSISTENCE ISOLATION

`provider`'s volumes (`mag-provider-etc`, `mag-provider-var`) were
already, and remain, entirely independent from every production/
customer-owned volume (`mag-db`, `asterisk-etc`, `mag-asterisk-var`,
`mag-asterisk-spool`, `mag-asterisk-log`) — confirmed by reading
`compose.yaml`'s `volumes:` section in full. No fixture mounts a
production volume, in either direction. Nothing to block here; this was
already correctly isolated before this task and remains so.

---

## ENVIRONMENT CONTAMINATION PROOF

Reproduced live:

- `COMPOSE_PROFILES=test make -n up` → recipe still resolves to
  `COMPOSE_PROFILES="" docker compose ... up -d --build` (the Makefile
  recipe builds `COMPOSE_PROFILES` from `$(FIXTURE_PROFILE)`, a
  Make-only variable never read from the process environment under that
  same name, so a same-named shell export cannot influence it).
- `COMPOSE_PROFILES=dev make -n pilot-up` → recipe still resolves to
  `COMPOSE_PROFILES= docker compose -f compose.yaml -f
  compose.pilot.yaml up -d --build app asterisk db` (hardcoded empty,
  ignoring the inherited value entirely).
- `COMPOSE_PROFILES=dev make -s pilot-config` (live, not a dry run) →
  output contains zero `provider:` service blocks — exercised by the
  automated suite below (check 3) and confirmed manually.
- `env -u COMPOSE_PROFILES docker compose config --services` and plain
  `docker compose config --services` (this session's shell has no
  `COMPOSE_PROFILES` set) produced identical output — confirms
  `COMPOSE_PROFILES=""` and an unset `COMPOSE_PROFILES` are equivalent
  to Compose, so `up`'s recipe (`COMPOSE_PROFILES="$(FIXTURE_PROFILE)"`,
  empty by default) behaves exactly like an unset variable in the
  default case, not like some third, surprising state.

`FIXTURE_PROFILE` itself is never exported into the ambient shell
environment by any recipe — it is consumed purely at Make-parse-time to
construct one `COMPOSE_PROFILES=` prefix on one command line, so it
cannot leak into a suite script invoked afterward in the same recipe
(confirmed: `scripts/regression.sh`, run as a later line in
`regression`'s own recipe, executes in an environment with no
`COMPOSE_PROFILES` set at all, regardless of what `FIXTURE_PROFILE` was
for the preceding `up` line).

---

## PILOT-CONFIG PROOF

```
$ make pilot-config | grep -c "provider:"
0
$ make pilot-config | grep -A20 "asterisk:" | grep -A20 "ports:"
    ports:
      - mode: ingress
        target: 5060
        published: "5060"
        protocol: udp
      - mode: ingress
        target: 5060
        published: "5060"
        protocol: tcp
      - mode: ingress
        target: 8089
        published: "8089"
        protocol: tcp
      - mode: ingress
        target: 10000
        published: "10000"
        protocol: udp
      ... (200 RTP ports total, 10000-10199)
```

Matches TASK-0034B's own established contract exactly — this task did
not reopen RTP range sizing.

---

## PILOT-UP PROOF

```
$ make pilot-up
...
 Container mag-pbx-asterisk-1 Recreated
 Container mag-pbx-app-1 Recreated
...
$ docker compose ps -a --format 'table {{.Service}}\t{{.State}}'
SERVICE    STATE
app        running
asterisk   running
db         running
$ docker port mag-pbx-asterisk-1 | wc -l
406
$ docker port mag-pbx-asterisk-1 | grep -c 5038
0
$ docker port mag-pbx-db-1 | grep -c 3306
0
```

---

## FOCUSED FIXTURE-ISOLATION TEST

New: `scripts/compose-profile-isolation-smoke-test.sh` /
`make compose-profile-isolation-smoke`. Pure `docker compose ... config`
inspection (plus one live `make pilot-config` invocation to exercise the
real Makefile recipe directly) — never starts, stops, or mutates any
container, volume, or file, so it has no `up` dependency and runs first
in `scripts/regression.sh`, alongside `lint`/`harness-lib-selftest`.
Proves, in order: (1) the default base config excludes `provider`; (2)
the pilot overlay excludes `provider`/AMI/DB and the RTP range still
matches `10000-10199`, not `10000-20000`; (3) `make pilot-config` resists
an inherited `COMPOSE_PROFILES=dev`; (4) `COMPOSE_PROFILES=dev` and
`=test` each explicitly include `provider`. Ran live standalone: **8/8
PASS**. Also included and passing inside both full regression runs
below.

---

## SECURITY REGRESSION

No authorization, authentication, CSRF, SQL-parameterization, shell-
escaping, path-validation, or output-encoding boundary was touched.
Every security suite in the canonical regression set (`preauth-security`,
`sql-security`, `residual-sql-security`, `shell-security`,
`pjsip-config-security`, `api-security`, `api-sql-security`,
`session-csrf-security`, `auth-hardening-security`,
`disclosure-path-security`, `legacy-maintenance-exposure-security`,
`authorization-coverage`, `authorization-smoke`) passed unchanged in
both regression runs below.

---

## PRODUCTION FILES CHANGED

`git diff --name-only` after this task's implementation:

- `compose.yaml` — `provider` gains `profiles: [dev, test]`; base-
  contract header comment added. **PLATFORM**.
- `Makefile` — `FIXTURE_PROFILE` variable; `dev-up` and
  `compose-profile-isolation-smoke` new targets; `up`/`config` read
  `FIXTURE_PROFILE`; `pilot-config`/`pilot-up` hardcode
  `COMPOSE_PROFILES=` empty; `trunk-smoke`/`pjsip-runtime-status-smoke`/
  `readiness-smoke`/`regression` gain `FIXTURE_PROFILE = test`; `.PHONY`
  updated. **PLATFORM**.
- `scripts/compose-profile-isolation-smoke-test.sh` (new). **TEST**.
- `scripts/regression.sh` — one new `run_suite` line. **TEST**.
- `scripts/doctor.sh` — `check_container` annotates the `provider`-
  specific `SKIP`/running messages; classification logic (PASS/WARN/
  FAIL) unchanged for every service and every state. **PLATFORM**.
- `docs/operations/production-release-runbook.md` — provider/CH-3 notes
  updated to reflect the structural gate; explicit warning against
  `COMPOSE_PROFILES`/`FIXTURE_PROFILE` on a pilot host. **DOCUMENTATION**.
- `docs/tasks/0034-release-readiness-production-pilot-gate.md` — new
  "UPDATE (TASK-0034C)" section; CH-3 moves to CLOSED. **DOCUMENTATION**.
- `docs/tasks/0034c-production-fixture-compose-profile-isolation.md`
  (this document, new). **DOCUMENTATION**.

No application/PHP file was touched — this is a pure platform/Compose/
Makefile/documentation change, matching the task's own scope boundary.

---

## REGRESSION PROOF

Two consecutive `make regression` runs, no manual repair/reset between
them, against the same dev stack (provider present via `regression`'s
own `FIXTURE_PROFILE=test`):

- Run 1: **39/39 PASS** (38 pre-existing suites + the new
  `compose-profile-isolation-smoke`), clean.
- Run 2 (first attempt): killed mid-`trunk-smoke` by the harness's own
  low-memory protection (`SIGTERM`, exit 15) — the same pre-existing
  host-load class already documented in TASK-0027/TASK-0033E1/
  TASK-0034A/TASK-0034B (this host runs several unrelated long-lived
  Docker projects continuously). All four containers remained healthy
  afterward, no crash loop, no orphaned process found. Treated as
  `BLOCKED`, not counted, disclosed rather than hidden.
- Run 2 (retry, immediate, no manual reset — each suite's own built-in
  leftover-fixture detection/cleanup handled the interrupted
  `trunk-smoke` run's partial fixtures): **39/39 PASS**, clean.

Runs 1 and the retry together satisfy the "two consecutive clean
regression runs" gate, per this project's own established precedent for
this exact flake class.

Canonical suite count is 39, not 38, because this task legitimately adds
one new suite (`compose-profile-isolation-smoke`) — the 38 pre-existing
suites are otherwise unchanged and all still present, in the same
relative order, with the new suite inserted early (alongside
`lint`/`harness-lib-selftest`, its natural place given it has no
container-state dependency).

Additional canonical gates, both runs: `make lint` PASS (5/5); `make
doctor` PASS, 0 FAIL (`provider` correctly `SKIP` when absent, `PASS`
with an explicit fixture-active annotation when a prior `dev-up` left it
running); `make secrets-check` MATCH; `make migrate-check`
SCHEMA_CURRENT; `make reconcile-check` IN_SYNC; `git diff --check` clean;
`git status --short` matching exactly this task's own CHANGES.

---

## REMAINING DEBT

- `FOLLOW_UP_DEBT`: `docker compose down`/`restart` are not
  profile-aware (Compose's own documented behavior — they operate on
  whatever containers already exist for the project, regardless of
  current profile activation). This is pre-existing Compose semantics,
  unrelated to this task's fix, and not a CH-3-class risk (it cannot
  *start* a fixture that isn't already running) — noted for completeness
  only.
- `FOLLOW_UP_DEBT`: no `make preflight` target exists yet (TASK-0034 §7
  already recorded this). A future `preflight` could add a read-only
  "development fixture active" check (`docker compose ps provider`) as
  one more line-item; not added here since no such target exists to
  extend, and `make doctor`'s own `provider`-specific annotation already
  gives an operator the same visibility today (Phase 27).
- `FOLLOW_UP_DEBT` (reconfirmed, unchanged from TASK-0034B): the
  200-port RTP default and the Docker-Desktop-specific port-publishing
  limitation it works around remain unvalidated against the project's
  actual Debian 14/Docker Engine production target. Not reopened by
  this task.

---

## VALIDATION

`make lint` PASS (5/5); two consecutive clean `make regression` runs,
39/39 both times (one disclosed, uncounted, pre-existing-class host-load
`BLOCKED` retry in between — see REGRESSION PROOF); `make doctor`
PASS/0 FAIL (both fixture-absent and fixture-active states exercised);
`make secrets-check` OVERALL: MATCH; `make migrate-check`
SCHEMA_CURRENT; `make reconcile-check` IN_SYNC; `git diff --check`
clean (exit 0); `git status --short` — exactly the 6 modified + 2 new
paths listed in PRODUCTION FILES CHANGED, no unrelated files.
`make pilot-config`/`make pilot-up` re-verified against the isolation
change; host exposure (5060/udp, 5060/tcp, 8089/tcp, 10000-10199/udp)
reconfirmed unchanged; AMI/DB reconfirmed unpublished; no fixture volume
found to leak into production state.

## RECOMMENDATION

APPROVE. CH-3 is genuinely, structurally closed — the target invariant
("development fixtures require explicit development/test opt-in;
production/pilot never includes them by default") holds for every
Compose invocation this task could construct, including a deliberately
contaminated shell environment and `--force-recreate`, not merely for
the documented `make` targets.
