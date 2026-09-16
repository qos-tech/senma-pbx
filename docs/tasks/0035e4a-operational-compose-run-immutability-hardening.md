# TASK-0035E4A — Operational Compose Run Immutability Hardening

**Status:** implementation complete — awaiting checkpoint authorization
**Incident:** I4 reopened by real-pilot evidence (compose-run implicit build)
**Depends on:** TASK-0035E4 (Make lifecycle immutability), TASK-0035E5 (runtime topology)
**Does not:** create tags, push, commit, mutate `v0.1.0-rc.7`, or touch `tmp-0035a/`

## Final decision (this checkpoint)

```text
OPERATIONAL_IMMUTABILITY_PASS_WITH_CONSTRAINTS
```

Constraints:

1. Docker Compose 2.40.x `run` has no `--no-build`; operational
   immutability is enforced by mandatory local-image preflight plus
   `run --pull never` (proven: `--pull never` alone still builds).
2. Canonical `:dev` regression required parking a gitignored leftover
   `release-manifest.json` for `v0.1.0-rc.7` (E7 build evidence) that
   made `doctor` correctly report DRIFT under `:dev`. Manifest restored
   after the two consecutive PASS runs. Not caused by E4A code.

## Real-pilot trigger

During TASK-0035E7 on TEXTE-PBX-001-class host:

```bash
RELEASE_VERSION=v0.1.0-rc.7
bash scripts/backup.sh
```

The release image was **not** present locally. `scripts/backup.sh` used
bare `docker compose run` (Compose 2.x `run` has no `--no-build`; with a
`build:` section and missing `image:`, Compose still builds). Compose then:

1. attempted to pull `senma-asterisk:v0.1.0-rc.7`
2. pull failed
3. **implicitly built** `senma-asterisk:v0.1.0-rc.7`

Resulting image carried:

```text
version=v0.1.0-rc.7
revision=unknown
```

That violates TASK-0035E4 / I4: only `make release-build VERSION=…` may
create a real release-tagged image with correct provenance.

## Root cause

Operational ephemeral containers used bare:

```bash
$COMPOSE run --rm --no-deps -T …
```

On Compose 2.40.x, `run` has no `--no-build`. When the named release
image is missing and the service declares `build:`, Compose still builds
(even with `--pull never`). E4 hardened Make `up` / `pilot-up` / restore
recreate with `--no-build`, but **did not** cover operational `compose
run` paths used by backup and secrets helpers.

## Affected paths (pre-fix)

| Path | Classification | Pre-E4A | Post-E4A |
|---|---|---|---|
| `scripts/backup.sh` (asterisk volume archives) | OPERATIONAL/RUNTIME | `$COMPOSE run` (implicit build) | `senma_compose_run` + runtime image preflight |
| `scripts/lib/secrets-lib.sh` (`slib_run_sh`) | OPERATIONAL/RUNTIME | `$COMPOSE run` (implicit build) | `senma_compose_run` |
| `scripts/restore.sh` (asterisk volume restore helpers) | OPERATIONAL/RUNTIME | `$COMPOSE run` (implicit build) | `senma_compose_run` |
| `scripts/lib/compose-runtime.sh` | SHARED | topology only | + `senma_require_local_image`, `senma_require_runtime_images`, `senma_compose_run` (`--pull never`) |
| `scripts/secrets-check.sh` / `rotate-secrets.sh` | OPERATIONAL via secrets-lib | comments only; invoke `slib_run_sh` | inherit hardening |
| `*-smoke-test.sh` | DEV/TEST | may mention compose run in comments | allowlisted; static gate scans for bare invocations |
| `make release-build` | RELEASE/BUILD | intentional build | unchanged — sole release build path |

## Immutability contract

```text
Operational/runtime compose run:
  MUST go through senma_compose_run
  MUST fail closed if required local image is missing
  MUST use --pull never (defense-in-depth)

Platform constraint (Compose 2.40.x):
  `docker compose run` has NO --no-build flag
  Missing image + build: section ⇒ implicit build (even with --pull never)
  Therefore local-image preflight is mandatory

Release image missing:
  FAIL CLOSED

Operational command:
  MUST NOT pull/build/fallback-build a release-tagged image

Only supported release image build:
  make release-build VERSION=vX.Y.Z
```

Forbidden sequence:

```text
release tag missing locally
→ compose run
→ pull attempt
→ build fallback
→ release-tag image created (revision=unknown)
```

## Implementation

### Shared helper (`scripts/lib/compose-runtime.sh`)

- `senma_require_local_image <image>` — fail closed with operator guidance
- `senma_require_runtime_images` — require both `senma-app` and
  `senma-asterisk` for active `RELEASE_VERSION` (default `dev`)
- `senma_require_release_images_if_tagged` — release-only alias (skips `:dev`)
- `senma_compose_run …` — preflight runtime images, then
  `$COMPOSE run --pull never …`

Compose `up` still uses `--no-build` (E4). Compose `run` cannot; the
preflight is the authoritative build ban for ephemeral operational runs.

### Call sites

- `backup.sh` resolves topology (E5) when release/mode signals are present,
  then `senma_require_runtime_images` before any archive work
- All operational ephemeral runs go through `senma_compose_run`
- Preserves existing `--rm`, `--no-deps`, `-T`, `--entrypoint`, `-v`
- Does **not** change backup payload contents or secret-check semantics
- Does **not** bypass `compose-runtime.sh` topology selection

## Fail-closed behavior

Example operator message:

```text
ERROR: required image senma-asterisk:vX.Y.Z is not available locally.
Build the exact release first with:
  make release-build VERSION=vX.Y.Z
Operational commands never build or pull release images (TASK-0035E4A / I4).
```

No silent switch to `:dev`. No silent pull of an unrelated tag.

## Negative proof (mandatory)

Fake tag (never a published RC):

```text
v0.0.0-immutability-test
```

| Probe | Result |
|---|---|
| `docker image inspect senma-asterisk:v0.0.0-immutability-test` before | NOT FOUND / ABSENT |
| Operational backup / `senma_compose_run` under that `RELEASE_VERSION` | FAIL CLOSED |
| `docker image inspect …` after | still ABSENT |

Covered by `scripts/operational-compose-run-immutability-smoke-test.sh`.

## Tests

| Gate | Command |
|---|---|
| Static + reproduction + backup/secrets negative/positive | `make operational-compose-run-immutability-smoke` |
| Existing E4 | `make release-immutability-smoke` |
| Existing E5 | `make restore-runtime-topology-smoke` |
| Backup | `make backup-smoke` |
| Secrets | `make secrets-consistency-smoke` |
| Canonical | `make lint` + `make regression` × 2 |

Static gate: operational scripts must not contain bare `$COMPOSE run` /
`docker compose run` in non-comment code; `senma_compose_run` is required.
Helper must include local-image preflight and `run --pull never`. DEV/TEST
smokes are scanned; bare invocations fail the suite unless classified.

## Runtime topology (E5)

Unchanged:

| Context | Compose |
|---|---|
| Host / pilot | `compose.yaml` + `compose.pilot.yaml` |
| Bridge / dev | `compose.yaml` |

Immutability is enforced **through** `compose-runtime.sh`, not by
bypassing it.

## Release provenance

No operational command may create an image carrying a real release tag
except via:

```bash
make release-build VERSION=…
```

## rc.7 disposition

| Item | Disposition |
|---|---|
| Tag `v0.1.0-rc.7` | **Do not retag, rebuild, move, or replace** |
| Contaminated local images (if any on pilot) | out of scope for this task; next RC supersedes |
| Next release candidate after E4A merge | `v0.1.0-rc.8` (not created here) |
| Candidate for final E7 closure | **No** — rc.7 is not eligible |

## E7 status

```text
TASK-0035E7 remains blocked
I4 reopened by real-pilot evidence → closed by E4A implementation
rc.7 is not candidate for final closure
next candidate must include E4A
TASK-0035 is not closed
```

## Scope discipline

Out of scope (unchanged): PJSIP, SIP/RTP, WebRTC, NAT, TLS ownership,
trusted proxy, status detail UX, restore REPLACE semantics, schema,
application features, rebranding.

## Remaining debt

- Pilot re-validation of backup under release images on TEXTE-PBX-001
  after rc.8 build (operational proof, not this task’s gate)
- Any historically contaminated `senma-*:v0.1.0-rc.7` on a pilot host must
  be replaced by a proper `release-build` of a later RC — not “fixed in
  place” as rc.7

## Proposed commit split (awaiting authorization)

1. `fix(ops): prevent implicit builds in runtime compose runs`
2. `test(ops): cover operational compose-run immutability`
3. `docs(ops): record TASK-0035E4A immutability closure`
