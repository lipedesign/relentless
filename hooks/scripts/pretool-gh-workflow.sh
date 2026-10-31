#!/usr/bin/env bash
# PreToolUse: block Bash that would gh-label human:pending without decision-request markers,
# or stack state labels incorrectly via raw gh calls (best-effort heuristic).
# Claude Code / Codex: exit 2 = block the tool call.
set -euo pipefail

INPUT="$(cat || true)"
# Only inspect Bash tool payloads
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)"
[[ -n "$CMD" ]] || exit 0

# Allow our own helpers
if echo "$CMD" | grep -qE 'request-decision\.sh|decide\.sh|set-state\.sh|bootstrap\.sh'; then
  exit 0
fi

# Block applying human:pending via raw gh without evidence of decision-request file/marker in the same command
if echo "$CMD" | grep -qE 'human:pending' && echo "$CMD" | grep -qE 'gh\s+issue\s+edit'; then
  if ! echo "$CMD" | grep -qE 'relentless:decision-request|decision-request\.md|request-decision'; then
    echo "[relentless] BLOCKED: applying human:pending requires the decision-request template (use request-decision.sh)." >&2
    exit 2
  fi
fi

# Block bare removal of human:pending without human:decided in same command
if echo "$CMD" | grep -qE -- '--remove-label[= ]["'\'']?human:pending' ; then
  if ! echo "$CMD" | grep -qE 'human:decided|decide\.sh'; then
    echo "[relentless] BLOCKED: never bare-remove human:pending — use decide.sh / flip to human:decided." >&2
    exit 2
  fi
fi

exit 0
