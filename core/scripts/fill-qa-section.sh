#!/usr/bin/env bash
# fill-qa-section.sh — post QA as a 🤖 PR comment with <!-- relentless:qa --> (avoids fragile PR-body splice).
# Also optionally patches the PR body QA section if --patch-body is set.
# Usage: fill-qa-section.sh --repo OWNER/NAME --pr N --body-file PATH [--patch-body]
set -euo pipefail
REPO="" PR="" BODY_FILE="" PATCH=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --patch-body) PATCH=1; shift ;;
    *) shift ;;
  esac
done
[[ -n "$REPO" && -n "$PR" && -n "$BODY_FILE" && -f "$BODY_FILE" ]] || { echo "need --repo --pr --body-file" >&2; exit 2; }

TMP="$(mktemp)"
{
  echo "🤖 QA / dogfood result"
  echo ""
  echo "<!-- relentless:author=agent -->"
  echo "<!-- relentless:qa -->"
  echo ""
  cat "$BODY_FILE"
} >"$TMP"
gh pr comment "$PR" --repo "$REPO" --body-file "$TMP"
rm -f "$TMP"

if [[ "$PATCH" -eq 1 ]]; then
  # Best-effort: replace ## QA / dogfood result section in PR body
  BODY="$(gh pr view "$PR" --repo "$REPO" --json body -q .body)"
  QA="$(cat "$BODY_FILE")"
  NEW="$(printf '%s\n' "$BODY" | awk -v qa="$QA" '
    BEGIN { inqa=0 }
    /^## QA \/ dogfood result/ { print; print qa; inqa=1; next }
    /^## / && inqa { inqa=0 }
    inqa { next }
    { print }
  ')"
  gh pr edit "$PR" --repo "$REPO" --body "$NEW" >/dev/null || true  # intentional fail-soft
fi
echo "ok QA posted on PR #$PR"
