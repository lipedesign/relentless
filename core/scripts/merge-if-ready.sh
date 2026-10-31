#!/usr/bin/env bash
# merge-if-ready.sh — orchestrator final step after isolated review.
# Resolves merge mode (issue merge:* else config merge.default).
# auto: require CI green on head SHA + review:approved → merge commit, state:done, close issue.
# human: post 🤖 ready-to-merge and exit 0 without merging.
#
# Before deleting the merged head branch, retargets open PRs that used it as base
# (avoids GitHub closing dependents with base_ref_deleted).
#
# Usage:
#   merge-if-ready.sh --repo OWNER/NAME --pr N [--issue N] [--config PATH] [--dry-run]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" PR="" ISSUE="" CONFIG="" DRY=0 CLEANUP_WT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    --cleanup-worktree) CLEANUP_WT="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") --repo OWNER/NAME --pr N [--issue N] [--config PATH] [--cleanup-worktree PATH] [--dry-run]"
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" && -n "$PR" ]] || { echo "need --repo --pr" >&2; exit 2; }

RESOLVED="$(resolve_config "${CONFIG:-.relentless/config.json}" "$REPO" || true)"  # intentional fail-soft
CONFIG="${RESOLVED:-}"

if [[ -z "$ISSUE" ]]; then
  ISSUE="$(gh pr view "$PR" --repo "$REPO" --json closingIssuesReferences -q '.closingIssuesReferences[0].number // empty' 2>/dev/null || true)"  # intentional fail-soft
  if [[ -z "$ISSUE" ]]; then
    ISSUE="$(gh pr view "$PR" --repo "$REPO" --json body -q .body | grep -oiE 'closes[[:space:]]+#([0-9]+)' | head -1 | grep -oE '[0-9]+' || true)"  # intentional fail-soft
  fi
fi
[[ -n "$ISSUE" ]] || { echo "error: could not resolve linked issue; pass --issue N" >&2; exit 1; }

MODE="$(resolve_merge_mode "$REPO" "$ISSUE" "$CONFIG")"
echo "merge mode: $MODE (issue #$ISSUE, PR #$PR)"

LABELS="$(gh api "repos/${REPO}/issues/${ISSUE}" --jq '[.labels[].name] | join("\n")')"
if ! echo "$LABELS" | grep -Fxq "review:approved"; then
  echo "error: issue #$ISSUE missing review:approved — run isolated reviewer first" >&2
  exit 1
fi

PR_JSON="$(gh pr view "$PR" --repo "$REPO" --json headRefOid,headRefName,baseRefName,state)"
HEAD_SHA="$(jq -r .headRefOid <<<"$PR_JSON")"
HEAD_REF="$(jq -r .headRefName <<<"$PR_JSON")"
BASE_REF="$(jq -r .baseRefName <<<"$PR_JSON")"
echo "head SHA: $HEAD_SHA (branch=$HEAD_REF → $BASE_REF)"

# Accepted ADRs introduced by this PR need a prior decision-request on the linked issue.
# Agents can write "Decided by" themselves; GitHub cannot tell that account from the human.
check_accepted_adr_decision_requests() {
  local files rc f b64 text status comments crc
  set +e
  files="$(gh api --paginate "repos/${REPO}/pulls/${PR}/files" --jq '.[].filename' 2>/dev/null)"
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    # intentional fail-soft: a files-API outage must not block every merge; the guard runs when the list is available
    echo "warn: could not list PR files; skipped accepted-ADR decision-request check" >&2
    return 0
  fi
  while IFS= read -r f; do
    [[ "$f" == docs/decisions/adr/*.md ]] || continue
    set +e
    b64="$(gh api "repos/${REPO}/contents/${f}?ref=${HEAD_SHA}" --jq .content 2>/dev/null)"
    rc=$?
    set -e
    if [[ $rc -ne 0 || -z "$b64" ]]; then
      echo "error: could not read ${f} at ${HEAD_SHA}; refusing merge (accepted-ADR check)" >&2
      exit 1
    fi
    text="$(printf '%s' "$b64" | tr -d '[:space:]' | base64 -d 2>/dev/null || true)"
    status="$(printf '%s\n' "$text" | sed -n 's/^- \*\*Status:\*\*[[:space:]]*//p' | head -1 | tr '[:upper:]' '[:lower:]' | tr -d '\r')"
    [[ "$status" == "accepted" ]] || continue
    set +e
    comments="$(gh api --paginate "repos/${REPO}/issues/${ISSUE}/comments" --jq '.[].body' 2>/dev/null)"
    crc=$?
    set -e
    if [[ $crc -ne 0 ]]; then
      echo "error: issue #${ISSUE} comments unreadable; refusing merge while ${f} is accepted" >&2
      exit 1
    fi
    if ! printf '%s\n' "$comments" | grep -q 'relentless:decision-request'; then
      echo "error: ${f} is accepted in this PR but issue #${ISSUE} has no decision-request comment (<!-- relentless:decision-request -->). Refusing merge." >&2
      echo "Agents must not accept ADRs. The decider runs decide.sh in their own terminal, outside the agent session." >&2
      exit 1
    fi
  done <<<"$files"
  return 0
}

check_accepted_adr_decision_requests

wait_ci() {
  local tries=0
  local max="${MERGE_CI_TRIES:-36}"
  local sleep_s="${MERGE_CI_SLEEP:-10}"
  while [[ $tries -lt $max ]]; do
    local out rc
    set +e
    out="$(gh pr checks "$PR" --repo "$REPO" 2>&1)"
    rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
      echo "CI: green"
      return 0
    fi
    if echo "$out" | grep -qiE 'fail|error|cancelled'; then
      echo "CI: failed" >&2
      echo "$out" >&2
      return 1
    fi
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

# Retarget open PRs whose base is HEAD_REF onto new_base. Returns 1 if any remain.
retarget_dependents() {
  local head="$1" new_base="$2"
  local deps dep_num failed=0
  deps="$(gh pr list --repo "$REPO" --state open --base "$head" --json number -q '.[].number' 2>/dev/null || true)"  # intentional fail-soft
  if [[ -z "$deps" ]]; then
    echo "stacked PRs: none open with base=$head"
    return 0
  fi
  echo "stacked PRs: retargeting onto $new_base before deleting $head:"
  while IFS= read -r dep_num; do
    [[ -n "$dep_num" ]] || continue
    echo "  PR #$dep_num: base $head → $new_base"
    if [[ "$DRY" -eq 1 ]]; then
      echo "  dry-run: would gh pr edit $dep_num --base $new_base"
      continue
    fi
    if gh pr edit "$dep_num" --repo "$REPO" --base "$new_base"; then
      echo "  retargeted PR #$dep_num"
    else
      echo "warn: failed to retarget PR #$dep_num" >&2
      failed=1
    fi
  done <<<"$deps"
  return "$failed"
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
  wait_ci
  gh pr comment "$PR" --repo "$REPO" --body "$BODY"
  echo "Posted ready-to-merge; not merging (merge:human)."
  exit 0
fi

wait_ci

if [[ "$DRY" -eq 1 ]]; then
  echo "dry-run: would retarget dependents of $HEAD_REF → $BASE_REF, then merge + delete-branch (if safe), state:done, close #$ISSUE"
  retarget_dependents "$HEAD_REF" "$BASE_REF" || true  # intentional fail-soft
  exit 0
fi

# Retarget FIRST so --delete-branch cannot close dependents with base_ref_deleted
retarget_dependents "$HEAD_REF" "$BASE_REF" || true  # intentional fail-soft
remaining="$(gh pr list --repo "$REPO" --state open --base "$HEAD_REF" --json number -q '.[].number' 2>/dev/null || true)"  # intentional fail-soft
if [[ -z "$remaining" ]]; then
  gh pr merge "$PR" --repo "$REPO" --merge --delete-branch 2>/dev/null || \
    gh pr merge "$PR" --repo "$REPO" --merge
else
  echo "warn: dependents still base=$HEAD_REF ($remaining) — merging WITHOUT --delete-branch" >&2
  gh pr merge "$PR" --repo "$REPO" --merge
fi

set_issue_state "$REPO" "$ISSUE" "state:done" 1
STATE="$(gh api "repos/${REPO}/issues/${ISSUE}" --jq .state)"
if [[ "$STATE" == "open" ]]; then
  gh issue close "$ISSUE" --repo "$REPO" --comment "🤖 Closed after auto-merge of PR #${PR}

<!-- relentless:author=agent -->
<!-- relentless:merged -->
" || true  # intentional fail-soft
fi

gh pr comment "$PR" --repo "$REPO" --body "🤖 Auto-merged (merge commit) per policy \`auto\`

<!-- relentless:author=agent -->
<!-- relentless:merged mode=\"auto\" -->
" 2>/dev/null || true  # intentional fail-soft

echo "Merged PR #${PR}; issue #${ISSUE} → state:done"

if [[ -n "$CLEANUP_WT" ]]; then
  if [[ "$DRY" -eq 1 ]]; then
    echo "dry-run: would worktree-cleanup --path $CLEANUP_WT"
  else
    "${SCRIPT_DIR}/worktree-cleanup.sh" --path "$CLEANUP_WT" --repo "$REPO" || echo "warn: worktree cleanup failed for $CLEANUP_WT" >&2
  fi
fi
