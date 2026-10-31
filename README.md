# Relentless

Reusable **agent workflow plugin** for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex CLI](https://github.com/openai/codex) (verified against **codex-cli 0.165.x**): GitHub issues & milestones as product outcomes, human decision gates, configurable merge policy, isolated reviewer, **agent auto-merge**.

## Install (Claude Code) — headless CLI

```bash
claude plugin marketplace add marcelusfernandes/relentless
claude plugin install relentless@relentless -y
```

Interactive slash form also works: `/plugin install relentless --marketplace marcelusfernandes/relentless`.

**Dogfood tip:** `claude -p` buffers stdout when redirected to a file. Prefer:

```bash
claude -p --output-format stream-json --dangerously-skip-permissions "…"
```

Find scripts: `claude plugin list --json` → `installPath` → export `RELENTLESS_ROOT=…`.

## Install (Codex CLI) — headless CLI

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

1. `gh auth refresh -s workflow` then `./core/scripts/bootstrap.sh --check-scopes`
2. Bootstrap (empty repos get an initial commit on `--apply`):
   ```bash
   ./core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout \
     --merge-default auto --decider Marcelus
   ./core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout \
     --merge-default auto --decider Marcelus --apply
   ```
3. Create outcome milestone + issues:
   ```bash
   ./core/scripts/create-milestone.sh --repo OWNER/NAME --title "User can …" \
     --outcome "…" --exit-criterion "…"
   ./core/scripts/create-issue.sh --repo OWNER/NAME --title "…" --milestone 1 --label merge:auto
   ```
4. Implement → QA → **stop at `state:review`** → isolated reviewer → `apply-review-verdict` → **`merge-if-ready`**.

Harness profiles (Codex implementer bypass vs reviewer read-only; Claude `--agent relentless:reviewer`): **`docs/harness-profiles.md`**.

Deferred items: **`docs/deferred-v1.1.md`**.

## Layout

```
.agents/plugins/marketplace.json   Codex marketplace catalog
.claude-plugin/                    Claude manifests
.codex-plugin/ + plugin.json       Codex / Agent Plugins manifests
.codex/agents/                     Codex agent stubs
agents/ skills/ commands/ hooks/   Runtime surfaces
core/                              labels, templates, scripts, schemas
AGENTS.md                          Doctrine (Claude + Codex)
docs/                              harness profiles, deferred, PLAN
```

## License

MIT
