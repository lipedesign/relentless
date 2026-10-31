#!/usr/bin/env bash
# detect-stack.sh — detect project stack and check commands under WORKDIR.
# Sourced by bootstrap, or run standalone:
#   detect-stack.sh --workdir PATH [--json]
# Prints human lines; with --json prints one JSON object to stdout.
set -euo pipefail

_DETECT_WORKDIR=""
_DETECT_JSON=0

detect_stack_usage() {
  echo "Usage: detect-stack.sh --workdir PATH [--json]"
}

# Populate globals: STACK PM INSTALL LINT TYPECHECK TEST BUILD HAS_TEST
# STACK: node|python|go|rust|unknown
detect_stack() {
  local root="${1:-.}"
  STACK="unknown"
  PM=""
  INSTALL=""
  LINT=""
  TYPECHECK=""
  TEST=""
  BUILD=""
  HAS_TEST=0

  root="$(cd "$root" && pwd)"

  if [[ -f "${root}/package.json" ]]; then
    STACK="node"
    if [[ -f "${root}/pnpm-lock.yaml" ]]; then PM="pnpm"; INSTALL="pnpm install --frozen-lockfile"
    elif [[ -f "${root}/yarn.lock" ]]; then PM="yarn"; INSTALL="yarn install --frozen-lockfile"
    elif [[ -f "${root}/bun.lockb" || -f "${root}/bun.lock" ]]; then PM="bun"; INSTALL="bun install --frozen-lockfile"
    elif [[ -f "${root}/package-lock.json" ]]; then PM="npm"; INSTALL="npm ci"
    else PM="npm"; INSTALL="npm install"
    fi
    # scripts from package.json
    local scripts
    scripts="$(jq -r '.scripts // {} | keys[]' "${root}/package.json" 2>/dev/null || true)"
    _has_script() { grep -Fxq "$1" <<<"$scripts"; }
    if _has_script lint; then LINT="${PM} run lint"
    elif _has_script eslint; then LINT="${PM} run eslint"
    fi
    if _has_script typecheck; then TYPECHECK="${PM} run typecheck"
    elif _has_script "type-check"; then TYPECHECK="${PM} run type-check"
    elif _has_script tsc; then TYPECHECK="${PM} run tsc"
    fi
    if _has_script test; then TEST="${PM} run test"; HAS_TEST=1
    elif _has_script "test:unit"; then TEST="${PM} run test:unit"; HAS_TEST=1
    fi
    if _has_script build; then BUILD="${PM} run build"; fi

  elif [[ -f "${root}/go.mod" ]]; then
    STACK="go"
    INSTALL="go mod download"
    LINT="go vet ./..."
    TEST="go test ./..."
    HAS_TEST=1
    BUILD="go build ./..."

  elif [[ -f "${root}/Cargo.toml" ]]; then
    STACK="rust"
    INSTALL="cargo fetch"
    LINT="cargo clippy -- -D warnings"
    TEST="cargo test"
    HAS_TEST=1
    BUILD="cargo build"

  elif [[ -f "${root}/pyproject.toml" || -f "${root}/requirements.txt" || -f "${root}/setup.py" ]]; then
    STACK="python"
    if [[ -f "${root}/pyproject.toml" ]]; then
      INSTALL="pip install -e ."
      if grep -qE 'pytest|\[project\.optional-dependencies\.dev\]|\[tool\.pytest' "${root}/pyproject.toml" 2>/dev/null; then
        TEST="pytest"; HAS_TEST=1
      fi
      if grep -qE '\[tool\.ruff|ruff' "${root}/pyproject.toml" 2>/dev/null; then
        LINT="ruff check ."
      fi
      if grep -qE 'mypy|\[tool\.mypy' "${root}/pyproject.toml" 2>/dev/null; then
        TYPECHECK="mypy ."
      fi
    else
      INSTALL="pip install -r requirements.txt"
    fi
    # Fallback probes
    if [[ "$HAS_TEST" -eq 0 ]] && { [[ -d "${root}/tests" ]] || [[ -d "${root}/test" ]] || compgen -G "${root}/test_*.py" >/dev/null 2>&1; }; then
      TEST="pytest"; HAS_TEST=1
      [[ -z "$INSTALL" ]] && INSTALL="pip install pytest"
    fi
    if [[ -z "$LINT" ]] && command -v ruff >/dev/null 2>&1; then
      : # don't assume ruff in CI unless declared
    fi
    # If requirements mention pytest
    if [[ "$HAS_TEST" -eq 0 && -f "${root}/requirements.txt" ]] && grep -qi pytest "${root}/requirements.txt"; then
      TEST="pytest"; HAS_TEST=1
    fi
  fi
}

detect_stack_json() {
  jq -n \
    --arg stack "$STACK" \
    --arg pm "$PM" \
    --arg install "$INSTALL" \
    --arg lint "$LINT" \
    --arg typecheck "$TYPECHECK" \
    --arg test "$TEST" \
    --arg build "$BUILD" \
    --argjson has_test "$HAS_TEST" \
    '{stack:$stack, package_manager:$pm, has_test:$has_test,
      checks:{install:$install, lint:$lint, typecheck:$typecheck, test:$test, build:$build}}'
}

# Standalone entry
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --workdir) _DETECT_WORKDIR="${2:-}"; shift 2 ;;
      --json) _DETECT_JSON=1; shift ;;
      -h|--help) detect_stack_usage; exit 0 ;;
      *) echo "Unknown: $1" >&2; exit 2 ;;
    esac
  done
  [[ -n "$_DETECT_WORKDIR" ]] || { detect_stack_usage; exit 2; }
  detect_stack "$_DETECT_WORKDIR"
  if [[ "$_DETECT_JSON" -eq 1 ]]; then
    detect_stack_json
  else
    echo "stack=$STACK pm=$PM has_test=$HAS_TEST"
    echo "install=$INSTALL"
    echo "lint=$LINT"
    echo "typecheck=$TYPECHECK"
    echo "test=$TEST"
    echo "build=$BUILD"
  fi
fi
