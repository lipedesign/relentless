---
name: milestone-guard
description: Keep milestones as product outcomes; block closing while any issue still has human:pending.
---

# Milestone guard

## Checks
```bash
core/scripts/check-milestone-outcomes.sh --repo OWNER/NAME
core/scripts/check-milestone-pending.sh --repo OWNER/NAME --milestone N
```

Orchestrators **must not close** a milestone when the pending check exits non-zero.

## Outcome shape
See `core/templates/milestone-outcome.md`.
