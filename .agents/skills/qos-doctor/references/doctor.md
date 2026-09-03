---
description: Diagnose whether a repository is ready for QoS Harness workflows and autonomous Ralph execution. Read-only.
allowed-tools: Read, Glob, Grep, Bash
---

# doctor

Run a read-only readiness diagnosis. Check Git repository status, clean working tree, `AGENTS.md`, `.spec/`, test command detection, executable `scripts/ralph.sh`, Codex CLI, Claude CLI, Docker/Sail when applicable, and notification configuration names without printing secret values.

Return a table with PASS/WARN/FAIL, evidence and remediation. Do not install packages, edit files, start containers or expose credentials.
