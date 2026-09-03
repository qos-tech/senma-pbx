---
name: 'step-01-understand'
description: 'Analyze the requirement delta between current state and what user wants to build'

templateFile: '../tech-spec-template.md'
wipFile: '{project-root}/.nexus/specs/{active_issue}/tech-spec-wip.md'
---

# Step 1: Analyze Requirement Delta

**Progress: Step 1 of 4** - Next: Deep Investigation

## RULES:

- MUST NOT skip steps.
- MUST NOT optimize sequence.
- MUST follow exact instructions.
- MUST NOT look ahead to future steps.
- ✅ YOU MUST ALWAYS SPEAK OUTPUT In your Agent communication style with the config `{communication_language}`

## CONTEXT:

- Variables from `workflow.md` are available in memory.
- Focus: Define the technical requirement delta and scope.
- Investigation: Perform surface-level code scans ONLY to verify the delta. Reserve deep dives into implementation consequences for Step 2.
- Objective: Establish a verifiable delta between current state and target state.

## SEQUENCE OF INSTRUCTIONS

### 0. Check for Work in Progress

a) **Before anything else, check if `{wipFile}` exists:**

b) **IF WIP FILE EXISTS:**

1. Read the frontmatter and extract: `title`, `slug`, `stepsCompleted`
2. Calculate progress: `lastStep = max(stepsCompleted)`
3. Present to user:

```
Hey {user_name}! Found a tech-spec in progress:

**{title}** - Step {lastStep} of 4 complete

Is this what you're here to continue?
**HOW to ask this menu:** Read fully and follow: {project-root}/.nexus/method/core/workflows/ask-the-person/workflow.md - show the section above BEFORE asking, offer these same choices through the asking channel this run provides, and keep the written menu as the fallback when that channel is unavailable.

[Y] Yes, pick up where I left off
[N] No, archive it and start something new
```

4. **HALT and wait for user selection.**

a) **Menu Handling:**

- **[Y] Continue existing:**
  - Jump directly to the appropriate step based on `stepsCompleted`:
    - `[1]` → Read fully and follow: `{project-root}/.nexus/method/workflows/evo-quick-flow/quick-spec/steps/step-02-investigate.md` (Step 2)
    - `[1, 2]` → Read fully and follow: `{project-root}/.nexus/method/workflows/evo-quick-flow/quick-spec/steps/step-03-generate.md` (Step 3)
    - `[1, 2, 3]` → Read fully and follow: `{project-root}/.nexus/method/workflows/evo-quick-flow/quick-spec/steps/step-04-review.md` (Step 4)
- **[N] Archive and start fresh:**
  - Rename `{wipFile}` to `{project-root}/.nexus/specs/{active_issue}/tech-spec-{slug}-archived-{date}.md`

### 1. Greet and Ask for Initial Request

a) **Greet the user briefly:**

"Hey {user_name}! What are we building today?"

b) **Get their initial description.** Don't ask detailed questions yet - just understand enough to know where to look.

### 2. Quick Orient Scan

a) **Before asking detailed questions, do a rapid scan to understand the landscape:**

b) **Check for existing context docs:**

- Check `{project-root}/.nexus/specs/{active_issue}/` and `{project-root}/.nexus/docs/` for planning documents (PRD, architecture, epics, research). Read `{project-root}/.nexus/board.yaml` for context on where this issue sits (read-only: the app is the board's only writer).
- Check for `**/project-context.md` - if it exists, skim for patterns and conventions
- Check for any existing specs related to user's request

c) **If user mentioned specific code/features, do a quick scan:**

- Search for relevant files/classes/functions they mentioned
- Skim the structure (don't deep-dive yet - that's Step 2)
- Note: tech stack, obvious patterns, file locations

d) **Build mental model:**

- What's the likely landscape for this feature?
- What's the likely scope based on what you found?
- What questions do you NOW have, informed by the code?

**This scan should take < 30 seconds. Just enough to ask smart questions.**

### 3. Ask Informed Questions

a) **Now ask clarifying questions - but make them INFORMED by what you found:**

Instead of generic questions like "What's the scope?", ask specific ones like:
- "`AuthService` handles validation in the controller, should the new field follow that pattern or move it to a dedicated validator?"
- "`NavigationSidebar` component uses local state for the 'collapsed' toggle, should we stick with that or move it to the global store?"
- "The epics doc mentions X - is this related?"

**Adapt to {user_skill_level}.** Technical users want technical questions. Non-technical users need translation.

b) **If no existing code is found:**

- Ask about intended architecture, patterns, constraints
- Ask what similar systems they'd like to emulate

### 4. Capture Core Understanding

a) **From the conversation, extract and confirm:**

- **Title**: A clear, concise name for this work
- **Slug**: URL-safe version of title (lowercase, hyphens, no spaces)
- **Problem Statement**: What problem are we solving?
- **Solution**: High-level approach (1-2 sentences)
- **In Scope**: What's included
- **Out of Scope**: What's explicitly NOT included

b) **Ask the user to confirm the captured understanding before proceeding.**

### 5. Initialize WIP File

a) **Create the tech-spec WIP file:**

1. Copy template from `{templateFile}`
2. Write to `{wipFile}`
3. Update frontmatter with captured values. This list REPLACES nothing: every
   other key the template declares stays exactly as the template wrote it.
   ```yaml
   ---
   key: 'tech-spec-{slug}'
   issue: '{active_issue}'
   title: '{title}'
   slug: '{slug}'
   created: '{date}'
   status: 'in-progress'
   stepsCompleted: [1]
   ---
   ```

   `slug`, `created`, `status` and `stepsCompleted` are WIP bookkeeping and
   belong to `tech-spec-wip.md` only. Step 4 drops them when it saves the final
   spec, because the app writes a spec back on every task tick and writes only
   the fields the template's frontmatter ends with: anything else is deleted
   silently. The stack, the files to modify and the patterns go in the BODY,
   where the app leaves them alone.

   `key` and `issue` are REQUIRED and the app REFUSES a spec without them: the
   card never links to the file and the work is invisible on the board. `key`
   MUST be the final file name without `.md`, which Step 4 writes as
   `tech-spec-{slug}.md`, so `key` is `tech-spec-{slug}` and not `{slug}`.
4. Fill in Overview section with Problem Statement, Solution, and Scope
5. Fill in Context for Development section with any technical preferences or constraints gathered during informed discovery.
6. Write the file

b) **Report to user:**

"Created: `{wipFile}`

**Captured:**

- Title: {title}
- Problem: {problem_statement_summary}
- Scope: {scope_summary}"

### 6. Present Checkpoint Menu

a) **Display menu:**

Display: "**Select:** [A] Advanced Elicitation [P] Party Mode [C] Continue to Deep Investigation (Step 2 of 4)"

b) **HALT and wait for user selection.**

#### Menu Handling Logic:

- IF A: Read fully and follow: `{advanced_elicitation}` with current tech-spec content, process enhanced insights, ask user "Accept improvements? (y/n)", if yes update WIP file then redisplay menu, if no keep original then redisplay menu
- IF P: Read fully and follow: `{party_mode_exec}` with current tech-spec content, process collaborative insights, ask user "Accept changes? (y/n)", if yes update WIP file then redisplay menu, if no keep original then redisplay menu
- IF C: Verify `{wipFile}` has `stepsCompleted: [1]`, then read fully and follow: `{project-root}/.nexus/method/workflows/evo-quick-flow/quick-spec/steps/step-02-investigate.md`
- IF Any other comments or queries: respond helpfully then redisplay menu

#### EXECUTION RULES:

- ALWAYS halt and wait for user input after presenting menu
- ONLY proceed to next step when user selects 'C'
- After A or P execution, return to this menu

---

## REQUIRED OUTPUTS:

- MUST initialize WIP file with captured metadata.

## VERIFICATION CHECKLIST:

- [ ] WIP check performed FIRST before any greeting.
- [ ] `{wipFile}` created with correct frontmatter, Overview, Context for Development, and `stepsCompleted: [1]`.
- [ ] User selected [C] to continue.
