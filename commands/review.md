---
description: Spawn isolated reviewer with only issue acceptance criteria, PR diff, and QA/dogfood section
argument-hint: "<pr-number> [issue-number]"
---

# /review

1. Collect ONLY: issue body (acceptance criteria), `gh pr diff $1`, QA/dogfood sections.
2. Start a **fresh** reviewer session (`agents/reviewer.md`) — no implementer chat.
3. Parse verdict; run `core/scripts/apply-review-verdict.sh --repo … --issue … --pr … --verdict approved|changes_requested`.
