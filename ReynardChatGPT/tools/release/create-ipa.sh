#!/bin/sh

set -eu

CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
TOOLCHAIN_DIR="$(CDPATH= cd -- "$(dirname -- "$CLANG_PATH")/../.." && pwd)"
SWIFT_LIB_DIR="$TOOLCHAIN_DIR/usr/lib/swift/iphoneos"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/Reynard.xcarchive"
APP_DIR="$ARCHIVE_DIR/Products/Applications"
WORK_DIR="$ROOT_DIR/dist/Reynard"

cd "$ROOT_DIR"

if [ ! -d "$APP_DIR" ]; then
	echo "Missing archive output at $APP_DIR"
	echo "Run tools/release/build-app.sh first."
	exit 1
fi

APP_PATH="$(find "$APP_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [ -z "$APP_PATH" ]; then
	echo "No .app found in $APP_DIR"
	exit 1
fi

# I absolutely hate Apple for this
# Why is my bundle identifier just become unavailable for no reason?
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard" "$APP_PATH/Info.plist"
plutil -replace CFBundleDisplayName -string "ChatGPT Gecko" "$APP_PATH/Info.plist"
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.Helper" "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist"
plutil -replace CFBundleDisplayName -string "ChatGPT Gecko Helper" "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist"
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.OpenIn" "$APP_PATH/PlugIns/OpenIn.appex/Info.plist"
plutil -replace CFBundleDisplayName -string "Open in ChatGPT Gecko" "$APP_PATH/PlugIns/OpenIn.appex/Info.plist"

rm -rf "$WORK_DIR" "$ROOT_DIR/dist/Reynard.ipa" "$ROOT_DIR/dist/Reynard-TrollStore.ipa"
mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

PAYLOAD_APP_PATH="$WORK_DIR/Payload/$(basename "$APP_PATH")"
PAYLOAD_FRAMEWORKS_PATH="$PAYLOAD_APP_PATH/Frameworks"
mkdir -p "$PAYLOAD_FRAMEWORKS_PATH"

if [ -f "$SWIFT_LIB_DIR/libswift_Concurrency.dylib" ]; then
	cp -f "$SWIFT_LIB_DIR/libswift_Concurrency.dylib" "$PAYLOAD_FRAMEWORKS_PATH/"
else
	echo "Missing Swift concurrency runtime at $SWIFT_LIB_DIR/libswift_Concurrency.dylib"
	exit 1
fi

cd "$WORK_DIR"
zip -r ../Reynard.ipa Payload -x "._*" -x ".DS_Store" -x "__MACOSX" # normal ipa

PTRACE_JIT_SRC="$ROOT_DIR/browser/Reynard/TrollStore/JIT/ptrace_jit.c"
PTRACE_JIT_OUT="Payload/Reynard.app/ptrace_jit"

"$CLANG_PATH" \
	-arch arm64 \
	-isysroot "$SDK_PATH" \
	-miphoneos-version-min=14.0 \
	-Os \
	"$PTRACE_JIT_SRC" \
	-o "$PTRACE_JIT_OUT"

chmod 0755 "$PTRACE_JIT_OUT"

find Payload -type f -exec sh -c '
	for file do
		case "$(file -b "$file")" in
			*Mach-O*)
				ldid -S "$file"
				;;
		esac
	done
' sh {} +

ldid -S"$ROOT_DIR/browser/Reynard/TrollStore/JIT/ptrace_jit.entitlements" "$PTRACE_JIT_OUT"
ldid -S"$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "Payload/Reynard.app/Reynard"
ldid -S"$ROOT_DIR/browser/Helper/Entitlements/Reynard-Helper.private.entitlements" "Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper"
ldid -S "Payload/Reynard.app/PlugIns/OpenIn.appex/OpenIn"
zip -r ../Reynard-TrollStore.tipa Payload -x "._*" -x ".DS_Store" -x "__MACOSX" # trollstore ipa
