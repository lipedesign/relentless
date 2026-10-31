#!/usr/bin/env bash
# decide.sh — record a human decision on an issue and flip human:pending → human:decided.
# Usage:
#   decide.sh --repo OWNER/NAME --issue N --option K [--config PATH] [--note TEXT]

set -euo pipefail

REPO=""
ISSUE=""
OPTION=""
CONFIG=".relentless/config.json"
NOTE=""

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

DECIDER_NAME="human"
DECIDER_GH=""
if [[ -f "$CONFIG" ]]; then
  DECIDER_NAME="$(jq -r '.decider.name // "human"' "$CONFIG")"
  DECIDER_GH="$(jq -r '.decider.github // empty' "$CONFIG")"
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

# Flip labels: remove pending, add decided; clear state:blocked if present → state:todo
gh issue edit "$ISSUE" --repo "$REPO" --remove-label "human:pending" 2>/dev/null || true
gh issue edit "$ISSUE" --repo "$REPO" --add-label "human:decided" || true
gh issue edit "$ISSUE" --repo "$REPO" --remove-label "state:blocked" 2>/dev/null || true
gh issue edit "$ISSUE" --repo "$REPO" --add-label "state:todo" 2>/dev/null || true

# Reassign to default worker if configured
WORKER="$(jq -r '.workers.default.github // empty' "$CONFIG" 2>/dev/null || true)"
if [[ -n "$WORKER" ]]; then
  gh issue edit "$ISSUE" --repo "$REPO" --add-assignee "$WORKER" 2>/dev/null || true
fi

echo "Recorded option $OPTION on $REPO#$ISSUE (decider=$DECIDER_NAME)"
