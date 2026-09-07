# TASK-0034B — Production Network Exposure Hardening

## LEAD

senma-docker-platform-engineer

## REVIEWERS

senma-application-architect (Makefile/runbook operational-safety implications), senma-telephony-architect (RTP range / PJSIP transport reachability contract)

## SCOPE

Close TASK-0034 Finding CH-7 (no SIP/WSS/RTP host port exposure defined
anywhere in the repository) — the single highest-priority remaining
production-pilot blocker after TASK-0034A closed CH-1, selected per the
priority order in the task instructions (production configuration/
exposure class, and the last PILOT_CONSTRAINT-classified finding besides
CH-2/CH-3/CH-6/CH-9's already-accepted constraints).

**In scope**: an additive Compose override publishing the actually-seeded
PJSIP transports and RTP media range to the host; the RTP range's actual
size; Makefile/runbook wiring to invoke it safely; verifying that
wiring doesn't get silently undone by other canonical operational
commands.

**Out of scope**: adding a `tls` transport (not seeded by default, an
admin-configured choice — CH-7's own text already says so); a Compose
`profiles:` gate to stop `provider` from starting on plain `make up`
(pre-existing CH-3 debt, not reopened or re-scoped here); any PJSIP/
dialplan/application code change (none was needed — this is a pure
platform/network-exposure fix).

---

## ORIGINAL RELEASE FINDING

TASK-0034, Finding CH-7 (`docs/tasks/0034-release-readiness-production-pilot-gate.md:547`):

> No SIP/WSS host port exposure defined anywhere. `compose.yaml` never
> publishes any Asterisk port to the host. A pilot needs this added
> (compose override or explicit `ports:` addition) before real external
> calls are possible; purely a runbook/deployment-topology gap, not a
> code defect.

Classified `PILOT_CONSTRAINT`. Priority class: production configuration/
exposure (order-5 in the TASK-0034B routing instructions) — the highest
remaining item once CH-1 (order-4, core telephony/call) was closed by
TASK-0034A; CH-2/CH-3/CH-6/CH-9 were already accepted, documented
constraints rather than unaddressed gaps.

## REPRODUCTION

Confirmed via `docker compose config` on the unmodified `compose.yaml`:
only the `app` service publishes a host port (`8080`). `asterisk`
declares no `ports:` key at all — `pjsip show transports` inside the
container correctly shows `udp`/`tcp`/`wss` bound to `0.0.0.0`, but
nothing on the host's own network interfaces forwards to them. A real
external SIP client cannot reach this deployment no matter how it is
otherwise configured.

## ROOT CAUSE

Deployment-topology gap, not an application defect: the project's own
`compose.yaml` is deliberately internal-only for development (correct —
`make dev`/`make up` should never expose telephony ports just to run the
app locally), and no separate production/pilot overlay had been created
yet to add that exposure additively.

## PILOT CONTRACT

| | CURRENT (before this task) | TARGET (this task) |
|---|---|---|
| SIP UDP/TCP 5060 | Not published | Published via `compose.pilot.yaml` |
| WSS 8089 | Not published | Published via `compose.pilot.yaml` |
| RTP media | Not published (dev range 10000-20000 in `rtp.conf`, irrelevant with nothing published) | Published, narrowed to 10000-10199 (200 ports) in both `rtp.conf` and `compose.pilot.yaml` |
| AMI 5038 / DB 3306 | Not published | Still not published (unchanged, correctly excluded) |
| `provider` fixture | Starts on plain `make up` | Never started by `make pilot-up`; must also never be (re-)started by `make migrate-check`/`secrets-check`/`reconcile-check`/`lint` run against a pilot host |
| Dev workflow (`make dev`/`make up`) | No ports beyond 8080 | **Unchanged** — `compose.pilot.yaml` is additive-only |

Acceptance: a pilot operator can run `make pilot-up` and reach SIP/WSS/
RTP from outside the Docker host, without needing hand-written
`docker run`/one-off `ports:` edits, and without that exposure being
silently reverted by any other documented operational command.

## CHANGES

All `PLATFORM`/`DOCUMENTATION` — no application or telephony code
changed.

- **`compose.pilot.yaml`** (new). Additive Compose override. Publishes
  `5060/udp`, `5060/tcp`, `8089/tcp`, and `10000-10199/udp` on the
  `asterisk` service only. Deliberately excludes AMI (5038) and the
  database (3306). Deliberately does not add `provider` to any service
  list. Extensive header comment records the RTP-range incident
  (below) as the reason the range is 200 ports, not the dev default.
- **`snep/install/etc/asterisk/rtp.conf`**. `rtpstart`/`rtpend` narrowed
  from `10000`/`20000` to `10000`/`10199`, with a comment cross-
  referencing this doc and `compose.pilot.yaml`, and an explicit note
  that the two files must be kept in sync.
- **`Makefile`**. Added `pilot-config` (prints the merged, two-file
  config for review) and `pilot-up` (`up -d --build` restricted to
  `app asterisk db`, explicitly never `provider`) targets. Added two
  new opt-in variables, `COMPOSE_FILES ?=` and `SERVICES ?=` (both
  empty by default), and changed only the `up:` recipe to
  `$(COMPOSE) $(COMPOSE_FILES) up -d --build $(SERVICES)` — see
  the second finding below for why.
- **`docs/operations/production-release-runbook.md`**. Step 2's
  provider-fixture note now points at `make pilot-up`. New paragraph
  documenting that `compose.yaml` alone exposes nothing and
  `compose.pilot.yaml`/`make pilot-config`/`make pilot-up` is the
  supported way to get pilot exposure. Step 4 (certificates) gained an
  explicit "do this before step 5" warning, since `make pilot-up` is
  what first makes the WSS fixture certificate genuinely
  internet-reachable (CH-2 interaction). Step 5 changed from `make up`
  to `make pilot-up` plus the `COMPOSE_FILES`/`SERVICES` export
  instructions. Preflight, Upgrade procedure, and Rollback procedure
  sections all updated with the same export requirement, since each
  contains an `up`-dependent command that would otherwise silently
  revert a running pilot.
- **`docs/tasks/0034-release-readiness-production-pilot-gate.md`**. New
  "UPDATE (TASK-0034B)" section (see that file); CH-7's original
  finding text left untouched, per documentation policy.

## PRODUCTION-LIKE PROOF

- `make pilot-config`: confirmed the merged configuration publishes
  exactly `5060/udp`, `5060/tcp`, `8089/tcp`, and `10000-10199/udp` on
  `asterisk`, and nothing else changes for `app`/`db`.
- `docker compose -f compose.yaml -f compose.pilot.yaml up -d asterisk`:
  container recreated and became `healthy` in ~25 seconds total (vs. a
  confirmed multi-minute hang and a real host memory-exhaustion
  incident with the original 10,001-port range — see below).
  `docker port mag-pbx-asterisk-1` showed exactly 406 host-port mapping
  lines (5060 udp/tcp ×2 families + 8089 tcp ×2 + 200 RTP ports ×2
  families), matching the intended range precisely (first and last
  entries: `10000/udp`, `10199/udp`).
- `asterisk -rx "core show version"` and `pjsip show transports` both
  responded correctly against the pilot-configured container (`tcp`/
  `udp`/`wss` all bound to `0.0.0.0`, unchanged from dev).
- Host-level reachability proof (the actual new capability under test):
  `nc -zv 127.0.0.1 5060` (tcp) and `8089` (tcp) both succeeded; UDP
  send checks succeeded against `5060`, `10000`, and `10199` (the exact
  boundaries of the published RTP range). AMI (5038) and DB (3306)
  confirmed absent from the merged config's published-ports list.

## THE RTP-RANGE INCIDENT (first-class finding)

Publishing the full dev-default RTP range (`10000-20000`, 10,001
individual host ports) via `docker compose -f compose.yaml -f
compose.pilot.yaml up -d asterisk` was tried first, and is recorded here
because it directly shaped the final design, not as a narrative aside:

- The container hung in `Created` state for many minutes; subsequent
  `docker compose ps`/`exec`/`kill`/`rm -f` each hung for minutes;
  host free memory collapsed (`vm_stat` showed free pages down to
  roughly 64-81MB), and the harness's own low-memory protection killed
  several unrelated Bash invocations during the incident.
- `docker ps -a` (raw, bypassing `docker compose`) eventually showed the
  container itself had started successfully after ~17 minutes with all
  10,001 ports correctly recorded — the problem was specifically Docker
  Desktop's own port-publishing/proxy mechanism (on macOS, a per-port
  userspace forwarding process/thread) degrading under that many
  individual mappings, not the container or Asterisk itself.
- Recovery required two `osascript -e 'quit app "Docker"'` cycles (the
  first only cycled the GUI shell, confirmed via backend process start
  times unchanged from six days prior), `pkill -f com.docker`, and a
  genuine cold boot — which itself stalled for 16+ minutes (confirmed
  via the VM console log timestamp gap and the backend log's repeated
  `"cannot toggle VM OTel collector, backend is not running"` line)
  before recovering **on its own**, with every container on the host —
  this project's and two unrelated long-running ones — restarted
  automatically via restart policies, no data loss.
- Conclusion acted on: macOS Docker Desktop cannot practically publish
  a 10,001-individual-port range. The RTP range published to a pilot
  host must be small. 200 ports (10000-10199, ~100 simultaneous calls
  at 2 ports/call) was chosen as a generous first-pilot capacity number,
  documented as adjustable (widen both `rtp.conf` and
  `compose.pilot.yaml` together) if real usage requires more — ideally
  re-validated on the pilot's actual target OS/container runtime
  (Debian 14 + Docker Engine, per the project's stated production
  target), which may not share this specific Docker Desktop limitation.

## THE up-TARGET EXPOSURE-REVERSAL FINDING (second first-class finding)

Discovered while validating the fix, not part of the original CH-7 text:
`make migrate-check`, `make secrets-check`, `make reconcile-check`, and
`make lint` all declare a plain `up` prerequisite. Running any of them
after `make pilot-up` — confirmed live — re-runs `docker compose up -d
--build` with no file/service qualification, which:

1. Recreates `asterisk` to match the narrower base `compose.yaml`,
   **stripping the pilot's published SIP/WSS/RTP ports** (silently
   reopening CH-7), and
2. **Starts the `provider` dev-only trunk-simulator fixture** (the
   thing CH-3 and this runbook explicitly say must never run in
   production), because the base file's default service list includes
   it and `up`'s recipe passes no service filter.

This is not a hypothetical: it was reproduced exactly as described,
twice (once via `reconcile-check`, once via `migrate-check`), each time
confirmed via `docker port`/`docker ps` before and after. Since the
runbook this task authored explicitly instructs an operator to run
`make doctor`/`make migrate-check`/`make reconcile-check` immediately
after `make pilot-up` (steps 6-8), and again in the Preflight/Upgrade/
Rollback sections, leaving this unfixed would mean CH-7's own fix
defeats itself on the very next documented step — squarely
`REQUIRED_FOR_CURRENT_TASK`, not follow-up debt.

**Fix**: two new Makefile variables, `COMPOSE_FILES ?=` and
`SERVICES ?=`, both empty by default (`make -n up` confirmed
byte-identical output with no export — `docker compose up -d --build`,
unchanged). The `up:` recipe alone was changed to
`$(COMPOSE) $(COMPOSE_FILES) up -d --build $(SERVICES)`. A pilot
operator exports both once per shell session
(`COMPOSE_FILES="-f compose.yaml -f compose.pilot.yaml"`,
`SERVICES="app asterisk db"`); every `up`-dependent target then
transparently matches `pilot-up`'s own behavior. Re-verified live: with
both exported, `make reconcile-check`, `make migrate-check`, `make
secrets-check`, and `make lint` all ran successfully, `asterisk` kept
its 406 published-port mappings throughout, and `provider` never
started. `make doctor` was already safe as-is (its script only ever
runs `ps`/`exec`/`config` against whatever is already running, never
`up`).

`docs/operations/production-release-runbook.md` was updated at every
point this matters: step 5 (initial export instruction), step 7/8
(reference back to it), Preflight, Upgrade procedure, and Rollback
procedure (both of which end in a bare `make up` that would otherwise
silently downgrade a live pilot on every subsequent release/rollback).

## SECURITY/OPERATIONS IMPACT

- No new host-exposed attack surface beyond what CH-7 itself always
  intended to close: SIP/WSS/RTP, matching this repository's actually-
  seeded transports. AMI and the database remain correctly unpublished.
- Reinforces, rather than weakens, CH-2's existing WSS-certificate
  warning: the runbook now explicitly states that `make pilot-up` is
  the moment the fixture certificate becomes genuinely
  internet-reachable, and that step 4 (real certificate) must precede
  it.
- Closes a previously-undocumented risk of unintentionally exposing a
  production host to the `provider` dev fixture and of silently
  reverting the pilot's own network-exposure fix via routine,
  runbook-documented commands — see the finding above.
- No authorization, authentication, CSRF, validation, SQL
  parameterization, or output-encoding boundary was touched; none of
  the canonical security regression suites needed any change.

## REGRESSION PROOF

Two consecutive `make regression` runs against the normal (non-pilot)
dev stack, 38/38 both times:

- Run 1: 38/38 PASS, clean.
- Run 2 (first attempt): killed mid-`call-smoke` by the harness's own
  low-memory protection (`SIGTERM`, exit 15) — this specific host runs
  several unrelated long-lived Docker projects continuously and is a
  known source of host-load-contention flakes (same class already
  documented in TASK-0027/TASK-0033E1/TASK-0034A). No orphaned
  containers/processes found afterward; treated as `BLOCKED`, not
  counted, and not silently reported as a pass.
- Run 2 (retry): 38/38 PASS, clean. Two consecutive clean runs
  achieved.

Suite count (38) is unchanged from TASK-0034A's baseline — no new
regression suite was added in this task, since the fix is pure platform
configuration, already adequately proven by the production-like proof
above plus the existing `call-smoke`/`trunk-smoke`/etc. suites
continuing to pass unmodified against the (unaffected) dev topology.

Additional canonical gates, all against the normal dev stack:

- `make lint`: PASS (5/5 checks).
- `make doctor`: PASS, no FAIL lines (containers healthy, PJSIP
  `IN_SYNC`, secrets `MATCH`, schema `CURRENT`, certificate valid).
- `make secrets-check`: `OVERALL: MATCH`.
- `make migrate-check`: `SCHEMA_CURRENT`.
- `make reconcile-check`: `status: IN_SYNC`.
- `git diff --check`: clean, exit 0.
- `git status --short`: exactly the four expected paths (`Makefile`,
  `docs/operations/production-release-runbook.md`,
  `snep/install/etc/asterisk/rtp.conf` modified;
  `compose.pilot.yaml` new/untracked). No unrelated files.

All of the above (`lint`/`migrate-check`/`secrets-check`/
`reconcile-check`) were additionally re-run once each with
`COMPOSE_FILES`/`SERVICES` exported against the pilot-configured stack,
specifically to prove the second finding's fix — see that section for
results.

## TASK-0034 DISPOSITION

CH-7 moves from `PILOT_CONSTRAINT` to **PILOT_SUPPORTED (with a
documented, adjustable RTP capacity limit of ~100 simultaneous calls at
the default 200-port range)**. See the "UPDATE (TASK-0034B)" section
added to `docs/tasks/0034-release-readiness-production-pilot-gate.md`.
No other CH finding's status changes.

## REMAINING DEBT

- `FOLLOW_UP_DEBT`: CH-3's own pre-existing gap (`compose.yaml` has no
  `profiles:` gate to stop `provider` from starting on a plain, non-
  pilot `make up`) is unchanged by this task — `pilot-up`'s explicit
  service list already avoids it for the documented pilot path, and the
  `COMPOSE_FILES`/`SERVICES` fix closes the specific way it could leak
  through the check targets, but the underlying compose-level gate
  itself remains a documented, not-yet-implemented improvement.
- `FOLLOW_UP_DEBT`: the 200-port RTP default has not been load-tested
  against a real ~100-concurrent-call pilot; it is a reasoned starting
  estimate (2 ports/call), not a measured ceiling. Re-validate against
  actual pilot traffic and widen if needed.
- `FOLLOW_UP_DEBT`: the Docker-Desktop-specific port-publishing
  limitation discovered here has not been re-tested against the
  project's actual stated production target (Debian 14 + Docker
  Engine), which may not share it — worth a lighter-weight confirmation
  before assuming the 200-port number is a hard technical ceiling
  rather than a macOS-development-environment artifact.
- `FOLLOW_UP_DEBT`: if a pilot adds a `tls` transport via the
  Transports UI (not seeded by default), its port must be published in
  a pilot-specific copy of `compose.pilot.yaml` tailored to that
  choice — already noted inline in that file's own header comment.

## VALIDATION

See PRODUCTION-LIKE PROOF, REGRESSION PROOF, and SECURITY/OPERATIONS
IMPACT above. Summary: `PASS` on `make lint`, two consecutive clean
`make regression` (38/38, one intervening host-load `BLOCKED` attempt
disclosed and not counted), `make doctor`, `make secrets-check`, `make
migrate-check`, `make reconcile-check` (each re-verified in both dev and
pilot-variable-exported modes), `git diff --check`, `git status --short`
(exactly the expected four paths).

## RECOMMENDATION

APPROVE_WITH_CONSTRAINTS. CH-7 is genuinely closed and validated; the
qualifier reflects the two logged `FOLLOW_UP_DEBT` items above (the
200-port RTP default is a reasoned estimate, not a load-tested ceiling,
and the Docker-Desktop-specific port-publishing limitation that drove it
has not been re-confirmed against the project's actual Debian 14/Docker
Engine production target) — real, but non-blocking, capacity/
environment caveats on an otherwise complete fix, not unfinished work.
