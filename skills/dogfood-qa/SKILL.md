---
name: dogfood-qa
description: QA agent dogfooding — exercise the workflow on the host project and file gaps as issues. Not a separate Proof product.
---

# Dogfood QA

## Role
The **qa** agent uses this skill to dogfood Relentless on the repository that consumes it (including Relentless itself).

## What to do
1. Walk a thin path: bootstrap dry-run → sample issue → human-gate decision-request → `/decide` → state transitions.
2. Note broken scripts, missing docs, unclear labels, template gaps.
3. File issues under an outcome milestone (not a chore bucket).
4. Add a short QA section to the PR or issue summarizing what was exercised and what failed.

## What not to do
- Do not invent a separate "Proof" / provas product surface
- Do not apply bootstrap `--apply` to unrelated repos
