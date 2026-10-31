#!/usr/bin/env bash
# bootstrap.sh — install Relentless labels + optionally seed consumer files / CI.
# Usage:
#   bootstrap.sh --repo OWNER/NAME [--workdir PATH] [--apply] [--config PATH] [--no-seed-files]
# Default is dry-run (print planned actions). Seeding is part of the plan unless --no-seed-files.

set -euo pipefail

REPO=""
APPLY=0
CONFIG=""
WORKDIR=""
SEED_FILES=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
LABELS_FILE="${SCRIPT_DIR}/../labels/labels.json"
TEMPLATES_ROOT="${SCRIPT_DIR}/../templates"
SCHEMA_EXAMPLE="${SCRIPT_DIR}/../schemas/config.example.json"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME [options]

  --repo          Target repository (required)
  --workdir PATH  Local checkout of the target repo (required to seed files on disk)
  --apply         Perform changes (default: dry-run)
  --config PATH   Config to validate (default: WORKDIR/.relentless/config.json if present)
  --no-seed-files Skip seeding config/templates/CI/AGENTS stubs
  --check-scopes  Only check gh token scopes (workflow) and exit

Dry-run prints every label and seed action. --apply needs the 'workflow' scope
to write .github/workflows/*.yml (run: gh auth refresh -s workflow).
USAGE
}

CHECK_SCOPES_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    --no-seed-files) SEED_FILES=0; shift ;;
    --check-scopes) CHECK_SCOPES_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$CHECK_SCOPES_ONLY" -eq 1 ]]; then
  check_gh_workflow_scope
  exit $?
fi

if [[ -z "$REPO" ]]; then
  echo "error: --repo is required" >&2
  usage
  exit 2
fi

for cmd in jq gh; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: $cmd is required" >&2; exit 1; }
done
[[ -f "$LABELS_FILE" ]] || { echo "error: labels file not found: $LABELS_FILE" >&2; exit 1; }

MODE="DRY-RUN"
[[ "$APPLY" -eq 1 ]] && MODE="APPLY"
echo "== Relentless bootstrap ($MODE) on $REPO =="

# Always surface scope status (fail hard on --apply if seeding workflows and scope missing)
SCOPE_OK=0
if check_gh_workflow_scope; then
  SCOPE_OK=1
else
  if [[ "$APPLY" -eq 1 && "$SEED_FILES" -eq 1 ]]; then
    echo "error: refusing --apply with seed files while 'workflow' scope is missing." >&2
    exit 1
  fi
  echo "warn: continuing without workflow scope (CI template seed will be skipped on apply)" >&2
fi

# Empty-repo guidance
IS_EMPTY="$(gh repo view "$REPO" --json isEmpty -q .isEmpty 2>/dev/null || echo false)"
DEFAULT_BRANCH="$(gh repo view "$REPO" --json defaultBranchRef -q '.defaultBranchRef.name // empty' 2>/dev/null || true)"
if [[ "$IS_EMPTY" == "true" || -z "$DEFAULT_BRANCH" ]]; then
  echo "warn: repository appears empty (no default branch)."
  echo "  Labels/milestones need an initial commit first (e.g. README)."
  echo "  Bootstrap will still plan labels; create a first commit before relying on milestones."
fi

# Resolve config
if [[ -z "$CONFIG" && -n "$WORKDIR" && -f "${WORKDIR}/.relentless/config.json" ]]; then
  CONFIG="${WORKDIR}/.relentless/config.json"
fi
if [[ -n "$CONFIG" ]]; then
  if [[ -f "$CONFIG" ]]; then
    echo "config: found $CONFIG"
    if ! jq -e '.decider.name and .decider.github and .merge.default' "$CONFIG" >/dev/null 2>&1; then
      echo "warn: config missing required fields (decider.name, decider.github, merge.default)" >&2
    else
      echo "config: basic schema ok (decider + merge.default)"
    fi
    if ! jq -e '.workers and (.workers | type == "object") and (.workers | length > 0)' "$CONFIG" >/dev/null 2>&1; then
      echo "warn: config.workers missing or empty (assignees may not resolve)" >&2
    else
      echo "config: workers ok"
    fi
  else
    echo "warn: --config path not found: $CONFIG" >&2
  fi
else
  echo "config: none provided (seed will write .relentless/config.json from example when seeding)"
fi

# Labels
EXISTING="$(gh label list --repo "$REPO" --limit 200 --json name -q '.[].name' 2>/dev/null || true)"
while IFS= read -r row; do
  name="$(jq -r '.name' <<<"$row")"
  color="$(jq -r '.color' <<<"$row")"
  desc="$(jq -r '.description' <<<"$row")"
  if grep -Fxq "$name" <<<"$EXISTING"; then
    echo "label exists: $name (would update color/description)"
    if [[ "$APPLY" -eq 1 ]]; then
      gh label edit "$name" --repo "$REPO" --color "$color" --description "$desc" || \
        echo "warn: failed to edit label $name" >&2
    fi
  else
    echo "label create: $name"
    if [[ "$APPLY" -eq 1 ]]; then
      gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" || \
        echo "warn: failed to create label $name" >&2
    fi
  fi
done < <(jq -c '.labels[]' "$LABELS_FILE")

# Seed files
seed_copy() {
  local src="$1"
  local dest_rel="$2"
  local dest
  if [[ -z "$WORKDIR" ]]; then
    echo "seed (needs --workdir): $dest_rel"
    return 0
  fi
  dest="${WORKDIR}/${dest_rel}"
  if [[ -e "$dest" ]]; then
    echo "seed skip (exists): $dest_rel"
    return 0
  fi
  echo "seed write: $dest_rel"
  if [[ "$APPLY" -eq 1 ]]; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  fi
}

if [[ "$SEED_FILES" -eq 1 ]]; then
  echo "-- seed plan --"
  if [[ -z "$WORKDIR" ]]; then
    echo "seed: no --workdir; listing intended paths only (pass --workdir to write on apply)"
  fi
  seed_copy "$SCHEMA_EXAMPLE" ".relentless/config.json"
  seed_copy "${TEMPLATES_ROOT}/github/ISSUE_TEMPLATE/relentless.yml" ".github/ISSUE_TEMPLATE/relentless.yml"
  seed_copy "${TEMPLATES_ROOT}/github/PULL_REQUEST_TEMPLATE.md" ".github/PULL_REQUEST_TEMPLATE.md"
  seed_copy "${TEMPLATES_ROOT}/consumer/AGENTS.md" "AGENTS.md"
  seed_copy "${TEMPLATES_ROOT}/consumer/CLAUDE.md" "CLAUDE.md"
  # Codex agent stubs (consumer-local copies of plugin briefs as pointers)
  for agent in planner implementer qa reviewer; do
    src="${SCRIPT_DIR}/../../.codex/agents/${agent}.toml"
    if [[ -f "$src" ]]; then
      seed_copy "$src" ".codex/agents/${agent}.toml"
    else
      echo "seed skip (plugin missing ${agent}.toml until shipped): .codex/agents/${agent}.toml"
    fi
  done
  if [[ "$SCOPE_OK" -eq 1 ]]; then
    seed_copy "${TEMPLATES_ROOT}/github/workflows/ci.yml" ".github/workflows/ci.yml"
  else
    echo "seed skip (no workflow scope): .github/workflows/ci.yml"
  fi
  seed_copy "${TEMPLATES_ROOT}/milestone-outcome.md" "docs/relentless/milestone-outcome.example.md"
else
  echo "seed: skipped (--no-seed-files)"
fi

# Optional rulesets: opt-in, fail soft
if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  APPLY_RULESETS="$(jq -r '.rulesets.apply // false' "$CONFIG")"
  if [[ "$APPLY_RULESETS" == "true" ]]; then
    echo "rulesets: apply=true (opt-in; fail soft — not hard-required)"
    if [[ "$APPLY" -eq 1 ]]; then
      echo "warn: ruleset application skipped/fail-soft" >&2
    fi
  else
    echo "rulesets: apply=false (skip)"
  fi
fi

echo "== done ($MODE) =="
