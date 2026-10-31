---
name: milestone-guard
description: Keep milestones as product outcomes; require epic parent + native sub-issues; block closing while human:pending remains.
---

# Milestone guard

## Checks
```bash
core/scripts/check-milestone-outcomes.sh --repo OWNER/NAME
core/scripts/check-milestone-pending.sh --repo OWNER/NAME --milestone N
```

Fails when:
- description lacks Product outcome / exit criterion shape
- open `human:pending` under the milestone (unless `--allow-pending`)
- **no epic parent** in the milestone
- issues not linked as native sub-issues of that epic (unless labeled `orphan:ok`)

Orchestrators **must not close** a milestone when these checks exit non-zero.
Close the epic with `close-epic.sh` only after all sub-issues are closed.

## Outcome shape
See `core/templates/milestone-outcome.md` (deliverable / validates-with / depends-on + exit criterion).
Title: `Theme: subtitle`.
