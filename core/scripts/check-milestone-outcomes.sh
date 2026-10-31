#!/usr/bin/env bash
# check-milestone-outcomes.sh — warn if milestones lack Product outcome section.
# Also fails if any open issue under a milestone still has human:pending (unless --allow-pending).
# Usage: check-milestone-outcomes.sh --repo OWNER/NAME [--milestone N|TITLE] [--allow-pending]
set -euo pipefail

REPO=""
FILTER=""
ALLOW_PENDING=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --milestone) FILTER="${2:-}"; shift 2 ;;
    --allow-pending) ALLOW_PENDING=1; shift ;;
    *) shift ;;
  esac
done
[[ -n "$REPO" ]] || { echo "need --repo"; exit 2; }

DRIFT=0
PENDING_BLOCK=0

while IFS= read -r row; do
  number="$(jq -r '.number' <<<"$row")"
  title="$(jq -r '.title' <<<"$row")"
  desc="$(jq -r '.description // ""' <<<"$row")"

  if [[ -n "$FILTER" ]]; then
    if [[ "$FILTER" =~ ^[0-9]+$ ]]; then
      [[ "$number" == "$FILTER" ]] || continue
    else
      [[ "$title" == "$FILTER" ]] || continue
    fi
  fi

  if ! grep -qiE 'product outcome|## outcome' <<<"$desc"; then
    echo "DRIFT: milestone \"$title\" (#$number) missing Product outcome section"
    DRIFT=1
  else
    echo "ok: $title (#$number) outcome section"
  fi

  # Open issues with human:pending under this milestone
  pending="$(gh issue list --repo "$REPO" --milestone "$title" --state open --label "human:pending" --json number,title -q '.[] | "#\(.number) \(.title)"' 2>/dev/null || true)"
  if [[ -n "$pending" ]]; then
    echo "PENDING: milestone \"$title\" (#$number) still has human:pending issues:"
    printf '%s\n' "$pending" | while IFS= read -r line; do echo "  $line"; done
    PENDING_BLOCK=1
  else
    echo "ok: $title (#$number) no open human:pending"
  fi
done < <(gh api "repos/${REPO}/milestones?state=open&per_page=100" --jq '.[] | {number,title,description}')

if [[ "$DRIFT" -ne 0 ]]; then
  echo "result: outcome-section drift detected" >&2
fi
if [[ "$PENDING_BLOCK" -ne 0 && "$ALLOW_PENDING" -eq 0 ]]; then
  echo "result: refusing clean milestone while human:pending remains (orchestrator must not close)" >&2
  exit 1
fi
[[ "$DRIFT" -eq 0 ]] || exit 1
exit 0
