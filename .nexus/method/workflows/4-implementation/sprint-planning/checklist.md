# Sprint Planning Validation Checklist

## Core Validation

### Complete Coverage Check

- [ ] Every epic found in epic\*.md files has an issue file under `.nexus/issues/`
- [ ] Every story found in epic\*.md files has a spec file under `.nexus/specs/<ISSUE-KEY>/`
- [ ] Every issue's `specs` list names exactly the spec files that exist for it
- [ ] No spec files that don't correspond to a story in the epic files

### Parsing Verification

Compare epic files against the issue and spec files:

```
Epic Files Contains:                Issues / Specs Contains:
✓ Epic 1                            ✓ issues/epic-1.md
  ✓ Story 1.1: User Auth              ✓ specs/epic-1/1-1-user-auth.md
  ✓ Story 1.2: Account Mgmt           ✓ specs/epic-1/1-2-account-mgmt.md
  ✓ Story 1.3: Plant Naming           ✓ specs/epic-1/1-3-plant-naming.md
                                      (epic-1-retro.md only after retrospective runs)
✓ Epic 2                            ✓ issues/epic-2.md
  ✓ Story 2.1: Personality Model      ✓ specs/epic-2/2-1-personality-model.md
  ✓ Story 2.2: Chat Interface         ✓ specs/epic-2/2-2-chat-interface.md
```

### Final Check

- [ ] Total count of epics (issues) matches
- [ ] Total count of stories (specs) matches
- [ ] Each issue lists its specs in epic order (story 1, story 2, ...)
- [ ] `.nexus/board.yaml` was NOT written by this workflow (the app is its only writer)
