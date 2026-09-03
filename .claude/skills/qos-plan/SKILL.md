---
name: qos-plan
description: Plan a feature into SPEC.md, PLAN.md and Ralph-compatible PHASES.md using QoS engineering rules.
---

Plan the requested feature using the same semantics as the QoS Claude plugin.

1. Read `references/plan.md`, `references/specifier.md`, `references/clarifier.md`, `references/planner.md`, and the repository's `qos/engineering-principles.md` when present.
2. Replace Claude subagent delegation with sequential role passes in the current Codex session: first Specifier, then Clarifier when required, then Planner. Keep each role's contract and validation gates intact.
3. Use the user's arguments as the feature description or file path.
4. Preserve human checkpoints. Do not write application code.
5. Produce `.spec/features/<slug>/SPEC.md`, `PLAN.md`, `PHASES.md`, and conditional API contracts exactly as defined.
