---
name: setup
description: Prepare a consumer GitHub repo for Relentless — interactive merge/decider/harness, stack detection, bootstrap dry-run then apply, commit seeds on a branch and open a PR (or main for empty repos). Optional first milestone+epic. Use when the user asks to set up Relentless, bootstrap a project, or "prepare the repo".
argument-hint: '[OWNER/NAME] [--workdir PATH]'
allowed-tools: Bash, Read, Grep, Glob, Write, AskUserQuestion
user-invocable: true
---

# /relentless:setup — prepare the user's repo

Goal: the consumer repo works with Relentless end-to-end (labels, real CI, docs blocks, issue forms, config). Prefer this over raw `bootstrap.sh`.

## Interactively collect (AskUserQuestion or chat)

1. **Target** `OWNER/NAME` and local `--workdir` (default `.`)
2. **merge.default**: `auto` | `human`  
   - If stack detection finds no test command, **recommend human** and only set `auto` if the user insists (warn that merge-if-ready trusts CI).
3. **decider.name** (and github login if not `gh api user`)
4. **harness**: `claude` | `codex` | `both`
5. **GitHub branch protection on main**: optional question, **off unless the user explicitly says yes**. Do not pass `--branch-protection` otherwise. Local git hooks are installed either way (they are not a substitute you skip). If they say yes, the apply command includes `--branch-protection` (fail-soft when the token cannot admin the repo).
6. Optional: **first product outcome** text → after apply, create milestone + epic

## Plugin install (before or during)

**Claude (project scope):**
```bash
claude plugin marketplace add marcelusfernandes/relentless
claude plugin install relentless@relentless --scope project -y
```

**Codex 0.165.x (user-level only):**
```bash
codex plugin marketplace add marcelusfernandes/relentless
codex plugin add relentless@relentless
```

## Steps

```bash
export RELENTLESS_ROOT=…   # plugin installPath
cd "$WORKDIR"

"$RELENTLESS_ROOT/core/scripts/bootstrap.sh" --check-scopes
# refresh workflow scope if needed:
# gh auth refresh -s workflow

# Dry-run — show plan (stack, CI, docs, labels)
"$RELENTLESS_ROOT/core/scripts/bootstrap.sh" --repo OWNER/NAME --workdir . \
  --merge-default human --decider "NAME" --harness both

# After user approves the plan:
"$RELENTLESS_ROOT/core/scripts/bootstrap.sh" --repo OWNER/NAME --workdir . \
  --merge-default human --decider "NAME" --harness both --apply
# Add --branch-protection only after an explicit yes. Default is off.
```

## Commit + PR

Unless the repo was empty and bootstrap already pushed `main`:

```bash
branch="chore/relentless-setup"
git checkout -b "$branch"
git add AGENTS.md CLAUDE.md .relentless .github docs/relentless .codex 2>/dev/null || true
git status
git commit -m "chore: Relentless setup (labels, CI, docs, issue forms)"
git push -u origin HEAD
gh pr create --title "chore: Relentless setup" --body "## Relentless setup

- Stack-detected CI (\`.github/workflows/relentless-ci.yml\`)
- Idempotent AGENTS.md / CLAUDE.md blocks
- Issue forms (relentless, investigation, epic) + blank_issues disabled
- \`.relentless/config.json\` with checks + merge.default
"
```

Empty repo: seeds may land on `main` via bootstrap initial commit — still open a follow-up PR if more files need review.

## Optional first wave

If the user described a product outcome:

```bash
"$RELENTLESS_ROOT/core/scripts/create-milestone.sh" --repo OWNER/NAME \
  --title "Theme: subtitle" --outcome "…" --exit-criterion "…"
"$RELENTLESS_ROOT/core/scripts/create-epic.sh" --repo OWNER/NAME \
  --title "… understanding" --milestone "Theme: subtitle" \
  --outcome "…" --exit-criterion "…" --understanding "…"
```

## What "prepared" means

| Artifact | Behavior |
|----------|----------|
| Labels | Idempotent create/edit from `labels.json` |
| CI | `relentless-ci.yml` with real commands **or** FAIL-closed if no test |
| Docs | `<!-- relentless:start -->` blocks upserted (never skip existing files) |
| Issues | `relentless.yml` + `investigation.yml` + `epic.yml` + `config.yml` |
| Config | `checks.{install,lint,typecheck,test,build}` + `stack` |
| Git hooks | `.relentless/githooks/pre-commit` and `pre-push`. `core.hooksPath` points at them, or an existing hooksPath / husky is chained and not replaced. They refuse commits on main/master, pushes to main/master, and non-fast-forward pushes. |
| Branch protection | **Off** unless the setup question was answered yes (`--branch-protection`, fail-soft). |

Never vendor plugin `agents/` / `skills/` into the consumer.


## After setup — product loop is self-sufficient

Once the user describes the product, the **orchestrator** (not a human driver) must:
1. Create milestone + epic + sub-issues
2. Implement → QA → `state:review`
3. Spawn isolated reviewer itself (`run-isolated-review.sh --merge` or equivalent nested `claude`/`codex`)
4. Continue to `merge-if-ready` without waiting for a resume prompt

Dogfood / real-user simulation: install plugin → `/relentless:setup` → answer questions → ask for the product. No mid-flow human wiring of review/merge.
