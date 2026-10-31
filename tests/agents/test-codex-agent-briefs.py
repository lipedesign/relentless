#!/usr/bin/env python3
"""Codex agent TOMLs are the only guard (no Claude hooks).

Each .codex/agents/<role>.toml developer_instructions must cover the normative
lines of agents/<role>.md, plus the Codex-only rules that the markdown leaves
to hooks (no commit/push on main, read-only reviewer, and so on).
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROLES = ("orchestrator", "planner", "implementer", "reviewer", "qa", "documenter")

# Codex adaptations that are not always spelled out in the Claude brief,
# because Claude enforces them with hooks. They must still be in the TOML.
CODEX_REQUIRED = {
    "orchestrator": [
        "do not run /decide",
        "decide.sh",
        "accept-adr.sh",
        "decided by",
        "decider.name",
        "own terminal",
        "expected",
        "do not retry",
        "do not stall for a human",
        "state:review",
        "merge-if-ready",
        "do not self-review",
        "worktree",
        "main",
        "never force-push",
    ],
    "planner": [
        "do not run /decide",
        "decide.sh",
        "decided by",
        "proposed",
        "--status accepted",
        "decider.name",
        "own terminal",
        "human:pending",
        "do not implement",
        "main",
    ],
    "implementer": [
        "own worktree",
        "state:review",
        "stop",
        "never commit",
        "never push",
        "main",
        "self-review",
        "do not merge",
        "review:approved",
        "decide.sh",
        "accept-adr.sh",
        "decided by",
        "decider.name",
        "own terminal",
        "do not retry",
        "origin/main",
    ],
    "reviewer": [
        "read-only",
        "acceptance criteria",
        "diff",
        "qa",
        "adr",
        "do not edit",
        "do not commit",
        "approved",
        "changes_requested",
        "decide.sh",
        "decided by",
        "decider.name",
    ],
    "qa": [
        "dogfood",
        "fill-qa-section",
        "do not silently patch",
        "follow-up",
        "readme",
        "docs/decisions",
        "do not merge",
        "main",
        "decide.sh",
        "decided by",
        "decider.name",
        "own terminal",
    ],
    "documenter": [
        "milestone close",
        "write-status-snapshot",
        "docs/decisions",
        "readme",
        "review:approved",
        "human-gated",
        "do not write decided by",
        "decide.sh",
        "decider.name",
        "main",
    ],
}

DENY_NAMES = ("marcelus", "fernandes")
STOPWORDS = {
    "about", "after", "again", "agent", "agents", "allow", "allows", "along",
    "already", "another", "apply", "around", "because", "before", "being",
    "below", "between", "brief", "could", "every", "exists", "first", "fresh",
    "human", "issue", "issues", "never", "other", "please", "should", "still",
    "their", "there", "these", "those", "under", "using", "which", "while",
    "would", "write", "writes", "your",
}


def strip_frontmatter(text: str) -> tuple[str, str]:
    if text.startswith("---\n"):
        end = text.find("\n---\n", 4)
        if end != -1:
            return text[4:end], text[end + 5 :]
    return "", text


def strip_code_fences(text: str) -> str:
    return re.sub(r"```.*?```", "", text, flags=re.S)


def normative_lines(md: str) -> list[str]:
    front, body = strip_frontmatter(md)
    desc = ""
    match = re.search(r"^description:\s*(.+)$", front, re.M)
    if match:
        desc = match.group(1).strip()
    lines: list[str] = []
    if desc and any(
        phrase in desc.lower() for phrase in ("do not", "never ", "must not", "must do", " stop")
    ):
        lines.append(desc)
    in_code = False
    heading_normative = False
    for raw in strip_code_fences(body).splitlines():
        if raw.strip().startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        if raw.startswith("#"):
            heading = raw.lstrip("#").strip().lower()
            heading_normative = any(
                key in heading
                for key in (
                    "do not",
                    "must not",
                    "must do",
                    "human decision",
                    "isolation",
                    "explicit failure",
                )
            )
            continue
        text = raw.strip()
        if not text:
            continue
        lowered = text.lower()
        is_bullet = bool(re.match(r"[-*]|\d+\.", text))
        if any(
            phrase in lowered
            for phrase in ("do not", "never ", "must not", "must do", " stop")
        ):
            lines.append(text)
        elif heading_normative and is_bullet:
            lines.append(text)
    return lines


def clean_token(token: str) -> str:
    return token.strip().lower().strip(".,;:!?\"'()[]")


def keywords(line: str) -> list[str]:
    found: list[str] = []
    for code in re.findall(r"`([^`]+)`", line):
        token = clean_token(code)
        if len(token) >= 4:
            found.append(token)
    plain = re.sub(r"`[^`]*`", " ", line)
    plain = re.sub(r"[*_]", "", plain)
    for word in re.findall(r"[A-Za-z][A-Za-z0-9:_./-]{3,}", plain):
        token = clean_token(word)
        if len(token) < 5 or token in STOPWORDS:
            continue
        found.append(token)
    # Preserve order, drop duplicates.
    seen: set[str] = set()
    unique: list[str] = []
    for token in found:
        if token not in seen:
            seen.add(token)
            unique.append(token)
    return unique


def developer_instructions(toml_text: str) -> str:
    match = re.search(
        r'developer_instructions\s*=\s*"""(.*?)"""',
        toml_text,
        re.S,
    )
    if not match:
        return ""
    return match.group(1)


def main() -> int:
    failures: list[str] = []
    for role in ROLES:
        md_path = ROOT / "agents" / f"{role}.md"
        toml_path = ROOT / ".codex" / "agents" / f"{role}.toml"
        if not md_path.is_file():
            failures.append(f"{role}: missing {md_path}")
            continue
        if not toml_path.is_file():
            failures.append(f"{role}: missing {toml_path}")
            continue
        instructions = developer_instructions(toml_path.read_text())
        if len(instructions.strip()) < 400:
            failures.append(f"{role}: developer_instructions missing or too short")
            continue
        lowered = instructions.lower()
        for name in DENY_NAMES:
            if name in lowered:
                failures.append(f"{role}: hardcoded name {name!r} in developer_instructions")
        for phrase in CODEX_REQUIRED[role]:
            if phrase not in lowered:
                failures.append(f"{role}: Codex rule missing from TOML: {phrase}")
        for line in normative_lines(md_path.read_text()):
            missing = [token for token in keywords(line) if token not in lowered]
            # A paraphrase may drop a function word. Require the concrete tokens
            # (code spans and the longer words) so a new prohibition in the brief
            # fails this check until the TOML covers it.
            if missing:
                failures.append(
                    f"{role}: TOML does not cover brief line {line.strip()!r}; missing {missing}"
                )
    if failures:
        print(f"fail={len(failures)}")
        for item in failures:
            print(item)
        return 1
    print(f"pass={len(ROLES)} codex agent briefs cover their markdown rules")
    return 0


if __name__ == "__main__":
    sys.exit(main())
