#!/usr/bin/env bash
# PreToolUse: human-gate + state helpers + soft isolation guard.
# Claude Code / Codex: exit 2 = block the tool call.
set -euo pipefail

INPUT="$(cat || true)"  # intentional: empty stdin ok
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)"  # intentional fail-soft
[[ -n "$CMD" ]] || exit 0

# Drop quoted regions so a commit message that *mentions* decide.sh is not an invocation.
# bash -c / eval with the script name still counts (checked on the raw command).
strip_quoted_regions() {
  local s="$1"
  local i=0 len=${#s} quote="" out="" c
  while [[ $i -lt $len ]]; do
    c="${s:i:1}"
    if [[ -n "$quote" ]]; then
      if [[ "$c" == "$quote" ]]; then quote=""; fi
      i=$((i + 1))
      continue
    fi
    if [[ "$c" == "'" || "$c" == '"' ]]; then
      quote="$c"
      i=$((i + 1))
      continue
    fi
    out+="$c"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

agent_role_active() {
  [[ -n "${RELENTLESS_ROLE:-}${CODEX_THREAD_ROLE:-}${CLAUDE_AGENT:-}${AGENT_NAME:-}" ]]
}

block_decision_script() {
  echo "relentless: BLOCKED — ${1}" >&2
  echo "This is expected, not a broken lock. Do not retry or try another route." >&2
  echo "The decider runs decide.sh in their own terminal, outside the agent session." >&2
  exit 2
}

if agent_role_active; then
  UNQUOTED="$(strip_quoted_regions "$CMD")"
  if printf '%s\n' "$UNQUOTED" | grep -qE '(^|[^[:alnum:]_])((\.?/)?[[:alnum:]./_-]*/)?(decide|accept-adr)\.sh([^[:alnum:]_]|$)'; then
    block_decision_script "agents do not run decide.sh or accept-adr.sh"
  fi
  if printf '%s\n' "$UNQUOTED" | grep -qE '(^|[^[:alnum:]_])((\.?/)?[[:alnum:]./_-]*/)?(userprompt-decide|human-decision)\.sh([^[:alnum:]_]|$)|relentless_record_decision|relentless_accept_adr_apply'; then
    block_decision_script "agents do not invoke the human-decision hook or its recorder"
  fi
  if printf '%s\n' "$CMD" | grep -qE '(^|[[:space:];|&])(bash|sh|eval)[[:space:]]+' \
    && printf '%s\n' "$CMD" | grep -qE '(decide|accept-adr|userprompt-decide|human-decision)\.sh|relentless_record_decision|relentless_accept_adr_apply'; then
    block_decision_script "agents do not run decide.sh or accept-adr.sh via a shell wrapper"
  fi
  if printf '%s\n' "$CMD" | grep -qE '(^|[^[:alnum:]_])((\.?/)?[[:alnum:]./_-]*/)?new-adr\.sh([^[:alnum:]_]|$)' \
    && printf '%s\n' "$CMD" | grep -qE -- '--status[=[:space:]]+["'\'']?accepted([^[:alnum:]_]|$)'; then
    block_decision_script "new-adr.sh must stay --status proposed; accepted is only via the decider"
  fi
fi

# Still enforce implementer isolation below for apply/merge when role set.

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
    echo "[relentless] BLOCKED: never bare-remove human:pending. The decider runs decide.sh in their own terminal; a refusal inside the agent session is expected." >&2
    exit 2
  fi
fi

# Soft block: same bash applying review:approved while also pushing/creating PR
if echo "$CMD" | grep -qE 'review:approved' && echo "$CMD" | grep -qE 'git\s+push|gh\s+pr\s+create'; then
  echo "[relentless] BLOCKED: do not self-approve in the implementer session. Stop at state:review." >&2
  exit 2
fi

exit 0
