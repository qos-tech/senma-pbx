# Method: origin and attribution

This directory is the method of Nexus Studio. Like `apps/memory`, it is **not a
dependency and not a submodule**: the files live here and ship with the product.

## Where it came from

Copied whole from [`EvolutionAPI/EVO-METHOD`](https://github.com/EvolutionAPI/EVO-METHOD)
at commit `59b61d94` on 2026-08-12, itself an MIT fork of
[`bmad-code-org/BMAD-METHOD`](https://github.com/bmad-code-org/BMAD-METHOD).

Copied at import: `agents/` (9 agents), `workflows/` (the bmm set),
`core/` (brainstorming, elicitation, party-mode), `utility/` (agent compile
fragments), `module-help.csv` (the 33-workflow catalog).

**The files arrive by copy, never by retyping.** A rewrite burns effort and
loses content; a copy is complete by construction. Adaptations to the Studio
schema are edits on top, one concern per commit, findable in history.

## Changes on top of the copy

- `agents/qa.agent.yaml`: `metadata.id` gained the `.md` extension the other
  eight always had. Upstream defect, found 2026-08-12.

## What will change here (planned, slice 10)

- Workflow paths stop pointing at `_evo/` and `{project-root}/_evo/bmm/config.yaml`;
  they read `.nexus/` and the Studio schema instead.
- `sprint-status.yaml` (flat map, order-sensitive) is replaced by `board.yaml`
  (ordered list) from `method/schema/`.
- The "SAVE QUESTIONS for the end" policy inverts: with a question modal on
  screen, holding questions makes no sense.
