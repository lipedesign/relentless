---
description: Spawn isolated reviewer with only issue AC, PR diff (no lockfiles), and QA; then apply verdict; on approve run merge-if-ready
argument-hint: "<pr-number> [issue-number]"
---

# /review

1. Build bundle (lockfiles excluded):
   ```bash
   core/scripts/build-review-bundle.sh --repo OWNER/NAME --pr $1 --issue $2 --out review-bundle.md
   ```
2. Start a **fresh** reviewer session — no implementer chat:
   - Claude: `claude -p --agent relentless:reviewer "$(cat review-bundle.md)"`
   - Codex: `codex exec --sandbox read-only "$(cat review-bundle.md)"`
3. Parse verdict; run:
   ```bash
   core/scripts/apply-review-verdict.sh --repo … --issue … --pr … --verdict approved|changes_requested
   ```
4. If `approved` → **immediately** `/merge` / `merge-if-ready.sh` (do not stall).
5. If `changes_requested` → issue is already `state:in-progress`; send implementer back.
