# TASK-0034F — Production AMI ACL Scoping (closing TASK-0034 Finding CH-6)

## LEAD

`senma-asterisk-pjsip-engineer` (routed by `senma-workflow-orchestrator`).

## REVIEWERS

`senma-telephony-architect` (trust-boundary/network-model decision),
`senma-docker-platform-engineer` (dedicated Compose network, health/
readiness interaction), `senma-application-architect` (app-side
`ASTERISK_HOST`/`ip_sock` consumption, no controller/API/security-
boundary change). Consulted via their domain rules/lenses during this
task; no separate agent sessions were spawned.

---

## ORIGINAL CH-6

From `docs/tasks/0034-release-readiness-production-pilot-gate.md`
(preserved verbatim, not rewritten):

> **CH-6 — AMI ACL subnet is a single flat CIDR.** Already-classified
> pre-existing debt (TASK-0033E); reconfirmed as PILOT_CONSTRAINT, not a
> blocker, for this pilot's single-instance topology (§37).

And §37 (Production AMI ACL proof), also preserved verbatim:

> `ASTERISK_AMI_ACL_SUBNET` is parameterized (not hardcoded) via `.env`,
> substituted into `manager.conf` at entrypoint time, fails fast if
> unset. Confirmed working for the single-instance topology this project
> runs (`permit=172.28.0.0/16`, `deny=0.0.0.0/0.0.0.0`). Limitation:
> single flat CIDR only, and it implicitly trusts every container on the
> same Docker bridge network, not just `app` — a real gap only if
> unrelated containers share that same user-defined network (unlikely by
> Compose's own per-project network naming).
>
> **Classification: PILOT_CONSTRAINT**, not a blocker — the mechanism
> works correctly for the single-instance topology this pilot actually
> runs. Runbook requires setting `ASTERISK_AMI_ACL_SUBNET` explicitly to
> match the deployment's real network, not assuming the dev default.

And the original TASK-0033E debt entry it traces back to
(`docs/tasks/0033e-readiness-contract-hardening.md`, REMAINING DEBT #2):

> **`ASTERISK_AMI_ACL_SUBNET` is not parameterizable independently of
> the network's own pinned subnet** without an explicit Compose
> override — only surfaced because this task's own fresh-install proof
> needed an isolated network. No operational impact on the
> single-instance topology this project actually runs; noted as a minor
> test-ergonomics gap, not a product defect. `FOLLOW_UP_DEBT`.

**What TASK-0034 actually reconfirmed live, and what this task adds.**
TASK-0034's own §37 proof was accurate as far as it went (the CIDR is
parameterized, not hardcoded, and fails closed if unset), but its "real
gap only if unrelated containers share that same user-defined network"
caveat undersold the actual exposure on THIS project's own topology:
`mag` is not a network `db`/`provider` merely *might* share — TASK-0034
CH-3's own provider fixture and the core `db` service are permanently on
it by design (general connectivity — HTTP publishing, DB access, ODBC,
trunk-simulator SIP). A single flat `permit=172.28.0.0/16` therefore
ACL-trusts them for AMI too, not because of any accident, but as a
direct, structural consequence of `mag` being one shared network for
every service. This task's own Phase 15/16 negative-proof requirement
(provider and DB must not gain AMI trust merely by sharing a network) is
exactly the property the OLD flat ACL could not have satisfied — see
NEGATIVE PROOF below for the live before/after evidence.

**Disposition: CH-6 is CLOSED.** See RISK CLASSIFICATION and PILOT PROOF
below for the live evidence.

---

## CURRENT AMI TOPOLOGY

**Bind:** `manager.conf`'s `[general]` section sets `bindaddr = 0.0.0.0`
inside the `asterisk` container — every interface the container has
(both `mag` and the new `senma-control` network below). Narrowing WHO
may actually use the listener is the ACL's job, not the bind address's
(see BIND-ADDRESS SCOPE below).

**Port:** 5038/tcp, container-to-container only. Not present in
`compose.yaml`'s or `compose.pilot.yaml`'s `ports:` for any service —
confirmed live (5038-HOST-PUBLICATION PROOF below).

**Username/secret:** templated at container first boot from
`AMI_USER`/`AMI_PASSWORD` (`.env`) by `docker/asterisk-entrypoint.sh`,
never hardcoded. Rotation is TASK-0033C's existing contract
(`make rotate-ami-password`), unchanged by this task — see SECRET
ROTATION COMPATIBILITY below.

**ACL (this task's change):** `permit=` now targets a dedicated,
`internal: true` Compose network, `senma-control` (172.29.0.0/24),
joined only by `app` and `asterisk` — not `mag` (172.28.0.0/16, shared
by `app`/`asterisk`/`db`/`provider`). `deny=0.0.0.0/0.0.0.0` is
unchanged (deny-all baseline, `permit=` is the one narrowing carve-out).

**Reload behavior:** `asterisk -rx "manager reload"` re-reads
`manager.conf`'s ACL live, without restarting Asterisk or affecting
active calls — live-proven both by TASK-0033C's pre-existing
`AMI_PASSWORD` rotation path and, specifically for the `permit=`/`deny=`
lines, by this task (RELOAD/RESTART PROOF below).

---

## CALLER INVENTORY

Every AMI client in the repository, classified. No production caller is
`UNKNOWN`.

| Caller | Runs in | Classification | Notes |
|---|---|---|---|
| `snep/lib/Asterisk/AMI.php` / `snep/lib/PBX/Asterisk/AMI.php` (SENMA's own `Asterisk_AMI` client — raw TCP `fsockopen`, never AMI-over-HTTP) | `app` | PRODUCTION_REQUIRED | The one underlying client class every PHP caller below goes through. Connects to `setup.conf`'s `ip_sock` value (templated from `ASTERISK_HOST`) — not `127.0.0.1`, not a hardcoded name. |
| `SystemstatusController.php`, `TrunksController.php`, `PjsipTransportsController.php`, `ip_status_peers.php`, `ip_status_trunks.php`, `ip_status_queues.php`, `AsteriskInfo.php`, `ConferenceRoomsController.php` | `app` | PRODUCTION_REQUIRED | Runtime status/diagnostics UI (TASK-0029B's own established graceful-degradation contract governs app-side behavior when AMI is unreachable — unchanged by this task). |
| `snep/lib/Snep/Pjsip/Reconciler.php`, `PjsipConf.php`, `PjsipTrunkConf.php`, `PjsipTransportConf.php`, `InterfaceConf.php` | `app` | PRODUCTION_REQUIRED | TASK-0033B's own DB→PJSIP reconciliation/apply path (`make reconcile`, `make reconcile-check`). |
| `snep/lib/Snep/Asterisk/Operations.php` | `app` | PRODUCTION_REQUIRED | Shared AMI action helper used by the controllers above. |
| `snep/modules/callback/actions/CallbackAction.php` | `app` | PRODUCTION_REQUIRED | Callback/originate feature. |
| `docker/entrypoint.sh` (app) | `app` | PRODUCTION_REQUIRED | Templates `setup.conf`'s `ip_sock` from `ASTERISK_HOST` at first boot — not an AMI client itself, but the source of the hostname every PHP caller above resolves. |
| `docker/asterisk-entrypoint.sh` | `asterisk` | PRODUCTION_REQUIRED | Templates `manager.conf`'s `permit=`/`secret=` at first boot; validates `ASTERISK_AMI_ACL_SUBNET` (this task, Phase 29). |
| `docker/healthcheck-asterisk.sh` | `asterisk` | PRODUCTION_REQUIRED | Docker `HEALTHCHECK`, every 10s — self-connects over `ASTERISK_HOST` (this task; previously `$(hostname)`, ambiguous once the container joined a second network). |
| `scripts/doctor.sh` (`make doctor`) | host, via `docker compose exec` | PRODUCTION_REQUIRED | Operator diagnostic — `AMI reachable` (pre-existing) + `AMI network ACL` (this task, Phase 34). |
| `scripts/rotate-secrets.sh` / `scripts/secrets-check.sh` (`make rotate-ami-password`, `make secrets-check`) | host, via `docker compose exec` | PRODUCTION_REQUIRED | TASK-0033C's own secret-rotation/consistency contract, via `scripts/lib/secrets-lib.sh`'s `slib_ami_auth_check`. |
| `scripts/ami-acl-migrate.sh` (`make ami-acl-migrate`, this task) | host, via `docker compose exec` | PRODUCTION_REQUIRED | Existing-install migration path — see ACL GENERATION / MIGRATION below. |
| `scripts/lib/secrets-lib.sh` (`slib_ami_auth_check`) | shared library | PRODUCTION_REQUIRED | Used by both of the two production commands directly above; not a standalone caller. |
| `scripts/ami-acl-smoke-test.sh` (`make ami-acl-smoke`, this task) | host, via `docker compose exec`, from `app`/`db`/`provider` containers | TEST_ONLY | New regression suite (see FOCUSED ACL TEST below). |
| `scripts/doctor-smoke-test.sh`, `readiness-smoke-test.sh`, `secrets-consistency-smoke-test.sh`, `readiness-failure-smoke-test.sh`, `doctor-failure-smoke-test.sh`, `secret-rotation-smoke-test.sh`, `db-migration-smoke-test.sh`, `compose-profile-isolation-smoke-test.sh` | host, via `docker compose exec` (from `app`/`asterisk`) | TEST_ONLY | Pre-existing regression suites that already call the production paths above; none open an independent AMI connection from an unauthorized network position. |

No `DEVELOPMENT_ONLY` or `OBSOLETE` AMI caller was found.

---

## CURRENT ACL

Before this task (live-captured, TASK-0034 §37's own recorded value):

```text
bindaddr = 0.0.0.0
permit=172.28.0.0/16      ; = the shared "mag" network -- app, asterisk, db, provider
deny=0.0.0.0/0.0.0.0
```

After this task (live-captured, this pilot's default):

```text
bindaddr = 0.0.0.0
permit=172.29.0.0/24      ; = the dedicated "senma-control" network -- app, asterisk ONLY
deny=0.0.0.0/0.0.0.0
```

---

## RISK CLASSIFICATION

**Before this task: `DOCKER_NETWORK_WIDE`.** `permit=172.28.0.0/16`
ACL-trusted every container Compose could ever place on the `mag`
network — structurally including `db` and `provider`, not merely as a
theoretical edge case. Not `HOST_WIDE` or `PUBLICLY_REACHABLE` (5038 was
never host-published — confirmed both before and after this task, see
5038-HOST-PUBLICATION PROOF) and not `MULTI_NETWORK` (only one Docker
network was ever in play).

**After this task: still `DOCKER_NETWORK_WIDE` in category, but the
network it targets is now single-purpose.** `permit=172.29.0.0/24`
covers exactly the dedicated `senma-control` network, whose only two
members, by Compose definition, are `app` and `asterisk` — the two
services this project's own architecture requires to speak AMI. This
satisfies the task's own least-privilege target ("AMI is reachable only
from explicitly authorized SENMA control-plane sources... not any
container/host/subnet that happens to be nearby") without depending on
convention alone: `senma-control` is `internal: true` (no external
gateway routing) and structurally excludes `db`/`provider`, which remain
on `mag` only.

5038 is confirmed **not** host-published, before and after (PILOT
BLOCKER condition does not apply).

---

## TRUST BOUNDARY

**Chosen model: `DEDICATED_CONTROL_PLANE_NETWORK`** — the preferred
option named by this task's own Phase 7, and the only one of the four
candidates (`APP_CONTAINER_NETWORK_ONLY`, `DEDICATED_CONTROL_PLANE_NETWORK`,
`LOOPBACK_PROXY`, `STATIC_TRUSTED_SUBNET`) that satisfies the
requirement without a brittle or higher-blast-radius mechanism:

- `APP_CONTAINER_NETWORK_ONLY` (narrow `permit=` to a `/32` for `app`'s
  own address) was rejected: Docker container IPs on a bridge network
  are not guaranteed stable across recreate, and this task's own Phase 8
  explicitly rules out hardcoding an ephemeral container IP.
- `LOOPBACK_PROXY` (a local proxy/socat relay bound to loopback inside
  the `asterisk` container) was rejected as unjustified complexity — it
  would require a new runtime process and a new failure mode for a
  problem Compose's own network primitive already solves natively.
- `STATIC_TRUSTED_SUBNET` (narrow `permit=` on the EXISTING `mag`
  network to some sub-range) was rejected: every container on one Docker
  bridge network draws its address from the SAME subnet allocator —
  there is no sub-range within `mag` that includes `app`/`asterisk` and
  excludes `db`/`provider` without depending on allocation order, which
  Compose does not contractually guarantee.
- `DEDICATED_CONTROL_PLANE_NETWORK` — a second, `internal: true` Compose
  network joined only by the two services that need it — makes the
  trust boundary structural (who CAN be on the network) rather than
  merely a CIDR-math coincidence (who HAPPENS to fall in a sub-range).

---

## NETWORK MODEL

```text
mag (172.28.0.0/16)              senma-control (172.29.0.0/24, internal: true)
├── app          172.28.0.5      ├── app          (client only, no alias)
├── asterisk     172.28.0.4      └── asterisk     172.29.0.2  (alias: senma-ami)
├── db           172.28.0.x
└── provider     172.28.0.x
```

`asterisk` is the only service on both networks (it must be reachable
by `app` for AMI over `senma-control`, and by `app`/`db`/`provider` over
`mag` for HTTP-published trunk registration, ODBC, and trunk-simulator
SIP — none of which this task changes). `manager.conf`'s `bindaddr =
0.0.0.0` means Asterisk listens for AMI on BOTH interfaces
(172.28.0.4:5038 and 172.29.0.2:5038) — the ACL, not the bind address,
is what makes only the second one actually usable. See BIND-ADDRESS
SCOPE below for why this combination is correct, not merely tolerated.

`db` and `provider` are **not** joined to `senma-control` — this is the
actual isolation mechanism (PROVIDER ISOLATION / DB ISOLATION below),
not merely the ACL.

`ASTERISK_HOST=senma-ami` (`.env`) is the one name every authorized AMI
caller in this codebase now resolves — `app`'s own AMI client (via
`setup.conf`'s `ip_sock`), `healthcheck-asterisk.sh`'s self-check, and
`scripts/lib/secrets-lib.sh`'s `slib_ami_auth_check`. The bare `asterisk`
Compose service name still resolves (unrelated traffic — WSS-certificate
verification, `make shell`, `docker compose exec` — is unaffected, since
that addresses the container at the Docker Engine level, not via this
DNS alias) but must never be used for AMI: a connection made via that
name/address leaves `mag`, not `senma-control`, and is correctly
ACL-rejected.

---

## ACL GENERATION

**Single source of truth, one generation path (Phase 19/Phase 10):**
`docker/asterisk-entrypoint.sh` templates `manager.conf`'s `permit=`
line from `ASTERISK_AMI_ACL_SUBNET` (`.env`) — the ONLY place that
value is written into `manager.conf`. `docker/entrypoint.sh` (app)
templates `setup.conf`'s `ip_sock` from `ASTERISK_HOST` the same way.
Both are `FIRST_BOOT_SEED`: templated once (`if [ ! -f
"$ASTERISK_ETC/asterisk.conf" ]` / the app entrypoint's equivalent
first-boot guard), never touched again by a later `docker compose up`,
`--force-recreate`, or plain `.env` edit — matching TASK-0033C's own
established precedent for this exact class of file (`AMI_PASSWORD`'s
`secret=` line has the identical first-boot-only behavior, which is why
`rotate-ami-password` exists as a dedicated reconciliation path rather
than "just edit `.env`").

**CIDR validation** (Phase 28/29), in `docker/asterisk-entrypoint.sh`,
runs before either templated value is written:

1. `: "${ASTERISK_AMI_ACL_SUBNET:?...}"` — unset fails fast with a
   named-variable error.
2. A plain IPv4-CIDR-shape check (`[0-9]*.[0-9]*.[0-9]*.[0-9]*/[0-9]*`)
   — not a full octet-range validator by design (Phase 29's own scope:
   catch "not a CIDR at all", not become a general network-config
   linter) — rejects a malformed value with an explicit `FATAL` line.
3. `0.0.0.0/0` is rejected unless `AMI_ACL_ALLOW_UNSAFE_SUBNET=1` is
   also set — a documented, dev-only escape hatch, never a pilot/
   production default.

All three rejection paths, plus the two acceptance paths (a valid CIDR,
and `0.0.0.0/0` with the explicit override), are live-proven — see
CIDR VALIDATION LIVE PROOF below.

**Safe default (Phase 30):** `.env.example` ships
`ASTERISK_AMI_ACL_SUBNET=172.29.0.0/24` / `ASTERISK_HOST=senma-ami` —
matching `compose.yaml`'s own pinned `senma-control` subnet/alias out of
the box. A fresh `cp .env.example .env && make dev` lands on the narrow,
internal-only configuration with zero operator Docker-networking
knowledge required. Operators only need to touch either value if they
have also edited `compose.yaml`'s `senma-control` subnet (e.g. to
resolve a collision with an existing host network) — `make doctor`'s
"AMI network ACL" check (Phase 34, below) and `make ami-acl-smoke`
detect a mismatch between the two either way.

**Migration (Phase 31), for an installation that already has both files
first-boot-seeded with the OLD `mag`-network values:** `scripts/
ami-acl-migrate.sh` (`make ami-acl-migrate`) reconciles the values
currently declared in `.env` into `manager.conf`'s `permit=` and
`setup.conf`'s `ip_sock`, on an existing installation, without a
destructive volume reset. It reuses `scripts/lib/secrets-lib.sh`'s own
`slib_remote_template_line` — the exact same atomic,
backed-up-then-verified templating helper `rotate-secrets.sh`'s own
`rotate_ami_password()` already uses for the `secret=`/`pass_sock=`
lines — rather than a second, hand-rolled mechanism (Phase 19's own "one
generation path" rule). Idempotent (`ALREADY_CURRENT` if nothing to do);
rolls back both files automatically if post-migration live AMI
verification fails. See ACL GENERATION LIVE PROOF (MIGRATION) below.

**Bug found and fixed during this task's own validation:**
`ami-acl-migrate.sh`'s original precondition gated on the `asterisk`
container being Docker-`healthy` before it would run — but on exactly
the installation this command exists for, `asterisk` is correctly
`unhealthy` until the migration completes (its own healthcheck now
authenticates over the new `senma-ami` path, which the not-yet-migrated
ACL legitimately rejects). This made the command unable to fix the one
situation it was written for — a real deadlock, reproduced live
(REQUIRED_FOR_CURRENT_TASK, not follow-up debt: it is a direct
consequence of this task's own new code). **Fixed**: the precondition
now checks the container is `Up` (running; `docker compose exec` only
needs this, confirmed live), not `healthy` — the real post-migration
correctness gate (live AMI re-verification, with automatic rollback) was
already present and unchanged.

---

## POSITIVE PROOF (authorized caller)

From the `app` container, over `$ASTERISK_HOST` (`senma-ami`), a real
AMI login followed by `Action: Ping`:

```text
Response: Success|ActionID: proof-1|Ping: Pong|Timestamp: 1788888537.952085||
```

Also independently confirmed via `scripts/lib/secrets-lib.sh`'s own
`slib_ami_auth_check` helper (the same one `make doctor`/`make
secrets-check` use): `MATCH`.

---

## NEGATIVE PROOF (unauthorized callers)

**`db` (mag-only, not joined to `senma-control`):**
- Cannot resolve `senma-ami` at all (`getent hosts` fails — not on that
  network, full stop).
- A correct-credential login attempt against `asterisk`'s OTHER, still-
  reachable `mag`-network address (`bindaddr = 0.0.0.0` listens there
  too) is rejected purely on ACL grounds:
  `Response: Error|Message: Authentication failed`.

**`provider` (mag-only, not joined to `senma-control`):** identical
result to `db` — cannot resolve `senma-ami`; correct-credential login
against the `mag` address rejected with the same generic
`Authentication failed`.

**Loopback, from inside the `asterisk` container itself
(`127.0.0.1:5038`):** also rejected —
`Response: Error|Message: Authentication failed`. Confirms the ACL
grants no implicit localhost trust; only the `senma-control` subnet is
permitted.

**Host (Docker host machine):** connection refused —
`ConnectionRefusedError(61, 'Connection refused')` — 5038 is not
listening on any host-reachable interface at all (see
5038-HOST-PUBLICATION PROOF).

**Before-this-task comparison (why this matters, not just "ACL says
no"):** repeating the `db`/`provider` login attempt against the OLD
`permit=172.28.0.0/16` value (temporarily reproduced live, then
reverted) succeeds — `Response: Success|Message: Authentication
accepted`. This is the concrete, live-reproduced difference CH-6's
closure rests on: the same correct-credential connection from `db`/
`provider` goes from ACCEPTED to REJECTED purely as a result of this
task's ACL/network change, nothing else.

**MANAGER ACL SEMANTICS (Phase 11):** Asterisk returns the SAME generic
`Authentication failed` message for both an ACL-driven rejection and a
genuinely wrong secret — it does not distinguish the two on the wire (a
deliberate, correct choice: it does not leak which factor failed to an
unauthenticated-so-far connection). This is why `check_asterisk_ami`'s
pre-existing `make doctor` line alone ("AMI reachable") cannot serve as
ACL-scope evidence — see DOCTOR/RELEASE GATE below for the dedicated
check this task adds specifically to close that gap. `deny=` then
`permit=` is evaluated per-connection; a source address failing the
`permit=` list is treated as an auth failure at the manager-ACL layer
before Asterisk's own credential check ever reports a distinct outcome
(consistent with the "ACL denied before authentication" preference this
task's own Phase 16 states).

---

## RELOAD/RESTART PROOF

**`manager reload`:** `permit=` line unchanged before/after; a fresh
authorized login immediately after reload still succeeds. Exercised
twice — once as part of `ami-acl-migrate.sh`'s own post-change
verification, once as a standalone step in `scripts/
ami-acl-smoke-test.sh`.

**Scoped `asterisk` container restart** (`docker compose restart
asterisk`): `permit=` line unchanged after restart (confirms
`manager.conf` is genuinely first-boot-seeded, not regenerated); a fresh
authorized login succeeds; ODBC/CDR are recovered via the shared
`harness_restore_asterisk_post_restart` helper (the same TASK-0033E1
recovery contract every other suite that restarts this container already
relies on).

**Full `docker compose up -d --force-recreate asterisk`:** exercised
live during this task's own validation (recovering from the stale-image
condition below) — `permit=` line, once migrated, survives recreation
unchanged (the volume, not the container, is what's authoritative for
this first-boot-seeded file).

**Operational note (not a defect, but worth recording for the
runbook):** `manager.conf`/`healthcheck-asterisk.sh`'s BEHAVIOR only
changes on a rebuilt image (`docker/healthcheck-asterisk.sh` is `COPY`'d
into the image at build time, not bind-mounted) — `docker compose up -d`
without `--build` on an already-built host leaves a stale healthcheck
script running even though the compose network topology itself updates
immediately (network membership is container-level config, not baked
into the image). `make up`'s own recipe already always passes `--build`,
so this is invisible on the documented developer/operator path; it was
only visible here because of an ad hoc `docker compose up -d` (no
`--build`) used during this task's own manual investigation.

---

## DOCTOR/RELEASE GATE

**`make doctor`** gains a new, dedicated **"AMI network ACL"** line
(Phase 34), deliberately separate from the pre-existing "AMI reachable"
line (see MANAGER ACL SEMANTICS above for why one check cannot serve
both purposes):

- `FAIL` if 5038 is host-published.
- `FAIL` if `permit=0.0.0.0/0` (or the legacy `0.0.0.0/0.0.0.0` spelling).
- `PASS` if `permit=` matches the dedicated control-plane network's own
  live-inspected subnet (identified by the `senma-ami` alias contract,
  not by a project-name-derived network name, which is not guaranteed
  stable — Phase 27's own "use `docker network inspect`, not compose.yaml
  text alone" instruction).
- `FAIL` if `permit=` matches a DIFFERENT, shared network the asterisk
  container is also attached to (the exact old-broad-ACL regression this
  task closes) — reported by name, e.g. "matches the SHARED 'mag-pbx_mag'
  network... every service on that network is ACL-trusted, not just the
  authorized caller".
- `WARN` if `permit=` matches neither (an intentional custom topology
  this check cannot itself validate — needs a human).
- `SKIP`/`UNKNOWN` if the asterisk container isn't running/reachable yet.

Live-verified all four reachable branches (`PASS`, the two `FAIL`
variants, and the broad-network `FAIL`) by temporarily reproducing each
`permit=` value and reverting — see the live evidence captured during
this task's own checkpoint validation.

No secret value is read or reported by this check (it only reads the
`permit=` line and network metadata, matching the existing "AMI
reachable" check's own secret-safety contract).

---

## PILOT PROOF

Under the base `compose.yaml` (this pilot's actual supported topology —
`compose.pilot.yaml` only adds SIP/WSS/RTP host publication per
TASK-0034B, it does not touch AMI):

- `app → AMI`: allowed (POSITIVE PROOF above).
- `db`/`provider` → AMI: denied (NEGATIVE PROOF above); `provider` is
  additionally Compose-profile-gated (TASK-0034C, CH-3) and absent
  entirely from a plain `docker compose up`/`make pilot-up`.
- 5038: not host-published, under either `compose.yaml` alone or
  `compose.yaml` + `compose.pilot.yaml` (`compose.pilot.yaml` publishes
  only 5060/udp+tcp, 8089/tcp WSS, and the RTP range — confirmed by
  inspecting its own `ports:` list; it adds no `5038` entry).

**Dev/test topology:** `provider`'s own profile gate (`dev`/`test`) is
unaffected by this task. When `provider` IS started (`make dev-up`/
`make regression`'s own `FIXTURE_PROFILE=test`), it still only ever
joins `mag`, never `senma-control` — this task adds no code path that
would put it there, and `scripts/ami-acl-smoke-test.sh` (which runs
inside `make regression`) asserts this every run, not just once.

---

## REMAINING DEBT

1. **CIDR validation is shape-only, not a full IPv4 semantics
   validator** (Phase 29's own explicit scope boundary — deliberate, not
   an oversight). A value like `999.999.999.999/24` would pass the shape
   check and only fail later, opaquely, inside Asterisk's own config
   parser. `FOLLOW_UP_DEBT` if a concrete operator-facing confusion ever
   demonstrates a real need for stricter validation.
2. **No IPv6 consideration** — this project's Docker networking is
   IPv4-only throughout (pre-existing, unchanged by this task; the
   original `manager.conf` comment already notes bindaddr was
   deliberately narrowed from legacy `[::]` for this reason).
3. **`senma-control`'s subnet is a second pinned value an operator could
   still let drift from `.env`'s `ASTERISK_AMI_ACL_SUBNET`** if they hand-
   edit `compose.yaml` without also updating `.env` (or vice versa) —
   `make doctor`'s new check and `make ami-acl-smoke` both detect this
   live (they read the actual Docker network, never compose.yaml text
   alone), so a drift cannot pass release gates silently, but nothing
   currently prevents the drift from being introduced in the first
   place. `FOLLOW_UP_DEBT` — a single-source-of-truth mechanism (e.g.
   deriving one value from the other at `make up` time) was considered
   and deferred as unjustified complexity for a single-instance pilot
   topology (Phase 10's "avoid... without detection" bar is met by
   detection, which this task provides; true derivation was not judged
   worth the added indirection yet).

No `PILOT_BLOCKER` or `OPEN_CONSTRAINT` remains from this task's own
scope. CH-6 is CLOSED.
