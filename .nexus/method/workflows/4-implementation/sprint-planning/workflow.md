---
name: sprint-planning
description: 'Lay out issues and specs from epics. Use when the user says "run sprint planning" or "generate sprint plan"'
---

# Sprint Planning Workflow

**Goal:** Lay out issues and specs from the epics, detecting which specs already have files, and writing the issue files under `.nexus/issues/` and the spec files under `.nexus/specs/<ISSUE-KEY>/`. The board follows: the app is its only writer.

**WHAT to read:** Read fully and follow: `{project-root}/.nexus/method/references/context-budget.md` before you load any planning document. The frontmatter before the body, the one section before the whole file, and a spec of more than 3 tasks is one to split.

**Your Role:** You are a Scrum Master laying out the issue and spec files. Parse epic files, detect which specs already exist on disk, and produce the issue and spec files. You READ `.nexus/board.yaml`; you never write it.

---

## INITIALIZATION

### Configuration Loading

Load config from `{project-root}/.nexus/project.yaml` and resolve:

- `project_name`, `user_name`
- `communication_language`, `document_output_language`
- `specs_dir` (`.nexus/specs/`)
- `docs_dir` (assigned by the runner)
- `date` as system-generated current datetime
- YOU MUST ALWAYS SPEAK OUTPUT in your Agent communication style with the config `{communication_language}`

### Paths

- `installed_path` = `{project-root}/.nexus/method/workflows/4-implementation/sprint-planning`
- `schema` = `{project-root}/.nexus/method/schema/` (the source of the issue and spec shapes)
- `checklist` = `{installed_path}/checklist.md`
- `tracking_system` = `nexus-board`
- `project_key` = `NOKEY`
- `spec_location` = `.nexus/specs/`
- `issue_location` = `.nexus/issues/`
- `epics_location` = `{docs_dir}`
- `epics_pattern` = `*epic*.md`
- `board` = `.nexus/board.yaml` (READ ONLY: the app is the board's only writer)

### Input Files

| Input | Path | Load Strategy |
|-------|------|---------------|
| Epics | `{docs_dir}/*epic*.md` (whole) or `{docs_dir}/*epic*/*.md` (sharded) | FULL_LOAD |

### Context

- `project_context` = `**/project-context.md` (load if exists)

---

## EXECUTION

### Document Discovery - Full Epic Loading

**Strategy**: Sprint planning needs ALL epics and stories to lay out the complete set of issues and specs.

**Epic Discovery Process:**

1. **Search for whole document first** - Look for `epics.md`, `bmm-epics.md`, or any `*epic*.md` file
2. **Check for sharded version** - If whole document not found, look for `epics/index.md`
3. **If sharded version found**:
   - Read `index.md` to understand the document structure
   - Read ALL epic section files listed in the index (e.g., `epic-1.md`, `epic-2.md`, etc.)
   - Process all epics and their stories from the combined content
   - This ensures complete issue and spec coverage
4. **Priority**: If both whole and sharded versions exist, use the whole document

**Fuzzy matching**: Be flexible with document names - users may use variations like `epics.md`, `bmm-epics.md`, `user-stories.md`, etc.

<workflow>

<step n="1" goal="Parse epic files and extract all work items">
<action>Load {project_context} for project-wide patterns and conventions (if exists)</action>
<action>Communicate in {communication_language} with {user_name}</action>
<action>Look for all files matching `{epics_pattern}` in {epics_location}</action>
<action>Could be a single `epics.md` file or multiple `epic-1.md`, `epic-2.md` files</action>

<action>For each epic file found, extract:</action>

- Epic numbers from headers like `## Epic 1:` or `## Epic 2:`
- Story IDs and titles from patterns like `### Story 1.1: User Authentication`
- Convert story format from `Epic.Story: Title` to kebab-case key: `epic-story-title`

**Story ID Conversion Rules:**

- Original: `### Story 1.1: User Authentication`
- Replace period with dash: `1-1`
- Convert title to kebab-case: `user-authentication`
- Final key: `1-1-user-authentication`

<action>Build complete inventory of all epics and stories from all epic files</action>
</step>

<step n="2" goal="Build the issue and spec inventory">
<action>For each epic found, plan these files in this order:</action>

1. **Epic issue** - Key: `epic-{num}`, an issue file `.nexus/issues/epic-{num}.md` (one board card, `epic` field left unset)
2. **Story specs** - Key: `{epic}-{story}-{title}`, a spec file `.nexus/specs/<ISSUE-KEY>/{epic}-{story}-{title}.md` grouped under the issue that carries this epic's work
3. **Retrospective spec** - Key: `epic-{num}-retro`, absent until the retrospective workflow runs; its existence is the record that the retro is done

**Example inventory:**

```
issues/epic-1.md              (the epic's board card)
specs/epic-1/1-1-user-authentication.md
specs/epic-1/1-2-account-management.md
specs/epic-1/epic-1-retro.md  (only after retrospective runs)
```

<note>An epic maps to one issue (one board card). Its stories map to specs under that issue. The spec key keeps the old `epic-story-title` kebab shape, so the conversion rules in Step 1 apply unchanged.</note>
</step>

<step n="3" goal="Detect which specs already have files">
<action>For each planned spec, detect whether its file already exists:</action>

**Spec file detection:**

- Check: `.nexus/specs/<ISSUE-KEY>/{spec-key}.md` (e.g., `specs/epic-1/1-1-user-authentication.md`)
- If it exists → leave it as-is; do not overwrite an authored spec

**Preservation rule:**

- READ `{board}` for the current column of each issue and the `done` flag of each spec; never write the board
- Never regress an authored spec: if a spec file exists with tasks checked off, preserve it
- The app owns column moves; this workflow only lands the issue and spec files that are missing

**Column Flow Reference (owned by the app, shown for context):**

- Columns: `backlog` → `planning` → `specs` → `dev` → `tests` → `review` → `done`
- A spec carries `done: true|false`; the app moves the issue as its specs complete
  </step>

<step n="4" goal="Write the issue and spec files">
<action>Create or update the issue and spec files, following the shapes in `{schema}` (`types.ts`: `Issue`, `Spec`):</action>

**Issue file (`.nexus/issues/<ISSUE-KEY>.md`):**

- Frontmatter: `key`, `title`, `column` (default `backlog`), `origin: full`, optional `epic`, `feature`, `labels`, `specs` (the ordered spec keys), `context` (prose), `criteria` (list), `comments`
- `key`, `title`, `column` and `origin` are REQUIRED: without all four the app REFUSES the issue whole and the card never reaches the board
- `foundIn`: when you author an issue because work on ANOTHER issue exposed it, set `foundIn` to that issue's key. It is what links the new card back to the one it came out of; omitted, the trail is lost and the issue looks like it arrived from nowhere
- Body `## Context` and `## Acceptance Criteria` are generated from the frontmatter
- Only author `context` and `criteria` when the epic file supplies them; leave placeholders otherwise for the author to fill

**Spec file (`.nexus/specs/<ISSUE-KEY>/<spec-key>.md`):**

- Frontmatter: `key`, `title`, `issue: <ISSUE-KEY>`, `done: false`, `story` (prose), `criteria` (list), `tasks` (each `id`, `text`, `done: false`), `links`
- Body `## Story`, `## Acceptance Criteria`, `## Tasks / Subtasks` are generated from the frontmatter

<action>Write each missing issue file to `.nexus/issues/` and each missing spec file to `.nexus/specs/<ISSUE-KEY>/`</action>
<action>List the ordered spec keys in each issue's `specs` field so the board and workflows share one order</action>
<critical>Never write `.nexus/board.yaml`: the app is the board's only writer and adds or moves cards in reaction to the issue and spec files.</critical>
<action>Ensure specs are ordered within each issue: story 1, story 2, ... in epic order</action>
</step>

<step n="5" goal="Validate and report">
<action>Perform validation checks:</action>

- [ ] Every epic in epic files has an issue file under `.nexus/issues/`
- [ ] Every story in epic files has a spec file under `.nexus/specs/<ISSUE-KEY>/`
- [ ] Every issue's `specs` list names exactly the spec files that exist for it
- [ ] No spec files that don't correspond to a story in the epic files
- [ ] Every issue and spec matches the shapes in `{schema}`
- [ ] Each file is valid frontmatter + generated body

<action>Count totals:</action>

- Total epics (issues): {{epic_count}}
- Total stories (specs): {{story_count}}
- Issues already in progress on the board: {{in_progress_count}}
- Specs done: {{done_count}}

<action>Display completion summary to {user_name} in {communication_language}:</action>

**Issues and Specs Laid Out Successfully**

- **Issues Folder:** .nexus/issues/
- **Specs Folder:** .nexus/specs/
- **Total Epics (issues):** {{epic_count}}
- **Total Stories (specs):** {{story_count}}
- **Issues In Progress:** {{in_progress_count}}
- **Specs Completed:** {{done_count}}

**Next Steps:**

1. Review the issue files in .nexus/issues/ and the spec files in .nexus/specs/
2. The app reflects them on the board (it is the board's only writer)
3. Agents update spec tasks and issue comments as they work; the board follows
4. Re-run this workflow to lay out any newly added stories

</step>

</workflow>

## Additional Documentation

### Board Columns (owned by the app)

The board (`.nexus/board.yaml`) has one writer: the app. Sprint planning READS it and
writes the issue and spec files; the app moves cards in reaction. The columns are:

```
backlog → planning → specs → dev → tests → review → done
```

- **backlog**: Issue exists, no work started
- **planning / specs**: Earlier method phases for the issue
- **dev**: A spec is being implemented
- **review**: A spec is ready for code review (via the Dev's code-review workflow)
- **done**: All of the issue's specs are done

**Spec completion:** A spec carries `done: true|false`. As specs complete, the app advances
the issue's column. The retrospective is recorded by its saved document
(`.nexus/specs/epic-<n>/epic-<n>-retro.md`) plus a comment on the epic's issue.

### Guidelines

1. **Issue Activation**: The app advances an issue's column when work starts on its first spec
2. **Sequential Default**: Specs are typically worked in order, but parallel work is supported
3. **Parallel Work Supported**: Multiple specs can be in `dev` if team capacity allows
4. **Review Before Done**: Specs should pass through `review` before `done`
5. **Learning Transfer**: SM typically authors the next spec after the previous one is `done` to incorporate learnings
