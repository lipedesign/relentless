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

Prefer shared `core/` over duplicating logic per runtime. See `docs/harness-profiles.md`.

## Labels
- `state:todo` | `in-progress` | `blocked` | `review` | `done` — **exactly one** active `state:*` (helpers swap; never stack)
- `merge:auto` | `merge:human` — per-issue override of `merge.default`
- `human:pending` | `human:decided` — **never** bare-remove `human:pending`; always flip to `human:decided` via `/decide`
- `review:approved` — review passed

`state:blocked` pairs with `human:pending` when waiting on a person.

Use `core/scripts/set-state.sh` (quiet by default) for every state transition.

## Assignees
- Worker while `state:in-progress`
- Decider (`decider.github` in `.relentless/config.json`) while `human:pending`
- Reviewer **role** is required in v1 as an isolated agent; automatic GitHub reviewer *assignment* remains **v1.1**

## Authorship markers
Every workflow comment:
- Agent: leading `🤖` + `<!-- relentless:author=agent -->` (prefer `comment-agent.sh`)
- Human / relayed decision: leading `☺️` + `<!-- relentless:author=human decider="<decider.name>" -->`

## Human decisions
When moving an issue to `human:pending`, the agent **must** comment using **`core/templates/decision-request.md`**. Skills: `human-gate`. Commands: `/request-decision`, `/decide`.

## Orchestrator loop (implement → review → merge)

```
in-progress → (QA) → state:review → [STOP implementer]
  → isolated reviewer (bundle only)
  → apply-review-verdict
       approved          → merge-if-ready → state:done
       changes_requested → state:in-progress (resume implementer)
```

### Implementer stop rule (mandatory)
The implementer **stops at `state:review`**. It must **not**:
- claim to have run review in the same session
- apply `review:approved` or run `apply-review-verdict.sh`
- run `merge-if-ready.sh` / `gh pr merge`

Hooks soft-block these when `RELENTLESS_ROLE=implementer` or the same bash mixes push + review:approved.

### Isolated REVIEWER
Orchestrator **must** start the reviewer as a **separate** subagent / fresh session.

**Pass ONLY** (use `build-review-bundle.sh` — lockfiles excluded):
1. Issue text (acceptance criteria)
2. PR diff (no `package-lock.json` / yarn.lock / etc.)
3. QA / dogfood section

- Claude: `claude -p --agent relentless:reviewer "$(cat review-bundle.md)"`
- Codex: `codex exec --sandbox read-only "$(cat review-bundle.md)"`

Reviewer is **read-only**. Orchestrator applies verdict via `apply-review-verdict.sh`.

### FINAL step — merge-if-ready
After `approved`, orchestrator **must** run (do not stall at approved-but-unmerged):

```bash
core/scripts/merge-if-ready.sh --repo OWNER/NAME --pr N --issue N
```

- `merge:auto` / config default `auto`: CI green on head SHA + `review:approved` → **merge commit** (`gh pr merge --merge`) → `state:done` → close issue
- `merge:human`: post 🤖 ready-to-merge and wait

CI wait: prefer `wait-ci.sh` / `gh run watch` after a run id exists (avoids `gh pr checks` “no checks reported” race).

## Merge policy
- Default: `.relentless/config.json` → `merge.default` (`auto` | `human`)
- Overrides: issue labels when `allow_issue_override` is true
- Branch rulesets: **opt-in**, **fail-soft** at bootstrap
- Pushing `.github/workflows/*` requires GitHub token scope **`workflow`**

## Milestones
Product outcomes, not work buckets:

```bash
core/scripts/create-milestone.sh --repo OWNER/NAME --title "User can …" \
  --outcome "…" --exit-criterion "…"
core/scripts/check-milestone-outcomes.sh --repo OWNER/NAME
core/scripts/check-milestone-pending.sh --repo OWNER/NAME --milestone N
```

**Do not close a milestone** while any open issue still has `human:pending`.

## Dogfood QA
`qa` agent + `dogfood-qa` skill. Prefer `fill-qa-section.sh`. README must match shipped features before milestone close.

## Bootstrap
```bash
core/scripts/bootstrap.sh --check-scopes
core/scripts/bootstrap.sh --repo OWNER/NAME --workdir PATH \
  --merge-default auto --decider Marcelus --harness both          # dry-run
core/scripts/bootstrap.sh --repo OWNER/NAME --workdir PATH \
  --merge-default auto --decider Marcelus --harness claude --apply
```

`--harness claude|codex|both` (default `both`): seeds `.codex/agents/*.toml` only for `codex`/`both`. **Never** vendor plugin `agents/` or `skills/` into the consumer — install the plugin.

## Plugin install (do not copy agents/skills)
- **Claude (prefer project scope):** `claude plugin install relentless@relentless --scope project -y` after `marketplace add` — writes `.claude/settings.json` `enabledPlugins` so collaborators are prompted.
- **Codex 0.165.x:** no project-scope flag on `codex plugin add` (user-level `~/.codex/config.toml` only). Each collaborator runs `codex plugin marketplace add` + `codex plugin add`.

## Headless / CLI notes
- Claude: `claude -p` buffers stdout when redirected — use `--output-format stream-json` for dogfoods.
- Codex: `codex plugin list` is very verbose (curated catalog); confirm install amid noise or parse JSON if available. Prefer `~/.codex/plugins/cache/relentless/relentless/<ver>/` as `RELENTLESS_ROOT`.
- See `docs/harness-profiles.md` and `docs/deferred-v1.1.md`.

## Out of scope / deferred
- Product Upstream / BUS port; Proof (provas)
- Automatic GitHub reviewer assignment; upstream Codex list filters — see `docs/deferred-v1.1.md`
