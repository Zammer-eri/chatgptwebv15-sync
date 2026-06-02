#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PROJECT_PATH="$ROOT_DIR/browser/Reynard.xcodeproj"
PROJECT_FILE="$PROJECT_PATH/project.pbxproj"
XCCONFIG_PATH="$ROOT_DIR/browser/Configuration/Reynard.xcconfig"
APP_DIR="$ROOT_DIR/apps"
SELECTED_SHELL_TARGET="${SHELL_TARGET:-browser}"
SHELL_PROFILE_PATH="$APP_DIR/$SELECTED_SHELL_TARGET/app.xcconfig"
PROJECT_BACKUP=""

restore_project_file() {
	if [ -n "$PROJECT_BACKUP" ] && [ -f "$PROJECT_BACKUP" ]; then
		mv "$PROJECT_BACKUP" "$PROJECT_FILE"
	fi
}

trap restore_project_file EXIT

case "$SELECTED_SHELL_TARGET" in
	""|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]*)
		echo "Invalid shell target: $SELECTED_SHELL_TARGET"
		exit 1
		;;
esac

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp "$XCCONFIG_PATH" "$DIST_DIR/Reynard.xcconfig"

if [ ! -f "$SHELL_PROFILE_PATH" ]; then
	echo "Missing shell profile: $SHELL_PROFILE_PATH"
	exit 1
fi

{
	echo ""
	echo "// Selected shell profile: $SELECTED_SHELL_TARGET"
	cat "$SHELL_PROFILE_PATH"
} >> "$DIST_DIR/Reynard.xcconfig"

BUILD_SHA=$(git -C "$ROOT_DIR" rev-parse --short HEAD)
sed -i '' "s/CURRENT_BUILD = .*/CURRENT_BUILD = $BUILD_SHA/" "$DIST_DIR/Reynard.xcconfig"

append_xcconfig_override() {
	name="$1"
	value="$2"
	if [ -n "$value" ]; then
		printf '%s = %s\n' "$name" "$value" >> "$DIST_DIR/Reynard.xcconfig"
	fi
}

append_xcconfig_override SHELL_TARGET "${SHELL_TARGET:-}"
append_xcconfig_override SHELL_DISPLAY_NAME "${SHELL_DISPLAY_NAME:-}"
append_xcconfig_override SHELL_BUNDLE_IDENTIFIER "${SHELL_BUNDLE_IDENTIFIER:-}"
append_xcconfig_override SHELL_URL_SCHEME "${SHELL_URL_SCHEME:-}"
append_xcconfig_override SHELL_PACKAGE_BASENAME "${SHELL_PACKAGE_BASENAME:-}"
append_xcconfig_override SHELL_RELEASE_TAG "${SHELL_RELEASE_TAG:-}"
append_xcconfig_override SHELL_PACKAGE_OPENIN_EXTENSION "${SHELL_PACKAGE_OPENIN_EXTENSION:-}"
append_xcconfig_override CURRENT_VERSION "${CURRENT_VERSION:-}"

profile_value() {
	key="$1"
	awk -F= -v key="$key" '
		$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
			value = $2
			sub(/^[[:space:]]*/, "", value)
			sub(/[[:space:]]*$/, "", value)
			print value
			exit
		}
	' "$SHELL_PROFILE_PATH"
}

PACKAGE_OPENIN_EXTENSION="${SHELL_PACKAGE_OPENIN_EXTENSION:-$(profile_value SHELL_PACKAGE_OPENIN_EXTENSION)}"
if [ -z "$PACKAGE_OPENIN_EXTENSION" ]; then
	if [ "$SELECTED_SHELL_TARGET" = "browser" ]; then
		PACKAGE_OPENIN_EXTENSION=1
	else
		PACKAGE_OPENIN_EXTENSION=0
	fi
fi

if [ "$PACKAGE_OPENIN_EXTENSION" != "1" ]; then
	PROJECT_BACKUP="$PROJECT_FILE.shell-build-backup"
	cp "$PROJECT_FILE" "$PROJECT_BACKUP"
	python3 - "$PROJECT_FILE" <<'PY'
from pathlib import Path
import sys

project_file = Path(sys.argv[1])
text = project_file.read_text(encoding="utf-8")
for entry in (
    "\n\t\t\t\t03OLPBF12F3100000000001 /* OpenIn.appex in Embed Process Extensions */,",
    "\n\t\t\t\t03OLDEP2F3100000000001 /* PBXTargetDependency */,",
):
    text = text.replace(entry, "")
project_file.write_text(text, encoding="utf-8")
PY
fi

set -- xcodebuild archive \
	-scheme "Reynard" \
	-archivePath "$DIST_DIR/Reynard.xcarchive" \
	-project "$PROJECT_PATH" \
	-sdk iphoneos \
	-arch arm64 \
	-configuration Release \
	-xcconfig "$DIST_DIR/Reynard.xcconfig"

if [ "${REYNARD_SKIP_CODE_SIGNING:-0}" = "1" ]; then
	set -- "$@" \
		CODE_SIGNING_ALLOWED=NO \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGN_IDENTITY= \
		DEVELOPMENT_TEAM= \
		AD_HOC_CODE_SIGNING_ALLOWED=YES
fi

"$@"
