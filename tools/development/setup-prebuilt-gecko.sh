#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
TAG="${REYNARD_RELEASE_TAG:-0.3.0}"
ASSET="${REYNARD_RELEASE_ASSET:-Reynard.ipa}"
URL="https://github.com/minh-ton/reynard-browser/releases/download/${TAG}/${ASSET}"
WORK_DIR="$ROOT_DIR/dist/prebuilt-gecko-work"
DIST_DIR="$ROOT_DIR/engine/prebuilt-gecko/obj-aarch64-apple-ios/dist"
BIN_DIR="$DIST_DIR/bin"
INCLUDE_DIR="$DIST_DIR/include/GeckoView"
MARKER="$ROOT_DIR/engine/prebuilt-gecko/.release"
RUNTIME_PATCH_VERSION="39"
EXTENSION_PREF_OVERRIDES="true"
DEFAULT_RELEASE_SHA256=""

if [ "$TAG" = "0.4.0" ] && [ "$ASSET" = "Reynard.ipa" ]; then
	DEFAULT_RELEASE_SHA256="e8e674474b406f0d0549053aa2b52b3a2c7afe7241dbf2947770b6ac836b3938"
fi

RELEASE_SHA256="${REYNARD_RELEASE_SHA256:-$DEFAULT_RELEASE_SHA256}"

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

RUNTIME_PATCH_FINGERPRINT="$(
	{
		printf '%s\n' "$RUNTIME_PATCH_VERSION"
		hash_file "$SCRIPT_DIR/setup-prebuilt-gecko.sh"
		hash_file "$SCRIPT_DIR/patch-prebuilt-gecko.py"
		hash_file "$SCRIPT_DIR/chatgpt-shell/page-runtime.js"
	} | hash_stdin
)"
MARKER_SHA="${RELEASE_SHA256:-unverified}"
MARKER_VALUE="${TAG}/${ASSET}/asset-${MARKER_SHA}/runtime-${RUNTIME_PATCH_VERSION}-${RUNTIME_PATCH_FINGERPRINT}"

echo "Reynard ChatGPT prebuilt setup:"
echo "  release tag: $TAG"
echo "  asset: $ASSET"
echo "  runtime patch version: $RUNTIME_PATCH_VERSION"
echo "  runtime patch fingerprint: $RUNTIME_PATCH_FINGERPRINT"
echo "  release sha256: ${RELEASE_SHA256:-unverified}"
echo "  extension prefs override: $EXTENSION_PREF_OVERRIDES"
echo "  ChatGPT runtime hooks: enabled"

if [ -f "$BIN_DIR/XUL" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$MARKER_VALUE" ]; then
	echo "Using cached prebuilt Gecko dist at $DIST_DIR"
	echo "  ChatGPT runtime hooks patched: cached"
	exit 0
fi

rm -rf "$WORK_DIR" "$ROOT_DIR/engine/prebuilt-gecko"
mkdir -p "$WORK_DIR" "$BIN_DIR" "$INCLUDE_DIR"

echo "Downloading Reynard prebuilt engine payload: $URL"
curl -L --fail --retry 3 -o "$WORK_DIR/Reynard.ipa" "$URL"
if [ -n "$RELEASE_SHA256" ]; then
	ACTUAL_SHA256="$(hash_file "$WORK_DIR/Reynard.ipa")"
	if [ "$ACTUAL_SHA256" != "$RELEASE_SHA256" ]; then
		echo "Downloaded Reynard IPA checksum mismatch."
		echo "Expected: $RELEASE_SHA256"
		echo "Actual:   $ACTUAL_SHA256"
		exit 1
	fi
fi
unzip -q "$WORK_DIR/Reynard.ipa" -d "$WORK_DIR/unpacked"

APP_DIR="$(find "$WORK_DIR/unpacked/Payload" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [ -z "$APP_DIR" ]; then
	echo "No .app found in downloaded Reynard IPA"
	exit 1
fi

GECKOVIEW_FW="$APP_DIR/Frameworks/GeckoView.framework"
if [ ! -f "$GECKOVIEW_FW/XUL" ]; then
	echo "Downloaded Reynard IPA does not contain GeckoView.framework/XUL"
	exit 1
fi

cp -f "$GECKOVIEW_FW/XUL" "$BIN_DIR/XUL"
find "$APP_DIR/Frameworks" -maxdepth 1 -type f -name '*.dylib' -exec cp -f {} "$BIN_DIR/" \;
cp -R "$GECKOVIEW_FW/Frameworks/." "$BIN_DIR/"
find "$BIN_DIR" -maxdepth 1 -type f -name 'libswift*.dylib' -delete
python3 "$SCRIPT_DIR/patch-prebuilt-gecko.py" "$BIN_DIR"

cat > "$INCLUDE_DIR/GeckoViewSwiftSupport.h" <<'EOF'
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifndef MOZ_EXPORT
#define MOZ_EXPORT __attribute__((visibility("default")))
#endif

@protocol EventCallback <NSObject>
- (void)sendSuccess:(id _Nullable)response;
- (void)sendError:(id _Nullable)response;
@end

@protocol GeckoEventDispatcher <NSObject>
- (void)dispatchToGecko:(NSString *_Nonnull)type message:(id _Nullable)message callback:(id<EventCallback> _Nullable)callback NS_SWIFT_NAME(dispatch(toGecko:message:callback:));
- (BOOL)hasListener:(NSString *_Nonnull)type;
@end

@protocol SwiftEventDispatcher <NSObject>
- (void)dispatchWithType:(NSString *_Nonnull)type message:(NSDictionary<NSString *, id> *_Nullable)message callback:(id<EventCallback> _Nullable)callback NS_SWIFT_NAME(dispatch(type:message:callback:));
- (void)attach:(id<GeckoEventDispatcher> _Nullable)dispatcher;
- (void)dispatchToSwift:(NSString *_Nonnull)type message:(id _Nullable)message callback:(id<EventCallback> _Nullable)callback NS_SWIFT_NAME(dispatch(toSwift:message:callback:));
- (void)activate;
- (BOOL)hasListener:(NSString *_Nonnull)type;
@end

@protocol SwiftGeckoViewRuntime <NSObject>
- (id<SwiftEventDispatcher> _Nonnull)runtimeDispatcher;
- (id<SwiftEventDispatcher> _Nonnull)dispatcherByName:(const char *_Nonnull)name;
@optional
- (void)childProcessDidStartWithPID:(int32_t)pid processType:(NSString *_Nonnull)processType;
@end

@protocol GeckoProcessExtension <NSObject>
- (void)lockdownSandbox:(NSString *_Nonnull)revision;
@end

@protocol GeckoViewWindow <NSObject>
- (UIView *_Nullable)view;
- (void)close;
@end

#ifdef __cplusplus
extern "C" {
#endif

MOZ_EXPORT id<GeckoViewWindow> _Nullable GeckoViewOpenWindow(NSString *_Nonnull aId, id<SwiftEventDispatcher> _Nonnull aDispatcher, NSDictionary *_Nonnull aInitData, bool aPrivateMode);

#ifdef __cplusplus
}
#endif
EOF

cat > "$INCLUDE_DIR/IOSBootstrap.h" <<'EOF'
#import <Foundation/Foundation.h>
#include <stdbool.h>
#include <xpc/xpc.h>

#ifndef MOZ_EXPORT
#define MOZ_EXPORT __attribute__((visibility("default")))
#endif

@protocol SwiftGeckoViewRuntime;
@protocol GeckoProcessExtension;

#ifdef __cplusplus
extern "C" {
#endif

MOZ_EXPORT void MainProcessInit(int argc, char **argv, id<SwiftGeckoViewRuntime> runtime);
MOZ_EXPORT void ChildProcessInit(xpc_connection_t connection, id<GeckoProcessExtension> process, id<SwiftGeckoViewRuntime> runtime);
MOZ_EXPORT void ReportJITStatusForChild(int32_t pid, bool enabled, bool hasTXM26);

#ifdef __cplusplus
}
#endif
EOF

echo "$MARKER_VALUE" > "$MARKER"
echo "Prepared prebuilt Gecko dist at $DIST_DIR"
