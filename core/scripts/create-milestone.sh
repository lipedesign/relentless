#!/usr/bin/env bash
# create-milestone.sh — create a product-outcome milestone (requires outcome + exit criterion).
# Usage:
#   create-milestone.sh --repo OWNER/NAME --title TEXT --outcome TEXT --exit-criterion TEXT [--due YYYY-MM-DD]
set -euo pipefail

REPO="" TITLE="" OUTCOME="" EXIT_CRITERION="" DUE="" OUT_OF_SCOPE=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --title TEXT --outcome TEXT --exit-criterion TEXT [--due YYYY-MM-DD] [--out-of-scope TEXT]

Creates a GitHub milestone whose description follows the Relentless product-outcome template.
Refuses engineering-only titles that look like chore buckets (heuristic warning only).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    --exit-criterion) EXIT_CRITERION="${2:-}"; shift 2 ;;
    --due) DUE="${2:-}"; shift 2 ;;
    --out-of-scope) OUT_OF_SCOPE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$REPO" && -n "$TITLE" && -n "$OUTCOME" && -n "$EXIT_CRITERION" ]] || { usage; exit 2; }

if echo "$TITLE" | grep -qiE '^(sprint |chore|misc|backend chores|refactor)'; then
  echo "warn: title looks like a work bucket, not a product outcome — prefer \"User can …\"" >&2
fi

DESC=$(cat <<DESC
## Product outcome
${OUTCOME}

## Success signals / exit criterion
${EXIT_CRITERION}

## Out of scope
${OUT_OF_SCOPE:-- (none listed)}
DESC
)

ARGS=(--method POST "repos/${REPO}/milestones" -f "title=${TITLE}" -f "description=${DESC}" -f state=open)
if [[ -n "$DUE" ]]; then
  ARGS+=(-f "due_on=${DUE}T23:59:59Z")
fi

gh api "${ARGS[@]}" --jq '"milestone #\(.number): \(.html_url)"'
