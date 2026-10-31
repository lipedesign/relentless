#!/usr/bin/env bash
# wait-ci.sh — bounded foreground poll for PR checks.
# Does not start a run watcher. A watcher blocks until the run ends, so agents
# background it, and headless Claude then stops the session when that task is
# still running after the turn (CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS).
#
# One invocation polls until --timeout-sec (default 30), then returns:
#   0  CI green
#   1  CI failed
#   2  usage error
#   3  CI pending — re-run this script in the foreground on the next step
#
# Usage: wait-ci.sh --repo OWNER/NAME --pr N [--timeout-sec 30]
set -euo pipefail
REPO="" PR="" TIMEOUT=30
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR="${2:-}"; shift 2 ;;
    --timeout-sec) TIMEOUT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") --repo OWNER/NAME --pr N [--timeout-sec 30]"
      echo "Exit 0 green, 1 failed, 3 pending (re-run in the foreground)."
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" && -n "$PR" ]] || { echo "need --repo --pr" >&2; exit 2; }
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || { echo "timeout must be a positive integer" >&2; exit 2; }

INTERVAL=5
run_id=""
status=""
BRANCH="$(gh pr view "$PR" --repo "$REPO" --json headRefName --jq .headRefName)"
deadline=$((SECONDS + TIMEOUT))

pending() {
  local detail="${1:-}"
  echo "CI: pending${detail} — re-run wait-ci.sh in the foreground on the next step (exit 3)."
  exit 3
}

while (( SECONDS < deadline )); do
  raw="$(gh run list --repo "$REPO" --branch "$BRANCH" --limit 1 --json databaseId,status,conclusion 2>/dev/null || true)"  # intentional fail-soft: no run yet is pending, not a failure
  run_id="" status="" conclusion=""
  if [[ -n "$raw" && "$raw" != "null" ]]; then
    run_id="$(jq -r '.[0].databaseId // empty' <<<"$raw" 2>/dev/null || true)"  # intentional fail-soft
    status="$(jq -r '.[0].status // empty' <<<"$raw" 2>/dev/null || true)"  # intentional fail-soft
    conclusion="$(jq -r '.[0].conclusion // empty' <<<"$raw" 2>/dev/null || true)"  # intentional fail-soft
  fi

  if [[ -n "$run_id" && "$status" == "completed" ]]; then
    case "$conclusion" in
      success)
        echo "CI green (run $run_id)"
        exit 0
        ;;
      failure|cancelled|timed_out|startup_failure|action_required)
        echo "CI failed (run $run_id conclusion=$conclusion)" >&2
        exit 1
        ;;
    esac
  fi

  set +e
  out="$(gh pr checks "$PR" --repo "$REPO" 2>&1)"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "CI green"
    exit 0
  fi
  if echo "$out" | grep -qiE 'fail|error|cancelled'; then
    echo "CI failed" >&2
    echo "$out" >&2
    exit 1
  fi

  if [[ -n "$run_id" ]]; then
    echo "CI: pending (run $run_id ${status:-unknown}) — still in this foreground poll"
  else
    echo "CI: pending — no checks yet (${out:0:80})"
  fi

  remaining=$((deadline - SECONDS))
  if (( remaining <= 0 )); then
    break
  fi
  if (( remaining < INTERVAL )); then
    sleep "$remaining"
  else
    sleep "$INTERVAL"
  fi
done

if [[ -n "${run_id:-}" ]]; then
  pending " (run $run_id ${status:-unknown})"
fi
pending ""
