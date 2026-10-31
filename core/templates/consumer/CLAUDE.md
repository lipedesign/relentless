# Claude Code — Relentless consumer

Use Relentless skills/commands. Implementer stops at `state:review`. Reviewer: `claude -p --agent relentless:reviewer` with a `build-review-bundle.sh` file only. After approve: `merge-if-ready.sh`.

For headless logs use `claude -p --output-format stream-json`.
