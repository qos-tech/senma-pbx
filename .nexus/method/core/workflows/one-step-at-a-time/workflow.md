---
name: one-step-at-a-time
description: 'How a multi-step workflow is PACED: one step file in memory, the step finished before the next is read, and a stop at every checkpoint. Read fully at the start of any workflow whose steps are separate files.'
---

# One step at a time

**Goal:** stop a multi-step workflow from being read ahead and answered in one
pass, without changing what any step asks or the order it asks it in.

---

## The defect this exists to stop

A pm agent was handed a PRD workflow of thirteen step files. It read all
thirteen at once, wrote 605 lines in a single pass, asked nothing, and then said
in its own summary that it had read the steps together rather than just in time
because the session was non-interactive and there was nobody to ask.

Nobody had told it that. It was watched the whole time. Every checkpoint the
thirteen steps carried went past unasked, and what came back was a document the
person had never been consulted on: not a draft he could steer, but a finished
thing to accept or throw away.

So the rule below is about the one judgement an agent must not make.

---

## Rule 1: a person is there, and that is not yours to decide

You are watched by someone who can answer you. This is a fact about how you were
started, not an inference for you to draw. Never conclude that a session is
non-interactive, unattended, headless or batch, and never take the quiet so far
as evidence that nobody is there. Not seeing a person is what running looks
like; it is not what being alone looks like.

## Rule 2: one step file in memory

Load the step you are on. Finish it. Only then read the next one. Do not read
ahead to see where the workflow is going, do not open several step files to plan
your writing, and do not build a to-do list out of steps you have not reached.
A step written to be answered before the next one is asked stops working the
moment you have already read them both.

## Rule 3: a checkpoint is a full stop

Where a step ends in a question or a menu, ask it and stop there. Ask through
`{project-root}/.nexus/method/core/workflows/ask-the-person/workflow.md`, which
is the one description of how to put a question on screen, and wait for the
answer before you go on. Printing the question and continuing past it is the
same as never asking.

**Which of those two you do is not yours to work out.** The prompt that started
you names the engine you are on and gives you one of them: follow the one you
were given. If you were told your engine cannot ask mid-run, that is not
permission to carry on. Print the menu with the question you would have asked,
say in one line that you are stopping for an answer, and end your turn. The
person answers in the conversation and you carry on from the reply.

## Rule 4: one pass is something the person asks for

Writing the whole document in one go, with no checkpoints, is a thing the person
can want. It is theirs to ask for, in their own words, in this conversation, and
it is never a shortcut you choose for them. Until they say it here, pace the
work and stop at every checkpoint the workflow has.

If they do ask, take it for the run they asked in and no further: say back what
you understood, write the document, and bring it to them whole.
