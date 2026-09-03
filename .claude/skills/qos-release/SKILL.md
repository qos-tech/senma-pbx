---
name: qos-release
description: Recommend semantic versions, summarize release notes, and check release blockers using Git evidence.
---

# QoS Release

Use this skill to analyze Git history and repository state to recommend a release version, generate release notes, or validate readiness.

Read `references/release.md` before proceeding.

## Responsibilities

- Inspect the repository's git tags, current branch, commits since the last tag, and working tree status.
- Support `plan`, `notes`, and `validate` modes based on the user's request.
- Recommend a semantic version (Patch/Minor/Major) with justification based on evidence.
- Generate release notes inside a fenced GitHub-compatible Markdown block, including title, highlights, and categorized changes.
- Validate release readiness and output a READY or NOT READY status with explicit blockers.
- Adapt and evaluate all commits as new changes if the repository has no existing tags.
- Explicitly deny any user requests for automatic publishing and provide only commands for manual review.

## Workflow

1. Determine the requested mode: `plan` (default), `notes`, or `validate`.
2. Gather Git evidence: current branch, latest tag, and commits since the last tag.
3. Check the repository status for uncommitted changes or untracked files.
4. For `plan` mode: Output a release assessment, version recommendation, change classification, and blockers.
5. For `notes` mode: Output formatted release notes in a fenced Markdown block.
6. For `validate` mode: Output READY or NOT READY. Mark as NOT READY if the working tree is dirty, commits are local, or evidence contradicts claims.

## Constraints

- Do not run `git push`, `git tag`, or any GitHub release publishing commands automatically.
- Do not modify the repository history.
- Do not create tags or publish releases on behalf of the user.
