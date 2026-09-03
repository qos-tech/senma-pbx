# The Nexus contract: where the method reads and writes

This method runs inside Nexus Studio. Its files no longer live under `_evo/`
and there is no `sprint-status.yaml`, no `active_feature`, and no separate
`planning_artifacts` / `implementation_artifacts` trees. Everything is under
`<project-root>/.nexus/`, and this file is the one place that says what maps to
what. Every workflow reads this contract; nothing hard-codes the old paths.

## The layout

```
<project-root>/.nexus/
  project.yaml                   identity, the active feature (a filter), active sprint
  board.yaml                     the board, an ordered list of items, ONE writer: the app
  features/<FEATURE-KEY>/        one feature's planning docs: brief · prd · ux · architecture · epics
  issues/<KEY>.md                one issue = one board card (feature is an OPTIONAL field)
  specs/<KEY>/<spec>.md          specs of issue <KEY> (a spec is one method "story")
  sprints/<SPRINT-KEY>.yaml      a timebox: which issues, its dates (app-written)
  docs/                          project-level only: index · source-tree · overview · deep-dive
  runs/<KEY>/*.jsonl             run records, app-written, gitignored
  runs/queued-messages.jsonl     messages waiting for a running agent, app-written, gitignored
  method/                        this method, installed into the project
```

## Name-for-name

| Old evo name | Nexus | Notes |
|---|---|---|
| `{project-root}/_evo/bmm/...` | `{project-root}/.nexus/method/...` | the method is installed here |
| `_evo/bmm/config.yaml` | `.nexus/project.yaml` | project name, language, active feature |
| `planning_artifacts` (per-feature) | `.nexus/features/<FEATURE-KEY>/` | prd, architecture, brief, epics, ux, a feature owns them as a set |
| `planning_artifacts` (project-level) | `.nexus/docs/` | document-project output: index, source-tree, overview, deep-dive |
| `implementation_artifacts` | `.nexus/specs/` | grouped by issue, see below |
| `prd_file` | `.nexus/features/<FEATURE-KEY>/prd.md` | |
| `architecture_file` | `.nexus/features/<FEATURE-KEY>/architecture.md` | |
| `epics_file` | `.nexus/features/<FEATURE-KEY>/epics.md` | the source the board reads from |
| `ux_file` | `.nexus/features/<FEATURE-KEY>/ux.md` | |
| `sprint-status.yaml` | `.nexus/board.yaml` (read) + `.nexus/sprints/<KEY>.yaml` | the board is an ordered list, one writer: the app. A workflow READS it |
| a "story" file | `.nexus/specs/<ISSUE-KEY>/<spec-key>.md` | one story = one spec |
| `{active_feature}` folder | `.nexus/features/<FEATURE-KEY>/` for planning docs | feature is a FIELD on the issue (filters the board) AND a FOLDER for a feature's planning docs. Both hold. Optional: quick/manual issues carry no feature |
| `default_output_file` for a story | `.nexus/specs/<ISSUE-KEY>/<spec-key>.md` | |

## The rules that changed, and why

- **The board has one writer: the app.** A workflow READS `board.yaml` to find
  what to work on; it never writes it. Column moves happen because the app
  reacts to the run. So the old "update sprint-status.yaml" steps become
  "update the issue and its specs", the board follows.
- **Typed sections, not a prose blob.** An issue's frontmatter carries
  `context` (the description), `criteria` (acceptance criteria as a list), and
  `comments`. A spec's frontmatter carries `story`, `criteria`, `tasks`, and
  `links`. The markdown body (`## Context`, `## Acceptance Criteria`,
  `## Tasks / Subtasks`) is generated from the frontmatter, write the
  frontmatter, and the body follows. See `method/schema/`.
- **A spec is a story.** The method's story shape (Story, Acceptance Criteria,
  Tasks/Subtasks, Dev Agent Record) is the spec. `create-story` writes a spec
  under `.nexus/specs/<ISSUE-KEY>/`; `dev-story` implements it and checks its
  tasks off; `code-review` reviews it.
- **No `active_feature` folder switching.** Where a workflow used
  `{implementation_artifacts}/{active_feature}/...`, it uses
  `.nexus/specs/<ISSUE-KEY>/...`. The active feature is a field on
  `project.yaml` that filters the board, and moves nothing.
- **The write boundary holds.** An agent modifies only: a spec's `tasks[].done`
  and its Dev Agent Record; and appends a comment to the issue's frontmatter
  (`who: "agent:<id>"`). It does not write the board, the issue's context, or
  its criteria, those are the author's.
- **Frontmatter has TWO fences.** `---` on its own line at the top, and a second
  `---` on its own line where it ends. A comment appended to the frontmatter goes
  BEFORE the closing fence, and that fence must still be there when you save.
  An agent wrote past it on 2026-08-14 and the whole issue, its artifacts and
  every comment on it, stopped being readable for one missing line. **Read the
  file back after writing it and check both fences are present.**
- **English in the product.** Method output written into the repo is English;
  conversation with the user follows the user's language setting.
