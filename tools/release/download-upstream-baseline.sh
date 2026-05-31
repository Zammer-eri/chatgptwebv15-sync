#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
TAG="${REYNARD_BASELINE_TAG:-0.4.0}"
ASSET="${REYNARD_BASELINE_ASSET:-Reynard-TrollStore.tipa}"
URL="https://github.com/minh-ton/reynard-browser/releases/download/${TAG}/${ASSET}"
EXPECTED_SHA256="${REYNARD_BASELINE_SHA256:-09e1d8d290112fffacbfecb8249b3bb587fdfeac801505c959f261a75aa7b7ac}"
OUT="$DIST_DIR/Reynard-TrollStore.tipa"
PYTHON_BIN="$(command -v python3 || command -v python)"

hash_file() {
	"$PYTHON_BIN" -c 'import hashlib, pathlib, sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())' "$1"
}

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "Downloading upstream Reynard baseline:"
echo "  tag: $TAG"
echo "  asset: $ASSET"
echo "  url: $URL"

curl -L --fail --retry 3 -o "$OUT" "$URL"

ACTUAL_SHA256="$(hash_file "$OUT")"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
	echo "Baseline checksum mismatch." >&2
	echo "Expected: $EXPECTED_SHA256" >&2
	echo "Actual:   $ACTUAL_SHA256" >&2
	exit 1
fi

echo "Baseline verified: $ACTUAL_SHA256"
