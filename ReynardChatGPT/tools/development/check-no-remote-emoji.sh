#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"

if rg -n "cdn\\.jsdelivr\\.net|twemoji\\.maxcdn\\.com|https?://[^[:space:]\"']*twemoji" \
	"$ROOT_DIR/tools/development/patch-prebuilt-gecko.py" \
	"$ROOT_DIR/tools/development/chatgpt-shell"; then
	echo "Remote Twemoji asset URL found in production ChatGPT shell runtime code." >&2
	exit 1
fi
