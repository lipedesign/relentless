#!/usr/bin/env bash
# request-decision.sh — post decision-request comment and apply human:pending + state:blocked.
# The comment body MUST follow core/templates/decision-request.md (pass via --body-file).
#
# Usage:
#   request-decision.sh --repo OWNER/NAME --issue N --body-file PATH [--config PATH]

set -euo pipefail

REPO=""
ISSUE=""
BODY_FILE=""
CONFIG=".relentless/config.json"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --issue N --body-file PATH [--config PATH]

Body file must follow core/templates/decision-request.md (question, numbered options
with pros/cons, recommendation).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --body-file) BODY_FILE="${2:-}"; shift 2 ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REPO" || -z "$ISSUE" || -z "$BODY_FILE" ]]; then
  usage; exit 2
fi
if [[ ! -f "$BODY_FILE" ]]; then
  echo "error: body file not found: $BODY_FILE" >&2
  exit 1
fi

# Soft check that template markers exist
if ! grep -q 'relentless:decision-request' "$BODY_FILE"; then
  echo "warn: body missing <!-- relentless:decision-request --> marker" >&2
fi
if ! grep -qE '^### [0-9]+\.' "$BODY_FILE"; then
  echo "warn: body may be missing numbered options (### N.)" >&2
fi

gh issue comment "$ISSUE" --repo "$REPO" --body-file "$BODY_FILE"

gh issue edit "$ISSUE" --repo "$REPO" --add-label "human:pending" || true
gh issue edit "$ISSUE" --repo "$REPO" --add-label "state:blocked" || true
# Remove in-progress if present
gh issue edit "$ISSUE" --repo "$REPO" --remove-label "state:in-progress" 2>/dev/null || true

DECIDER_GH="$(jq -r '.decider.github // empty' "$CONFIG" 2>/dev/null || true)"
if [[ -n "$DECIDER_GH" ]]; then
  gh issue edit "$ISSUE" --repo "$REPO" --add-assignee "$DECIDER_GH" 2>/dev/null || true
fi

echo "Decision requested on $REPO#$ISSUE (human:pending + state:blocked)"
