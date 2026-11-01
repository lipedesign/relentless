---
name: issue-lifecycle
description: Move issues through exactly one state:* label; create milestones, epics, and sub-issues; assignees. The orchestrator runs set-state. Planner uses create-milestone / create-epic / create-issue / add-sub-issue.
---

# Issue lifecycle

Only the orchestrator runs `core/scripts/set-state.sh` and moves `state:*` labels (quiet by default; `--verbose` for URLs). The implementer, qa, documenter, and planner do not write state labels or run `set-state.sh`.

## Open a wave (planner)
```bash
core/scripts/create-milestone.sh --repo OWNER/NAME --title "Theme: subtitle" \
  --outcome "…" --exit-criterion "…"
# FIRST: parent epic (understanding)
core/scripts/create-epic.sh --repo OWNER/NAME --title "… understanding" \
  --milestone "Theme: subtitle" --outcome "…" --exit-criterion "…" \
  --understanding "…" --plan "…"
# THEN: sub-issues linked natively
core/scripts/create-issue.sh --repo OWNER/NAME --title "feat: …" \
  --milestone "Theme: subtitle" --type enhancement --parent N --label merge:auto
```

`--label` APPENDS to `state:todo`. `--type` sets bug|enhancement|documentation|investigation|epic.
Creating an issue with the default `state:todo` is the initial label, not a state transition.
Work too big for one session/PR → epic + sub-issues (`decompose-epic` skill). No complexity labels.

## State transitions (orchestrator)

```bash
core/scripts/set-state.sh --repo OWNER/NAME --issue N --state in-progress
core/scripts/close-epic.sh --repo OWNER/NAME --epic N
```

State machine:
- todo → in-progress → review (implementer **stops here**; the orchestrator sets the label)
- review + isolated approve → merge-if-ready → done
- review + changes_requested → **in-progress**

Assignees: worker while in progress; decider on `human:pending`; after the decider runs `/decide`, back to the worker. The orchestrator assigns.
