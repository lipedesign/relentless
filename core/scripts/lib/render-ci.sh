#!/usr/bin/env bash
# render-ci.sh — write .github/workflows/relentless-ci.yml from detect_stack globals.
# Requires STACK, PM, HAS_TEST, INSTALL, LINT, TYPECHECK, TEST, BUILD.
# shellcheck shell=bash

render_relentless_ci_to_file() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"

  if [[ "$STACK" == "unknown" || "$HAS_TEST" -eq 0 ]]; then
    cat > "$dest" <<YAML
name: relentless-ci

on:
  push:
    branches: [main, master]
  pull_request:

# Relentless: no reliable test command detected — FAIL closed.
# merge-if-ready trusts CI green; a silent pass is unsafe.
jobs:
  configure-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Relentless — configure project checks
        run: |
          echo "::error::Relentless could not detect a reliable test command (stack=${STACK}, has_test=${HAS_TEST})."
          echo "merge-if-ready trusts CI green — refusing a silent pass."
          echo "Add project checks, then re-run bootstrap --apply, or replace this workflow."
          echo "Detected: install='${INSTALL}' lint='${LINT}' typecheck='${TYPECHECK}' test='${TEST}' build='${BUILD}'"
          exit 1
YAML
    return 0
  fi

  {
    echo "name: relentless-ci"
    echo ""
    echo "on:"
    echo "  push:"
    echo "    branches: [main, master]"
    echo "  pull_request:"
    echo ""
    echo "jobs:"
    echo "  checks:"
    echo "    runs-on: ubuntu-latest"
    echo "    steps:"
    echo "      - uses: actions/checkout@v4"
    case "$STACK" in
      node)
        if [[ "$PM" == "pnpm" ]]; then
          cat <<'NODE'
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "pnpm"
NODE
        elif [[ "$PM" == "yarn" ]]; then
          cat <<'NODE'
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "yarn"
NODE
        elif [[ "$PM" == "bun" ]]; then
          cat <<'NODE'
      - uses: oven-sh/setup-bun@v2
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
NODE
        else
          cat <<'NODE'
      - uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"
NODE
        fi
        ;;
      python)
        cat <<'PY'
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
PY
        ;;
      go)
        cat <<'GO'
      - uses: actions/setup-go@v5
        with:
          go-version: "1.22"
GO
        ;;
      rust)
        cat <<'RUST'
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy
RUST
        ;;
    esac
    if [[ -n "$INSTALL" ]]; then
      echo "      - name: Install"
      echo "        run: ${INSTALL}"
    fi
    if [[ -n "$LINT" ]]; then
      echo "      - name: Lint"
      echo "        run: ${LINT}"
    fi
    if [[ -n "$TYPECHECK" ]]; then
      echo "      - name: Typecheck"
      echo "        run: ${TYPECHECK}"
    fi
    echo "      - name: Test"
    echo "        run: ${TEST}"
    if [[ -n "$BUILD" ]]; then
      echo "      - name: Build"
      echo "        run: ${BUILD}"
    fi
  } > "$dest"
}
