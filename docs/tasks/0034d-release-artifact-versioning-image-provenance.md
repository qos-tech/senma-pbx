# TASK-0034D — Release Artifact Versioning & Image Provenance

## LEAD

senma-docker-platform-engineer

## REVIEWERS

senma-application-architect (build/release tooling touches the Makefile's
public interface and the pilot deployment contract, not just Docker
internals), senma-workflow-orchestrator (routing/checkpoint)

`senma-telephony-architect` was not invoked: no Asterisk runtime
semantics (dialplan, AMI, PJSIP objects, reload/restart behavior) change
here — only how the Asterisk *image* is versioned, labeled, and
deployed. `senma-product-designer` was not invoked: no user-facing
version surface is introduced (per this task's own explicit instruction)
— `make release-info`/`make doctor` are operator CLI output, not
application UI.

## SCOPE

Close TASK-0034 Finding CH-9 (no release-artifact/versioning or image-
provenance mechanism exists): establish a deterministic release identity
model proving `source commit -> release version -> built image -> image
id/digest -> running deployment`, so an operator can always answer "what
version is this, which commit produced it, which exact image is
running, has it drifted."

**In scope**: release version model (Git tag contract), OCI image
labels/build-arg plumbing, image tag contract, image id/digest
recording, `make release-build`/`make release-info` tooling, drift
detection, `make doctor` integration, `pilot-up`'s deploy contract,
production release runbook updates, TASK-0034 CH-9 closure, focused
regression coverage.

**Out of scope** (per task instructions, and per this task's own
findings below): container registry vendor selection, CI/CD platform
rollout, automatic GitHub release publishing, image signing/SBOM,
cosign/Sigstore, HA, Kubernetes, WSS fixture certificate (CH-2), AMI ACL
redesign (CH-6). Base-image digest pinning is investigated and
classified but not implemented (see BASE IMAGE AUDIT). Registry
push/pull is investigated and classified LOCAL_ONLY, not implemented.

---

## ORIGINAL CH-9 (verbatim, TASK-0034)

From `docs/tasks/0034-release-readiness-production-pilot-gate.md` §30
("Release version/artifact model"):

> **Finding CH-9 (release debt, not a blocker)**: no git tag exists in
> this repository (`git tag -l` returns empty), and no image-tag/
> version-identifier convention is defined. The runbook now instructs
> operators to `git checkout <release-tag-or-commit>` and record the
> exact commit at deploy time, but the *tagging convention itself*
> doesn't exist yet. Recommend establishing one (e.g., `pilot-v0.1.0`)
> as part of the next task, not invented here.

§31 ("Image provenance"):

> **Same finding as §30**: no build-time mechanism (LABEL, build arg)
> captures the source git commit into the image. Current process cannot
> automatically map a running image back to a source commit —
> classified as release debt (CH-9), to close alongside the tagging
> convention.
>
> Asterisk's own version is pinned exactly (`ASTERISK_VERSION=22.11.0`);
> no image anywhere uses `:latest` (`db: mariadb:10.11`, app base
> `php:8.4-apache`, asterisk/provider base `debian:13-slim` — all
> confirmed via direct Dockerfile/compose.yaml inspection).

§32 ("Compose/release immutability") is closely related and directly
shaped this task's design:

> **Classification: development-shaped, not yet production-immutable.**
> Both `app` and `asterisk` bind-mount `./snep` from the host
> (read-write for app, read-only for asterisk) rather than baking
> application source into the image. This is correct and intentional
> for the current development phase, but a production pilot deploying
> from this same `compose.yaml` would be live-editing application source
> via bind mount rather than deploying an immutable built artifact.

The §36/§637 numbered-findings summary lists CH-9 as
`PILOT_CONSTRAINT`, unchanged through TASK-0034A/B/C.

---

## CURRENT BUILD MODEL (before this task)

Inspected directly: `compose.yaml`, `compose.pilot.yaml`, `docker/
app.Dockerfile`, `docker/asterisk.Dockerfile`, `Makefile`, `.dockerignore`,
`.gitignore`, `docs/operations/production-release-runbook.md`. No CI/
release scripts exist in this repository (`scripts/` contains only dev/
regression tooling).

| Service | Build | Image identity (before) | Source binding |
|---|---|---|---|
| `app` | `docker/app.Dockerfile`, local build | none (`image:` unset — Compose auto-names it `mag-pbx-app`, i.e. project-name-derived, not version-derived) | `./snep` bind-mounted read-write into the container; PHP application code is NEVER baked into the image (no `COPY snep` in either Dockerfile) |
| `asterisk` | `docker/asterisk.Dockerfile`, local build | none (`mag-pbx-asterisk`) | `./snep` bind-mounted read-only (for AGI); Asterisk's own compiled binary IS baked into the image (multi-stage build, source compiled from a pinned tarball URL) |
| `provider` | same Dockerfile as `asterisk`, local build | none (`mag-pbx-provider`) | TEST_ONLY/DEV_ONLY fixture (TASK-0034C, `profiles: [dev, test]`) — excluded from every release concern in this task |
| `db` | none — official image | `mariadb:10.11` (already version-pinned) | n/a — stock image, no bind mount of application data into the image |

Every `up`-family Makefile target (`up`, `dev-up`, `pilot-up` before this
task) invoked `docker compose ... up -d --build`, i.e. **every single
invocation rebuilt from local source**, unconditionally, with no image
tag ever surviving a rebuild under a stable, inspectable name. `git tag
-l` returns empty (reconfirmed live). No `VERSION` file, no version
string anywhere in the repository (reconfirmed via targeted grep before
starting this task).

**Classification (Phase 2 of this task's routing instructions):**

| Service | Classification |
|---|---|
| `app` | `LOCAL_BUILD` + `SOURCE_BOUND` (runtime code comes from the bind mount, not the image) |
| `asterisk` | `LOCAL_BUILD` (core binary baked into the image; dialplan/AGI source is `SOURCE_BOUND` via the same bind mount) |
| `provider` | `LOCAL_BUILD`, `TEST_ONLY` — out of release scope (Phase 30) |
| `db` | `TAGGED_IMAGE`, third-party (Phase 29) — recorded for inventory, never a SENMA release artifact |

No production-required service was left `UNKNOWN`.

---

## VERSION MODEL

**Decision: SemVer, `vX.Y.Z`, with `-rc.N` prereleases for release
candidates.** No prior convention existed in this repository (confirmed:
no tags, no `VERSION` file, no version string anywhere) — Phase 3
explicitly says not to invent a complex scheme in that case, and CH-9's
own text already suggested this exact shape (`pilot-v0.1.0`; this task
drops the `pilot-` prefix since the same version identity now applies to
every SENMA-built image, not only a pilot-specific artifact). Version
identity is independent of Docker image tags (image tags *derive* from
it — `senma-app:vX.Y.Z` — they do not define it).

## GIT TAG CONTRACT

**A release version IS an annotated Git tag: `vX.Y.Z` (or `vX.Y.Z-rc.N`
for a release candidate).** `scripts/release-build.sh` enforces this in
two modes:

- **Formal release** (default, no `RC=1`): HEAD must be *exactly* the
  tag named `VERSION` (`git describe --tags --exact-match HEAD`).
  Mismatch is a hard failure with a message telling the operator how to
  create the tag or use RC mode instead.
- **Release candidate** (`RC=1`): no tag is required — `VERSION` +
  the current commit is an explicit, deliberate pairing (Phase 33). This
  is intentionally "just SemVer prereleases," not a separate
  release-channel system, per this task's own instruction not to
  over-build this.

A lightweight (non-annotated) tag at HEAD is accepted with a warning
(the commit mapping is still exact either way) — annotated is preferred,
not mandatory.

**This task does not create any real release tag in this repository.**
Per explicit instruction ("do not actually tag/release automatically
... unless explicitly instructed"), the mechanism was validated with
temporary, immediately-deleted local tags (`v0.0.2`, deleted right after
use — see PILOT PROOF/REGRESSION PROOF below) and disposable
`-rc.N` builds. `git tag -l` in this repository is empty again at the
end of this task, identical to its state at the start.

## OCI LABEL CONTRACT

Both `docker/app.Dockerfile` and `docker/asterisk.Dockerfile` declare:

```dockerfile
ARG RELEASE_VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_TIMESTAMP=unknown
LABEL org.opencontainers.image.title="SENMA PBX app"        # or "... asterisk"
      org.opencontainers.image.version="${RELEASE_VERSION}"
      org.opencontainers.image.revision="${GIT_COMMIT}"
      org.opencontainers.image.created="${BUILD_TIMESTAMP}"
      org.opencontainers.image.source="https://github.com/qos-tech/mag-pbx"
      org.opencontainers.image.licenses="GPL-3.0-or-later"
```

Standard OCI keys only (`org.opencontainers.image.*`), no custom label
namespace. No secret is ever passed as a build arg or label (see SECRET/
BUILD-CONTEXT AUDIT).

**Placement matters and was a real, live-discovered defect in this
task's own first draft — see BUILD REPRODUCIBILITY BOUNDARY below.** The
block is placed as the LAST instruction in each Dockerfile (`asterisk.
Dockerfile`: in the runtime stage only — the build stage produces no
image anyone runs), specifically so a changing `BUILD_TIMESTAMP` (which
changes on every single invocation, by design) only busts the cache for
this one trivial LABEL layer, never the expensive `apt-get install`/
Asterisk-compile layers above it.

`compose.yaml` threads these through for both `app` and `asterisk`:

```yaml
build:
  args:
    RELEASE_VERSION: ${RELEASE_VERSION:-dev}
    GIT_COMMIT: ${GIT_COMMIT:-unknown}
    BUILD_TIMESTAMP: ${BUILD_TIMESTAMP:-unknown}
```

The Makefile computes and `export`s `RELEASE_VERSION` (default `dev`),
`GIT_COMMIT` (`git rev-parse HEAD`, always real, no operator action
needed) and `BUILD_TIMESTAMP` (`date -u ...`) once, near the top —
every target automatically inherits them; no per-recipe wiring exists
anywhere else. `provider` deliberately receives no `args:` override (it
inherits the Dockerfile's own `dev`/`unknown` defaults) — it is excluded
from release identity by design (see PROVIDER FIXTURE SCOPE below).

## IMAGE TAG CONTRACT

`compose.yaml` now names both images explicitly:

```yaml
app:       image: senma-app:${RELEASE_VERSION:-dev}
asterisk:  image: senma-asterisk:${RELEASE_VERSION:-dev}
```

- `senma-app:dev` / `senma-asterisk:dev` — the default for every plain
  `make up`/`make dev`/`make dev-up`. **Classification: `DEVELOPMENT_
  ONLY`, mutable** (Phase 7) — exactly the same role `:latest` would
  play, under a name that cannot be confused with a real version.
- `senma-app:vX.Y.Z` / `senma-asterisk:vX.Y.Z` — produced only by `make
  release-build VERSION=vX.Y.Z`. Not pushed anywhere (see REGISTRY
  POLICY).
- No secondary `:<git-sha>` tag was added — the `git_revision` field in
  `release-manifest.json` and the `org.opencontainers.image.revision`
  label already carry the commit; a second tag would be a second,
  redundant place for the same fact to drift out of sync.

`provider` is untouched (`image:` deliberately not set) — it keeps
Compose's own project-name-derived name, unrelated to the `senma-*`
namespace.

## DIGEST CONTRACT

**No container registry exists for this repository (LOCAL_ONLY — see
REGISTRY POLICY), so there is no registry digest to record.** The
strongest artifact identity available without pushing anywhere is the
image's own local content-addressable id (`docker image inspect
--format '{{.Id}}'`, a `sha256:...` value derived from the image's
config + layer chain). `scripts/release-build.sh` records this for both
`app` and `asterisk` in `release-manifest.json`; `scripts/release-
info.sh` compares a running container's bound image id
(`docker inspect <container> --format '{{.Image}}'`) against it.

This is honestly weaker than a registry digest (it says nothing about
what a *different host* would produce from the same commit — see BUILD
REPRODUCIBILITY BOUNDARY) but is a real, non-spoofable, content-derived
identity for *this* Docker daemon, and is exactly what `make pilot-up`'s
own no-rebuild contract (below) depends on.

## DEPLOYMENT IDENTITY / RELEASE BUILD

`make release-build VERSION=vX.Y.Z [RC=1] [ALLOW_DIRTY=1]`
(`scripts/release-build.sh`):

1. Validates `VERSION` matches `^vN.N.N(-rc.N)?$`.
2. **Dirty-tree protection** (Phase 13): refuses if `git status
   --porcelain` is non-empty, unless `ALLOW_DIRTY=1` is explicitly
   passed — recorded as `"dirty": true` in the manifest so it can never
   be mistaken for a clean release later. There is no way to build a
   real release from a dirty tree without leaving that fact permanently
   recorded.
3. Resolves `GIT_COMMIT` and enforces the **Git tag contract** above.
4. Builds `app`+`asterisk` (never `provider`, never `db`) via `docker
   compose build`, with `RELEASE_VERSION`/`GIT_COMMIT`/`BUILD_TIMESTAMP`
   passed as env vars (compose.yaml's own `args:` picks them up).
5. **Self-verifies** (Phase 24/25): reads the labels back off both just-
   built images and fails loudly if `version`/`revision` don't exactly
   equal what was requested — a build-arg/label plumbing defect must
   never silently produce an unlabeled or mislabeled "release."
6. Writes `release-manifest.json` (flat JSON, gitignored, regenerated
   every run — see RELEASE METADATA MODEL) and prints an evidence table.
7. Never pushes anywhere (see REGISTRY POLICY/PUSH SEPARATION).

`make pilot-up` — the one supported pilot start/redeploy command — was
changed as part of this task (see BUILD REPRODUCIBILITY BOUNDARY for
why): it now (a) refuses to run if `RELEASE_VERSION` is unset or still
the mutable `dev` tag, (b) refuses if `senma-app:$RELEASE_VERSION`/
`senma-asterisk:$RELEASE_VERSION` are not already present locally
(telling the operator to run `release-build` first), and (c) **never
passes `--build`** — it deploys the *exact* image `release-build`
already produced, rather than triggering a second, independently-
timestamped build of the identical commit.

## DRIFT DETECTION

`make release-info` (read-only, `scripts/release-info.sh`, shared by
`make doctor` and the regression suite — Phase 19, no second inspection
implementation):

- Per SENMA-built service (`app`, `asterisk`): `MATCH` (manifest exists,
  running container's labels AND bound image id all agree with it),
  `DRIFT` (a manifest exists but any of those disagree — deliberately
  strict: a label-only match with a different image id is still `DRIFT`,
  not `MATCH`, because this repository's images are not proven
  bit-for-bit reproducible — see below), `UNKNOWN` (no manifest yet, or
  the image carries no OCI labels at all — never a crash), or
  `NOT_RUNNING`.
- **Multi-image consistency** (Phase 28): if both resolve to real
  labels, their version+revision must agree; disagreement is reported
  as `MIXED_VERSION` and counts as a failure — see `release_versions_
  mixed()` in `scripts/lib/release-lib.sh`.
- `db` is reported for inventory only, explicitly `THIRD_PARTY`, never
  classified `MATCH`/`DRIFT`/`UNKNOWN` (Phase 29) — see THIRD-PARTY DB
  IMAGE SCOPE.

`make doctor` gained one new check, "Release artifact identity," that
calls the exact same script (`--summary` mode) rather than
reimplementing any of this: `PASS` on `MATCH`, `FAIL` on `DRIFT`, `SKIP`
when no manifest exists yet (the normal state of a dev environment —
never a doctor failure just because nobody ran `release-build`).

## THIRD-PARTY DB IMAGE SCOPE

`db` (`mariadb:10.11`) is recorded in every inventory (manifest, `make
release-info`, evidence tables) but is never a SENMA release artifact
and never gains SENMA OCI labels. **Live-confirmed, and worth recording
explicitly**: the official `mariadb` image already carries its *own*
`org.opencontainers.image.version` label (`10.11.19` — MariaDB's own
upstream version, coincidentally under the identical OCI key name) but
carries no `org.opencontainers.image.revision` at all. `release-info.sh`
never compares `db` against SENMA identity at all (it reads only
`.Config.Image`/the running image id, for inventory display) — this
avoids a real, easy-to-write bug: naively reusing the generic label-
comparison path against `db` would either silently succeed against
MariaDB's own foreign version string, or misreport it, depending on
which label happened to be checked first.

## PROVIDER FIXTURE SCOPE

`provider` (TASK-0034C, `profiles: [dev, test]`) is untouched by this
task beyond inheriting the Dockerfile's own unlabeled `dev`/`unknown`
defaults (no `args:`/`image:` override was added for it). It is never
built by `release-build.sh`, never appears in `release-manifest.json`,
and the CH-3 Compose-profile gate this task depends on remaining intact
was reconfirmed live (see REGRESSION PROOF — `compose-profile-isolation-
smoke` still passes unmodified).

## RELEASE METADATA MODEL

**Decision: Git tags are the sole authoritative source of release-
version identity. `release-manifest.json` is a generated, gitignored
build receipt, not a second source of truth** (Phase 11 — "avoid dual
sources of truth"). It is never manually edited, never committed, and
is fully reproducible from `make release-build VERSION=...` — if it
disagrees with reality, the fix is to rebuild, not to hand-edit it. A
committed `VERSION` file was considered and rejected for exactly this
reason: it would be a second place the version could say something
different from the actual checked-out tag.

The manifest is deliberately a **flat** JSON object (`app_repo_tag`,
`app_image_id`, `app_label_version`, ..., not a nested `images.app.*`
shape) — every key name is unique across the whole file. This
repository's own tooling reads it with plain `grep`/`sed` (`scripts/lib/
release-lib.sh`'s `manifest_get`), not a JSON parser — no `jq`/`python3`
dependency was introduced for this (Phase 6 of the shared engineering
rules: document new dependencies; the decision here is *not* to add
one). A nested schema would make that unsafe (ambiguous which
`image_id` occurrence a naive grep matched); the flat schema makes it
safe by construction, since every value written is a known-shape token
(a version string, a hex Git SHA, an RFC3339 timestamp, an `image:tag`
string, or a `sha256:...` id) — never arbitrary untrusted text.

## SECRET/BUILD-CONTEXT AUDIT

- Neither Dockerfile does a wholesale `COPY . .` — every `COPY` names a
  specific file (confirmed via direct inspection, both before and after
  this task's changes). Application source (`snep/`) is **never** baked
  into either image; it reaches both containers exclusively via the
  existing bind mounts.
- `.dockerignore` already excluded `.git`/`.env`; this task additionally
  excludes `/backups` (currently empty, but classified `CUSTOMER_OWNED`/
  `PERSISTENT_DATA` per TASK-0033A — contains DB rows, SIP secrets, and
  a TLS private key when populated) and `release-manifest.json` (no
  secrets, but a generated artifact with no reason to reach the build
  context).
- Live-confirmed on the actual built images (`senma-app:dev`, `senma-
  asterisk:dev`):
  - `docker image inspect --format '{{json .Config.Env}}'` — app image
    contains only standard PHP-build-toolchain variables (`PATH`,
    `PHP_VERSION`, `PHP_CFLAGS`, etc.); asterisk image contains only
    `PATH`. No `DB_PASSWORD`/`DB_ROOT_PASSWORD`/`AMI_PASSWORD`/any
    SENMA secret variable name appears in either.
  - `docker history --no-trunc | grep -iE '\.env|password|secret'` —
    no match in either image's layer history.
- Neither Dockerfile declares any `ARG`/`ENV` named after a secret; the
  only `ARG`s are `DEBIAN_FRONTEND`, `ASTERISK_VERSION`, and this task's
  own `RELEASE_VERSION`/`GIT_COMMIT`/`BUILD_TIMESTAMP` (none of which
  are secret-shaped).

**Conclusion: no secret reaches an image layer, label, environment, or
the manifest.** This was checked with real Docker introspection
commands against real built images, not source review alone (per this
task's own Phase 22 instruction).

## BUILD REPRODUCIBILITY BOUNDARY

**Do not claim bit-for-bit reproducibility — it is not proven, and one
specific gap was found and fixed live during this task, not merely
disclaimed on paper.**

**Live-discovered defect (fixed in this task, not left as debt):** the
first draft of this task placed the `ARG RELEASE_VERSION`/`LABEL
org.opencontainers.image.*` block immediately after each Dockerfile's
`FROM` line, before the expensive `apt-get install`/Asterisk-source-
compile steps. `BUILD_TIMESTAMP` is recomputed fresh on every single
Make invocation by design — and a Docker build-cache miss on any
instruction invalidates every instruction after it. Confirmed live: a
second `make up` with a different `RELEASE_VERSION`/timestamp forced
`apt-get install` to rerun from scratch (no `CACHED` marker at all) on
both images, purely because of the LABEL block's placement — this also
meant two separate builds of the *identical* commit produced two
different image ids (`sha256:57f521c6...` vs. `sha256:912e483554...`,
both correctly labeled with the same version/revision), which would
have silently broken this task's own strict image-id-based `MATCH`
contract. **Fix**: moved both blocks to be the very last instruction in
their respective Dockerfile/stage — re-verified live, the `apt-get
install` layer is now `CACHED` across a version/timestamp change, and
(more importantly) `make pilot-up`'s new no-rebuild contract means this
particular reproducibility gap can never actually surface in a real
pilot deploy, because no second build ever happens there at all.

**What is/isn't proven:**

- Source identity: exact (Git commit is the sole input to `GIT_COMMIT`;
  self-verified against the built label every time).
- Dockerfile identity: exact for a given commit (same file, same repo).
- Base image references: `php:8.4-apache`, `debian:13-slim` (×2 stages),
  `mariadb:10.11` — all `VERSION_PINNED` (major.minor, not `:latest`),
  none `DIGEST_PINNED` — see BASE IMAGE AUDIT. A base image tag can
  legitimately point at different bytes over time (security patches),
  which a rebuild weeks later would pick up even from the identical
  commit — this is real, disclosed release debt, not hidden.
  `apt-get install` similarly pulls whatever the Debian/PHP package
  mirrors currently serve — not pinned to specific package versions.
- **What IS structurally guaranteed**: `make pilot-up` never rebuilds —
  it deploys the literal image id `make release-build` produced and
  recorded. The reproducibility gap above can only ever matter *between
  two separate `release-build` runs* (e.g., a rollback rebuild weeks
  later — see ROLLBACK ARTIFACT CONTRACT), never between a release build
  and its own pilot deploy.

## BASE IMAGE AUDIT

| Dockerfile | `FROM` | Classification |
|---|---|---|
| `docker/app.Dockerfile` | `php:8.4-apache` | `VERSION_PINNED` (major.minor, not `:latest`) |
| `docker/asterisk.Dockerfile` (build stage) | `debian:13-slim` | `VERSION_PINNED` |
| `docker/asterisk.Dockerfile` (runtime stage) | `debian:13-slim` | `VERSION_PINNED` |
| `compose.yaml` `db` | `mariadb:10.11` | `VERSION_PINNED`, third-party (not SENMA-built) |

No `DIGEST_PINNED` base image, no `MUTABLE` (`:latest`) base image.
**Classification: `POST_PILOT` debt, not `PILOT_BLOCKER`/`PILOT_
CONSTRAINT`.** CLAUDE.md's own Docker rules already set the bar at
"pin major/minor versions at minimum" (satisfied for all four), not
digest pinning; CH-9's own original text already noted approvingly that
no image anywhere uses `:latest`. Digest-pinning every base image now
would also make routine security-patch pickup (a real, wanted property
for a PBX handling real calls) require an explicit Dockerfile edit for
every Debian/PHP point release — a real tradeoff, not obviously a net
improvement, and out of this task's narrow mandate per Phase 16's own
"do not necessarily pin every base image in this task if operationally
excessive" instruction.

## REGISTRY POLICY / PUSH SEPARATION

**Classification: `LOCAL_ONLY`.** No container registry is configured
anywhere in this repository (no `docker login`/registry URL in any
script, Makefile, or compose file). `make release-build` stops at local
tagged images + a locally-computed image id — per this task's own scope
boundary ("registry vendor selection" is explicitly out of scope) and
Phase 34/35's explicit permission to stop here. No push mechanism exists
to separate from build, so there is nothing to accidentally couple.

## ROLLBACK ARTIFACT CONTRACT

TASK-0033A already covers state (DB/config/certificate) rollback. This
task adds the missing artifact half: the production release runbook's
Upgrade procedure now copies `release-manifest.json` to
`release-manifest.json.previous` *before* checking out the new release,
and the Rollback procedure uses it (plus the previous release's own Git
tag) to know exactly what to rebuild — `make release-build
VERSION=<previous-release-tag>` from that tag reconstructs the exact
same version+commit pairing (and, if the previous version's tagged
images were never pruned, reuses them via Docker's build cache rather
than rebuilding from scratch). The runbook explicitly warns against
pruning a previous release's tagged images while a rollback to it is
still plausible.

## COMPOSE RELEASE MODEL

**Decision: pilot/production now consumes a pre-built image, not an
opportunistic rebuild — the Phase 9 "preferred model," not the "split
into 0034D2" fallback.** This turned out to be a small, safe change (one
Makefile target, two guard clauses, no `--build` flag), not the large
architectural split originally hedged against — `pilot-up` already
existed as a dedicated target with no other caller depending on its
`--build` behavior (confirmed: grepped every script/doc reference to
`pilot-up`; only the runbook and this task's own docs mention it — no
regression suite calls it). `compose.yaml` retains `build:` alongside
`image:` for `app`/`asterisk` so plain development (`make up`/`make
dev`) is completely unaffected — only `pilot-up`'s own recipe changed.

The one remaining, larger, deliberately out-of-scope piece of Phase 9's
full vision — building on a *different* host/CI runner than the one
running `pilot-up`, requiring a registry push/pull or an image-tarball
transfer — is real future work, tracked below (REMAINING DEBT), not
silently dropped.

---

## PILOT PROOF

Performed live against this repository's own dev Docker stack (the same
stack this task's own regression suite runs against — not a separate
isolated clone; the working tree was uncommitted during this task, so
formal-tag proofs used a temporary, immediately-deleted local Git tag
rather than committing/tagging the real branch, per this task's explicit
"do not tag automatically" instruction):

1. **Clean-build proof**: `VERSION=v0.0.1-rc.1 RC=1 ALLOW_DIRTY=1 make
   release-build` (RC mode — the tree carried this very task's own
   uncommitted changes) → built `senma-app:v0.0.1-rc.1`/`senma-
   asterisk:v0.0.1-rc.1`, both self-verified, `release-manifest.json`
   written.
2. **Pilot deploy**: `RELEASE_VERSION=v0.0.1-rc.1 make pilot-up` →
   `docker compose` logged `"No services to build"` (confirming no
   rebuild occurred) and recreated `app`/`asterisk` directly on the
   just-built images.
3. **MATCH proof**: `make release-info` → `app:MATCH`, `asterisk:MATCH`,
   `RESULT: no drift detected` (exit 0).
4. **Restart proof**: `docker compose restart app asterisk` → `release-
   info.sh --summary` still `app:MATCH`/`asterisk:MATCH`.
5. **Force-recreate proof**: `docker compose ... up -d --force-recreate
   --no-build app asterisk db` (with `RELEASE_VERSION` still exported)
   → still `app:MATCH`/`asterisk:MATCH`. (A first attempt at this step,
   run from a shell where `RELEASE_VERSION` was *not* re-exported for
   the raw `docker compose` invocation, silently fell back to the
   mutable `dev` tag and correctly reported `DRIFT` — see OPERATIONAL
   FOOTGUN below; this is included here as a real, reproduced negative
   proof, not just a hypothetical.)
6. **Formal-tag proof**: created a temporary local annotated tag
   `v0.0.2` at HEAD, ran `VERSION=v0.0.2 ALLOW_DIRTY=1
   bash scripts/release-build.sh` (no `RC=1`) → succeeded (HEAD matched
   the tag exactly).
7. **Wrong-tag proof**: with the same `v0.0.2` tag still at HEAD, ran
   `VERSION=v9.9.9 ALLOW_DIRTY=1 bash scripts/release-build.sh` (no
   `RC=1`) → rejected: `"HEAD is not tagged 'v9.9.9' (found: 'v0.0.2')"`,
   no build attempted.
8. **Cleanup**: `git tag -d v0.0.2` (repository's tag list confirmed
   empty again, identical to this task's starting state), removed
   `release-manifest.json` and every test-built image
   (`senma-app`/`senma-asterisk` `:v0.0.0-rc.99`, `:v0.0.1-rc.1`,
   `:v0.0.2`), and rebuilt/redeployed plain `make up` to restore the dev
   stack to `senma-app:dev`/`senma-asterisk:dev` — confirmed via `docker
   compose ps -a` and `git status --short` (only this task's own source
   changes remain).

**Operational footgun found and documented (not a code defect — a real
operator-facing risk this task now documents, mirroring TASK-0034B's
own `COMPOSE_FILES`/`SERVICES` precedent):** `RELEASE_VERSION` must stay
exported for the entire pilot operator shell session. A restart from a
shell where it is still exported preserves identity exactly (step 4
above); a plain `docker compose up`/`--force-recreate` from a shell
where it is unset silently recreates the container on the mutable `dev`
tag instead — reproduced live (see step 5's parenthetical) before being
corrected. The runbook now states this explicitly, next to the
identical pre-existing `COMPOSE_FILES`/`SERVICES` warning.

## MIXED-VERSION PROOF

Per Phase 45's own text ("do not leave the main dev environment mixed
afterward"), this was **not** proven by building a real app/asterisk
pair on different versions (real containers running the same dev stack
this task's own regression depends on) — instead, `release_versions_
mixed()` (`scripts/lib/release-lib.sh`), the exact comparison function
`release-info.sh` uses in production, is exercised directly with
synthetic inputs in `scripts/release-artifact-smoke-test.sh` item 8:
confirmed it flags `v1.0.0/aaa111` vs. `v1.0.1/aaa111` as mixed, and
confirmed it does *not* flag `v1.0.0/aaa111` against itself. Every other
part of the same code path (label reading, manifest comparison, MATCH/
DRIFT classification) is already exercised against real containers by
items 1-7 of the same suite (see REGRESSION PROOF).

---

## REGRESSION PROOF

`scripts/release-artifact-smoke-test.sh` (new, registered as suite 40
in `scripts/regression.sh`, placed immediately after `compose-profile-
isolation-smoke`) — standalone run against the real dev stack, all 8
proof items, 12 individual checks, 0 failures:

```
1: app labels present                    PASS
1: asterisk labels present               PASS
1: revision matches current HEAD         PASS
2: app/asterisk agree                    PASS
3: dirty tree rejected                   PASS
4: MATCH reported                        PASS
5: DRIFT reported                        PASS
6: UNKNOWN reported                      PASS
7: missing-label case handled            PASS
8: mixed version detected                PASS
8: agreement not flagged                 PASS
PASS: 12   FAIL: 0
```

Every temporary file/manifest/image this suite writes is cleaned up via
`harness_register_cleanup`; a pre-existing `release-manifest.json` (a
real pilot operator's own) is backed up and restored, never clobbered.

Full `make regression` (all 40 suites, including the new one in its
real placement) and `make lint` results are in the shared VALIDATION
section of the TASK-0034D checkpoint (this task's implementation report)
— not duplicated here to avoid two places the same pass/fail evidence
could drift out of sync.

---

## REMAINING DEBT

- `FOLLOW_UP_DEBT` — **Cross-host reproducibility.** `make release-
  build` followed by `make pilot-up` on the *same* Docker daemon is
  structurally guaranteed identical (no second build occurs). Building
  the identical commit+version on a *different* host/CI runner is not
  guaranteed byte-identical (mutable base-image tags, unpinned `apt-get`
  package versions — see BUILD REPRODUCIBILITY BOUNDARY). This matters
  only if a future architecture builds on one host and deploys to
  another (Phase 9's larger vision, deliberately not implemented here —
  see COMPOSE RELEASE MODEL). Fixing it fully would mean either digest-
  pinning every base image and vendoring/pinning every `apt-get`
  package, or introducing a registry + `docker push`/`pull` so the exact
  same image bytes travel between hosts instead of being rebuilt twice —
  either is a real, separate task, not a small addition to this one.
- `POST_PILOT` — base images (`php:8.4-apache`, `debian:13-slim` ×2,
  `mariadb:10.11`) are version-pinned, not digest-pinned (see BASE IMAGE
  AUDIT). Acceptable for pilot per CLAUDE.md's own existing bar; revisit
  if/when reproducibility requirements tighten.
- `FOLLOW_UP_DEBT` — no container registry exists (LOCAL_ONLY). If a
  future deployment topology needs to build on one machine and deploy to
  another, this needs a registry (or an explicit `docker save`/`load`
  transfer step) — out of this task's scope per its own instructions.
- `FOLLOW_UP_DEBT` — `RELEASE_VERSION` export-persistence is a real
  operator footgun (see PILOT PROOF) with no structural guard beyond
  documentation and `make release-info`'s after-the-fact detection —
  the same category of debt TASK-0034B accepted for `COMPOSE_FILES`/
  `SERVICES` (not re-litigated here; a single combined "harden every
  pilot-session environment-variable footgun at once" follow-up may be
  worth considering, but is not proposed as urgent).
- Pre-existing, reconfirmed, unrelated to this task: CH-2 (WSS fixture
  certificate) and CH-6 (flat AMI ACL) remain open, exactly as TASK-0034
  left them.

---

## VALIDATION

See the TASK-0034D implementation checkpoint (reported alongside this
document) for the full canonical-gate evidence: `make lint`, two
consecutive `make regression` runs (40/40 expected), `make doctor`,
`make secrets-check`, `make migrate-check`, `make reconcile-check`,
`git diff --check`, `git status --short`.

## RECOMMENDATION

`APPROVE_WITH_CONSTRAINTS` — see the shared checkpoint for the full
CH-9 disposition and updated `TASK-0034` pilot decision.
