# TASK-0035E4 — Release Immutability & Operational Target Hardening

**Status:** implementation complete — awaiting checkpoint authorization
**Incident:** I4 (release tag rewritten by operational `up --build`)
**Depends on:** TASK-0035E1 (merged), TASK-0035E2 (merged), TASK-0035E3 (merged/reviewed)
**Does not:** create tags, push, commit, or touch `tmp-0035a/`

## Starting state (this agent run)

| Item | Value |
|---|---|
| Branch | `cursor/asterisk-console-observability-c149` (E3 work landed; E4 continues here) |
| HEAD at start | `c956450` (E3 docs) |
| Dirty | `?? tmp-0035a/` only (untouched) |
| I4 | OPEN → closed by this task if gates pass |
| Pilot rc.4 | host networking + bidirectional audio previously validated |

## Root cause (I4)

Operational Make targets inherited `up`, and `up` was:

```make
up:
	... docker compose ... up -d --build ...
```

With `RELEASE_VERSION=v0.1.0-rc.X` exported (pilot operator shell), any of
`backup`, `reconcile-check`, `migrate-check`, `secrets-check`, `lint`,
smokes, etc. rebuilt and **retagged** `senma-app` / `senma-asterisk` under
the immutable release tag. `release-info` then flipped MATCH → DRIFT.

Secondary defect: `release-info` treated missing manifest / missing OCI
labels as soft `UNKNOWN` with exit 0 and printed `RESULT: no drift
detected` — a false negative when evidence was unavailable.

## Affected targets (pre-fix audit)

| Target | Pre-E4 | Post-E4 |
|---|---|---|
| `up` | `up -d --build` | `up -d --no-build` |
| `dev` | `doctor` + `up` (builds) | `doctor` + `ensure-dev-stack` forced `RELEASE_VERSION=dev` |
| `dev-build` | (none) | explicit mutable `:dev` build only |
| `dev-up` | `FIXTURE_PROFILE=dev` + `up` | forced `:dev` `ensure-dev-stack` |
| `ensure-dev-stack` | (none) | `refuse-non-dev-build` → `dev-build` → `up` |
| `require-runtime` | (none) | fail if app/asterisk/db not running; never build/start |
| `pilot-up` | no `--build`, image guards | same + explicit `--no-build` |
| `backup`, `reconcile`, `reconcile-check`, `migrate`, `migrate-check`, `secrets-check`, `rotate-*`, `ami-acl-migrate`, `cert-check` | `: up` | `: require-runtime` |
| `lint`, `regression`, `*smoke` (validation) | `: up` | `: ensure-dev-stack` (`:dev` only) |
| `doctor`, `release-info` | observational | unchanged (no build); doctor maps `UNKNOWN_FATAL`+no-manifest+`:dev` → SKIP |
| `restore` / `rotate-secrets` scripts | `up -d` (Compose auto-build possible) | `up -d --no-build` |
| `smoke-test.sh` | auto `up -d --build` if down | BLOCKED if not running (never builds) |

## Final lifecycle contract

| Concept | Supported command | May build? |
|---|---|---|
| **Build (dev)** | `make dev-build` | yes (`:dev` only) |
| **Build (release)** | `make release-build VERSION=vX.Y.Z` | yes (release tags only; dirty/tag policy intact) |
| **Start (generic)** | `make up` | **never** (`--no-build`) |
| **Start (dev+fixture)** | `make dev-up` / `make dev` | yes, but only `:dev` via `ensure-dev-stack` |
| **Start (pilot)** | `make pilot-up` | **never**; requires images + `RELEASE_VERSION≠dev` |
| **Runtime ops** | `reconcile*`, `migrate*`, `secrets-check`, `backup`, `doctor`, … | **never**; `require-runtime` or observational |
| **Validation** | `lint`, `regression`, smokes | may build **`:dev` only**; refuse release tags |
| **Release verify** | `release-info`, `release-artifact-smoke`, `release-immutability-smoke` | never |

### Guardrail

If `RELEASE_VERSION != dev`, any build-capable path (`dev-build`,
`ensure-dev-stack`, and therefore lint/regression/smokes) **fails loudly**
and points the operator at `make release-build VERSION=…`.

## release-info contract (fail-closed)

| Condition | State | Exit |
|---|---|---|
| Running image matches manifest (labels + image id + local tag id) | `MATCH` | 0 if all SENMA services MATCH |
| Manifest disagrees | `DRIFT` | 1 |
| Manifest missing / incomplete | `UNKNOWN_FATAL` | 1 |
| OCI version/revision labels missing | `UNKNOWN_FATAL` | 1 |
| Expected local tag missing | `UNKNOWN_FATAL` | 1 |
| Service not running | `NOT_RUNNING` | does not fail alone |
| `db` | `THIRD_PARTY` | inventory only |

Never prints `RESULT: no drift detected` when evidence is missing.
Prints EXPECTED / LOCAL TAG / RUNNING / OCI VERSION/REVISION fields.

`doctor`: on `:dev` with no manifest, `UNKNOWN_FATAL` → **SKIP** (expected
dev state). DRIFT or release-mode UNKNOWN_FATAL → **FAIL**.

## Tests

- `scripts/release-immutability-smoke-test.sh` (`make release-immutability-smoke`)
  - `up` / `pilot-up` `--no-build`
  - ops targets → `require-runtime`
  - non-dev build refused
  - missing release image → `pilot-up` FAIL
  - missing manifest → `UNKNOWN_FATAL`
  - wrong image ids → `DRIFT`
  - image IDs unchanged across reconcile/migrate/secrets/doctor/release-info/backup
- `release-artifact-smoke` updated: no-manifest case expects `UNKNOWN_FATAL` + non-zero exit
- Wired into `scripts/regression.sh`

## Host networking / E3

No changes to host-networking overlays, loopback binds, HTTP `:8080`,
SIP/RTP host bindings, console logger, or runtime debug opt-in.

## Pilot follow-up (not this task)

After merge, cut **`v0.1.0-rc.5`** bundling E1–E4. Do **not** create that
tag in this task. Do not mutate the current running pilot automatically.

## I4 closure checklist

1. operational targets do not build — **yes** (`require-runtime`)
2. release-tagged images remain unchanged across ops — **proven by smoke §8**
3. `pilot-up` never builds — **yes** (`--no-build` + guards)
4. `release-info` fails on missing/unknown identity — **yes** (`UNKNOWN_FATAL`)
5. deterministic image-ID immutability test — **yes**
6. canonical regression ×2 — see checkpoint

## Decision (filled after gates)

**`RELEASE_IMMUTABILITY_PASS`**

I4 **CLOSED**.

### Gate evidence

| Gate | Result |
|---|---|
| `make release-immutability-smoke` | **PASS** (14/14) |
| `make lint` | **PASS** |
| `make regression` #1 | **PASS** (includes release-immutability-smoke) |
| `make regression` #2 | **PASS** consecutive, no repair between |
| `git diff --check` | **PASS** |

### Follow-up (not blocking I4)

- Cut `v0.1.0-rc.5` after merge for full pilot re-validation (E1–E4 bundle). Do not create that tag in this task.
- Optional: add `--no-build` to destructive smoke `force-recreate` paths (already gated to `:dev` via `ensure-dev-stack`).
