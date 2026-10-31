---
description: Bootstrap Relentless on a target repo (dry-run first; --merge-default / --decider / --harness; empty-repo initial commit; no vendored agents/skills)
argument-hint: "<owner/name> [workdir]"
---

# /bootstrap

First ensure the plugin is installed for this repo (Claude: **project** scope):

```bash
claude plugin marketplace add marcelusfernandes/relentless
claude plugin install relentless@relentless --scope project -y
# Codex has no project scope (0.165.x): codex plugin marketplace add … && codex plugin add relentless@relentless
```

Then:

```bash
core/scripts/bootstrap.sh --check-scopes
core/scripts/bootstrap.sh --repo $1 --workdir ${2:-.} \
  --merge-default auto --decider Marcelus --harness both
# after approval:
core/scripts/bootstrap.sh --repo $1 --workdir ${2:-.} \
  --merge-default auto --decider Marcelus --harness both --apply
```

`--harness claude` skips seeding `.codex/agents/*.toml`. Empty repos get an initial README commit on apply (unless `--no-init-empty`).
