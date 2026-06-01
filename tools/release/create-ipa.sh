#!/bin/sh

set -eu

CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_XCCONFIG="$ROOT_DIR/dist/Reynard.xcconfig"
ARCHIVE_DIR="$ROOT_DIR/dist/Reynard.xcarchive"
APP_DIR="$ARCHIVE_DIR/Products/Applications"
WORK_DIR="$ROOT_DIR/dist/Reynard"
TROLLSTORE_ONLY="${REYNARD_TROLLSTORE_ONLY:-0}"

xcconfig_value() {
	key="$1"
	default_value="$2"
	eval "env_value=\${$key:-}"
	if [ -n "$env_value" ]; then
		printf '%s' "$env_value"
		return
	fi

	if [ -f "$DIST_XCCONFIG" ]; then
		config_value="$(sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*//p" "$DIST_XCCONFIG" | tail -n 1 | sed 's/[[:space:]]*$//')"
		if [ -n "$config_value" ]; then
			printf '%s' "$config_value"
			return
		fi
	fi

	printf '%s' "$default_value"
}

CURRENT_VERSION="$(xcconfig_value CURRENT_VERSION 0.2.0)"
SHELL_TARGET="$(xcconfig_value SHELL_TARGET chatgpt)"
SHELL_URL_SCHEME="$(xcconfig_value SHELL_URL_SCHEME chatgptshell)"
SHELL_PACKAGE_BASENAME="$(xcconfig_value SHELL_PACKAGE_BASENAME ChatGPT-Shell)"
APP_BUNDLE_IDENTIFIER="$(xcconfig_value SHELL_BUNDLE_IDENTIFIER com.chatgpt.shell)"
HELPER_BUNDLE_IDENTIFIER="${SHELL_HELPER_BUNDLE_IDENTIFIER:-$APP_BUNDLE_IDENTIFIER.Helper}"
OPENIN_BUNDLE_IDENTIFIER="${SHELL_OPENIN_BUNDLE_IDENTIFIER:-$APP_BUNDLE_IDENTIFIER.OpenIn}"
PACKAGE_OPENIN_EXTENSION="$(xcconfig_value SHELL_PACKAGE_OPENIN_EXTENSION "")"

if [ -z "$PACKAGE_OPENIN_EXTENSION" ]; then
	if [ "$SHELL_TARGET" = "browser" ]; then
		PACKAGE_OPENIN_EXTENSION=1
	else
		PACKAGE_OPENIN_EXTENSION=0
	fi
fi

sign_macho_files() {
	find Payload -type f -exec sh -c '
		set -e
		for file do
			case "$(file -b "$file")" in
				*Mach-O*)
					echo "Signing Mach-O: $file"
					ldid -S "$file"
					;;
			esac
		done
	' sh {} +
}

verify_macho_signatures() {
	find Payload -type f -exec sh -c '
		set -e
		for file do
			case "$(file -b "$file")" in
				*Mach-O*)
					if ! codesign -dv "$file" >/dev/null 2>&1; then
						echo "Unsigned Mach-O after packaging: $file" >&2
						exit 1
					fi
					;;
			esac
		done
	' sh {} +
}

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

if [ "$PACKAGE_OPENIN_EXTENSION" != "1" ]; then
	rm -rf "$APP_PATH/PlugIns/OpenIn.appex"
fi

# I absolutely hate Apple for this
# Why is my bundle identifier just become unavailable for no reason?
plutil -replace CFBundleShortVersionString -string "$CURRENT_VERSION" "$APP_PATH/Info.plist"
plutil -replace CFBundleIdentifier -string "$APP_BUNDLE_IDENTIFIER" "$APP_PATH/Info.plist"
if [ "$SHELL_TARGET" != "browser" ]; then
	plutil -replace CFBundleURLTypes.0.CFBundleURLSchemes -json "[\"$SHELL_URL_SCHEME\"]" "$APP_PATH/Info.plist"
fi
plutil -replace CFBundleShortVersionString -string "$CURRENT_VERSION" "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist"
plutil -replace CFBundleIdentifier -string "$HELPER_BUNDLE_IDENTIFIER" "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist"
if [ -d "$APP_PATH/PlugIns/OpenIn.appex" ]; then
	plutil -replace CFBundleShortVersionString -string "$CURRENT_VERSION" "$APP_PATH/PlugIns/OpenIn.appex/Info.plist"
	plutil -replace CFBundleIdentifier -string "$OPENIN_BUNDLE_IDENTIFIER" "$APP_PATH/PlugIns/OpenIn.appex/Info.plist"
fi

APP_ENTITLEMENTS="$ROOT_DIR/dist/Reynard.private.generated.entitlements"
HELPER_ENTITLEMENTS="$ROOT_DIR/dist/Reynard-Helper.private.generated.entitlements"
cp "$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "$APP_ENTITLEMENTS"
cp "$ROOT_DIR/browser/Helper/Entitlements/Reynard-Helper.private.entitlements" "$HELPER_ENTITLEMENTS"
plutil -replace application-identifier -string "$APP_BUNDLE_IDENTIFIER" "$APP_ENTITLEMENTS"
plutil -replace application-identifier -string "$HELPER_BUNDLE_IDENTIFIER" "$HELPER_ENTITLEMENTS"

rm -rf "$WORK_DIR" \
	"$ROOT_DIR/dist/$SHELL_PACKAGE_BASENAME.ipa" \
	"$ROOT_DIR/dist/$SHELL_PACKAGE_BASENAME-TrollStore.tipa" \
	"$ROOT_DIR/dist/$SHELL_PACKAGE_BASENAME-Jailbroken.ipa" \
	"$ROOT_DIR/dist/Reynard.ipa" \
	"$ROOT_DIR/dist/Reynard-TrollStore.tipa" \
	"$ROOT_DIR/dist/Reynard-Jailbroken.ipa"
mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

cd "$WORK_DIR"
if [ "$TROLLSTORE_ONLY" != "1" ]; then
	zip -r "../$SHELL_PACKAGE_BASENAME.ipa" Payload -x "._*" -x ".DS_Store" -x "__MACOSX" # normal ipa
fi

PTRACE_JIT_SRC="$ROOT_DIR/browser/Reynard/TrollStore/JIT/ptrace_jit.c"
PTRACE_JIT_OUT="Payload/Reynard.app/ptrace_jit"

"$CLANG_PATH" \
	-arch arm64 \
	-isysroot "$SDK_PATH" \
	-miphoneos-version-min=13.0 \
	-Os \
	"$PTRACE_JIT_SRC" \
	-o "$PTRACE_JIT_OUT"

chmod 0755 "$PTRACE_JIT_OUT"

sign_macho_files

ldid -S"$ROOT_DIR/browser/Reynard/TrollStore/JIT/ptrace_jit.entitlements" "$PTRACE_JIT_OUT"
ldid -S"$APP_ENTITLEMENTS" "Payload/Reynard.app/Reynard"
ldid -S"$HELPER_ENTITLEMENTS" "Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper"
if [ -d "Payload/Reynard.app/PlugIns/OpenIn.appex" ]; then
	ldid -S "Payload/Reynard.app/PlugIns/OpenIn.appex/OpenIn"
fi
verify_macho_signatures
zip -r "../$SHELL_PACKAGE_BASENAME-TrollStore.tipa" Payload -x "._*" -x ".DS_Store" -x "__MACOSX" # trollstore ipa
if [ "$TROLLSTORE_ONLY" != "1" ]; then
	cp "../$SHELL_PACKAGE_BASENAME-TrollStore.tipa" "../$SHELL_PACKAGE_BASENAME-Jailbroken.ipa" # for jailbroken users
fi
