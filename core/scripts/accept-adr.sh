#!/usr/bin/env bash
# accept-adr.sh — mark ADR accepted, set Decision + Decided by.
# Usage: accept-adr.sh --file PATH --option K --decider NAME [--note TEXT] [--dry-run]
set -euo pipefail
FILE="" OPTION="" DECIDER="" NOTE="" DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="${2:-}"; shift 2 ;;
    --option) OPTION="${2:-}"; shift 2 ;;
    --decider) DECIDER="${2:-}"; shift 2 ;;
    --note) NOTE="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") --file PATH --option K --decider NAME [--note TEXT]"
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -f "$FILE" && -n "$OPTION" && -n "$DECIDER" ]] || { echo "need --file --option --decider" >&2; exit 2; }

DATE="$(TZ=America/Sao_Paulo date +%Y-%m-%d)"
DECISION_LINE="Option ${OPTION} accepted on ${DATE}."
[[ -n "$NOTE" ]] && DECISION_LINE+=" ${NOTE}"

if [[ "$DRY" -eq 1 ]]; then
  echo "dry-run: accept $FILE as option $OPTION by $DECIDER"
  exit 0
fi

export ADR_FILE="$FILE" ADR_OPTION="$OPTION" ADR_DECIDER="$DECIDER" ADR_DECISION="$DECISION_LINE"
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
