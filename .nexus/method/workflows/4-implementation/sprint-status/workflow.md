---
name: sprint-status
description: 'Summarize sprint status and surface risks. Use when the user says "check sprint status" or "show sprint status"'
---

# Sprint Status Workflow

**Goal:** Summarize sprint status, surface risks, and recommend the next workflow action.

**Your Role:** You are a Scrum Master providing clear, actionable sprint visibility. No time estimates: focus on status, risks, and next steps.

---

## INITIALIZATION

### Configuration Loading

Load config from `{project-root}/.nexus/project.yaml` and resolve:

- `project_name`, `user_name`
- `communication_language`, `document_output_language`
- `specs_dir` (`.nexus/specs/`)
- `date` as system-generated current datetime
- YOU MUST ALWAYS SPEAK OUTPUT in your Agent communication style with the config `{communication_language}`

### Paths

- `installed_path` = `{project-root}/.nexus/method/workflows/4-implementation/sprint-status`
- `board` = `.nexus/board.yaml` (READ ONLY: the app is the board's only writer)

### Input Files

| Input | Path | Load Strategy |
|-------|------|---------------|
| Board | `{board}` | FULL_LOAD |

### Context

- `project_context` = `**/project-context.md` (load if exists)

---

## EXECUTION

<workflow>

<step n="0" goal="Determine execution mode">
  <action>Set mode = {{mode}} if provided by caller; otherwise mode = "interactive"</action>

  <check if="mode == data">
    <action>Jump to Step 20</action>
  </check>

  <check if="mode == validate">
    <action>Jump to Step 30</action>
  </check>

  <check if="mode == interactive">
    <action>Continue to Step 1</action>
  </check>
</step>

<step n="1" goal="Locate the board file">
  <action>Load {project_context} for project-wide patterns and conventions (if exists)</action>
  <action>Try {board}</action>
  <check if="file not found">
    <output>❌ board.yaml not found.
Run `/evo:bmm:workflows:sprint-planning` to lay out issues and specs (the app then creates the board), then rerun sprint-status.</output>
    <action>Exit workflow</action>
  </check>
  <action>Continue to Step 2</action>
</step>

<step n="2" goal="Read and parse board.yaml">
  <action>Read the FULL file: {board}</action>
  <action>Parse fields: version, columns (the declared column list), items</action>
  <action>Parse the items list. Classify item keys:</action>
  - Epics: keys starting with "epic-"
  - Stories/issues: everything else (e.g., LOJA-113, 1-2-login-form)
  <action>For each issue, read its `specs` list and open the spec files under `.nexus/specs/<ISSUE-KEY>/` to read each spec's `done` flag</action>
  <action>Count issues per column across the declared columns (backlog, planning, specs, dev, tests, review, done)</action>
  <action>Count epics per column (backlog, ..., dev, review, done)</action>
  <action>Count specs by `done`: done vs not-done</action>

<action>Validate every item's column against the board's declared `columns` list:</action>

- Valid columns are exactly those in the board's `columns` field (backlog, planning, specs, dev, tests, review, done)
- An item whose `column` is not in that list is invalid (the same rule `parseBoard` enforces)

  <check if="any item sits in a column the board does not declare">
    <output>
⚠️ **Unknown column detected:**
{{#each invalid_entries}}

- `{{key}}`: "{{column}}" (not a declared column)
  {{/each}}

**Declared columns:** backlog, planning, specs, dev, tests, review, done
  </output>
  <critical>The board has one writer: the app. Do NOT edit board.yaml. Report the invalid entries so the author can fix them in the app.</critical>
  <action>Report the invalid entries and continue with the valid ones; the app owns any correction</action>
</check>

<action>Detect risks:</action>

- IF any issue sits in the "review" column: suggest `/evo:bmm:workflows:code-review`
- IF any issue sits in the "dev" column AND no issue sits in "specs": recommend staying focused on the active issue
- IF all issues sit in "backlog" AND no issue has any spec file yet: prompt `/evo:bmm:workflows:create-story`
- IF any spec key doesn't match an epic pattern (e.g., spec "5-1-..." but no "epic-5" issue): warn "orphaned spec detected"
- IF any epic issue sits past "backlog" but has no associated specs: warn "active epic has no specs"
  </step>

<step n="3" goal="Select next action recommendation">
  <action>Pick the next recommended workflow using priority:</action>
  <note>When selecting "first" spec: sort by epic number, then story number (e.g., 1-1 before 1-2 before 2-1)</note>
  1. If any issue sits in the "dev" column with a spec still `done: false` → recommend `dev-story` for the first such spec
  2. Else if any issue sits in the "review" column → recommend `code-review` for the first review issue
  3. Else if any issue sits in "specs" with a spec file ready → recommend `dev-story`
  4. Else if any issue in "backlog" still has specs without files → recommend `create-story`
  5. Else if any epic issue is done but has no retro spec → recommend `retrospective`
  6. Else → All implementation items done; congratulate the user - you both did amazing work together!
  <action>Store selected recommendation as: next_story_id, next_workflow_id, next_agent (SM/DEV as appropriate)</action>
</step>

<step n="4" goal="Display summary">
  <output>
## 📊 Sprint Status

- Project: {{project}} ({{project_key}})
- Tracking: {{tracking_system}}
- Board file: {board}

**Issues by column:** backlog {{count_backlog}}, specs {{count_specs}}, dev {{count_dev}}, review {{count_review}}, done {{count_done}}

**Epics by column:** backlog {{epic_backlog}}, dev {{epic_dev}}, review {{epic_review}}, done {{epic_done}}

**Next Recommendation:** /evo:bmm:workflows:{{next_workflow_id}} ({{next_story_id}})

{{#if risks}}
**Risks:**
{{#each risks}}

- {{this}}
  {{/each}}
  {{/if}}

  </output>
  </step>

<step n="5" goal="Offer actions">
  <ask>Pick an option:
1) Run recommended workflow now
2) Show all issues grouped by column
3) Show raw board.yaml
4) Exit
Choice:</ask>

  <check if="choice == 1">
    <output>Run `/evo:bmm:workflows:{{next_workflow_id}}`.
If the command targets a spec, set `spec_key={{next_story_id}}` when prompted.</output>
  </check>

  <check if="choice == 2">
    <output>
### Issues by Column
- Dev: {{issues_in_dev}}
- Review: {{issues_in_review}}
- Specs: {{issues_in_specs}}
- Backlog: {{issues_backlog}}
- Done: {{issues_done}}
    </output>
  </check>

  <check if="choice == 3">
    <action>Display the full contents of {board}</action>
  </check>

  <check if="choice == 4">
    <action>Exit workflow</action>
  </check>
</step>

<!-- ========================= -->
<!-- Data mode for other flows -->
<!-- ========================= -->

<step n="20" goal="Data mode output">
  <action>Load and parse {board} same as Step 2</action>
  <action>Compute recommendation same as Step 3</action>
  <template-output>next_workflow_id = {{next_workflow_id}}</template-output>
  <template-output>next_story_id = {{next_story_id}}</template-output>
  <template-output>count_backlog = {{count_backlog}}</template-output>
  <template-output>count_specs = {{count_specs}}</template-output>
  <template-output>count_dev = {{count_dev}}</template-output>
  <template-output>count_review = {{count_review}}</template-output>
  <template-output>count_done = {{count_done}}</template-output>
  <template-output>epic_backlog = {{epic_backlog}}</template-output>
  <template-output>epic_dev = {{epic_dev}}</template-output>
  <template-output>epic_done = {{epic_done}}</template-output>
  <template-output>risks = {{risks}}</template-output>
  <action>Return to caller</action>
</step>

<!-- ========================= -->
<!-- Validate mode -->
<!-- ========================= -->

<step n="30" goal="Validate the board file">
  <action>Check that {board} exists</action>
  <check if="missing">
    <template-output>is_valid = false</template-output>
    <template-output>error = "board.yaml missing"</template-output>
    <template-output>suggestion = "Run sprint-planning to lay out issues and specs (the app then creates the board)"</template-output>
    <action>Return</action>
  </check>

<action>Read and parse {board}</action>

<action>Validate required top-level fields exist: version, columns, items</action>
<check if="any required field missing">
<template-output>is_valid = false</template-output>
<template-output>error = "Missing required field(s): {{missing_fields}}"</template-output>
<template-output>suggestion = "The app owns board.yaml; re-run sprint-planning and let the app rebuild it"</template-output>
<action>Return</action>
</check>

<action>Verify the items list exists with at least one entry</action>
<check if="items missing or empty">
<template-output>is_valid = false</template-output>
<template-output>error = "items missing or empty"</template-output>
<template-output>suggestion = "The app owns board.yaml; re-run sprint-planning and let the app rebuild it"</template-output>
<action>Return</action>
</check>

<action>Validate every item's column against the board's declared columns:</action>

- Declared columns: backlog, planning, specs, dev, tests, review, done
- This is the same rule `parseBoard` enforces in `method/schema/board.ts`
  <check if="any invalid column found">
  <template-output>is_valid = false</template-output>
  <template-output>error = "Invalid column values: {{invalid_entries}}"</template-output>
  <template-output>suggestion = "The app is the board's only writer; fix the invalid columns from the app"</template-output>
  <action>Return</action>
  </check>

<template-output>is_valid = true</template-output>
<template-output>message = "board.yaml valid: top-level fields present, all columns recognized"</template-output>
</step>

</workflow>
