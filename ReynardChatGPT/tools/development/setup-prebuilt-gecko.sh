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
SHIM_VERSION="3"

if [ -f "$BIN_DIR/XUL" ] && [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "${TAG}/${ASSET}/shim-${SHIM_VERSION}" ]; then
	echo "Using cached prebuilt Gecko dist at $DIST_DIR"
	exit 0
fi

rm -rf "$WORK_DIR" "$ROOT_DIR/engine/prebuilt-gecko"
mkdir -p "$WORK_DIR" "$BIN_DIR" "$INCLUDE_DIR"

echo "Downloading Reynard prebuilt engine payload: $URL"
curl -L --fail --retry 3 -o "$WORK_DIR/Reynard.ipa" "$URL"
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

echo "${TAG}/${ASSET}/shim-${SHIM_VERSION}" > "$MARKER"
echo "Prepared prebuilt Gecko dist at $DIST_DIR"
