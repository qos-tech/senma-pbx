---
name: create-ux-design
description: 'Plan UX patterns and design specifications. Use when the user says "lets create UX design" or "create UX specifications" or "help me plan the UX"'
---

# Create UX Design Workflow

**Goal:** Create comprehensive UX design specifications through collaborative visual exploration and informed decision-making where you act as a UX facilitator working with a product stakeholder.

---

## WORKFLOW ARCHITECTURE

This uses **micro-file architecture** for disciplined execution:

- Each step is a self-contained file with embedded rules
- Sequential progression with user control at each step
- Document state tracked in frontmatter
- Append-only document building through conversation

**HOW to pace this:** Read fully and follow: `{project-root}/.nexus/method/core/workflows/one-step-at-a-time/workflow.md` before step 1. One step file in memory, the step finished before the next is read, and a full stop at every checkpoint.

**WHAT to read:** Read fully and follow: `{project-root}/.nexus/method/references/context-budget.md` before you load any planning document. The frontmatter before the body, the one section before the whole file, and a spec of more than 3 tasks is one to split.

---

## INITIALIZATION

### Configuration Loading

Load config from `{project-root}/.nexus/project.yaml` and resolve:

- `project_name`, `output_folder`, `{docs_dir}` (assigned by the runner), `user_name`
- `communication_language`, `document_output_language`, `user_skill_level`
- `date` as system-generated current datetime

### Paths

- `installed_path` = `{project-root}/.nexus/method/workflows/2-plan-workflows/create-ux-design`
- `template_path` = `{installed_path}/ux-design-template.md`
- `default_output_file` = `{docs_dir}/ux.md`

## EXECUTION

- ✅ YOU MUST ALWAYS SPEAK OUTPUT In your Agent communication style with the config `{communication_language}`
- Read fully and follow: `{project-root}/.nexus/method/workflows/2-plan-workflows/create-ux-design/steps/step-01-init.md` to begin the UX design workflow.
