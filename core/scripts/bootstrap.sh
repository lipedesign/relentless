#!/usr/bin/env bash
# bootstrap.sh — apply Relentless labels (and optional config) to a GitHub repo.
# Usage:
#   bootstrap.sh --repo owner/name [--apply] [--config path]
# Default is dry-run (print planned actions only).

set -euo pipefail

REPO=""
APPLY=0
CONFIG=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABELS_FILE="${SCRIPT_DIR}/../labels/labels.json"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --repo OWNER/NAME [--apply] [--config PATH]

  --repo     Target repository (required)
  --apply    Perform changes (default: dry-run)
  --config   Path to .relentless/config.json to validate/copy hints
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --config) CONFIG="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "error: --repo is required" >&2
  usage
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh is required" >&2
  exit 1
fi

if [[ ! -f "$LABELS_FILE" ]]; then
  echo "error: labels file not found: $LABELS_FILE" >&2
  exit 1
fi

MODE="DRY-RUN"
[[ "$APPLY" -eq 1 ]] && MODE="APPLY"
echo "== Relentless bootstrap ($MODE) on $REPO =="

if [[ -n "$CONFIG" ]]; then
  if [[ -f "$CONFIG" ]]; then
    echo "config: found $CONFIG"
    # Light validation of required keys
    for key in decider.workers merge; do :; done
    if ! jq -e '.decider.name and .decider.github and .merge.default' "$CONFIG" >/dev/null 2>&1; then
      echo "warn: config missing required fields (decider.name, decider.github, merge.default)" >&2
    else
      echo "config: basic schema ok (decider + merge.default)"
    fi
  else
    echo "warn: --config path not found: $CONFIG" >&2
  fi
fi

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

# Optional rulesets: opt-in, fail soft (never abort bootstrap)
if [[ -n "$CONFIG" && -f "$CONFIG" ]]; then
  APPLY_RULESETS="$(jq -r '.rulesets.apply // false' "$CONFIG")"
  if [[ "$APPLY_RULESETS" == "true" ]]; then
    echo "rulesets: apply=true (opt-in; fail soft — not implemented as hard requirement in v1)"
    if [[ "$APPLY" -eq 1 ]]; then
      echo "warn: ruleset application skipped/fail-soft in v1 scaffold" >&2
    fi
  else
    echo "rulesets: apply=false (skip)"
  fi
fi

echo "== done ($MODE) =="
