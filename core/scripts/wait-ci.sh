#!/usr/bin/env bash
# wait-ci.sh — wait until PR checks are green (handles "no checks reported" race).
# Usage: wait-ci.sh --repo OWNER/NAME --pr N [--timeout-sec 600]
set -euo pipefail
REPO="" PR="" TIMEOUT=600
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --timeout-sec) TIMEOUT="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$REPO" && -n "$PR" ]] || { echo "need --repo --pr" >&2; exit 2; }

BRANCH="$(gh pr view "$PR" --repo "$REPO" --json headRefName -q .headRefName)"
deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
  # Prefer run watch once a run exists
  RUN="$(gh run list --repo "$REPO" --branch "$BRANCH" --limit 1 --json databaseId,status -q '.[0].databaseId // empty' 2>/dev/null || true)"  # intentional fail-soft
  if [[ -n "$RUN" ]]; then
    echo "watching run $RUN on $BRANCH"
    if gh run watch "$RUN" --repo "$REPO" --exit-status; then
      echo "CI green"
      exit 0
    else
      echo "CI failed" >&2
      exit 1
    fi
  fi
  set +e
  out="$(gh pr checks "$PR" --repo "$REPO" 2>&1)"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then echo "CI green"; exit 0; fi
  if echo "$out" | grep -qiE 'fail|error|cancelled'; then echo "$out" >&2; exit 1; fi
  echo "waiting for checks… (${out:0:80})"
  sleep 8
done
echo "timeout waiting for CI" >&2
exit 1
