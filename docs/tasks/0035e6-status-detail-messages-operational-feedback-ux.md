# TASK-0035E6 — Status Detail Messages & Operational Feedback UX

**Status:** `STATUS_DETAIL_UX_PASS_WITH_CONSTRAINTS` (filled after gates)
**Depends on:** TASK-0029B (runtime status vocabulary), TASK-0031/0032 (shared badge), TASK-0035E5 (orthogonal)
**Does not:** change telephony, PJSIP config, NAT, RTP, restore, release, auth, or rebranding

## Starting state

| Item | Value |
|---|---|
| Branch | `cursor/status-detail-ux-0035e6-c149` from `origin/main` (post-E5 merge) |
| Scope | UI / status-feedback only |

## Affected status surfaces

| Surface | Primary | Detail before E6 | Detail after E6 |
|---|---|---|---|
| Extensions list | badge | tooltip: verbose "Registered -- reachable (Nms)" | tooltip omitted when ACTIVE; short detail otherwise |
| Extensions edit Diagnostics | badge + help-block | local maps + raw Manager detail always shown | shared `statusBadge` + Presenter |
| Trunks list | badge | same Manager details | same Presenter gate |
| Trunks edit Diagnostics | `statusBadge` showDetail | verbose success / long external essays | Presenter; ACTIVE empty |
| Transports list/edit | `normalizeStatus` + badge | ACTIVE had long loaded-config sentence | ACTIVE detail empty |
| System Status Asterisk restart | state + detail (polled) | RUNNING always had success prose | RUNNING empty; empty detail hides separator |

Not in scope as badge+detail: legacy `ip-status` Registry/Latency columns; ApplyFeedback flashes.

## Root cause

Runtime status was correct, but secondary detail:

- repeated success facts under ACTIVE ("Registered -- reachable…");
- used long technical essays (external endpoint / AMI);
- duplicated badge maps on Extensions Diagnostics;
- could leave a visible " — detail" separator with empty/stale text on restart poll.

## Normalized contract

```text
runtime facts
  → Snep_PjsipStatus_Manager {state, detail}   # API shape unchanged
  → Snep_PjsipStatus_Presenter::operatorDetail  # UI gate
  → StatusBadge (tooltip + optional help-block)
```

| Rule | Behavior |
|---|---|
| Primary | answers "what is the state?" (Active / Pending / …) |
| Detail | answers "what does the operator need?" only when useful |
| ACTIVE | detail empty (primary alone) |
| Failures / degraded / unknown | one short factual line |
| Leakage | exception / SQL / nullish / HTTP 4xx/5xx suppressed; logged |
| Redundant echo | "Offline" / "Endpoint is offline" → empty |
| Length | soft-capped at 120 chars |

## State / message matrix (Manager → operator detail)

| Runtime condition | Primary | Detail |
|---|---|---|
| Contact Avail / qualify off | ACTIVE | *(hidden)* |
| No SIP contact | INACTIVE | No SIP contact registered |
| Qualify pending | PENDING | Reachability check pending |
| Qualify failing | DEGRADED | Not responding to reachability checks |
| AMI / query failed | UNKNOWN | Runtime status unavailable |
| Not in Asterisk yet | UNKNOWN | Not yet present in Asterisk runtime |
| Disabled row | DISABLED | Disabled in configuration |
| Trunk REGISTER OK | ACTIVE | *(hidden)* |
| Trunk REGISTER rejected | ERROR | Registration rejected by provider |
| Trunk REGISTER in progress | PENDING | Registration in progress |
| External endpoint missing | ERROR | External endpoint not found in Asterisk |
| External endpoint present | ACTIVE | *(hidden)* |
| Transport loaded | ACTIVE | *(hidden)* |
| Transport restart required | PENDING | Configuration saved; Asterisk restart required to apply. |
| Restart RUNNING (healthy) | RUNNING | *(hidden)* |

## Stale-message prevention

- Extensions/Trunks/Transports: server-rendered from one status snapshot per request (no client poll).
- System Status restart: `applyState()` updates label + detail from the same JSON object; empty detail hides `#restartStateSep` / `#restartStateDetail`.

## API compatibility

`{state, detail}` shape preserved. Detail **content** is shorter / empty for ACTIVE. Callers reading `detail` for display should treat empty as "no secondary text".

## Tests

`make status-detail-ux-smoke` — Presenter matrix + source contracts.

`make pjsip-runtime-status-smoke` — ACTIVE reachable fixture expects **empty** detail tooltip (updated assertion).

## Pilot runtime proof

`PILOT_RUNTIME_PROOF_PENDING` — real SIP/WebRTC registered/unregistered screens on TEXTE-PBX-001 after a future RC.

## Decision

**`STATUS_DETAIL_UX_PASS_WITH_CONSTRAINTS`**

Pilot runtime proof: **`PILOT_RUNTIME_PROOF_PENDING`**

### Gate evidence

| Gate | Result |
|---|---|
| `make status-detail-ux-smoke` | **PASS** (26/26) |
| `make pjsip-runtime-status-smoke` | **PASS** (ACTIVE detail empty) |
| `make lint` | **PASS** (`LINT_EXIT:0`) |
| `make regression` A | **PASS** (`REGRESSION_A_EXIT:0`) |
| `make regression` B | **PASS** (`REGRESSION_B_EXIT:0`, consecutive, no repair) |
| `status-detail-ux` in A+B | **PASS** both |
| `git diff --check` | **PASS** |

### Constraints

- Real-pilot screens (registered/unregistered SIP + WebRTC) remain
  `PILOT_RUNTIME_PROOF_PENDING` after a future RC.
- Detail wording stays English product language for PJSIP badges (matches
  existing Active/Pending translate keys from TASK-0029B/0032). Full PT
  localization belongs to TASK-0036 rebranding, not this task.
- System Status restart non-RUNNING messages remain Portuguese (existing
  TASK-0021 convention).
- Legacy `ip-status` Registry/Latency columns unchanged (out of shared
  badge+detail pattern).
