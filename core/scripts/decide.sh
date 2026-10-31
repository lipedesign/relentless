#!/usr/bin/env bash
# decide.sh — record human decision; flip human:pending → human:decided; set state:todo (swap).
set -euo pipefail

REPO=""
ISSUE=""
OPTION=""
CONFIG=""
NOTE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --issue N --option K [--config PATH] [--note TEXT]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --option) OPTION="${2:-}"; shift 2 ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REPO" || -z "$ISSUE" || -z "$OPTION" ]]; then
  usage; exit 2
fi

RESOLVED="$(resolve_config "${CONFIG:-.relentless/config.json}" "$REPO" || true)"
CONFIG="${RESOLVED:-}"

DECIDER_NAME="human"
if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  DECIDER_NAME="$(jq -r '.decider.name // "human"' "$CONFIG")"
fi

BODY=$(cat <<COMMENT
☺️ Decision recorded: option ${OPTION}

<!-- relentless:author=human decider="${DECIDER_NAME}" -->
<!-- relentless:decision option="${OPTION}" -->

Chose **option ${OPTION}**${NOTE:+ — ${NOTE}}.

Labels: \`human:pending\` → \`human:decided\`.
COMMENT
)

gh issue comment "$ISSUE" --repo "$REPO" --body "$BODY"

gh issue edit "$ISSUE" --repo "$REPO" --remove-label "human:pending" 2>/dev/null || true
gh issue edit "$ISSUE" --repo "$REPO" --add-label "human:decided" || true
set_issue_state "$REPO" "$ISSUE" "state:todo"

if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  WORKER="$(jq -r '.workers.default.github // empty' "$CONFIG")"
  if [[ -n "$WORKER" ]]; then
    gh issue edit "$ISSUE" --repo "$REPO" --add-assignee "$WORKER" 2>/dev/null || true
  fi
fi

echo "Recorded option $OPTION on $REPO#$ISSUE (decider=$DECIDER_NAME)"
