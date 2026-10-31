#!/usr/bin/env bash
# PreToolUse: human-gate + state helpers + soft isolation guard.
# Claude Code / Codex: exit 2 = block the tool call.
set -euo pipefail

INPUT="$(cat || true)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)"
[[ -n "$CMD" ]] || exit 0

# Allow our own helpers always
if echo "$CMD" | grep -qE 'request-decision\.sh|decide\.sh|set-state\.sh|bootstrap\.sh|merge-if-ready\.sh|apply-review-verdict\.sh|create-issue\.sh|create-milestone\.sh|comment-agent\.sh|wait-ci\.sh|build-review-bundle\.sh'; then
  # Still enforce implementer isolation below for apply/merge when role set
  :
fi

ROLE="${RELENTLESS_ROLE:-}"
AGENT="${CLAUDE_AGENT:-${AGENT_NAME:-}}"
if [[ "$ROLE" == "implementer" || "$AGENT" == *"implementer"* ]]; then
  if echo "$CMD" | grep -qE 'apply-review-verdict\.sh|merge-if-ready\.sh|review:approved'; then
    echo "[relentless] BLOCKED: implementer stops at state:review — no self-review / no merge." >&2
    exit 2
  fi
fi

# Block human:pending via raw gh without decision-request markers
if echo "$CMD" | grep -qE 'human:pending' && echo "$CMD" | grep -qE 'gh\s+issue\s+(edit|create)'; then
  if ! echo "$CMD" | grep -qE 'relentless:decision-request|decision-request\.md|request-decision'; then
    echo "[relentless] BLOCKED: applying human:pending requires the decision-request template (use request-decision.sh)." >&2
    exit 2
  fi
fi

# Block bare removal of human:pending without human:decided
if echo "$CMD" | grep -qE -- '--remove-label[= ]["'\'']?human:pending' ; then
  if ! echo "$CMD" | grep -qE 'human:decided|decide\.sh'; then
    echo "[relentless] BLOCKED: never bare-remove human:pending — use decide.sh / flip to human:decided." >&2
    exit 2
  fi
fi

# Soft block: same bash applying review:approved while also pushing/creating PR
if echo "$CMD" | grep -qE 'review:approved' && echo "$CMD" | grep -qE 'git\s+push|gh\s+pr\s+create'; then
  echo "[relentless] BLOCKED: do not self-approve in the implementer session. Stop at state:review." >&2
  exit 2
fi

exit 0
