#!/usr/bin/env bash
# merge-if-ready.sh — orchestrator final step after isolated review.
# Resolves merge mode (issue merge:* else config merge.default).
# auto: require CI green on head SHA + review:approved → merge commit, state:done, close issue.
# human: post 🤖 ready-to-merge and exit 0 without merging.
#
# Usage:
#   merge-if-ready.sh --repo OWNER/NAME --pr N [--issue N] [--config PATH] [--dry-run]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" PR="" ISSUE="" CONFIG="" DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") --repo OWNER/NAME --pr N [--issue N] [--config PATH] [--dry-run]"
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" && -n "$PR" ]] || { echo "need --repo --pr" >&2; exit 2; }

RESOLVED="$(resolve_config "${CONFIG:-.relentless/config.json}" "$REPO" || true)"
CONFIG="${RESOLVED:-}"

# Resolve linked issue if not provided
if [[ -z "$ISSUE" ]]; then
  ISSUE="$(gh pr view "$PR" --repo "$REPO" --json closingIssuesReferences -q '.closingIssuesReferences[0].number // empty' 2>/dev/null || true)"
  if [[ -z "$ISSUE" ]]; then
    # Fallback: parse "Closes #N" from body
    ISSUE="$(gh pr view "$PR" --repo "$REPO" --json body -q .body | grep -oiE 'closes[[:space:]]+#([0-9]+)' | head -1 | grep -oE '[0-9]+' || true)"
  fi
fi
[[ -n "$ISSUE" ]] || { echo "error: could not resolve linked issue; pass --issue N" >&2; exit 1; }

MODE="$(resolve_merge_mode "$REPO" "$ISSUE" "$CONFIG")"
echo "merge mode: $MODE (issue #$ISSUE, PR #$PR)"

# review:approved required for both paths before merge; human path still wants approval signal
LABELS="$(gh api "repos/${REPO}/issues/${ISSUE}" --jq '[.labels[].name] | join("\n")')"
if ! echo "$LABELS" | grep -Fxq "review:approved"; then
  echo "error: issue #$ISSUE missing review:approved — run isolated reviewer first" >&2
  exit 1
fi

HEAD_SHA="$(gh pr view "$PR" --repo "$REPO" --json headRefOid -q .headRefOid)"
echo "head SHA: $HEAD_SHA"

# CI green on head — prefer check runs via gh pr checks
wait_ci() {
  local tries=0
  local max="${MERGE_CI_TRIES:-36}"   # ~6 min at 10s
  local sleep_s="${MERGE_CI_SLEEP:-10}"
  while [[ $tries -lt $max ]]; do
    local out rc
    set +e
    out="$(gh pr checks "$PR" --repo "$REPO" 2>&1)"
    rc=$?
    set -e
    # exit 0 = all green; 8 = pending; other = fail
    if [[ $rc -eq 0 ]]; then
      echo "CI: green"
      return 0
    fi
    if echo "$out" | grep -qiE 'fail|error|cancelled'; then
      echo "CI: failed" >&2
      echo "$out" >&2
      return 1
    fi
    # no checks yet / pending
    if echo "$out" | grep -qiE 'no checks reported'; then
      echo "CI: no checks yet (try $((tries+1))/$max) — prefer: gh run list --branch … && gh run watch"
    else
      echo "CI: pending (try $((tries+1))/$max)"
    fi
    sleep "$sleep_s"
    tries=$((tries + 1))
  done
  echo "error: CI did not go green in time" >&2
  return 1
}

if [[ "$MODE" == "human" ]]; then
  BODY=$(cat <<COMMENT
🤖 Ready to merge (policy: human)

<!-- relentless:author=agent -->
<!-- relentless:ready-to-merge -->

PR #${PR} has \`review:approved\`. Merge mode is **human** — waiting for a person to merge.
Head: \`${HEAD_SHA}\`.
COMMENT
)
  if [[ "$DRY" -eq 1 ]]; then
    echo "dry-run: would comment ready-to-merge and wait"
    echo "$BODY"
    exit 0
  fi
  # Still require CI green before asking human? Yes — don't ping human on red CI
  wait_ci
  gh pr comment "$PR" --repo "$REPO" --body "$BODY"
  echo "Posted ready-to-merge; not merging (merge:human)."
  exit 0
fi

# auto
wait_ci

if [[ "$DRY" -eq 1 ]]; then
  echo "dry-run: would gh pr merge --merge, set state:done, close issue #$ISSUE"
  exit 0
fi

gh pr merge "$PR" --repo "$REPO" --merge --delete-branch 2>/dev/null || \
  gh pr merge "$PR" --repo "$REPO" --merge

set_issue_state "$REPO" "$ISSUE" "state:done" 1
# Close issue if still open (merge may already close via Closes #)
STATE="$(gh api "repos/${REPO}/issues/${ISSUE}" --jq .state)"
if [[ "$STATE" == "open" ]]; then
  gh issue close "$ISSUE" --repo "$REPO" --comment "🤖 Closed after auto-merge of PR #${PR}

<!-- relentless:author=agent -->
<!-- relentless:merged -->
" || true
fi

gh pr comment "$PR" --repo "$REPO" --body "🤖 Auto-merged (merge commit) per policy \`auto\`

<!-- relentless:author=agent -->
<!-- relentless:merged mode=\"auto\" -->
" 2>/dev/null || true

echo "Merged PR #${PR}; issue #${ISSUE} → state:done"
