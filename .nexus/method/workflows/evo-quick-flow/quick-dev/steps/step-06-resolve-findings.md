---
name: 'step-06-resolve-findings'
description: 'Handle review findings interactively, apply fixes, update tech-spec with final status'
---

# Step 6: Resolve Findings

**Goal:** Handle adversarial review findings interactively, apply fixes, finalize tech-spec.

---

## AVAILABLE STATE

From previous steps:

- `{baseline_commit}` - Git HEAD at workflow start
- `{execution_mode}` - "tech-spec" or "direct"
- `{tech_spec_path}` - Tech-spec file (if Mode A)
- Findings table from step-05

---

## RESOLUTION OPTIONS

Present: "How would you like to handle these findings?"

Display:
**HOW to ask this menu:** Read fully and follow: {project-root}/.nexus/method/core/workflows/ask-the-person/workflow.md - show the section above BEFORE asking, offer these same choices through the asking channel this run provides, and keep the written menu as the fallback when that channel is unavailable.

**[W] Walk through** - Discuss each finding individually
**[F] Fix automatically** - Automatically fix issues classified as "real"
**[S] Skip** - Acknowledge and proceed to commit

### Menu Handling Logic:

- IF W: Execute WALK THROUGH section below
- IF F: Execute FIX AUTOMATICALLY section below
- IF S: Execute SKIP section below

### EXECUTION RULES:

- ALWAYS halt and wait for user input after presenting menu
- ONLY proceed when user makes a selection

---

## WALK THROUGH [W]

For each finding in order:

1. Present the finding with context
2. Ask: **fix now / skip / discuss**
3. If fix: Apply the fix immediately
4. If skip: Note as acknowledged, continue
5. If discuss: Provide more context, re-ask
6. Move to next finding

After all findings processed, summarize what was fixed/skipped.

---

## FIX AUTOMATICALLY [F]

1. Filter findings to only those classified as "real"
2. Apply fixes for each real finding
3. Report what was fixed:

```
**Auto-fix Applied:**
- F1: {description of fix}
- F3: {description of fix}
...

Skipped (noise/uncertain): F2, F4
```

---

## SKIP [S]

1. Acknowledge all findings were reviewed
2. Note that user chose to proceed without fixes
3. Continue to completion

---

## UPDATE SPEC (Mode A only)

If `{execution_mode}` is "tech-spec":

1. Load `{tech_spec_path}` (the spec is a story under `{project-root}/.nexus/specs/{active_issue}/`)
2. Record the review outcome in the spec's Dev Agent Record:
   ```
   ## Dev Agent Record, Review Notes
   - Adversarial review completed
   - Findings: {count} total, {fixed} fixed, {skipped} skipped
   - Resolution approach: {walk-through/auto-fix/skip}
   ```
3. Save changes

Write boundary: the agent modifies only the spec's `tasks[].done` and its Dev Agent Record, and appends a comment to `{project-root}/.nexus/issues/{active_issue}.md` frontmatter with `who: "agent:<id>"`. It NEVER writes `{project-root}/.nexus/board.yaml` (the app is the board's only writer), the issue's context, or its criteria.

---

## COMPLETION OUTPUT

```
**Review complete. Ready to commit.**

**Implementation Summary:**
- {what was implemented}
- Files modified: {count}
- Tests: {status}
- Review findings: {X} addressed, {Y} skipped

{Explain what was implemented based on user_skill_level}
```

---

## WORKFLOW COMPLETE

This is the final step. The Quick Dev workflow is now complete.

User can:

- Commit changes
- Run additional tests
- Start new Quick Dev session

---

### Record

Before this workflow ends, write what the next run must not rediscover with `mcp__ai-memory__memory_write_page`, to the `project` and `workspace` the run's preamble names, under `nexus/{active_issue}/quick-dev.md`:

- the implementation decisions made and why;
- discoveries about the code that the documents did not say;
- what failed or was rejected, so nobody retries it.

When the preamble says memory is not available, skip the call and say so in one line.

## SUCCESS METRICS

- User presented with resolution options
- Chosen approach executed correctly
- Fixes applied cleanly (if applicable)
- Tech-spec updated with final status (Mode A)
- Completion summary provided
- User understands what was implemented

## FAILURE MODES

- Not presenting resolution options
- Auto-fixing "noise" or "uncertain" findings
- Not updating tech-spec after resolution (Mode A)
- No completion summary
- Leaving user unclear on next steps
