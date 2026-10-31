# Relentless doctrine

Shared operating rules for Claude Code and Codex agents using this plugin.

## Purpose
Ship personal projects with a repeatable agent workflow: GitHub milestones as **product outcomes**, issues with explicit state, configurable merge policy, and **human decision gates** that never silently drop pending decisions.

## Dual runtime
| Surface | Location |
|---------|----------|
| Claude Code plugin | `.claude-plugin/`, `agents/`, `skills/`, `commands/`, `hooks/` |
| Codex | `plugin.json` / `.codex-plugin/`, `.codex/agents/*.toml`, `.agents/plugins/marketplace.json`, this `AGENTS.md` |
| Shared core | `core/` (templates, labels, scripts, schemas) |

Prefer shared `core/` over duplicating logic per runtime.

## Labels
- `state:todo` | `in-progress` | `blocked` | `review` | `done` — **exactly one** active `state:*` (helpers swap; never stack)
- `merge:auto` | `merge:human` — per-issue override of `merge.default`
- `human:pending` | `human:decided` — **never** bare-remove `human:pending`; always flip to `human:decided` via `/decide`
- `review:approved` — review passed

`state:blocked` pairs with `human:pending` when waiting on a person.

Use `core/scripts/set-state.sh` (or `set_issue_state` in `lib/common.sh`) for every state transition.

## Assignees
- Worker while `state:in-progress`
- Decider (`decider.github` in `.relentless/config.json`) while `human:pending`
- Reviewer **role** is required in v1 as an isolated agent; automatic GitHub reviewer *assignment* remains **v1.1**

## Authorship markers
Every workflow comment:
- Agent: leading `🤖` + `<!-- relentless:author=agent -->`
- Human / relayed decision: leading `☺️` + `<!-- relentless:author=human decider="<decider.name>" -->`

`decider.name` comes from project config, not from which GitHub account posted.

## Human decisions
When moving an issue to `human:pending`, the agent **must** comment using **`core/templates/decision-request.md`**:

1. Question + context  
2. Numbered options, each with short pros/cons  
3. Agent recommendation with reasoning  

The human replies with an option number. `/decide` (or `core/scripts/decide.sh`) records ☺️ + flips to `human:decided`.

Skills: `human-gate`. Commands: `/request-decision`, `/decide`.

## Orchestrator — spawn isolated REVIEWER
After QA has filled **QA / dogfood result**, the orchestrator **must** start the **reviewer** as a **separate subagent / fresh session** (never continue the implementer thread).

**Pass ONLY:**
1. Issue text (acceptance criteria)
2. PR diff
3. QA / dogfood section

**Do not** pass implementer reasoning, chat logs, or planning notes.

- Claude Code: new agent/session with `agents/reviewer.md`
- Codex: separate process, for example:

```bash
# Prepare a bundle file with ONLY the three inputs, then:
codex exec --sandbox read-only "$(cat review-bundle.md)"

# Or use the built-in review entrypoint with custom instructions:
codex review --base main "$(cat review-instructions.md)"
```

Reviewer is **read-only** (no edits/commits). It outputs the structured verdict in `agents/reviewer.md`. Orchestrator (or `core/scripts/apply-review-verdict.sh`) applies `review:approved` or leaves changes requested.

## Merge policy
- Default: `.relentless/config.json` → `merge.default` (`auto` | `human`)
- Overrides: issue labels when `allow_issue_override` is true
- Branch rulesets: **opt-in**, **fail-soft** at bootstrap
- Pushing `.github/workflows/*` requires GitHub token scope **`workflow`** (`gh auth refresh -s workflow`)

## Milestones
Product outcomes, not work buckets. Guard with `milestone-guard` and:

```bash
core/scripts/check-milestone-outcomes.sh --repo OWNER/NAME
core/scripts/check-milestone-pending.sh --repo OWNER/NAME --milestone N
```

**Do not close a milestone** while any of its open issues still has `human:pending`. Orchestrators must run the pending check first; exit code 1 means leave the milestone open.

## Dogfood QA
The `qa` agent dogfoods this workflow (`dogfood-qa` skill) and writes a QA section. No separate Proof/provas product.

Private repos / plans without GitHub Pages: do not require a Pages URL — use local preview (e.g. `npm run preview`) and note that in the QA section.

## Bootstrap
```bash
core/scripts/bootstrap.sh --check-scopes
core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout          # dry-run (shows labels + seed plan)
core/scripts/bootstrap.sh --repo OWNER/NAME --workdir /path/to/checkout --apply  # labels + seed files + CI template
```

Seeding (unless `--no-seed-files`): `.relentless/config.json`, issue + PR templates (with QA / dogfood), minimal CI workflow, `AGENTS.md` / `CLAUDE.md` stubs, Codex agent tomls.

Empty repos need an initial commit before milestones work reliably.

## Headless / CI auth (dogfood)
- Claude Code: `CLAUDE_CODE_OAUTH_TOKEN` (or documented Claude CI auth) for non-interactive runs
- Codex: API key / `codex login` device flow; for automation prefer env credentials documented by Codex for your plan
- Relentless does not replace provider login — document tokens in the consumer CI secrets store

## Out of scope
- Product Upstream / BUS port
- Proof (provas) surfaces
- Automatic GitHub reviewer assignment (v1.1)
