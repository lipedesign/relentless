#!/usr/bin/env bash
# set-state.sh — set exactly one state:* label on an issue (swap, never stack).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO=""
ISSUE=""
STATE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --state) STATE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") --repo OWNER/NAME --issue N --state todo|in-progress|blocked|review|done"
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" && -n "$ISSUE" && -n "$STATE" ]] || { echo "need --repo --issue --state" >&2; exit 2; }
case "$STATE" in
  state:*) LABEL="$STATE" ;;
  *) LABEL="state:${STATE}" ;;
esac
set_issue_state "$REPO" "$ISSUE" "$LABEL"
echo "Set $REPO#$ISSUE → $LABEL"
