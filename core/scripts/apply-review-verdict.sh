#!/usr/bin/env bash
# apply-review-verdict.sh — after ISOLATED reviewer verdict, set labels.
# changes_requested → state:in-progress (implementer resumes).
# approved → review:approved + state:review (orchestrator then runs merge-if-ready).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" ISSUE="" PR="" VERDICT="" REVIEW_OUT="" WORKDIR="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --verdict) VERDICT="${2:-}"; shift 2 ;;
    --review-out) REVIEW_OUT="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$REPO" && -n "$ISSUE" && -n "$VERDICT" ]] || { echo "need --repo --issue --verdict" >&2; exit 2; }

# Findings live in .relentless/review/<pr>/reviewer-out.md until this comment posts them.
if [[ -z "$REVIEW_OUT" && -n "$PR" ]]; then
  candidate="${WORKDIR}/.relentless/review/${PR}/reviewer-out.md"
  if [[ -f "$candidate" ]]; then
    REVIEW_OUT="$candidate"
  fi
fi

collect_findings() {
  local file="$1"
  [[ -n "$file" && -f "$file" ]] || return 0
  grep -i -E '\[(blocker|major|minor|nit)\]' "$file" || true  # intentional fail-soft: no tagged findings
}

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
      findings="$(collect_findings "$REVIEW_OUT")"
      body_file="$(mktemp)"
      {
        echo "🤖 changes_requested — back to state:in-progress"
        echo
        echo "<!-- relentless:author=agent -->"
        echo "<!-- relentless:review-verdict -->"
        if [[ -n "$findings" ]]; then
          echo
          echo "## Findings"
          printf '%s\n' "$findings"
        fi
      } >"$body_file"
      gh pr comment "$PR" --repo "$REPO" --body-file "$body_file" || true  # intentional fail-soft: labels already applied; comment is best-effort
      rm -f "$body_file"
    fi
    echo "ok changes_requested → state:in-progress"
    ;;
  *) echo "verdict must be approved|changes_requested" >&2; exit 2 ;;
esac
