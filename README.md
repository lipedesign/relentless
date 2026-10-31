# Relentless

Reusable **agent workflow plugin** for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex CLI](https://github.com/openai/codex) (verified against **codex-cli 0.165.x**): GitHub issues & milestones as product outcomes, human decision gates, configurable merge policy, isolated reviewer, **agent auto-merge**.

Do **not** copy plugin `agents/` or `skills/` into consumer repos — install the plugin, then **set up the repo**.

## Install (Claude Code) — headless CLI

Prefer **project scope** so the repo records the plugin in `.claude/settings.json`:

```bash
claude plugin marketplace add marcelusfernandes/relentless
claude plugin install relentless@relentless --scope project -y
```

## Install (Codex CLI) — headless CLI

As of **codex-cli 0.165.x**, no project-scope flag — each collaborator:

```bash
codex plugin marketplace add marcelusfernandes/relentless
codex plugin add relentless@relentless
```

Canonical scripts path: `~/.codex/plugins/cache/relentless/relentless/<version>/` (or Claude `installPath`). Export `RELENTLESS_ROOT`.

## Prepare a consumer repo (required)

Installing the plugin alone is not enough. Run **setup** so the target repo gets labels, real CI, docs, and issue forms:

- Claude: **`/relentless:setup`** (skill `setup`)
- Codex: invoke skill **`setup`**
- Or scripts directly:

```bash
gh auth refresh -s workflow
./core/scripts/bootstrap.sh --check-scopes
./core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout \
  --merge-default human --decider YourName --harness both
# review plan, then:
./core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout \
  --merge-default human --decider YourName --harness both --apply
```

### What setup / bootstrap does

| Piece | Behavior |
|-------|----------|
| **Stack detection** | Node (lockfile → npm/pnpm/yarn/bun + scripts), Python, Go, Rust; else `unknown` |
| **CI** | Writes `.github/workflows/relentless-ci.yml` with detected commands. If unknown / no test → workflow **fails** with a clear message (never a silent pass). Leaves other workflows alone. |
| **merge.default** | Forced to `human` when checks are weak, unless you pass `--merge-default auto` explicitly |
| **Config** | `.relentless/config.json` includes `stack` + `checks.{install,lint,typecheck,test,build}` |
| **AGENTS.md / CLAUDE.md** | Upserts a `<!-- relentless:start -->` … `<!-- relentless:end -->` block (idempotent; does not skip existing files) |
| **Issue forms** | `relentless.yml`, `investigation.yml`, **`epic.yml`**, `config.yml` with `blank_issues_enabled: false` |
| **Labels** | Idempotent create/edit |

Setup then commits seeds on `chore/relentless-setup` and opens a PR (empty repos may seed `main` first).

## Quick start after setup

```bash
./core/scripts/create-milestone.sh --repo OWNER/NAME --title "Theme: subtitle" \
  --outcome "…" --exit-criterion "…"
./core/scripts/create-epic.sh --repo OWNER/NAME --title "… understanding" \
  --milestone "Theme: subtitle" --outcome "…" --exit-criterion "…"
./core/scripts/create-issue.sh --repo OWNER/NAME --title "feat: …" \
  --milestone "Theme: subtitle" --type enhancement --parent N --label merge:auto
```

Implement → QA → **stop at `state:review`** → isolated reviewer → `apply-review-verdict` → **`merge-if-ready`**.

Harness profiles: **`docs/harness-profiles.md`**. Plan / backlog: **`docs/PLAN.md`**.

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

## Decision records & worktrees

- Durable choices live in `docs/decisions/` (ADR = human gate via `/decide`; notes = no gate). Agents read them before plan/implement.
- Each implementer works in its own git worktree (`skills/worktree-segura`, `worktree-create.sh`) on `<type>/<n>-<slug>` from `origin/main`.

