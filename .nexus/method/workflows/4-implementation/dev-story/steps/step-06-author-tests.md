---
name: 'step-06-author-tests'
description: 'Author the comprehensive tests the story requires for the current task'
nextStepFile: './step-07-run-validations.md'
---

# Step 6: Author comprehensive tests

**Step 6 of 10** - Next: run validations and tests

**Inside the loop.** This step runs once per task, after step 5.

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🚫 Do NOT read the next step file until this one is finished
- 🛑 NEVER lie about tests being written or passing. Tests must actually exist
- 💬 BE CONCISE. Show code, not explanations
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Cover the work of this task at every level the story requires, and no level it does not.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="6" goal="Author comprehensive tests">
  <action>Create unit tests for business logic and core functionality introduced/changed by the task</action>
  <action>Add integration tests for component interactions specified in story requirements</action>
  <action>Include end-to-end tests for critical user flows when story requirements demand them</action>
  <action>Cover edge cases and error handling scenarios identified in story Dev Notes</action>
</step>

## NEXT STEP:

Read fully and follow `{nextStepFile}` (step-07-run-validations.md).

## SUCCESS:

✅ Unit tests exist for every piece of core functionality this task introduced or changed
✅ Integration tests added where the story requirements demand them
✅ End-to-end tests added where the story requirements demand them
✅ Edge cases from Dev Notes covered

## FAILURE:

❌ Claiming coverage that does not exist as a real, running test
❌ Skipping the edge cases the Dev Notes name
