# Claude notes (Relentless)

Install the plugin at **project** scope (do not copy agents/skills into this repo):

```bash
claude plugin marketplace add <relentless-repo-or-path>
claude plugin install relentless@relentless --scope project -y
```

Planner order for a new outcome: `create-milestone` → `create-epic` (understanding) → `create-issue --parent`. See skill `decompose-epic` and `AGENTS.md`.
