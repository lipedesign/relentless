#!/usr/bin/env bash
# wait-ci.sh polls in the foreground and never starts a run watcher.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

cat >"$TMP/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *watch* ]]; then
  echo "watcher invoked: $*" >&2
  exit 99
fi
case "$1 $2" in
  "pr view")
    printf '%s\n' '{"headRefName":"feat/1-x"}'
    ;;
  "run list")
    cat "$GH_RUN_LIST"
    ;;
  "pr checks")
    cat "$GH_CHECKS_OUT"
    exit "${GH_CHECKS_RC:-8}"
    ;;
  *)
    echo "unexpected gh: $*" >&2
    exit 99
    ;;
esac
EOF
chmod +x "$TMP/gh"

run_wait() {
  PATH="$TMP:$PATH" "$ROOT/core/scripts/wait-ci.sh" --repo o/r --pr 1 --timeout-sec 1
}

export GH_CHECKS_OUT="$TMP/checks.txt"
export GH_CHECKS_RC=8
export GH_RUN_LIST="$TMP/runs.json"
printf '%s\n' 'no checks reported' >"$GH_CHECKS_OUT"

printf '%s\n' '[{"databaseId":9,"status":"completed","conclusion":"success"}]' >"$GH_RUN_LIST"
out="$(run_wait 2>"$TMP/err")"
rc=$?
if [[ "$rc" -eq 0 && "$out" == *"CI green"* && ! -s "$TMP/err" ]]; then ok; else bad "success run rc=$rc out=$out err=$(cat "$TMP/err")"; fi

printf '%s\n' '[{"databaseId":9,"status":"completed","conclusion":"failure"}]' >"$GH_RUN_LIST"
out="$(run_wait 2>"$TMP/err")"
rc=$?
if [[ "$rc" -eq 1 && "$(cat "$TMP/err")" == *"CI failed"* ]]; then ok; else bad "failed run rc=$rc out=$out err=$(cat "$TMP/err")"; fi

printf '%s\n' '[{"databaseId":9,"status":"in_progress","conclusion":null}]' >"$GH_RUN_LIST"
out="$(run_wait 2>"$TMP/err")"
rc=$?
if [[ "$rc" -eq 3 && "$out" == *"CI: pending"* && "$out" == *"exit 3"* && "$out" == *"foreground"* && "$out" == *"run 9"* ]]; then
  ok
else
  bad "pending run rc=$rc out=$out err=$(cat "$TMP/err")"
fi

printf '%s\n' '[]' >"$GH_RUN_LIST"
GH_CHECKS_RC=0
printf '%s\n' 'all passed' >"$GH_CHECKS_OUT"
out="$(run_wait 2>"$TMP/err")"
rc=$?
if [[ "$rc" -eq 0 && "$out" == *"CI green"* ]]; then ok; else bad "checks pass rc=$rc out=$out"; fi

GH_CHECKS_RC=1
printf '%s\n' 'test fail' >"$GH_CHECKS_OUT"
out="$(run_wait 2>"$TMP/err")"
rc=$?
if [[ "$rc" -eq 1 && "$(cat "$TMP/err")" == *"CI failed"* ]]; then ok; else bad "checks fail rc=$rc err=$(cat "$TMP/err")"; fi

GH_CHECKS_RC=8
printf '%s\n' 'no checks reported' >"$GH_CHECKS_OUT"
out="$(run_wait 2>"$TMP/err")"
rc=$?
if [[ "$rc" -eq 3 && "$out" == *"CI: pending"* && "$out" == *"next step"* ]]; then ok; else bad "no run pending rc=$rc out=$out"; fi

if grep -n 'gh run watch' "$ROOT"/core/scripts/*.sh >/dev/null; then
  bad "a core script still invokes gh run watch"
else
  ok
fi

echo "pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
