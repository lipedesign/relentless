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

### 2. <Short label>
- **Pros:** …
- **Cons:** …

### 3. <Short label>   <!-- add more as needed; keep numbered -->
- **Pros:** …
- **Cons:** …

## Recommendation
**Option <N>** — <one or two sentences of agent reasoning.>

---
Reply with the option number (e.g. `1`). An agent will record it with `/decide` and flip
`human:pending` → `human:decided`.
```

Rules:
- Always number options starting at 1.
- Every option MUST have short pros and cons.
- Always include an explicit recommendation with reasoning.
- Do not apply `human:pending` without posting this template first (same comment or immediately before the label change).
- Do not remove `human:pending` by deleting the label; flip to `human:decided` via `/decide`.
