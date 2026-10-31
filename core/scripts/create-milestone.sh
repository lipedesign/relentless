#!/usr/bin/env bash
# create-milestone.sh — create a product-outcome milestone (Theme: subtitle + exit criterion).
# Usage:
#   create-milestone.sh --repo OWNER/NAME --title TEXT --outcome TEXT --exit-criterion TEXT \
#     [--deliverable TEXT] [--validates-with TEXT] [--depends-on TEXT] [--due YYYY-MM-DD] [--out-of-scope TEXT]
set -euo pipefail

REPO="" TITLE="" OUTCOME="" EXIT_CRITERION="" DUE="" OUT_OF_SCOPE=""
DELIVERABLE="" VALIDATES="" DEPENDS=""

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --title TEXT --outcome TEXT --exit-criterion TEXT \\
  [--deliverable TEXT] [--validates-with TEXT] [--depends-on TEXT] [--due YYYY-MM-DD] [--out-of-scope TEXT]

Title rule: "Theme: subtitle" (e.g. "Auth: user can sign in"). Prefer product outcomes over chore buckets.
After creating the milestone, the planner MUST create-epic.sh (understanding parent) BEFORE sub-issues.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    --exit-criterion) EXIT_CRITERION="${2:-}"; shift 2 ;;
    --deliverable) DELIVERABLE="${2:-}"; shift 2 ;;
    --validates-with) VALIDATES="${2:-}"; shift 2 ;;
    --depends-on) DEPENDS="${2:-}"; shift 2 ;;
    --due) DUE="${2:-}"; shift 2 ;;
    --out-of-scope) OUT_OF_SCOPE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$REPO" && -n "$TITLE" && -n "$OUTCOME" && -n "$EXIT_CRITERION" ]] || { usage; exit 2; }

if echo "$TITLE" | grep -qiE '^(sprint |chore|misc|backend chores|refactor)'; then
  echo "warn: title looks like a work bucket — prefer \"Theme: subtitle\" / \"User can …\"" >&2
fi
if ! echo "$TITLE" | grep -q ':'; then
  echo "warn: prefer \"Theme: subtitle\" title shape (lohra-ts / apollo)" >&2
fi

DESC=$(cat <<DESC
## Product outcome
${OUTCOME}

## Deliverable
${DELIVERABLE:-(same as outcome unless planner narrows)}

## Validates with
${VALIDATES:-${EXIT_CRITERION}}

## Depends on
${DEPENDS:-none}

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
echo "next: create-epic.sh --repo ${REPO} --milestone \"${TITLE}\" --title \"…\" --outcome \"…\" --exit-criterion \"…\"" >&2
