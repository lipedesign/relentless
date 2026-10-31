---
description: Record the human's chosen decision option, comment with ☺️ marker, flip human:pending → human:decided; create or link an ADR for durable choices
argument-hint: "<issue-number> <option-number> [optional note] [--adr PATH | --create-adr --title T --slug S]"
---

# /decide

Record a human decision on a gated issue.

## Arguments
- `$1` — issue number
- `$2` — option number (from the decision-request comment)
- `$3…` — optional free-text note
- Durable decisions: pass `--adr docs/decisions/adr/NNNN-slug.md` **or** `--create-adr --title "…" --slug …`

## Steps
1. Read `.relentless/config.json` for `decider.name` / `decider.github` and default worker.
2. Confirm the issue has `human:pending` (warn if not; still allow recording if user insists).
3. **If the choice is durable** (architecture, public contract, merge/security policy, product rule that should outlive the issue):
   - Prefer an existing proposed ADR from the decision-request, or create one:
     ```bash
     core/scripts/new-adr.sh --workdir . --title "…" --slug … --issue "$1"
     ```
   - Then run decide with `--adr` or `--create-adr`.
4. Run:
   ```bash
   core/scripts/decide.sh --repo OWNER/NAME --issue "$1" --option "$2" --note "${NOTE:-}" \
     --workdir . [--adr PATH | --create-adr --title T --slug S]
   ```
   Infer `OWNER/NAME` from `gh repo view --json nameWithOwner -q .nameWithOwner`.
   Use `--no-adr` only for ephemeral tactical choices that must not become records.
5. The script posts a ☺️ comment with:
   - `<!-- relentless:author=human decider="<name>" -->`
   - `<!-- relentless:decision option="N" adr="…" -->` when an ADR is linked
   - ADR file updated: Status → accepted, Decided by, Decision section
   and flips labels: remove `human:pending`, add `human:decided`, clear blocked, set `state:todo`, reassign worker.
6. Summarize the recorded option (and ADR path) to the user.

## Do not
- Invent an option the human did not choose
- Bare-remove `human:pending` without the decided label and ☺️ comment
- Accept a durable architectural choice without an ADR
