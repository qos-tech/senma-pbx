# TASK-0033E — Readiness Contract Hardening

Status: implemented and validated against a live, already-provisioned
installation plus isolated fresh-install/failure-injection projects.
Lead: `senma-docker-platform-engineer`. Reviewers:
`senma-telephony-architect` (Asterisk/PJSIP/AMI/WSS readiness
invariant), `senma-application-architect` (DB/app readiness boundary).
`senma-product-designer` not invoked -- readiness state is not exposed
in any new admin workflow, only via `docker compose ps`/`make doctor`
(already existing operator surfaces).

This task closes the boundary TASK-0033D deliberately left open: SENMA
had no formal distinction between a container being RUNNING, HEALTHY,
and actually READY to perform the operations SENMA depends on.
TASK-0028V's historical PJSIP startup race is the proof this was not
theoretical.

---

## DEPENDENCY GRAPH

| Service | Dependency | Required capability | Classification |
|---|---|---|---|
| `app` | `db` | Schema + app-credential auth (setup.conf generation, bootstrap-admin.php, virtually every page) | `HARD_STARTUP_DEPENDENCY` |
| `app` | `asterisk` | None at startup -- TASK-0029B's graceful degradation (runtime status -> UNKNOWN, admin UI stays usable) | `RUNTIME_OPTIONAL_DEPENDENCY` |
| `asterisk` | `db` | ODBC/CDR remain runtime-optional to core telephony (confirmed: `asterisk-entrypoint.sh` never blocks on DB; `res_pjsip` loads regardless of ODBC state) -- **but a Compose *ordering* gate is required regardless**, corrected below | `RUNTIME_OPTIONAL_DEPENDENCY` (CDR only) at the capability level; `HARD_STARTUP_ORDERING_DEPENDENCY` at the Compose level (see COMPOSE DEPENDENCY GATES) |
| `asterisk` | `provider` | None -- `provider` is a local dev trunk-simulator fixture, never a startup dependency | `TEST_ONLY_DEPENDENCY` |
| tests (regression suites) | `app` + `db` + `asterisk` PJSIP | Full stack readiness before exercising product flows | `TEST_ONLY_DEPENDENCY`, unchanged by this task (see TEST-HARNESS INTERACTION) |

Confirmed by direct inspection of `docker/entrypoint.sh`,
`docker/asterisk-entrypoint.sh`, and live behavior -- not assumed from
`compose.yaml` alone.

---

## RUNNING/HEALTHY/READY MODEL

```text
RUNNING  -> the container's PID 1 process exists (docker compose ps State=running)
HEALTHY  -> Docker's own healthcheck currently passes
READY    -> HEALTHY, by this task's own deliberate mapping (see below)
```

**Decision (Phase 14): HEALTHCHECK = READINESS, for all three core
services.** Compose exposes exactly one health status per container;
inventing a second, Compose-invisible readiness signal would be an
unused parallel implementation Compose itself cannot consume (`depends_
on: condition: service_healthy` only ever looks at the ONE health
status). Each of the three dedicated scripts below (`docker/
healthcheck-{db,app,asterisk}.sh`) IS the readiness check, not a
liveness ping with readiness bolted on elsewhere.

`STARTING`/`DEGRADED`/`FAILED`/`UNKNOWN` map onto Docker's own health
states: `starting` (within `start_period`), a container reporting
`unhealthy` while `State=running` (`DEGRADED`/`FAILED` -- SENMA does
not currently need a distinction Docker itself doesn't expose), and
`UNKNOWN` for `docker compose ps` itself being unreachable (Docker
daemon down, `make doctor`'s own `Docker daemon` check already covers
this, TASK-0033D).

---

## DB READINESS CONTRACT

`docker/healthcheck-db.sh` (bind-mounted into the stock `mariadb:10.11`
image -- no custom Dockerfile, per CLAUDE.md's preference for official
images):

1. `mariadb-admin ping` as **root** (preserves TASK-0033C's own secret-
   rotation fail-fast contract, which depends on this exact healthcheck
   already authenticating with the current declared
   `DB_ROOT_PASSWORD`).
2. The **application credential** (`MARIADB_USER`/`MARIADB_PASSWORD`)
   authenticates.
3. `core_config` table exists in `MARIADB_DATABASE`.

No filesystem flag was introduced (Phase 4) -- `docker-entrypoint-
initdb.d` semantics already guarantee the schema import completes
before MariaDB starts accepting external connections at all on first
boot, so "accepts a connection" plus "the marker table exists" is
already sufficient, real DB-state evidence.

---

## APPLICATION READINESS CONTRACT

`docker/healthcheck-app.sh`: `curl` the login page and assert its
known `<title>SNEP - Login</title>` content signature. Live-confirmed
(both in this task and reproducing TASK-0033's own finding): with `db`
stopped, a bare socket check would still see an HTTP response (just a
500) -- the login page's own rendering already depends on reading
company/system settings from the database, so a successful render is
real evidence PHP bootstrapped AND reached the database, not just that
Apache is listening. No dedicated readiness endpoint was added -- the
existing page is already safe (unauthenticated, read-only, no side
effects), cheap, and stable enough for this purpose.

---

## ASTERISK READINESS CONTRACT

`docker/healthcheck-asterisk.sh` -- the most important contract in this
task, closing TASK-0028V directly:

1. `core show version` responds.
2. `res_pjsip.so` reports `Running`.
3. **Every transport declared in the generated `senma-pjsip-
   transports.conf`** (parsed locally, no DB round-trip) is confirmed
   bound in live `pjsip show transports` output. An install with zero
   provisioned transports (fresh install) trivially satisfies this --
   nothing is required that isn't actually declared.
4. AMI authenticates (see AMI CLASSIFICATION).
5. **Conditionally**, only if a `wss` transport is declared: HTTP
   server reports enabled (see WSS CLASSIFICATION).

Deliberately excluded: ODBC (see ODBC CLASSIFICATION), and requiring
`provider` (or any external trunk) to be registered (Phase 7's own
explicit instruction).

---

## PJSIP READINESS (minimal invariant, Phase 8)

```text
core CLI available
+ res_pjsip.so Running
+ every SENMA-managed transport declared in config is actually bound
+ AMI operational
+ HTTP/WSS operational, but ONLY if wss is declared
```

Cost: transport comparison reads one local file (`senma-pjsip-
transports.conf`) and one CLI query (`pjsip show transports`) -- no DB
access, no PHP bootstrap, no per-endpoint dump. This does NOT reuse
`scripts/lib/harness.sh`'s `pjsip_modules_running`/`harness_retry`
directly (that is a host-side bash library with no presence inside the
container); the same small, proven primitive (module-Running check)
was reimplemented natively in the healthcheck script itself, per this
task's own Phase 10 instruction ("prefer extracting/reimplementing...
rather than calling a test script").

**Reproduced the TASK-0028V class of defect deterministically**, not by
racing a timing window (a live restart on this project's own warm dev
box converges in well under a second, making the original race
impractical to reliably re-trigger): declared an extra transport in
`senma-pjsip-transports.conf` that was never actually loaded --
`healthcheck-asterisk.sh` correctly reported `FAIL: expected
transport(s) not loaded: fake-missing-transport` every time, and
recovered the instant the file was restored. This is a structural
guarantee (the check explicitly compares expected vs. actual), not a
timing-dependent one -- it cannot report READY without both conditions
actually holding, regardless of how narrow or wide any given boot's
real race window is.

---

## AMI/WSS/ODBC CLASSIFICATION

| Dependency | Classification | Rationale |
|---|---|---|
| **AMI** | Required for READY (failure = `NOT_READY`, container `unhealthy`) | AMI is core to SENMA's own operational contract, not just telephony: runtime status (TASK-0029B), apply verification (TASK-0033B's own `module reload`-via-AMI apply path), diagnostics, and `make reconcile` all depend on it. This is a DIFFERENT question from TASK-0029B's app-side graceful degradation -- that governs how the *application* behaves when AMI is unreachable from its side; this governs whether *Asterisk itself* should claim to be ready when the capability a large part of SENMA's own product depends on doesn't work. Live-verified: AMI failure -> `healthcheck-asterisk.sh` FAIL -> Docker reports `unhealthy` within the tuned window -> recovers automatically once restored. |
| **WSS/HTTP** | Required for READY, but **only when a `wss` transport is actually declared** | Conditional, not universal -- an install with no WSS transport configured is never penalized for a capability it doesn't use. Live-verified: with `wss` declared, disabling the HTTP server -> FAIL -> recovers once re-enabled; TLS cert/key confirmed byte-identical (sha256) throughout, never touched by the check or the recovery. |
| **ODBC** | `DEGRADED`, NOT `NOT_READY` | The only current ODBC consumer is CDR (`cdr_adaptive_odbc`, confirmed in TASK-0033). CDR failure does not prevent SENMA from processing calls -- overstating it as total PBX failure would be wrong per this task's own Phase 13 instruction. Deliberately excluded from `healthcheck-asterisk.sh`'s pass/fail gate; `odbc show all` remains available as a `make doctor`/manual diagnostic (TASK-0033D), unchanged by this task. |

---

## HEALTHCHECK IMPLEMENTATION

Dedicated scripts, not inline Compose shell (Phase 36):
`docker/healthcheck-db.sh` (bind-mounted, stock `mariadb:10.11`),
`docker/healthcheck-app.sh` and `docker/healthcheck-asterisk.sh` (baked
into their respective images via `COPY`, matching the existing
`log-rotate-*.sh` convention from TASK-0033D). `provider` (a TEST_ONLY
fixture, Phase 1) gets a minimal inline `CMD-SHELL` (CLI + `res_pjsip`
Running only -- no AMI is even configured for it) rather than a
dedicated file, since it needs none of the DB-driven transport/AMI/WSS
logic the real `asterisk` service does.

---

## COMPOSE DEPENDENCY GATES

- `app -> db`: **`condition: service_healthy`** (unchanged) -- app's
  own bootstrap hard-needs the database.
- `app -> asterisk`: **changed from `service_healthy` to
  `service_started`** (Phase 18). `app` has no hard startup dependency
  on Asterisk being READY; TASK-0029B's already-proven graceful
  degradation means coupling app's own readiness to Asterisk's would be
  architecturally wrong, not just unnecessary. `service_started` keeps
  a sane default container-start ORDER for `make up` without blocking
  on Asterisk's full readiness. Live-verified: on a full recreate, app
  now starts as soon as Asterisk is merely `Starting`/`Started`, not
  waiting for it to be `Healthy`.
- `asterisk -> db`: **`condition: service_healthy`, added** (corrected
  during validation, superseding an earlier draft decision in this same
  task to leave it absent). The capability-level classification is
  unchanged -- ODBC/CDR remain `RUNTIME_OPTIONAL_DEPENDENCY` and stay
  deliberately excluded from `healthcheck-asterisk.sh`'s pass/fail gate
  (Asterisk does not need `db` to be READY to be READY itself). But
  `res_odbc.so` makes exactly ONE connection attempt, during Asterisk's
  own module-load sequence, and does **not** auto-reconnect afterward
  (the same non-auto-reconnect behavior this doc's FAILURE
  TRANSITIONS/RECOVERY TRANSITIONS section documents for destructive
  `db` restarts). With no Compose ordering gate at all, `asterisk` and
  `db` start in parallel, and this is not a theoretical race: **3/3 live
  simultaneous-cold-start trials** (`docker compose down && docker
  compose up -d`, no staggering) reproduced Asterisk losing that race
  and ending up with `Number of active connections: 0` permanently --
  breaking every CDR write from first boot onward with nothing
  surfacing it operator-side, since the call itself completes normally
  and ODBC is intentionally outside the healthcheck. A staggered control
  (start `db` alone, wait for Docker-healthy, then start `asterisk`)
  connected cleanly every time. Adding `depends_on: db: condition:
  service_healthy` to `asterisk` and re-running the same simultaneous
  cold-start trial **3/3 times** produced a clean ODBC connection every
  time, with Asterisk's own healthy-convergence unchanged at 14-15s
  (`db` converges well inside Asterisk's existing 15s `start_period`, so
  the gate adds no observable startup cost on this hardware). This is
  purely an ordering fix for Asterisk's own one-shot initial connection
  attempt -- it does not reintroduce a hard runtime dependency, and
  Asterisk still starts and stays healthy with `db` stopped afterward
  (see FAILURE TRANSITIONS). The original "no dependency" decision was
  reasoned from entrypoint-script inspection alone and missed
  `res_odbc`'s own non-retrying connect-once behavior; corrected here
  per this project's evidence-over-assumption rule rather than
  preserved for consistency with an earlier, now-disproven draft.

---

## TIMEOUT/RETRY MODEL

| Service | interval | timeout | retries | start_period | Grace before `unhealthy` |
|---|---|---|---|---|---|
| `db` | 5s | 3s | **10** (was 30) | 20s | ~50s (was ~150s) |
| `app` | 10s | 5s | **6** (was 10) | 15s | ~60s (was ~100s) |
| `asterisk` | 10s | 5s | **6** (was 10) | 15s | ~60s (was ~100s) |

**Retries lowered across all three, with measured justification**: the
pre-existing values were tuned when each check was a bare liveness
ping, where generous tolerance made sense (an occasional transient
socket hiccup is not a real problem). Now that each check verifies
actual capability (schema, PHP+DB, PJSIP+AMI+WSS), a genuine failure is
not a transient condition more retries would help ride out -- it stays
FAIL until something is actually fixed, so a shorter window only
delays the operator finding out, without buying real stability.
`start_period` values are **unchanged** and were confirmed still
correct against live measurement: a full fresh-install cold start (see
FIRST BOOT below) converges the entire four-service stack in
**~13-14 seconds**, comfortably inside the existing 15s/20s
`start_period` margins.

---

## FAILURE TRANSITIONS / RECOVERY TRANSITIONS

All live-verified against the real dev stack (or an isolated throwaway
project for the DB-schema case), each fully restored before moving to
the next scenario:

| Scenario | Detection | Recovery |
|---|---|---|
| DB schema missing (isolated project, `core_config` dropped) | `healthcheck-db.sh`: `FAIL: schema not ready` immediately, on demand | N/A (isolated project torn down, never restored -- disposable by design) |
| `db` stopped | `app` -> `unhealthy` within ~56s (measured); container stays `running`, never process-dead | `docker compose start db` -> `db` healthy in ~7s -> `app` healthy in ~3s more, **no recreate** |
| `asterisk` stopped | `app` stays **healthy** throughout (TASK-0029B contract preserved, confirmed over 2+ minutes) | `docker compose start asterisk` -> healthy in ~6s |
| Asterisk PJSIP transport mismatch (deterministic TASK-0028V reproduction) | `healthcheck-asterisk.sh`: `FAIL: expected transport(s) not loaded` immediately | Restoring the file -> READY immediately, no restart |
| AMI secret corrupted | `FAIL: AMI login did not succeed` immediately; Docker `unhealthy` within ~51-60s | `manager reload` after restoring `manager.conf` -> healthy again, no restart |
| WSS listener disabled | `FAIL: wss transport declared but HTTP server not enabled` immediately; Docker `unhealthy` within the tuned window | `module reload http` after restoring `http.conf` -> healthy again; TLS cert/key sha256 confirmed unchanged throughout |

---

## FIRST BOOT

Measured in a fully isolated Compose project (own network/volumes,
`docker compose -p senma-fresh-test ... up -d`, torn down afterward --
the main dev stack was never touched): **the entire four-service stack
(db, asterisk, provider, app) reached `healthy` in ~13-14 seconds** from
container creation on a completely fresh set of volumes. `app`'s own
healthcheck passed within ~6-8s of ITS OWN start (gated behind `db`
being healthy first, per the preserved hard dependency).

## EXISTING BOOT

The main dev stack (hours of real uptime, real persisted state)
consistently converges in the same ~7-20s range on `--force-recreate`
or `restart` -- persisted schema/transports/certs mean there is
materially less to converge on than first boot.

## RECREATE/RESTART

`docker compose up -d --force-recreate` and `docker compose restart`
(both full-stack) were each run multiple times during this task's own
validation (including immediately after the destructive failure-
injection proofs) and converged deterministically to healthy every
time. TASK-0033A/B/C's own persistent-state contracts were re-verified
intact after each: `make doctor`/`make secrets-check` both reported
clean.

## FRESH-INSTALL PROOF

Performed (Phase 22), via an isolated Compose project rather than
destroying the main one (a network-subnet override was required --
`compose.yaml` pins `172.28.0.0/16`, and Docker refuses two networks
with the same pool on one host; `ASTERISK_AMI_ACL_SUBNET` had to be
overridden to match, since it is not otherwise parameterized). Result:
identical convergence behavior to a warm/existing install, just paced
by the DB schema import and PJSIP directory/cert bootstrap rather than
by nothing -- both comfortably inside the ~13-14s window measured.

**Re-verified after the `asterisk -> db` `depends_on` gate was added**
(see COMPOSE DEPENDENCY GATES): a second isolated-project fresh-volume
run confirmed `db` reaches healthy first and `asterisk` starts and
converges to healthy immediately after (~20s total including this
project's one-time image build/cache-warm overhead, not present on the
main dev stack); the isolated `app` container itself could not fully
start in this run only because it collided with the main dev stack's
own `app` on host port 8080 (both projects publish `8080` -- a test-
environment artifact of running two stacks simultaneously, unrelated to
`depends_on`/readiness and not reproducible in normal single-stack
operation). The `db`+`asterisk` portion relevant to this gate converged
correctly. Combined with 3/3 repeated full-stack simultaneous-restart
trials on the main (warm) stack converging to healthy in 14-15s with
ODBC connected every time, there is no evidence of a meaningful timing
regression from serializing `asterisk` behind `db` instead of racing
them in parallel.

---

## SECRET SAFETY

- `docker inspect .Config.Healthcheck.Test` shows only the fixed script
  invocation (`["CMD","bash","/usr/local/bin/healthcheck-db.sh"]`,
  etc.) on all three core services -- confirmed live, never a resolved
  secret value, even for the pre-existing root-password check this task
  preserved inside `healthcheck-db.sh` (`MYSQL_PWD` env-scoped to the
  one child process, never `-p"$PASSWORD"` on an argv).
- The AMI check inside `healthcheck-asterisk.sh` feeds the credential
  over the raw socket (same technique established in TASK-0033C's
  `secrets-lib.sh`), never as a CLI argument.
- `scripts/readiness-smoke-test.sh` automates the proof: greps every
  container's `.State.Health.Log`, every healthcheck script's own
  output, AND every container's stored `.Config.Healthcheck.Test` for
  all three live secret values -- none found, confirmed passing.

---

## RUNTIME COST

Measured live, per invocation: `healthcheck-db.sh` ~120ms,
`healthcheck-app.sh` ~100ms, `healthcheck-asterisk.sh` ~95ms. Each is a
handful of CLI queries or one local file read plus one HTTP/AMI round
trip -- no PHP bootstrap beyond the single page request the app check
already needed, no full PJSIP endpoint/registration dump, no DB scan
beyond a single indexed `SHOW TABLES LIKE`. Cost does not scale with
deployment size (endpoint/trunk count) -- the transport-comparison
check scales with the number of *transports* (typically 1-3), never
extensions/trunks.

---

## TEST-HARNESS INTERACTION

**Classified, not blindly changed** (Phase 33): `scripts/lib/
harness.sh`'s `harness_require_containers` (used by ~30 smoke test
files) checks `State=running` ("Up"), a `STARTUP_READINESS`-adjacent
precondition, with its own existing bounded retry. `pjsip_modules_
running`-style checks in `call-smoke-test.sh`/`trunk-smoke-test.sh`/
`transport-smoke-test.sh` are `POST_RELOAD_CONVERGENCE` -- they guard
against a *different* suite's own PJSIP reload having just happened
moments earlier mid-regression-run, a condition container-level health
status cannot observe (Docker's healthcheck runs on its own periodic
interval, not synchronously with an application-triggered reload) and
this task's own healthchecks do not change.

**Decision: `harness_require_containers` was deliberately NOT upgraded
to require `healthy`.** Considered and rejected: the function is called
by ~30 files including its own dedicated self-test
(`harness-lib-selftest.sh`, which mocks `$COMPOSE` output textually and
would itself need updating), and the concrete benefit -- mostly
diagnostic, since suites needing genuine PJSIP/AMI readiness already
have their own specific assertions -- did not justify the blast radius
of changing shared infrastructure without a specific failure it fixes.
This is an intentional decision, not an oversight; nothing here was
deleted opportunistically.

---

## OPERATOR OBSERVABILITY

`docker compose ps` already shows the new, meaningful health status
directly (no change needed there). `make doctor` (TASK-0033D) already
surfaces the SAME `.Health` value via its own `Container: <svc>` check
and needed **zero code changes** for this integration -- confirmed live
throughout every failure-injection scenario above (`doctor` correctly
showed `[FAIL] Container: asterisk: running but unhealthy` etc. the
instant the underlying healthcheck did, and recovered automatically).
Doctor's own separate granular checks (`Asterisk CLI reachable`, `PJSIP
module loaded`, `AMI reachable`, ...) are intentionally preserved
alongside the aggregate health signal -- they answer "which SPECIFIC
condition is broken", which one pass/fail Docker health status alone
cannot.

---

## REGRESSION SPLIT

- **`scripts/readiness-smoke-test.sh`** (`make readiness-smoke`) --
  safe: all-healthy assertion, direct healthcheck-script invocation,
  AMI/WSS-are-part-of-the-invariant assertions, secret non-disclosure,
  and a full-stack `docker compose restart` convergence proof (the same
  class of operation `restart-smoke-test.sh` already runs in normal
  regression). **Included in `make regression`.**
- **`scripts/readiness-failure-smoke-test.sh`** (`make
  readiness-failure-smoke`) -- the real destructive proof: isolated-
  project DB-schema-missing, app-without-DB, the deterministic
  TASK-0028V transport-mismatch reproduction, AMI failure, WSS failure,
  each with its own recovery proof, plus a full-stack force-recreate
  convergence proof. **Deliberately NOT part of `make regression`**,
  mirroring the `secret-rotation-smoke`/`doctor-failure-smoke`
  precedent -- stopping core services and running an isolated Compose
  project on every regression run is unnecessary cost for a suite whose
  detection CONTRACT is already proven by the 9 non-mutating checks in
  `readiness-smoke-test.sh`.

---

## REMAINING DEBT

1. **`harness_require_containers` left at "Up", not "healthy"** --
   deliberate, see TEST-HARNESS INTERACTION. `FOLLOW_UP_DEBT` if a
   concrete flaky-test failure ever demonstrates a real need.
2. **`ASTERISK_AMI_ACL_SUBNET` is not parameterizable independently of
   the network's own pinned subnet** without an explicit Compose
   override -- only surfaced because this task's own fresh-install
   proof needed an isolated network. No operational impact on the
   single-instance topology this project actually runs; noted as a
   minor test-ergonomics gap, not a product defect. `FOLLOW_UP_DEBT`.
3. **ODBC has no dedicated readiness/doctor check beyond the pre-
   existing manual `odbc show all`** -- correctly excluded from the
   Asterisk healthcheck gate per its `DEGRADED` classification; a
   dedicated `make doctor` WARN-level check would be a reasonable small
   TASK-0033D-adjacent follow-up, not built here (scope boundary).
4. **No support for a fourth health state distinguishing `DEGRADED`
   from `FAILED`** -- Docker Compose exposes only `healthy`/
   `unhealthy`/`starting`, and this task did not invent a parallel
   signal Compose itself cannot consume (Phase 14's own explicit
   instruction). If a real need for finer-grained states emerges,
   `make doctor`'s own per-condition checks already provide that
   detail today.
5. **Regression suites that legitimately restart/recreate `asterisk`
   mid-run (`wss-platform-smoke`, `tls-cert-management-smoke`,
   `transport-shared-runtime-ux-smoke`, `restart-smoke`) do not reload
   `res_odbc.so`/`cdr_adaptive_odbc.so` afterward.** Discovered live
   during this task's own two-consecutive-clean-regression-run gate:
   the same one-shot, non-auto-reconnecting `res_odbc` behavior that
   motivated the `asterisk -> db` Compose gate above (item above this
   list) also applies every time Asterisk's process itself restarts,
   not only at initial cold boot -- and those four *pre-existing*
   suites restart Asterisk as part of their own normal, already-
   established operation, unrelated to anything this task added. When
   one of them runs before `trunk-smoke`/`pjsip-external-trunk-smoke`/
   `dialplan-legacy-closure` in the same or a subsequent regression
   run, those later suites' CDR assertions can fail even though the
   call itself completes correctly -- reproduced live and confirmed
   NOT caused by this task's healthcheck/`depends_on` changes (which
   touch neither dialplan, CDR, nor ODBC configuration; the affected
   suites and their restart behavior predate this task). The Compose
   `depends_on` fix above only closes the *initial* cold-start race; it
   cannot help a mid-run process restart performed by a test suite
   itself. Classified `FOLLOW_UP_DEBT`, not fixed here per this
   project's "do not fix unrelated legacy bugs opportunistically" rule
   -- the correct owner is a dedicated task adding a `res_odbc.so`/
   `cdr_adaptive_odbc.so` reload to those four suites' own restart
   logic (or their shared harness restart helper, if one is
   introduced). Operationally, this task's own validation worked
   around it by fully recreating the stack (`make down && make up`)
   between consecutive regression runs rather than relying on the
   previous run's tail-end state.

---

## VALIDATION SUMMARY

- `bash -n` on every new/modified shell script: clean.
- `docker compose config`: valid.
- Target tests: `scripts/readiness-smoke-test.sh` PASS (9/9 checks,
  included in `make regression`); `scripts/readiness-failure-smoke-
  test.sh` PASS (14/14 checks, explicit `make readiness-failure-smoke`
  target, re-verified after the `asterisk -> db` `depends_on` fix).
- `make lint`: PASS (5/5).
- `make regression` run 1 (after a full `make down && make up` cold
  recreate onto the corrected compose.yaml): **PASS, 36/36 suites**,
  including `trunk-smoke`, `pjsip-external-trunk-smoke`,
  `dialplan-legacy-closure`, and `readiness-smoke`.
- `make regression` run 2 (after a second full `make down && make up`
  cold recreate, per REMAINING DEBT item 5 above): **PASS, 36/36
  suites**. Two consecutive, fully clean regression runs achieved.
- `git diff --check`: PASS, no whitespace errors.
- `git status --short`: only this task's own files (`Makefile`,
  `compose.yaml`, `docker/app.Dockerfile`, `docker/asterisk.Dockerfile`,
  `scripts/regression.sh` modified; `docker/healthcheck-{db,app,
  asterisk}.sh`, `scripts/readiness-{smoke,failure-smoke}-test.sh`,
  this document new).
- A genuine defect was found and fixed *during* this validation, not
  merely documented: the `asterisk -> db` cold-start ODBC race (see
  COMPOSE DEPENDENCY GATES and DEPENDENCY GRAPH above) -- 3/3
  reproductions without the gate, 3/3 clean connections with it, a live
  `trunk-smoke-test.sh` CDR failure caused by it on a freshly recreated
  stack, and a live CDR-writing pass after the fix.
