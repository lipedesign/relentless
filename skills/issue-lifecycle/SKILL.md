---
name: issue-lifecycle
description: Move issues through exactly one state:* label; assignees; milestones as outcomes. Use set-state.sh / create-issue.sh.
---

# Issue lifecycle

Always **swap** state labels via `core/scripts/set-state.sh` (never stack `state:*`).

Create issues with milestone **number or title**:
```bash
core/scripts/create-issue.sh --repo OWNER/NAME --title "…" --milestone 1
```

Assignees: worker in progress; decider on `human:pending`; after `/decide` back to worker.
