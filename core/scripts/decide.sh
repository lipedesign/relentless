#!/usr/bin/env bash
# decide.sh — record a human decision; flip human:pending → human:decided; set state:todo.
# Durable choices: create or link an ADR (docs/decisions/adr/NNNN-slug.md).
#
# Agents must not run this. Codex has no TTY (including the interactive TUI), so a
# refusal here is expected. The decider runs it in their own terminal. On Claude,
# typing /decide is handled by hooks/scripts/userprompt-decide.sh instead.
#
# Usage:
#   decide.sh --repo OWNER/NAME --issue N --option K [--note TEXT] [--config PATH] \
#     [--adr PATH | --create-adr --title T --slug S] [--workdir PATH] [--no-adr]
set -euo pipefail

REPO="" ISSUE="" OPTION="" CONFIG="" NOTE="" ADR="" CREATE_ADR=0 TITLE="" SLUG="" WORKDIR="." NO_ADR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/human-decision.sh
source "${SCRIPT_DIR}/lib/human-decision.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --issue N --option K [--note TEXT] [--config PATH]
       [--adr PATH | --create-adr --title T --slug S] [--workdir PATH] [--no-adr]

For durable architectural/product decisions, pass --adr or --create-adr so the
comment links the ADR and Status becomes accepted.

Run this from the decider's own terminal, outside the agent session. A refusal
inside Codex or an agent role is expected, not a broken lock.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --option) OPTION="${2:-}"; shift 2 ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    --adr) ADR="${2:-}"; shift 2 ;;
    --create-adr) CREATE_ADR=1; shift ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --slug) SLUG="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --no-adr) NO_ADR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REPO" || -z "$ISSUE" || -z "$OPTION" ]]; then
  usage
  exit 2
fi

EXACT="${SCRIPT_DIR}/decide.sh --repo $(printf '%q' "$REPO") --issue $(printf '%q' "$ISSUE") --option $(printf '%q' "$OPTION")"
[[ -n "$NOTE" ]] && EXACT+=" --note $(printf '%q' "$NOTE")"
[[ -n "$ADR" ]] && EXACT+=" --adr $(printf '%q' "$ADR")"
if [[ "$CREATE_ADR" -eq 1 ]]; then
  EXACT+=" --create-adr --title $(printf '%q' "$TITLE") --slug $(printf '%q' "$SLUG")"
fi
[[ "$NO_ADR" -eq 1 ]] && EXACT+=" --no-adr"
[[ "$WORKDIR" != "." ]] && EXACT+=" --workdir $(printf '%q' "$WORKDIR")"
[[ -n "$CONFIG" ]] && EXACT+=" --config $(printf '%q' "$CONFIG")"

relentless_refuse_if_agent "decide.sh" "$EXACT"
relentless_confirm_on_tty "decide.sh" "$EXACT" "Record option ${OPTION} on ${REPO}#${ISSUE} as a human decision?"
relentless_record_decision
