---
description: Bootstrap Relentless on a target repo (dry-run first; supports --merge-default / --decider; empty-repo initial commit)
argument-hint: "<owner/name> [workdir]"
---

# /bootstrap

```bash
core/scripts/bootstrap.sh --check-scopes
core/scripts/bootstrap.sh --repo $1 --workdir ${2:-.} \
  --merge-default auto --decider Marcelus
# after approval:
core/scripts/bootstrap.sh --repo $1 --workdir ${2:-.} \
  --merge-default auto --decider Marcelus --apply
```

Empty repos get an initial README commit on apply (unless `--no-init-empty`).
