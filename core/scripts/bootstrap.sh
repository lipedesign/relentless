#!/usr/bin/env bash
# bootstrap.sh — install Relentless labels + seed consumer files / CI.
# Default dry-run. Seeding is part of the plan unless --no-seed-files.
set -euo pipefail

REPO="" APPLY=0 CONFIG="" WORKDIR="" SEED_FILES=1
MERGE_DEFAULT="" DECIDER_NAME="" DECIDER_GITHUB=""
HARNESS="both"
INIT_EMPTY=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
LABELS_FILE="${SCRIPT_DIR}/../labels/labels.json"
TEMPLATES_ROOT="${SCRIPT_DIR}/../templates"
SCHEMA_EXAMPLE="${SCRIPT_DIR}/../schemas/config.example.json"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME [options]

  --repo OWNER/NAME
  --workdir PATH           Local checkout (needed to seed on disk / initial commit)
  --apply                  Perform changes (default: dry-run)
  --config PATH            Config to validate
  --no-seed-files          Skip seeding
  --check-scopes           Only check gh token scopes and exit
  --merge-default auto|human   Set merge.default when seeding/writing config
  --decider NAME           Set decider.name (non-interactive)
  --decider-github LOGIN   Set decider.github (default: gh api user login)
  --no-init-empty          Do not create initial commit on empty repos
  --harness claude|codex|both
                           Which agent harness this repo uses (default: both).
                           Seeds .codex/agents/*.toml only when harness is
                           codex or both. Never vendors plugin agents/skills
                           into the consumer — install the plugin instead.

Empty repos: with --workdir and --apply, creates a minimal README commit on main
unless --no-init-empty. Dry-run prints the plan.
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
    --merge-default) MERGE_DEFAULT="${2:-}"; shift 2 ;;
    --decider) DECIDER_NAME="${2:-}"; shift 2 ;;
    --decider-github) DECIDER_GITHUB="${2:-}"; shift 2 ;;
    --no-init-empty) INIT_EMPTY=0; shift ;;
    --harness) HARNESS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$CHECK_SCOPES_ONLY" -eq 1 ]]; then
  check_gh_workflow_scope
  exit $?
fi

[[ -n "$REPO" ]] || { usage; exit 2; }
for cmd in jq gh; do command -v "$cmd" >/dev/null || { echo "error: $cmd required" >&2; exit 1; }; done
[[ -f "$LABELS_FILE" ]] || { echo "error: labels missing" >&2; exit 1; }

if [[ -n "$MERGE_DEFAULT" && "$MERGE_DEFAULT" != "auto" && "$MERGE_DEFAULT" != "human" ]]; then
  echo "error: --merge-default must be auto|human" >&2; exit 2
fi
case "$HARNESS" in
  claude|codex|both) ;;
  *) echo "error: --harness must be claude|codex|both" >&2; exit 2 ;;
esac

MODE="DRY-RUN"; [[ "$APPLY" -eq 1 ]] && MODE="APPLY"
echo "== Relentless bootstrap ($MODE) on $REPO (harness=$HARNESS) =="

SCOPE_OK=0
if check_gh_workflow_scope; then SCOPE_OK=1
else
  if [[ "$APPLY" -eq 1 && "$SEED_FILES" -eq 1 ]]; then
    echo "error: refusing --apply with seed files while 'workflow' scope is missing." >&2
    exit 1
  fi
  echo "warn: continuing without workflow scope (CI seed skipped on apply)" >&2
fi

IS_EMPTY="$(gh repo view "$REPO" --json isEmpty -q .isEmpty 2>/dev/null || echo false)"
DEFAULT_BRANCH="$(gh repo view "$REPO" --json defaultBranchRef -q '.defaultBranchRef.name // empty' 2>/dev/null || true)"

if [[ "$IS_EMPTY" == "true" || -z "$DEFAULT_BRANCH" ]]; then
  echo "empty-repo: no default branch yet"
  if [[ "$INIT_EMPTY" -eq 1 ]]; then
    echo "plan: create initial README commit on main"
    if [[ "$APPLY" -eq 1 ]]; then
      if [[ -z "$WORKDIR" ]]; then
        echo "error: --workdir required to create initial commit on empty repo" >&2
        exit 1
      fi
      mkdir -p "$WORKDIR"
      if [[ ! -d "$WORKDIR/.git" ]]; then
        git clone "https://github.com/${REPO}.git" "$WORKDIR" 2>/dev/null || true
      fi
      # If still empty clone
      (
        cd "$WORKDIR"
        if [[ ! -d .git ]]; then git init -b main; git remote add origin "https://github.com/${REPO}.git" 2>/dev/null || true; fi
        if [[ ! -f README.md ]]; then
          printf '# %s\n\nBootstrapped by Relentless.\n' "${REPO##*/}" > README.md
        fi
        git config user.email >/dev/null 2>&1 || git config user.email "relentless-bot@users.noreply.github.com"
        git config user.name >/dev/null 2>&1 || git config user.name "Relentless Bootstrap"
        git add README.md
        if git commit -m "chore: initial commit" 2>/dev/null; then
          git push -u origin HEAD:main
          echo "empty-repo: pushed initial commit"
        else
          # maybe already committed
          git push -u origin HEAD:main 2>/dev/null || true
        fi
      )
    fi
  else
    echo "warn: --no-init-empty; create an initial commit before milestones"
  fi
fi

if [[ -z "$CONFIG" && -n "$WORKDIR" && -f "${WORKDIR}/.relentless/config.json" ]]; then
  CONFIG="${WORKDIR}/.relentless/config.json"
fi

write_or_patch_config() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  if [[ ! -f "$dest" ]]; then
    cp "$SCHEMA_EXAMPLE" "$dest"
  fi
  local login
  login="${DECIDER_GITHUB:-$(gh api user -q .login 2>/dev/null || echo "")}"
  local name="${DECIDER_NAME:-}"
  local merge="${MERGE_DEFAULT:-}"
  local tmp
  tmp="$(mktemp)"
  jq --arg name "$name" --arg gh "$login" --arg merge "$merge" '
    if ($name | length) > 0 then .decider.name = $name else . end |
    if ($gh | length) > 0 then .decider.github = $gh | .workers.default.github = $gh else . end |
    if ($merge | length) > 0 then .merge.default = $merge else . end
  ' "$dest" >"$tmp" && mv "$tmp" "$dest"
  echo "config written: $dest (merge.default=$(jq -r .merge.default "$dest"), decider=$(jq -r .decider.name "$dest"))"
}

if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  echo "config: found $CONFIG"
  if ! jq -e '.decider.name and .decider.github and .merge.default' "$CONFIG" >/dev/null 2>&1; then
    echo "warn: config missing required fields" >&2
  else
    echo "config: basic schema ok"
  fi
  if ! jq -e '.workers and (.workers | type == "object") and (.workers | length > 0)' "$CONFIG" >/dev/null 2>&1; then
    echo "warn: config.workers missing or empty" >&2
  else
    echo "config: workers ok"
  fi
  # Patch flags into existing config on apply
  if [[ "$APPLY" -eq 1 && ( -n "$MERGE_DEFAULT" || -n "$DECIDER_NAME" || -n "$DECIDER_GITHUB" ) ]]; then
    write_or_patch_config "$CONFIG"
  elif [[ -n "$MERGE_DEFAULT" || -n "$DECIDER_NAME" ]]; then
    echo "plan: would set merge.default=${MERGE_DEFAULT:-} decider=${DECIDER_NAME:-} on $CONFIG"
  fi
else
  echo "config: none yet"
  if [[ -n "$MERGE_DEFAULT" || -n "$DECIDER_NAME" ]]; then
    echo "plan: seed config with merge.default=${MERGE_DEFAULT:-'(example)'} decider=${DECIDER_NAME:-'(example)'}"
  fi
fi

EXISTING="$(gh label list --repo "$REPO" --limit 200 --json name -q '.[].name' 2>/dev/null || true)"
while IFS= read -r row; do
  name="$(jq -r '.name' <<<"$row")"
  color="$(jq -r '.color' <<<"$row")"
  desc="$(jq -r '.description' <<<"$row")"
  if grep -Fxq "$name" <<<"$EXISTING"; then
    echo "label exists: $name"
    if [[ "$APPLY" -eq 1 ]]; then
      gh label edit "$name" --repo "$REPO" --color "$color" --description "$desc" >/dev/null || true
    fi
  else
    echo "label create: $name"
    if [[ "$APPLY" -eq 1 ]]; then
      gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" >/dev/null || true
    fi
  fi
done < <(jq -c '.labels[]' "$LABELS_FILE")

seed_copy() {
  local src="$1" dest_rel="$2"
  if [[ -z "$WORKDIR" ]]; then
    echo "seed (needs --workdir): $dest_rel"; return 0
  fi
  local dest="${WORKDIR}/${dest_rel}"
  if [[ -e "$dest" ]]; then
    echo "seed skip (exists): $dest_rel"; return 0
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
    echo "seed: no --workdir; listing paths only"
  fi
  # Config seed with optional patches
  if [[ -n "$WORKDIR" ]]; then
    dest_cfg="${WORKDIR}/.relentless/config.json"
    if [[ -e "$dest_cfg" ]]; then
      echo "seed skip (exists): .relentless/config.json"
      if [[ "$APPLY" -eq 1 && ( -n "$MERGE_DEFAULT" || -n "$DECIDER_NAME" || -n "$DECIDER_GITHUB" ) ]]; then
        write_or_patch_config "$dest_cfg"
      fi
    else
      echo "seed write: .relentless/config.json"
      if [[ "$APPLY" -eq 1 ]]; then
        write_or_patch_config "$dest_cfg"
      fi
    fi
  else
    echo "seed (needs --workdir): .relentless/config.json"
  fi
  seed_copy "${TEMPLATES_ROOT}/github/ISSUE_TEMPLATE/relentless.yml" ".github/ISSUE_TEMPLATE/relentless.yml"
  seed_copy "${TEMPLATES_ROOT}/github/ISSUE_TEMPLATE/investigation.yml" ".github/ISSUE_TEMPLATE/investigation.yml"
  seed_copy "${TEMPLATES_ROOT}/github/PULL_REQUEST_TEMPLATE.md" ".github/PULL_REQUEST_TEMPLATE.md"
  seed_copy "${TEMPLATES_ROOT}/consumer/AGENTS.md" "AGENTS.md"
  seed_copy "${TEMPLATES_ROOT}/consumer/CLAUDE.md" "CLAUDE.md"
  # Do NOT vendor Claude agents/ or skills/ into the consumer — collaborators
  # install the plugin (prefer --scope project). Codex agent tomls are optional
  # stubs only when this repo uses Codex.
  if [[ "$HARNESS" == "codex" || "$HARNESS" == "both" ]]; then
    for agent in planner implementer qa reviewer; do
      src="${SCRIPT_DIR}/../../.codex/agents/${agent}.toml"
      [[ -f "$src" ]] && seed_copy "$src" ".codex/agents/${agent}.toml"
    done
  else
    echo "seed skip (--harness claude): .codex/agents/*.toml"
  fi
  if [[ "$SCOPE_OK" -eq 1 ]]; then
    seed_copy "${TEMPLATES_ROOT}/github/workflows/ci.yml" ".github/workflows/ci.yml"
  else
    echo "seed skip (no workflow scope): .github/workflows/ci.yml"
  fi
  seed_copy "${TEMPLATES_ROOT}/milestone-outcome.md" "docs/relentless/milestone-outcome.example.md"
  seed_copy "${TEMPLATES_ROOT}/epic-body.md" "docs/relentless/epic-body.example.md"
  seed_copy "${TEMPLATES_ROOT}/investigation-body.md" "docs/relentless/investigation-body.example.md"
else
  echo "seed: skipped (--no-seed-files)"
fi

if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  if [[ "$(jq -r '.rulesets.apply // false' "$CONFIG")" == "true" ]]; then
    echo "rulesets: apply=true (fail soft)"
  else
    echo "rulesets: apply=false"
  fi
fi

echo "== done ($MODE) =="
echo "tip: do NOT copy plugin agents/skills into this repo."
echo "tip: Claude — install at PROJECT scope so .claude/settings.json records it for collaborators:"
echo "     claude plugin marketplace add marcelusfernandes/relentless"
echo "     claude plugin install relentless@relentless --scope project -y"
echo "tip: Codex (0.165.x) has no project-scope plugin install — use user-level:"
echo "     codex plugin marketplace add marcelusfernandes/relentless && codex plugin add relentless@relentless"
echo "tip: scripts path → export RELENTLESS_ROOT=\$(claude plugin list --json | …) or ~/.codex/plugins/cache/relentless/relentless/<ver>/"
