#!/usr/bin/env bash
# seed-relentless-docs.sh — insert/update <!-- relentless:start -->…<!-- relentless:end --> blocks.
# shellcheck shell=bash

RELENTLESS_BLOCK_START="<!-- relentless:start -->"
RELENTLESS_BLOCK_END="<!-- relentless:end -->"

# Args: merge_default harness stack install lint typecheck test build
render_relentless_agents_block() {
  local merge_default="${1:-human}"
  local harness="${2:-both}"
  local stack="${3:-unknown}"
  local install="${4:-}"
  local lint="${5:-}"
  local typecheck="${6:-}"
  local test="${7:-}"
  local build="${8:-}"
  cat <<BLOCK
${RELENTLESS_BLOCK_START}
# Relentless workflow (managed — do not edit inside markers)

This repo uses the **Relentless** agent plugin. Do **not** vendor plugin \`agents/\` or \`skills/\` here — install the plugin.

## Wave order
1. Outcome milestone (\`Theme: subtitle\`) via \`create-milestone.sh\`
2. **Parent epic first** (understanding) via \`create-epic.sh\` / skill \`decompose-epic\`
3. Native sub-issues via \`create-issue.sh --parent N\` / \`add-sub-issue.sh\`
4. Implement → QA → \`state:review\` → **isolated** reviewer → \`apply-review-verdict\` → \`merge-if-ready\`

## Labels
- Exactly one \`state:*\` (swap with \`set-state.sh\`)
- Exactly one type: \`bug\` | \`enhancement\` | \`documentation\` | \`investigation\` | \`epic\`
- \`human:pending\` / \`human:decided\` — never bare-remove pending; use \`/decide\`
- Merge override: \`merge:auto\` | \`merge:human\` (default for this repo: **${merge_default}**)

## Authorship markers
- Agent comments: leading 🤖 + \`<!-- relentless:author=agent -->\`
- Human / relayed: leading ☺️ + \`<!-- relentless:author=human decider="…" -->\`

## Project checks (detected stack: **${stack}**)
| Step | Command |
|------|---------|
| install | \`${install:-(none)}\` |
| lint | \`${lint:-(none)}\` |
| typecheck | \`${typecheck:-(none)}\` |
| test | \`${test:-(none)}\` |
| build | \`${build:-(none)}\` |

CI workflow: \`.github/workflows/relentless-ci.yml\` (owned by Relentless; other workflows untouched).

## Harness
Configured for: **${harness}**
- Claude: \`claude plugin install relentless@relentless --scope project -y\`
- Codex 0.165.x: user-level \`codex plugin add relentless@relentless\` (no project scope)

See plugin \`docs/harness-profiles.md\` and \`AGENTS.md\` doctrine.
${RELENTLESS_BLOCK_END}
BLOCK
}

render_relentless_claude_block() {
  local merge_default="${1:-human}"
  local harness="${2:-both}"
  local stack="${3:-unknown}"
  local test="${4:-}"
  cat <<BLOCK
${RELENTLESS_BLOCK_START}
# Relentless (managed — do not edit inside markers)

Install at **project** scope (do not copy agents/skills into this repo):

\`\`\`bash
claude plugin marketplace add marcelusfernandes/relentless
claude plugin install relentless@relentless --scope project -y
\`\`\`

Setup / re-seed: skill \`setup\` or \`/relentless:setup\` → \`core/scripts/bootstrap.sh\`.

Wave: milestone → **epic understanding** → sub-issues (\`--parent\`). Merge default: **${merge_default}**. Stack: **${stack}**. Test: \`${test:-(configure)}\`.
${RELENTLESS_BLOCK_END}
BLOCK
}

# Upsert delimited block in file. Args: path, block_content
upsert_relentless_block() {
  local path="$1"
  local block="$2"
  local dir
  dir="$(dirname "$path")"
  mkdir -p "$dir"

  if [[ ! -f "$path" ]]; then
    printf '%s\n' "$block" > "$path"
    echo "seed write: $path (new)"
    return 0
  fi

  if grep -q "$RELENTLESS_BLOCK_START" "$path" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    # Replace existing block (non-greedy via awk)
    awk -v start="$RELENTLESS_BLOCK_START" -v end="$RELENTLESS_BLOCK_END" -v block="$block" '
      BEGIN { printing=1 }
      index($0, start) == 1 {
        print block
        printing=0
        next
      }
      index($0, end) == 1 {
        printing=1
        next
      }
      printing { print }
    ' "$path" > "$tmp"
    mv "$tmp" "$path"
    echo "seed update: $path (relentless block)"
  else
    {
      echo ""
      printf '%s\n' "$block"
    } >> "$path"
    echo "seed append: $path (relentless block)"
  fi
}
