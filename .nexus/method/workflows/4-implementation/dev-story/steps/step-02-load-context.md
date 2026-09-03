---
name: 'step-02-load-context'
description: 'Load project context and story information before any implementation'
nextStepFile: './step-03-review-continuation.md'
---

# Step 2: Load project context and story information

**Step 2 of 10** - Next: detect review continuation

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🚫 Do NOT read the next step file until this one is finished
- 📚 Read fully and follow `{project-root}/.nexus/method/references/context-budget.md` before loading any planning document: the frontmatter before the body, the one section before the whole file
- 💬 BE CONCISE. One-line status updates, no preambles
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Load everything that informs implementation, and nothing else.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="2" goal="Load project context and story information">
  <critical>Load all available context to inform implementation</critical>

  <action>Load {project_context} for coding standards and project-wide patterns (if exists)</action>
  <action>Parse sections: Story, Acceptance Criteria, Tasks/Subtasks, Dev Notes, Dev Agent Record, File List, Change Log, Status</action>
  <action>Load comprehensive context from story file's Dev Notes section</action>
  <action>Extract developer guidance from Dev Notes: architecture requirements, previous learnings, technical specifications</action>
  <action>Use enhanced story context to inform implementation decisions and approaches</action>
  <output>✅ **Context Loaded**
    Story and project context available for implementation
  </output>
</step>

## NEXT STEP:

Read fully and follow `{nextStepFile}` (step-03-review-continuation.md).

## SUCCESS:

✅ `project-context.md` loaded when it exists
✅ Every spec section parsed, Dev Notes guidance extracted
✅ A document already read in this run was not read again

## FAILURE:

❌ Implementing without the Dev Notes guidance the spec carries
❌ Re-reading a document already in context, which is the 35.4% the context budget names
