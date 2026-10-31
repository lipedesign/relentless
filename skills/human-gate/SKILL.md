---
name: human-gate
description: Block work pending a human decision. Posts decision-request template; applies human:pending + exactly one state:blocked (swap). Never bare-remove pending. Durable choices draft or link an ADR.
---

# Human gate

## Required comment
Follow `core/templates/decision-request.md` (question, numbered options with pros/cons, recommendation + markers).

## Durable decisions → ADR
If the options change architecture, a public contract, merge/security policy, or another rule that should outlive the issue:
1. Create a **proposed** ADR before or with the request:
   `core/scripts/new-adr.sh --workdir . --title "…" --slug … --issue N`
2. Mention the path in the decision-request body (`Proposed ADR: docs/decisions/adr/NNNN-….md`).
3. Resolve with `/decide` + `--adr` (or `--create-adr`) so Status becomes **accepted** and **Decided by** is filled.

Ephemeral tactical choices may use `--no-adr`.

## Flow
1. Draft body → `core/scripts/request-decision.sh --repo … --issue N --body-file …`
   - Adds `human:pending`
   - **Swaps** to `state:blocked` (removes other `state:*`; never stacks)
   - Assigns `decider.github`
2. Resolve only via `/decide` / `decide.sh` (☺️ + `human:decided` + `state:todo` swap; ADR when durable).

Config path resolves from git root `.relentless/config.json` when relative CWD fails.
