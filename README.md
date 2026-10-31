# Relentless

Reusable **agent workflow plugin** for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex](https://openai.com/codex): GitHub issues & milestones as product outcomes, human decision gates, configurable merge policy.

## Install (Claude Code)

```text
/plugin install relentless --marketplace marcelusfernandes/relentless
```

Or add this repo as a marketplace plugin source, or copy/link the plugin root into your Claude plugins path. See `.claude-plugin/plugin.json` and `marketplace/marketplace.json`.

## Install (Codex)

Point Codex at this directory; read `AGENTS.md` and `.codex/agents/*.toml`. Shared logic lives under `core/`.

## Quick start

1. Copy `core/schemas/config.example.json` → `.relentless/config.json` in the **target** project; set `decider` and `merge.default`.
2. Dry-run bootstrap (from this plugin root):
   ```bash
   ./core/scripts/bootstrap.sh --repo OWNER/NAME --config /path/to/.relentless/config.json
   ```
3. Apply only after review: add `--apply`.
4. Work issues with `state:*` labels. When blocked on a human, use the **decision-request** template (`core/templates/decision-request.md`) and `human:pending`. Record the answer with `/decide`.

## Layout

```
.claude-plugin/   Claude plugin manifest
.codex-plugin/    Codex plugin manifest
.codex/agents/    Codex agent stubs
agents/           Shared agent briefs (Claude markdown)
skills/           bootstrap, human-gate, issue-lifecycle, milestone-guard, pr-merge-gate, dogfood-qa
commands/         /decide, /bootstrap, /request-decision
hooks/            Light reminders
core/             labels, templates, scripts, schemas
docs/PLAN.md      Design plan (English)
AGENTS.md         Doctrine (Claude + Codex)
```

## License

MIT
