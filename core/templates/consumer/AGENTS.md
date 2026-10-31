# Agent notes (Relentless)

This repo is bootstrapped with Relentless. **Do not vendor** plugin `agents/` or `skills/` here — install the plugin:

- Claude: `claude plugin install relentless@relentless --scope project -y` (after marketplace add)
- Codex 0.165.x: no project-scope install; each person runs `codex plugin add relentless@relentless`

Follow plugin doctrine and `docs/harness-profiles.md`.

Quick loop: implement → QA → `state:review` → **isolated** reviewer → `apply-review-verdict` → `merge-if-ready`.
