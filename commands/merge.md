---
description: After isolated review:approved + CI green, run merge-if-ready (auto merge commit or human ready-to-merge)
argument-hint: "<pr-number> [issue-number]"
---

# /merge

Final orchestrator step. Do **not** run from the implementer session.

```bash
core/scripts/merge-if-ready.sh --repo OWNER/NAME --pr $1 --issue ${2:-}
```

See `skills/pr-merge-gate` and `docs/harness-profiles.md`.
