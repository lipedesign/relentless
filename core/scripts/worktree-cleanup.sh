#!/usr/bin/env bash
# worktree-cleanup.sh — remove a Relentless implementer worktree AFTER merge.
# Never delete before merge-if-ready succeeds. Prefer calling from merge-if-ready
# with --cleanup-worktree PATH, or manually after the PR is merged.
#
# Usage:
#   worktree-cleanup.sh --path PATH [--repo OWNER/NAME] [--force-local] [--dry-run]
set -euo pipefail

PATH_WT="" REPO="" FORCE=0 DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) PATH_WT="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --force-local) FORCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") --path PATH [--repo OWNER/NAME] [--force-local] [--dry-run]"
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$PATH_WT" ]] || { echo "need --path" >&2; exit 2; }
[[ -d "$PATH_WT" ]] || { echo "error: not a directory: $PATH_WT" >&2; exit 1; }

PATH_WT="$(cd "$PATH_WT" && pwd)"
BRANCH="$(git -C "$PATH_WT" branch --show-current 2>/dev/null || true)"  # intentional fail-soft
# common-dir is often <primary>/.git — resolve toplevel of main
MAIN_TOP="$(git -C "$PATH_WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
MAIN_TOP="$(cd "$(dirname "$MAIN_TOP")" 2>/dev/null && pwd || true)"  # intentional fail-soft

echo "cleanup worktree: $PATH_WT (branch=${BRANCH:-unknown})"

# Safety: refuse if uncommitted changes unless --force-local
if [[ "$FORCE" -eq 0 ]]; then
  if [[ -n "$(git -C "$PATH_WT" status --porcelain 2>/dev/null)" ]]; then
    echo "error: worktree has uncommitted changes — commit/stash or pass --force-local" >&2
    exit 1
  fi
fi

# Prefer only cleaning after remote branch is gone (merged+deleted) or PR merged
if [[ -n "$REPO" && -n "$BRANCH" ]]; then
  state="$(gh pr list --repo "$REPO" --head "$BRANCH" --state all --json state -q '.[0].state // empty' 2>/dev/null || true)"  # intentional fail-soft
  if [[ "$state" == "OPEN" ]]; then
    echo "error: PR for $BRANCH still OPEN — merge first" >&2
    exit 1
  fi
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "dry-run: git worktree remove $PATH_WT"
  exit 0
fi

# Remove from primary repo
if [[ -n "$MAIN_TOP" && -d "$MAIN_TOP" ]]; then
  git -C "$MAIN_TOP" worktree remove --force "$PATH_WT" 2>/dev/null \
    || git -C "$MAIN_TOP" worktree remove "$PATH_WT" 2>/dev/null \
    || { rm -rf "$PATH_WT"; git -C "$MAIN_TOP" worktree prune; }
else
  # Fallback: prune after rm
  rm -rf "$PATH_WT"
fi

echo "ok: removed worktree $PATH_WT"
