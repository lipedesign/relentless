---
name: issue-lifecycle
description: Move issues through state:* labels, keep assignees aligned with workers vs decider, and keep milestones as product outcomes.
---

# Issue lifecycle

## States
| Label | Meaning |
|-------|---------|
| `state:todo` | Ready |
| `state:in-progress` | Active work; assignee = worker |
| `state:blocked` | Cannot proceed; if waiting on human, also `human:pending` |
| `state:review` | Awaiting review |
| `state:done` | Finished |

Only one `state:*` should be active. Replace, do not stack.

## Assignees (v1)
- On `state:in-progress`: assign configured worker (`workers.default.github` or role-specific).
- On `human:pending`: reassign to `decider.github`.
- After `/decide`: reassign to worker, `state:todo`.
- Reviewer assignment is **v1.1** (not required in v1).

## Merge policy labels
- Repo default from `.relentless/config.json` → `merge.default` (`auto` \| `human`)
- Per-issue override: `merge:auto` or `merge:human` when `allow_issue_override` is true

## Milestones
Milestones are **product outcomes**, not sprint buckets. Descriptions should follow `core/templates/milestone-outcome.md`. Run `core/scripts/check-milestone-outcomes.sh` when planning or closing milestones.
