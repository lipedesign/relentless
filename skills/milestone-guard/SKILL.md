---
name: milestone-guard
description: Keep GitHub milestones framed as product outcomes; detect drift into work-bucket language.
---

# Milestone guard

## Rules
- Milestone title + description describe a **user/product outcome**
- Description includes a Product outcome section (see `core/templates/milestone-outcome.md`)
- Issues under a milestone must map to that outcome in their body (`## Outcome`)

## Check
```bash
core/scripts/check-milestone-outcomes.sh --repo OWNER/NAME
```

## Drift examples (fix)
- "Sprint 12", "Backend chores", "Misc fixes" without an outcome statement

## Fix
Edit milestone description to state the outcome and success signals; rename if needed.
