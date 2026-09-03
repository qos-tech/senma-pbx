---
description: Review the current branch or requested diff against QoS engineering rules, project architecture, specs and tests. Read-only; never edits or commits.
argument-hint: '[base-branch-or-range]'
allowed-tools: Read, Glob, Grep, Bash
---

# review

Perform a read-only pre-merge review. Default comparison is the merge base with the repository default branch through `HEAD`; use `$ARGUMENTS` when a range or base is supplied.

Read `AGENTS.md`, relevant `docs/agents/*`, applicable `.spec/` artifacts, the diff and tests. Report findings ordered by severity:

- **BLOCKER** — data loss, security issue, broken contract, migration risk or clearly incomplete requirement.
- **HIGH** — likely regression, missing critical test or architecture violation.
- **MEDIUM** — maintainability, incomplete edge case or documentation drift.
- **LOW** — optional improvement.

For every finding include file and line, evidence, impact and concrete remediation. Then report requirement coverage, tests executed or inspected, and residual risks. If no findings exist, say so explicitly and list what was checked. Never modify files, stage or commit.
