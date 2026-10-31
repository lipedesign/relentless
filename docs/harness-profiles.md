# Harness profiles (implementer vs reviewer)

Agents **must not** self-review. Use separate processes with different permissions.

## Codex CLI

### Implementer / orchestrator (needs git + gh)
```bash
codex exec \
  --dangerously-bypass-approvals-and-sandbox \
  --dangerously-bypass-hook-trust \
  -C /path/to/workdir \
  "$(cat implementer-prompt.md)"
```
Export `RELENTLESS_ROLE=implementer` so hooks block `review:approved` / `merge-if-ready` / `apply-review-verdict`.

### Reviewer (read-only)
```bash
# Bundle ONLY issue AC + QA + diff (lockfiles excluded):
core/scripts/build-review-bundle.sh --repo OWNER/NAME --pr N --issue N --out /tmp/review-bundle.md

codex exec --sandbox read-only -C /tmp/reviewer-sandbox \
  "$(cat /tmp/review-bundle.md)"
```
Or: `codex review --base main …` with the same bundle. Do **not** pass implementer chat.

## Claude Code

### Implementer / orchestrator
```bash
claude -p --dangerously-skip-permissions "$(cat orchestrator-prompt.md)"
# Prefer live logs:
claude -p --output-format stream-json --dangerously-skip-permissions "…"
```

### Reviewer (restricted tools)
```bash
claude -p --agent relentless:reviewer "$(cat /tmp/review-bundle.md)"
```
The `relentless:reviewer` agent brief is read-only by doctrine. Prefer not combining with `--dangerously-skip-permissions` when the harness can restrict tools; if you must skip permissions for `gh` label writes, keep the session inputs to the bundle only and let the **orchestrator** run `apply-review-verdict.sh` + `merge-if-ready.sh`.

## Orchestrator final step (both)
After isolated review returns `approved` and `apply-review-verdict.sh … --verdict approved`:
```bash
core/scripts/merge-if-ready.sh --repo OWNER/NAME --pr N --issue N
```
- `merge:auto` (or config default auto): wait CI green on head SHA → `gh pr merge --merge` → `state:done` → close issue.
- `merge:human`: post 🤖 ready-to-merge and **do not** merge.

## Plugin script path
```bash
# Claude
claude plugin list --json   # → installPath
export RELENTLESS_ROOT="<installPath>"

# Codex — prefer cache path, not .tmp marketplaces clone
# ~/.codex/plugins/cache/relentless/relentless/<version>/
export RELENTLESS_ROOT=~/.codex/plugins/cache/relentless/relentless/1.2.0
```
