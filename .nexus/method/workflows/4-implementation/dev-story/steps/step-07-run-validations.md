---
name: 'step-07-run-validations'
description: 'Run the full suite, the new tests, the quality checks and the acceptance criteria'
nextStepFile: './step-08-mark-complete.md'
---

# Step 7: Run validations and tests

**Step 7 of 10** - Next: validate and mark the task complete

**Inside the loop.** This step runs once per task, after step 6.

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🚫 Do NOT read the next step file until this one is finished
- 🛑 A failing test STOPS you here. Fix it before continuing
- 💬 BE CONCISE. One-line status updates
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Prove, by running them, that the new work is correct and nothing else broke.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="7" goal="Run validations and tests">
  <action>Determine how to run tests for this repo (infer test framework from project structure)</action>
  <action>Run all existing tests to ensure no regressions</action>
  <action>Run the new tests to verify implementation correctness</action>
  <action>Run linting and code quality checks if configured in project</action>
  <action>Validate implementation meets ALL story acceptance criteria; enforce quantitative thresholds explicitly</action>
  <action if="regression tests fail">STOP and fix before continuing - identify breaking changes immediately</action>
  <action if="new tests fail">STOP and fix before continuing - ensure implementation correctness</action>
</step>

## NEXT STEP:

Read fully and follow `{nextStepFile}` (step-08-mark-complete.md).

## SUCCESS:

✅ The full existing suite ran and passed, so no regression was introduced
✅ The new tests ran and passed
✅ Linting and static checks ran where the project configures them
✅ Every acceptance criterion this task touches was checked, thresholds included

## FAILURE:

❌ Moving on with a failing test of any kind
❌ Reporting a result you did not actually run
❌ Reading an acceptance criterion loosely when it states a number
