#!/usr/bin/env bash
# check-milestone-pending.sh — exit 1 if milestone has any open human:pending issue.
# Usage: check-milestone-pending.sh --repo OWNER/NAME --milestone N|TITLE
set -euo pipefail

REPO=""
MILESTONE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --milestone) MILESTONE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") --repo OWNER/NAME --milestone N|TITLE"
      exit 0 ;;
    *) shift ;;
  esac
done
[[ -n "$REPO" && -n "$MILESTONE" ]] || { echo "need --repo and --milestone" >&2; exit 2; }

TITLE="$MILESTONE"
if [[ "$MILESTONE" =~ ^[0-9]+$ ]]; then
  TITLE="$(gh api "repos/${REPO}/milestones/${MILESTONE}" --jq .title)"
fi

pending="$(gh issue list --repo "$REPO" --milestone "$TITLE" --state open --label "human:pending" --json number,title)"
count="$(jq 'length' <<<"$pending")"
if [[ "$count" -gt 0 ]]; then
  echo "error: milestone \"$TITLE\" has $count open human:pending issue(s) — do not close" >&2
  jq -r '.[] | "  #\(.number) \(.title)"' <<<"$pending" >&2
  exit 1
fi
echo "ok: milestone \"$TITLE\" has no open human:pending"
