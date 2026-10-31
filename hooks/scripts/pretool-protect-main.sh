#!/usr/bin/env bash
# pretool-protect-main.sh — PreToolUse Bash: block commit/push directly to main/master
# and destructive git; when implementer/worktree, also block force-push / reset --hard / clean.
set -euo pipefail
INPUT="$(cat 2>/dev/null || true)"  # intentional: empty stdin ok
CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)"  # intentional fail-soft
fi
[[ -z "$CMD" ]] && exit 0

deny() { printf 'protect-main: BLOCKED — %s\n' "$*" >&2; exit 2; }

# Strip quoted heredoc bodies so false positives from scripts echoing git commands are reduced
# (same idea as isolation hook). Best-effort.
STRIPPED="$CMD"

# Destructive patterns always denied for Relentless roles / worktrees; soft-deny globally for main
if echo "$STRIPPED" | grep -qiE '(^|[;|&[:space:]])git[[:space:]]+push[[:space:]]+[^;|&]*[[:space:]](--force|-f)([[:space:]]|$)'; then
  deny "force-push is forbidden"
fi
if echo "$STRIPPED" | grep -qiE '(^|[;|&[:space:]])git[[:space:]]+reset[[:space:]]+[^;|&]*(--hard|--merge)'; then
  deny "git reset --hard/--merge is forbidden (destructive)"
fi
if echo "$STRIPPED" | grep -qiE '(^|[;|&[:space:]])git[[:space:]]+clean[[:space:]]+[^;|&]*-f'; then
  deny "git clean -f is forbidden (destructive)"
fi

# Commit / push to main or master
BRANCH=""
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"  # intentional fail-soft
fi
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
  if echo "$STRIPPED" | grep -qiE '(^|[;|&[:space:]])git[[:space:]]+(commit|push)\b'; then
    deny "commit/push on ${BRANCH} is forbidden — use a feature worktree (<type>/<n>-<slug>)"
  fi
fi
# Explicit push of main
if echo "$STRIPPED" | grep -qiE '(^|[;|&[:space:]])git[[:space:]]+push\b[^;|&]*\b(origin[[:space:]]+)?(main|master)\b'; then
  deny "git push of main/master is forbidden"
fi
# checkout main then commit in same command
if echo "$STRIPPED" | grep -qiE 'git[[:space:]]+checkout[[:space:]]+(main|master)' \
  && echo "$STRIPPED" | grep -qiE 'git[[:space:]]+(commit|push)\b'; then
  deny "checkout main + commit/push in one command is forbidden"
fi

exit 0
