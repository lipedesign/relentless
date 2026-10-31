#!/usr/bin/env bash
# PostToolUse: non-blocking hint when commenting on issues/PRs without markers (exit 0 always).
set -euo pipefail
INPUT="$(cat || true)"
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)"
[[ -n "$CMD" ]] || exit 0
if echo "$CMD" | grep -qE 'gh\s+issue\s+comment|gh\s+pr\s+comment'; then
  if ! echo "$CMD" | grep -qE 'relentless:author|🤖|☺️'; then
    echo "[relentless] hint: workflow comments should include 🤖/☺️ + <!-- relentless:author=... -->" >&2
  fi
fi
exit 0
