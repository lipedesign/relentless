# Agent notes (Relentless)

This repo is bootstrapped with Relentless. Follow the plugin doctrine (`AGENTS.md` in the Relentless plugin) and `docs/harness-profiles.md`.

Quick loop: implement → QA → `state:review` → **isolated** reviewer → `apply-review-verdict` → `merge-if-ready`.

Implementer never self-reviews. Prefer `merge-if-ready.sh` for the final merge step.
