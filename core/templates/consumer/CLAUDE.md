# Claude Code — Relentless consumer

Install the Relentless plugin at **project** scope (do not copy agents/skills into this repo):

```bash
claude plugin marketplace add marcelusfernandes/relentless
claude plugin install relentless@relentless --scope project -y
```

That records the plugin in `.claude/settings.json` so collaborators get prompted.

Use Relentless skills/commands. Implementer stops at `state:review`. Reviewer: `claude -p --agent relentless:reviewer` with a `build-review-bundle.sh` file only. After approve: `merge-if-ready.sh`.

For headless logs use `claude -p --output-format stream-json`.
