#!/usr/bin/env bash
# create-issue.sh — create an issue with Relentless body template; resolve milestone by number or title.
# Usage:
#   create-issue.sh --repo OWNER/NAME --title TEXT [--milestone N|TITLE] [--body-file PATH] [--label L]...
set -euo pipefail

REPO=""
TITLE=""
MILESTONE=""
BODY_FILE=""
LABELS=()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_BODY="${SCRIPT_DIR}/../templates/issue-body.md"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --title TEXT [options]

  --milestone N|TITLE   Milestone number (e.g. 1) or exact title
  --body-file PATH      Issue body (default: core/templates/issue-body.md)
  --label NAME          Repeatable; default includes state:todo
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --milestone) MILESTONE="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --label) LABELS+=("${2:-}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$REPO" && -n "$TITLE" ]] || { usage; exit 2; }
BODY_FILE="${BODY_FILE:-$DEFAULT_BODY}"
[[ -f "$BODY_FILE" ]] || { echo "error: body file not found: $BODY_FILE" >&2; exit 1; }

if [[ ${#LABELS[@]} -eq 0 ]]; then
  LABELS=(state:todo)
fi

MS_ARGS=()
if [[ -n "$MILESTONE" ]]; then
  MS_TITLE=""
  if [[ "$MILESTONE" =~ ^[0-9]+$ ]]; then
    # gh issue create --milestone wants title; resolve number → title
    MS_TITLE="$(gh api "repos/${REPO}/milestones/${MILESTONE}" --jq .title 2>/dev/null || true)"
    if [[ -z "$MS_TITLE" ]]; then
      echo "error: milestone number $MILESTONE not found in $REPO" >&2
      exit 1
    fi
    echo "milestone: #$MILESTONE → \"$MS_TITLE\""
  else
    MS_TITLE="$MILESTONE"
  fi
  MS_ARGS=(--milestone "$MS_TITLE")
fi

LABEL_ARGS=()
for l in "${LABELS[@]}"; do
  LABEL_ARGS+=(--label "$l")
done

URL="$(gh issue create --repo "$REPO" --title "$TITLE" --body-file "$BODY_FILE" "${MS_ARGS[@]}" "${LABEL_ARGS[@]}")"
echo "$URL"
