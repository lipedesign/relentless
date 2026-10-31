#!/usr/bin/env bash
# accept-adr.sh — mark ADR accepted, set Decision + Decided by.
# Agents must not run this. The decider reaches it from their own terminal
# (usually via decide.sh). A refusal inside an agent session is expected.
# Usage: accept-adr.sh --file PATH --option K --decider NAME [--note TEXT] [--dry-run]
set -euo pipefail
FILE="" OPTION="" DECIDER="" NOTE="" DRY=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/human-decision.sh
source "${SCRIPT_DIR}/lib/human-decision.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="${2:-}"; shift 2 ;;
    --option) OPTION="${2:-}"; shift 2 ;;
    --decider) DECIDER="${2:-}"; shift 2 ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") --file PATH --option K --decider NAME [--note TEXT] [--dry-run]"
      echo "Run from the decider's own terminal, outside the agent session."
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -f "$FILE" && -n "$OPTION" && -n "$DECIDER" ]] || { echo "need --file --option --decider" >&2; exit 2; }

EXACT="${SCRIPT_DIR}/accept-adr.sh --file $(printf '%q' "$FILE") --option $(printf '%q' "$OPTION") --decider $(printf '%q' "$DECIDER")"
[[ -n "$NOTE" ]] && EXACT+=" --note $(printf '%q' "$NOTE")"

relentless_refuse_if_agent "accept-adr.sh" "$EXACT"
relentless_confirm_on_tty "accept-adr.sh" "$EXACT" "Mark $(basename "$FILE") accepted as option ${OPTION}, decided by ${DECIDER}?"

if [[ "$DRY" -eq 1 ]]; then
  echo "dry-run: accept $FILE as option $OPTION by $DECIDER"
  exit 0
fi

relentless_accept_adr_apply "$FILE" "$OPTION" "$DECIDER" "$NOTE"
