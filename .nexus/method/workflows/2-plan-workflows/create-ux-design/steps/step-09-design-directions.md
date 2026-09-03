# Step 9: Design Direction Mockups

## MANDATORY EXECUTION RULES (READ FIRST):

- 🛑 NEVER generate content without user input

- 📖 CRITICAL: ALWAYS read the complete step file before taking any action - partial understanding leads to incomplete decisions
- 🔄 CRITICAL: When loading next step with 'C', ensure the entire file is read and understood before proceeding
- ✅ ALWAYS treat this as collaborative discovery between UX facilitator and stakeholder
- 📋 YOU ARE A UX FACILITATOR, not a content generator
- 💬 FOCUS on generating and evaluating design direction variations
- 🎯 COLLABORATIVE exploration, not assumption-based design
- ✅ YOU MUST ALWAYS SPEAK OUTPUT In your Agent communication style with the config `{communication_language}`

## EXECUTION PROTOCOLS:

- 🎯 Show your analysis before taking any action
- 💾 Write content directly to output file after generation
- 💾 Draw the directions as ONE HTML file under `.nexus/assets/`, by following
  the design-mock workflow, and LIST it in the document's `artifacts:`
- 📖 Update output file frontmatter, adding this step to the end of the list of stepsCompleted.
- ⚠️ Present A/P/C/R menu after writing to file

## COLLABORATION MENUS (A/P/C/R):

This step will generate content and present choices:

- **A (Advanced Elicitation)**: Use discovery protocols to develop deeper design insights
- **P (Party Mode)**: Bring multiple perspectives to evaluate design directions
- **C (Continue)**: Accept the content and proceed to next step
- **R (Rewrite)**: Rewrite this section from scratch based on user feedback

## PROTOCOL INTEGRATION:

- When 'A' selected: Read fully and follow: {project-root}/.nexus/method/core/workflows/advanced-elicitation/workflow.md
- When 'P' selected: Read fully and follow: {project-root}/.nexus/method/core/workflows/party-mode/workflow.md
- PROTOCOLS always return to this step's A/P/C/R menu
- User accepts/rejects protocol changes before proceeding

## CONTEXT BOUNDARIES:

- Current document and frontmatter from previous steps are available
- Visual foundation from step 8 provides design tokens
- Core experience from step 7 informs layout and interaction design
- Focus on exploring different visual design directions

## YOUR TASK:

Generate comprehensive design direction mockups showing different visual approaches for the product.

## DESIGN DIRECTIONS SEQUENCE:

### 1. Generate Design Direction Variations

**Read "Existing Reference" from the document first** (step 5 wrote it). Where
a reference exists, these are not alternatives to it: they are ways of
EXTENDING it, and a direction that throws away a running product's look is a
direction the person cannot take. Say which parts are fixed by the reference
and are therefore the same in every variation. Where it says nothing exists,
explore freely.

Create diverse visual explorations:
"I'll generate 6-8 different design direction variations exploring:

- Different layout approaches and information hierarchy
- Various interaction patterns and visual weights
- Alternative color applications from our foundation
- Different density and spacing approaches
- Various navigation and component arrangements

Each mockup will show a complete vision for {{project_name}} with all our design decisions applied."

### 2. Create the HTML Design Direction Showcase

**Draw it by running the mock skill, not by inventing a file of your own.**
Read fully and follow:
{project-root}/.nexus/method/workflows/design-mock/workflow.md. It carries the
rules the app enforces (no script, no network, tokens rather than invented
colour) and the anchor trap that silently destroys a mock.

Two things it fixes that this step used to get wrong:

- **The file goes under `.nexus/assets/`, not `.nexus/docs/`.** The app opens
  that one folder and no other. A showcase written to `docs/` is a file on disk
  that no screen can ever show, which is the same as not drawing it.
- **It must be LISTED**, in the `artifacts:` of this workflow's own output
  document (`ux.md`), or it stays invisible however good it is.

Draw the directions as ONE page, each direction under a heading, one below
another so they can be compared by scrolling. Say plainly, in your message:

"I've drawn the design directions at `.nexus/assets/ux-design-directions.html`
and listed them on this document, so you can open them from this page.

**What you'll see:**

- 6-8 full-screen mockup variations, laid out one under another
- Hover states, which are CSS and do work
- Complete UI examples with real content

There are no links between them and no clicking through: a mock is shown with
scripting off, so it is a drawing you scroll, not a prototype you operate."

### 3. Present Design Exploration Framework

Guide evaluation criteria:
"As you explore the design directions, look for:

✅ **Layout Intuitiveness** - Which information hierarchy matches your priorities?
✅ **Interaction Style** - Which interaction style fits your core experience?
✅ **Visual Weight** - Which visual density feels right for your brand?
✅ **Navigation Approach** - Which navigation pattern matches user expectations?
✅ **Component Usage** - How well do the components support your user journeys?
✅ **Brand Alignment** - Which direction best supports your emotional goals?

Take your time exploring - this is a crucial decision that will guide all our design work!"

### 4. Facilitate Design Direction Selection

Help user choose or combine elements:
"After exploring all the design directions:

**Which approach resonates most with you?**

- Pick a favorite direction as-is
- Combine elements from multiple directions
- Request modifications to any direction
- Use one direction as a base and iterate

**Tell me:**

- Which layout feels most intuitive for your users?
- Which visual weight matches your brand personality?
- Which interaction style supports your core experience?
- Are there elements from different directions you'd like to combine?"

### 5. Document Design Direction Decision

Capture the chosen approach:
"Based on your exploration, I'm understanding your design direction preference:

**Chosen Direction:** [Direction number or combination]
**Key Elements:** [Specific elements you liked]
**Modifications Needed:** [Any changes requested]
**Rationale:** [Why this direction works for your product]

This will become our design foundation moving forward. Are we ready to lock this in, or do you want to explore variations?"

### 6. Generate Design Direction Content and Write to File

Generate the content and immediately append to the document:

#### Content Structure:

After generation, immediately append these Level 2 and Level 3 sections to the output file (before presenting the menu):

```markdown
## Design Direction Decision

### Design Directions Explored

[Summary of design directions explored based on conversation]

### Chosen Direction

[Chosen design direction based on conversation]

### Design Rationale

[Rationale for design direction choice based on conversation]

### Implementation Approach

[Implementation approach based on chosen direction]
```

### 7. Present Menu

Content has been written to the document. Present choices:
**HOW to ask this menu:** Read fully and follow: {project-root}/.nexus/method/core/workflows/ask-the-person/workflow.md - show the section above BEFORE asking, offer these same choices through the asking channel this run provides, and keep the written menu as the fallback when that channel is unavailable.

"I've documented our design direction decision for {{project_name}} and written it to the document. This visual approach will guide all our detailed design work.

**What would you like to do?**
[A] Advanced Elicitation - Let's refine our design direction
[P] Party Mode - Bring different perspectives on visual choices
[C] Continue - Move to user journey flows
[R] Rewrite - Rewrite this section from scratch based on feedback

### 8. Handle Menu Selection

#### If 'A' (Advanced Elicitation):

- Read fully and follow: {project-root}/.nexus/method/core/workflows/advanced-elicitation/workflow.md with the current design direction content
- Process the enhanced design insights that come back
- Ask user: "Accept these improvements to the design direction? (y/n)"
- If yes: Update content with improvements and overwrite in file, then return to A/P/C/R menu
- If no: Keep original content, then return to A/P/C/R menu

#### If 'P' (Party Mode):

- Read fully and follow: {project-root}/.nexus/method/core/workflows/party-mode/workflow.md with the current design direction
- Process the collaborative design insights that come back
- Ask user: "Accept these changes to the design direction? (y/n)"
- If yes: Update content with improvements and overwrite in file, then return to A/P/C/R menu
- If no: Keep original content, then return to A/P/C/R menu

#### If 'C' (Continue):

- Update frontmatter: append step to end of stepsCompleted array
- Load `{project-root}/.nexus/method/workflows/2-plan-workflows/create-ux-design/steps/step-10-user-journeys.md`

#### If 'R' (Rewrite):

- Rewrite the section from scratch based on user feedback, overwrite in file, then redisplay menu

## APPEND TO DOCUMENT:

After generation, immediately append the content to the document using the structure from step 6 (before presenting the menu).

## SUCCESS METRICS:

✅ Multiple design direction variations generated
✅ HTML showcase saved under `.nexus/assets/` and LISTED in the document's
   `artifacts:`, so the person can open it from this page
✅ Design evaluation criteria clearly established
✅ User able to explore and compare directions effectively
✅ Design direction decision made with clear rationale
✅ Content written to document immediately after generation
✅ A/P/C/R menu presented and handled correctly

## FAILURE MODES:

❌ Not creating enough variation in design directions
❌ Design directions not aligned with established foundation
❌ Writing the showcase anywhere but `.nexus/assets/`, or not listing it: a file
   no screen can open is work the person never sees
❌ Promising clicking-through, tabs or "comparison tools": scripting is off, and
   an `#anchor` link destroys the mock rather than navigating it
❌ Not providing clear evaluation criteria
❌ Rushing decision without thorough exploration
❌ Not presenting A/P/C/R menu after writing content to file

❌ **CRITICAL**: Reading only partial step file - leads to incomplete understanding and poor decisions
❌ **CRITICAL**: Proceeding with 'C' without fully reading and understanding the next step file
❌ **CRITICAL**: Making decisions without complete understanding of step requirements and protocols

## NEXT STEP:

Write content to file immediately after generation. Load `{project-root}/.nexus/method/workflows/2-plan-workflows/create-ux-design/steps/step-10-user-journeys.md` to design user journey flows.

Remember: Write content to file immediately after generation. Do NOT proceed to step-10 until user explicitly selects 'C' from the menu.
