#!/usr/bin/env bash
# wait-ci.sh — bounded foreground poll for PR checks.
# Does not start a run watcher. A watcher blocks until the run ends, so agents
# background it, and headless Claude then stops the session when that task is
# still running after the turn (CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS).
#
# One invocation polls until --timeout-sec (default 30), then returns:
#   0  CI green
#   1  CI failed (a test or other real job ran and failed)
#   2  usage error
#   3  CI pending — re-run this script in the foreground on the next step
#   4  CI unavailable (quota) — billing, spending limit, minutes exhausted,
#      startup_failure, or a completed run whose jobs executed no steps.
#      Not a test failure. Do not retry this script in a loop.
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
      echo "Exit 0 green, 1 failed, 3 pending (re-run in the foreground), 4 CI unavailable (quota)."
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

quota_exit() {
  echo "CI unavailable (quota)" >&2
  exit 4
}

# True when text mentions Actions billing / quota rather than a test assertion.
text_is_quota() {
  grep -qiE 'billing|spending[[:space:]]+limit|minutes[[:space:]]+exhausted|out of minutes|minute quota'
}

# Inspect a completed non-success run. Returns 0 when it is quota, 1 otherwise.
# A jobs-API miss is not quota: merge-if-ready must not run local checks unless
# this script classified the run.
run_is_quota() {
  local id="$1"
  local view="" sha="" blob="" ann="" job_id="" rc=0
  set +e
  view="$(gh run view "$id" --repo "$REPO" --json jobs,headSha,conclusion 2>/dev/null)"
  rc=$?
  set -e
  if [[ $rc -ne 0 || -z "$view" ]]; then
    return 1
  fi
  set +e
  jq -e '
    (.jobs // []) as $j
    | if ($j | length) == 0 then true
      elif any($j[]; .conclusion == "startup_failure") then true
      elif all($j[]; ((.steps // []) | length) == 0) then true
      else false end
  ' <<<"$view" >/dev/null
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    return 0
  fi
  sha="$(jq -r '.headSha // empty' <<<"$view" 2>/dev/null || true)"  # intentional fail-soft: missing head SHA skips check-run text
  blob=""
  if [[ -n "$sha" ]]; then
    set +e
    blob="$(gh api "repos/${REPO}/commits/${sha}/check-runs" 2>/dev/null)"
    set -e
  fi
  while IFS= read -r job_id; do
    [[ "$job_id" =~ ^[0-9]+$ ]] || continue
    set +e
    ann="$(gh api "repos/${REPO}/check-runs/${job_id}/annotations" 2>/dev/null)"
    rc=$?
    set -e
    if [[ $rc -eq 0 && -n "$ann" ]]; then
      blob+="$ann"$'\n'
    fi
  done < <(jq -r '.jobs[]?.databaseId // empty' <<<"$view" 2>/dev/null || true)  # intentional fail-soft: no job ids means no annotations to read
  if printf '%s\n' "$blob" | text_is_quota; then
    return 0
  fi
  return 1
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
      startup_failure)
        quota_exit
        ;;
      failure|cancelled|timed_out|action_required)
        if run_is_quota "$run_id"; then
          quota_exit
        fi
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
  # Quota before the generic fail match: "startup_failure" contains "fail".
  if printf '%s\n' "$out" | grep -qiE 'startup_failure' || printf '%s\n' "$out" | text_is_quota; then
    quota_exit
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
