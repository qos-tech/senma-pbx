---
name: explain-conflict
description: 'Explain a merge conflict: what each side changed, why they collide, and what choosing between them costs. Use when a merge stops with conflicts, or the user asks what a conflict means.'
main_config: '{project-root}/.nexus/project.yaml'
---

# Explain Conflict Workflow

**Goal:** Turn a set of conflict markers into an explanation a person can decide
from. What did each side change, why do the two collide, and what is lost by
taking one over the other. You resolve NOTHING and edit NOTHING.

---

## What you are given

The app writes the conflicted region of each file, markers included, and names
the file in the prompt. It also names the two sides: the branch being merged in,
and the branch being merged into.

**That file is the only evidence.** The app read it from the tree the merge is
happening in.

## What you must not do

- **Never run a git command**, and never `merge`, `rebase`, `checkout` or
  `reset`. The merge is in progress in a real tree; a command from you would
  change a state a person is standing in.
- **Never edit the conflicted file, or any file.** Removing markers is
  resolving, and resolving is the person's decision. Write your explanation to
  the path the prompt names and nothing else.
- **Never guess intent from a branch name.** What each side changed is in the
  diff. Why it was changed may not be knowable, and then you say so.

## Steps

1. Read the conflict file in full, including the markers.
2. For each conflicted region, write:

```
<file>:<the region, by what it contains rather than by line number>

  ours (<branch>):   <what this side does, in a sentence>
  theirs (<branch>): <what this side does, in a sentence>

  why they collide:  <the actual reason: same function, same key, one moved
                      what the other edited>
  what taking one costs: <what is lost by each choice, named>
```

3. **Say plainly when a conflict is textual rather than real**: two sides adding
different lines in one place collide in git and not in meaning. That is the most
common case and the one people waste the most time on.

4. **Say plainly when it is NOT safe to take either side whole**: when both
changed the same logic for different reasons, the answer is usually a third
version, and saying "take theirs" there loses work silently.

5. End with what you would ask the person, if anything is genuinely undecidable
from the text. A question is a better ending than a confident wrong answer.

## The rule that matters most

**Never say which side to take as if it were a fact.** You can say what each
costs; which cost is acceptable is a judgement about the product, and the person
holds it. A resolution recommended in a confident voice and taken without
reading is how one side's work disappears.
