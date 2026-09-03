---
name: qos-init
description: Inspect and advance the QoS project initialization specification chain.
---

Use this skill to inspect and advance the QoS init specification chain.

Read `references/init.md` and follow it as the authoritative workflow. Wherever it says to invoke a Claude slash command, execute the corresponding referenced workflow directly:

- project description → `$qos-init-project-description`
- user stories → `$qos-init-user-stories`
- database schema → `$qos-init-database-schema`
- project phases → `$qos-init-project-phases`

Advance only one missing or stale artifact per invocation. Preserve the stamps and `.spec/init/design/` contract.
