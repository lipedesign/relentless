---
name: human-gate
description: Block work pending a human decision. Posts decision-request template; applies human:pending + exactly one state:blocked (swap). Never bare-remove pending.
---

# Human gate

## Required comment
Follow `core/templates/decision-request.md` (question, numbered options with pros/cons, recommendation + markers).

## Flow
1. Draft body → `core/scripts/request-decision.sh --repo … --issue N --body-file …`
   - Adds `human:pending`
   - **Swaps** to `state:blocked` (removes other `state:*`; never stacks)
   - Assigns `decider.github`
2. Resolve only via `/decide` / `decide.sh` (☺️ + `human:decided` + `state:todo` swap).

Config path resolves from git root `.relentless/config.json` when relative CWD fails.
