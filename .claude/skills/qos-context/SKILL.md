---
name: qos-context
description: Generate or refresh AGENTS.md, CLAUDE.md and docs/agents from implemented code only.
---

Read all files in `references/`. Execute the context workflow while adapting Claude agent delegation into three role passes: Inspector first, then Core Writer and Documentation Writer. The two writer scopes are disjoint; preserve ownership banners, `--adopt`, filtering, reality-only rules and verification checks. Never read `.spec/` as evidence for implemented reality.
