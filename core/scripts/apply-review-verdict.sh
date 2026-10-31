#!/usr/bin/env bash
# apply-review-verdict.sh — after reviewer verdict, set labels.
# Usage: apply-review-verdict.sh --repo OWNER/NAME --issue N --pr N --verdict approved|changes_requested
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" ISSUE="" PR="" VERDICT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --verdict) VERDICT="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$REPO" && -n "$ISSUE" && -n "$VERDICT" ]] || { echo "need --repo --issue --verdict" >&2; exit 2; }

case "$VERDICT" in
  approved)
    gh issue edit "$ISSUE" --repo "$REPO" --add-label "review:approved" || true
    set_issue_state "$REPO" "$ISSUE" "state:review"
    if [[ -n "$PR" ]]; then
      gh pr comment "$PR" --repo "$REPO" --body "🤖 review:approved

<!-- relentless:author=agent -->
<!-- relentless:review-verdict verdict=\"approved\" -->
" || true
    fi
    ;;
  changes_requested)
    gh issue edit "$ISSUE" --repo "$REPO" --remove-label "review:approved" 2>/dev/null || true
    set_issue_state "$REPO" "$ISSUE" "state:review"
    ;;
  *) echo "verdict must be approved|changes_requested" >&2; exit 2 ;;
esac
echo "Applied verdict=$VERDICT on $REPO#$ISSUE"
