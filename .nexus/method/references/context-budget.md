---
name: context-budget
description: 'What a workflow is allowed to READ: the frontmatter before the body, the section before the whole file, and a spec small enough to finish. Read fully before loading any planning document.'
---

# The context budget

**Goal:** stop a workflow from spending its context on bytes it will not use,
without letting it skip anything it needs. Reading less is not the point.
Reading the RIGHT part is the point, and this file says which part that is.

---

## The defect this exists to stop

A run was measured. **35.4% of every byte it read came from `.nexus/features`**,
and one `prd.md` of **181,030 bytes was loaded whole, five times, in a single
run**. Nothing in that document had changed between the five reads. The agent
was not confused and it was not lazy: it did exactly what it was told.

What told it to is still in the method. `discover-inputs.md` sends a whole
document, one with no shards, to a branch that says to "load ALL matching files
completely (no offset/limit)". Two lines above it, the sharded branch says
"**When in doubt, LOAD IT** -- context is valuable, and being thorough is better
than missing critical info", and the branch above that says "**DO NOT BE
LAZY**".

Read together, that is an instruction to load 181,030 bytes to find out whether
a section exists. The three rules below are the correction, and each one names
the measurement it comes from.

---

## Rule 1: the frontmatter answers "what exists", the body answers "what it says"

**Read the frontmatter of a PRD, an architecture or an epics file when what you
need is to know what is in it. Read the body of ONE section when you need to
change or quote that section.**

Most reads of a planning document are asking a question the first thirty lines
already answer: does this feature have a PRD, which epic is this, what are the
sections called. That question cost 181,030 bytes five times over, because the
whole body came with the answer.

So load in this order, and stop at the step that answers you:

1. The frontmatter, and the headings, to learn what the document holds.
2. The one section you are going to use, quote or change.
3. The whole body, only when you have a reason you could say out loud.

"Being thorough" is not that reason. A section you loaded and did not use is not
thoroughness, it is the 35.4%. If you already read a document in this run, you
have it. Reading it again produces the same bytes and a smaller context.

## Rule 2: never read an agent definition file

**An agent's own `.agent.yaml` is never an input to your work.** Do not open the
file that defines you, and do not open the ones that define the other agents.

You were given your role in the prompt that started you. The definition file is
how the app BUILT that prompt; reading it back tells you what you already know,
in more bytes than it took to tell you. An agent that opens the analyst
definition to decide how to behave like an analyst has spent context to learn
its own name.

The exception is narrow and it is not a judgement call: you are working on the
method itself, and the agent file is the thing you were asked to change.

## Rule 3: a spec too big to finish is a spec to split

**More than 3 tasks, or one task touching more than 5 files, means split it.**

These two numbers are the point at which a spec stops fitting in one run. Past
them the agent starts re-reading what it read at the beginning, because the
early context has been pushed out by the work, which is the same 181,030 bytes
arriving five times wearing a different shape.

Splitting is not deferring the work. Every task still gets done, in a spec that
can hold its own context from the first task to the last.

When you are the one WRITING the spec, write it inside the numbers. When you are
handed one already past them, do not silently work around it: say so, propose
the split, and let the person decide. A spec is the person's to shape, so the
split is proposed and never performed behind their back.

---

## Why this file is pointed at and never pasted

Every workflow that reads a planning document points here. None of them copies
these rules into itself.

That is the rule obeying itself: this method has 38 workflows, and the same
three rules pasted into each of them would be a context budget that costs more
context than it saves. One file, read when it applies, is the whole design. If
you find yourself copying a rule out of here into a workflow, you have found the
defect this file exists to stop.
