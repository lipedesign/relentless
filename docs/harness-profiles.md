# Harness profiles (implementer vs reviewer)

Agents **must not** self-review. Use separate processes with different permissions.

**Orchestrator owns the full loop:** after `state:review`, the **same orchestrator session** must spawn the isolated reviewer (nested process), apply the verdict, and run `merge-if-ready` — do **not** stop for a human/driver resume. Prefer `core/scripts/run-isolated-review.sh --merge`.

## Codex CLI

### Implementer / orchestrator (needs git + gh)
```bash
codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  --dangerously-bypass-hook-trust \
  -C /path/to/workdir \
  < implementer-prompt.md
```
Export `RELENTLESS_ROLE=implementer` so hooks block `review:approved` / `merge-if-ready` / `apply-review-verdict`.

Prefer **Write / apply_patch** over huge `cat > file <<'EOF'` heredocs inside nested sessions — Codex shell classifiers can false-positive on heredoc bodies that look like dangerous commands.

### Reviewer (read-only)
```bash
core/scripts/build-review-bundle.sh --repo OWNER/NAME --pr N --issue N --out /tmp/review-bundle.md

# stdin — never "$(cat bundle)" as argv (large diffs fail)
codex exec --sandbox read-only -C /tmp/reviewer-sandbox < /tmp/review-bundle.md
```
Or: `codex review --base main …` with the same bundle. Do **not** pass implementer chat.

One-shot (orchestrator):
```bash
core/scripts/run-isolated-review.sh --repo OWNER/NAME --pr N --issue N \
  --harness codex --workdir . --merge
```

## Claude Code

### Implementer / orchestrator
```bash
claude -p --dangerously-skip-permissions < orchestrator-prompt.md
# Live logs — stream-json REQUIRES --verbose on Claude Code 2.1.x+:
claude -p --verbose --output-format stream-json --dangerously-skip-permissions < orchestrator-prompt.md
```

### Reviewer (restricted tools)
```bash
# stdin / file — never "$(cat review-bundle.md)" as argv
claude -p --agent relentless:reviewer \
  --allowedTools "Read,Grep,Glob,Bash(gh *)" \
  --verbose --output-format stream-json \
  < /tmp/review-bundle.md
```
The `relentless:reviewer` agent brief is read-only by doctrine. Prefer not combining with `--dangerously-skip-permissions` when the harness can restrict tools; if you must skip permissions for `gh` label writes, keep the session inputs to the bundle only and let the **orchestrator** run `apply-review-verdict.sh` + `merge-if-ready.sh`.

One-shot (orchestrator):
```bash
core/scripts/run-isolated-review.sh --repo OWNER/NAME --pr N --issue N \
  --harness claude --workdir . --merge
```

## Orchestrator final step (both)
After isolated review returns `approved` and `apply-review-verdict.sh … --verdict approved`:
```bash
core/scripts/merge-if-ready.sh --repo OWNER/NAME --pr N --issue N
```
- `merge:auto` (or config default auto): wait CI green on head SHA → **retarget open PRs stacked on the head branch** → `gh pr merge --merge` (delete branch only if no dependents remain) → `state:done` → close issue.
- `merge:human`: post 🤖 ready-to-merge and **do not** merge.

## Plugin script path
```bash
# Claude
claude plugin list --json   # → installPath
export RELENTLESS_ROOT="<installPath>"

# Codex — prefer cache path, not .tmp marketplaces clone
# ~/.codex/plugins/cache/relentless/relentless/<version>/
export RELENTLESS_ROOT=~/.codex/plugins/cache/relentless/relentless/1.4.0
```

## Project-scoped plugin install

| Runtime | Project scope? | How |
|---------|----------------|-----|
| Claude Code | **Yes** — `--scope project` (also `user`, `local`; default `user`) | Writes `.claude/settings.json` `enabledPlugins`; collaborators get prompted. Prefer this over copying agents/skills into the repo. |
| Codex CLI 0.165.x | **No** equivalent flag on `codex plugin add` | Plugins live in user `~/.codex/config.toml`. Each collaborator installs. Do not invent a project install. |

Bootstrap `--harness claude|codex|both` (default `both`) only seeds `.codex/agents/*.toml` stubs when Codex is in use; it never vendors Claude `agents/`/`skills/`. Prefer **`/relentless:setup`** / skill `setup` for the full interactive consumer prep.
