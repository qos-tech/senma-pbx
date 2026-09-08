# TASK-0034G — Final Release Candidate Environment Certification

## LEAD

senma-docker-platform-engineer

## REVIEWERS

senma-workflow-orchestrator, senma-application-architect, senma-telephony-architect (consulted via their domain lenses for the release-manifest/schema/secrets and AMI-ACL/PJSIP/WSS portions respectively; no separate agent sessions were spawned — this is a single-session live certification run)

## PURPOSE

TASK-0034F closed TASK-0034's last open product constraint (CH-6, flat
AMI ACL), but its own final canonical regression ran in a sandbox where
`docker compose build app` stalled on package/image download while
host-side network access remained functional — classified there as an
environment/build-context limitation, not a SENMA product defect, but
left as the one remaining item before `TASK-0034 = COMPLETE` could be
certified with full confidence. This task is a **certification task,
not a feature task**: certify the exact release candidate (current HEAD)
in an environment capable of rebuilding the SENMA images correctly, end
to end through the full canonical release-gate chain, twice
consecutively for regression. No product/application code was expected
or intended to change; none did (see SOURCE IDENTITY / git diff-check
below).

## ENVIRONMENT

| Item | Value |
|---|---|
| Host OS | macOS 26.6.2 (Darwin 25.6.0, arm64) |
| Docker | Docker Desktop, Engine 29.1.3, VM: Docker Desktop Linux, kernel 6.12.54-linuxkit |
| Architecture | aarch64 (Apple Silicon) inside the Docker Desktop VM |
| Docker Compose | v5.0.1 |
| CPUs available to Docker | 10 |
| RAM available to Docker | ~7.65 GiB (8217448448 bytes reported) |
| Disk free (host) | 71 GiB free on the volume backing the repo/Docker data |

**This is the same class of development host TASK-0034F ran on — macOS
+ Docker Desktop, not the actual Debian 14 / Docker Engine pilot
target or a CI runner.** Explicitly not the real target; differs from
it in: host OS/kernel (macOS+linuxkit VM vs. native Debian 14 Linux),
Docker distribution (Docker Desktop vs. Docker Engine), and — the
material one, see BUILD CONNECTIVITY below — Docker Desktop's own
GUI-Keychain-backed credential helper, which a native Debian 14 Docker
Engine install does not have at all. Everything downstream of the build
(image content, OCI labels, running behavior, regression results) is
environment-independent; the one thing this document cannot certify is
"the real target's own credential/registry-access path behaves
identically," which is why the recommendation below calls that out
explicitly as a pre-go-live confirmation for whichever host actually
runs the pilot.

## SOURCE IDENTITY

```
$ git status --short
(clean)
$ git log -1 --oneline
3d3e1c4 docs(release): close CH-6 with scoped AMI control plane
$ git branch --show-current
main
```

Working tree was clean at the start of certification. TASK-0034F's
commits are present and were independently verified, not merely trusted
from the log message: `compose.yaml` defines the dedicated,
`internal: true` `senma-control` network (172.29.0.0/24), and the
Makefile registers `ami-acl-smoke`, `ami-acl-migrate`, `release-build`,
`release-info`, `release-artifact-smoke`, `pilot-config`, `pilot-up`,
`cert-check`/`wss-cert-check`, `secrets-check`, `migrate-check`,
`reconcile-check`, `readiness-smoke`, and `compose-profile-isolation-smoke`
— every target this certification exercises below.

## BUILD CONNECTIVITY

Proven, not assumed from host `curl` alone (per this task's own Phase 4
instruction):

1. **Debian package repositories, from inside a live BuildKit stage**:
   a throwaway `debian:13-slim` build running `apt-get update &&
   apt-get install -y ca-certificates curl` completed in 3.8s. PASS.
2. **Container registry — first attempt, FAILED, root-caused**:
   `docker pull hello-world` (a few KB) and `docker pull php:8.4-apache`
   (~450MB, not yet cached locally) both stalled with **zero** progress
   output for several minutes each. Host `curl` to the same endpoints
   succeeded immediately (`registry-1.docker.io`: HTTP 401 in 0.46s;
   `auth.docker.io`: HTTP 200 in 0.22s — 401/200 both prove the endpoint
   answered, not that auth succeeded), proving this was not a raw
   network-reachability problem and exactly matching this task's own
   warning not to trust host `curl` as proof of container-side
   connectivity.
3. **Isolating the actual cause**: `docker info` showed Docker Desktop's
   daemon configured with `HTTP Proxy`/`HTTPS Proxy: http.docker.internal:3128`
   and a Hub proxy at `hubproxy.docker.internal:5555` — both internal
   DNS names that resolve only inside the Docker Desktop VM (confirmed:
   `nslookup` for both timed out from the host). A running container
   using an **already-cached** image (`alpine:latest`, no pull needed)
   reached `https://registry-1.docker.io/v2/` directly in seconds (HTTP
   401 — reachable) and `https://deb.debian.org` in seconds — proving
   general container-to-internet HTTPS egress, including to the
   registry host itself, was fine. This narrowed the fault to the
   `docker pull`/`docker compose build` **credential-resolution** step
   specifically, not network egress.
4. **Root cause, directly reproduced**: `~/.docker/config.json` has
   `"credsStore": "desktop"`. A bounded direct test —
   `echo "registry-1.docker.io" | docker-credential-desktop get`,
   killed after 5s — was **still running**, confirming the helper itself
   hangs when asked to resolve credentials for a pull, even for a
   public/anonymous image. This is consistent with the helper blocking
   on a macOS Keychain/GUI-IPC round-trip that this non-interactive,
   headless automation session cannot service.
5. **Workaround validated, session-scoped, no repository or user-global
   config changed**: an isolated `DOCKER_CONFIG` directory containing
   `{"auths":{}}` (no `credsStore` key, so the CLI never invokes the
   hanging helper) plus a copy of `~/.docker/cli-plugins/*` (required —
   redirecting `DOCKER_CONFIG` also redirects where the CLI looks for
   the `compose` plugin, and the first attempt at `make release-build`
   failed with `docker: unknown command: docker compose` until this was
   copied in). With this exported, `docker pull hello-world` completed
   in ~2s and `docker pull php:8.4-apache` completed in 2.3s — both
   images that had stalled for minutes moments earlier under the
   default config.

**Classification: environment/tooling limitation of this specific
session (Docker Desktop's GUI-Keychain-backed credential helper has no
GUI/Keychain session to service in headless automation), not a SENMA
product defect.** This is the precise mechanism behind TASK-0034F's
"BuildKit network/package-download stall" finding. A native Debian 14
Docker Engine install (the actual pilot target) does not ship this
credential helper at all and would not be expected to exhibit this
failure mode; this should still be explicitly confirmed on that host
before relying on unattended `make release-build` there (see REMAINING
POST-PILOT DEBT).

## RELEASE VERSION

`v0.1.0-rc.1`, built in `RC=1` mode (no Git tag exists in this
repository yet — confirmed via `git tag -l`, empty — consistent with
TASK-0034D's own finding that a formal tagging convention is still
not established; `RC=1` is the documented, supported release-candidate path for
exactly this situation). Git revision: `3d3e1c4c46e92d74b5824eb7152205f7053531b6`
(matches HEAD, short form `3d3e1c4`).

Pre-build image inventory recorded before any rebuild (per this task's
"do not use stale images as proof" instruction): `mag-pbx-app:latest`
(`3eea194e7bc2`), `mag-pbx-asterisk:latest` (`01d71f388502`),
`senma-app:dev` (`d5049aabde85`), `senma-asterisk:dev` (`fcb932d18fec`)
— none of these IDs reappear as the certified release artifact below.

## APP ARTIFACT

```
$ make release-build VERSION=v0.1.0-rc.1 RC=1
==> Building senma-app:v0.1.0-rc.1 and senma-asterisk:v0.1.0-rc.1 from commit 3d3e1c4c46e92d74b5824eb7152205f7053531b6
...
app        senma-app:v0.1.0-rc.1    v0.1.0-rc.1      sha256:2987753bd6be2263323e72461b9c223897df510ee8c449cc932be85bf0bd3176
```

Self-verified by `release-build.sh` itself (no label-mismatch error was
raised — the script fails loudly if version/revision labels don't match
what was requested). `org.opencontainers.image.version` =
`v0.1.0-rc.1`, `.revision` = `3d3e1c4c46e92d74b5824eb7152205f7053531b6`
(both == HEAD/requested version, as required).

## ASTERISK ARTIFACT

```
asterisk   senma-asterisk:v0.1.0-rc.1 v0.1.0-rc.1      sha256:a795f23667e48238f6141b38ecbc9195a7236b91c20bb7cbcfa9d3975ef721fb
```

Same self-verification, same result: `.version` = `v0.1.0-rc.1`,
`.revision` = `3d3e1c4c46e92d74b5824eb7152205f7053531b6`. Built from
source (Asterisk 22.11.0, per `docker/asterisk.Dockerfile`'s pinned
`ASTERISK_VERSION`) — most build layers were BuildKit-cache hits
(identical Dockerfile/context/base image as a prior local build), which
is expected, correct cache reuse, not "reusing a stale image": the
final exported image ID is new and distinct from every pre-existing
image recorded above, and the label self-check independently proves it
was actually built from this exact commit/version pair, not merely
retagged.

## CROSS-IMAGE CONSISTENCY

`app.version == asterisk.version == v0.1.0-rc.1`;
`app.revision == asterisk.revision == HEAD (3d3e1c4c46e92d74b5824eb7152205f7053531b6)`.
No mixed release — `release-build.sh`'s own self-check would have
failed the build otherwise, and this was independently re-confirmed by
`release-artifact-smoke`'s own check 2 ("app/asterisk agree") later in
this run.

## MANIFEST

`release-manifest.json` (generated, gitignored — `.gitignore:31`
confirmed, never appears in `git status`):

```json
{
  "version": "v0.1.0-rc.1",
  "git_revision": "3d3e1c4c46e92d74b5824eb7152205f7053531b6",
  "dirty": false,
  "build_time": "2026-09-08T21:14:59Z",
  "app_repo_tag": "senma-app:v0.1.0-rc.1",
  "app_image_id": "sha256:2987753bd6be2263323e72461b9c223897df510ee8c449cc932be85bf0bd3176",
  "app_label_version": "v0.1.0-rc.1",
  "app_label_revision": "3d3e1c4c46e92d74b5824eb7152205f7053531b6",
  "asterisk_repo_tag": "senma-asterisk:v0.1.0-rc.1",
  "asterisk_image_id": "sha256:a795f23667e48238f6141b38ecbc9195a7236b91c20bb7cbcfa9d3975ef721fb",
  "asterisk_label_version": "v0.1.0-rc.1",
  "asterisk_label_revision": "3d3e1c4c46e92d74b5824eb7152205f7053531b6",
  "db_image": "mariadb:10.11"
}
```

No secret material present (matches the documented contract). This
exact manifest was later deliberately removed mid-certification (see
FINDING F1 under REMAINING POST-PILOT DEBT) and regenerated by
re-running the identical `make release-build` command before the
restart/force-recreate proofs — the regenerated manifest records new
image IDs (`0c10a5b8...`/`89f58bfe...`) for the same version/commit, a
direct, expected instance of TASK-0034D's own documented "BUILD
REPRODUCIBILITY BOUNDARY" (two builds of an identical commit differ in
`org.opencontainers.image.created`, hence image ID) — not a defect.

## PILOT DEPLOYMENT

Clean teardown first (`docker compose down` + an explicit
`--profile dev --profile test down` to remove the pre-existing
`provider` fixture container left running from an earlier session, so
"provider absent" would be a structural proof, not incidental), then:

```
$ RELEASE_VERSION=v0.1.0-rc.1 make pilot-up
COMPOSE_PROFILES= docker compose -f compose.yaml -f compose.pilot.yaml up -d app asterisk db
...No services to build...
```

`No services to build` confirms `pilot-up` never rebuilds — it deployed
the exact artifact `release-build` had just produced.

## RELEASE-INFO

**Pre-deployment** (containers still the pre-existing `:dev` images):
`make release-info` → `app DRIFT`, `asterisk DRIFT` (both expected
against the newly-recorded manifest, as this task's own instructions
anticipate — "If containers still run development images, DRIFT is
acceptable before the deployment step").

**Post-deployment**:

```
app        MATCH    senma-app:v0.1.0-rc.1        matches recorded release senma-app:v0.1.0-rc.1
asterisk   MATCH    senma-asterisk:v0.1.0-rc.1   matches recorded release senma-asterisk:v0.1.0-rc.1
db         THIRD_PARTY mariadb:10.11                not a SENMA release artifact
RESULT: no drift detected.
```

## NETWORK EXPOSURE

From `docker compose ps` immediately after pilot deployment:

| Port | Required state | Observed |
|---|---|---|
| 5060/udp | published | `0.0.0.0:5060->5060/udp` — PASS |
| 5060/tcp | published | `0.0.0.0:5060->5060/tcp` — PASS |
| 8089/tcp | published | `0.0.0.0:8089->8089/tcp` — PASS |
| 10000-10199/udp | published | `0.0.0.0:10000-10199->10000-10199/udp` — PASS, confirmed all 200 ports individually via `docker port` |
| 5038 (AMI) | NOT published | absent from both `docker compose ps` and `docker port asterisk` — PASS |
| 3306 (DB) | NOT published | `docker port db` returned nothing — PASS |

The full 200-port RTP range (10000-10199) published without incident on
this same class of host (macOS Docker Desktop) that TASK-0034B
documented as unable to handle the *full* 10001-port dev range —
consistent with, not contradicting, that finding (this range is exactly
the 200-port width TASK-0034B deliberately narrowed to).

## AMI ACL

`ami-acl-smoke-test.sh` requires `app asterisk db provider` all `Up`
(`harness_require_containers app asterisk db provider`), but the
`ami-acl-smoke` Makefile target — unlike its sibling provider-dependent
targets — does not set `FIXTURE_PROFILE=test`, so a bare `make
ami-acl-smoke` is **BLOCKED** ("one or more of [app asterisk db
provider] not Up"). This is a genuine, newly-discovered, narrow
Makefile-wiring gap in TASK-0034F's own target definition — see
REMAINING POST-PILOT DEBT F2; not fixed here (would be a Makefile/product
change, out of this certification-only task's scope). Worked around for
this proof using the Makefile's own existing, documented override
mechanism (no file changed): `make ami-acl-smoke FIXTURE_PROFILE=test`.

```
PASS: 9   FAIL: 0
RESULT: PASS (ami-acl-smoke-test.sh)
```

All 9 checks passed: 5038 not host-published; authorized `app` caller
authenticates; `db`/`provider` cannot even resolve the AMI alias (not
joined to `senma-control`) and are denied even with correct credentials
against Asterisk's other, still-reachable address; `manager reload` and
a full Asterisk restart both preserve the narrowed ACL.

## WSS TRUST

```
$ make cert-check PILOT=1
...
TRUST_STATE: SELF_SIGNED
PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT (no public WSS hostname configured (set WSS_PUBLIC_HOSTNAME); known fixture/test-only certificate)
```

**Expected, not a new defect.** This environment deliberately still runs
the shipped dev-fixture certificate with no `WSS_PUBLIC_HOSTNAME`
configured — exactly the pre-go-live gap TASK-0034E's own CH-2 already
documents and the production runbook already requires closing before a
real pilot go-live (install a real certificate for the pilot's actual
hostname). The *mechanism* for a trusted cert (TRUSTED/PILOT_ACCEPTABLE
classification, verified live REGISTER with real TLS verification
enabled) was separately, already proven live in TASK-0034E and is
reconfirmed by `wss-certificate-runtime-smoke`'s own PASS below (which
exercises a real ephemeral-CA-issued certificate as one of its 20
checks). This certification does not (and per its own out-of-scope list,
should not) install a real production certificate.

## REGRESSION GATES

**Focused gates run individually first** (Phase 19), all PASS:
`ami-acl-smoke` (9/9, above), `wss-certificate-runtime-smoke` (20/20),
`compose-profile-isolation-smoke` (8/8), `release-artifact-smoke`
(12/12 — see below), `readiness-smoke` (see FINDING F3 — failed 3/3
standalone on a harness timing race, PASS both times inside full
regression).

**`release-artifact-smoke` — the previously-blocked suite — PASS 12/12**:
version/revision labels present and HEAD-matching on both images;
app/asterisk agree; `release-build.sh` correctly refuses a dirty tree;
`release-info.sh` correctly reports MATCH (real values), DRIFT
(deliberately wrong manifest), and UNKNOWN (no manifest) in turn; the
third-party `db` image's absent SENMA revision label is handled, not
crashed on; synthetic mixed-version detection and non-detection both
correct; all fixtures cleaned up (dirty-tree probe removed, pre-existing
manifest restored).

`make lint`: **PASS, 5/5** (275 PHP files 0 syntax errors, 67 shell
scripts parse clean, 3 `resources.xml` well-formed, `git diff --check`
clean).

## OPERATIONAL GATES

```
make doctor          -> 0 FAIL (1 WARN: dev WSS fixture cert, already known/expected;
                         1 SKIP: no release-manifest.json present once the stack had
                         returned to plain dev `up` — expected, not a fault)
make secrets-check    -> OVERALL: MATCH (DB_PASSWORD, DB_ROOT_PASSWORD, AMI_PASSWORD,
                         all consumers)
make migrate-check    -> SCHEMA_CURRENT
make reconcile-check  -> IN_SYNC (senma-pjsip-transports.conf, senma-http-tls.conf,
                         senma-pjsip.conf, senma-pjsip-trunks.conf all in_sync)
```

**Two consecutive full regression runs, no manual repair, reset, or
teardown between them:**

| Run | Started | Finished | Result |
|---|---|---|---|
| 1 | 2026-09-08 18:41:59 -03 | 2026-09-08 18:56:58 -03 | **PASS 42/42** |
| 2 | 2026-09-08 18:57:13 -03 | 2026-09-08 19:12:05 -03 | **PASS 42/42** |

Run 2 started 15 seconds after run 1 finished (the time this session
took to read run 1's summary and re-invoke `make regression` — no
`docker compose down`, no manual DB/Asterisk/ODBC repair, no fixture
cleanup outside the harness). Suite count (42) matches TASK-0034F's own
established baseline exactly; no suite was added, removed, or skipped.

**Disclosed, not hidden** (per this project's own transparency norm —
see TASK-0034's own §46 precedent): an *earlier, uncounted* full
regression attempt in this same session failed 41/42 on `doctor-smoke`
— root-caused immediately to a stale `release-manifest.json` this
certification's own Phase 5 (APP ARTIFACT, above) had legitimately
written and never cleaned up before starting regression, which made
`doctor`'s "Release artifact identity" check correctly report `DRIFT`
against the now-differently-tagged dev containers. This is **not a
product defect** — `release-manifest.json` is a generated, gitignored
build receipt; removing it (confirmed via `git status --short` — no
effect on tracked source) and re-verifying `doctor-smoke` PASS
standalone before restarting the two-run gate from a clean baseline was
the correct, minimal remediation, not a silent product fix. The two
runs counted above are the first two, back-to-back, both clean.

## RESTART/RECREATE

Pilot redeployed a second time from a freshly-regenerated manifest
(same version/commit, new image IDs — see MANIFEST above) after the
dev/test regression cycle moved the stack off the pilot images:

```
$ RELEASE_VERSION=v0.1.0-rc.1 make pilot-up   # MATCH confirmed
$ docker compose restart app asterisk          # restart proof
$ make release-info
app        MATCH    senma-app:v0.1.0-rc.1
asterisk   MATCH    senma-asterisk:v0.1.0-rc.1
RESULT: no drift detected.
```

**Force-recreate** (`--force-recreate --no-build`, the supported
pilot-contract equivalent — no dedicated Makefile target exists for
this combination, so the documented two-file pilot invocation was used
directly with `--force-recreate --no-build` added, per the runbook's
own guidance to keep `RELEASE_VERSION` exported across the same shell):

```
$ RELEASE_VERSION=v0.1.0-rc.1 COMPOSE_PROFILES= docker compose \
    -f compose.yaml -f compose.pilot.yaml up -d --force-recreate --no-build \
    app asterisk db
```

Pre-recreate image IDs (`sha256:0c10a5b8...` app, `sha256:89f58bfe...`
asterisk) and post-recreate running image IDs were **byte-for-byte
identical** — no rebuild occurred. `make release-info` still reported
MATCH for both services afterward. `provider` remained absent; AMI
(5038) and DB (3306) remained unpublished throughout.

## FINAL PROVENANCE TABLE

| SERVICE | RELEASE VERSION | GIT REVISION | IMAGE ID | RUNNING IMAGE ID | STATE |
|---|---|---|---|---|---|
| app | v0.1.0-rc.1 | 3d3e1c4c46e92d74b5824eb7152205f7053531b6 | sha256:0c10a5b808be1687fc63d54767b16011f097023f2c80533535ebc27e0c4c3e48 | sha256:0c10a5b808be1687fc63d54767b16011f097023f2c80533535ebc27e0c4c3e48 | MATCH |
| asterisk | v0.1.0-rc.1 | 3d3e1c4c46e92d74b5824eb7152205f7053531b6 | sha256:89f58bfe581f5ac3a147119ac53f9895446d37230fcb5eaac63a7b874c7cd153 | sha256:89f58bfe581f5ac3a147119ac53f9895446d37230fcb5eaac63a7b874c7cd153 | MATCH |

(This is the second, restart/recreate-proof build generation — see
MANIFEST above for why its image IDs differ from the first APP/ASTERISK
ARTIFACT section; both generations were independently self-verified and
independently proven MATCH end to end.)

## THIRD-PARTY DB IMAGE INVENTORY

`mariadb:10.11`, image ID `sha256:ce66c7be32a03aabe7241d0a10993a2db827ef652a35d25727d92a832ac8ef73`,
carries its own unrelated `org.opencontainers.image.version=10.11.19`
label. **Classification: `THIRD_PARTY`** — never compared to or
conflated with the SENMA release version, per the existing, unchanged
contract (`release-info.sh`'s own design, TASK-0034D Phase 29).

## REMAINING POST-PILOT DEBT

- **F1 — Operator hygiene, not a defect**: a real `release-build`-produced
  `release-manifest.json` left in place while later returning to plain
  `make up`/dev-mode testing will make `doctor`'s "Release artifact
  identity" check correctly, deliberately report `DRIFT` (or, if later
  removed, `SKIP`/`UNKNOWN`) rather than silently ignoring the mismatch —
  this is the documented, intended strictness of `release-info.sh`, not
  a bug. Recommend a one-line addition to the runbook or `pilot-up`'s own
  header comment noting that a release-build receipt should be removed
  (or a matching release re-built) before returning to ordinary `make
  up` dev iteration on the same checkout, to avoid the exact,
  reproducible false-`DRIFT` this certification hit and disclosed above.
  `FOLLOW_UP_DEBT`, documentation-only, no urgency.
- **F2 — `ami-acl-smoke` Makefile wiring gap**: the target does not set
  `FIXTURE_PROFILE=test` the way `trunk-smoke`, `pjsip-runtime-status-smoke`,
  `readiness-smoke`, and `regression` all do, so a bare `make
  ami-acl-smoke` run outside `make regression` is `BLOCKED` (`provider`
  never starts, and the suite requires it for its negative-ACL proof).
  Trivial one-line fix (`ami-acl-smoke: FIXTURE_PROFILE = test` above
  the target, matching the existing sibling pattern) — **not applied
  here**, per this task's certification-only mandate ("if product/
  platform changes become necessary: STOP, CLASSIFY ROOT CAUSE, do not
  silently fix them"). Does not affect `make regression`, where
  `FIXTURE_PROFILE=test` is already set for the whole run and the suite
  passes (confirmed, twice). Recommend a small, dedicated follow-up.
- **F3 — `readiness-smoke-test.sh` standalone timing race**: check #1
  ("all core containers healthy") reads `docker compose ps --format
  {{.Health}}` immediately after its own `up` prerequisite returns, with
  no polling/retry. Because this repository's `up` recipe always passes
  `--build`, and the image's OCI labels (`BUILD_TIMESTAMP`, embedded via
  the Makefile's per-invocation `date -u` computation) differ on every
  invocation, every `make readiness-smoke` (or any other `up`-dependent
  target run immediately beforehand) forces a genuine container
  recreate — and Asterisk's own healthcheck has a 15s `start_period`
  (confirmed via `docker inspect`), so an immediate, unretried read of
  its health status right after `up` returns can and reproducibly does
  (3/3 in this session) observe `starting`, not yet `healthy`. This does
  **not** manifest inside `make regression` (PASS both counted runs)
  because ~37 other suites already run first, leaving the stack stable
  well past the 15s window by the time this suite executes. Pre-existing
  test-design gap (same root-cause family as TASK-0034's own already-
  documented, accepted §41 debt item, "`harness_require_containers`
  checks 'Up' not 'healthy' | POST_PILOT"), not caused by this task, not
  a product defect, not fixed here. Recommend the same class of fix
  already used elsewhere in this harness (e.g. check #6's own "reconverge
  within 60s" polling contract) be applied to check #1 too, as a small,
  dedicated follow-up.
- **CH-2 — see FINAL DECISION above for the full statement; not merely a
  footnote here.** Real-certificate installation on the actual pilot
  host, followed by a passing `make cert-check PILOT=1` there, is this
  task's one `OPEN_CONSTRAINT` blocking unconditional `PILOT_GO`. It is
  an environment-provisioning item, not a reopening of CH-2's own
  implementation, which stays `CLOSED`.
- **Pre-existing, reconfirmed, unaffected by this task**: CH-7's RTP
  capacity note (200 ports/~100
  concurrent calls, unchanged, reconfirmed publishable without incident
  on this host), CH-8 (stale README, cosmetic), base-image digest
  pinning (still tag-only: `php:8.4-apache`, `debian:13-slim`,
  `mariadb:10.11` — none `:latest`, all pinned to major.minor/named tags,
  digest pinning explicitly out of this task's scope per its own
  instructions and remains `POST_PILOT`), and the non-atomic
  trunk-name collision / no cert-expiry UI warning items already carried
  as `PILOT_CONSTRAINT` in the main TASK-0034 document (unchanged,
  unaffected by anything in this certification).
- **New recommendation from this task specifically**: before the real
  pilot go-live host is used unattended for `make release-build`,
  explicitly confirm it does not use an interactive/GUI-Keychain-backed
  Docker credential helper (see BUILD CONNECTIVITY above) — a native
  Debian 14 Docker Engine install should not, but this was not directly
  tested on that exact host in this certification.

## FINAL DECISION

**TASK-0034G = `APPROVE_WITH_CONSTRAINTS`. TASK-0034 = `PILOT_GO_WITH_CONSTRAINTS`.**

Release/build certification: **PASS**. `release-artifact-smoke`:
**PASS 12/12**. Regression: **42/42 PASS**, **42/42 PASS** (two
consecutive runs, back-to-back, no manual repair between them).
`release-info`: **MATCH** (pre- and post-restart, pre- and
post-force-recreate). `doctor` 0 unexplained FAIL; `secrets-check`
MATCH; `migrate-check` SCHEMA_CURRENT; `reconcile-check` IN_SYNC. No
release blocker.

**Exactly one release constraint remains, and it is why this is
`APPROVE_WITH_CONSTRAINTS` rather than an unconditional `APPROVE`:**

> **Remaining constraint**: provision a production/pilot-acceptable WSS
> certificate on the actual pilot environment, and obtain
> `make cert-check PILOT=1` → **PASS** (`PILOT_ACCEPTABLE`) on that
> environment.

This is deliberate, not an oversight: `make cert-check PILOT=1` on
*this* certification's own environment correctly returned
`NOT_ACCEPTABLE_FOR_PILOT`, because this environment deliberately still
runs the shipped dev-fixture certificate. Three things are true at once,
and none of them contradict each other:

1. **CH-2 remains CLOSED at the implementation level.** TASK-0034E
   already proved, live, that the certificate-trust mechanism itself
   correctly classifies and accepts a real, trusted certificate
   (`TRUSTED`/`PILOT_ACCEPTABLE`, with a real REGISTER succeeding over
   TLS with verification actually enabled, never `CERT_NONE`). This
   certification is not reopening that mechanism, not casting doubt on
   it, and found no defect in it.
2. **The outstanding item is environment provisioning, not a code or
   test failure.** No script, gate, or product behavior needs to change
   for this constraint to close — only the actual pilot host's own WSS
   certificate material does.
3. **Once a real certificate is installed on the actual pilot
   environment and `make cert-check PILOT=1` passes there, TASK-0034 can
   close as plain `PILOT_GO` with no further product/code change** —
   this is a provisioning/certification step against the already-proven
   mechanism, not a reopened finding.

**The two narrow gaps this certification itself surfaced (F2, F3 above)
remain `FOLLOW_UP_DEBT`** — `ami-acl-smoke` standalone without
`FIXTURE_PROFILE=test`, and `readiness-smoke-test.sh`'s timing race
immediately after a rebuild. Both are pre-existing test-harness/Makefile
gaps, neither reachable from the supported product surface, neither
affecting `make regression`'s own PASS result, and **neither blocks this
certification's `APPROVE_WITH_CONSTRAINTS` outcome** — they are
independent of, and unrelated to, the WSS-certificate constraint above.

**Do not recommend `TASK-0034 = COMPLETE` yet.** TASK-0034 stays open,
carrying exactly one `OPEN_CONSTRAINT` (the WSS certificate
provisioning above), until that constraint is closed on the real pilot
environment.

**Recommend `TASK-0035 — Pilot Deployment & Soak Validation` as the next
task, carrying the WSS certificate provisioning and `make cert-check
PILOT=1` PASS as an explicit early prerequisite.** Not started here.
