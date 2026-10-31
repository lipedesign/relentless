---
name: bootstrap
description: Install Relentless labels and seed consumer artifacts. Dry-run first unless user asks to apply. Empty repos get an initial commit. Supports --merge-default / --decider / --harness. Never vendors plugin agents/skills.
---

# Bootstrap

## Before seeding — install the plugin (not copy files)
Do **not** copy Relentless `agents/` or `skills/` into the consumer repo.

**Claude Code (prefer project scope — records `.claude/settings.json` for collaborators):**
```bash
claude plugin marketplace add marcelusfernandes/relentless
claude plugin install relentless@relentless --scope project -y
```
Scopes from `claude plugin install --help`: `user` | `project` | `local` (default `user`).

**Codex CLI 0.165.x:** `codex plugin add` has **no** project-scope option (verified). User-level only:
```bash
codex plugin marketplace add marcelusfernandes/relentless
codex plugin add relentless@relentless
```

## Steps
1. `core/scripts/bootstrap.sh --check-scopes`
2. Empty repos: with `--workdir --apply`, creates an initial README commit on `main` (unless `--no-init-empty`).
3. Dry-run then apply:
   ```bash
   core/scripts/bootstrap.sh --repo OWNER/NAME --workdir PATH \
     --merge-default auto --decider Marcelus --harness claude
   core/scripts/bootstrap.sh --repo OWNER/NAME --workdir PATH \
     --merge-default auto --decider Marcelus --harness claude --apply
   ```
4. `--harness claude|codex|both` (default `both`): `.codex/agents/*.toml` stubs only when harness is `codex` or `both`.
5. Rulesets remain opt-in fail-soft.

## Seeds
`.relentless/config.json`, issue + PR templates, CI workflow, `AGENTS.md` / `CLAUDE.md` stubs, milestone example. Optional Codex agent tomls per `--harness`. Never `agents/` or `skills/` from the plugin.
