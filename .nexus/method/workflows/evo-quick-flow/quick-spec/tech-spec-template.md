---
key: 'tech-spec-{slug}' # REQUIRED: the file name without .md. Step 4 saves this
# file as tech-spec-{slug}.md, so the key carries the prefix too. A key that
# does not match the file name links a card to a spec that cannot be opened.
issue: '{issue}' # REQUIRED: the issue key this spec belongs to, e.g. LOJA-113
# Without key and issue the app REFUSES the whole spec: the card never links it
# and the board reports a file it could not put up.
title: '{title}'
done: false
route: '' # one-shot or plan-code-review, chosen by the router and shown on screen
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
# The frontmatter ends here. The app writes this file back whenever a task is
# ticked, and it writes ONLY the fields above; any other key you add is deleted
# then, without a word. Working notes belong in the body, which the app leaves
# alone. That is why the WIP keys (slug, status, stepsCompleted) live only in
# tech-spec-wip.md and are gone by the time step 4 saves the final file.
---

# Tech-Spec: {title}

**Created:** {date}
**Stack:** {tech_stack}
**Files to modify:** {files_to_modify}
**Code patterns:** {code_patterns}
**Test patterns:** {test_patterns}

## Overview

### Problem Statement

{problem_statement}

### Solution

{solution}

### Scope

**In Scope:**
{in_scope}

**Out of Scope:**
{out_of_scope}

## Context for Development

### Codebase Patterns

{codebase_patterns}

### Files to Reference

| File | Purpose |
| ---- | ------- |

{files_table}

### Technical Decisions

{technical_decisions}

## Implementation Plan

### Tasks

{tasks}

### Acceptance Criteria

{acceptance_criteria}

## Additional Context

### Dependencies

{dependencies}

### Testing Strategy

{testing_strategy}

### Notes

{notes}

## Dev Agent Record

<!-- Agent-written during dev-story. The agent updates only this section and the
     spec's tasks[].done. It appends a comment to the issue frontmatter
     (who: "agent:<id>"); it never writes the board, the issue context, or its criteria. -->

{dev_agent_record}
