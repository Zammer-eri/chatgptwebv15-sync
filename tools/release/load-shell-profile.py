#!/usr/bin/env python3

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
APP_DIR = ROOT_DIR / "apps"
ALLOWED_KEYS = {
    "CURRENT_VERSION",
    "SHELL_TARGET",
    "SHELL_DISPLAY_NAME",
    "SHELL_BUNDLE_IDENTIFIER",
    "SHELL_URL_SCHEME",
    "SHELL_PACKAGE_BASENAME",
    "SHELL_RELEASE_TAG",
    "SHELL_PACKAGE_OPENIN_EXTENSION",
}


def parse_xcconfig(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//") or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key in ALLOWED_KEYS:
            values[key] = value
    return values


def write_github_env(values: dict[str, str]) -> None:
    env_path = os.environ.get("GITHUB_ENV")
    output = "\n".join(f"{key}={value}" for key, value in values.items()) + "\n"
    if env_path:
        with open(env_path, "a", encoding="utf-8") as env_file:
            env_file.write(output)
    else:
        sys.stdout.write(output)


def main() -> int:
    target = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("SHELL_TARGET", "browser")).strip().lower()
    if not re.fullmatch(r"[a-z0-9_-]+", target):
        print(f"Invalid shell target: {target}", file=sys.stderr)
        return 2

    profile_path = APP_DIR / target / "app.xcconfig"
    if not profile_path.exists():
        print(f"Missing shell profile: {profile_path}", file=sys.stderr)
        return 2

    values = parse_xcconfig(profile_path)
    missing = sorted({"CURRENT_VERSION", "SHELL_TARGET", "SHELL_BUNDLE_IDENTIFIER"} - values.keys())
    if missing:
        print(f"Shell profile {profile_path} is missing: {', '.join(missing)}", file=sys.stderr)
        return 2

    write_github_env(values)
    print(f"Loaded shell profile: {profile_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
