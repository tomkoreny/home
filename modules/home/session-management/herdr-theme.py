#!/usr/bin/env python3
"""Ensure repo-owned Herdr settings in an existing config.toml.

Herdr owns ~/.config/herdr/config.toml: onboarding writes `onboarding`, and
`herdr config reset-keys` rewrites the whole file. A read-only store symlink
would break both, so instead of managing the file this reconciles only the keys
the desktop setup needs, in place, idempotently.

Keys are written verbatim as TOML lines rather than through a serialiser so the
rest of the file - comments, ordering, and user-owned settings - is left
byte-identical.
"""

from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

# Repo-owned values. Anything else in the file is left alone.
DESIRED = {
    "theme": {
        "auto_switch": "true",
        "dark_name": '"catppuccin"',
        "light_name": '"catppuccin-latte"',
    },
    "ui.toast": {
        "delivery": '"system"',
    },
}


def section_bounds(lines: list[str], name: str) -> tuple[int, int] | None:
    """Return [start, end) line indices of a table's body, or None."""
    header = re.compile(rf"^\s*\[{re.escape(name)}\]\s*$")
    any_header = re.compile(r"^\s*\[")
    for index, line in enumerate(lines):
        if header.match(line):
            end = len(lines)
            for offset in range(index + 1, len(lines)):
                if any_header.match(lines[offset]):
                    end = offset
                    break
            return index + 1, end
    return None


def apply_section(lines: list[str], name: str, desired: dict[str, str]) -> list[str]:
    bounds = section_bounds(lines, name)

    if bounds is None:
        block = [f"[{name}]"] + [f"{key} = {value}" for key, value in desired.items()]
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(block)
        return lines

    start, end = bounds
    body = lines[start:end]
    for key, value in desired.items():
        pattern = re.compile(rf"^\s*#?\s*{re.escape(key)}\s*=")
        for offset, line in enumerate(body):
            if pattern.match(line):
                body[offset] = f"{key} = {value}"
                break
        else:
            # Insert after the last real line so the key cannot land after the
            # blank line that separates this table from the next one.
            tail = len(body)
            while tail > 0 and not body[tail - 1].strip():
                tail -= 1
            body.insert(tail, f"{key} = {value}")

    return lines[:start] + body + lines[end:]


def apply(text: str) -> str:
    lines = text.splitlines()
    for name, desired in DESIRED.items():
        lines = apply_section(lines, name, desired)
    return "\n".join(lines) + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: herdr-theme.py <config.toml>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    original = path.read_text() if path.exists() else ""
    updated = apply(original)

    try:
        parsed = tomllib.loads(updated)
    except tomllib.TOMLDecodeError as error:
        print(f"herdr-theme: refusing to write invalid TOML: {error}", file=sys.stderr)
        return 1

    expected_sections = {
        "theme": {
            "auto_switch": True,
            "dark_name": "catppuccin",
            "light_name": "catppuccin-latte",
        },
        "ui.toast": {
            "delivery": "system",
        },
    }
    for name, expected in expected_sections.items():
        table = parsed
        for component in name.split("."):
            table = table.get(component, {})
        if {key: table.get(key) for key in expected} != expected:
            print(f"herdr-theme: [{name}] did not round-trip: {table}", file=sys.stderr)
            return 1

    if updated != original:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".herdr-theme.tmp")
        temporary.write_text(updated)
        temporary.replace(path)
        print(f"herdr-theme: updated {path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
