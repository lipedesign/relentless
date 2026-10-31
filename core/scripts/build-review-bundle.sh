#!/usr/bin/env bash
# build-review-bundle.sh — write a reviewer-only bundle (issue AC + QA + diff without lockfiles).
# Usage: build-review-bundle.sh --repo OWNER/NAME --pr N --issue N --out PATH
set -euo pipefail
REPO="" PR="" ISSUE="" OUT="review-bundle.md"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$REPO" && -n "$PR" && -n "$ISSUE" ]] || { echo "need --repo --pr --issue" >&2; exit 2; }

ISSUE_BODY="$(gh issue view "$ISSUE" --repo "$REPO" --json body,title -q '"# \(.title)\n\n\(.body)"')"
PR_META="$(gh pr view "$PR" --repo "$REPO" --json body,title -q '"# PR: \(.title)\n\n\(.body)"')"
DIFF_RAW="$(gh pr diff "$PR" --repo "$REPO" 2>/dev/null || true)"  # intentional fail-soft
# Strip lockfile diffs (package-lock.json, pnpm-lock.yaml, yarn.lock, Cargo.lock, poetry.lock, go.sum)
DIFF_FILTERED="$(printf '%s\n' "$DIFF_RAW" | awk '
  BEGIN { skip=0 }
  /^diff --git / {
    if ($0 ~ /package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Cargo\.lock|poetry\.lock|composer\.lock|go\.sum/) skip=1;
    else skip=0;
  }
  skip==0 { print }
')"

{
  echo "# Relentless review bundle (isolated inputs ONLY)"
  echo ""
  echo "Do not include implementer chat. Reviewer is read-only."
  echo ""
  echo "## Issue (acceptance criteria)"
  echo ""
  echo "$ISSUE_BODY"
  echo ""
  echo "## PR body (for QA / dogfood section only)"
  echo ""
  echo "$PR_META"
  echo ""
  echo "## Diff (lockfiles excluded)"
  echo ""
  echo '```diff'
  echo "$DIFF_FILTERED"
  echo '```'
} >"$OUT"

echo "Wrote $OUT"
