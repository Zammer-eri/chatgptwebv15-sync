#!/bin/sh

set -eu

GECKO_DIST_BIN="${GECKO_DIST}/bin"
APP_BUNDLE="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
FRAMEWORKS_DIR="${APP_BUNDLE}/Frameworks"
GECKOVIEW_FW="${FRAMEWORKS_DIR}/GeckoView.framework"
GECKOVIEW_FW_FRAMEWORKS="${GECKOVIEW_FW}/Frameworks"

DEFAULT_THEME_SRC="${SRCROOT}/../engine/firefox/toolkit/mozapps/extensions/default-theme"
CHATGPT_DIAGNOSTICS_SRC="${SRCROOT}/Reynard/Resources/ChatGPTDiagnostics"
CHATGPT_DIAGNOSTICS_DST="${APP_BUNDLE}/ChatGPTDiagnostics"

sign_if_needed() {
	if [ "${CODE_SIGNING_ALLOWED:-YES}" != "YES" ] || [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
		return 0
	fi
	codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "$@"
}

mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}"

# copy dylibs and XUL, then sign
cp -fL "${GECKO_DIST_BIN}/"*.dylib "${FRAMEWORKS_DIR}/"
cp -fL "${GECKO_DIST_BIN}/XUL" "${GECKOVIEW_FW}/XUL"

for file in "${GECKOVIEW_FW}/XUL" "${FRAMEWORKS_DIR}/"*.dylib; do
	if [ -f "${file}" ]; then
		sign_if_needed --preserve-metadata=identifier,entitlements "${file}"
	fi
done

# copy the rest of the files, excluding the ones we already copied and the test files
rsync -pvtrlL --delete --exclude "XUL" --exclude "*.dylib" --exclude "Test*" --exclude "test_*" --exclude "*_unittest" "${GECKO_DIST_BIN}/" "${GECKOVIEW_FW_FRAMEWORKS}"

if [ -d "${DEFAULT_THEME_SRC}" ]; then
	# default theme missing error fix for source-built Gecko
	mkdir -p "${GECKOVIEW_FW_FRAMEWORKS}/default-theme"
	cp -RfL "${DEFAULT_THEME_SRC}/" "${GECKOVIEW_FW_FRAMEWORKS}/default-theme/"
	echo "resource default-theme file:default-theme/" >> "${GECKOVIEW_FW_FRAMEWORKS}/chrome.manifest"
fi

if [ -d "${CHATGPT_DIAGNOSTICS_SRC}" ]; then
	rm -rf "${CHATGPT_DIAGNOSTICS_DST}"
	mkdir -p "${CHATGPT_DIAGNOSTICS_DST}"
	cp -RfL "${CHATGPT_DIAGNOSTICS_SRC}/" "${CHATGPT_DIAGNOSTICS_DST}/"
fi

# sign the GeckoView.framework
sign_if_needed "${GECKOVIEW_FW}"
