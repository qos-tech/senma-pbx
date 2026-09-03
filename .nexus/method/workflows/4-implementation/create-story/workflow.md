---
name: create-story
description: 'Creates a dedicated story file with all the context the agent will need to implement it later. Use when the user says "create the next story" or "create story [story identifier]"'
---

# Create Story Workflow

**Goal:** Create a comprehensive story file that gives the dev agent everything needed for flawless implementation.

**WHAT to read:** Read fully and follow: `{project-root}/.nexus/method/references/context-budget.md` before you load any planning document. The frontmatter before the body, the one section before the whole file, and a spec of more than 3 tasks is one to split.

**Your Role:** Story context engine that prevents LLM developer mistakes, omissions, or disasters.
- Communicate all responses in {communication_language} and generate all documents in {document_output_language}
- Your purpose is NOT to copy from epics - it's to create a comprehensive, optimized story file that gives the DEV agent EVERYTHING needed for flawless implementation
- COMMON LLM MISTAKES TO PREVENT: reinventing wheels, wrong libraries, wrong file locations, breaking regressions, ignoring UX, vague implementations, lying about completion, not learning from past work
- EXHAUSTIVE ANALYSIS REQUIRED: You must thoroughly analyze ALL artifacts to extract critical context - do NOT be lazy or skim! This is the most important function in the entire development process!
- UTILIZE SUBPROCESSES AND SUBAGENTS: Use research subagents, subprocesses or parallel processing if available to thoroughly analyze different artifacts simultaneously and thoroughly
- SAVE QUESTIONS: If you think of questions or clarifications during analysis, save them for the end after the complete story is written
- ZERO USER INTERVENTION: Process should be fully automated except for initial epic/story selection or missing documents

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

- `installed_path` = `{project-root}/.nexus/method/workflows/4-implementation/create-story`
- `template` = `{installed_path}/template.md`
- `validation` = `{installed_path}/checklist.md`
- `board` = `.nexus/board.yaml` (READ ONLY: the app is the board's only writer)
- `issue_file` = `.nexus/issues/<ISSUE-KEY>.md`
- `epics_file` = `{docs_dir}/epics.md`
- `prd_file` = `{docs_dir}/prd.md`
- `architecture_file` = `{docs_dir}/architecture.md`
- `ux_file` = `{docs_dir}/*ux*.md`
- `story_title` = "" (will be elicited if not derivable)
- `project_context` = `**/project-context.md` (load if exists)
- `default_output_file` = `.nexus/specs/<ISSUE-KEY>/{{spec_key}}.md`

### Input Files

| Input | Description | Path Pattern(s) | Load Strategy |
|-------|-------------|------------------|---------------|
| prd | PRD (fallback - epics file should have most content) | whole: `{docs_dir}/*prd*.md`, sharded: `{docs_dir}/*prd*/*.md` | SELECTIVE_LOAD |
| architecture | Architecture (fallback - epics file should have relevant sections) | whole: `{docs_dir}/*architecture*.md`, sharded: `{docs_dir}/*architecture*/*.md` | SELECTIVE_LOAD |
| ux | UX design (fallback - epics file should have relevant sections) | whole: `{docs_dir}/*ux*.md`, sharded: `{docs_dir}/*ux*/*.md` | SELECTIVE_LOAD |
| epics | Enhanced epics+stories file with BDD and source hints | whole: `{docs_dir}/*epic*.md`, sharded: `{docs_dir}/*epic*/*.md` | SELECTIVE_LOAD |

---

### Recall

Before the issue, the spec or any step file is read:

- `mcp__ai-memory__memory_query`: search the epic, the feature and the decisions already made about them; read the hits that matter with `mcp__ai-memory__memory_read_page`. What the project already remembers is input, never something to ask the person again.
- `mcp__codegraph__codegraph_explore`: before any grep, find or file read while investigating code, ask the index with the symbols or the question; it returns the source and the call paths in one call.
- The run's preamble says whether each server is available and which `project`/`workspace` to pass. When one is not available, skip it and say so in one line.

## EXECUTION

<workflow>

<step n="1" goal="Determine target story">
  <check if="{{story_path}} is provided by user or user provided the epic and story number such as 2-4 or 1.6 or epic 1 story 5">
    <action>Parse user-provided story path: extract epic_num, story_num, story_title from format like "1-2-user-auth"</action>
    <action>Set {{epic_num}}, {{story_num}}, {{spec_key}} from user input</action>
    <action>GOTO step 2a</action>
  </check>

  <action>Check if {{board}} file exists for auto discover</action>
  <check if="board file does NOT exist">
    <output>🚫 No board found and no story specified</output>
    <output>
      **Required Options:**
      1. Run `sprint-planning` to lay out issues and specs from the epics (recommended)
      2. Provide specific epic-story number to create (e.g., "1-2-user-auth")
      3. Provide path to story documents if the board doesn't exist yet
    </output>
    <ask>Choose option [1], provide epic-story number, path to story docs, or [q] to quit:</ask>

    <check if="user chooses 'q'">
      <action>HALT - No work needed</action>
    </check>

    <check if="user chooses '1'">
      <output>Run sprint-planning workflow first to lay out issues and specs</output>
      <action>HALT - User needs to run sprint-planning</action>
    </check>

    <check if="user provides epic-story number">
      <action>Parse user input: extract epic_num, story_num, story_title</action>
      <action>Set {{epic_num}}, {{story_num}}, {{spec_key}} from user input</action>
      <action>GOTO step 2a</action>
    </check>

    <check if="user provides story docs path">
      <action>Use user-provided path for story documents</action>
      <action>GOTO step 2a</action>
    </check>
  </check>

  <!-- Auto-discover from the board only if no user input -->
  <check if="no user input provided">
    <critical>MUST read COMPLETE {board} file from start to end to preserve order</critical>
    <action>Load the FULL file: {{board}}</action>
    <action>Read ALL lines from beginning to end - do not skip any content</action>
    <action>Parse the items list completely</action>

    <action>Scope to {{active_issue}}: read its `specs` list in board order and open the issue file `.nexus/issues/{{active_issue}}.md` for its context and criteria</action>
    <action>Find the FIRST spec key in {{active_issue}}'s `specs` list where:
      - Key matches pattern: number-number-name (e.g., "1-2-user-auth")
      - No spec file exists yet at `.nexus/specs/{{active_issue}}/<spec-key>.md`
    </action>

    <check if="no spec still needing a file found">
      <output>📋 No pending specs found for {{active_issue}}

        All of this issue's specs already have files, are in progress, or are done.

        **Options:**
        1. Run sprint-planning to refresh the issue/spec layout
        2. Load PM agent and run correct-course to add more specs
        3. Check if the issue is complete and run retrospective
      </output>
      <action>HALT</action>
    </check>

    <action>Extract from found spec key (e.g., "1-2-user-authentication"):
      - epic_num: first number before dash (e.g., "1")
      - story_num: second number after first dash (e.g., "2")
      - story_title: remainder after second dash (e.g., "user-authentication")
    </action>
    <action>Set {{story_id}} = "{{epic_num}}.{{story_num}}"</action>
    <action>Store spec_key for later use (e.g., "1-2-user-authentication")</action>

    <!-- The app moves the issue's column in reaction to the new spec; this workflow never writes the board -->
    <action>Check if this is the first spec for {{active_issue}} by looking for a {{epic_num}}-1-* key in its `specs` list</action>
    <check if="this is the first spec for {{active_issue}}">
      <action>Confirm the issue is not already complete before authoring a new spec</action>
      <check if="issue is already marked done on the board">
        <output>🚫 ERROR: Cannot create a spec for a completed issue</output>
        <output>Issue {{active_issue}} is in the done column. All specs are complete.</output>
        <output>If you need to add more work, either:</output>
        <output>1. Reopen the issue from the app (the app is the board's only writer)</output>
        <output>2. Create a new issue for additional work</output>
        <action>HALT - Cannot proceed</action>
      </check>
      <output>📊 First spec for {{active_issue}} - the app moves it forward when the spec file lands</output>
    </check>

    <action>GOTO step 2a</action>
  </check>
  <action>Load the FULL file: {{board}}</action>
  <action>Read ALL lines from beginning to end - do not skip any content</action>
  <action>Parse the items list completely</action>

  <action>Scope to {{active_issue}}: read its `specs` list in board order and open the issue file `.nexus/issues/{{active_issue}}.md` for its context and criteria</action>
  <action>Find the FIRST spec key in {{active_issue}}'s `specs` list where:
    - Key matches pattern: number-number-name (e.g., "1-2-user-auth")
    - No spec file exists yet at `.nexus/specs/{{active_issue}}/<spec-key>.md`
  </action>

  <check if="no spec still needing a file found">
    <output>No pending specs found for {{active_issue}}

      All of this issue's specs already have files, are in progress, or are done.

      **Options:**
      1. Run sprint-planning to refresh the issue/spec layout
      2. Load PM agent and run correct-course to add more specs
      3. Check if the issue is complete and run retrospective
    </output>
    <action>HALT</action>
  </check>

  <action>Extract from found spec key (e.g., "1-2-user-authentication"):
    - epic_num: first number before dash (e.g., "1")
    - story_num: second number after first dash (e.g., "2")
    - story_title: remainder after second dash (e.g., "user-authentication")
  </action>
  <action>Set {{story_id}} = "{{epic_num}}.{{story_num}}"</action>
  <action>Store spec_key for later use (e.g., "1-2-user-authentication")</action>

  <!-- The app moves the issue's column in reaction to the new spec; this workflow never writes the board -->
  <action>Check if this is the first spec for {{active_issue}} by looking for a {{epic_num}}-1-* key in its `specs` list</action>
  <check if="this is the first spec for {{active_issue}}">
    <action>Confirm the issue is not already complete before authoring a new spec</action>
    <check if="issue is already marked done on the board">
      <output>ERROR: Cannot create a spec for a completed issue</output>
      <output>Issue {{active_issue}} is in the done column. All specs are complete.</output>
      <output>If you need to add more work, either:</output>
      <output>1. Reopen the issue from the app (the app is the board's only writer)</output>
      <output>2. Create a new issue for additional work</output>
      <action>HALT - Cannot proceed</action>
    </check>
    <output>First spec for {{active_issue}} - the app moves it forward when the spec file lands</output>
  </check>

  <action>GOTO step 2a</action>
</step>

<step n="2" goal="Load and analyze core artifacts">
  <critical>🔬 EXHAUSTIVE ARTIFACT ANALYSIS - This is where you prevent future developer fuckups!</critical>

  <!-- Load all available content through discovery protocol -->
  <action>Read fully and follow `{installed_path}/discover-inputs.md` to load all input files</action>
  <note>Available content: {epics_content}, {prd_content}, {architecture_content}, {ux_content},
  {project_context}</note>

  <!-- Analyze epics file for story foundation -->
  <action>From {epics_content}, extract Epic {{epic_num}} complete context:</action> **EPIC ANALYSIS:** - Epic
  objectives and business value - ALL stories in this epic for cross-story context - Our specific story's requirements, user story
  statement, acceptance criteria - Technical requirements and constraints - Dependencies on other stories/epics - Source hints pointing to
  original documents <!-- Extract specific story requirements -->
  <action>Extract our story ({{epic_num}}-{{story_num}}) details:</action> **STORY FOUNDATION:** - User story statement
  (As a, I want, so that) - Detailed acceptance criteria (already BDD formatted) - Technical requirements specific to this story -
  Business context and value - Success criteria <!-- Previous story analysis for context continuity -->
  <check if="story_num > 1">
    <action>Find {{previous_story_num}}: scan `.nexus/specs/{{active_issue}}/` for the spec file in epic {{epic_num}} with the highest story number less than {{story_num}}</action>
    <action>Load previous spec file: `.nexus/specs/{{active_issue}}/{{epic_num}}-{{previous_story_num}}-*.md`</action> **PREVIOUS STORY INTELLIGENCE:** -
  Dev notes and learnings from previous story - Review feedback and corrections needed - Files that were created/modified and their
  patterns - Testing approaches that worked/didn't work - Problems encountered and solutions found - Code patterns established <action>Extract
  all learnings that could impact current story implementation</action>
  </check>

  <!-- Git intelligence for previous work patterns -->
  <check
    if="previous story exists AND git repository detected">
    <action>Get last 5 commit titles to understand recent work patterns</action>
    <action>Analyze 1-5 most recent commits for relevance to current story:
      - Files created/modified
      - Code patterns and conventions used
      - Library dependencies added/changed
      - Architecture decisions implemented
      - Testing approaches used
    </action>
    <action>Extract actionable insights for current story implementation</action>
  </check>
</step>

<step n="3" goal="Architecture analysis for developer guardrails">
  <critical>🏗️ ARCHITECTURE INTELLIGENCE - Extract everything the developer MUST follow!</critical> **ARCHITECTURE DOCUMENT ANALYSIS:** <action>Systematically
  analyze architecture content for story-relevant requirements:</action>

  <!-- Load architecture - single file or sharded -->
  <check if="architecture file is single file">
    <action>Load complete {architecture_content}</action>
  </check>
  <check if="architecture is sharded to folder">
    <action>Load architecture index and scan all architecture files</action>
  </check> **CRITICAL ARCHITECTURE EXTRACTION:** <action>For
  each architecture section, determine if relevant to this story:</action> - **Technical Stack:** Languages, frameworks, libraries with
  versions - **Code Structure:** Folder organization, naming conventions, file patterns - **API Patterns:** Service structure, endpoint
  patterns, data contracts - **Database Schemas:** Tables, relationships, constraints relevant to story - **Security Requirements:**
  Authentication patterns, authorization rules - **Performance Requirements:** Caching strategies, optimization patterns - **Testing
  Standards:** Testing frameworks, coverage expectations, test patterns - **Deployment Patterns:** Environment configurations, build
  processes - **Integration Patterns:** External service integrations, data flows <action>Extract any story-specific requirements that the
  developer MUST follow</action>
  <action>Identify any architectural decisions that override previous patterns</action>
</step>

<step n="4" goal="Web research for latest technical specifics">
  <critical>🌐 ENSURE LATEST TECH KNOWLEDGE - Prevent outdated implementations!</critical> **WEB INTELLIGENCE:** <action>Identify specific
  technical areas that require latest version knowledge:</action>

  <!-- Check for libraries/frameworks mentioned in architecture -->
  <action>From architecture analysis, identify specific libraries, APIs, or
  frameworks</action>
  <action>For each critical technology, research latest stable version and key changes:
    - Latest API documentation and breaking changes
    - Security vulnerabilities or updates
    - Performance improvements or deprecations
    - Best practices for current version
  </action>
  **EXTERNAL CONTEXT INCLUSION:** <action>Include in story any critical latest information the developer needs:
    - Specific library versions and why chosen
    - API endpoints with parameters and authentication
    - Recent security patches or considerations
    - Performance optimization techniques
    - Migration considerations if upgrading
  </action>
</step>

<step n="5" goal="Create comprehensive story file">
  <critical>📝 CREATE ULTIMATE STORY FILE - The developer's master implementation guide!</critical>

  <action>Initialize from template.md:
  {default_output_file}</action>
  <template-output file="{default_output_file}">story_header</template-output>

  <!-- Story foundation from epics analysis -->
  <template-output
    file="{default_output_file}">story_requirements</template-output>

  <!-- Developer context section - MOST IMPORTANT PART -->
  <template-output file="{default_output_file}">
  developer_context_section</template-output> **DEV AGENT GUARDRAILS:** <template-output file="{default_output_file}">
  technical_requirements</template-output>
  <template-output file="{default_output_file}">architecture_compliance</template-output>
  <template-output
    file="{default_output_file}">library_framework_requirements</template-output>
  <template-output file="{default_output_file}">
  file_structure_requirements</template-output>
  <template-output file="{default_output_file}">testing_requirements</template-output>

  <!-- Previous story intelligence -->
  <check
    if="previous story learnings available">
    <template-output file="{default_output_file}">previous_story_intelligence</template-output>
  </check>

  <!-- Git intelligence -->
  <check
    if="git analysis completed">
    <template-output file="{default_output_file}">git_intelligence_summary</template-output>
  </check>

  <!-- Latest technical specifics -->
  <check if="web research completed">
    <template-output file="{default_output_file}">latest_tech_information</template-output>
  </check>

  <!-- Project context reference -->
  <template-output
    file="{default_output_file}">project_context_reference</template-output>

  <!-- Final status update -->
  <template-output file="{default_output_file}">
  story_completion_status</template-output>

  <!-- The spec lands with done: false and all tasks unchecked; the app moves the issue's column in reaction -->
  <action>Write the spec frontmatter: `key`, `title`, `issue: {{active_issue}}`, `done: false`, `story`, `criteria`, `tasks` (all `done: false`), `links`</action>
  <action>On every task, write `ac` naming the criterion ids it serves, using ONLY ids spelled under `criteria` in this same spec. An id that is not a slug, a repeat, or anything that is not a list makes the app REFUSE the whole spec.</action>
  <action>Write `optional: true` on a task that may be skipped without failing a criterion, and leave the field out on every other task. Do not write `optional: false`.</action>
  <critical>A criterion no required task names is a criterion nothing must happen for. Before you finish, check that every criterion is named by at least one task that is not optional.</critical>
  <action>Add completion note in Dev Agent Record: "Ultimate
  context engine analysis completed - comprehensive developer guide created"</action>
  <critical>Do NOT write the issue's `context` or `criteria`; those are the author's. This workflow authors a spec, nothing on the issue.</critical>
</step>

<step n="6" goal="Finalize the spec and let the board follow">
  <action>Validate the newly created spec file {default_output_file} against {installed_path}/checklist.md and apply any required fixes before finalizing</action>
  <action>Save the spec document unconditionally</action>

  <!-- The board has one writer: the app. It moves {{active_issue}} forward in reaction to the new spec file; this workflow never writes board.yaml -->
  <action>Confirm the spec file exists at `.nexus/specs/{{active_issue}}/{{spec_key}}.md` with `done: false` and every task unchecked</action>
  <action>Confirm the spec key is present in {{active_issue}}'s `specs` list (author it via the app if it is missing; do not edit the board here)</action>

  <action>Report completion</action>
  <output>**🎯 ULTIMATE EVO Method STORY CONTEXT CREATED, {user_name}!**

    **Spec Details:**
    - Story ID: {{story_id}}
    - Spec Key: {{spec_key}}
    - Issue: {{active_issue}}
    - File: .nexus/specs/{{active_issue}}/{{spec_key}}.md

    **Next Steps:**
    1. Review the comprehensive spec in .nexus/specs/{{active_issue}}/{{spec_key}}.md
    2. Run dev agents `dev-story` for optimized implementation
    3. Run `code-review` when complete (checks tasks off and appends an agent comment)
    4. Optional: If Test Architect module installed, run `/evo:tea:automate` after `dev-story` to generate guardrail tests

    **The developer now has everything needed for flawless implementation!**
  </output>
</step>

<step n="7" goal="Record what this story settled">

### Record

Before this workflow ends, write what the next run must not rediscover with `mcp__ai-memory__memory_write_page`, to the `project` and `workspace` the run's preamble names, under `nexus/<ISSUE-KEY>/create-story.md`:

- the scoping decisions the story settled and why;
- discoveries about the code that the documents did not say;
- what failed or was rejected, so nobody retries it.

When the preamble says memory is not available, skip the call and say so in one line.
</step>

</workflow>
