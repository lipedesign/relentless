# Follow-ups after review of <milestone>

Use when isolated review (or milestone close) produces findings that are **not** fixed in the same PR.

## Framing
- **User-facing / product gap** → open (or extend) an **outcome-framed milestone** (`Theme: subtitle` with exit criterion verified by using the product), then put issues under it.
- **Engineering-only debt** → issues under the **current** outcome milestone (do not invent a fake "cleanup" milestone).

## Issue title pattern
`Fixes after review of <milestone-title>: <short finding>`

## Body must include
- Link to the review PR / comment
- Severity label when applicable (`severity:critical|high|medium`)
- Acceptance criteria that close the finding
- Parent epic if the milestone already has one (`--parent`)

## Do not
- Quietly re-open a merged PR for drive-by fixes without an issue
- Park findings only in chat — every finding becomes an issue or an explicit wontfix with ☺️
