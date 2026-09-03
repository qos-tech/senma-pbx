---
name: 'step-05-implement'
description: 'Implement the current task following the red-green-refactor cycle'
nextStepFile: './step-06-author-tests.md'
---

# Step 5: Implement task following red-green-refactor cycle

**Step 5 of 10** - Next: author comprehensive tests

**This step is the head of the loop.** Steps 5, 6, 7 and 8 run once per task.
Step 8 sends you back HERE while incomplete tasks remain, so reading this file
again is required and is not a violation of one-step-at-a-time.

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🚫 Do NOT read the next step file until this one is finished
- 🛑 Execute continuously. Do NOT stop for "milestones", "significant progress" or "session boundaries". Only a HALT condition stops you
- 🎯 NEVER implement anything not mapped to a specific task/subtask in the story file
- 💬 BE CONCISE. Show code, not explanations
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Implement the current task exactly as the story file writes it, failing test first.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="5" goal="Implement task following red-green-refactor cycle">
  <critical>FOLLOW THE STORY FILE TASKS/SUBTASKS SEQUENCE EXACTLY AS WRITTEN - NO DEVIATION</critical>

  <action>Review the current task/subtask from the story file - this is your authoritative implementation guide</action>
  <action>Plan implementation following red-green-refactor cycle</action>

  <!-- RED PHASE -->
  <action>Write FAILING tests first for the task/subtask functionality</action>
  <action>Confirm tests fail before implementation - this validates test correctness</action>

  <!-- GREEN PHASE -->
  <action>Implement MINIMAL code to make tests pass</action>
  <action>Run tests to confirm they now pass</action>
  <action>Handle error conditions and edge cases as specified in task/subtask</action>

  <!-- REFACTOR PHASE -->
  <action>Improve code structure while keeping tests green</action>
  <action>Ensure code follows architecture patterns and coding standards from Dev Notes</action>

  <action>Document technical approach and decisions in Dev Agent Record → Implementation Plan</action>

  <action if="new dependencies required beyond story specifications">HALT: "Additional dependencies need user approval"</action>
  <action if="3 consecutive implementation failures occur">HALT and request guidance</action>
  <action if="required configuration is missing">HALT: "Cannot proceed without necessary configuration files"</action>

  <critical>NEVER implement anything not mapped to a specific task/subtask in the story file</critical>
  <critical>NEVER proceed to next task until current task/subtask is complete AND tests pass</critical>
  <critical>Execute continuously without pausing until all tasks/subtasks are complete or explicit HALT condition</critical>
  <critical>Do NOT propose to pause for review until the step 9 completion gates are satisfied</critical>
</step>

## NEXT STEP:

Read fully and follow `{nextStepFile}` (step-06-author-tests.md).

## SUCCESS:

✅ A failing test was written and seen to fail BEFORE the implementation
✅ Only what the current task/subtask specifies was implemented
✅ Technical approach recorded in Dev Agent Record → Implementation Plan

## FAILURE:

❌ Writing implementation first and the test after, so the test proves nothing
❌ Implementing something no task maps to
❌ Pausing for review before the step 9 gates are satisfied
❌ Adding a dependency the story does not specify without user approval
