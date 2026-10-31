# Deferred to v1.1+

Cheap Round-2 items shipped in 1.2.x. The following remain deferred:

| ID | Item | Why deferred |
|----|------|--------------|
| P1-codex-list | `codex plugin list --installed` / default-to-local | Upstream Codex CLI flag; document noise workaround only |
| C5 | Codex rollout/session `thread not found` errors | Upstream Codex; does not block work |
| P2-dual-roots | Dual Codex plugin roots (`.tmp/marketplaces` vs `plugins/cache`) | Document canonical `RELENTLESS_ROOT`; Codex owns layout |
| C9 | Dual GitHub write paths (Codex Apps MCP vs `gh`) | Observation; both OK if isolation preserved |
| P2-claude-y | `-y` on `marketplace add` | Upstream Claude Code CLI |
| P3-dup-bootstrap | Duplicate bootstrap in plugin details inventory | Cosmetic |
| P3-always-on-tok | Always-on ~634 tok injection | Claude plugin surface; tune later |
| P3-consumer-claude-agents | Seed Claude `agents/` into consumer | **Won't do** — install plugin at `--scope project` instead |
| Codex-project-scope | Upstream `codex plugin add --scope` | Not present in 0.165.x; document user-level only until Codex adds it |
| P2-headless-dogfood | Ship puppeteer/playwright helper in plugin | Recipe noted in dogfood-qa; full scaffold is heavier |
| P2-react-input | Document native value setter for controlled inputs | One-liner in dogfood-qa skill (done lightly); full harness later |
| P3-pkill | PID-file guidance for preview servers | Note in dogfood-qa; not a script yet |
| P3-npm-audit | Vite/React audit noise in dogfood CI | Consumer app concern |
| P3-ssh-marketplace | SSH not configured → HTTPS fallback | Documented; fine with `gh` auth |
| v1.1 | Automatic GitHub reviewer *assignment* | Doctrine already says role required; assignment later |
| Rulesets apply | Hard-apply branch rulesets | Remains opt-in fail-soft |

Workarounds documented in README / AGENTS / harness-profiles.
