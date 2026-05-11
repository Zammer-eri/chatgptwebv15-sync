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

print_log_context() {
	local title="$1"
	local pattern="$2"
	local context="${3:-20}"

	echo ""
	echo "::group::$title"
	grep -n -E -C "$context" "$pattern" "$BUILD_LOG" || echo "No matches for: $pattern"
	echo "::endgroup::"
}

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
	echo "::error::xcodebuild archive failed with exit code $status"
	echo "Local archive log captured at: $BUILD_LOG"
	print_log_context "Swift compiler errors" '(^|[^A-Za-z])(error|fatal error):' 25
	print_log_context "ChatGPTShellDiagnostics.swift context" 'ChatGPTShellDiagnostics\.swift' 35
	print_log_context "Swift compile commands" 'SwiftCompile|CompileSwift' 18
	print_log_context "Failed frontend command context" 'Failed frontend command' 35
	print_log_context "Relevant project file diagnostics" 'ContentDelegate\.swift|BrowserLayout\.swift|BrowserViewController\.swift|BrowserActions\.swift|TabManagerImpl\.swift' 18
	echo ""
	echo "::group::Last 300 lines of xcodebuild archive log"
	tail -n 300 "$BUILD_LOG" || true
	echo "::endgroup::"
	exit "$status"
fi
