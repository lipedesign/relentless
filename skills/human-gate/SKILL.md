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
3. The **decider** resolves it, not the agent. On Claude they type `/decide` (the UserPromptSubmit hook records it). On Codex, and from any terminal, they run `decide.sh` themselves with `--adr` (or `--create-adr`). Agents do not run `/decide`, `decide.sh`, or `accept-adr.sh`, and do not write `Decided by`. A refusal is expected.

Ephemeral tactical choices may use `--no-adr`.

## Flow
1. Draft body → `core/scripts/request-decision.sh --repo … --issue N --body-file …`
   - Adds `human:pending`
   - **Swaps** to `state:blocked` (removes other `state:*`; never stacks)
   - Assigns `decider.github`
2. The decider resolves it outside the agent session (`/decide` on Claude, or `decide.sh` in their own terminal). That posts ☺️ + `human:decided` + `state:todo` (ADR when durable). Agents do not call the script. If the issue is `human:pending`, tell the decider (`decider.name`) the exact command and move on.

Config path resolves from git root `.relentless/config.json` when relative CWD fails.
