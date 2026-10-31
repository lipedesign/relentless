#!/usr/bin/env bash
# run-isolated-review.sh — orchestrator helper: build bundle → spawn isolated reviewer
# (stdin, not argv) → parse verdict → apply-review-verdict → optional merge-if-ready.
#
# The orchestrator MUST call this (or equivalent nested spawn) itself — do NOT stop
# and wait for a human/driver to resume after state:review.
#
# Usage:
#   run-isolated-review.sh --repo OWNER/NAME --pr N --issue N \
#     [--harness claude|codex] [--workdir PATH] [--out-dir PATH] [--merge] [--dry-run]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" PR="" ISSUE="" HARNESS="" WORKDIR="." OUT_DIR="" MERGE=0 DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --harness) HARNESS="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --merge) MERGE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      sed -n '2,12p' "$0" | tr -d '#'
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" && -n "$PR" && -n "$ISSUE" ]] || { echo "need --repo --pr --issue" >&2; exit 2; }

# Infer harness from config or PATH
if [[ -z "$HARNESS" ]]; then
  if [[ -f "${WORKDIR}/.relentless/config.json" ]]; then
    HARNESS="$(jq -r '.harness // empty' "${WORKDIR}/.relentless/config.json" 2>/dev/null || true)"  # intentional fail-soft
  fi
fi
if [[ -z "$HARNESS" || "$HARNESS" == "both" ]]; then
  if command -v claude >/dev/null 2>&1; then HARNESS="claude"
  elif command -v codex >/dev/null 2>&1; then HARNESS="codex"
  else
    echo "error: set --harness claude|codex (neither claude nor codex on PATH)" >&2
    exit 1
  fi
fi

OUT_DIR="${OUT_DIR:-${WORKDIR}/.relentless/review/${PR}}"
mkdir -p "$OUT_DIR"
BUNDLE="${OUT_DIR}/review-bundle.md"
VERDICT_RAW="${OUT_DIR}/reviewer-out.md"
VERDICT_FILE="${OUT_DIR}/verdict.txt"

echo "== isolated review (harness=$HARNESS) PR #$PR issue #$ISSUE =="

"${SCRIPT_DIR}/build-review-bundle.sh" --repo "$REPO" --pr "$PR" --issue "$ISSUE" --out "$BUNDLE"
echo "bundle: $BUNDLE ($(wc -c <"$BUNDLE") bytes)"

PROMPT_FILE="${OUT_DIR}/reviewer-prompt.md"
{
  echo "You are the Relentless isolated reviewer. Read-only. Emit the structured verdict only."
  echo "Do not edit files, push, or merge. Prefer not re-running full CI."
  echo ""
  cat "$BUNDLE"
} > "$PROMPT_FILE"

if [[ "$DRY" -eq 1 ]]; then
  echo "dry-run: would spawn $HARNESS reviewer with stdin from $PROMPT_FILE"
  echo "dry-run: then apply-review-verdict + $([ "$MERGE" -eq 1 ] && echo merge-if-ready || echo 'no --merge')"
  exit 0
fi

# Pass bundle via stdin/file — NEVER "$(cat bundle)" as argv (fails on large diffs).
case "$HARNESS" in
  claude)
    # stream-json requires --verbose on Claude Code 2.1.x+
    claude -p \
      --agent relentless:reviewer \
      --allowedTools "Read,Grep,Glob,Bash(gh *)" \
      --verbose \
      --output-format stream-json \
      < "$PROMPT_FILE" \
      > "${OUT_DIR}/reviewer.stream.jsonl" 2>"${OUT_DIR}/reviewer.stderr.log" || true  # intentional fail-soft
    # Extract last assistant text if stream-json; else fall back to raw
    if [[ -s "${OUT_DIR}/reviewer.stream.jsonl" ]]; then
      jq -r 'select(.type=="assistant" or .message.content) | .message.content[]? // . | select(.type=="text")? // empty | .text // empty' \
        "${OUT_DIR}/reviewer.stream.jsonl" 2>/dev/null | tail -n +1 > "$VERDICT_RAW" || true  # intentional fail-soft
      if [[ ! -s "$VERDICT_RAW" ]]; then
        # Alternate stream shape: result field
        jq -r 'select(.type=="result") | .result // empty' "${OUT_DIR}/reviewer.stream.jsonl" 2>/dev/null > "$VERDICT_RAW" || true  # intentional fail-soft
      fi
    fi
    if [[ ! -s "$VERDICT_RAW" ]]; then
      # Non-stream fallback
      claude -p --agent relentless:reviewer --allowedTools "Read,Grep,Glob,Bash(gh *)" \
        < "$PROMPT_FILE" > "$VERDICT_RAW" 2>>"${OUT_DIR}/reviewer.stderr.log" || true  # intentional fail-soft
    fi
    ;;
  codex)
    # Prefer Write/apply_patch inside nested sessions; avoid huge shell heredocs (Codex classifier false positives).
    RELENTLESS_ROLE=reviewer codex exec \
      --sandbox read-only \
      -C "$WORKDIR" \
      < "$PROMPT_FILE" \
      > "$VERDICT_RAW" 2>"${OUT_DIR}/reviewer.stderr.log" || true  # intentional fail-soft
    ;;
  *)
    echo "error: unknown harness $HARNESS" >&2; exit 2 ;;
esac

# Parse verdict
VERDICT=""
if grep -qiE '^\s*`?approved`?\s*$|## Verdict[[:space:]]*$' "$VERDICT_RAW" 2>/dev/null; then
  if grep -qiE '`approved`|^approved$|Verdict.*approved' "$VERDICT_RAW"; then
    if grep -qiE '`changes_requested`|changes_requested' "$VERDICT_RAW" && \
       ! grep -qiE '`approved`' "$VERDICT_RAW"; then
      VERDICT="changes_requested"
    else
      # Prefer last explicit verdict token
      if grep -qoE '`?(approved|changes_requested)`?' "$VERDICT_RAW"; then
        VERDICT="$(grep -oE '`?(approved|changes_requested)`?' "$VERDICT_RAW" | tr -d '`' | tail -1)"
      fi
    fi
  fi
fi
if [[ -z "$VERDICT" ]]; then
  VERDICT="$(grep -oE '`?(approved|changes_requested)`?' "$VERDICT_RAW" 2>/dev/null | tr -d '`' | tail -1 || true)"  # intentional fail-soft
fi
if [[ -z "$VERDICT" ]]; then
  echo "error: could not parse verdict from $VERDICT_RAW" >&2
  echo "---- reviewer output (tail) ----" >&2
  tail -40 "$VERDICT_RAW" >&2 || true  # intentional fail-soft
  exit 1
fi
echo "$VERDICT" > "$VERDICT_FILE"
echo "verdict: $VERDICT"

"${SCRIPT_DIR}/apply-review-verdict.sh" --repo "$REPO" --issue "$ISSUE" --pr "$PR" --verdict "$VERDICT"

if [[ "$VERDICT" == "approved" && "$MERGE" -eq 1 ]]; then
  "${SCRIPT_DIR}/merge-if-ready.sh" --repo "$REPO" --pr "$PR" --issue "$ISSUE"
fi

echo "== isolated review done (verdict=$VERDICT) =="
