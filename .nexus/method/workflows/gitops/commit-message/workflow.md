---
name: commit-message
description: 'Write a commit message from the selected files and their diff. Use when the user says "generate a commit message" or presses the commit message button on the git screen.'
main_config: '{project-root}/.nexus/project.yaml'
---

# Commit Message Workflow

**Goal:** Read the diff the app prepared, and write ONE commit message describing
what that diff actually does. The message is a DRAFT: a person reads it, edits it
and presses commit. You never commit anything.

---

## What you are given

The app writes two files before it starts you, and names both in the prompt:

| file | what it holds |
|---|---|
| `selection.txt` | the files the person ticked, one path per line |
| `selection.patch` | the diff of exactly those files, and nothing else |

The patch is the ONLY evidence of what changed. It was read from the checkout the
work happened in, so it describes this branch and no other.

## What you must not do

- **Never run a git command.** Not `add`, not `commit`, not `push`, not `status`,
  not `diff`. The app already read what you need, and a second read from a
  different tree is how a message comes to describe another branch's work.
- **Never write any file but the draft.** The implementation is not yours to
  touch here.
- **Never describe a change that is not in the patch.** If the patch is empty or
  says nothing you can characterise, say so in the draft rather than guessing
  from the file names. A message describing work nobody can see is worse than no
  message, because it is committed and then believed.

## Steps

1. Read `selection.txt`, then read `selection.patch` in full.
2. If the patch is empty, write exactly this as the draft and stop:
   `The diff of the selected files could not be read, so nothing here describes them.`
3. Work out what the change DOES, not which files it touched. A list of file
   names is something the person can already see on screen; the reason the change
   exists is what they cannot.
4. Write the draft to the path the prompt names, in this shape:

```
<one line, imperative, at most 72 characters>

<a blank line, then one short paragraph saying why, when the subject
does not already say it. Omit the paragraph entirely for a small change.>
```

5. Say in one sentence what you wrote and that it is waiting for them to edit.

## The subject line

- Imperative and present tense: `Fix the lane diff reading the wrong tree`, never
  `Fixed` and never `Fixes`.
- No trailing full stop, no emoji, no prefix the project does not already use.
- Describe the effect, not the mechanism, whenever the two differ.
- English, always, whatever language the conversation is in.

If the project's recent history follows a convention you can see in the log the
app quoted, follow it instead of this shape. A message that does not match the
history around it is a message somebody has to rewrite.
