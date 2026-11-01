#!/usr/bin/env bash
# Reviewer findings are posted on the PR, and the verdict is only the last line.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$*"; }

export GH_LOG="$TMP/gh.log"
export GH_COMMENT="$TMP/comment.md"

cat >"$TMP/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
if [[ "$1" == "pr" && "$2" == "comment" ]]; then
  prev=""
  for arg in "$@"; do
    if [[ "$prev" == "--body-file" ]]; then
      cp "$arg" "$GH_COMMENT"
    elif [[ "$prev" == "--body" ]]; then
      printf '%s\n' "$arg" >"$GH_COMMENT"
    fi
    prev="$arg"
  done
  exit 0
fi
if [[ "$1" == "api" ]]; then
  if [[ "$*" == *"-X"* ]]; then
    exit 0
  fi
  printf '%s\n' '["state:review"]'
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 99
EOF
chmod +x "$TMP/gh"

reset_gh() {
  : >"$GH_LOG"
  rm -f "$GH_COMMENT"
}

run_from() {
  local work="$1" file="$2"
  PATH="$TMP:$PATH" "$ROOT/core/scripts/run-isolated-review.sh" \
    --repo o/r --pr 7 --issue 7 \
    --workdir "$work" \
    --from-output "$file"
}

# findings + marker + last line changes_requested
reset_gh
work="$TMP/cr"
mkdir -p "$work"
cat >"$work/review.md" <<'EOF'
## Findings
1. **[blocker]** session cookie is dropped on refresh (`src/auth.ts:40`)
2. **[major]** ADR line missing from the PR body
3. **[minor]** name the timeout constant
4. **[nit]** trailing space in the comment

Verdict: changes_requested
EOF
out="$(run_from "$work" "$work/review.md" 2>"$work/err")"
rc=$?
body="$(cat "$GH_COMMENT" 2>/dev/null || true)"
if [[ "$rc" -eq 0 && "$body" == *"[blocker]"* && "$body" == *"[major]"* && "$body" == *"[minor]"* && "$body" == *"[nit]"* && "$body" == *"session cookie is dropped on refresh"* ]]; then
  ok
else
  bad "findings in comment rc=$rc body=$body err=$(cat "$work/err")"
fi
if [[ "$rc" -eq 0 && "$body" == *"<!-- relentless:review-verdict -->"* ]]; then
  ok
else
  bad "marker missing rc=$rc body=$body"
fi
if [[ "$rc" -eq 0 && "$out" == *"verdict: changes_requested"* && "$body" != *"review:approved"* && "$(cat "$GH_LOG")" == *"state:in-progress"* ]]; then
  ok
else
  bad "last line changes_requested rc=$rc out=$out"
fi

# last line approved, earlier text quotes changes_requested
reset_gh
work="$TMP/ap"
mkdir -p "$work"
cat >"$work/review.md" <<'EOF'
## Findings
1. **[nit]** rename the helper

A quoted rule says blockers mean `changes_requested`.

Verdict: approved
EOF
out="$(run_from "$work" "$work/review.md" 2>"$work/err")"
rc=$?
log="$(cat "$GH_LOG")"
if [[ "$rc" -eq 0 && "$out" == *"verdict: approved"* && "$log" == *"review:approved"* && "$log" != *"state:in-progress"* ]]; then
  ok
else
  bad "last line approved rc=$rc out=$out log=$log err=$(cat "$work/err")"
fi

# rule quoted earlier ends on the other word; the final line wins
reset_gh
work="$TMP/quote"
mkdir -p "$work"
cat >"$work/review.md" <<'EOF'
Verdict: approved

## Findings
1. **[blocker]** refresh drops the session cookie

Verdict rule: any blocker or major finding, any unmet acceptance criterion, a missing ADRs line, or failing QA → `changes_requested`. Only minor/nit findings → `approved`; list them as follow-ups.

Verdict: changes_requested
EOF
out="$(run_from "$work" "$work/review.md" 2>"$work/err")"
rc=$?
body="$(cat "$GH_COMMENT" 2>/dev/null || true)"
log="$(cat "$GH_LOG")"
if [[ "$rc" -eq 0 && "$out" == *"verdict: changes_requested"* && "$out" != *"verdict: approved"* && "$log" == *"state:in-progress"* && "$log" != *"labels[]=review:approved"* && "$body" == *"[blocker]"* && "$body" == *"refresh drops the session cookie"* ]]; then
  ok
else
  bad "quoted rule must not flip verdict rc=$rc out=$out log=$log body=$body err=$(cat "$work/err")"
fi

# missing verdict line (no non-empty line)
reset_gh
work="$TMP/miss"
mkdir -p "$work"
printf '\n\n' >"$work/review.md"
out="$(run_from "$work" "$work/review.md" 2>"$work/err")"
rc=$?
if [[ "$rc" -ne 0 && "$(cat "$work/err")" == *"missing verdict line"* && ! -s "$GH_LOG" ]]; then
  ok
else
  bad "missing verdict rc=$rc out=$out err=$(cat "$work/err") log=$(cat "$GH_LOG")"
fi

# malformed: quoted rule is the last line, so the old last-token parse would flip to approved
reset_gh
work="$TMP/bad"
mkdir -p "$work"
cat >"$work/review.md" <<'EOF'
## Verdict
`changes_requested`

## Findings
1. **[blocker]** session cookie is dropped

Verdict rule: any blocker or major finding → `changes_requested`. Only minor/nit findings → `approved`.
EOF
out="$(run_from "$work" "$work/review.md" 2>"$work/err")"
rc=$?
if [[ "$rc" -ne 0 && "$(cat "$work/err")" == *"malformed verdict line"* && ! -s "$GH_LOG" ]]; then
  ok
else
  bad "malformed verdict rc=$rc out=$out err=$(cat "$work/err") log=$(cat "$GH_LOG")"
fi

# the brief's example placeholder is not a verdict
reset_gh
work="$TMP/placeholder"
mkdir -p "$work"
cat >"$work/review.md" <<'EOF'
## Findings
1. **[nit]** rename the helper

Verdict: <approved|changes_requested>
EOF
out="$(run_from "$work" "$work/review.md" 2>"$work/err")"
rc=$?
err="$(cat "$work/err")"
if [[ "$rc" -ne 0 && "$err" == *"refusing placeholder verdict line"* && "$err" == *"Verdict: <approved|changes_requested>"* && "$err" == *"No labels changed"* && ! -s "$GH_LOG" ]]; then
  ok
else
  bad "placeholder verdict rc=$rc out=$out err=$err log=$(cat "$GH_LOG")"
fi

echo "pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
