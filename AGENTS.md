# SENMA PBX Agent Instructions

Read and follow `CLAUDE.md` before making changes.

This repository uses a checkpoint-driven engineering workflow.

## Core behavior

- Prefer evidence from the current runtime over assumptions, comments, or historical behavior.
- Reproduce bugs before fixing them whenever practical.
- Keep changes small, isolated, reversible, and within the current task scope.
- Do not perform opportunistic refactors.
- Preserve customer-owned configuration and data.
- Do not weaken security controls to make tests pass.
- Do not silently reinterpret existing architecture decisions.

## Task execution

Before implementing:

1. Read the current task.
2. Inspect relevant predecessor task documents under `docs/tasks/`.
3. Inventory the current implementation.
4. Reproduce the issue or verify the current state.
5. Identify the root cause.
6. Define the supported contract.
7. Implement the smallest coherent fix.
8. Run focused validation.
9. Run canonical gates when required.

## Git

- Never commit automatically.
- Never push automatically.
- Never amend or rebase unless explicitly authorized.
- Never use `git add .`.
- Use explicit staging.
- If the working tree contains unrelated changes, do not touch or stage them.

## Validation

Canonical gates normally include:

```bash
make lint
make regression
make regression
git diff --check
git status --short
```

Some tasks also require:

```bash
make doctor
make secrets-check
make migrate-check
make reconcile-check
```

Two consecutive clean regression passes are required when defined by the task.

Do not manually repair or reset the stack between consecutive regression runs unless the task explicitly allows it.

## Reporting

Use precise result states such as:

- PASS
- FAIL
- BLOCKED
- PARTIAL
- NOT_RUN

Do not report a test as passed if it did not complete successfully.

Do not create commits unless the user explicitly authorizes them.
