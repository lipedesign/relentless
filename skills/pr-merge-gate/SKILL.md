---
name: pr-merge-gate
description: Final orchestrator step after isolated review — resolve merge:auto/human, require CI + review:approved, merge commit or post ready-to-merge.
---

# PR merge gate (orchestrator FINAL step)

After the **isolated** reviewer returns and you run `apply-review-verdict.sh`:

## Sequence (mandatory)
1. Implementer stops at `state:review` — **never** self-reviews or applies `review:approved`.
2. Orchestrator builds bundle (lockfiles excluded) and spawns isolated reviewer.
3. `core/scripts/apply-review-verdict.sh --repo … --issue … --pr … --verdict approved|changes_requested`
   - `approved` → `review:approved` + `state:review`
   - `changes_requested` → **`state:in-progress`** (implementer resumes)
4. **If approved → run merge-if-ready** (do not stall):
   ```bash
   core/scripts/merge-if-ready.sh --repo OWNER/NAME --pr N --issue N
   ```

## merge-if-ready behavior
- Mode: issue `merge:auto` / `merge:human`, else `.relentless/config.json` → `merge.default`.
- Requires `review:approved` and CI green on the PR **head SHA**.
- **auto:** `gh pr merge --merge` (merge commit), `state:done`, close issue, 🤖 merged comment.
- **human:** post 🤖 ready-to-merge comment and **wait** (do not merge).

## Helpers
- `wait-ci.sh --repo … --pr N` — prefer `gh run watch` once a run id exists (avoids `gh pr checks` “no checks reported” race).
- `comment-agent.sh` — 🤖 + authorship marker without heredoc pain.
- `build-review-bundle.sh` — issue + QA + diff with lockfiles stripped.

## Rulesets
Opt-in fail-soft at bootstrap.
