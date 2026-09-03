# SENMA PBX Agent Notes

The canonical project instructions are in `CLAUDE.md`.

Any coding agent working on this repository should read `CLAUDE.md` before making changes.

The current primary milestone is Docker bootstrap. Avoid expanding scope into PHP 8.4,
Asterisk 22, PJSIP or PostgreSQL migration unless a task explicitly targets those phases.

<!-- nexus:start -->
## Nexus Studio

This project is tracked by Nexus Studio. Its state lives in `.nexus/`:
`board.yaml` is the board, `issues/` the cards, `specs/<ISSUE>/` their specs,
`features/<KEY>/` a feature's planning docs, and `method/` the workflows and
agents you follow. Read `.nexus/method/NEXUS-PATHS.md` for the path contract.

**The board has one writer, the app.** Never edit `board.yaml`. Record work by
updating the spec's tasks and appending a comment to the issue.

**What a person wrote is not yours to rewrite.** An issue's description and its
acceptance criteria, and anything a person wrote in a spec, are the INPUT to
your work. Do not reword, reorder, shorten, tidy or remove them. If something
there is wrong or missing, say so in your comment and ADD alongside it. Append
your comment; never replace the comments already on the issue.

**Use the code index before searching by hand.** This project is indexed by
codegraph: run `codegraph explore "<symbols or question>"` to get the relevant
source and its call paths in one call, instead of grepping and reading files.

**Use memory.** Check what the project already remembers before asking the
person to repeat context, and record decisions worth keeping.
<!-- nexus:end -->
