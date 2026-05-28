#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SUBMODULE_PATH="$REPO_ROOT/support/idevice"
IDEVICE_URL="https://github.com/jkcoxson/idevice"
FFI_DIR="$SUBMODULE_PATH/ffi"
OUTPUT_LIB="$REPO_ROOT/browser/Reynard/JIT/libidevice_ffi.a"
OUTPUT_MARKER="$OUTPUT_LIB.fingerprint"

TARGET_DIR="$SUBMODULE_PATH/target"
DEPLOYMENT_TARGET="14.0"
RUST_TARGET="aarch64-apple-ios"
FEATURES="full,ring"

hash_file() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	else
		openssl dgst -sha256 "$1" | awk '{print $NF}'
	fi
}

hash_stdin() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 256 | awk '{print $1}'
	elif command -v sha256sum >/dev/null 2>&1; then
		sha256sum | awk '{print $1}'
	else
		openssl dgst -sha256 | awk '{print $NF}'
	fi
}

if [ ! -e "$SUBMODULE_PATH/.git" ]; then
  rm -rf "$SUBMODULE_PATH"
  git clone --depth 1 "$IDEVICE_URL" "$SUBMODULE_PATH"
fi

DEPLOYMENT_FLAG="-miphoneos-version-min=${DEPLOYMENT_TARGET}"
CACHE_FINGERPRINT="$(
	{
		printf '%s\n' "$IDEVICE_URL"
		printf '%s\n' "$RUST_TARGET"
		printf '%s\n' "$DEPLOYMENT_TARGET"
		printf '%s\n' "$FEATURES"
		hash_file "$SCRIPT_DIR/build-idevice.sh"
		find "$FFI_DIR" -type f ! -path "*/target/*" ! -path "*/.git/*" -print | LC_ALL=C sort | while IFS= read -r path; do
			printf '%s ' "${path#$SUBMODULE_PATH/}"
			hash_file "$path"
		done
	} | hash_stdin
)"

if [ -f "$OUTPUT_LIB" ] && [ -f "$OUTPUT_MARKER" ] && [ "$(cat "$OUTPUT_MARKER")" = "$CACHE_FINGERPRINT" ]; then
	echo "Using cached idevice bridge at $OUTPUT_LIB"
	echo "  fingerprint: $CACHE_FINGERPRINT"
	exit 0
fi

if ! rustup target list | grep -q "^$RUST_TARGET (installed)"; then
	rustup target add "$RUST_TARGET"
fi

export IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
if [ -n "${RUSTFLAGS:-}" ]; then
  export RUSTFLAGS="${RUSTFLAGS} -C link-arg=${DEPLOYMENT_FLAG}"
else
  export RUSTFLAGS="-C link-arg=${DEPLOYMENT_FLAG}"
fi
export TARGET_DIR

mkdir -p "$(dirname "$OUTPUT_LIB")"
cd "$FFI_DIR"
cargo build --release --target "$RUST_TARGET" --no-default-features --features "$FEATURES"
cp "$TARGET_DIR/$RUST_TARGET/release/libidevice_ffi.a" "$OUTPUT_LIB"
echo "$CACHE_FINGERPRINT" > "$OUTPUT_MARKER"
