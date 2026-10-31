#!/usr/bin/env bash
# check-milestone-outcomes.sh — warn if milestones lack a Product outcome section.
# Usage: check-milestone-outcomes.sh --repo OWNER/NAME

set -euo pipefail

REPO=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$REPO" ]] || { echo "need --repo"; exit 2; }

DRIFT=0
while IFS= read -r row; do
  title="$(jq -r '.title' <<<"$row")"
  desc="$(jq -r '.description // ""' <<<"$row")"
  if ! grep -qiE 'product outcome|## outcome' <<<"$desc"; then
    echo "DRIFT: milestone \"$title\" missing Product outcome section"
    DRIFT=1
  else
    echo "ok: $title"
  fi
done < <(gh api "repos/${REPO}/milestones?state=open&per_page=100" --jq '.[] | {title,description}')

exit "$DRIFT"
