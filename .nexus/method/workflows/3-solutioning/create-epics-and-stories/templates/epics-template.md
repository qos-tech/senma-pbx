---
# Read as a YAML SUBSET, not as full YAML. A list ALWAYS indents two spaces
# under its key, and a value ALWAYS stays on one line. A list at its key's own
# indentation, or a sentence folded onto a second line, is valid YAML that this
# reader refuses. Keep the shape below exactly.
stepsCompleted:
  - step-01-validate-prerequisites
inputDocuments:
  - '{docs_dir}/prd.md'
requirements: |
  {{fr_list}}
  {{nfr_list}}
  {{additional_requirements}}
  {{requirements_coverage_map}}
epics:
  - id: EPIC-1
    title: '{{epic_title_1}}'
    goal: '{{epic_goal_1}}'
    stories:
      - id: '1.1'
        title: '{{story_title_1_1}}'
        statement: 'As a {{user_type}}, I want {{capability}}, so that {{value_benefit}}.'
        criteria:
          - 'Given {{precondition}}, when {{action}}, then {{expected_outcome}}'
      - id: '1.2'
        title: '{{story_title_1_2}}'
        statement: 'As a {{user_type}}, I want {{capability}}, so that {{value_benefit}}.'
        criteria:
          - 'Given {{precondition}}, when {{action}}, then {{expected_outcome}}'
        dependsOn:
          - '1.1'
---

# {{project_name}} - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for {{project_name}}, decomposing the requirements from the PRD, UX Design if it exists, and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

{{fr_list}}

### NonFunctional Requirements

{{nfr_list}}

### Additional Requirements

{{additional_requirements}}

### FR Coverage Map

{{requirements_coverage_map}}

## Epic List

{{epics_list}}

<!-- Repeat for each epic in epics_list (N = 1, 2, 3...) -->

## Epic {{N}}: {{epic_title_N}}

{{epic_goal_N}}

<!-- Repeat for each story (M = 1, 2, 3...) within epic N -->

### Story {{N}}.{{M}}: {{story_title_N_M}}

As a {{user_type}},
I want {{capability}},
So that {{value_benefit}}.

**Acceptance Criteria:**

<!-- for each AC on this story -->

**Given** {{precondition}}
**When** {{action}}
**Then** {{expected_outcome}}
**And** {{additional_criteria}}

**Depends on:** {{story_dependencies_N_M}}

<!-- End story repeat -->
