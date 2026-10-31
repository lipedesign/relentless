---
name: bootstrap
description: Install Relentless labels and seed consumer artifacts. Always dry-run first unless the user explicitly asks to apply. Checks gh workflow scope.
---

# Bootstrap

## Steps
1. `core/scripts/bootstrap.sh --check-scopes` — if `workflow` missing, tell the user to run `gh auth refresh -s workflow`.
2. Confirm target repo has a default branch (initial commit); if empty, say so before milestones.
3. Dry-run with `--workdir` pointing at the consumer checkout:
   ```bash
   core/scripts/bootstrap.sh --repo OWNER/NAME --workdir PATH --config PATH/.relentless/config.json
   ```
4. Show the full plan (labels + seed files + CI). Only with explicit approval, re-run with `--apply`.
5. Rulesets remain opt-in fail-soft (`rulesets.apply`).

## Seeds (unless `--no-seed-files`)
`.relentless/config.json`, `.github/ISSUE_TEMPLATE/relentless.yml`, `.github/PULL_REQUEST_TEMPLATE.md` (QA section), `.github/workflows/ci.yml`, `AGENTS.md`, `CLAUDE.md`, `.codex/agents/*.toml`.
