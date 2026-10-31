---
description: Record the human's chosen decision option, comment with ☺️ marker, flip human:pending → human:decided
argument-hint: "<issue-number> <option-number> [optional note]"
---

# /decide

Record a human decision on a gated issue.

## Arguments
- `$1` — issue number
- `$2` — option number (from the decision-request comment)
- `$3…` — optional free-text note

## Steps
1. Read `.relentless/config.json` for `decider.name` / `decider.github` and default worker.
2. Confirm the issue has `human:pending` (warn if not; still allow recording if user insists).
3. Run:
   ```bash
   core/scripts/decide.sh --repo OWNER/NAME --issue "$1" --option "$2" --note "${NOTE:-}"
   ```
   Infer `OWNER/NAME` from `gh repo view --json nameWithOwner -q .nameWithOwner`.
4. The script posts a ☺️ comment with:
   - `<!-- relentless:author=human decider="<name>" -->`
   - `<!-- relentless:decision option="N" -->`
   and flips labels: remove `human:pending`, add `human:decided`, clear `state:blocked`, set `state:todo`, reassign worker.
5. Summarize the recorded option to the user.

## Do not
- Invent an option the human did not choose
- Bare-remove `human:pending` without the decided label and ☺️ comment
