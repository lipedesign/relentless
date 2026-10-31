#!/usr/bin/env bash
# apply-review-verdict.sh — after ISOLATED reviewer verdict, set labels.
# changes_requested → state:in-progress (implementer resumes).
# approved → review:approved + state:review (orchestrator then runs merge-if-ready).
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
    gh api -X POST "repos/${REPO}/issues/${ISSUE}/labels" -f "labels[]=review:approved" >/dev/null || true  # intentional fail-soft
    set_issue_state "$REPO" "$ISSUE" "state:review" 1
    if [[ -n "$PR" ]]; then
      gh pr comment "$PR" --repo "$REPO" --body "🤖 review:approved

<!-- relentless:author=agent -->
<!-- relentless:review-verdict verdict=\"approved\" -->
" || true  # intentional fail-soft
    fi
    echo "ok approved → review:approved + state:review (next: merge-if-ready.sh)"
    ;;
  changes_requested)
    gh api -X DELETE "repos/${REPO}/issues/${ISSUE}/labels/review%3Aapproved" 2>/dev/null || true  # intentional fail-soft
    set_issue_state "$REPO" "$ISSUE" "state:in-progress" 1
    if [[ -n "$PR" ]]; then
      gh pr comment "$PR" --repo "$REPO" --body "🤖 changes_requested — back to state:in-progress

<!-- relentless:author=agent -->
<!-- relentless:review-verdict verdict=\"changes_requested\" -->
" || true  # intentional fail-soft
    fi
    echo "ok changes_requested → state:in-progress"
    ;;
  *) echo "verdict must be approved|changes_requested" >&2; exit 2 ;;
esac
