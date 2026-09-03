---
name: design-mock
description: 'Draw an HTML mock of a screen so a person can SEE it before it becomes code. Use when planning or a quick spec proposes a screen, a panel or a layout, and when the user asks for a mock, a mockup or "let me see it first".'
main_config: '{project-root}/.nexus/project.yaml'
---

# Design Mock Workflow

**Goal:** Draw ONE screen as a static HTML file, save it under `.nexus/assets/`,

**WHAT to read:** Read fully and follow: `{project-root}/.nexus/method/references/context-budget.md` before you load any planning document. The frontmatter before the body, the one section before the whole file, and a spec of more than 3 tasks is one to split.
and list it on the issue so the app can open it. A person then looks at it and
decides, before anybody writes the real component.

This exists because a mock changes decisions that prose does not. Two mocks
written on 2026-08-13 cut a set of charts that would have been drawn from
invented numbers, which no amount of describing them had done.

---

## The app is the only viewer: never open the file yourself

**Do not run `open`, `xdg-open`, `start`, a browser, or any command that
launches an application.** An agent did exactly that on 2026-08-14 and a mock
meant to be read inside the app opened in Chrome, outside everything the frame
below guarantees.

Writing the file and listing it on the issue IS the whole job. The app lists it
and a person clicks it. You never need to look at the rendered page to finish,
and there is no step here that asks you to.

For the same reason, **never write a task or an acceptance criterion that says
to open, preview or view the mock**: `.nexus/assets/...` renders in the app, so
a task saying "open it in the browser and check it" describes a workflow this
method does not have and cannot be ticked honestly.

---

## The one hard rule: a mock cannot run

The app renders your file in a frame that is allowed **nothing**: no script, no
network, no reach into the app. This is not a style preference, it is what makes
it safe to open a file an agent wrote.

- **No `<script>` anywhere.** The app REFUSES a file containing one, so a mock
  with a script is not shown half-working, it is not shown at all.
- **No `fetch`, no inline handlers (`onclick=`), no `javascript:` URLs.** They
  would not run, and writing them tells the reader something works when it does not.
- **Nothing loaded from the network:** no CDN stylesheet, no Google font, no
  remote image. They are blocked, and the mock renders without them.
- **Images:** inline SVG, or a `data:` URI. Nothing else arrives.

A static mock is still a mock. State it in markup instead of computing it: to
show a loading state and a loaded state, draw them as two blocks side by side.

### A link is not navigation here, and `href="#section"` DESTROYS the mock

Measured in Chromium on 2026-08-17, against the real panel. The file is shown
through `srcdoc`, so it has no URL of its own and a `#` link resolves against
the APP's address instead. Clicking one replaced the mock with a blank frame:
the drawing was gone, and only a reopen brought it back.

- **Never write `href="#anything"`,** no tab strip, no "back to top", no index
  that jumps to a section. `<base>` does not rescue it: `base-uri 'none'` in the
  policy blocks that too, measured the same day.
- **Never link to another artifact file.** Each one is opened from its own row.
- The only safe `href` is none. Draw a nav bar as styled text, not as links.

**So "navigable" here means LAID OUT, not clicked through.** Put the screens on
one page, one under another, each with a heading saying which screen it is and
what leads to it. A person scrolls and sees the whole flow at once, which is
what makes a set of screens judgeable in a glance.

---

## Steps

1. **Find the project's design tokens, and read the real values.** Do not
   invent a palette. Look, in this order, for:
   - `src/styles/tokens.css`
   - any file matching `tokens.css`, `theme.css`, `variables.css`, `globals.css`
   - `tailwind.config.*`, or a `@theme` block in a CSS file
   - a design document under `.nexus/features/*/ux.md`

2. **If the project has NO tokens file, say so plainly** in the comment you
   write on the issue: "this project defines no design tokens, so the mock uses
   neutral greys and is about layout, not colour." Then use plain neutral CSS.
   Inventing a brand palette produces a mock that argues for colours nobody chose.

3. **Copy the token values into the mock as a `:root` block.** The mock is a
   single self-contained file, so it cannot import the project's CSS. Copy the
   real values, and use `var(--token)` everywhere below. Never write a hex code
   in the markup: if you need a colour that is not a token, you have found
   something to ask about, not something to pick.

4. **Draw ONE screen**, when the question is about one screen. A mock that
   covers three unrelated screens gets discussed as three things and decided as
   none.

   **The exception is a FLOW**, which is what the UX design workflow asks for: a
   sequence a person walks through is one decision, and splitting it across
   files is what makes the sequence impossible to judge. Then draw every screen
   of the flow on ONE page, in order, each under a heading naming it and what
   leads to it. Still one file, still no links between them.

5. **Save it** to `.nexus/assets/<short-name>.html`. Nothing outside that folder
   is opened by the app.

6. **List it where the work lives**, leaving every existing field and every
   existing comment exactly as they are. The same three keys either way:

```yaml
artifacts:
  - name: The source control view
    rel: .nexus/assets/source-control.html
    producedBy: specs
```

- **Working on an ISSUE:** add it to the issue's frontmatter.
- **Working on a feature's planning doc** (`features/<key>/ux.md`, `prd.md`):
  add it to THAT document's frontmatter, beside `stepsCompleted`. The document
  that drew the screen is the page a person has open when they want to see it.
  Omit `producedBy` there: it names a board column, and a planning doc is in
  none.

`name` is what a person reads in the list, so name the SCREEN, not the file.
`rel` must be the `.nexus/assets/...` path, `.html`, and nothing else parses.
`producedBy` is the column you are running in (`planning`, `specs`, `dev`).

7. **Say in your comment on the issue what the mock shows and what decision it
   is asking for.** A mock with no question attached gets admired and not used.

---

## The design vocabulary, when the project is Nexus Studio

Read `apps/studio/src/styles/tokens.css` for the values. The names below are
that file's, and using them is what makes a mock look like the product rather
than like a generic dashboard.

| what | tokens |
|---|---|
| surfaces, deepest to highest | `--bg-0` `--bg-1` `--bg-2` `--bg-3` `--bg-4` |
| borders | `--line` visible, `--line-soft` quiet |
| text | `--ink-1` primary, `--ink-2` secondary, `--ink-3` label and placeholder |
| meaning | `--evo` green, `--iris` violet, `--amber`, `--coral` |
| type | `--display` headings, `--body` prose, `--mono` paths and code |
| space | `--s1` to `--s12`, a scale of 4, nothing outside it |
| radius | `--r-xs` to `--r-xl`, `--r-full` |

**Green is never a reading colour.** Body text is `--ink-1` or `--ink-2`.

The component shapes to draw with, all real components in
`apps/studio/src/components/ui/`:

- **Card** with **CardTitle**: the box a section lives in.
- **Kpi**: one number with its label. Use it only for a number you actually
  have. A KPI drawn from a number nobody measured is the exact failure a mock is
  supposed to prevent.
- **Tag**: states a FIXED fact, no dot. `blocked`, `3 files`, a feature name.
- **Pill**: states a CHANGING state, with a dot. Running, waiting, failed.
- **ApprovalBlock**: the amber block that asks a person to approve something.
- **EmptyState**: what a list says when it has nothing in it. Draw this too:
  the empty case is where most screens are worst and it is rarely mocked.

The Tag and Pill distinction is the one most often got wrong: if what it says
can change while you watch it, it is a Pill and it has a dot.

---

## What good looks like

- It is DRAWN to fit one screen at 1280 by 800, the app's own window size. That
  is a constraint on how you lay it out, not a check to go and perform: judge it
  from the markup you are writing, never by opening the file.
- It shows the state a person will actually be in most of the time, not the
  demo state where every field is full.
- It has the empty case, or the error case, somewhere on it.
- Every colour is a `var(--token)`. Search your own file for `#` before saving.
