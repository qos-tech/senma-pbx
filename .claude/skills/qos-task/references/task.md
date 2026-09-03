---
description: Turn a small, well-bounded change into an executable QoS task document under .spec/tasks/ without using the full feature planning pipeline.
argument-hint: '"task description" or path-to-description'
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion
---

# task

Create one self-contained task document for a change that should fit in a single Ralph phase.

## Input

`$ARGUMENTS`

Resolve a file path when supplied; otherwise treat the arguments as the task description. Read `AGENTS.md`, relevant `docs/agents/*`, manifests, tests and the affected code before writing.

## Output

Write `.spec/tasks/<slug>.md` using exactly this execution contract:

```markdown
## Phase 1: <short title>

- [ ] **Task:** <implementation task>
  - **Context:** <current behavior and affected areas>
  - **Acceptance criteria:**
    - <binary criterion>
  - **Tests:**
    - <test or explicit reason no automated test applies>
  - **Files likely affected:**
    - `<path>`
```

Include all necessary dependencies inside the single phase. Do not write application code. Do not include secrets. End with:

```bash
./scripts/ralph.sh .spec/tasks/<slug>.md
```
