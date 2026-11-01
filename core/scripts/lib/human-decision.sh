#!/usr/bin/env bash
# human-decision.sh — shared decision recording. Sourcing defines functions only.
#
# Executables (decide.sh, accept-adr.sh, new-adr.sh --status accepted) enforce the
# human gate before they call these functions. There is no env var, token, or
# marker file that skips the gate: an agent shares the OS user and could forge one.
#
# Claude's UserPromptSubmit hook calls relentless_record_decision directly because
# the typed /decide prompt is the human action. Codex has no such hook and no TTY
# inside the agent, so the human runs decide.sh from their own terminal.
# shellcheck shell=bash

relentless_agent_why() {
  local -a bits=()
  [[ -n "${RELENTLESS_ROLE:-}" ]] && bits+=("RELENTLESS_ROLE=${RELENTLESS_ROLE}")
  [[ -n "${CODEX_THREAD_ROLE:-}" ]] && bits+=("CODEX_THREAD_ROLE=${CODEX_THREAD_ROLE}")
  [[ -n "${CLAUDE_AGENT:-}" ]] && bits+=("CLAUDE_AGENT=${CLAUDE_AGENT}")
  [[ -n "${AGENT_NAME:-}" ]] && bits+=("AGENT_NAME=${AGENT_NAME}")
  if [[ ${#bits[@]} -eq 0 ]]; then
    return 1
  fi
  local IFS=", "
  printf '%s' "${bits[*]}"
}

# what, why, exact command
relentless_decision_refusal() {
  local what="$1" why="$2" exact="$3"
  cat >&2 <<EOF
relentless: ${what} was not run (${why}).
This is expected, not a broken lock. Do not retry inside the agent session and do not try another route.
Codex commands have no TTY, even in the interactive TUI, so the human cannot confirm /decide from inside a Codex session.
decide must be run by the human in their own terminal, outside the agent session:
  ${exact}
EOF
  exit 1
}

relentless_refuse_if_agent() {
  local what="$1" exact="$2" why=""
  if why="$(relentless_agent_why)"; then
    relentless_decision_refusal "$what" "agent role is set: ${why}" "$exact"
  fi
}

# Prompt on /dev/tty. A missing controlling terminal is the Codex case, not a failure to diagnose.
relentless_confirm_on_tty() {
  local what="$1" exact="$2" prompt="$3" answer=""
  if ! printf '%s\nType yes to confirm: ' "$prompt" >/dev/tty 2>/dev/null; then
    relentless_decision_refusal "$what" "no terminal on /dev/tty" "$exact"
  fi
  if ! IFS= read -r answer </dev/tty; then
    relentless_decision_refusal "$what" "could not read a confirmation from /dev/tty" "$exact"
  fi
  answer="${answer//$'\r'/}"
  if [[ "$answer" != "yes" ]]; then
    echo "relentless: confirmation was not yes; nothing was recorded." >&2
    exit 1
  fi
}

relentless_accept_adr_apply() {
  local file="$1" option="$2" decider="$3" note="${4:-}"
  local date decision_line
  date="$(TZ=America/Sao_Paulo date +%Y-%m-%d)"
  decision_line="Decided ${date} (new decision): option ${option}."
  [[ -n "$note" ]] && decision_line+=" ${note}"
  ADR_FILE="$file" ADR_OPTION="$option" ADR_DECIDER="$decider" ADR_DECISION="$decision_line" \
    python3 << 'PY'
import os, re
path = os.environ["ADR_FILE"]
decider = os.environ["ADR_DECIDER"]
decision = os.environ["ADR_DECISION"]
text = open(path, encoding="utf-8").read()
text = re.sub(r"(\*\*Status:\*\*\s*)[^\n]+", r"\1accepted", text, count=1)
text = re.sub(r"(\*\*Decided by:\*\*\s*)[^\n]+", r"\1" + decider, text, count=1)

def repl(m):
    return m.group(1) + decision + "\n\n"

text2, n = re.subn(r"(## Decision\n)(.*?)(?=\n## |\Z)", repl, text, count=1, flags=re.S)
if n == 0:
    text2 = text + "\n## Decision\n" + decision + "\n"
open(path, "w", encoding="utf-8").write(text2)
print(path)
PY
}

# Uses globals set by decide.sh or the UserPromptSubmit hook:
# REPO ISSUE OPTION NOTE WORKDIR ADR CREATE_ADR TITLE SLUG NO_ADR
# CONFIG is optional. common.sh must already be sourced (resolve_config, set_issue_state).
relentless_record_decision() {
  local resolved="" decider_name="human" rel_adr="" adr_line="" body worker
  if resolved="$(resolve_config "${CONFIG:-.relentless/config.json}" "$REPO" 2>/dev/null)"; then
    CONFIG="$resolved"
  else
    CONFIG=""
  fi
  if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
    decider_name="$(jq -r '.decider.name // "human"' "$CONFIG")"
  fi
  DECIDER_NAME="$decider_name"

  WORKDIR="$(cd "$WORKDIR" && pwd)"
  if [[ "${CREATE_ADR:-0}" -eq 1 && "${NO_ADR:-0}" -eq 0 ]]; then
    [[ -n "${TITLE:-}" && -n "${SLUG:-}" ]] || { echo "error: --create-adr needs --title and --slug" >&2; exit 2; }
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    ADR="$("${script_dir}/new-adr.sh" --workdir "$WORKDIR" --title "$TITLE" --slug "$SLUG" --issue "$ISSUE" --status proposed)"
  fi

  if [[ -n "${ADR:-}" && "${NO_ADR:-0}" -eq 0 ]]; then
    if [[ ! -f "$ADR" && -f "${WORKDIR}/${ADR}" ]]; then
      ADR="${WORKDIR}/${ADR}"
    fi
    if [[ ! -f "$ADR" ]]; then
      echo "error: ADR file not found: $ADR" >&2
      exit 1
    fi
    relentless_accept_adr_apply "$ADR" "$OPTION" "$decider_name" "${NOTE:-}"
    rel_adr="$ADR"
    case "$ADR" in
      "$WORKDIR"/*) rel_adr="${ADR#"$WORKDIR"/}" ;;
    esac
    adr_line="
**ADR:** \`${rel_adr}\` (status → accepted, option ${OPTION})."
  fi

  body=$(cat <<COMMENT
☺️ Decision recorded: option ${OPTION}

<!-- relentless:author=human decider="${decider_name}" -->
<!-- relentless:decision option="${OPTION}"${rel_adr:+ adr="${rel_adr}"} -->

Chose **option ${OPTION}**${NOTE:+ — ${NOTE}}.
${adr_line}

Labels: \`human:pending\` → \`human:decided\`.
COMMENT
)

  gh issue comment "$ISSUE" --repo "$REPO" --body "$body"

  if ! gh issue edit "$ISSUE" --repo "$REPO" --remove-label "human:pending" 2>/dev/null; then
    echo "warn: could not remove human:pending (may already be absent)" >&2
  fi
  if ! gh issue edit "$ISSUE" --repo "$REPO" --add-label "human:decided"; then
    echo "error: failed to add human:decided" >&2
    exit 1
  fi
  set_issue_state "$REPO" "$ISSUE" "state:todo"

  if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
    worker="$(jq -r '.workers.default.github // empty' "$CONFIG")"
    if [[ -n "$worker" ]]; then
      if ! gh issue edit "$ISSUE" --repo "$REPO" --add-assignee "$worker" 2>/dev/null; then
        echo "warn: could not assign worker $worker" >&2
      fi
    fi
  fi

  echo "Recorded option ${OPTION} on ${REPO}#${ISSUE} (decider=${decider_name}${ADR:+; adr=$ADR})"
}
