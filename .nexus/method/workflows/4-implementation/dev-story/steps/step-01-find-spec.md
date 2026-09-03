---
name: 'step-01-find-spec'
description: 'Find the next ready spec for the active issue and load it whole'
nextStepFile: './step-02-load-context.md'
completionStepFile: './step-09-complete.md'
---

# Step 1: Find next ready spec and load it

**Step 1 of 10** - Next: load project context

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🚫 Do NOT read the next step file until this one is finished
- 🛑 The write boundary holds: only `tasks[].done` and the Dev Agent Record, plus an appended issue comment with `who: "agent:dev"`. NEVER write the board, the issue's context, or its criteria
- 📋 `{{board}}` is READ ONLY here. The app is the board's only writer
- 💬 BE CONCISE. One-line status updates, no preambles
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Find the first spec of `{{active_issue}}` that still has unfinished tasks, load it completely, and identify the first incomplete task.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="1" goal="Find next ready spec and load it" tag="board">
  <check if="{{story_path}} is provided">
    <action>Use {{story_path}} directly</action>
    <action>Read COMPLETE spec file</action>
    <action>Extract spec_key from filename or frontmatter `key`</action>
    <goto anchor="task_check" />
  </check>

  <!-- Board-based spec discovery -->
  <check if="{{board}} file exists">
    <critical>MUST read COMPLETE board.yaml file from start to end to preserve order</critical>
    <action>Load the FULL file: {{board}}</action>
    <action>Read ALL lines from beginning to end - do not skip any content</action>
    <action>Parse the items list completely to understand spec order</action>

    <action>Scope to {{active_issue}} and read its `specs` list in board order</action>
    <action>Find the FIRST spec (by reading its `specs` list top to bottom) where:
      - Key matches pattern: number-number-name (e.g., "1-2-user-auth")
      - The spec file exists at `.nexus/specs/{{active_issue}}/<spec-key>.md` and has at least one task with `done: false`
    </action>

    <check if="no spec with unfinished tasks found">
      <output>📋 No ready spec found for {{active_issue}}

        **Current Issue:** {{active_issue}} ({{issue_column}})

        **What would you like to do?**
        1. Run `create-story` to author the next spec from epics with comprehensive context
        2. Run `*validate-create-story` to improve existing specs before development (recommended quality check)
        3. Specify a particular spec file to develop (provide full path)
        4. Open `{{issue_file}}` to review the issue and its spec list

        💡 **Tip:** Specs may not have been validated. Consider running `validate-create-story` first for a quality
        check.
      </output>
      <ask>Choose option [1], [2], [3], or [4], or specify spec file path:</ask>

      <check if="user chooses '1'">
        <action>HALT - Run create-story to author the next spec</action>
      </check>

      <check if="user chooses '2'">
        <action>HALT - Run validate-create-story to improve existing specs</action>
      </check>

      <check if="user chooses '3'">
        <ask>Provide the spec file path to develop:</ask>
        <action>Store user-provided spec path as {{story_path}}</action>
        <goto anchor="task_check" />
      </check>

      <check if="user chooses '4'">
        <output>Loading {{issue_file}} for detailed review...</output>
        <action>Display the issue's context, criteria, and spec list</action>
        <action>HALT - User can review the issue and provide a spec path</action>
      </check>

      <check if="user provides spec file path">
        <action>Store user-provided spec path as {{story_path}}</action>
        <goto anchor="task_check" />
      </check>
    </check>
  </check>

  <!-- Board-less spec discovery -->
  <check if="{{board}} file does NOT exist">
    <action>Search `.nexus/specs/{{active_issue}}/` for spec files directly</action>
    <action>Find specs that still have tasks with `done: false`</action>
    <action>Look for spec files matching pattern: *-*-*.md</action>
    <action>Read each candidate spec file to check its `tasks` and `done` fields</action>

    <check if="no spec with unfinished tasks found in files">
      <output>📋 No ready specs found

        **Available Options:**
        1. Run `create-story` to author the next spec from epics with comprehensive context
        2. Run `*validate-create-story` to improve existing specs
        3. Specify which spec to develop
      </output>
      <ask>What would you like to do? Choose option [1], [2], or [3]:</ask>

      <check if="user chooses '1'">
        <action>HALT - Run create-story to author the next spec</action>
      </check>

      <check if="user chooses '2'">
        <action>HALT - Run validate-create-story to improve existing specs</action>
      </check>

      <check if="user chooses '3'">
        <ask>It's unclear what spec you want developed. Please provide the full path to the spec file:</ask>
        <action>Store user-provided spec path as {{story_path}}</action>
        <action>Continue with provided spec file</action>
      </check>
    </check>

    <check if="spec with unfinished tasks found in files">
      <action>Use discovered spec file and extract spec_key</action>
    </check>
  </check>

  <action>Store the found spec_key (e.g., "1-2-user-authentication") for later spec and issue updates</action>
  <action>Find matching spec file in `.nexus/specs/{{active_issue}}/` using spec_key pattern: {{spec_key}}.md</action>
  <action>Read COMPLETE spec file from discovered path</action>

  <anchor id="task_check" />

  <action>Parse sections: Story, Acceptance Criteria, Tasks/Subtasks, Dev Notes, Dev Agent Record, File List, Change Log, Status</action>

  <action>Load comprehensive context from story file's Dev Notes section</action>
  <action>Extract developer guidance from Dev Notes: architecture requirements, previous learnings, technical specifications</action>
  <action>Use enhanced story context to inform implementation decisions and approaches</action>

  <action>Identify first incomplete task (unchecked [ ]) in Tasks/Subtasks</action>

  <action if="no incomplete tasks">
    <goto step="9">Completion sequence: ./step-09-complete.md</goto>
  </action>
  <action if="spec file inaccessible">HALT: "Cannot develop story without access to the spec file"</action>
  <action if="incomplete task or subtask requirements ambiguous">ASK user to clarify or HALT</action>
</step>

## ANCHOR NOTE:

`task_check` lives inside THIS file, and three branches above jump to it. Never
split this step across files and never look for the anchor in another one.

## NEXT STEP:

- If there are NO incomplete tasks: read fully and follow `{completionStepFile}` (step-09-complete.md). Steps 2 to 8 are skipped, because there is nothing left to implement.
- Otherwise: read fully and follow `{nextStepFile}` (step-02-load-context.md).

## SUCCESS:

✅ A spec with at least one unfinished task is found and read COMPLETE
✅ `{{spec_key}}` stored for later spec and issue updates
✅ The first incomplete task is identified
✅ The board was read and never written

## FAILURE:

❌ Reading the board partially, losing spec order
❌ Picking a spec other than the first one with unfinished tasks
❌ Writing `board.yaml` instead of leaving it to the app
❌ Proceeding when the spec file is inaccessible, instead of HALTing
