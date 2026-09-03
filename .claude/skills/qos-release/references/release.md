# QoS Release Reference

This document provides detailed guidance for the `/qos-release` skill on evidence collection, semantic versioning rules, change classification, and readiness rules.

## Evidence Collection

Before planning a release or generating notes, gather the following Git evidence:
- **Current Branch**: Ensure context of where the release is being prepared (e.g., `git rev-parse --abbrev-ref HEAD`).
- **Latest Tag**: Identify the most recent release tag (e.g., `git describe --tags --abbrev=0`). If no tags exist in the repository, assume the next release will encompass all commits from the beginning of the repository.
- **Commits Since Last Tag**: Retrieve all commits between the latest tag and `HEAD` (e.g., `git log <latest_tag>..HEAD --oneline`). If no tags exist, use all commits (`git log --oneline`).
- **Working Tree Status**: Determine if there are uncommitted changes or untracked relevant files (`git status`).

## Semantic Versioning Rules

Use standard Semantic Versioning (SemVer - `MAJOR.MINOR.PATCH`) to recommend the next version based on the collected commits:

- **MAJOR version**: Must be incremented when there are incompatible API changes or breaking changes. Look for commits indicating breaking changes (e.g., `BREAKING CHANGE:` in the footer, or an exclamation mark like `feat!:` in conventional commits).
- **MINOR version**: Must be incremented when functionality is added in a backward-compatible manner. Look for new features (e.g., `feat:` prefix).
- **PATCH version**: Must be incremented when backward-compatible bug fixes are made. Look for bug fixes, chores, documentation updates, or minor tweaks (e.g., `fix:`, `chore:`, `docs:`).

## Change Classification

When generating release notes, classify the commits into clear, readable categories:

- **Features**: Commits that add new functionality or capabilities.
- **Bug Fixes**: Commits that resolve issues or bugs.
- **Documentation**: Commits that update README files, guides, or other documentation.
- **Chores & Maintenance**: Commits related to refactoring, dependency updates, CI/CD changes, or internal cleanups.

Highlight significant changes (especially breaking changes or major features) at the top of the notes.

## Readiness Rules

During validation mode, evaluate the repository state against these rules. A release is considered **NOT READY** if:

1. **Dirty Working Tree**: There are uncommitted changes or untracked files that are relevant to the project.
2. **Unpushed Commits**: There are local commits that have not been pushed to the remote tracking branch.
3. **Contradictory Evidence**: Claims made in documentation or commit messages contradict the actual state (e.g., claiming no breaking changes when breaking changes exist).

If none of the blockers above apply, the release state is **READY**.
