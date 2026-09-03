---
name: set-feature
description: 'Set the active feature context. The feature is a field on project.yaml that filters the board; it creates no folders and moves nothing. Use when the user says "set feature", "switch feature", "new feature", or "what feature is active"'
---

# Set Feature Workflow

**Goal:** Set or switch the `active_feature` field so the board is filtered to that feature. The feature is a label, not a folder. Specs continue to live under `.nexus/specs/<ISSUE-KEY>/`, grouped by issue, regardless of the active feature.

**WHAT to read:** Read fully and follow: `{project-root}/.nexus/method/references/context-budget.md` before you load any planning document. The frontmatter before the body, the one section before the whole file, and a spec of more than 3 tasks is one to split.

---

## INITIALIZATION

Load config from `{project-root}/.nexus/project.yaml` and resolve:

- `project_name`, `user_name`, `communication_language`
- `active_feature` (current value, may be empty)
- YOU MUST ALWAYS SPEAK OUTPUT in your Agent communication style with the config `{communication_language}`

---

## EXECUTION

### 1. Show Current State

Display the current active feature:

- If `active_feature` is set: "Active feature: **{{active_feature}}**"
- If empty: "No active feature set."

### 2. Ask for Feature Slug

Ask the user:

"What is the feature name? Use a short kebab-case slug (e.g. `admin-panel`, `auth-refactor`, `dashboard-financeiro`). This becomes the `active_feature` label that filters the board. It is not a folder name; specs stay under `.nexus/specs/<ISSUE-KEY>/`."

Wait for user input.

### 3. Validate Input

- Must be non-empty
- Suggest converting spaces to hyphens and lowercasing if needed
- Confirm the final slug with the user before proceeding

### 4. Update Config

Edit `{project-root}/.nexus/project.yaml`:

- Find the `active_feature:` key
- Update its value to the confirmed slug
- Save the file

### 5. No Folders Are Created

Setting the active feature creates no directories and moves nothing. The feature is a field on `project.yaml` that filters the board. Specs continue to live under `.nexus/specs/<ISSUE-KEY>/`, grouped by issue, and a feature's planning docs stay under `.nexus/features/<FEATURE-KEY>/`. Nothing on disk is reorganized by this step.

### 6. Confirm

Inform the user:

"Feature set to **{{active_feature}}**.

The board is now filtered to this feature. No folders were created, and nothing was moved. Specs stay under `.nexus/specs/<ISSUE-KEY>/`, grouped by issue.

You can switch features anytime by running `/evo-bmm-set-feature`."

---

## SUCCESS METRICS

✅ `active_feature` updated in `.nexus/project.yaml`
✅ No folders created and nothing moved; the field only filters the board
✅ User clearly informed of the new active feature and that specs stay under `.nexus/specs/<ISSUE-KEY>/`
