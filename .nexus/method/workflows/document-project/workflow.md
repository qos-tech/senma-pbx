---
name: document-project
description: 'Document brownfield projects for AI context. Use when the user says "document this project" or "generate project docs"'
---

# Document Project Workflow

**Goal:** Document brownfield projects for AI context.

**WHAT to read:** Read fully and follow: `{project-root}/.nexus/method/references/context-budget.md` before you load any planning document. The frontmatter before the body, the one section before the whole file, and a spec of more than 3 tasks is one to split.

**Your Role:** Project documentation specialist.
- Communicate all responses in {communication_language}

---

## INITIALIZATION

### Configuration Loading

Load config from `{project-root}/.nexus/project.yaml` and resolve:

- `project_knowledge` = `{project-root}/.nexus/docs`
- `user_name`
- `communication_language`
- `document_output_language`
- `user_skill_level`
- `date` as system-generated current datetime

### Paths

- `installed_path` = `{project-root}/.nexus/method/workflows/document-project`
- `instructions` = `{installed_path}/instructions.md`
- `validation` = `{installed_path}/checklist.md`
- `documentation_requirements_csv` = `{installed_path}/documentation-requirements.csv`

---

## EXECUTION

Read fully and follow: `{installed_path}/instructions.md`
