---
name: 'step-04-signal-start'
description: 'Signal that work has started by commenting on the issue, leaving the board to the app'
nextStepFile: './step-05-implement.md'
---

# Step 4: Signal work has started

**Step 4 of 10** - Next: implement the task

## RULES THAT BIND THIS STEP:

- 📖 Read this entire step file before taking any action
- 🚫 Do NOT read the next step file until this one is finished
- 🛑 The board has ONE writer, the app. Do NOT edit `board.yaml`
- ✍️ You announce the start by appending a comment to the issue; the app moves the column in reaction
- 💬 BE CONCISE. One-line status updates, no preambles
- ✅ Communicate in {communication_language}, tailored to {user_skill_level}

## YOUR TASK:

Announce the start of work in the only place you are allowed to write it, and record whether board tracking is available.

## SEQUENCE (do not deviate, skip, or optimize):

<step n="4" goal="Signal work has started" tag="board">
  <critical>The board has one writer: the app. Do NOT edit board.yaml. Announce start by appending a comment to the issue and touching
    the spec; the app moves {{active_issue}} into the dev column in reaction.</critical>
  <check if="{{board}} file exists">
    <action>Load the FULL file: {{board}} and read {{active_issue}}'s current column</action>

    <check if="issue column is 'specs' (spec ready) OR review_continuation == true">
      <action>Append a comment to `{{issue_file}}` frontmatter: `who: "agent:dev"`, `at: {date}`, `text: "Started work on spec {{spec_key}}."`</action>
      <critical>The frontmatter is fenced by `---` at the top AND a second `---` where it ends. Your comment goes BEFORE the closing
        fence, and that fence must still be there when you save. Read the file back and check both are present: one missing fence makes
        the entire issue unreadable, artifacts and every comment with it.</critical>
      <output>🚀 Starting work on spec {{spec_key}}
        The app moves {{active_issue}} into the dev column in reaction.
      </output>
    </check>

    <check if="issue column is already 'dev'">
      <output>⏯️ Resuming work on spec {{spec_key}}
        Issue is already in the dev column
      </output>
    </check>

    <check if="issue column is neither 'specs' nor 'dev'">
      <output>⚠️ Unexpected issue column: {{issue_column}}
        Expected specs or dev. Continuing anyway...
      </output>
    </check>

    <action>Store {{board_tracking}} = "enabled" for later use</action>
  </check>

  <check if="{{board}} file does NOT exist">
    <output>ℹ️ No board exists - spec progress will be tracked in the spec file only</output>
    <action>Set {{board_tracking}} = "no-board-tracking"</action>
  </check>
</step>

## NEXT STEP:

Read fully and follow `{nextStepFile}` (step-05-implement.md).

## SUCCESS:

✅ A comment with `who: "agent:dev"` appended to the issue frontmatter
✅ BOTH `---` fences still present when the issue file is saved, verified by reading it back
✅ `{{board_tracking}}` stored for steps 8 and 9
✅ `board.yaml` unchanged

## FAILURE:

❌ Editing `board.yaml` to move the column yourself
❌ Saving the issue file with a missing closing fence, which makes the whole issue unreadable
❌ Replacing existing comments instead of appending
