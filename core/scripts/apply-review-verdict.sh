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

# Full headRefOid of the PR that was reviewed. Merge compares this exact value.
HEAD_SHA=""
if [[ -n "$PR" ]]; then
  set +e
  # intentional: stderr is replaced by the refusal below when the head SHA cannot be read
  HEAD_SHA="$(gh pr view "$PR" --repo "$REPO" --json headRefOid -q .headRefOid 2>/dev/null)"
  rc=$?
  set -e
  HEAD_SHA="${HEAD_SHA//$'\r'/}"
  HEAD_SHA="${HEAD_SHA//$'\n'/}"
  if [[ $rc -ne 0 || ! "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo "error: could not read the full head SHA for PR #${PR}; not recording a review verdict" >&2
    exit 1
  fi
fi

post_verdict_comment() {
  local title="$1" with_findings="${2:-0}" findings="" body_file="" rc=0
  [[ -n "$PR" ]] || return 0
  if [[ "$with_findings" -eq 1 ]]; then
    findings="$(collect_findings "$REVIEW_OUT")"
  fi
  body_file="$(mktemp)"
  {
    echo "$title"
    echo
    echo "<!-- relentless:author=agent -->"
    echo "<!-- relentless:review-verdict verdict=\"${VERDICT}\" sha=\"${HEAD_SHA}\" -->"
    if [[ -n "$findings" ]]; then
      echo
      echo "## Findings"
      printf '%s\n' "$findings"
    fi
  } >"$body_file"
  set +e
  gh pr comment "$PR" --repo "$REPO" --body-file "$body_file"
  rc=$?
  set -e
  rm -f "$body_file"
  return "$rc"
}

# The SHA lives in the comment. Labels change only after that comment is posted.
# A failed comment exits before any label write, so review:approved cannot exist without a SHA.
case "$VERDICT" in
  approved)
    if ! post_verdict_comment "🤖 review:approved" 0; then
      echo "error: could not post the review verdict on PR #${PR}. review:approved was not applied." >&2
      exit 1
    fi
    gh api -X POST "repos/${REPO}/issues/${ISSUE}/labels" -f "labels[]=review:approved" >/dev/null || true  # intentional fail-soft: comment already holds the SHA
    set_issue_state "$REPO" "$ISSUE" "state:review" 1
    echo "ok approved → review:approved + state:review (next: merge-if-ready.sh)"
    ;;
  changes_requested)
    if ! post_verdict_comment "🤖 changes_requested — back to state:in-progress" 1; then
      echo "error: could not post the review verdict on PR #${PR}. No labels were changed." >&2
      exit 1
    fi
    gh api -X DELETE "repos/${REPO}/issues/${ISSUE}/labels/review%3Aapproved" 2>/dev/null || true  # intentional fail-soft: label may already be absent
    set_issue_state "$REPO" "$ISSUE" "state:in-progress" 1
    echo "ok changes_requested → state:in-progress"
    ;;
  *) echo "verdict must be approved|changes_requested" >&2; exit 2 ;;
esac
