#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
APP_DIR = ROOT_DIR / "apps"
BUMP_TYPES = {
    "patch": (0, 0, 1),
    "fix": (0, 0, 1),
    "minor": (0, 1, 0),
    "feature": (0, 1, 0),
    "major": (1, 0, 0),
    "breaking": (1, 0, 0),
}


def bump_version(version: str, bump_type: str) -> str:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", version)
    if not match:
        raise ValueError(f"Expected semver like 0.1.0, got {version!r}")

    major, minor, patch = (int(part) for part in match.groups())
    delta = BUMP_TYPES[bump_type]

    if delta[0]:
        return f"{major + 1}.0.0"
    if delta[1]:
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: bump-shell-version.py <shell-target> <patch|minor|major>", file=sys.stderr)
        return 2

    target = sys.argv[1].strip().lower()
    bump_type = sys.argv[2].strip().lower()
    if bump_type not in BUMP_TYPES:
        print(f"Unknown bump type: {bump_type}", file=sys.stderr)
        return 2

    profile_path = APP_DIR / target / "app.xcconfig"
    if not profile_path.exists():
        print(f"Missing shell profile: {profile_path}", file=sys.stderr)
        return 2

    lines = profile_path.read_text(encoding="utf-8").splitlines()
    current_version = None
    for line in lines:
        match = re.match(r"^\s*CURRENT_VERSION\s*=\s*(\S+)\s*$", line)
        if match:
            current_version = match.group(1)
            break

    if current_version is None:
        print(f"Missing CURRENT_VERSION in {profile_path}", file=sys.stderr)
        return 2

    next_version = bump_version(current_version, bump_type)
    updated_lines = [
        re.sub(r"^(\s*CURRENT_VERSION\s*=\s*)\S+(\s*)$", rf"\g<1>{next_version}\2", line)
        for line in lines
    ]
    profile_path.write_text("\n".join(updated_lines) + "\n", encoding="utf-8")
    print(f"{target}: {current_version} -> {next_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
