#!/usr/bin/env bash
# comment-agent.sh — post an issue/PR comment with 🤖 + HTML authorship marker (avoids heredoc escaping pain).
# Usage:
#   comment-agent.sh --repo OWNER/NAME --issue N --body-file PATH
#   comment-agent.sh --repo OWNER/NAME --pr N --body-file PATH
#   echo "text" | comment-agent.sh --repo OWNER/NAME --issue N
set -euo pipefail

REPO="" ISSUE="" PR="" BODY_FILE="" MARKER="agent"
TMP=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --marker) MARKER="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") --repo OWNER/NAME (--issue N|--pr N) [--body-file PATH]"
      exit 0 ;;
    *) shift ;;
  esac
done
[[ -n "$REPO" ]] || { echo "need --repo" >&2; exit 2; }
[[ -n "$ISSUE" || -n "$PR" ]] || { echo "need --issue or --pr" >&2; exit 2; }

TMP="$(mktemp)"
cleanup() { rm -f "$TMP"; }
trap cleanup EXIT

{
  echo "🤖"
  echo ""
  echo "<!-- relentless:author=${MARKER} -->"
  echo ""
  if [[ -n "$BODY_FILE" ]]; then
    cat "$BODY_FILE"
  else
    cat
  fi
} >"$TMP"

if [[ -n "$PR" ]]; then
  gh pr comment "$PR" --repo "$REPO" --body-file "$TMP"
else
  gh issue comment "$ISSUE" --repo "$REPO" --body-file "$TMP"
fi
