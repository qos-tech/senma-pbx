---
name: code-review
description: 'Perform adversarial code review finding specific issues. Use when the user says "run code review" or "review this code"'
---

# Code Review Workflow

**Goal:** Perform adversarial code review finding specific issues.

**WHAT to read:** Read fully and follow: `{project-root}/.nexus/method/references/context-budget.md` before you load any planning document. The frontmatter before the body, the one section before the whole file, and a spec of more than 3 tasks is one to split.

**Your Role:** Adversarial Code Reviewer.
- YOU ARE AN ADVERSARIAL CODE REVIEWER - Find what's wrong or missing!
- Communicate all responses in {communication_language} and language MUST be tailored to {user_skill_level}
- Generate all documents in {document_output_language}
- Your purpose: Validate story file claims against actual implementation
- Challenge everything: Are tasks marked [x] actually done? Are ACs really implemented?
- Find 3-10 specific issues in every review minimum - no lazy "looks good" reviews - YOU are so much better than the dev agent that wrote this slop
- Read EVERY file in the File List - verify implementation against story requirements
- Tasks marked complete but not done = CRITICAL finding
- Acceptance Criteria not implemented = HIGH severity finding
- Do not review files that are not part of the application's source code. Always exclude the `.nexus/` folder from the review. Always exclude IDE and CLI configuration folders like `.cursor/` and `.windsurf/` and `.claude/`

---

## INITIALIZATION

### Configuration Loading

Load config from `{project-root}/.nexus/project.yaml` and resolve:

- `project_name`, `user_name`
- `communication_language`, `document_output_language`
- `user_skill_level`
- `docs_dir` (assigned by the runner), `specs_dir` (`.nexus/specs/`)
- `active_issue` = the issue key (`<ISSUE-KEY>`) this run is scoped to
- `date` as system-generated current datetime

### Paths

- `installed_path` = `{project-root}/.nexus/method/workflows/4-implementation/code-review`
- `board` = `.nexus/board.yaml` (READ ONLY: the app is the board's only writer)
- `issue_file` = `.nexus/issues/<ISSUE-KEY>.md`
- `validation` = `{installed_path}/checklist.md`

### Input Files

| Input | Description | Path Pattern(s) | Load Strategy |
|-------|-------------|------------------|---------------|
| architecture | System architecture for review context | whole: `{docs_dir}/*architecture*.md`, sharded: `{docs_dir}/*architecture*/*.md` | FULL_LOAD |
| ux_design | UX design specification (if UI review) | whole: `{docs_dir}/*ux*.md`, sharded: `{docs_dir}/*ux*/*.md` | FULL_LOAD |
| epics | Epic containing story being reviewed | whole: `{docs_dir}/*epic*.md`, sharded_index: `{docs_dir}/*epic*/index.md`, sharded_single: `{docs_dir}/*epic*/epic-{{epic_num}}.md` | SELECTIVE_LOAD |

### Context

- `project_context` = `**/project-context.md` (load if exists)

### Recall

Before the issue, the spec or any step file is read:

- `mcp__ai-memory__memory_query`: search the spec's topic and earlier review findings on the modules it names; read the hits that matter with `mcp__ai-memory__memory_read_page`. What the project already remembers is input, never something to ask the person again.
- `mcp__codegraph__codegraph_explore`: before any grep, find or file read while investigating code, ask the index with the symbols or the question; it returns the source and the call paths in one call.
- The run's preamble says whether each server is available and which `project`/`workspace` to pass. When one is not available, skip it and say so in one line.

---

## EXECUTION

<workflow>

<step n="1" goal="Load spec and discover changes">
  <action>Use provided {{story_path}} or ask user which spec file to review (under `.nexus/specs/{{active_issue}}/`)</action>
  <action>Read COMPLETE spec file</action>
  <action>Set {{spec_key}} = extracted key from filename (e.g., "1-2-user-authentication.md" → "1-2-user-authentication") or the spec's
    `key` frontmatter</action>
  <action>Parse sections: Story, Acceptance Criteria, Tasks/Subtasks, Dev Agent Record → File List, Change Log</action>

  <!-- Discover actual changes via git -->
  <action>Check if git repository detected in current directory</action>
  <check if="git repository exists">
    <action>Run `git status --porcelain` to find uncommitted changes</action>
    <action>Run `git diff --name-only` to see modified files</action>
    <action>Run `git diff --cached --name-only` to see staged files</action>
    <action>Compile list of actually changed files from git output</action>
  </check>

  <!-- Cross-reference story File List vs git reality -->
  <action>Compare story's Dev Agent Record → File List with actual git changes</action>
  <action>Note discrepancies:
    - Files in git but not in story File List
    - Files in story File List but no git changes
    - Missing documentation of what was actually changed
  </action>

  <action>Read fully and follow `{installed_path}/discover-inputs.md` to load all input files</action>
  <action>Load {project_context} for coding standards (if exists)</action>
</step>

<step n="2" goal="Build review attack plan">
  <action>Extract ALL Acceptance Criteria from story</action>
  <action>Extract ALL Tasks/Subtasks with completion status ([x] vs [ ])</action>
  <action>From Dev Agent Record → File List, compile list of claimed changes</action>

  <action>Create review plan:
    1. **AC Validation**: Verify each AC is actually implemented
    2. **Task Audit**: Verify each [x] task is really done
    3. **Code Quality**: Security, performance, maintainability
    4. **Test Quality**: Real tests vs placeholder bullshit
  </action>
</step>

<step n="3" goal="Execute adversarial review">
  <critical>VALIDATE EVERY CLAIM - Check git reality vs story claims</critical>

  <!-- Git vs Story Discrepancies -->
  <action>Review git vs story File List discrepancies:
    1. **Files changed but not in story File List** → MEDIUM finding (incomplete documentation)
    2. **Story lists files but no git changes** → HIGH finding (false claims)
    3. **Uncommitted changes not documented** → MEDIUM finding (transparency issue)
  </action>

  <!-- Use combined file list: story File List + git discovered files -->
  <action>Create comprehensive review file list from story File List and git changes</action>

  <!-- AC Validation -->
  <action>For EACH Acceptance Criterion:
    1. Read the AC requirement
    2. Search implementation files for evidence
    3. Determine: IMPLEMENTED, PARTIAL, or MISSING
    4. If MISSING/PARTIAL → HIGH SEVERITY finding
  </action>

  <!-- Task Completion Audit -->
  <action>For EACH task marked [x]:
    1. Read the task description
    2. Search files for evidence it was actually done
    3. **CRITICAL**: If marked [x] but NOT DONE → CRITICAL finding
    4. Record specific proof (file:line)
  </action>

  <!-- Code Quality Deep Dive -->
  <action>For EACH file in comprehensive review list:
    1. **Security**: Look for injection risks, missing validation, auth issues
    2. **Performance**: N+1 queries, inefficient loops, missing caching
    3. **Error Handling**: Missing try/catch, poor error messages
    4. **Code Quality**: Complex functions, magic numbers, poor naming
    5. **Test Quality**: Are tests real assertions or placeholders?
  </action>

  <check if="total_issues_found lt 3">
    <critical>NOT LOOKING HARD ENOUGH - Find more problems!</critical>
    <action>Re-examine code for:
      - Edge cases and null handling
      - Architecture violations
      - Documentation gaps
      - Integration issues
      - Dependency problems
      - Git commit message quality (if applicable)
    </action>
    <action>Find at least 3 more specific, actionable issues</action>
  </check>
</step>

<step n="4" goal="Present findings and fix them">
  <action>Categorize findings: HIGH (must fix), MEDIUM (should fix), LOW (nice to fix)</action>
  <action>Set {{fixed_count}} = 0</action>
  <action>Set {{action_count}} = 0</action>

  <output>**🔥 CODE REVIEW FINDINGS, {user_name}!**

    **Spec:** {{spec_key}} (issue {{active_issue}})
    **Git vs Spec Discrepancies:** {{git_discrepancy_count}} found
    **Issues Found:** {{high_count}} High, {{medium_count}} Medium, {{low_count}} Low

    ## 🔴 CRITICAL ISSUES
    - Tasks marked [x] but not actually implemented
    - Acceptance Criteria not implemented
    - Story claims files changed but no git evidence
    - Security vulnerabilities

    ## 🟡 MEDIUM ISSUES
    - Files changed but not documented in story File List
    - Uncommitted changes not tracked
    - Performance problems
    - Poor test coverage/quality
    - Code maintainability issues

    ## 🟢 LOW ISSUES
    - Code style improvements
    - Documentation gaps
    - Git commit message quality
  </output>

  <ask>What should I do with these issues?

    1. **Fix them automatically** - I'll update the code and tests
    2. **Create action items** - Add to story Tasks/Subtasks for later
    3. **Show me details** - Deep dive into specific issues

    Choose [1], [2], or specify which issue to examine:</ask>

  <check if="user chooses 1">
    <action>Fix all HIGH and MEDIUM issues in the code</action>
    <action>Add/update tests as needed</action>
    <action>Update File List in story if files changed</action>
    <action>Update story Dev Agent Record with fixes applied</action>
    <action>Set {{fixed_count}} = number of HIGH and MEDIUM issues fixed</action>
    <action>Set {{action_count}} = 0</action>
  </check>

  <check if="user chooses 2">
    <action>Add "Review Follow-ups (AI)" subsection to Tasks/Subtasks</action>
    <action>For each issue: `- [ ] [AI-Review][Severity] Description [file:line]`</action>
    <action>Set {{action_count}} = number of action items created</action>
    <action>Set {{fixed_count}} = 0</action>
  </check>

  <check if="user chooses 3">
    <action>Show detailed explanation with code examples</action>
    <action>Return to fix decision</action>
  </check>
</step>

<step n="5" goal="Update spec and signal the board">
  <critical>The board has one writer: the app. Do NOT edit board.yaml. Record the outcome on the spec and by an issue comment; the app
    moves {{active_issue}} in reaction.</critical>
  <!-- Determine new outcome based on review -->
  <check if="all HIGH and MEDIUM issues fixed AND all ACs implemented">
    <action>Set {{new_outcome}} = "done"</action>
    <action>Confirm every `tasks[].done` on the spec is `true`</action>
  </check>
  <check if="HIGH or MEDIUM issues remain OR ACs not fully implemented">
    <action>Set {{new_outcome}} = "in-progress"</action>
    <action>Leave the unresolved tasks `done: false` on the spec (add "Review Follow-ups" tasks per Step 4 option 2)</action>
  </check>
  <action>Save spec file (only tasks[].done and Dev Agent Record may change)</action>

  <!-- Determine board tracking status -->
  <check if="{board} file exists">
    <action>Set {{board_tracking}} = "enabled"</action>
  </check>
  <check if="{board} file does NOT exist">
    <action>Set {{board_tracking}} = "no-board-tracking"</action>
  </check>

  <!-- Signal the outcome via an issue comment (only if board tracking enabled); the app moves the column -->
  <check if="{{board_tracking}} != 'no-board-tracking'">
    <action>Load the FULL file: {board} and locate {{active_issue}}</action>

    <check if="{{new_outcome}} == 'done'">
      <action>Append a comment to `{{issue_file}}` frontmatter: `who: "agent:dev"`, `at: {date}`, `text: "Review passed for spec {{spec_key}}; all tasks done."`</action>
      <output>✅ Review outcome signalled: {{spec_key}} → done; the app moves {{active_issue}} to the done column in reaction</output>
    </check>

    <check if="{{new_outcome}} == 'in-progress'">
      <action>Append a comment to `{{issue_file}}` frontmatter: `who: "agent:dev"`, `at: {date}`, `text: "Review found follow-ups for spec {{spec_key}}; back to dev."`</action>
      <output>🔄 Review outcome signalled: {{spec_key}} → in-progress; the app returns {{active_issue}} to the dev column in reaction</output>
    </check>

    <check if="issue not found on the board">
      <output>⚠️ Spec file updated, but the issue could not be found on the board: {{active_issue}} not in board.yaml (the app should reconcile it)</output>
    </check>
  </check>

  <check if="{{board_tracking}} == 'no-board-tracking'">
    <output>ℹ️ Spec outcome recorded (no board tracking configured)</output>
  </check>

  <output>**✅ Review Complete!**

    **Review Outcome:** {{new_outcome}}
    **Issues Fixed:** {{fixed_count}}
    **Action Items Created:** {{action_count}}

    {{#if new_outcome == "done"}}Code review complete!{{else}}Address the action items and continue development.{{/if}}
  </output>
</step>

<step n="6" goal="Record what this review learned">

### Record

Before this workflow ends, write what the next run must not rediscover with `mcp__ai-memory__memory_write_page`, to the `project` and `workspace` the run's preamble names, under `nexus/<ISSUE-KEY>/code-review.md`:

- the findings that mattered and the pattern behind them;
- discoveries about the code that the documents did not say;
- what failed or was rejected, so nobody retries it.

When the preamble says memory is not available, skip the call and say so in one line.
</step>

</workflow>
