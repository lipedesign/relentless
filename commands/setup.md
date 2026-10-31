---
description: Prepare this GitHub repo for Relentless (interactive setup → bootstrap → PR)
argument-hint: "[OWNER/NAME]"
---

# /relentless:setup

Follow skill **`setup`** end-to-end.

1. Ask merge.default, decider name, harness, and whether to enable GitHub branch protection on main (default **no** — only if the user says yes). Git hooks are always installed; branch protection is not. Optional first outcome.
2. Recommend Claude `--scope project` install (Codex: user-level).
3. `bootstrap.sh --check-scopes` then **dry-run** with `--workdir` of this repo; show stack + CI plan.
4. On approval: `--apply`, commit seeded files on `chore/relentless-setup`, open PR (or note empty-repo main).
5. Optionally `create-milestone` + `create-epic` if the user gave an outcome.

`$ARGUMENTS` may be `OWNER/NAME`. Default workdir `.`.
