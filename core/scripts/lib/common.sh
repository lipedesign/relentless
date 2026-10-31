#!/usr/bin/env bash
# Shared helpers for Relentless core scripts.
# shellcheck source=lib/common.sh

die() { echo "error: $*" >&2; exit 1; }

STATE_LABELS=(state:todo state:in-progress state:blocked state:review state:done)

resolve_config() {
  local cfg="${1:-}"
  if [[ -n "$cfg" && -f "$cfg" ]]; then
    (cd "$(dirname "$cfg")" && echo "$(pwd)/$(basename "$cfg")")
    return 0
  fi
  if [[ -n "$cfg" && "$cfg" != /* && -n "${WORKDIR:-}" && -f "${WORKDIR}/${cfg}" ]]; then
    echo "${WORKDIR}/${cfg}"
    return 0
  fi
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$root" && -f "${root}/.relentless/config.json" ]]; then
    echo "${root}/.relentless/config.json"
    return 0
  fi
  if [[ -f ".relentless/config.json" ]]; then
    echo "$(pwd)/.relentless/config.json"
    return 0
  fi
  echo ""
  return 1
}

# Plugin root (install cache or checkout). Prefer RELENTLESS_ROOT, else this script tree.
relentless_root() {
  if [[ -n "${RELENTLESS_ROOT:-}" && -d "${RELENTLESS_ROOT}" ]]; then
    echo "$RELENTLESS_ROOT"
    return 0
  fi
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  echo "$here"
}

# set_issue_state REPO ISSUE state:NAME [quiet=0]
# One GET + one PATCH; preserves non-state labels; never stacks state:*.
set_issue_state() {
  local repo="$1"
  local issue="$2"
  local target="$3"
  local quiet="${4:-0}"
  local current new_json
  current="$(gh api "repos/${repo}/issues/${issue}" --jq '[.labels[].name]' 2>/dev/null || echo '[]')"
  new_json="$(jq -c --arg t "$target" --argjson states "$(printf '%s\n' "${STATE_LABELS[@]}" | jq -R . | jq -s .)" '
    ([.[] | select(. as $l | $states | index($l) | not)] + [$t]) | unique
  ' <<<"$current")"
  # Build -f labels[]= args
  local args=(-X PATCH "repos/${repo}/issues/${issue}")
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    args+=(-f "labels[]=${name}")
  done < <(jq -r '.[]' <<<"$new_json")
  if [[ "$quiet" -eq 1 ]]; then
    gh api "${args[@]}" >/dev/null
  else
    gh api "${args[@]}" --jq '"\(.html_url) → labels updated"' >/dev/null
    echo "${repo}#${issue} → ${target}"
  fi
}

check_gh_workflow_scope() {
  local status scopes
  status="$(gh auth status 2>&1 || true)"
  if echo "$status" | grep -qiE "Token scopes:.*['\"]workflow['\"]|scopes:.*workflow"; then
    echo "gh scopes: workflow present"
    return 0
  fi
  scopes="$(gh api -i -X GET /user 2>&1 | grep -i '^x-oauth-scopes:' || true)"
  if echo "$scopes" | grep -qw workflow; then
    echo "gh scopes: workflow present"
    return 0
  fi
  echo "error: GitHub token is missing the 'workflow' scope." >&2
  echo "  Relentless cannot push .github/workflows/*.yml without it." >&2
  echo "  Fix: gh auth refresh -s workflow" >&2
  return 1
}

# resolve_merge_mode REPO ISSUE CONFIG → prints auto|human
resolve_merge_mode() {
  local repo="$1" issue="$2" config="${3:-}"
  local labels
  labels="$(gh api "repos/${repo}/issues/${issue}" --jq '[.labels[].name] | join("\n")' 2>/dev/null || true)"
  if echo "$labels" | grep -Fxq "merge:human"; then
    echo "human"; return 0
  fi
  if echo "$labels" | grep -Fxq "merge:auto"; then
    echo "auto"; return 0
  fi
  if [[ -n "$config" && -f "$config" ]]; then
    jq -r '.merge.default // "human"' "$config"
    return 0
  fi
  echo "human"
}
