#!/usr/bin/env bash
# check-commit-msg.sh — lightweight conventional commit + branch hint.
# Usage:
#   check-commit-msg.sh [--message MSG | --file PATH] [--branch NAME] [--require-closes]
# Exit 0 ok, 1 on failure. Intended for local hooks / CI / agent self-check.
set -euo pipefail

MSG="" FILE="" BRANCH="" REQUIRE_CLOSES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --message) MSG="${2:-}"; shift 2 ;;
    --file) FILE="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --require-closes) REQUIRE_CLOSES=1; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--message MSG | --file PATH] [--branch NAME] [--require-closes]"
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "$FILE" ]]; then
  MSG="$(cat "$FILE")"
fi
if [[ -z "$MSG" ]]; then
  MSG="$(git log -1 --pretty=%B 2>/dev/null || true)"  # intentional fail-soft
fi
[[ -n "$MSG" ]] || { echo "error: no commit message" >&2; exit 1; }

SUBJECT="$(printf '%s' "$MSG" | head -1)"
# type(scope)?: subject  OR type: subject
if ! printf '%s' "$SUBJECT" | grep -qE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9._/-]+\))?!?: .+'; then
  echo "error: subject must be conventional: <type>(optional-scope): description" >&2
  echo "  got: $SUBJECT" >&2
  exit 1
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"  # intentional fail-soft
fi
if [[ -n "$BRANCH" && "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
  if ! printf '%s' "$BRANCH" | grep -qE '^(feat|fix|chore|docs|refactor|test|ci|perf|build|style)/[0-9]+-[a-z0-9][a-z0-9-]*$'; then
    echo "warn: branch '$BRANCH' is not <type>/<n>-<slug> (Relentless doctrine)" >&2
  fi
fi

BODY="$(printf '%s' "$MSG" | tail -n +2)"
if [[ "$REQUIRE_CLOSES" -eq 1 ]]; then
  if ! printf '%s\n%s' "$SUBJECT" "$BODY" | grep -qiE 'closes[[:space:]]+#[0-9]+'; then
    echo "error: message must contain plain 'Closes #N'" >&2
    exit 1
  fi
fi

echo "ok: conventional commit"
exit 0
