#!/usr/bin/env bash
# PreToolUse: block implementer from applying review:approved / apply-review-verdict / merge-if-ready
# when RELENTLESS_ROLE=implementer (or agent name looks like implementer).
# Claude/Codex: exit 2 = block.
set -euo pipefail

INPUT="$(cat || true)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)"
[[ -n "$CMD" ]] || exit 0

ROLE="${RELENTLESS_ROLE:-${CODEX_THREAD_ROLE:-}}"
AGENT="${CLAUDE_AGENT:-${AGENT_NAME:-}}"

is_implementer=0
if [[ "$ROLE" == "implementer" ]] || [[ "$AGENT" == *"implementer"* ]]; then
  is_implementer=1
fi
# Heuristic: same-session claiming review while also editing/pushing
if [[ "$is_implementer" -eq 0 ]]; then
  # Still block raw apply of review:approved + merge in one bash that also has git push / gh pr create
  if echo "$CMD" | grep -qE 'review:approved|apply-review-verdict|merge-if-ready' && \
     echo "$CMD" | grep -qE 'git\s+push|gh\s+pr\s+create|gh\s+pr\s+merge'; then
    echo "[relentless] BLOCKED: implementer must not self-review/merge in the same session. Stop at state:review; orchestrator spawns isolated reviewer then merge-if-ready." >&2
    exit 2
  fi
  exit 0
fi

if echo "$CMD" | grep -qE 'review:approved|apply-review-verdict\.sh|merge-if-ready\.sh'; then
  echo "[relentless] BLOCKED: implementer role must stop at state:review. Do not apply review labels or merge. Orchestrator spawns isolated reviewer." >&2
  exit 2
fi

exit 0
