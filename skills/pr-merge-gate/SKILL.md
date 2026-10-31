---
name: pr-merge-gate
description: Enforce configurable merge policy (auto vs human) using repo config and per-issue merge:* labels.
---

# PR merge gate

## Resolve policy for a PR
1. Find linked issue(s).
2. If any linked issue has `merge:human` → require human merge.
3. Else if any has `merge:auto` and overrides allowed → agent may auto-merge (after checks).
4. Else use `merge.default` from `.relentless/config.json`.

## When policy is human
- Do not merge
- Optionally open a decision-request (human-gate skill) if the human must choose among merge strategies
- Leave a 🤖 comment stating policy and waiting state

## When policy is auto
- Merge only if required checks are green and review:approved (when used)
- Comment with 🤖 + authorship marker noting auto-merge per policy

## Rulesets
Applying branch rulesets is **opt-in** and **fail-soft** during bootstrap. Missing permissions must not block label install.
