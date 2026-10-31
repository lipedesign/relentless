#!/usr/bin/env bash
# set-state.sh — set exactly one state:* (one GET + one PATCH; quiet by default).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" ISSUE="" STATE="" VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --state) STATE="${2:-}"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") --repo OWNER/NAME --issue N --state todo|in-progress|blocked|review|done [--verbose]"
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" && -n "$ISSUE" && -n "$STATE" ]] || { echo "need --repo --issue --state" >&2; exit 2; }
case "$STATE" in
  state:*) LABEL="$STATE" ;;
  *) LABEL="state:${STATE}" ;;
esac
if [[ "$VERBOSE" -eq 1 ]]; then
  set_issue_state "$REPO" "$ISSUE" "$LABEL" 0
else
  set_issue_state "$REPO" "$ISSUE" "$LABEL" 1
  echo "ok ${REPO}#${ISSUE} → ${LABEL}"
fi
