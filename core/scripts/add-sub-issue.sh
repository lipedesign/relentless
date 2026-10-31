#!/usr/bin/env bash
# add-sub-issue.sh — link an existing issue as a GitHub native sub-issue of a parent.
# Usage:
#   add-sub-issue.sh --repo OWNER/NAME --parent N --child N [--replace-parent]
#
# Uses REST POST /repos/{o}/{r}/issues/{parent}/sub_issues with sub_issue_id =
# the child's database id (not the issue number). gh has no --parent flag.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" PARENT="" CHILD="" REPLACE=0

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --parent N --child N [--replace-parent]

Links CHILD as a native GitHub sub-issue of PARENT.
sub_issue_id must be the child's database id (integer), fetched via the Issues API.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --parent) PARENT="${2:-}"; shift 2 ;;
    --child) CHILD="${2:-}"; shift 2 ;;
    --replace-parent) REPLACE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$REPO" && -n "$PARENT" && -n "$CHILD" ]] || { usage; exit 2; }
[[ "$PARENT" =~ ^[0-9]+$ && "$CHILD" =~ ^[0-9]+$ ]] || die "parent and child must be issue numbers"

CHILD_ID="$(gh api "repos/${REPO}/issues/${CHILD}" --jq .id)"
[[ -n "$CHILD_ID" && "$CHILD_ID" != "null" ]] || die "could not resolve database id for #${CHILD}"

PAYLOAD="$(jq -n --argjson id "$CHILD_ID" --argjson replace "$REPLACE" \
  '{sub_issue_id: $id} + (if $replace == 1 then {replace_parent: true} else {} end)')"

# IMPORTANT: use --input so sub_issue_id stays an integer (-f would stringify → 422)
echo "$PAYLOAD" | gh api "repos/${REPO}/issues/${PARENT}/sub_issues" -X POST --input - \
  --jq '"linked #\(.number // empty) as sub-issue of #'"${PARENT}"'"' >/dev/null

# Inherit parent milestone if child has none
PARENT_MS="$(gh api "repos/${REPO}/issues/${PARENT}" --jq '.milestone.number // empty')"
CHILD_MS="$(gh api "repos/${REPO}/issues/${CHILD}" --jq '.milestone.number // empty')"
if [[ -n "$PARENT_MS" && -z "$CHILD_MS" ]]; then
  gh api -X PATCH "repos/${REPO}/issues/${CHILD}" -f "milestone=${PARENT_MS}" >/dev/null
  echo "inherited milestone #${PARENT_MS} onto #${CHILD}"
fi

echo "ok: #${CHILD} (id=${CHILD_ID}) is now a sub-issue of #${PARENT}"
