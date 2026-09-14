# TASK-0034R — Final Release Readiness Closure Review

## Status

**CLOSED — audit/closure only.**

**Final decision: `READY_WITH_NON_BLOCKING_DEBT`**

No reproducible `PILOT_BLOCKER` was found. Canonical gates passed twice
consecutively. Remaining items are explicitly classified as
`PILOT_CONSTRAINT`, `POST_PILOT_DEBT`, or `DEAD/OBSOLETE`.



## TASK-0035A amendment (WSS TLS termination)

The WSS-specific interpretation that Asterisk itself must present the trusted
public certificate is **SUPERSEDED BY TASK-0035A**. Final release-readiness
closure otherwise stands. See
`docs/tasks/0035a-reverse-proxy-wss-tls-termination-pilot-realignment.md`.

## Predecessor

- Parent: `docs/tasks/0034-release-readiness-production-pilot-gate.md`
- Immediate predecessors: TASK-0034M / 0034N / 0034O / 0034P / 0034Q
- Operational certificate gate history: TASK-0034E / 0034G / 0034H

## Starting state

```text
branch: cursor/cloud-agent-1789228026971-noiwv
HEAD:   8ea14048369e08a0271de6605adecfa0b4e4f069
        (docs: close TASK-0034Q dashboard preferences authorization audit)
git status --short: (clean)
```

## Routing

| Role | Specialist |
|---|---|
| Lead | workflow / orchestration |
| Reviewer | application architecture / security |
| Reviewer | telephony architecture |
| Reviewer | Docker / platform / release |
| Product designer | not required (no new user-facing blocker) |

## Scope discipline

This task did **not**:

- refactor unrelated code;
- redesign architecture;
- fix cosmetic debt;
- create new features;
- reopen closed tasks without new evidence;
- broaden into a new global security audit;
- build a future portal;
- redesign release engineering;
- commit or push.

No product code changes were required. Documentation only.

---

## 0034 closure matrix (authoritative for this review)

Later verified evidence supersedes stale wording in earlier sections of
the parent release-readiness document.

| Item | Original risk / constraint | Task(s) | Current state | Evidence | Pilot impact |
|---|---|---|---|---|---|
| CH-1 Calls Report SQL/PHP fatal | Feature broken end-to-end | 0034A | **CLOSED** | Calls-report smoke PASS in both 0034R regressions; 0034A repair | None (supported) |
| CH-2 WSS fixture cert trust mechanism | Doctor validated fixture, not runtime trust | 0034E | **CLOSED** (implementation) | `make cert-check` / doctor WSS path; 0034E contract | Mechanism closed |
| CH-2 real pilot host cert provisioning | Operator must install real cert | 0034G/H | **CLOSED_WITH_FOLLOW_UP_DEBT** → accepted as **PILOT_CONSTRAINT** | 0034H: no real pilot host/CA in this environment; doctor WARN fixture cert | Must provision real cert on real pilot host before go-live |
| CH-3 provider profile gate | Dev fixture started in production topology | 0034C | **CLOSED** | `profiles: [dev, test]`; `pilot-up` clears `COMPOSE_PROFILES` | None if runbook followed |
| CH-6 AMI flat ACL | Broad AMI trust | 0034F | **CLOSED** | Dedicated `senma-control` network; doctor AMI ACL PASS | Topology remains single-CIDR **PILOT_CONSTRAINT** |
| CH-7 SIP/WSS/RTP host ports | No pilot port publish path | 0034B | **CLOSED** → **PILOT_SUPPORTED** with capacity note | `compose.pilot.yaml`; RTP 10000-10199 | Capacity limit ~100 concurrent calls |
| CH-8 README stale | Docs drift | 0034 (deferred) | **CLOSED_WITH_FOLLOW_UP_DEBT** | Still deferred | **POST_PILOT_DEBT** |
| CH-9 release provenance | No versioned images / OCI labels | 0034D | **CLOSED** | `make release-build`, OCI labels, manifest, `pilot-up` refuses `dev` | Dev env without manifest is expected; pilot must release-build |
| ParametersController write boundary | Read implied write | 0034L | **CLOSED** | `$writeOnPostIndex['default_parameters']` | None |
| Mixed GET/POST index writers (CNL, module-settings, errors-*, conference) | Read implied write | 0034M | **CLOSED** | `$writeOnPostIndex` entries + resources.xml write children | None |
| CNL PHP 8.4 TypeError / import | Import crash | 0034N | **CLOSED** | CNL security + import suites in regression | Residual unlink/symlink = POST_PILOT |
| ITC mandatory interstitial / alwaysAllow writes | System-wide ITC writes for any auth user | 0034O | **CLOSED** | `itc_enabled=false` default; write gates; Register GET no DB mutation | Standalone SENMA contract |
| Notification dismiss alwaysAllow | Shared global write | 0034P | **CLOSED** | `$writeActionsOnAlwaysAllow` + suite | None |
| Dashboard prefs GET mutation / CSRF | State-changing GET | 0034Q | **CLOSED** | POST+CSRF; Model A ownership; suite 19/19 in task; regression | Dead edit.phtml/Title = POST_PILOT |
| System-status / runtime resource | Runtime panels | 0034I/J | **CLOSED** | Suites in regression | Residual harness notes POST_PILOT |
| Call language / pre-auth locale | Locale authority | 0034K | **CLOSED** | Task evidence | None for pilot |
| Backup/restore DR | Ops readiness | 0033a / regression | **CLOSED** | `backup-smoke` PASS ×2 | Backup dir WARN until first backup |
| Migration lifecycle | Schema drift | 0033f / 0034R | **CLOSED** | `make migrate-check` → SCHEMA_CURRENT | None |
| Secrets rotation/match | Secret drift | 0034R live | **CLOSED** | `make secrets-check` OVERALL: MATCH | None |
| PJSIP reconcile | Config drift | 0034R live | **CLOSED** | `make reconcile-check` IN_SYNC | None |

Classification legend used above: **CLOSED** / **CLOSED_WITH_FOLLOW_UP_DEBT** /
**STILL_OPEN_BLOCKER** / **OBSOLETE** / **UNKNOWN_NEEDS_EVIDENCE**.

No row is **STILL_OPEN_BLOCKER**. No row is **UNKNOWN_NEEDS_EVIDENCE** after
this review.

---

## Remaining debt classification

### PILOT_BLOCKER

*(none)*

### PILOT_CONSTRAINT

Must be documented and operationally accepted; pilot may proceed.

1. **Real TLS/WSS certificate on the pilot host** — CH-2 implementation is
   closed; fixture cert must be replaced and `make cert-check PILOT=1` must
   return `PILOT_ACCEPTABLE` on the real host (0034H stop condition).
2. **Concurrent trunk-name allocation collision** — avoid parallel trunk
   creates by multiple admins.
3. **Certificate expiry watch** — manual operational watch; no UI expiry
   warning.
4. **TLS/WSS cert rotation on already-bound port** — requires Asterisk
   restart (documented lifecycle).
5. **AMI ACL single CIDR** — mitigated by dedicated control-plane network;
   do not publish AMI; keep subnet matched to `senma-control`.
6. **RTP published range capacity** — pilot overlay 10000-10199 (~100
   simultaneous calls); widen `compose.pilot.yaml` + `rtp.conf` together if
   needed.
7. **External carrier trunks** — historical live proofs are simulator-
   backed; first real-carrier cutover is soak/ops work (0035), not a code
   blocker.
8. **ITC enabled-mode Register GET** — soft clears session `noregister`
   (re-prompt). Irrelevant while `itc_enabled=false` (default).
9. **Release artifact required for `pilot-up`** — never deploy `senma-*:dev`
   as the pilot identity; run `make release-build VERSION=vX.Y.Z` first.
10. **`provider` fixture** — must remain profile-gated off on pilot hosts.

### POST_PILOT_DEBT

1. Dead dashboard `edit.phtml` / missing `editAction`.
2. Legacy Title.php “add to dashboard” stub.
3. Optional native `.sn-dash-add` href → POST form cleanup (JS interceptor
   sufficient).
4. ITC Register menu visibility while ITC disabled (DISPLAY_ONLY).
5. Future replacement portal (explicit non-goal of 0034O).
6. CNL upload `unlink()` cleanup residual.
7. CNL zip-slip symlink-entry defense-in-depth.
8. README / project-identity doc refresh (historical CH-8).
9. Dead `Snep_Parameters_Manager::change()` removal candidate.
10. Dev seed gap: `core_cnl_country id=76` absent until suite seeds it.
11. Broader §41 POST_PILOT telephony cosmetic/legacy items (InterfaceConf
    leftovers, redundant reloads, IpStatus N.D., etc.) — unchanged, not
    reopened.
12. Harness PJSIP readiness race — mitigated by widened retry (0034Q); keep
    as harness note, not product defect.

### DEAD / OBSOLETE

1. ITC as mandatory registration interstitial for SENMA core.
2. Treating notification dismiss as per-user self-service (disproven; now
   explicit write).
3. Treating dashboard prefs as system-wide write requiring RBAC write
   (Model A proven; method/CSRF fixed).
4. CH-1 / CH-3 / CH-6 / CH-7 / CH-9 as open product blockers.
5. Manufacturing new blockers from closed historical debt.

---

## Architecture invariants (current evidence)

### Telephony

- Supported SIP runtime is **PJSIP** (`res_pjsip.so Running`).
- **`chan_sip` not loaded** (0 modules).
- Generated PJSIP state reconciles from DB (`make reconcile-check` →
  `IN_SYNC` / doctor PJSIP configuration PASS).
- Live transports: `udp`/`tcp` `:5060`, `wss` `:8089`.
- WSS via Asterisk HTTP/HTTPS (`HTTPS Server Enabled and Bound to
  0.0.0.0:8089`, `/ws` enabled).
- TLS/WSS lifecycle (restart for bound-port cert rotation) unchanged from
  established contract.

### Application / security

- Mutating index POSTs inventoried in 0034L/M/O require matching `*_write`.
- Shared notification dismiss requires `default_notifications_write`
  (0034P).
- Dashboard preferences: Model A self-service; GET no longer mutates;
  POST+CSRF (0034Q).
- CSRF remains required on audited mutating POSTs.
- No known audited state-changing GET remains on supported paths covered
  by 0034L–Q.
- `$alwaysAllow` still means authenticated-open **read** (plus legitimate
  self-service dashboard prefs); global writes fall through write maps.

### ITC standalone contract

```text
SENMA core = standalone by default
ITC = optional integration (itc_enabled=false)
```

With ITC disabled (live `setup.conf`): login works; normal navigation
works; no ITC DB mutation required; no external ITC endpoint required; no
mandatory registration interstitial.

### Operations

- Backup/restore suites PASS in both regressions.
- `make doctor` — no FAIL (WARN: fixture cert; backups dir; SKIP: no
  release-manifest in this **dev** environment — expected).
- `make secrets-check` — OVERALL: MATCH.
- `make migrate-check` — SCHEMA_CURRENT.
- `make reconcile-check` — IN_SYNC.
- Pilot compose overlay + runbook remain the supported deployment path.
- AMI/DB not host-published in supported pilot topology.

### Release / provenance

- Contract from 0034D remains: annotated Git tag / explicit VERSION,
  `GIT_COMMIT`, OCI labels on `senma-app`/`senma-asterisk`,
  `release-manifest.json`, `make release-info`, `make pilot-up` refuses
  `RELEASE_VERSION=dev` and missing release images.
- Absence of `release-manifest.json` on this cloud/dev workspace is
  **environment state**, not a product defect.

---

## Security closure review (0034-series surfaces only)

| Question | Answer |
|---|---|
| Known authenticated low-privilege user can perform system/global write without explicit legitimate boundary? | **No** on audited surfaces (Parameters, CNL/module-settings/errors/conference, ITC POSTs, notification dismiss). Dashboard prefs are intentional **per-user** self-service. |
| Audited state-changing GET still present on supported paths? | **No** (Register GET mutation removed in 0034O; dashboard GET add removed in 0034Q; notifications GET no longer setRead). |
| Known CSRF gap on audited write path? | **No** (dashboard add moved to CSRF-backed POST). |
| Unintentional public/anonymous write path? | **No** evidence on audited surfaces (`$alwaysAllow` still requires authentication). |

Not a new full-repo security audit.

---

## Runtime sanity (this session)

| Check | Result |
|---|---|
| Container health (settled) | app/asterisk/db healthy |
| `make doctor` (settled stack) | **PASS** (exit 0; WARN fixture cert / backups; SKIP release-manifest) |
| `make secrets-check` | **PASS** MATCH |
| `make migrate-check` | **PASS** SCHEMA_CURRENT |
| `make reconcile-check` | **PASS** (`status: IN_SYNC`) |
| Asterisk / PJSIP / HTTP-WSS | PASS (see invariants) |
| App → DB | PASS |
| AMI control path | PASS (doctor + ACL) |

Note: `secrets-check`/`migrate-check`/`reconcile-check` recipes rebuild/
recreate app+asterisk; doctor was re-run after the stack settled to avoid
false SKIP from mid-recreation races. No manual state repair was applied
to force green results.

---

## Canonical gates

| Gate | Result |
|---|---|
| `make lint` | **PASS** (5/5) |
| `make regression` #1 | **PASS** (48 suites; ~16 min) |
| `make regression` #2 | **PASS** (48 suites; consecutive; no repair between) |
| `git diff --check` | **PASS** |
| `git status --short` (pre-doc) | clean |

Interrupted runs: none counted.

---

## Pilot deployment checklist (operator-facing)

Based only on existing Makefile/runbook support
(`docs/operations/production-release-runbook.md`):

1. **Host**: Debian 14 + Docker Engine + Compose v2; pilot network plan.
2. **Checkout**: annotated release tag (`vX.Y.Z`).
3. **Config**: copy `.env.example` → `.env`; set unique `DB_*` / `AMI_*`;
   keep AMI ACL on dedicated control subnet; never publish AMI/DB.
4. **Do not** enable `COMPOSE_PROFILES=dev|test` / provider fixture.
5. **Release identity**: `make release-build VERSION=vX.Y.Z` (clean tree);
   verify OCI labels / `make release-info`; confirm `release-manifest.json`.
6. **Pilot topology**: `export RELEASE_VERSION=vX.Y.Z` then `make pilot-up`
   (`compose.yaml` + `compose.pilot.yaml`; images `senma-app` /
   `senma-asterisk` at that version).
7. **TLS/WSS**: replace fixture cert; set public hostname;
   `make cert-check PILOT=1` → pilot-acceptable; prove WSS REGISTER if
   WSS is in scope.
8. **`make migrate-check`** → `SCHEMA_CURRENT` (or migrate then re-check).
9. **`make secrets-check`** → `OVERALL: MATCH`.
10. **`make reconcile-check`** → `status: IN_SYNC`.
11. **`make doctor`** → no FAIL; resolve WARNs before go-live.
12. **Backup readiness**: ensure backup destination; take first
    `make backup` before soak.
13. **Post-deploy**: login; create extension; register; place test call;
    CDR readback; trunk path as scoped.
14. **Rollback prerequisite**: known-good prior release images + last good
    backup retained before upgrade.

Do not invent automation beyond these existing targets.

---

## Final decision

```text
READY_WITH_NON_BLOCKING_DEBT
```

Rationale:

- No open pilot blocker remains under current evidence.
- Canonical lint + two consecutive full regressions PASS.
- Telephony, application/security, ITC standalone, ops, and release
  contracts are proven or explicitly constrained.
- Non-blocking debt and pilot constraints remain and are listed above;
  they are operationally acceptable for a controlled production pilot
  when the checklist is followed (especially real WSS cert + release
  build + provider off).

Not `READY_FOR_PRODUCTION_PILOT` only because accepted constraints and
documented non-blocking debt still exist and must travel with the pilot
(especially real-host certificate provisioning from 0034H).

Not `NOT_READY_BLOCKED`: no concrete reproducible blocker found.

---

## Next phase recommendation

**TASK-0035 — Pilot Deployment & Soak Validation** on a real pilot host:

1. Provision real hostname/DNS + trusted WSS/TLS certificate.
2. Build/deploy release artifacts (`release-build` / `pilot-up`).
3. Execute the checklist above end-to-end.
4. Soak: registration, calls, CDR, backup, cert trust, no provider
   fixture, external trunk cutover as scoped.
5. Track POST_PILOT debt separately; do not reopen closed 0034 decisions
   without new evidence.

---

## Evidence index (this session)

- HEAD: `8ea14048369e08a0271de6605adecfa0b4e4f069`
- Logs: `/tmp/0034r-doctor2.log`, `/tmp/0034r-secrets.log`,
  `/tmp/0034r-migrate.log`, `/tmp/0034r-reconcile.log`,
  `/tmp/0034r-lint.log`, `/tmp/0034r-regression1.log`,
  `/tmp/0034r-regression2.log`
- Live `itc_enabled = "false"` in app `setup.conf`
- PJSIP transports / `chan_sip` unloaded / HTTP-WSS bound

## Commit note

Documentation produced for an explicit commit checkpoint. **No commit or
push was performed in this task** (per task authorization).
