#!/usr/bin/env python3

from __future__ import annotations

import hashlib
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
INPUTS = [
    ROOT_DIR / "engine" / "release.txt",
    ROOT_DIR / "tools" / "development" / "build-gecko.sh",
]


def update_file(hasher: "hashlib._Hash", path: Path) -> None:
    relative_path = path.relative_to(ROOT_DIR).as_posix()
    hasher.update(relative_path.encode("utf-8"))
    hasher.update(b"\0")
    hasher.update(path.read_bytes())
    hasher.update(b"\0")


def main() -> int:
    hasher = hashlib.sha256()
    for path in INPUTS:
        update_file(hasher, path)

    for path in sorted((ROOT_DIR / "patches").rglob("*.patch")):
        update_file(hasher, path)

    print(hasher.hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
