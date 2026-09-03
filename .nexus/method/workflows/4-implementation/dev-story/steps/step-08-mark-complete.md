---
name: 'step-08-mark-complete'
description: 'Mark the task complete only when every validation gate passes, then loop or finish'
loopStepFile: './step-05-implement.md'
nextStepFile: './step-09-complete.md'
---

# Step 8: Validate and mark task complete ONLY when fully done

**Step 8 of 10** - Next: back to step 5 for the next task, or step 9 when none remain

**This step closes the loop.** While incomplete tasks remain, it sends you back
to `{loopStepFile}` (step-05-implement.md). Re-reading that file is required.

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🛑 NEVER mark a task complete unless ALL conditions are met - NO LYING OR CHEATING
- 🛑 The write boundary holds: only `tasks[].done` and the Dev Agent Record, plus the appended issue comment
- 💬 BE CONCISE. One-line status updates
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Pass every gate before ticking anything, then decide whether the loop continues.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="8" goal="Validate and mark task complete ONLY when fully done">
  <critical>NEVER mark a task complete unless ALL conditions are met - NO LYING OR CHEATING</critical>

  <!-- VALIDATION GATES -->
  <action>Verify ALL tests for this task/subtask ACTUALLY EXIST and PASS 100%</action>
  <action>Confirm implementation matches EXACTLY what the task/subtask specifies - no extra features</action>
  <action>Validate that ALL acceptance criteria related to this task are satisfied</action>
  <action>Run full test suite to ensure NO regressions introduced</action>

  <!-- REVIEW FOLLOW-UP HANDLING -->
  <check if="task is review follow-up (has [AI-Review] prefix)">
    <action>Extract review item details (severity, description, related AC/file)</action>
    <action>Add to resolution tracking list: {{resolved_review_items}}</action>

    <!-- Mark task in Review Follow-ups section -->
    <action>Mark task checkbox [x] in "Tasks/Subtasks → Review Follow-ups (AI)" section</action>

    <!-- CRITICAL: Also mark corresponding action item in review section -->
    <action>Find matching action item in "Senior Developer Review (AI) → Action Items" section by matching description</action>
    <action>Mark that action item checkbox [x] as resolved</action>

    <action>Add to Dev Agent Record → Completion Notes: "✅ Resolved review finding [{{severity}}]: {{description}}"</action>
  </check>

  <!-- ONLY MARK COMPLETE IF ALL VALIDATION PASS -->
  <check if="ALL validation gates pass AND tests ACTUALLY exist and pass">
    <action>ONLY THEN mark the task (and subtasks) checkbox with [x]</action>
    <action>Update File List section with ALL new, modified, or deleted files (paths relative to repo root)</action>
    <action>Add completion notes to Dev Agent Record summarizing what was ACTUALLY implemented and tested</action>
  </check>

  <check if="ANY validation fails">
    <action>DO NOT mark task complete - fix issues first</action>
    <action>HALT if unable to fix validation failures</action>
  </check>

  <check if="review_continuation == true and {{resolved_review_items}} is not empty">
    <action>Count total resolved review items in this session</action>
    <action>Add Change Log entry: "Addressed code review findings - {{resolved_count}} items resolved (Date: {{date}})"</action>
  </check>

  <action>Save the story file</action>
  <action>Determine if more incomplete tasks remain</action>
  <action if="more tasks remain">
    <goto step="5">Next task: ./step-05-implement.md</goto>
  </action>
  <action if="no tasks remain">
    <goto step="9">Completion: ./step-09-complete.md</goto>
  </action>
</step>

## NEXT STEP:

- **More incomplete tasks remain:** read fully and follow `{loopStepFile}` (step-05-implement.md) and run the loop again for the next task. Do NOT stop between tasks and do NOT summarize progress; only a HALT condition stops this run.
- **No incomplete tasks remain:** read fully and follow `{nextStepFile}` (step-09-complete.md).

## SUCCESS:

✅ A checkbox was ticked ONLY after tests that really exist really passed
✅ File List updated with every new, modified and deleted file, paths relative to repo root
✅ Review follow-ups marked in BOTH places: the follow-up subsection and the review's Action Items
✅ The story file saved, and the loop decision taken from what the spec now says

## FAILURE:

❌ Ticking a task whose tests do not exist or do not pass, which is the lie this step exists to stop
❌ Implementing extra features and calling the task done
❌ Marking a review follow-up in one place only, so the review still reads as unresolved
❌ Stopping between tasks instead of returning to step 5
