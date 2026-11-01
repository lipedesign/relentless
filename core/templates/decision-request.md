# Decision request template

Use this exact structure in the issue comment whenever an agent applies `human:pending`
(and usually `state:blocked`). The human should be able to reply with only an option number.

```markdown
🤖 Decision needed

<!-- relentless:author=agent -->
<!-- relentless:decision-request -->

## Question
<One clear question the human must answer.>

## Context
<Short background: why this blocks progress, constraints, links to issue/PR.>

## Options

### 1. <Short label>
- **Pros:** …
- **Cons:** …
- **Changes:** …
- **Affects:** … (code, milestones, other ADRs)
- **Risks:** …
- **Cost of reverting:** …

### 2. <Short label>
- **Pros:** …
- **Cons:** …
- **Changes:** …
- **Affects:** … (code, milestones, other ADRs)
- **Risks:** …
- **Cost of reverting:** …

### 3. <Short label>   <!-- add more as needed; keep numbered -->
- **Pros:** …
- **Cons:** …
- **Changes:** …
- **Affects:** … (code, milestones, other ADRs)
- **Risks:** …
- **Cost of reverting:** …

## Recommendation
**Option <N>** — <one or two sentences of agent reasoning.>

---
Reply with the option number (e.g. `1`). The decider records it in their own terminal, outside the agent session:

```bash
core/scripts/decide.sh --repo OWNER/NAME --issue N --option <N>
```

On Claude, typing `/decide <issue> <option>` is enough (the UserPromptSubmit hook records it). Agents must not run `decide.sh`; a refusal is expected, not a broken lock.
```

Rules:
- Always number options starting at 1.
- Every option MUST have short pros and cons, what changes, what it affects (code, milestones, other ADRs), the risks, and the cost of reverting.
- Always include an explicit recommendation with reasoning.
- Do not apply `human:pending` without posting this template first (same comment or immediately before the label change).
- Do not remove `human:pending` by deleting the label. The decider flips it to `human:decided` by running `decide.sh` outside the agent session (or by typing `/decide` on Claude).
