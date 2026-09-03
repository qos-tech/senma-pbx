---
name: read-history
description: 'Read a range of history and say what actually happened in it. Use for a release note, a catch-up after time away, or when the user asks what changed between two points.'
main_config: '{project-root}/.nexus/project.yaml'
---

# Read History Workflow

**Goal:** Turn a list of commits into an account of what happened: what the work
was, in the order it makes sense to read, not in the order it was committed.

---

## What you are given

The app writes the range it read and names the file in the prompt: the commits,
with their subjects, authors and dates, and the range they came from.

**That file is the only evidence, and its range is the whole claim.** Say the
range back in your first line. An account that does not name what it covers gets
read as covering everything.

## What you must not do

- **Never run a git command.** Not `log`, not `show`, not `diff`. The app read
  the range; reading it again from a different tree is how a summary comes to
  describe another branch.
- **Never describe a change that is not in the evidence.** If the subjects are
  too thin to say what happened, say that: "these 14 commits say only 'wip', so
  what they did cannot be read from the history" is a true and useful answer.
- **Never write any file but your own output.**

## Steps

1. Read the file in full. Note the range and the commit count.
2. Group the commits by what they DID, not by author and not by day. A reader
   wants to know what changed about the product.
3. Write, in this order:

```
<the range, and how many commits it holds>

<the two or three things that actually happened, one short paragraph each>

<anything a reader would want warned about: a revert, a migration, a
 dependency change, a rename that will break their branch>
```

4. **Name the evidence for each claim**: the commit's short sha, so anything you
say can be checked. A claim with no sha behind it is an impression.
5. If asked for a release note, write it for the person who USES the product,
not the person who wrote it: "invoices export as PDF" rather than "add
`PdfExporter`". Keep the internal wording only where nothing user-facing changed.

## The rule that matters most

**A commit subject is a claim, not a fact.** It says what its author believed
they did. Where subjects contradict each other or a later commit reverts an
earlier one, report what the sequence shows rather than repeating both claims as
if both landed.
