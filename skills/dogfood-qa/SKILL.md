---
name: dogfood-qa
description: QA agent dogfooding — exercise the workflow and fill QA / dogfood result. Not Proof/provas.
---

# Dogfood QA

1. Exercise bootstrap → issue → (optional human-gate) → implement → review path.
2. Fill **QA / dogfood result** via `core/scripts/fill-qa-section.sh --repo … --pr N --body-file qa.md` (and/or PR body section).
3. Before milestone close: README accuracy vs shipped pages/features.
4. File gaps as outcome-tied issues.

## Pages / preview
If GitHub Pages is unavailable, use local preview (`npm run preview`) and record it in QA. Prefer PID files over `pkill -f` for stopping preview (pkill can match the agent shell).

## Headless UI tips
- Controlled React inputs need the native value setter before `input`/`change` events.
- Prefer a throwaway `/tmp` puppeteer-core install over adding browser deps to the product.
