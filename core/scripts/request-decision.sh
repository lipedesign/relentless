#!/usr/bin/env bash
# request-decision.sh — post decision-request comment; human:pending + state:blocked (swap, never stack).
set -euo pipefail

REPO=""
ISSUE=""
BODY_FILE=""
CONFIG=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --issue N --body-file PATH [--config PATH]

Body file must follow core/templates/decision-request.md.
Config defaults to <git-root>/.relentless/config.json when omitted.
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
[[ -f "$BODY_FILE" ]] || { echo "error: body file not found: $BODY_FILE" >&2; exit 1; }

if ! grep -q 'relentless:decision-request' "$BODY_FILE"; then
  echo "warn: body missing <!-- relentless:decision-request --> marker" >&2
fi
if ! grep -qE '^### [0-9]+\.' "$BODY_FILE"; then
  echo "warn: body may be missing numbered options (### N.)" >&2
fi

RESOLVED="$(resolve_config "${CONFIG:-.relentless/config.json}" "$REPO" || true)"  # intentional fail-soft
CONFIG="${RESOLVED:-}"

gh issue comment "$ISSUE" --repo "$REPO" --body-file "$BODY_FILE"

gh issue edit "$ISSUE" --repo "$REPO" --add-label "human:pending" || true  # intentional fail-soft
# Exactly one state:* — blocked
set_issue_state "$REPO" "$ISSUE" "state:blocked"

if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  DECIDER_GH="$(jq -r '.decider.github // empty' "$CONFIG")"
  if [[ -n "$DECIDER_GH" ]]; then
    gh issue edit "$ISSUE" --repo "$REPO" --add-assignee "$DECIDER_GH" 2>/dev/null || true  # intentional fail-soft
  fi
fi

if ! grep -qiE 'docs/decisions/adr/|Proposed ADR' "$BODY_FILE"; then
  echo "tip: for durable architecture/product choices, draft a proposed ADR (new-adr.sh) and mention it in the request body" >&2
fi

echo "Decision requested on $REPO#$ISSUE (human:pending + state:blocked; other state:* removed)"
