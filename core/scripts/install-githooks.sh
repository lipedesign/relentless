#!/usr/bin/env bash
# install-githooks.sh — install consumer pre-commit and pre-push guards.
#
# Refuses commits on main/master, pushes to main/master, and force-pushes.
# Uses core.hooksPath=.relentless/githooks when that path is unset or already ours.
# An existing hooksPath (husky and anything else) is left in place and chained.
#
# Usage: install-githooks.sh --workdir PATH [--dry-run]
set -euo pipefail

WORKDIR=""
DRY=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/../templates/githooks"

usage() {
  echo "Usage: $(basename "$0") --workdir PATH [--dry-run]"
  echo "Install Relentless git hooks. Does not enable GitHub branch protection."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$WORKDIR" && -d "$WORKDIR" ]] || { echo "error: --workdir must be an existing directory" >&2; exit 2; }
WORKDIR="$(cd "$WORKDIR" && pwd)"

if ! git -C "$WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
  # intentional fail-soft: bootstrap may be pointed at a directory that is not a checkout yet
  echo "warn: ${WORKDIR} is not a git repo; skipped git hooks" >&2
  exit 0
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "plan: write .relentless/githooks/pre-commit and pre-push"
  echo "plan: core.hooksPath=.relentless/githooks, or chain an existing hooksPath without replacing it"
  echo "plan: refuse commits on main/master, pushes to main/master, and force-pushes"
  echo "plan: GitHub branch protection is not changed here"
  exit 0
fi

dest="${WORKDIR}/.relentless/githooks"
mkdir -p "$dest"
cp "${TEMPLATE_DIR}/pre-commit" "${dest}/pre-commit"
cp "${TEMPLATE_DIR}/pre-push" "${dest}/pre-push"
chmod +x "${dest}/pre-commit" "${dest}/pre-push"
echo "githooks: wrote ${dest}/pre-commit and pre-push"

chain_snippet() {
  local hookname="$1"
  cat <<EOF
# relentless:githooks — existing hook kept; relentless check runs first
_relentless_root=\$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "\$_relentless_root" ] && [ -x "\$_relentless_root/.relentless/githooks/${hookname}" ]; then
  "\$_relentless_root/.relentless/githooks/${hookname}" "\$@" || exit \$?
fi
EOF
}

prepend_chain() {
  local target="$1" hookname="$2" tmp
  if grep -q 'relentless:githooks' "$target" 2>/dev/null; then
    echo "githooks: already chained in ${target}"
    return 0
  fi
  # A NUL byte means this is not a shell script. grep with an empty pattern is not a NUL test.
  if [[ -n "$(tr -cd '\000' <"$target")" ]]; then
    # intentional fail-soft: do not rewrite a binary hook
    echo "warn: ${target} is not a text hook; left it unchanged" >&2
    return 0
  fi
  tmp="$(mktemp)"
  if head -n 1 "$target" | grep -q '^#!'; then
    head -n 1 "$target" >"$tmp"
    chain_snippet "$hookname" >>"$tmp"
    tail -n +2 "$target" >>"$tmp"
  else
    chain_snippet "$hookname" >"$tmp"
    cat "$target" >>"$tmp"
  fi
  mv "$tmp" "$target"
  chmod +x "$target"
  echo "githooks: chained relentless into ${target}"
}

current="$(git -C "$WORKDIR" config --get core.hooksPath || true)"  # intentional fail-soft: unset hooksPath is the default
current="${current%/}"
abs_dest="${dest}"

if [[ -z "$current" || "$current" == ".relentless/githooks" || "$current" == "$abs_dest" ]]; then
  git -C "$WORKDIR" config core.hooksPath .relentless/githooks
  echo "githooks: core.hooksPath=.relentless/githooks"
else
  echo "githooks: leaving core.hooksPath=${current} (chain, do not clobber)"
  if [[ "$current" == /* ]]; then
    hookdir="$current"
  else
    hookdir="${WORKDIR}/${current}"
  fi
  mkdir -p "$hookdir"
  for hookname in pre-commit pre-push; do
    target="${hookdir}/${hookname}"
    if [[ ! -e "$target" ]]; then
      {
        echo '#!/bin/sh'
        chain_snippet "$hookname"
      } >"$target"
      chmod +x "$target"
      echo "githooks: created ${target}"
    else
      prepend_chain "$target" "$hookname"
    fi
  done
fi
