# Step 5: UX Pattern Analysis & Inspiration

## MANDATORY EXECUTION RULES (READ FIRST):

- 🛑 NEVER generate content without user input

- 📖 CRITICAL: ALWAYS read the complete step file before taking any action - partial understanding leads to incomplete decisions
- 🔄 CRITICAL: When loading next step with 'C', ensure the entire file is read and understood before proceeding
- ✅ ALWAYS treat this as collaborative discovery between UX facilitator and stakeholder
- 📋 YOU ARE A UX FACILITATOR, not a content generator
- 💬 FOCUS on analyzing existing UX patterns and extracting inspiration
- 🎯 COLLABORATIVE discovery, not assumption-based design
- ✅ YOU MUST ALWAYS SPEAK OUTPUT In your Agent communication style with the config `{communication_language}`

## EXECUTION PROTOCOLS:

- 🎯 Show your analysis before taking any action
- 💾 Write content directly to output file after generation
- 📖 Update output file frontmatter, adding this step to the end of the list of stepsCompleted
- ⚠️ Present A/P/C/R menu after writing to file

## COLLABORATION MENUS (A/P/C):

This step will generate content and present choices:

- **A (Advanced Elicitation)**: Use discovery protocols to develop deeper pattern insights
- **P ( Party Mode)**: Bring multiple perspectives to analyze UX patterns
- **C (Continue)**: Save the content to the document and proceed to next step

## PROTOCOL INTEGRATION:

- When 'A' selected: Read fully and follow: {project-root}/.nexus/method/core/workflows/advanced-elicitation/workflow.md
- When 'P' selected: Read fully and follow: {project-root}/.nexus/method/core/workflows/party-mode/workflow.md
- PROTOCOLS always return to this step's A/P/C menu
- User accepts/rejects protocol changes before proceeding

## CONTEXT BOUNDARIES:

- Current document and frontmatter from previous steps are available
- Emotional response goals from step 4 inform pattern analysis
- No additional data files needed for this step
- Focus on analyzing existing UX patterns and extracting lessons

## YOUR TASK:

Analyze inspiring products and UX patterns to inform design decisions for the current project.

## INSPIRATION ANALYSIS SEQUENCE:

### 0. Ask FIRST whether a reference already exists

Before asking what they admire elsewhere, ask what they already have. A team
with screens, a running product or a design file is not looking for
inspiration, they are looking for continuity, and inventing a direction beside
an existing product is the fastest way to produce a design nobody can use.

**HOW to ask this:** Read fully and follow:
{project-root}/.nexus/method/core/workflows/ask-the-person/workflow.md. This is
a real question through `AskUserQuestion`, with the written menu below as the
fallback for an engine that cannot ask.

Ask: "Before we look outward, is there something we should be designing FROM?"

Display: "**Select:** [E] Existing screens or a running product - design from
what is there [D] A design file or style guide - follow it [B] A brand only -
colours and logo, no screens [N] Nothing yet - this is a blank page"

- **IF E:** ask WHERE: a URL, a path, a repository, or screenshots they can
  point at. Then LOOK at what they name before going on. Record what you found
  under "Existing Reference" below, and treat every later step as extending
  that product rather than proposing a new one.
- **IF D:** ask for the file or its location, read it, and record which of its
  decisions are already fixed. Fixed decisions are not re-explored at step 8 or
  step 9.
- **IF B:** record the brand constraints and treat colour and type as given.
- **IF N:** say plainly that this is a blank page, and carry on with the
  inspiration questions below.

**What this answer binds:** it is not collected and forgotten. Steps 8, 9 and
12 each read it back. Where a reference exists, step 8 records the tokens the
reference ALREADY uses instead of proposing a palette, and step 9 draws
directions that extend it rather than alternatives that replace it.

### 1. Identify User's Favorite Apps

Start by gathering inspiration sources:
"Let's learn from products your users already love and use regularly.

**Inspiration Questions:**

- Name 2-3 apps your target users already love and USE frequently
- For each one, what do they do well from a UX perspective?
- What makes the experience compelling or delightful?
- What keeps users coming back to these apps?

Think about apps in your category or even unrelated products that have great UX."

### 2. Analyze UX Patterns and Principles

Break down what makes these apps successful:
"For each inspiring app, let's analyze their UX success:

**For [App Name]:**

- What core problem does it solve elegantly?
- What makes the onboarding experience effective?
- How do they handle navigation and information hierarchy?
- What are their most innovative or delightful interactions?
- What visual design choices support the user experience?
- How do they handle errors or edge cases?"

### 3. Extract Transferable Patterns

Identify patterns that could apply to your project:
"**Transferable UX Patterns:**
Looking across these inspiring apps, I see patterns we could adapt:

**Navigation Patterns:**

- [Pattern 1] - could work for your [specific use case]
- [Pattern 2] - might solve your [specific challenge]

**Interaction Patterns:**

- [Pattern 1] - excellent for [your user goal]
- [Pattern 2] - addresses [your user pain point]

**Visual Patterns:**

- [Pattern 1] - supports your [emotional goal]
- [Pattern 2] - aligns with your [platform requirements]

Which of these patterns resonate most for your product?"

### 4. Identify Anti-Patterns to Avoid

Surface what not to do based on analysis:
"**UX Anti-Patterns to Avoid:**
From analyzing both successes and failures in your space, here are patterns to avoid:

- [Anti-pattern 1] - users find this confusing/frustrating
- [Anti-pattern 2] - this creates unnecessary friction
- [Anti-pattern 3] - doesn't align with your [emotional goals]

Learning from others' mistakes is as important as learning from their successes."

### 5. Define Design Inspiration Strategy

Create a clear strategy for using this inspiration:
"**Design Inspiration Strategy:**

**What to Adopt:**

- [Specific pattern] - because it supports [your core experience]
- [Specific pattern] - because it aligns with [user needs]

**What to Adapt:**

- [Specific pattern] - modify for [your unique requirements]
- [Specific pattern] - simplify for [your user skill level]

**What to Avoid:**

- [Specific anti-pattern] - conflicts with [your goals]
- [Specific anti-pattern] - doesn't fit [your platform]

This strategy will guide our design decisions while keeping {{project_name}} unique."

### 6. Generate Inspiration Analysis Content

Prepare the content to append to the document:

#### Content Structure:

When saving to document, append these Level 2 and Level 3 sections:

```markdown
## UX Pattern Analysis & Inspiration

### Existing Reference

[What already exists to design FROM, from the question in section 0: screens, a
running product, a design file, a brand, or "nothing, this is a blank page".
Name WHERE it is, and which decisions it already fixes. Later steps read this
back, so "none" is written here explicitly rather than left absent.]

### Inspiring Products Analysis

[Analysis of inspiring products based on conversation]

### Transferable UX Patterns

[Transferable patterns identified based on conversation]

### Anti-Patterns to Avoid

[Anti-patterns to avoid based on conversation]

### Design Inspiration Strategy

[Strategy for using inspiration based on conversation]
```

### 7. Write to File and Present Menu

After generating the inspiration analysis content:

1. Append the content to `{docs_dir}/ux.md` using the structure from step 6
2. Update frontmatter: append step to end of stepsCompleted array

Then display menu:
**HOW to ask this menu:** Read fully and follow: {project-root}/.nexus/method/core/workflows/ask-the-person/workflow.md - show the section above BEFORE asking, offer these same choices through the asking channel this run provides, and keep the written menu as the fallback when that channel is unavailable.

Display: "**Select:** [A] Advanced Elicitation [P] Party Mode [C] Continue to Design System Choice (Step 6) [R] Rewrite this section"

### 8. Handle Menu Selection

- IF A: Read fully and follow: {project-root}/.nexus/method/core/workflows/advanced-elicitation/workflow.md, ask user "Accept improvements? (y/n)", if yes overwrite section in file, then redisplay menu
- IF P: Read fully and follow: {project-root}/.nexus/method/core/workflows/party-mode/workflow.md, ask user "Accept changes? (y/n)", if yes overwrite section in file, then redisplay menu
- IF C: Read fully and follow: `{project-root}/.nexus/method/workflows/2-plan-workflows/create-ux-design/steps/step-06-design-system.md`
- IF R: Rewrite the section from scratch based on user feedback, overwrite in file, then redisplay menu
- IF Any other: help user respond, then redisplay menu

## APPEND TO DOCUMENT:

After generation, immediately append the content directly to the document using the structure from step 6 (before presenting the menu).

## SUCCESS METRICS:

✅ Inspiring products identified and analyzed thoroughly
✅ UX patterns extracted and categorized effectively
✅ Transferable patterns identified for current project
✅ Anti-patterns identified to avoid common mistakes
✅ Clear design inspiration strategy established
✅ A/P/C menu presented and handled correctly
✅ Content properly appended to document when C selected

## FAILURE MODES:

❌ Not getting specific examples of inspiring products
❌ Surface-level analysis without deep pattern extraction
❌ Missing opportunities for pattern adaptation
❌ Not identifying relevant anti-patterns to avoid
❌ Strategy too generic or not actionable
❌ Not presenting A/P/C/R menu after writing content to file

❌ **CRITICAL**: Reading only partial step file - leads to incomplete understanding and poor decisions
❌ **CRITICAL**: Proceeding with 'C' without fully reading and understanding the next step file
❌ **CRITICAL**: Making decisions without complete understanding of step requirements and protocols

## NEXT STEP:

After user selects 'C' and content is saved to document, load `{project-root}/.nexus/method/workflows/2-plan-workflows/create-ux-design/steps/step-06-design-system.md` to choose the appropriate design system approach.

Remember: Write content to file immediately after generation. Do NOT proceed to step-06 until user explicitly selects 'C' from the menu.
