---
name: 'step-03-review-continuation'
description: 'Detect whether this run continues after a code review, and extract the review context'
nextStepFile: './step-04-signal-start.md'
---

# Step 3: Detect review continuation and extract review context

**Step 3 of 10** - Next: signal work has started

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🚫 Do NOT read the next step file until this one is finished
- 🛑 What a person wrote in the review is the INPUT to your work. Read it, never rewrite it
- 💬 BE CONCISE. One-line status updates, no preambles
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Determine whether this is a fresh start or a continuation after code review, and set `review_continuation` accordingly.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="3" goal="Detect review continuation and extract review context">
  <critical>Determine if this is a fresh start or continuation after code review</critical>

  <action>Check if "Senior Developer Review (AI)" section exists in the story file</action>
  <action>Check if "Review Follow-ups (AI)" subsection exists under Tasks/Subtasks</action>

  <check if="Senior Developer Review section exists">
    <action>Set review_continuation = true</action>
    <action>Extract from "Senior Developer Review (AI)" section:
      - Review outcome (Approve/Changes Requested/Blocked)
      - Review date
      - Total action items with checkboxes (count checked vs unchecked)
      - Severity breakdown (High/Med/Low counts)
    </action>
    <action>Count unchecked [ ] review follow-up tasks in "Review Follow-ups (AI)" subsection</action>
    <action>Store list of unchecked review items as {{pending_review_items}}</action>

    <output>⏯️ **Resuming Story After Code Review** ({{review_date}})

      **Review Outcome:** {{review_outcome}}
      **Action Items:** {{unchecked_review_count}} remaining to address
      **Priorities:** {{high_count}} High, {{med_count}} Medium, {{low_count}} Low

      **Strategy:** Will prioritize review follow-up tasks (marked [AI-Review]) before continuing with regular tasks.
    </output>
  </check>

  <check if="Senior Developer Review section does NOT exist">
    <action>Set review_continuation = false</action>
    <action>Set {{pending_review_items}} = empty</action>

    <output>🚀 **Starting Fresh Implementation**

      Spec: {{spec_key}}
      Issue Column: {{issue_column}}
      First incomplete task: {{first_task_description}}
    </output>
  </check>
</step>

## NEXT STEP:

Read fully and follow `{nextStepFile}` (step-04-signal-start.md).

## SUCCESS:

✅ `review_continuation` set from what the spec actually contains
✅ `{{pending_review_items}}` holds every unchecked review follow-up when continuing
✅ The user is told which of the two modes this run is in

## FAILURE:

❌ Treating a review continuation as a fresh start, so review findings go unaddressed
❌ Rewriting or tidying what the reviewer wrote
