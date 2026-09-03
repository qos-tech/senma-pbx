---
name: 'step-09-complete'
description: 'Spec completion, definition-of-done validation, and the signal that the work is ready for review'
nextStepFile: './step-10-communicate.md'
---

# Step 9: Spec completion and signal for review

**Step 9 of 10** - Next: completion communication

**This is the ONLY step that decides completion.** No earlier step may declare
the story done, and no earlier step may propose a pause for review.

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🚫 Do NOT read the next step file until this one is finished
- 🛑 The board has ONE writer, the app. Signal readiness by commenting on the issue; the app moves the column in reaction
- 🛑 Any gate that fails HALTs here. Do NOT report the story as complete
- 💬 BE CONCISE. One-line status updates
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Prove the story is actually done against `{project-root}/.nexus/method/workflows/4-implementation/dev-story/checklist.md`, then signal it in the one place you may write.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="9" goal="Spec completion and signal for review" tag="board">
  <action>Verify ALL tasks and subtasks are marked `done: true` (re-scan the spec now)</action>
  <action>Run the full regression suite (do not skip)</action>
  <action>Confirm File List includes every changed file</action>
  <action>Execute enhanced definition-of-done validation</action>
  <action>Confirm every `tasks[].done` is `true` and the spec's Dev Agent Record is filled; the app moves the issue to the review column in reaction</action>

  <!-- Enhanced Definition of Done Validation -->
  <action>Validate definition-of-done checklist with essential requirements:
    - All tasks/subtasks marked complete with `done: true`
    - Implementation satisfies every Acceptance Criterion
    - Unit tests for core functionality added/updated
    - Integration tests for component interactions added when required
    - End-to-end tests for critical flows added when story demands them
    - All tests pass (no regressions, new tests successful)
    - Code quality checks pass (linting, static analysis if configured)
    - File List includes every new/modified/deleted file (relative paths)
    - Dev Agent Record contains implementation notes
    - Change Log includes summary of changes
    - Only permitted spec sections were modified (tasks[].done and Dev Agent Record)
  </action>

  <!-- Signal ready for review - the app owns the board -->
  <check if="{board} file exists AND {{board_tracking}} != 'no-board-tracking'">
    <action>Append a comment to `{{issue_file}}` frontmatter: `who: "agent:dev"`, `at: {date}`, `text: "Spec {{spec_key}} ready for review."`</action>
    <action>Confirm {{active_issue}}'s spec {{spec_key}} has every task `done: true`</action>
    <output>✅ Spec {{spec_key}} marked complete; the app moves {{active_issue}} into the review column in reaction</output>
  </check>

  <check if="{board} file does NOT exist OR {{board_tracking}} == 'no-board-tracking'">
    <output>ℹ️ Spec {{spec_key}} completed in the spec file (no board tracking configured)</output>
  </check>

  <check if="issue not found on the board">
    <output>⚠️ Spec file updated, but the issue could not be found on the board: {{active_issue}} missing

      The spec's tasks are all done, but board.yaml may be out of sync (the app should reconcile it).
    </output>
  </check>

  <!-- Final validation gates -->
  <action if="any task is incomplete">HALT - Complete remaining tasks before marking ready for review</action>
  <action if="regression failures exist">HALT - Fix regression issues before completing</action>
  <action if="File List is incomplete">HALT - Update File List with all changed files</action>
  <action if="definition-of-done validation fails">HALT - Address DoD failures before completing</action>
</step>

## NEXT STEP:

Read fully and follow `{nextStepFile}` (step-10-communicate.md).

## SUCCESS:

✅ Every `tasks[].done` re-scanned and confirmed `true`
✅ The full regression suite RUN, not assumed
✅ The definition-of-done checklist at `{project-root}/.nexus/method/workflows/4-implementation/dev-story/checklist.md` passed item by item
✅ A comment with `who: "agent:dev"` appended so the app can move the issue to review
✅ `board.yaml` unchanged

## FAILURE:

❌ Declaring completion while any task is incomplete or any regression fails
❌ Editing `board.yaml` to move the issue to review yourself
❌ An incomplete File List, so the next reader cannot see what changed
❌ Skipping the definition-of-done checklist because the tasks look done
