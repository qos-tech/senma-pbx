---
name: lane-ready
description: 'Judge whether a lane is ready to leave: complete against its issue, nothing uncommitted, nothing out of scope in the diff. Use before merging an issue lane or when the user asks if it is done.'
main_config: '{project-root}/.nexus/project.yaml'
---

# Lane Ready Workflow

**Goal:** Say whether this lane's work is ready to leave, against the issue it
belongs to. Three questions, answered from evidence: is the work complete, is
anything uncommitted, is anything in the diff that does not belong to this issue.
You merge NOTHING and commit NOTHING.

---

## What you are given

The app writes and names in the prompt: the lane's diff against the main line,
the list of anything uncommitted in its checkout, and the path of the issue with
its acceptance criteria and its specs.

**The diff is the only evidence of what was built.** The issue is the only
evidence of what was asked for.

## What you must not do

- **Never run a git command**, and never merge, push, commit or delete. Leaving
  is a button with a confirmation, pressed by the person, after reading you.
- **Never mark a task or criterion done.** Judging that work exists and
  recording that it is accepted are different acts, and the second is not yours.
- **Never call it ready because the diff is large.** Volume is not completeness,
  and it is the most common way this judgement goes wrong.

## Steps

1. Read the issue, its acceptance criteria, and its specs.
2. Read the diff in full, then the uncommitted list.
3. Answer the three questions, each with its evidence:

```
Complete against the issue?
  <criterion by criterion: met / not met / cannot tell from the diff, and the
   file or hunk that shows it>

Anything uncommitted?
  <the files, or "nothing". Uncommitted work does not travel: it is what a
   lane loses when its checkout is removed>

Anything out of scope?
  <changes in the diff that no criterion asked for, named by file. Not an
   accusation: unrelated work in a lane is how a merge carries a surprise>
```

4. Finish with one line: **ready**, **not ready**, or **cannot tell**, and the
single most important reason.

5. "Cannot tell" is a real answer and often the right one. A criterion about
behaviour a diff cannot show (it is fast enough, it looks right) is not
verifiable from here, and claiming it is met is the failure this exists to stop.

## The rule that matters most

**Not ready is the cheap answer, and ready is the expensive one.** Saying a lane
is ready when a criterion was never built sends unfinished work onward with a
note saying it was checked. When the evidence is thin, say what is missing and
what would settle it.
