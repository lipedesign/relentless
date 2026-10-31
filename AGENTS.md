# Relentless doctrine

Shared operating rules for Claude Code and Codex agents using this plugin.

## Purpose
Ship personal projects with a repeatable agent workflow: GitHub milestones as **product outcomes**, issues with explicit state, configurable merge policy, and **human decision gates** that never silently drop pending decisions.

## Dual runtime
| Surface | Location |
|---------|----------|
| Claude Code plugin | `.claude-plugin/`, `agents/`, `skills/`, `commands/`, `hooks/` |
| Codex | `.codex-plugin/`, `.codex/agents/*.toml`, this `AGENTS.md` |
| Shared core | `core/` (templates, labels, scripts, schemas) |

Prefer shared `core/` over duplicating logic per runtime.

## Labels
- `state:todo` | `in-progress` | `blocked` | `review` | `done` — one active state
- `merge:auto` | `merge:human` — per-issue override of `merge.default`
- `human:pending` | `human:decided` — **never** bare-remove `human:pending`; always flip to `human:decided` via `/decide`
- `review:approved` — review passed

`state:blocked` pairs with `human:pending` when waiting on a person.

## Assignees
- Worker while `state:in-progress`
- Decider (`decider.github` in `.relentless/config.json`) while `human:pending`
- Reviewer assignment deferred to **v1.1**

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

## Merge policy
- Default: `.relentless/config.json` → `merge.default` (`auto` | `human`)
- Overrides: issue labels when `allow_issue_override` is true
- Branch rulesets: **opt-in**, **fail-soft** at bootstrap

## Milestones
Product outcomes, not work buckets. Guard with `milestone-guard` and `core/scripts/check-milestone-outcomes.sh`.

## Dogfood QA
The `qa` agent dogfoods this workflow (`dogfood-qa` skill) and writes a QA section. No separate Proof/provas product.

## Bootstrap
```bash
core/scripts/bootstrap.sh --repo OWNER/NAME --config .relentless/config.json          # dry-run
core/scripts/bootstrap.sh --repo OWNER/NAME --config .relentless/config.json --apply  # explicit only
```

## Out of scope (v1)
- Product Upstream / BUS port
- Proof (provas) surfaces
- Automatic reviewer assignment (v1.1)
