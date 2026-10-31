#!/usr/bin/env bash
# write-status-snapshot.sh — write docs/status/mN-status.md at milestone close.
# Usage:
#   write-status-snapshot.sh --repo OWNER/NAME --milestone N|--title TITLE \
#     [--workdir PATH] [--out PATH] [--dry-run]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

REPO="" MS="" TITLE="" WORKDIR="." OUT="" DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --milestone) MS="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    --workdir) WORKDIR="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help)
      echo "Usage: $(basename "$0") --repo OWNER/NAME (--milestone N | --title TITLE) [--workdir PATH] [--out PATH] [--dry-run]"
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$REPO" ]] || { echo "need --repo" >&2; exit 2; }
[[ -n "$MS" || -n "$TITLE" ]] || { echo "need --milestone or --title" >&2; exit 2; }

WORKDIR="$(cd "$WORKDIR" && pwd)"
if [[ -z "$TITLE" ]]; then
  TITLE="$(gh api "repos/${REPO}/milestones/${MS}" --jq .title)"
fi
if [[ -z "$MS" ]]; then
  MS="$(gh api "repos/${REPO}/milestones?state=all&per_page=100" --jq ".[] | select(.title==\"${TITLE}\") | .number" | head -1)"
fi
[[ -n "$MS" ]] || { echo "error: milestone not found" >&2; exit 1; }

# Derive mN from title (M0:, M1 —, or milestone number)
slug="$(printf '%s' "$TITLE" | sed -E 's/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//' | tr '[:upper:]' '[:lower:]' | cut -c1-40)"
OUT="${OUT:-${WORKDIR}/docs/status/m${MS}-${slug}-status.md}"

SHA="$(gh api "repos/${REPO}/commits?per_page=1" --jq '.[0].sha' 2>/dev/null || echo unknown)"
DATE="$(TZ=America/Sao_Paulo date +%Y-%m-%d)"

# Issues table
ROWS=""
while IFS=$'\t' read -r num title state; do
  [[ -n "$num" ]] || continue
  pr="$(gh pr list --repo "$REPO" --search "issue:${num}" --state all --json number -q '.[0].number // empty' 2>/dev/null || true)"  # intentional fail-soft
  [[ -z "$pr" ]] && pr="—"
  ROWS+="| #${num} | ${title} | ${state} | ${pr} | |"$'
'
done < <(gh issue list --repo "$REPO" --milestone "$TITLE" --state all --limit 100 \
  --json number,title,state -q '.[] | "\(.number)\t\(.title)\t\(.state)"' 2>/dev/null || true)  # intentional fail-soft

BODY=$(cat <<EOF
# Milestone status — M${MS} — ${TITLE}

- **Date:** ${DATE} (America/Sao_Paulo)
- **SHA:** \`${SHA}\`
- **Milestone:** ${TITLE} (#${MS})
- **Author role:** orchestrator | documenter

## Outcome
(restated by documenter/orchestrator)

## Issue / PR table

| Issue | Title | State | PR | Notes |
|-------|-------|-------|----|-------|
${ROWS:-"| — | | | | |"}

## Decisions this milestone
| Kind | Path | Summary |
|------|------|---------|
| | | |

## Follow-ups
See \`core/templates/follow-up-after-review.md\`.

## Notes
EOF
)

if [[ "$DRY" -eq 1 ]]; then
  echo "dry-run: would write $OUT"
  printf '%s\n' "$BODY"
  exit 0
fi
mkdir -p "$(dirname "$OUT")"
printf '%s\n' "$BODY" > "$OUT"
echo "wrote $OUT"
