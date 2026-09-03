---
name: qos-docs
description: Create, review, update, and synchronize project documentation using repository evidence.
---

# QoS Docs

Use this skill to create or maintain documentation for any software project.

Read `references/docs.md` before changing files.

## Responsibilities

- Inspect the repository before documenting it.
- Treat implemented code, configuration, scripts, tests, and tracked decisions as the source of truth.
- Create or update README files, guides, examples, architecture documents, and translations.
- Preserve correct existing content instead of rewriting blindly.
- Remove obsolete, contradictory, duplicated, or unverifiable documentation.
- Verify every documented command, path, option, configuration key, and capability.
- Keep examples executable and synchronized with the implementation.
- Clearly distinguish implemented, experimental, planned, deprecated, and unsupported behavior.
- Never present planned functionality as available.
- Keep translations semantically synchronized with the canonical document.
- Run relevant validation checks before finishing.

## Workflow

1. Discover the repository structure, stack, entry points, scripts, and existing documentation.
2. Identify the intended audience and documentation goal from the request.
3. Determine which document is canonical when multiple languages or variants exist.
4. Compare current documentation against repository evidence.
5. Produce a concise change plan.
6. Update the canonical documentation first.
7. Update translations or secondary documents from the canonical version.
8. Validate commands, paths, configuration examples, links, and code snippets.
9. Run available documentation and project checks.
10. Summarize changes, validations, and unresolved uncertainties.

## Constraints

- Do not invent capabilities.
- Do not silently remove valid project-specific decisions.
- Do not expose credentials, tokens, private URLs, personal data, or sensitive configuration.
- Do not replace precise technical documentation with marketing language.
- Do not add badges, compatibility claims, version requirements, or support guarantees unless they are verifiable.
- Do not assume README filenames, languages, stacks, package managers, or deployment platforms.
- Do not create tests merely to assert exact prose unless they protect deterministic contracts such as commands, paths, examples, or required sections.
