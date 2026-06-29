#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${1:-$ROOT_DIR/dist}"
ENGINE_OBJ_DIR="$ROOT_DIR/engine/firefox/obj-aarch64-apple-ios"
ENGINE_DIST_DIR="$ENGINE_OBJ_DIR/dist"
ARCHIVE_PATH="$OUT_DIR/reynard-engine-dist.tar.gz"
MANIFEST_PATH="$OUT_DIR/reynard-engine-dist.json"
FINGERPRINT="$(python3 "$SCRIPT_DIR/engine-fingerprint.py")"
RELEASE_TAG="$(tr -d '\000\r' < "$ROOT_DIR/engine/release.txt" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

if [ ! -f "$ENGINE_DIST_DIR/bin/XUL" ] || [ ! -f "$ENGINE_DIST_DIR/include/mozilla-config.h" ]; then
	echo "Missing complete Gecko dist at $ENGINE_DIST_DIR"
	exit 1
fi

mkdir -p "$OUT_DIR"
tar -czhf "$ARCHIVE_PATH" -C "$ENGINE_OBJ_DIR" dist

python3 - "$MANIFEST_PATH" "$FINGERPRINT" "$RELEASE_TAG" <<'PY'
import json
import sys
from pathlib import Path

path, fingerprint, release_tag = sys.argv[1:4]
Path(path).write_text(
    json.dumps(
        {
            "engine": "reynard-gecko",
            "format": 2,
            "fingerprint": fingerprint,
            "release": release_tag,
            "archive": "reynard-engine-dist.tar.gz",
        },
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY
