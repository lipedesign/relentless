#!/usr/bin/env bash
# close-epic.sh — close an epic only when every sub-issue is closed.
# Usage: close-epic.sh --repo OWNER/NAME --epic N [--force]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" EPIC="" FORCE=0

usage() {
  echo "Usage: $(basename "$0") --repo OWNER/NAME --epic N [--force]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --epic) EPIC="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$REPO" && -n "$EPIC" ]] || { usage; exit 2; }

LABELS="$(gh api "repos/${REPO}/issues/${EPIC}" --jq '[.labels[].name] | join(",")')"
echo "$LABELS" | grep -qw epic || die "#${EPIC} is not labeled epic"

OPEN_SUBS="$(gh api "repos/${REPO}/issues/${EPIC}/sub_issues?per_page=100" \
  --jq '[.[] | select(.state=="open") | "#\(.number) \(.title)"] | .[]' 2>/dev/null || true)"  # intentional fail-soft

if [[ -n "$OPEN_SUBS" && "$FORCE" -eq 0 ]]; then
  echo "refuse: epic #${EPIC} still has open sub-issues:" >&2
  printf '%s\n' "$OPEN_SUBS" | while IFS= read -r line; do echo "  $line" >&2; done
  exit 1
fi

gh issue close "$EPIC" --repo "$REPO" --reason completed
# Best-effort state:done
"${SCRIPT_DIR}/set-state.sh" --repo "$REPO" --issue "$EPIC" --state "done" 2>/dev/null || true  # intentional fail-soft
echo "closed epic #${EPIC}"
