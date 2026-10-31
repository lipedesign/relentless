# Decision records

First-class Relentless practice. **Read `docs/decisions/` before planning or implementing.**

Two layers:

| Kind | Path | Human gate? | When |
|------|------|-------------|------|
| **ADR** | `docs/decisions/adr/NNNN-<slug>.md` | **Yes** — explicit owner OK via `/decide`. Silence ≠ approval. | Architecture, public contract, merge/security policy, durable product choice |
| **Note** | `docs/decisions/notes/YYYY-MM-DD-<slug>.md` | **No** | Measured behavior kept on purpose; author doctrine; non-contract scope clarifications |

## ADR vs note
- Changes how the system is built or what it promises externally → **ADR** + human gate.
- Records what the code already does and marks it intentional → **note**.
- Unsure → start a note; promote to ADR if a contract appears.

## Lifecycle (durable human decisions)
1. Agent drafts `decision-request` (numbered options with pros/cons) and may pre-create `docs/decisions/adr/NNNN-<slug>.md` with **Status: proposed**.
2. `request-decision.sh` → `human:pending` + `state:blocked`.
3. Human picks an option → `/decide` / `decide.sh --adr PATH` (or `--create-adr --title … --slug …`).
4. Decide flow sets ADR **Status: accepted**, fills **Decision** + **Decided by**, comments `ADR: docs/decisions/adr/…` on the issue, flips `human:decided`.
5. Implementer/planner **read ADRs** before touching a decided area. Reviewer **requires** PRs that touch a decided area to reference the ADR path in the PR body or commits.

## Index
Keep the bullet list below current when adding records.

### ADRs
- [ADR 0002 — Decision records are first-class](adr/0002-decision-records-first-class.md) — accepted
- [ADR 0001 — Worktree per writer](adr/0001-worktree-per-writer.md) — accepted

### Notes
(none yet)

## Helpers
```bash
core/scripts/new-adr.sh --workdir . --title "…" --slug worktree-per-writer [--issue N]
core/scripts/decide.sh --repo OWNER/NAME --issue N --option K --adr docs/decisions/adr/0001-….md
core/scripts/decide.sh --repo OWNER/NAME --issue N --option K --create-adr --title "…" --slug …
```
