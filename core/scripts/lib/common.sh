#!/usr/bin/env bash
# Shared helpers for Relentless core scripts. Source from other scripts:
#   SCRIPT_DIR=...; # shellcheck source=lib/common.sh
#   source "${SCRIPT_DIR}/lib/common.sh"

STATE_LABELS=(state:todo state:in-progress state:blocked state:review state:done)

# resolve_config PATH_OR_EMPTY REPO → prints absolute config path or empty
resolve_config() {
  local cfg="${1:-}"
  local repo="${2:-}"
  if [[ -n "$cfg" && -f "$cfg" ]]; then
    # shellcheck disable=SC2001
    (cd "$(dirname "$cfg")" && echo "$(pwd)/$(basename "$cfg")")
    return 0
  fi
  if [[ -n "$cfg" && "$cfg" != /* && -n "${WORKDIR:-}" && -f "${WORKDIR}/${cfg}" ]]; then
    echo "${WORKDIR}/${cfg}"
    return 0
  fi
  # Try git root of current directory
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$root" && -f "${root}/.relentless/config.json" ]]; then
    echo "${root}/.relentless/config.json"
    return 0
  fi
  if [[ -n "$cfg" && -f "$cfg" ]]; then
    echo "$cfg"
    return 0
  fi
  # Last resort: relative default if present
  if [[ -f ".relentless/config.json" ]]; then
    echo "$(pwd)/.relentless/config.json"
    return 0
  fi
  echo ""
  return 1
}

# set_issue_state REPO ISSUE state:NAME
# Removes every other state:* label, then adds the target (one active state).
set_issue_state() {
  local repo="$1"
  local issue="$2"
  local target="$3"
  local label
  for label in "${STATE_LABELS[@]}"; do
    if [[ "$label" != "$target" ]]; then
      gh issue edit "$issue" --repo "$repo" --remove-label "$label" 2>/dev/null || true
    fi
  done
  gh issue edit "$issue" --repo "$repo" --add-label "$target" || true
}

# check_gh_workflow_scope → 0 if workflow present, 1 otherwise (prints guidance)
check_gh_workflow_scope() {
  local status scopes
  status="$(gh auth status 2>&1 || true)"
  # Prefer explicit token scopes line
  if echo "$status" | grep -qiE "Token scopes:.*['\"]workflow['\"]|scopes:.*workflow"; then
    echo "gh scopes: workflow present"
    return 0
  fi
  # Fallback: try to parse hosts.yml / gh api
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
