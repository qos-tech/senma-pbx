---
key: '{slug}' # REQUIRED: the spec's own key, the file name without .md. When
# Step 1 appended -2 or -3 to avoid overwriting an existing file, the key
# carries that suffix too: a key that does not match the file name links a card
# to a spec that cannot be opened.
issue: '{issue}' # REQUIRED: the issue key this spec belongs to, e.g. LOJA-113
# Without key and issue the app REFUSES the whole spec: the card never links it
# and the board reports a file it could not put up.
title: '{title}'
done: false
story: '' # the user-facing goal, one sentence, the spec's story
criteria: [] # acceptance criteria as a list (typed; the body mirrors this)
# tasks: each needs a unique id AND text, on their own lines. A flow map on one
# line ({ text: ..., done: false }) is NOT read and the task is lost.
# ac: the criterion ids this task serves, from the criteria list above. Only
# ids spelled there; an id that is not a slug is REFUSED with the whole spec.
# optional: true marks a task that may be skipped without failing a criterion.
# Leave both out when the task serves no named criterion and must be done.
tasks: []
#  - id: 't1'
#    text: 'Task 1: what to do'
#    done: false
#    ac: [c1, c2]
links: {} # a MAP of name to target, e.g. pr: 'https://...'. Not a list.
# The frontmatter ends here. The app rewrites this file from exactly the fields
# above whenever a task is ticked, so any other key (type, status, created, a
# context list) is deleted then, silently. Put that material in the body, which
# the app never touches.
---

<!-- Target: 900–1300 tokens. Above 1600 = high risk of context rot.
     Never over-specify "how", use boundaries + examples instead.
     Cohesive cross-layer stories (DB+BE+UI) stay in ONE file.
     IMPORTANT: Remove all HTML comments when filling this template. -->

# {title}

<frozen-after-approval reason="human-owned intent, do not modify unless human renegotiates">

## Intent

<!-- What is broken or missing, and why it matters. Then the high-level approach, the "what", not the "how". -->

**Problem:** ONE_TO_TWO_SENTENCES

**Approach:** ONE_TO_TWO_SENTENCES

## Boundaries & Constraints

<!-- Three tiers: Always = invariant rules. Ask First = human-gated decisions. Never = out of scope + forbidden approaches. -->

**Always:** INVARIANT_RULES

**Ask First:** DECISIONS_REQUIRING_HUMAN_APPROVAL
<!-- Agent: if any of these trigger during execution, HALT and ask the user before proceeding. -->

**Never:** NON_GOALS_AND_FORBIDDEN_APPROACHES

## I/O & Edge-Case Matrix

<!-- If no meaningful I/O scenarios exist, DELETE THIS ENTIRE SECTION. Do not write "N/A" or "None". -->

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| HAPPY_PATH | INPUT | OUTCOME | N/A |
| ERROR_CASE | INPUT | OUTCOME | ERROR_HANDLING |

</frozen-after-approval>

## Code Map

<!-- Agent-populated during planning. Annotated paths prevent blind codebase searching. -->

- `FILE` -- ROLE_OR_RELEVANCE
- `FILE` -- ROLE_OR_RELEVANCE

## Tasks & Acceptance

<!-- Tasks: backtick-quoted file path -- action -- rationale. Prefer one task per file; group tightly-coupled changes when splitting would be artificial. -->
<!-- If an I/O Matrix is present, include a task to unit-test its edge cases. -->
<!-- AC covers system-level behaviors not captured by the I/O Matrix. Do not duplicate I/O scenarios here. -->

**Execution:**
- [ ] `FILE` -- ACTION -- RATIONALE

**Acceptance Criteria:**
- Given PRECONDITION, when ACTION, then EXPECTED_RESULT

## Spec Change Log

<!-- Append-only. Populated by step-04 during review loops. Do not modify or delete existing entries.
     Each entry records: what finding triggered the change, what was amended, what known-bad state
     the amendment avoids, and any KEEP instructions (what worked well and must survive re-derivation).
     Empty until the first bad_spec loopback. -->

## Design Notes

<!-- If the approach is straightforward, DELETE THIS ENTIRE SECTION. Do not write "N/A" or "None". -->
<!-- Design rationale and golden examples only when non-obvious. Keep examples to 5–10 lines. -->

DESIGN_RATIONALE_AND_EXAMPLES

## Verification

<!-- If no build, test, or lint commands apply, DELETE THIS ENTIRE SECTION. Do not write "N/A" or "None". -->
<!-- How the agent confirms its own work. Prefer CLI commands. When no CLI check applies, state what to inspect manually. -->

**Commands:**
- `COMMAND` -- expected: SUCCESS_CRITERIA

**Manual checks (if no CLI):**
- WHAT_TO_INSPECT_AND_EXPECTED_STATE

## Dev Agent Record

<!-- Agent-written during implementation. The agent updates only this section and the
     spec's tasks[].done. It appends a comment to the issue frontmatter
     (who: "agent:<id>"); it never writes the board, the issue context, or its criteria. -->

AGENT_NOTES_ON_WHAT_WAS_IMPLEMENTED
