---
name: human-gate
description: Block work pending a human decision. Posts the decision-request template, applies human:pending + state:blocked, assigns the configured decider. Never bare-remove human:pending.
---

# Human gate

## When to use
- A choice needs a human (product, risk, merge policy exception, ambiguous requirements)
- Before continuing past a fork the agent must not decide alone

## Required comment template
**Always** post a comment that follows `core/templates/decision-request.md` before or as you apply `human:pending`:

1. Clear **Question** + short **Context**
2. **Numbered options** (1, 2, 3…), each with short **Pros** and **Cons**
3. Agent **Recommendation** with reasoning
4. Markers: `🤖`, `<!-- relentless:author=agent -->`, `<!-- relentless:decision-request -->`

The human should be able to answer with only the option number.

## Label + assignee flow
1. Draft the decision-request body (use the template file).
2. Prefer `core/scripts/request-decision.sh --repo … --issue N --body-file …`
   - Adds `human:pending` and `state:blocked`
   - Removes `state:in-progress` if present
   - Assigns `decider.github` from `.relentless/config.json`
3. **Never** delete `human:pending` by itself. Resolution path is `/decide` (or `core/scripts/decide.sh`), which:
   - Posts ☺️ comment with `<!-- relentless:author=human decider="…" -->`
   - Flips `human:pending` → `human:decided`
   - Clears `state:blocked`, sets `state:todo`, reassigns default worker

## Pairing
- `state:blocked` pairs with `human:pending` when waiting on a person
- Other blockers may use `state:blocked` without human labels; document why in a 🤖 comment

## Authorship
See `core/templates/authorship-markers.md`. Relayed decisions use ☺️ + human marker even when the agent account posts them.
