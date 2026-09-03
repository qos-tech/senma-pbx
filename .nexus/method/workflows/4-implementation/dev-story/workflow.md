---
name: dev-story
description: 'Execute story implementation following a context filled story spec file. Use when the user says "dev this story [story file]" or "implement the next story in the sprint plan"'
main_config: '{project-root}/.nexus/project.yaml'
nextStepFile: './steps/step-01-find-spec.md'
---

# Dev Story Workflow

**Goal:** Execute story implementation following a context filled story spec file.

**Your Role:** Developer implementing the story.
- Communicate all responses in {communication_language} and language MUST be tailored to {user_skill_level}
- Generate all documents in {document_output_language}
- The write boundary holds: you modify only the spec's `tasks[].done` and its Dev Agent Record (Debug Log, Completion Notes, File List, Change Log), and you append a comment to the issue frontmatter with `who: "agent:dev"`. You NEVER write the board, the issue's context, or its criteria. The app moves the column in reaction.
- A COMMENT IS READ ON A SCREEN, so it is written as markdown and not as one block of prose. Lead with a one-line summary, then short paragraphs, a bulleted list for anything enumerable, and `**bold**` for the few words that matter. A paragraph runs at most four sentences. The detail belongs in the spec's Dev Agent Record, which is where a reader goes for it; a comment that runs past roughly fifteen lines is a record in the wrong place.
- Execute ALL steps in exact order; do NOT skip steps
- Absolutely DO NOT stop because of "milestones", "significant progress", or "session boundaries". Continue in a single execution until the story is COMPLETE (all ACs satisfied and all tasks/subtasks checked) UNLESS a HALT condition is triggered or the USER gives other instruction.
- Do NOT schedule a "next session" or request review pauses unless a HALT condition applies. Only Step 9 decides completion.
- User skill level ({user_skill_level}) affects conversation style ONLY, not code updates.
- **BE CONCISE.** Minimize prose. Use one-line status updates. No preambles, no re-stating intent. Show code, not explanations. Only elaborate on HALTs or user questions.

---

## WORKFLOW ARCHITECTURE

**HOW to pace this:** Read fully and follow: `{project-root}/.nexus/method/core/workflows/one-step-at-a-time/workflow.md` before step 1. One step file in memory, the step finished before the next is read, and a full stop at every checkpoint.

**WHAT a checkpoint IS in this workflow:** this run goes to completion on its own. Its only checkpoints are the HALT conditions the steps name and the menu step 1 shows when no spec is ready. Nothing else is one. Finishing a task, finishing a test run, or noticing that a lot has been done is NOT a checkpoint, and stopping there is the exact defect the role rules above forbid.

**WHAT to read:** Read fully and follow: `{project-root}/.nexus/method/references/context-budget.md` before you load any planning document. The frontmatter before the body, the one section before the whole file, and a spec of more than 3 tasks is one to split.

This uses **step-file architecture** for disciplined execution:

- Each step is a self contained instruction file, read whole before you act on any part of it
- Only the current step file is in memory; never read ahead to plan
- The sequence inside the step files is followed exactly, with no skipping and no optimizing
- Steps 5 through 8 are a LOOP, run once per task: step 8 sends you back to step 5 while tasks remain. Re-reading a step file you already ran is required there, not a violation
- Step 1 is a single file on purpose: its `task_check` anchor is jumped to from three branches inside it

---

## INITIALIZATION

### Configuration Loading

Load config from `{project-root}/.nexus/project.yaml` and resolve:

- `project_name`, `user_name`
- `communication_language`, `document_output_language`
- `user_skill_level`
- `specs_dir` (`.nexus/specs/`)
- `active_issue` = the issue key (`<ISSUE-KEY>`) this run is scoped to
- `date` as system-generated current datetime

### Paths

- `installed_path` = `{project-root}/.nexus/method/workflows/4-implementation/dev-story`
- `steps_path` = `{installed_path}/steps`
- `validation` = `{installed_path}/checklist.md`
- `spec_file` = `` (explicit spec path; auto-discovered if empty)
- `board` = `.nexus/board.yaml` (READ ONLY: the app is the board's only writer)
- `issue_file` = `.nexus/issues/<ISSUE-KEY>.md`

### Context

- `project_context` = `**/project-context.md` (load if exists)

### Recall

Before the issue, the spec or any step file is read:

- `mcp__ai-memory__memory_query`: search the story's topic and the modules it names, including earlier failures around them; read the hits that matter with `mcp__ai-memory__memory_read_page`. What the project already remembers is input, never something to ask the person again.
- `mcp__codegraph__codegraph_explore`: before any grep, find or file read while investigating code, ask the index with the symbols or the question; it returns the source and the call paths in one call.
- The run's preamble says whether each server is available and which `project`/`workspace` to pass. When one is not available, skip it and say so in one line.

---

## EXECUTION

<workflow>
  <critical>Communicate all responses in {communication_language} and language MUST be tailored to {user_skill_level}</critical>
  <critical>Generate all documents in {document_output_language}</critical>
  <critical>The write boundary holds: modify only the spec's `tasks[].done` and its Dev Agent Record (Debug Log, Completion Notes, File
    List, Change Log), and append a comment to the issue frontmatter with `who: "agent:dev"`. NEVER write the board, the issue's context,
    or its criteria. The app moves the column in reaction.</critical>
  <critical>Execute ALL steps in exact order; do NOT skip steps</critical>
  <critical>Absolutely DO NOT stop because of "milestones", "significant progress", or "session boundaries". Continue in a single execution
    until the story is COMPLETE (all ACs satisfied and all tasks/subtasks checked) UNLESS a HALT condition is triggered or the USER gives
    other instruction.</critical>
  <critical>Do NOT schedule a "next session" or request review pauses unless a HALT condition applies. Only Step 9 decides completion.</critical>
  <critical>User skill level ({user_skill_level}) affects conversation style ONLY, not code updates.</critical>
  <critical>BE CONCISE. Minimize prose output. Prefer one-line status updates (e.g. "✅ Task 1 done"). No preambles, no summaries between
    tasks, no re-stating what you are about to do. Show code, not explanations. Only elaborate when a HALT or user question requires
    it.</critical>
  <critical>These rules bind EVERY step file. Each step file restates the ones that bind it, so a step read on its own still carries
    them.</critical>
</workflow>

Read fully and follow: `{nextStepFile}` (`{steps_path}/step-01-find-spec.md`) to begin.
