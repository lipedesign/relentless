---
name: bootstrap
description: Install Relentless labels and validate project config on a GitHub repo. Always dry-run first unless the user explicitly asks to apply.
---

# Bootstrap

## When to use
- First time wiring Relentless into a repository
- After label schema changes
- User says "bootstrap", "install labels", or "set up relentless"

## Steps
1. Ensure `gh` auth works for the target repo.
2. Confirm or create `.relentless/config.json` from `core/schemas/config.example.json`.
   - `decider.name` is the display name for ☺️ markers (not the GitHub login alone).
   - `decider.github` is who gets assigned on `human:pending`.
   - `merge.default` is `auto` or `human`; issue labels `merge:auto` / `merge:human` override when allowed.
3. Run dry-run:
   ```bash
   core/scripts/bootstrap.sh --repo OWNER/NAME --config .relentless/config.json
   ```
4. Show the plan to the user. Only with explicit approval, re-run with `--apply`.
5. Rulesets are opt-in (`rulesets.apply`); if enabled, fail soft — never abort the whole bootstrap.

## Do not
- Apply labels to repos other than the one the user named
- Skip dry-run on first contact with a repo
