#!/usr/bin/env bash
# create-epic.sh — create a parent epic ("understanding") issue in a milestone.
# Usage:
#   create-epic.sh --repo OWNER/NAME --title TEXT --milestone TITLE|N \
#     --outcome TEXT --exit-criterion TEXT \
#     [--understanding TEXT] [--decisions TEXT] [--plan TEXT] \
#     [--body-file PATH] [--dry-run]
#
# Doctrine: when opening an outcome milestone, the planner FIRST creates this
# epic, THEN creates sub-issues linked via add-sub-issue.sh / create-issue --parent.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" TITLE="" MILESTONE="" OUTCOME="" EXIT_CRITERION=""
UNDERSTANDING="" DECISIONS="" PLAN="" BODY_FILE="" DRY=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --title TEXT --milestone TITLE|N \\
  --outcome TEXT --exit-criterion TEXT \\
  [--understanding TEXT] [--decisions TEXT] [--plan TEXT] \\
  [--body-file PATH] [--dry-run]

Creates a parent issue labeled epic in the given milestone.
Body follows the Relentless epic/"understanding" template.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --milestone) MILESTONE="${2:-}"; shift 2 ;;
    --outcome) OUTCOME="${2:-}"; shift 2 ;;
    --exit-criterion) EXIT_CRITERION="${2:-}"; shift 2 ;;
    --understanding) UNDERSTANDING="${2:-}"; shift 2 ;;
    --decisions) DECISIONS="${2:-}"; shift 2 ;;
    --plan) PLAN="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$REPO" && -n "$TITLE" && -n "$MILESTONE" ]] || { usage; exit 2; }

if [[ -n "$BODY_FILE" ]]; then
  [[ -f "$BODY_FILE" ]] || die "body file not found: $BODY_FILE"
  BODY="$(cat "$BODY_FILE")"
else
  [[ -n "$OUTCOME" && -n "$EXIT_CRITERION" ]] || {
    echo "need --outcome and --exit-criterion (or --body-file)" >&2
    usage; exit 2
  }
  BODY=$(cat <<BODY
## Product outcome
${OUTCOME}

## Deliverable
${OUTCOME}

## Exit criterion / validates with
${EXIT_CRITERION}

## Depends on
none

## Understanding
${UNDERSTANDING:-(planner: fill in problem/context before decomposing)}

## Decisions fixed for this wave
${DECISIONS:-- (none yet; human forks → human:pending + decision-request)}

## Decomposition plan (waves)
${PLAN:-(waves / dependencies — fill before creating sub-issues)}

## Sub-issues
- (linked via add-sub-issue.sh / create-issue.sh --parent)
BODY
)
fi

# Resolve milestone title for gh --milestone
MS_TITLE="$MILESTONE"
if [[ "$MILESTONE" =~ ^[0-9]+$ ]]; then
  MS_TITLE="$(gh api "repos/${REPO}/milestones/${MILESTONE}" --jq .title)"
fi

ARGS=(issue create --repo "$REPO" --title "$TITLE" --body "$BODY"
      --label epic --label state:todo
      --milestone "$MS_TITLE")

if [[ "$DRY" -eq 1 ]]; then
  echo "[dry-run] gh ${ARGS[*]}"
  exit 0
fi

URL="$(gh "${ARGS[@]}")"
NUM="$(basename "$URL")"
echo "epic #${NUM}: ${URL}"
