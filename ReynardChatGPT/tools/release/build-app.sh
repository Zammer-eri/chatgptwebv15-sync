#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
XCCONFIG_PATH="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp "$XCCONFIG_PATH" "$DIST_DIR/Reynard.xcconfig"

BUILD_SHA=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || git -C "$ROOT_DIR/.." rev-parse --short HEAD 2>/dev/null || echo UNKNOWN)
sed -i '' "s/CURRENT_BUILD = .*/CURRENT_BUILD = $BUILD_SHA/" "$DIST_DIR/Reynard.xcconfig"

BUILD_LOG="$DIST_DIR/xcodebuild-archive.log"

set +e
xcodebuild archive \
	-scheme "Reynard" \
	-archivePath "$DIST_DIR/Reynard.xcarchive" \
	-project "$PROJECT_PATH" \
	-sdk iphoneos \
	-arch arm64 \
	-configuration Release \
	-xcconfig "$DIST_DIR/Reynard.xcconfig" \
	ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=YES \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY="" 2>&1 | tee "$BUILD_LOG"
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
	echo ""
	echo "xcodebuild archive failed with exit code $status"
	echo "Full archive log: $BUILD_LOG"
	echo ""
	echo "Swift/error diagnostics:"
	grep -n -E '(^|[^A-Za-z])(error|fatal error):|SwiftCompile|CompileSwift|ChatGPTShellDiagnostics\.swift|ContentDelegate\.swift|BrowserLayout\.swift|TabManagerImpl\.swift' "$BUILD_LOG" || true
	echo ""
	echo "ChatGPTShellDiagnostics.swift context:"
	grep -n -A 8 -B 8 'ChatGPTShellDiagnostics\.swift' "$BUILD_LOG" || true
	exit "$status"
fi
