---
name: create-architecture
description: 'Create architecture solution design decisions for AI agent consistency. Use when the user says "lets create architecture" or "create technical architecture" or "create a solution design"'
---

# Architecture Workflow

**Goal:** Create comprehensive architecture decisions through collaborative step-by-step discovery that ensures AI agents implement consistently.

**Your Role:** You are an architectural facilitator collaborating with a peer. This is a partnership, not a client-vendor relationship. You bring structured thinking and architectural knowledge, while the user brings domain expertise and product vision. Work together as equals to make decisions that prevent implementation conflicts.

---

## WORKFLOW ARCHITECTURE

This uses **micro-file architecture** for disciplined execution:

- Each step is a self-contained file with embedded rules
- Sequential progression with user control at each step
- Document state tracked in frontmatter
- Append-only document building through conversation
- You NEVER proceed to a step file if the current step file indicates the user must approve and indicate continuation.

**HOW to pace this:** Read fully and follow: `{project-root}/.nexus/method/core/workflows/one-step-at-a-time/workflow.md` before step 1. One step file in memory, the step finished before the next is read, and a full stop at every checkpoint.

**WHAT to read:** Read fully and follow: `{project-root}/.nexus/method/references/context-budget.md` before you load any planning document. The frontmatter before the body, the one section before the whole file, and a spec of more than 3 tasks is one to split.

---

## INITIALIZATION

### Configuration Loading

Load config from `{project-root}/.nexus/project.yaml` and resolve:

- `project_name`, `output_folder`, `user_name`
- `communication_language`, `document_output_language`, `user_skill_level`
- `date` as system-generated current datetime
- The planning artifacts folder is `{docs_dir}`, assigned by the runner.
- ✅ YOU MUST ALWAYS SPEAK OUTPUT In your Agent communication style with the config `{communication_language}`

### Paths

- `installed_path` = `{project-root}/.nexus/method/workflows/3-solutioning/create-architecture`
- `template_path` = `{installed_path}/architecture-decision-template.md`
- `data_files_path` = `{installed_path}/data/`

---

## EXECUTION

Read fully and follow: `{project-root}/.nexus/method/workflows/3-solutioning/create-architecture/steps/step-01-init.md` to begin the workflow.

**Note:** Input document discovery and all initialization protocols are handled in step-01-init.md.
