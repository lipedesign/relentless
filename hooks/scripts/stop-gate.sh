#!/usr/bin/env bash
# stop-gate.sh — Claude Code Stop hook (generic Relentless).
# Blocks ending a turn when:
#   1. Relentless worktree (or RELENTLESS_ROLE=implementer) has uncommitted changes
#   2. Project tests fail. Command is .relentless/config.json key checks.test when
#      that string is non-empty; otherwise `npm test` if package.json has
#      scripts.test. No command skips this gate. The run is capped (default 120s,
#      override RELENTLESS_STOP_GATE_TEST_TIMEOUT). hooks/hooks.json Stop timeout
#      stays above that cap so a timeout can still print its reason.
#   3. Current branch matches <type>/<n>-<slug>, issue #n is state:in-progress,
#      and there is neither a remote tracking push nor an open PR for the branch
#   4. Open PR for this branch exists but body lacks a ## QA (or QA / dogfood) section
# No product "prova"/tsc gates — those stay in the consumer repo if desired.
#
# Contract: JSON event on stdin (cwd, stop_hook_active); exit 2 blocks stop; exit 0 allows.
# stop_hook_active true exits 0 immediately so a blocked stop cannot loop.
# Fail-open on missing git/gh/jq with a stderr warning (except clear worktree dirt).
set -euo pipefail

INPUT="$(cat 2>/dev/null || true)"  # intentional: empty stdin ok

warn() { printf 'stop-gate: %s\n' "$*" >&2; }
deny() { printf 'stop-gate: BLOCKED — %s\n' "$*" >&2; exit 2; }

trim_ws() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# checks.test when set; else npm test when package.json has scripts.test.
# Prints the command, or nothing when this gate should be skipped.
resolve_test_command() {
  local cfg cmd pkg_test
  cmd=""
  cfg="${TOP}/.relentless/config.json"
  if [[ -f "$cfg" ]] && command -v jq >/dev/null 2>&1; then
    cmd="$(jq -r '.checks.test // empty' "$cfg" 2>/dev/null || true)"  # intentional fail-soft
  fi
  if [[ "$cmd" == "null" ]]; then
    cmd=""
  fi
  cmd="$(trim_ws "$cmd")"
  if [[ -n "$cmd" ]]; then
    printf '%s' "$cmd"
    return 0
  fi
  if [[ -f "${TOP}/package.json" ]] && command -v jq >/dev/null 2>&1; then
    pkg_test="$(jq -r '.scripts.test // empty' "${TOP}/package.json" 2>/dev/null || true)"  # intentional fail-soft
    if [[ "$pkg_test" == "null" ]]; then
      pkg_test=""
    fi
    pkg_test="$(trim_ws "$pkg_test")"
    if [[ -n "$pkg_test" ]]; then
      printf '%s' "npm test"
      return 0
    fi
  fi
  return 0
}

# Exit 2 when the resolved test command fails or exceeds the cap.
run_project_tests() {
  local test_cmd secs rc log tail_out pid elapsed
  test_cmd="$(resolve_test_command)"
  if [[ -z "$test_cmd" ]]; then
    return 0
  fi
  secs="${RELENTLESS_STOP_GATE_TEST_TIMEOUT:-120}"
  if [[ ! "$secs" =~ ^[1-9][0-9]*$ ]]; then
    secs=120
  fi
  log="$(mktemp)"
  rc=0
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 5 "$secs" bash -c "$test_cmd" >"$log" 2>&1 || rc=$?
  else
    # coreutils timeout is absent; still bound the wait so a hung suite cannot stall the hook.
    bash -c "$test_cmd" >"$log" 2>&1 &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
      if [[ "$elapsed" -ge "$secs" ]]; then
        kill "$pid" 2>/dev/null || true  # intentional fail-soft: process may have just exited
        wait "$pid" 2>/dev/null || true  # intentional fail-soft: reap the timed-out child
        rm -f "$log"
        deny "project tests timed out after ${secs}s (${test_cmd})"
      fi
      sleep 1
      elapsed=$((elapsed + 1))
    done
    wait "$pid" || rc=$?
  fi
  if [[ "$rc" -eq 124 ]]; then
    rm -f "$log"
    deny "project tests timed out after ${secs}s (${test_cmd})"
  fi
  if [[ "$rc" -ne 0 ]]; then
    tail_out="$(tail -n 20 "$log")"
    rm -f "$log"
    deny "project tests failed (exit ${rc}): ${test_cmd}
${tail_out}"
  fi
  rm -f "$log"
}

STOP_HOOK_ACTIVE="false"
CWD=""
if command -v jq >/dev/null 2>&1 && [[ -n "$INPUT" ]]; then
  STOP_HOOK_ACTIVE="$(printf '%s' "$INPUT" | jq -r 'if .stop_hook_active == true then "true" else "false" end' 2>/dev/null || echo false)"  # intentional fail-soft
  CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"  # intentional fail-soft
fi
# Already continuing from a blocked stop. Exit 0 so this hook cannot loop.
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then
  exit 0
fi

CWD="${CWD:-${CLAUDE_PROJECT_DIR:-${RELENTLESS_WORKTREE:-$(pwd)}}}"
cd "$CWD" 2>/dev/null || cd "${RELENTLESS_WORKTREE:-.}" 2>/dev/null || true  # intentional fail-soft

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  warn "not a git repo at $CWD; allowing stop"
  exit 0
fi
TOP="$(git rev-parse --show-toplevel)"
cd "$TOP"

IN_WT=0
if [[ -f "$TOP/.relentless/worktree.json" ]] || [[ "${RELENTLESS_ROLE:-}" == "implementer" ]] || [[ -n "${RELENTLESS_WORKTREE:-}" ]]; then
  IN_WT=1
fi
# Also treat linked worktrees (not the primary) as worktrees
if git rev-parse --git-dir >/dev/null 2>&1; then
  common="$(git rev-parse --git-common-dir 2>/dev/null || true)"  # intentional fail-soft
  gdir="$(git rev-parse --git-dir 2>/dev/null || true)"  # intentional fail-soft
  if [[ -n "$common" && -n "$gdir" && "$common" != "$gdir" && "$gdir" != ".git" ]]; then
    IN_WT=1
  fi
fi

# Ignore Relentless marker dir + .scratch probe
DIRTY="$(git status --porcelain 2>/dev/null | grep -Ev '(^\?\? \.relentless(/|$)|^\?\? \.scratch$)' || true)"  # intentional fail-soft
if [[ "$IN_WT" -eq 1 && -n "$DIRTY" ]]; then
  deny "uncommitted changes in worktree $TOP — commit a checkpoint before ending the turn
$(echo "$DIRTY" | head -20)"
fi

run_project_tests

BRANCH="$(git branch --show-current 2>/dev/null || true)"  # intentional fail-soft
if [[ ! "$BRANCH" =~ ^(feat|fix|chore|docs|refactor|test|ci|perf|build|style)/([0-9]+)-([a-z0-9][a-z0-9-]*)$ ]]; then
  # Outside Relentless branch pattern — no further issue/PR gates
  exit 0
fi
ISSUE="${BASH_REMATCH[2]}"

# Resolve repo
REPO=""
if command -v gh >/dev/null 2>&1; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"  # intentional fail-soft
fi
if [[ -z "$REPO" ]]; then
  warn "cannot resolve OWNER/NAME; skipping issue/PR stop checks"
  exit 0
fi

# Remote tracking / push?
HAS_REMOTE=0
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  HAS_REMOTE=1
elif git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  HAS_REMOTE=1
fi

PR_JSON=""
PR_BODY=""
PR_NUM=""
if command -v gh >/dev/null 2>&1; then
  PR_JSON="$(gh pr list --repo "$REPO" --head "$BRANCH" --state open --json number,body -q '.[0] // empty' 2>/dev/null || true)"  # intentional fail-soft
  if [[ -n "$PR_JSON" && "$PR_JSON" != "null" ]]; then
    PR_NUM="$(printf '%s' "$PR_JSON" | jq -r '.number // empty' 2>/dev/null || true)"  # intentional fail-soft
    PR_BODY="$(printf '%s' "$PR_JSON" | jq -r '.body // empty' 2>/dev/null || true)"  # intentional fail-soft
  fi
fi

# Issue state:in-progress without pushed branch/PR
LABELS=""
if command -v gh >/dev/null 2>&1; then
  LABELS="$(gh api "repos/${REPO}/issues/${ISSUE}" --jq '[.labels[].name] | join("\n")' 2>/dev/null || true)"  # intentional fail-soft
fi
if echo "$LABELS" | grep -Fxq "state:in-progress"; then
  if [[ "$HAS_REMOTE" -eq 0 && -z "$PR_NUM" ]]; then
    deny "issue #${ISSUE} is state:in-progress on ${BRANCH} but nothing is pushed and no open PR — push the branch (lock) or open a PR before ending the turn"
  fi
fi

# Open PR without QA section
if [[ -n "$PR_NUM" ]]; then
  if ! printf '%s' "$PR_BODY" | grep -qiE '^##[[:space:]]*(QA|QA[[:space:]]*/[[:space:]]*dogfood|Dogfood)'; then
    deny "PR #${PR_NUM} is open but has no ## QA (or QA / dogfood) section — fill via fill-qa-section.sh / qa agent before ending the turn"
  fi
fi

exit 0
