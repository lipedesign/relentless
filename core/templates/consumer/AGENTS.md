# Project agents

This project uses the **Relentless** workflow plugin.

- Doctrine: follow Relentless `AGENTS.md` (labels, human gates, authorship markers, merge policy, product-outcome milestones).
- Config: `.relentless/config.json`
- When blocked on a human: post `core/templates/decision-request.md` and apply `human:pending` (never bare-remove it — use `/decide`).
- Spawn the **reviewer** as an isolated session with only: issue acceptance criteria, PR diff, and QA/dogfood section.

Add project-specific notes below.
