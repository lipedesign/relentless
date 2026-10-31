---
description: Record the human's chosen decision option, comment with ☺️ marker, flip human:pending → human:decided; create or link an ADR for durable choices
argument-hint: "<issue-number> <option-number> [optional note] [--adr PATH | --create-adr --title T --slug S]"
---

# /decide

Record a human decision on a gated issue.

Run this only when the decider stated the option in this session (they typed `/decide` or named the option). Without `human:pending` and a decision-request comment, stop. Do not invent a decision.

## Who runs it

- **Claude:** a UserPromptSubmit hook sees the typed `/decide` and records the decision itself. The agent does not call `decide.sh`.
- **Codex:** commands have no TTY, even in the interactive TUI, so the human cannot confirm `/decide` from inside a Codex session at all. `decide.sh` refuses. That refusal is expected behavior, not a broken lock. Do not retry or try another route. The decider runs it in their own terminal, outside the agent session:

```bash
core/scripts/decide.sh --repo OWNER/NAME --issue N --option K
```

The script prints that exact command (with the real repo, issue, and option) when it refuses.

## Arguments
- `$1` — issue number
- `$2` — option number (from the decision-request comment)
- `$3…` — optional free-text note
- Durable decisions: pass `--adr docs/decisions/adr/NNNN-slug.md` **or** `--create-adr --title "…" --slug …`

## Steps

Recording is not an agent action. Do not run the script from this session.

1. Confirm the issue has `human:pending` and a decision-request comment. If either is missing, stop.
2. **Claude:** the UserPromptSubmit hook already recorded a typed `/decide` before this command is handled. Summarize that result (option, ADR path). Do not call `decide.sh`.
3. **Codex or any agent shell:** do not call `decide.sh`. Tell the decider (`decider.name` from `.relentless/config.json`) to run this in their own terminal, outside the agent session, then move on. A refusal is expected. Do not retry.

```bash
core/scripts/decide.sh --repo OWNER/NAME --issue "$1" --option "$2" --note "${NOTE:-}" \
  --workdir . [--adr PATH | --create-adr --title T --slug S]
```

Infer `OWNER/NAME` from `gh repo view --json nameWithOwner -q .nameWithOwner`. Use `--no-adr` only for ephemeral choices. Durable choices pass `--adr` or `--create-adr`. `new-adr.sh` stays `--status proposed` until that human command accepts it.

When the decider runs it, the script reads `/dev/tty`, posts a ☺️ comment (`relentless:author=human`, and `relentless:decision` when an ADR is linked), sets the ADR to **accepted** / **Decided by**, and flips `human:pending` → `human:decided`, `state:todo`, reassign worker.

## Do not
- Run this from an agent role, or retry after `decide.sh` refuses
- Invent an option the human did not choose
- Write `Decided by` by hand, or pass `--status accepted` to `new-adr.sh` (ADRs are created **proposed**)
- Bare-remove `human:pending` without the decided label and ☺️ comment
- Accept a durable architectural choice without an ADR
