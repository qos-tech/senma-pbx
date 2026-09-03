---
key: '{{spec_key}}'
title: '{{story_title}}'
issue: '{{active_issue}}'
done: false
story: "As a {{role}}, I want {{action}}, so that {{benefit}}."
criteria:
  - id: c1
    text: "[Add acceptance criterion from epics/PRD]"
  - id: c2
    text: "[Add acceptance criterion from epics/PRD]"
# tasks: `ac` names the criterion ids this task serves, and only ids spelled
# under `criteria` above. `optional: true` marks a task that may be skipped
# without failing a criterion; leave the field out on an ordinary task.
tasks:
  - id: t1
    text: "[What this task does]"
    done: false
    ac: [c1]
  - id: t2
    text: "[What this task does]"
    done: false
    ac: [c1, c2]
links:
  prd: "docs/prd.md#section"
  architecture: "docs/architecture.md#section"
---

## Story

As a {{role}},
I want {{action}},
so that {{benefit}}.

## Acceptance Criteria

1. [Add acceptance criterion from epics/PRD]
2. [Add acceptance criterion from epics/PRD]

## Tasks / Subtasks

- [ ] [What this task does] (AC: c1)
- [ ] [What this task does] (AC: c1, c2)

## Dev Notes

- Relevant architecture patterns and constraints
- Source tree components to touch
- Testing standards summary

### Project Structure Notes

- Alignment with unified project structure (paths, modules, naming)
- Detected conflicts or variances (with rationale)

### References

- Cite all technical details with source paths and sections, e.g. [Source: docs/<file>.md#Section]

## Dev Agent Record

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List
