# Relentless

Reusable **agent workflow plugin** for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex CLI](https://github.com/openai/codex) (verified against **codex-cli 0.165.x**): GitHub issues & milestones as product outcomes, human decision gates, configurable merge policy, isolated reviewer, **agent auto-merge**.

Do **not** copy plugin `agents/` or `skills/` into consumer repos — install the plugin.

## Install (Claude Code) — headless CLI

Prefer **project scope** so the repo records the plugin in `.claude/settings.json` (`enabledPlugins`) and collaborators get prompted:

```bash
claude plugin marketplace add marcelusfernandes/relentless
claude plugin install relentless@relentless --scope project -y
# scopes from `claude plugin install --help`: user | project | local  (default: user)
```

User-scope (this machine only): omit `--scope` or pass `--scope user`. Interactive: `/plugin install relentless --marketplace marcelusfernandes/relentless`.

**Dogfood tip:** `claude -p` buffers stdout when redirected to a file. Prefer:

```bash
claude -p --output-format stream-json --dangerously-skip-permissions "…"
```

Find scripts: `claude plugin list --json` → `installPath` → export `RELENTLESS_ROOT=…`.

## Install (Codex CLI) — headless CLI

As of **codex-cli 0.165.x**, `codex plugin add` has **no** `--scope` / project-scope flag (verified via `codex plugin add --help`). Plugins are enabled in the user config (`~/.codex/config.toml`). Do not invent a project install — each collaborator runs:

```bash
codex plugin marketplace add marcelusfernandes/relentless
codex plugin add relentless@relentless
codex plugin marketplace upgrade relentless   # after updates
```

Local path: `codex plugin marketplace add /absolute/path/to/relentless` then `codex plugin add relentless@relentless`.

Confirm with `codex plugin list` (verbose — dumps curated catalog; look for `relentless@relentless` enabled). Canonical scripts path:

`~/.codex/plugins/cache/relentless/relentless/<version>/` (prefer over `.tmp/marketplaces`).

Start a **new** Codex session after install.

## Quick start (target repo)

1. Install the plugin (Claude: `--scope project`; Codex: user-level — see above).
2. `gh auth refresh -s workflow` then `./core/scripts/bootstrap.sh --check-scopes`
3. Bootstrap (empty repos get an initial commit on `--apply`):
   ```bash
   ./core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout \
     --merge-default auto --decider Marcelus --harness both
   ./core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout \
     --merge-default auto --decider Marcelus --harness claude --apply
   ```
   `--harness claude|codex|both` (default `both`) controls whether `.codex/agents/*.toml` stubs are seeded. Never vendors plugin `agents/`/`skills/`.
4. Create outcome milestone + issues:
   ```bash
   ./core/scripts/create-milestone.sh --repo OWNER/NAME --title "User can …" \
     --outcome "…" --exit-criterion "…"
   ./core/scripts/create-issue.sh --repo OWNER/NAME --title "…" --milestone 1 --label merge:auto
   ```
5. Implement → QA → **stop at `state:review`** → isolated reviewer → `apply-review-verdict` → **`merge-if-ready`**.

Harness profiles: **`docs/harness-profiles.md`**. Deferred: **`docs/deferred-v1.1.md`**.

## Layout

```
.agents/plugins/marketplace.json   Codex marketplace catalog
.claude-plugin/                    Claude manifests
.codex-plugin/ + plugin.json       Codex / Agent Plugins manifests
.codex/agents/                     Codex agent stubs (plugin; optional consumer seed)
agents/ skills/ commands/ hooks/   Runtime surfaces (plugin only — do not vendor)
core/                              labels, templates, scripts, schemas
AGENTS.md                          Doctrine (Claude + Codex)
docs/                              harness profiles, deferred, PLAN
```

## License

MIT
