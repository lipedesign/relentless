# Codex agents (consumer stub)

Copy Relentless `.codex/agents/*.toml` into this project if you maintain local overrides,
or rely on the installed Relentless plugin agents.

Isolated reviewer (required):

```bash
# Gather inputs only — no implementer chat
codex exec --sandbox read-only "$(cat <<'PROMPT'
You are the Relentless REVIEWER. Read-only. Use ONLY:
1) Issue acceptance criteria (pasted below)
2) PR diff (pasted below)
3) QA / dogfood section (pasted below)

Output the structured verdict from agents/reviewer.md.
PROMPT
)"
```
