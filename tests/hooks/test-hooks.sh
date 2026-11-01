#!/usr/bin/env bash
# Regression tests for relentless PreToolUse hooks.
# Each case pipes a Bash tool event and expects exit 2 (block) or 0 (allow).
# Every dangerous command has a nearby legitimate command that must still pass.
#
# Usage: bash tests/hooks/test-hooks.sh
#    or: RELENTLESS_ROOT=/path/to/relentless bash tests/hooks/test-hooks.sh
set -uo pipefail
ROOT="${RELENTLESS_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Parent checkout is main; the hook cwd is a nested repo on feat/1-x.
# `cd ..` therefore lands on main, and `../other` is a second main checkout.
git -C "$TMP" init -q -b main outer
git -C "$TMP/outer" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$TMP" init -q -b main outer/other
git -C "$TMP/outer/other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$TMP" init -q -b main outer/repo
git -C "$TMP/outer/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$TMP/outer/repo" branch feat/1-x
mkdir -p "$TMP/outer/repo/sub"
REPO="$TMP/outer/repo"

PASS=0
FAIL=0
run() { # hook branch env expected cmd
  local hook="$1" br="$2" envs="$3" exp="$4" cmd="$5" got
  git -C "$REPO" checkout -q "$br"
  got=$(
    cd "$REPO" && jq -n --arg c "$cmd" '{tool_input:{command:$c}}' |
      env $envs bash "$ROOT/hooks/scripts/$hook" >/dev/null 2>&1
    echo $?
  )
  if [[ "$got" == "$exp" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %-32s [%s, %s] expected %s got %s: %s\n' \
      "$hook" "$br" "${envs:-no-role}" "$exp" "$got" "$cmd"
  fi
}

M=pretool-protect-main.sh
R=pretool-reviewer-isolation.sh
G=pretool-gh-workflow.sh
N="X=1"

# force-push: block every spelling, allow normal push and branch names that merely say "force"
run $M feat/1-x "$N" 2 'git push -f'
run $M feat/1-x "$N" 2 'git push --force'
run $M feat/1-x "$N" 2 'git push --force origin feat/1-x'
run $M feat/1-x "$N" 2 'git push --force-with-lease'
run $M feat/1-x "$N" 2 'git push --force-with-lease=refs/heads/feat/1-x'
run $M feat/1-x "$N" 2 'git push origin +feat/1-x'
run $M feat/1-x "$N" 2 'git push origin feat/1-x --force'
run $M feat/1-x "$N" 2 'git -C ../other push -f'
run $M feat/1-x "$N" 0 'git push -u origin feat/1-x'
run $M feat/1-x "$N" 0 'git push origin feat/1-x'
run $M feat/1-x "$N" 0 'git push origin feat/1-x-force-fix'
run $M feat/1-x "$N" 0 'git commit -m "git push --force is mentioned only in the message"'

# main: block commit/push targeting main, including another path; allow mentions
run $M main "$N" 2 'git commit -m x'
run $M main "$N" 2 'git push'
run $M feat/1-x "$N" 2 'git push origin HEAD:main'
run $M feat/1-x "$N" 2 'git -C ../other checkout main && git -C ../other commit -m x'
run $M feat/1-x "$N" 2 'git -C ../other commit -m x'
run $M feat/1-x "$N" 2 'cd .. && git commit -m x'
run $M feat/1-x "$N" 2 'cd .. && git push'
run $M feat/1-x "$N" 0 'git commit -m "fix: mention main branch in docs"'
run $M feat/1-x "$N" 0 'git log main..HEAD'
run $M feat/1-x "$N" 0 'cd .. && git status'
run $M feat/1-x "$N" 0 'cd sub && git commit -m wip'
run $M feat/1-x "$N" 0 'git -C sub commit -m wip'
run $M feat/1-x "$N" 0 'git -C ../other log -1'

# destructive
run $M feat/1-x "$N" 2 'git reset --hard origin/main'
run $M feat/1-x "$N" 2 'git clean -fdx'
run $M feat/1-x "$N" 2 'git -C ../other reset --hard'
run $M feat/1-x "$N" 0 'git reset --soft HEAD~1'
run $M feat/1-x "$N" 0 'git clean -n'

# reviewer isolation
run $R feat/1-x "RELENTLESS_ROLE=implementer" 2 'gh pr edit 3 --add-label review:approved'
run $R feat/1-x "RELENTLESS_ROLE=implementer" 2 './core/scripts/merge-if-ready.sh --pr 3'
run $R feat/1-x "RELENTLESS_ROLE=implementer" 2 'gh pr merge 3 --squash'
run $R feat/1-x "RELENTLESS_ROLE=implementer" 0 'git push -u origin feat/1-x'
run $R feat/1-x "RELENTLESS_ROLE=implementer" 0 'gh pr create --title x --body "waiting for review:approved"'
run $R feat/1-x "$N" 2 'gh pr edit 3 --add-label review:approved && gh pr merge 3'
run $R feat/1-x "RELENTLESS_ROLE=orchestrator" 0 './core/scripts/merge-if-ready.sh --pr 3'

# human decision scripts: agents cannot invoke them; quoting the name in a message is not an invocation
run $G feat/1-x "RELENTLESS_ROLE=implementer" 2 'core/scripts/decide.sh --repo o/n --issue 1 --option 1'
run $G feat/1-x "RELENTLESS_ROLE=orchestrator" 2 'core/scripts/accept-adr.sh --file a.md --option 1 --decider Ada'
run $G feat/1-x "RELENTLESS_ROLE=planner" 2 'core/scripts/new-adr.sh --title T --slug s --status accepted'
run $G feat/1-x "RELENTLESS_ROLE=planner" 0 'core/scripts/new-adr.sh --title T --slug s --status proposed'
run $G feat/1-x "RELENTLESS_ROLE=implementer" 2 'env -u RELENTLESS_ROLE core/scripts/decide.sh --repo o/n --issue 1 --option 1'
run $G feat/1-x "RELENTLESS_ROLE=implementer" 2 'RELENTLESS_HUMAN=1 RELENTLESS_DECISION_TOKEN=forge core/scripts/decide.sh --repo o/n --issue 1 --option 1'
run $G feat/1-x "RELENTLESS_ROLE=implementer" 2 'bash hooks/scripts/userprompt-decide.sh'
run $G feat/1-x "CODEX_THREAD_ROLE=implementer" 2 'core/scripts/decide.sh --repo o/n --issue 1 --option 1'
# request-decision.sh is not role-locked. Opening a request is reversible; decide.sh stays blocked.
# Workers are instructed not to run it. The hook still allows every role, including the implementer.
run $G feat/1-x "RELENTLESS_ROLE=implementer" 0 'core/scripts/request-decision.sh --repo o/n --issue 1 --body-file req.md'
run $G feat/1-x "RELENTLESS_ROLE=orchestrator" 0 'core/scripts/request-decision.sh --repo o/n --issue 1 --body-file req.md'
run $G feat/1-x "RELENTLESS_ROLE=qa" 0 'core/scripts/request-decision.sh --repo o/n --issue 1 --body-file req.md'
run $G feat/1-x "RELENTLESS_ROLE=planner" 0 'core/scripts/request-decision.sh --repo o/n --issue 1 --body-file req.md'
run $G feat/1-x "RELENTLESS_ROLE=documenter" 0 'core/scripts/request-decision.sh --repo o/n --issue 1 --body-file req.md'
run $G feat/1-x "RELENTLESS_ROLE=reviewer" 0 'core/scripts/request-decision.sh --repo o/n --issue 1 --body-file req.md'
run $G feat/1-x "RELENTLESS_ROLE=implementer" 0 'git commit -m "docs: tell the decider to run decide.sh themselves"'

# The Stop hook is gone. hooks.json must not register it.
if grep -q 'stop-gate' "$ROOT/hooks/hooks.json" || [[ -e "$ROOT/hooks/scripts/stop-gate.sh" ]]; then
  FAIL=$((FAIL + 1))
  printf 'FAIL stop-gate still registered\n'
else
  PASS=$((PASS + 1))
fi

# Reviewer launch exports the env names the isolation hooks read, before Claude is spawned.
review="$ROOT/core/scripts/run-isolated-review.sh"
role_line="$(grep -n '^export RELENTLESS_ROLE=reviewer$' "$review" | head -1 | cut -d: -f1)"
agent_line="$(grep -n '^export CLAUDE_AGENT=reviewer$' "$review" | head -1 | cut -d: -f1)"
claude_line="$(grep -n 'claude -p' "$review" | head -1 | cut -d: -f1)"
if [[ -n "$role_line" && -n "$agent_line" && -n "$claude_line" \
  && "$role_line" -lt "$claude_line" && "$agent_line" -lt "$claude_line" ]]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  printf 'FAIL reviewer env export (role=%s agent=%s claude=%s)\n' \
    "${role_line:-missing}" "${agent_line:-missing}" "${claude_line:-missing}"
fi

echo "pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
