
## TASK-0035A amendment (WSS TLS termination)

**SUPERSEDED BY TASK-0035A** for the WSS/certificate ownership assumption only:

- Old assumption: Asterisk `:8089` must present the trusted public WSS certificate.
- New supported model: public WSS TLS terminates at the SENMA reverse proxy
  (Apache in `app`); Asterisk receives private `ws://asterisk:8088/ws`.
- See `docs/tasks/0035a-reverse-proxy-wss-tls-termination-pilot-realignment.md`.
- WebRTC endpoint/media contract: see
  `docs/tasks/0035b-webrtc-endpoint-contract-real-media-validation.md`.
- Real browser / NAT / TURN validation: see
  `docs/tasks/0035c-real-browser-webrtc-internet-nat-turn-validation.md`
  (`REAL_BROWSER_WEBRTC_PASS_WITH_CONSTRAINTS`,
  `TURN_REQUIREMENT_INCONCLUSIVE`).

Unrelated TASK-0035 evidence (release/provenance/topology/migrate/secrets/
reconcile/doctor-non-WSS/backup/restart/lint/regressions) remains **STILL_VALID**.
The operational need for a non-fixture public certificate + DNS hostname remains,
but that certificate now belongs on the reverse proxy, not on Asterisk HTTP TLS.

# TASK-0035 — Pilot Deployment & Soak Validation

## SUPERSEDED BY EXECUTION RECORD

This file is the **pre-execution planning/stop record** (Phase 1 gate
before a real pilot host existed). The authoritative TASK-0035 execution
and decision live in:

`docs/tasks/0035-production-pilot-deployment-soak-validation.md`

**Decision there: `PILOT_DEPLOYMENT_BLOCKED`** (no authorized real pilot
host / public DNS / trusted WSS certificate on the available agent).
Do not treat this stub as the current status.

## LEAD

`senma-workflow-orchestrator`

## REVIEWERS

None invoked. Per the routing principle in `senma-workflow-orchestrator`
("add reviewers only when their domain is materially affected") and the
anti-ceremony rule, `senma-docker-platform-engineer`,
`senma-telephony-architect`, and `senma-application-architect` were not
engaged as separate sessions — this task's own Phase 1 gate stopped
execution before any deployment, network, telephony, or application
work existed for a domain specialist to review. `senma-asterisk-pjsip-engineer`
and `senma-product-designer` were not invoked — no telephony runtime
defect and no pilot feedback exist yet to trigger either.

Orchestrated by `senma-workflow-orchestrator`.

## PURPOSE

Deploy SENMA onto a real pilot environment and validate it through a
controlled soak period, per this task's own Phase 1–75 procedure, to
answer whether the system remains healthy, operational, recoverable and
usable under real pilot conditions long enough to justify broader
rollout — and, if a real trusted WSS certificate is provisioned during
this pilot, to close TASK-0034H's remaining `OPEN_CONSTRAINT` and
promote `TASK-0034` from `PILOT_GO_WITH_CONSTRAINTS` to `COMPLETE`/
`PILOT_GO`.

## SCOPE

**IN SCOPE** (as specified): real pilot deployment, real pilot
certificate prerequisite, pilot acceptance, real call validation,
runtime observation, backup verification, resource observation,
incident classification, soak period, final pilot decision.

**OUT OF SCOPE** (as specified): major feature development, HA,
multi-tenant redesign, new telephony protocol, monitoring-platform
rollout, automatic ACME implementation, large UX redesign, unrelated
technical debt.

**Executed in this session**: Phase 1 gate check only (identify actual
pilot environment). No deployment, configuration, or infrastructure
change was made or attempted.

## FINDINGS

**Task's own Phase 1 instruction:**
> "If no real pilot environment exists yet: BLOCK. This task cannot be
> meaningfully completed on the dev machine alone."

**Prior evidence (TASK-0034H, same commit lineage, `docs/tasks/0034h-pilot-host-wss-certificate-provisioning-final-go-gate.md`):**
that session already established, live and user-confirmed, that no real
pilot host exists separately from this development machine's local
Docker Desktop stack, no real public DNS hostname is recorded anywhere
in the repository, and no access to a public/enterprise CA exists. The
user explicitly directed that session not to simulate or fabricate a
production CA/certificate.

**Re-verified fresh in this session, before assuming that finding still
holds:**
```
$ git log -1 --oneline
6b82377 docs(release): record TASK-0034H pilot WSS certificate block
$ git status --short
(clean)
```
`6b82377` is TASK-0034H's own documentation commit — no product/platform
commits since. `.nexus/` does not exist in this repository (the
project's Nexus Studio board/tracking described in `CLAUDE.md` is not
present here; routing was done directly via the SENMA orchestrator
skill instead).

```
$ grep -i "WSS_PUBLIC_HOSTNAME\|PILOT" .env
(no output — WSS_PUBLIC_HOSTNAME is present but empty)
$ find docs/operations -iname "*pilot*"
(none — no pilot-soak-log exists yet)
$ find docs/tasks -iname "*0035*"
(none, prior to this session)
```
No pilot host record, no DNS record, no certificate plan, and no prior
`TASK-0035` documentation exist anywhere in the repository.

**User confirmation (this session, `AskUserQuestion`):** asked directly
whether a real external pilot environment (customer/site host, reachable
IP, DNS, provider) now exists, separate from the local Docker Desktop
stack used for TASK-0034. **User answered: no real pilot host yet.**

## DECISION

Unchanged from TASK-0034H: there is still no real pilot host, DNS, or
trusted-CA path available to this session or the project. This task's
own Phase 1 explicitly requires `BLOCK` under exactly this condition,
and the user has now confirmed directly (not merely by prior-session
citation) that the condition still holds. Proceeding into Phase 2
onward (pilot scope, success criteria, deployment, soak) would mean
running the entire procedure against this same dev machine relabeled as
a "pilot" — the same substitution TASK-0034H's Critical rule and the
user already rejected once. Doing so here would misrepresent the pilot
outcome this document exists to record honestly, and would not answer
the actual question this task asks: whether SENMA survives *real* pilot
conditions.

No product, platform, or configuration change was made. No specialist
was engaged, because no domain work exists yet for a specialist to
perform.

## CHANGES

**PRODUCTION**: none.

**PLATFORM/TOOLING**: none.

**TEST**: none.

**DOCUMENTATION**: this file only.

## VALIDATION

Gate check only — no deployment-phase validation (Phases 2–76) applies
yet:

- `git log -1 --oneline` → `6b82377` (TASK-0034H's own commit; no drift).
- `git status --short` → clean, before and after this session.
- `.env` inspected → `WSS_PUBLIC_HOSTNAME` unset; no pilot host/DNS
  values present.
- Repository searched for existing pilot host/DNS/certificate records
  and prior `TASK-0035` documentation → none found.
- User asked directly whether real pilot infrastructure now exists →
  confirmed it does not.

`make lint` / `make regression` / `git diff --check` were not run — no
code or configuration was touched, so canonical validation does not
apply to a documentation-only Phase-1 gate check.

## REMAINING DEBT

Unchanged from TASK-0034 / TASK-0034H, carried forward:

- **The one `OPEN_CONSTRAINT`**: provision a real pilot hostname/DNS, a
  real trusted (public or enterprise) CA-issued certificate for it, and
  obtain `make cert-check PILOT=1` → `PILOT_ACCEPTABLE` plus a verified
  (non-`CERT_NONE`) WSS SIP REGISTER, on an actual pilot host. This
  remains an operator/infrastructure prerequisite, not a code task.
- F1/F2/F3 from TASK-0034G/H (`release-manifest.json` operator-hygiene
  DRIFT note, `ami-acl-smoke`'s missing `FIXTURE_PROFILE=test` Makefile
  wiring, `readiness-smoke-test.sh`'s standalone timing race) — unchanged,
  not reconfirmed in this session (no commands were run against the
  stack), still `FOLLOW_UP_DEBT`.
- Pre-existing, unaffected: CH-7's RTP capacity note, CH-8 (stale
  README), base-image digest pinning (still tag-only), non-atomic
  trunk-name collision, no cert-expiry UI warning — all unchanged,
  `PILOT_CONSTRAINT`/`POST_PILOT` as already carried in TASK-0034.

## RECOMMENDATION

`BLOCK`.

**Required initial checkpoint (per task instructions):**

1. Actual pilot environment: **none exists** — only this development
   machine's local Docker Desktop stack (same as TASK-0034B–H).
2. Actual pilot scope: not defined — blocked before Phase 2.
3. Soak duration selected: N/A.
4. Minimum traffic sample: N/A.
5. Release version: `v0.1.0-rc.1` (last certified in TASK-0034G; not
   redeployed this session).
6. Release commit: `6b82377` (HEAD; TASK-0034H's own documentation
   commit, layered on `cdefd57`/`3d3e1c4`, the commits TASK-0034G
   certified).
7. release-info: not re-run this session (last known: `DRIFT`, expected
   dev-mode-stack/F1, per TASK-0034H).
8. DNS: none provisioned.
9. WSS certificate state: unchanged dev fixture
   (`CN=senma-wss-test`, self-signed), per TASK-0034H's last reading.
10. cert-check PILOT=1: not re-run this session (last known:
    `NOT_ACCEPTABLE_FOR_PILOT`, per TASK-0034H).
11. Network exposure: not re-verified this session.
12. AMI ACL: not re-verified this session.
13. Doctor: not re-run this session.
14. Secrets: not re-run this session.
15. Schema: not re-run this session.
16. Reconcile: not re-run this session.
17. Readiness: not applicable — no pilot deployment attempted.
18. Initial extension proof: N/A.
19. Initial trunk proof: N/A.
20. Inbound call: N/A.
21. Outbound call: N/A.
22. Internal call: N/A.
23. WSS REGISTER if applicable: N/A.
24. Backup status: N/A.
25. Pilot start timestamp: **not started**.
26. Current blockers: **no real pilot host/DNS/trusted-certificate
    infrastructure exists**, confirmed directly by the user in this
    session.
27. Current constraints: TASK-0034's single carried `OPEN_CONSTRAINT`
    (real WSS certificate provisioning) remains outstanding and is this
    task's explicit prerequisite.

**Return: `BLOCK`.**

`TASK-0034` is unaffected and stays exactly at `PILOT_GO_WITH_CONSTRAINTS`
(TASK-0034H's own outcome) — this session found nothing to promote or
regress it. Recommend `TASK-0035` remains open and un-started until a
real pilot site (host, DNS, trusted certificate path) is actually
available; re-run this Phase 1 gate at that time rather than opening a
numbered follow-up task, since no implementation work exists yet to
split off.

## PROPOSED COMMIT

```
docs(release): record TASK-0035 pilot-deployment BLOCK (no real pilot environment)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01APVko5xxm3Vbq8o7UJYK4X
```

Scope: this file only. Not created automatically per this project's
commit policy — awaiting authorization.
