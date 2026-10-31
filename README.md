# Relentless

Reusable **agent workflow plugin** for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex CLI](https://github.com/openai/codex) (verified against **codex-cli 0.165.x**): GitHub issues & milestones as product outcomes, human decision gates, configurable merge policy, isolated reviewer.

## Install (Claude Code)

```text
/plugin install relentless --marketplace marcelusfernandes/relentless
```

## Install (Codex CLI)

Codex discovers the repo marketplace at `.agents/plugins/marketplace.json`.

```bash
# 1) Register this repo as a marketplace (GitHub shorthand)
codex plugin marketplace add marcelusfernandes/relentless

# 2) Install the plugin from that marketplace
codex plugin add relentless@relentless

# Optional: refresh after updates
codex plugin marketplace upgrade relentless
```

Local path alternative (clone first):

```bash
codex plugin marketplace add /absolute/path/to/relentless
codex plugin add relentless@relentless
```

Do **not** confuse with Claude’s `/plugin install` — Codex uses `codex plugin marketplace add` + `codex plugin add`.

After install, start a **new** Codex session so skills/agents load. Confirm with `codex plugin list`.

## Quick start (target repo)

1. Ensure `gh` has the **`workflow`** scope (needed to seed CI):
   ```bash
   gh auth refresh -s workflow
   ./core/scripts/bootstrap.sh --check-scopes
   ```
2. Target repo must have an initial commit (default branch) before milestones.
3. From the plugin root, dry-run then apply:
   ```bash
   ./core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout
   ./core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout --apply
   ```
   Seeds labels, `.relentless/config.json`, issue + PR templates (with **QA / dogfood result**), minimal `.github/workflows/ci.yml`, `AGENTS.md` / `CLAUDE.md`, Codex agent stubs.
4. Edit `.relentless/config.json` (`decider`, `merge.default`, `workers`).
5. Human gates: decision-request template → `human:pending` → `/decide`.
6. Review: orchestrator spawns **isolated** reviewer (issue + diff + QA only).

## Layout

```
.agents/plugins/marketplace.json   Codex marketplace catalog
.claude-plugin/                    Claude manifests
.codex-plugin/ + plugin.json       Codex / Agent Plugins manifests
.codex/agents/                     Codex agent stubs (incl. reviewer)
agents/                            Claude agent briefs (incl. reviewer)
skills/ commands/ hooks/           Runtime surfaces (hooks enforce)
core/                              labels, templates, scripts, schemas
AGENTS.md                          Doctrine (Claude + Codex)
docs/PLAN.md                       Design plan
```

## License

MIT
