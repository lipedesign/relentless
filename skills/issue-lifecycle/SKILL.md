---
name: issue-lifecycle
description: Move issues through exactly one state:* label; create milestones/issues; assignees. Use set-state / create-issue / create-milestone.
---

# Issue lifecycle

Always **swap** state labels via `core/scripts/set-state.sh` (quiet by default; `--verbose` for URLs).

```bash
core/scripts/create-milestone.sh --repo OWNER/NAME --title "User can …" \
  --outcome "…" --exit-criterion "…"
core/scripts/create-issue.sh --repo OWNER/NAME --title "…" --milestone 1 --label merge:auto
# --label APPENDS to state:todo (does not replace defaults)
core/scripts/set-state.sh --repo OWNER/NAME --issue N --state in-progress
```

State machine:
- todo → in-progress → review (implementer **stops here**)
- review + isolated approve → merge-if-ready → done
- review + changes_requested → **in-progress**

Assignees: worker in progress; decider on `human:pending`; after `/decide` back to worker.
