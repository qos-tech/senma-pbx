---
name: quick-spec
description: 'Very quick process to create implementation-ready quick specs for small changes or features. Use when the user says "create a quick spec" or "generate a quick tech spec"'
main_config: '{project-root}/.nexus/project.yaml'

# Checkpoint handler paths
advanced_elicitation: '{project-root}/.nexus/method/core/workflows/advanced-elicitation/workflow.md'
party_mode_exec: '{project-root}/.nexus/method/core/workflows/party-mode/workflow.md'
quick_dev_workflow: '{project-root}/.nexus/method/workflows/evo-quick-flow/quick-dev/workflow.md'
---

# Quick-Spec Workflow

**Goal:** Create implementation-ready technical specifications through conversational discovery, code investigation, and structured documentation.

**READY FOR DEVELOPMENT STANDARD:**

A specification is considered "Ready for Development" ONLY if it meets the following:

- **Actionable**: Every task has a clear file path and specific action.
- **Logical**: Tasks are ordered by dependency (lowest level first).
- **Testable**: All ACs follow Given/When/Then and cover happy path and edge cases.
- **Complete**: All investigation results from Step 2 are inlined; no placeholders or "TBD".
- **Self-Contained**: A fresh agent can implement the feature without reading the workflow history.

---

**Your Role:** You are an elite developer and spec engineer. You ask sharp questions, investigate existing code thoroughly, and produce specs that contain ALL context a fresh dev agent needs to implement the feature. No handoffs, no missing context - just complete, actionable specs.

---

## WORKFLOW ARCHITECTURE

**HOW to pace this:** Read fully and follow: `{project-root}/.nexus/method/core/workflows/one-step-at-a-time/workflow.md` before step 1. One step file in memory, the step finished before the next is read, and a full stop at every checkpoint.

This uses **step-file architecture** for disciplined execution:

### Core Principles

- **Micro-file Design**: Each step is a self-contained instruction file that must be followed exactly
- **Just-In-Time Loading**: Only the current step file is in memory - never load future step files until directed
- **Sequential Enforcement**: Sequence within step files must be completed in order, no skipping or optimization
- **State Tracking**: Document progress in output file frontmatter using `stepsCompleted` array
- **Append-Only Building**: Build the tech-spec by updating content as directed

### Step Processing Rules

1. **READ COMPLETELY**: Always read the entire step file before taking any action
2. **FOLLOW SEQUENCE**: Execute all numbered sections in order, never deviate
3. **WAIT FOR INPUT**: If a menu is presented, halt and wait for user selection
4. **CHECK CONTINUATION**: Only proceed to next step when user selects [C] (Continue)
5. **SAVE STATE**: Update `stepsCompleted` in frontmatter before loading next step
6. **LOAD NEXT**: When directed, read fully and follow the next step file

### Critical Rules (NO EXCEPTIONS)

- **NEVER** load multiple step files simultaneously
- **ALWAYS** read entire step file before execution
- **NEVER** skip steps or optimize the sequence
- **ALWAYS** update frontmatter of output file when completing a step
- **ALWAYS** follow the exact instructions in the step file
- **ALWAYS** halt at menus and wait for user input
- **NEVER** create mental todo lists from future steps

---

## INITIALIZATION SEQUENCE

### 1. Configuration Loading

Load and read full config from `{main_config}` and resolve:

- `project_name`, `user_name`, `communication_language`, `document_output_language`, `user_skill_level`
- `active_issue` = the issue key this run is scoped to (from `project.yaml` active feature / the run)
- Fixed by contract (not config keys): docs live in `{project-root}/.nexus/docs/`, specs in `{project-root}/.nexus/specs/{active_issue}/`, the board is `{project-root}/.nexus/board.yaml` (read-only)
- `date` as system-generated current datetime
- `project_context` = `**/project-context.md` (load if exists)
- ✅ YOU MUST ALWAYS SPEAK OUTPUT In your Agent communication style with the config `{communication_language}`

### Recall

Before the issue, the spec or any step file is read:

- `mcp__ai-memory__memory_query`: search this issue's topic, its feature and the modules it touches; read the hits that matter with `mcp__ai-memory__memory_read_page`. What the project already remembers is input, never something to ask the person again.
- `mcp__codegraph__codegraph_explore`: before any grep, find or file read while investigating code, ask the index with the symbols or the question; it returns the source and the call paths in one call.
- The run's preamble says whether each server is available and which `project`/`workspace` to pass. When one is not available, skip it and say so in one line.

### 2. First Step Execution

Read fully and follow: `{project-root}/.nexus/method/workflows/evo-quick-flow/quick-spec/steps/step-01-understand.md` to begin the workflow.
