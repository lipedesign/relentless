#!/usr/bin/env bash
# decide.sh — record human decision; flip human:pending → human:decided; set state:todo.
# Durable choices: create or link an ADR (docs/decisions/adr/NNNN-slug.md).
#
# Usage:
#   decide.sh --repo OWNER/NAME --issue N --option K [--note TEXT] [--config PATH] \
#     [--adr PATH | --create-adr --title T --slug S] [--workdir PATH] [--no-adr]
set -euo pipefail

REPO="" ISSUE="" OPTION="" CONFIG="" NOTE="" ADR="" CREATE_ADR=0 TITLE="" SLUG="" WORKDIR="." NO_ADR=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME --issue N --option K [--note TEXT] [--config PATH]
       [--adr PATH | --create-adr --title T --slug S] [--workdir PATH] [--no-adr]

For durable architectural/product decisions, pass --adr or --create-adr so the
comment links the ADR and Status becomes accepted.
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
  usage; exit 2
fi

RESOLVED=""
if RESOLVED="$(resolve_config "${CONFIG:-.relentless/config.json}" "$REPO" 2>/dev/null)"; then
  :
else
  RESOLVED=""
fi
CONFIG="${RESOLVED:-}"

DECIDER_NAME="human"
if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  DECIDER_NAME="$(jq -r '.decider.name // "human"' "$CONFIG")"
fi

WORKDIR="$(cd "$WORKDIR" && pwd)"
REL_ADR=""

if [[ "$CREATE_ADR" -eq 1 && "$NO_ADR" -eq 0 ]]; then
  [[ -n "$TITLE" && -n "$SLUG" ]] || { echo "error: --create-adr needs --title and --slug" >&2; exit 2; }
  ADR="$("${SCRIPT_DIR}/new-adr.sh" --workdir "$WORKDIR" --title "$TITLE" --slug "$SLUG" --issue "$ISSUE" --status proposed)"
fi

ADR_LINE=""
if [[ -n "$ADR" && "$NO_ADR" -eq 0 ]]; then
  if [[ ! -f "$ADR" && -f "${WORKDIR}/${ADR}" ]]; then
    ADR="${WORKDIR}/${ADR}"
  fi
  if [[ ! -f "$ADR" ]]; then
    echo "error: ADR file not found: $ADR" >&2
    exit 1
  fi
  "${SCRIPT_DIR}/accept-adr.sh" --file "$ADR" --option "$OPTION" --decider "$DECIDER_NAME" --note "${NOTE:-}"
  REL_ADR="$ADR"
  case "$ADR" in
    "$WORKDIR"/*) REL_ADR="${ADR#"$WORKDIR"/}" ;;
  esac
  ADR_LINE="
**ADR:** \`${REL_ADR}\` (status → accepted, option ${OPTION})."
fi

BODY=$(cat <<COMMENT
☺️ Decision recorded: option ${OPTION}

<!-- relentless:author=human decider="${DECIDER_NAME}" -->
<!-- relentless:decision option="${OPTION}"${REL_ADR:+ adr="${REL_ADR}"} -->

Chose **option ${OPTION}**${NOTE:+ — ${NOTE}}.
${ADR_LINE}

Labels: \`human:pending\` → \`human:decided\`.
COMMENT
)

gh issue comment "$ISSUE" --repo "$REPO" --body "$BODY"

if ! gh issue edit "$ISSUE" --repo "$REPO" --remove-label "human:pending" 2>/dev/null; then
  echo "warn: could not remove human:pending (may already be absent)" >&2
fi
if ! gh issue edit "$ISSUE" --repo "$REPO" --add-label "human:decided"; then
  echo "error: failed to add human:decided" >&2
  exit 1
fi
set_issue_state "$REPO" "$ISSUE" "state:todo"

if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  WORKER="$(jq -r '.workers.default.github // empty' "$CONFIG")"
  if [[ -n "$WORKER" ]]; then
    if ! gh issue edit "$ISSUE" --repo "$REPO" --add-assignee "$WORKER" 2>/dev/null; then
      echo "warn: could not assign worker $WORKER" >&2
    fi
  fi
fi

echo "Recorded option $OPTION on $REPO#$ISSUE (decider=$DECIDER_NAME${ADR:+; adr=$ADR})"
