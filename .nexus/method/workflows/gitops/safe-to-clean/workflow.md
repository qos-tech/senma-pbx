---
name: branch-cleanup
description: 'Judge which branches are safe to clean up and which are not, with the reason stated per branch. Use when the user asks what can be deleted, what is safe to remove, or why a branch is still listed.'
main_config: '{project-root}/.nexus/project.yaml'
---

# Branch Cleanup Workflow

**Goal:** Say which branches are safe to remove and which are not, one line each,
with the criterion that decided it. You delete NOTHING. The person reads your
list and presses the button beside the branch, and the app does the removal with
a confirmation naming what would be lost.

---

## What you are given

The app writes the evidence before it starts you and names the file in the
prompt. It holds, per branch: its name, whether it has a checkout, how many
commits it carries that the main line does not, whether its checkout has
uncommitted files, and the issue it belongs to when its name carries one.

**That file is the only evidence.** It was read from the repository by the app,
which is the one thing here that runs git.

## What you must not do

- **Never run a git command.** Not `branch`, not `log`, not `status`, not
  `merge-base`. The app already read what you need. A second read from a
  different tree is how a claim comes to describe another repository's state.
- **Never delete, merge or push anything.** You produce words. Every removal is
  a button a person presses, with a confirmation that names the cost.
- **Never call a branch safe on a guess.** If the evidence does not settle it,
  say that, and say which fact would.

## Steps

1. Read the evidence file named in the prompt, in full.
2. Sort every branch into exactly one of three verdicts:

| verdict | the criterion, and it must hold exactly |
|---|---|
| **safe to remove** | carries no commit the main line lacks, and its checkout has nothing uncommitted (or it has no checkout) |
| **carries work** | carries commits the main line does not have, or has uncommitted files |
| **cannot tell** | the evidence does not settle it: say which fact is missing |

3. Write one line per branch, in this shape, so the list can be scanned:

```
<branch> — <verdict>: <the criterion, as a fact about this branch>
```

State the number. "safe to remove: 0 commits the main line lacks, no checkout"
is checkable; "looks fine" is not.

4. Put the branches that **carry work** first. A list that opens with what is
safe invites deleting the rest without reading, which is the accident this whole
skill exists to prevent.

5. End with one sentence: how many are safe, how many carry work, how many you
could not judge. Never a recommendation to delete them all at once.

## The rule that matters most

**A branch carrying commits nobody merged is work somebody did.** Being stale,
old, or named after a finished issue does not make it disposable, and none of
those is in the table above on purpose. If it carries commits, it carries work,
and the person decides.
