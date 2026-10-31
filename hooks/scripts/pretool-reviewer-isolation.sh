#!/usr/bin/env bash
# PreToolUse: block implementer from applying review:approved / apply-review-verdict / merge-if-ready
# when RELENTLESS_ROLE=implementer (or agent name looks like implementer).
# Claude/Codex: exit 2 = block.
#
# Avoid false positives on docs/heredocs that merely *mention* approval or merge:
# strip heredoc bodies before matching, and require command-like patterns.
set -euo pipefail

INPUT="$(cat || true)"  # intentional: empty stdin ok
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)"  # intentional fail-soft
[[ -n "$CMD" ]] || exit 0

# Strip heredoc bodies so prose inside cat >file <<'EOF' … EOF does not match.
strip_heredocs() {
  awk '
    BEGIN { in_h=0; tag="" }
    {
      if (in_h) {
        close_re = "^[[:space:]]*" tag "[[:space:]]*$"
        if ($0 ~ close_re) { in_h=0; tag=""; next }
        next
      }
      if ($0 ~ /<<[-]?[[:space:]]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/) {
        line = $0
        sub(/^.*<<[-]?[[:space:]]*/, "", line)
        gsub(/['\''"]/, "", line)
        split(line, a, /[^A-Za-z0-9_]/)
        tag = a[1]
        if (tag != "") {
          in_h = 1
          keep = $0
          sub(/<<.*/, "", keep)
          if (keep ~ /[^[:space:]]/) print keep
          next
        }
      }
      print
    }
  '
}

CMD_SCAN="$(printf '%s\n' "$CMD" | strip_heredocs)"

ROLE="${RELENTLESS_ROLE:-${CODEX_THREAD_ROLE:-}}"
AGENT="${CLAUDE_AGENT:-${AGENT_NAME:-}}"

is_implementer=0
if [[ "$ROLE" == "implementer" ]] || [[ "$AGENT" == *"implementer"* ]]; then
  is_implementer=1
fi

# Label/verdict application (not merge-if-ready — orchestrator must run that)
looks_like_review_label() {
  echo "$CMD_SCAN" | grep -qE '(^|[[:space:];|&])(\./|[^[:space:]]*/)?apply-review-verdict\.sh([[:space:]]|$)' \
    || echo "$CMD_SCAN" | grep -qE 'gh[[:space:]]+(label[[:space:]]+(add|create|edit)|issue[[:space:]]+edit|pr[[:space:]]+edit)[^|;]*review:approved' \
    || echo "$CMD_SCAN" | grep -qE 'gh[[:space:]]+api[[:space:]][^|;]*review:approved'
}

looks_like_merge_if_ready() {
  echo "$CMD_SCAN" | grep -qE '(^|[[:space:];|&])(\./|[^[:space:]]*/)?merge-if-ready\.sh([[:space:]]|$)'
}

looks_like_push_or_pr_merge() {
  echo "$CMD_SCAN" | grep -qE '(^|[[:space:];|&])git[[:space:]]+push([[:space:]]|$)' \
    || echo "$CMD_SCAN" | grep -qE 'gh[[:space:]]+pr[[:space:]]+(create|merge)([[:space:]]|$)'
}

if [[ "$is_implementer" -eq 1 ]]; then
  if looks_like_review_label || looks_like_merge_if_ready || looks_like_push_or_pr_merge; then
    # Allow git push during implement (needed); only block review + merge-if-ready + gh pr merge
    if looks_like_review_label || looks_like_merge_if_ready || echo "$CMD_SCAN" | grep -qE 'gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'; then
      echo "[relentless] BLOCKED: implementer role must stop at state:review. Do not apply review labels or merge. Orchestrator spawns isolated reviewer." >&2
      exit 2
    fi
  fi
  exit 0
fi

# Non-implementer heuristic: applying review:approved AND pushing/merging in one bash
# (self-review in same session). Orchestrator-only merge-if-ready is allowed.
if looks_like_review_label && looks_like_push_or_pr_merge; then
  echo "[relentless] BLOCKED: do not self-review and push/merge in the same session. Stop at state:review; orchestrator spawns isolated reviewer then merge-if-ready." >&2
  exit 2
fi

exit 0
