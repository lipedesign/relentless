# Harness profiles (implementer vs reviewer)

Agents **must not** self-review. Use separate processes with different permissions.

**Orchestrator owns the full loop:** after `state:review`, the **same orchestrator session** must spawn the isolated reviewer (nested process), apply the verdict, and run `merge-if-ready` — do **not** stop for a human/driver resume. Prefer `core/scripts/run-isolated-review.sh --merge`.

## Codex CLI

Codex has no Claude PreToolUse or Stop hooks, and commands have no TTY even in the interactive TUI. The guard is `.codex/agents/<role>.toml` `developer_instructions`, derived from `agents/<role>.md` (worktree, stop at `state:review`, no commit or push on main, read-only reviewer, QA and documenter limits, and the decision rules). `tests/agents/test-codex-agent-briefs.py` fails if a TOML drops a normative line from its brief.

### Implementer / orchestrator (needs git + gh)
```bash
codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  --dangerously-bypass-hook-trust \
  -C /path/to/workdir \
  < implementer-prompt.md
```
Export `RELENTLESS_ROLE=implementer`. Hooks are not present in Codex; the implementer TOML still forbids `review:approved`, `merge-if-ready`, and `apply-review-verdict`, and `decide.sh` refuses when that role is set.

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
export RELENTLESS_ROOT=~/.codex/plugins/cache/relentless/relentless/1.4.3
```

## Project-scoped plugin install

| Runtime | Project scope? | How |
|---------|----------------|-----|
| Claude Code | **Yes** — `--scope project` (also `user`, `local`; default `user`) | Writes `.claude/settings.json` `enabledPlugins`; collaborators get prompted. Prefer this over copying agents/skills into the repo. |
| Codex CLI 0.165.x | **No** equivalent flag on `codex plugin add` | Plugins live in user `~/.codex/config.toml`. Each collaborator installs. Do not invent a project install. |

Bootstrap `--harness claude|codex|both` (default `both`) only seeds `.codex/agents/*.toml` stubs when Codex is in use; it never vendors Claude `agents/`/`skills/`. Prefer **`/relentless:setup`** / skill `setup` for the full interactive consumer prep.

## Human decisions

Agents share the human's GitHub identity. There is no marker file or env token that proves a human (the agent could write it).

- **Claude:** typing `/decide <issue> <option>` runs `hooks/scripts/userprompt-decide.sh` (UserPromptSubmit). The hook records the decision. The agent does not call `decide.sh`.
- **Codex:** commands have no TTY, even in the interactive TUI, so the human cannot confirm `/decide` from inside a Codex session. `decide.sh` and `accept-adr.sh` refuse and print the exact command. That refusal is expected behavior, not a broken lock. Do not retry or try another route. The decider runs it in their own terminal, outside the agent session:

```bash
core/scripts/decide.sh --repo OWNER/NAME --issue N --option K
```

With the sandbox disabled, a process that allocates its own terminal lowers but does not eliminate the risk. `merge-if-ready` also refuses a PR that adds or changes an **accepted** ADR when the linked issue has no `<!-- relentless:decision-request -->` comment.

If the issue has `human:pending`, post the decision request, tell the decider (`decider.name` from config, not a hardcoded person) that command, and move on to another ready issue.

## Git hooks in the consumer repo

Setup / `bootstrap.sh` installs `.relentless/githooks/pre-commit` and `pre-push`:

- Unset `core.hooksPath` → set it to `.relentless/githooks`. An existing executable `.git/hooks/pre-commit` or `pre-push` is still chained.
- Existing `core.hooksPath` (husky or otherwise) → left unchanged; the hook files gain one `# relentless:githooks` chain call. Re-running does not duplicate it.
- They refuse commits on `main`/`master`, pushes that update `refs/heads/main` or `refs/heads/master`, and non-fast-forward pushes. The pre-push hook sees the old and new SHAs, not the `--force` flag, so a fast-forward update is allowed even if the client passed `--force`. The agent PreToolUse hook still blocks every force-push spelling (`-f`, `--force`, `--force-with-lease`, `+refspec`) before git runs.
- GitHub branch protection on main is **not** enabled by default. Setup asks; pass `--branch-protection` only after an explicit yes (fail-soft).

## Hook regression tests

```bash
bash tests/hooks/test-hooks.sh          # PreToolUse protect-main, reviewer isolation, decide block
bash tests/hooks/test-decide-guard.sh   # agent refusal, forged env, human PTY, UserPromptSubmit, merge ADR guard
bash tests/hooks/test-githooks.sh       # core.hooksPath install, husky chain, main and force-push
python3 tests/agents/test-codex-agent-briefs.py  # Codex TOML instructions cover agents/*.md
```

CI (`.github/workflows/ci.yml`) runs the same scripts.
