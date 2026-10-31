---
name: bootstrap
description: Install Relentless labels and seed consumer artifacts. Dry-run first unless user asks to apply. Empty repos get an initial commit. Supports --merge-default / --decider.
---

# Bootstrap

## Steps
1. `core/scripts/bootstrap.sh --check-scopes`
2. Empty repos: with `--workdir --apply`, bootstrap creates an initial README commit on `main` (unless `--no-init-empty`).
3. Dry-run then apply — non-interactive flags supported:
   ```bash
   core/scripts/bootstrap.sh --repo OWNER/NAME --workdir PATH \
     --merge-default auto --decider Marcelus --decider-github marcelusfernandes
   core/scripts/bootstrap.sh --repo OWNER/NAME --workdir PATH \
     --merge-default auto --decider Marcelus --apply
   ```
4. Rulesets remain opt-in fail-soft.

## Seeds
`.relentless/config.json`, issue + PR templates, CI workflow, `AGENTS.md` / `CLAUDE.md`, Codex agent tomls, milestone example.
