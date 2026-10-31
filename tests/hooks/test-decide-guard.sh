#!/usr/bin/env bash
# Human-decision guard: agents cannot record a decision, forged markers do not help,
# and a human at a real terminal (a PTY in this test) can.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

BIN="$TMP/bin"
mkdir -p "$BIN" "$TMP/work/.relentless" "$TMP/work/docs/decisions/adr"
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_LOG:?}"
if [[ "$1" == "repo" ]]; then
  echo "o/n"
  exit 0
fi
if [[ "$1" == "api" ]]; then
  case "$*" in
    *pulls/3/files*)
      printf '%s\n' "${GH_FILES:-README.md}"
      ;;
    *contents/docs/decisions/adr/*)
      tr -d '\n' <"${GH_ADR_B64:?}"
      echo
      ;;
    *issues/9/comments*)
      printf '%s\n' "${GH_COMMENTS:-}"
      ;;
    *issues/9*)
      printf '%s\n' "review:approved" "merge:human"
      ;;
    *)
      echo '["human:pending","state:blocked"]'
      ;;
  esac
  exit 0
fi
if [[ "$1" == "pr" ]]; then
  echo '{"headRefOid":"abc123","headRefName":"feat/1-x","baseRefName":"main","state":"open"}'
  exit 0
fi
exit 0
EOF
chmod +x "$BIN/gh"

cat >"$TMP/work/.relentless/config.json" <<'EOF'
{
  "decider": {"name": "Ada", "github": "ada"},
  "workers": {"default": {"github": "ada"}},
  "merge": {"default": "human", "allow_issue_override": true}
}
EOF

export GH_LOG="$TMP/gh.log"
export PATH="$BIN:$PATH"
: >"$GH_LOG"

# The script does not use set -e: refusals are expected non-zero statuses.

run_notty() {
  python3 - "$GH_LOG" "$@" <<'PY'
import os, subprocess, sys
gh_log = sys.argv[1]
argv = sys.argv[2:]
env = os.environ.copy()
env["GH_LOG"] = gh_log
p = subprocess.run(argv, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
sys.stdout.buffer.write(p.stdout)
sys.exit(p.returncode)
PY
}

run_pty() {
  python3 - "$GH_LOG" "$@" <<'PY'
import os, pty, select, sys, time
gh_log = sys.argv[1]
argv = sys.argv[2:]
env = os.environ.copy()
env["GH_LOG"] = gh_log
pid, fd = pty.fork()
if pid == 0:
    os.execvpe(argv[0], argv, env)
buf = b""
sent = False
deadline = time.time() + 8
status = None
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            chunk = b""
        if not chunk and status is not None:
            break
        buf += chunk
        if (not sent) and b"Type yes to confirm" in buf:
            os.write(fd, b"yes\n")
            sent = True
    wpid, st = os.waitpid(pid, os.WNOHANG)
    if wpid:
        status = os.waitstatus_to_exitcode(st)
        # drain
        while True:
            r, _, _ = select.select([fd], [], [], 0.05)
            if not r:
                break
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
        break
else:
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    status = 124
sys.stdout.buffer.write(buf)
sys.exit(status if status is not None else 124)
PY
}

assert_refusal() {
  local name="$1" out="$2" rc="$3"
  if [[ "$rc" -eq 0 ]]; then
    bad "$name exited 0; expected a refusal"
    return
  fi
  if ! printf '%s' "$out" | grep -q 'expected, not a broken lock'; then
    bad "$name missing expected-behavior wording"
    return
  fi
  if ! printf '%s' "$out" | grep -q 'own terminal'; then
    bad "$name missing own-terminal instruction"
    return
  fi
  if ! printf '%s' "$out" | grep -q 'decide.sh'; then
    bad "$name missing exact decide.sh command"
    return
  fi
  if [[ -s "$GH_LOG" ]]; then
    bad "$name called gh despite refusal: $(cat "$GH_LOG")"
    return
  fi
  ok
}

# Agent role refuses, even with forged env and a marker file the agent could write.
MARKER="$TMP/human-ok"
echo forged >"$MARKER"
: >"$GH_LOG"
out="$(
  RELENTLESS_ROLE=implementer \
  RELENTLESS_HUMAN=1 \
  RELENTLESS_DECISION_TOKEN=forge \
  RELENTLESS_DECIDE_OK=yes \
  RELENTLESS_HUMAN_CONFIRMED=1 \
  RELENTLESS_HUMAN_MARKER="$MARKER" \
  run_notty "$ROOT/core/scripts/decide.sh" --repo o/n --issue 7 --option 1 --note ship \
    --workdir "$TMP/work" --config "$TMP/work/.relentless/config.json" --no-adr
)"
rc=$?
assert_refusal "agent decide.sh" "$out" "$rc"

# Same forgery with no role and no TTY (Codex, including the interactive TUI).
: >"$GH_LOG"
out="$(
  unset RELENTLESS_ROLE CODEX_THREAD_ROLE CLAUDE_AGENT AGENT_NAME
  RELENTLESS_HUMAN=1 RELENTLESS_DECISION_TOKEN=forge RELENTLESS_HUMAN_MARKER="$MARKER" \
  run_notty "$ROOT/core/scripts/decide.sh" --repo o/n --issue 7 --option 1 \
    --workdir "$TMP/work" --config "$TMP/work/.relentless/config.json" --no-adr
)"
rc=$?
assert_refusal "forged env without a terminal" "$out" "$rc"
if ! printf '%s' "$out" | grep -q 'no TTY'; then
  bad "Codex refusal should say commands have no TTY"
else
  ok
fi

# Role wins even when a terminal is attached.
: >"$GH_LOG"
out="$(
  RELENTLESS_ROLE=orchestrator RELENTLESS_HUMAN=1 \
  run_pty "$ROOT/core/scripts/decide.sh" --repo o/n --issue 7 --option 1 \
    --workdir "$TMP/work" --config "$TMP/work/.relentless/config.json" --no-adr
)"
rc=$?
assert_refusal "agent decide.sh on a PTY" "$out" "$rc"

# Legitimate human path.
: >"$GH_LOG"
out="$(
  unset RELENTLESS_ROLE CODEX_THREAD_ROLE CLAUDE_AGENT AGENT_NAME
  run_pty "$ROOT/core/scripts/decide.sh" --repo o/n --issue 7 --option 1 --note ship \
    --workdir "$TMP/work" --config "$TMP/work/.relentless/config.json" --no-adr
)"
rc=$?
if [[ "$rc" -ne 0 ]]; then
  bad "human decide.sh failed ($rc): $out"
elif ! printf '%s' "$out" | grep -q 'Recorded option 1'; then
  bad "human decide.sh did not record: $out"
elif ! grep -q 'issue comment' "$GH_LOG"; then
  bad "human decide.sh did not comment: $(cat "$GH_LOG")"
else
  ok
fi

# accept-adr.sh: agent cannot write Decided by; human on a PTY can.
ADR="$TMP/work/docs/decisions/adr/0099-sample.md"
cat >"$ADR" <<'EOF'
# ADR 0099 — Sample

- **Status:** proposed
- **Date:** 2026-10-31 (America/Sao_Paulo)
- **Decided by:** _(filled by `/decide`)_

## Decision
_(filled when accepted)_

## Consequences
None.
EOF
cp "$ADR" "$TMP/adr-before"
: >"$GH_LOG"
out="$(
  RELENTLESS_ROLE=implementer RELENTLESS_HUMAN_CONFIRMED=1 RELENTLESS_HUMAN_MARKER="$MARKER" \
  run_notty "$ROOT/core/scripts/accept-adr.sh" --file "$ADR" --option 1 --decider Ada
)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  bad "agent accept-adr.sh exited 0"
elif ! cmp -s "$ADR" "$TMP/adr-before"; then
  bad "agent accept-adr.sh modified the ADR"
elif ! printf '%s' "$out" | grep -q 'expected, not a broken lock'; then
  bad "agent accept-adr.sh missing expected wording: $out"
else
  ok
fi

: >"$GH_LOG"
out="$(
  unset RELENTLESS_ROLE CODEX_THREAD_ROLE CLAUDE_AGENT AGENT_NAME
  run_pty "$ROOT/core/scripts/accept-adr.sh" --file "$ADR" --option 2 --decider Ada --note "ship it"
)"
rc=$?
if [[ "$rc" -ne 0 ]]; then
  bad "human accept-adr.sh failed ($rc): $out"
elif ! grep -q '^\- \*\*Status:\*\* accepted$' "$ADR"; then
  bad "human accept-adr.sh did not set accepted: $(grep Status "$ADR")"
elif ! grep -q '^\- \*\*Decided by:\*\* Ada$' "$ADR"; then
  bad "human accept-adr.sh did not set Decided by: $(grep 'Decided by' "$ADR")"
else
  ok
fi

# new-adr.sh: agents may create proposed ADRs and must not create accepted ones.
: >"$GH_LOG"
out="$(RELENTLESS_ROLE=planner "$ROOT/core/scripts/new-adr.sh" --workdir "$TMP/work" --title "Keep proposed" --slug keep-proposed)"
rc=$?
prop="$(find "$TMP/work/docs/decisions/adr" -name '*keep-proposed.md' -print -quit)"
if [[ "$rc" -ne 0 || ! -f "$prop" ]]; then
  bad "planner new-adr proposed failed ($rc): $out"
elif ! grep -q '^\- \*\*Status:\*\* proposed$' "$prop"; then
  bad "proposed ADR has wrong status"
else
  ok
fi

: >"$GH_LOG"
out="$(
  RELENTLESS_ROLE=planner RELENTLESS_DECISION_TOKEN=forge \
  run_notty "$ROOT/core/scripts/new-adr.sh" --workdir "$TMP/work" --title "Sneaky" --slug sneaky --status accepted
)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  bad "agent new-adr --status accepted exited 0"
elif compgen -G "$TMP/work/docs/decisions/adr/*sneaky.md" >/dev/null; then
  bad "agent wrote an accepted ADR"
elif ! printf '%s' "$out" | grep -q 'expected, not a broken lock'; then
  bad "accepted-status refusal missing expected wording: $out"
else
  ok
fi

# UserPromptSubmit performs /decide itself, including when the session role is set.
: >"$GH_LOG"
out="$(
  jq -n --arg p '/decide 7 1 ship it' --arg c "$TMP/work" '{hook_event_name:"UserPromptSubmit", prompt:$p, cwd:$c}' |
    RELENTLESS_ROLE=orchestrator bash "$ROOT/hooks/scripts/userprompt-decide.sh"
)"
rc=$?
if [[ "$rc" -ne 0 ]]; then
  bad "userprompt /decide failed ($rc): $out"
elif ! printf '%s' "$out" | grep -q 'additionalContext'; then
  bad "userprompt /decide did not return hook context: $out"
elif ! printf '%s' "$out" | grep -q 'Recorded option 1'; then
  bad "userprompt /decide did not record: $out"
elif ! grep -q 'issue comment' "$GH_LOG"; then
  bad "userprompt /decide did not comment"
else
  ok
fi

: >"$GH_LOG"
out="$(jq -n --arg p 'hello' '{hook_event_name:"UserPromptSubmit", prompt:$p}' | bash "$ROOT/hooks/scripts/userprompt-decide.sh")"
rc=$?
if [[ "$rc" -ne 0 || -n "$out" || -s "$GH_LOG" ]]; then
  bad "non-decide prompt should be a no-op (rc=$rc out=$out gh=$(cat "$GH_LOG"))"
else
  ok
fi

# merge-if-ready refuses an accepted ADR in the diff with no decision-request comment.
ADR_OK="$TMP/accepted.md"
cat >"$ADR_OK" <<'EOF'
# ADR 0004 — Example

- **Status:** accepted
- **Decided by:** Ada

## Decision
Option 1 accepted.
EOF
base64 -w0 "$ADR_OK" >"$TMP/adr.b64"
export GH_ADR_B64="$TMP/adr.b64"
export GH_FILES="docs/decisions/adr/0004-example.md"
export GH_COMMENTS="no request here"
: >"$GH_LOG"
out="$(
  env -u RELENTLESS_ROLE \
  "$ROOT/core/scripts/merge-if-ready.sh" --repo o/r --pr 3 --issue 9 \
    --config "$TMP/work/.relentless/config.json" --dry-run 2>&1
)"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  bad "merge-if-ready allowed an accepted ADR without a decision-request: $out"
elif ! printf '%s' "$out" | grep -q 'no decision-request'; then
  bad "merge-if-ready refusal missing decision-request reason: $out"
else
  ok
fi

export GH_COMMENTS="<!-- relentless:decision-request -->"
: >"$GH_LOG"
out="$(
  "$ROOT/core/scripts/merge-if-ready.sh" --repo o/r --pr 3 --issue 9 \
    --config "$TMP/work/.relentless/config.json" --dry-run 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]]; then
  bad "merge-if-ready blocked a requested ADR ($rc): $out"
elif ! printf '%s' "$out" | grep -q 'dry-run'; then
  bad "merge-if-ready did not reach dry-run: $out"
else
  ok
fi

export GH_FILES="README.md"
export GH_COMMENTS=""
: >"$GH_LOG"
out="$(
  "$ROOT/core/scripts/merge-if-ready.sh" --repo o/r --pr 3 --issue 9 \
    --config "$TMP/work/.relentless/config.json" --dry-run 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]]; then
  bad "merge-if-ready blocked a PR with no ADR ($rc): $out"
else
  ok
fi

echo "pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
