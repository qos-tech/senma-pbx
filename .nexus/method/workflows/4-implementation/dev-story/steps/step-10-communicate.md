---
name: 'step-10-communicate'
description: 'Communicate completion, answer the user, and suggest next steps'
---

# Step 10: Completion communication and user support

**Step 10 of 10 - FINAL STEP.** Do NOT load any further step file.

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🚫 NO more steps after this one
- 🛑 The board is the app's to move, never this workflow's
- 💬 BE CONCISE, and elaborate only where the user asks
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Tell the user what was built, answer what they ask, and hand them the next move.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="10" goal="Completion communication and user support">
  <action>Execute the enhanced definition-of-done checklist using the validation framework at `{project-root}/.nexus/method/workflows/4-implementation/dev-story/checklist.md`</action>
  <action>Prepare a concise summary in Dev Agent Record → Completion Notes</action>

  <action>Communicate to {user_name} that story implementation is complete and ready for review</action>
  <action>Summarize key accomplishments: story ID, story key, title, key changes made, tests added, files modified</action>
  <action>Provide the story file path and current status (now "review")</action>

  <action>Based on {user_skill_level}, ask if user needs any explanations about:
    - What was implemented and how it works
    - Why certain technical decisions were made
    - How to test or verify the changes
    - Any patterns, libraries, or approaches used
    - Anything else they'd like clarified
  </action>

  <check if="user asks for explanations">
    <action>Provide clear, contextual explanations tailored to {user_skill_level}</action>
    <action>Use examples and references to specific code when helpful</action>
  </check>

  <action>Once explanations are complete (or user indicates no questions), suggest logical next steps</action>
  <action>Recommended next steps (flexible based on project setup):
    - Review the implemented story and test the changes
    - Verify all acceptance criteria are met
    - Ensure deployment readiness if applicable
    - Run `code-review` workflow for peer review
    - Optional: If Test Architect module installed, run `/evo:tea:automate` to expand guardrail tests
  </action>

  <output>💡 **Tip:** For best results, run `code-review` using a **different** LLM than the one that implemented this story.</output>
  <check if="{board} file exists">
    <action>Suggest checking the board to see project progress</action>
  </check>
  <action>Remain flexible - allow user to choose their own path or ask for other assistance</action>
</step>

### Record

Before this workflow ends, write what the next run must not rediscover with `mcp__ai-memory__memory_write_page`, to the `project` and `workspace` the run's preamble names, under `nexus/<ISSUE-KEY>/dev-story.md`:

- the implementation decisions made and why;
- discoveries about the code that the documents did not say;
- what failed or was rejected, so nobody retries it.

When the preamble says memory is not available, skip the call and say so in one line.

## NEXT STEP:

None. This workflow is complete. Do NOT load another step file.

## SUCCESS:

✅ Completion Notes hold a concise summary of what was actually built and tested
✅ The user was told the story file path and that the status is now review
✅ The different-LLM tip for `code-review` was given
✅ The user's questions were answered at their skill level

## FAILURE:

❌ Loading another step file after this one
❌ Reporting completion the step 9 gates did not actually grant
❌ Leaving the user without a next step
