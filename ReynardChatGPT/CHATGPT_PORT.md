# ChatGPT Gecko Port

This folder is a vendored private fork of Reynard Browser, adapted as the experimental Gecko-backed ChatGPT app shell.

## Current baseline

- Loads `https://chatgpt.com` as the initial page instead of restoring generic browser tabs.
- Collapses the visible browser chrome so the Gecko view behaves more like the existing app shell.
- Adds hidden edge gestures:
  - Swipe from the left edge to reload the current ChatGPT page.
  - Swipe from the right edge to open Reynard's menu/settings sheet.
- Uses `com.codex.ChatGPTReynard` bundle identifiers so it can coexist with the existing fallback app.
- Keeps the original `Downloads/ChatGPTWebV15` WKWebView app untouched.

## Build model

Reynard's wrapper source is committed here, but the large upstream engine is not built in CI:

- `tools/development/setup-prebuilt-gecko.sh` downloads Reynard's released IPA and extracts the prebuilt Gecko runtime into `engine/prebuilt-gecko`.
- `support/idevice` is still cloned by `tools/development/build-idevice.sh` for the small JIT bridge library.
- `engine/firefox`, `engine/prebuilt-gecko`, and `support/idevice` are ignored by Git.

Manual build order on macOS:

```sh
cd ReynardChatGPT
./tools/development/update-gecko.sh
./tools/development/apply-patches.sh
./tools/development/build-idevice.sh
./tools/development/build-gecko.sh
./tools/release/build-app.sh
./tools/release/create-ipa.sh
```

Fast build order on macOS, matching CI:

```sh
cd ReynardChatGPT
./tools/development/setup-prebuilt-gecko.sh
./tools/development/build-idevice.sh
./tools/release/build-app.sh
./tools/release/create-ipa.sh
```

The root workflow `.github/workflows/reynard-ios-build.yml` runs the fast path on push and publishes `ChatGPT-Gecko.ipa` plus `ChatGPT-Gecko-TrollStore.tipa` to `ci-gecko-latest`.

## Next work

- Verify GitHub Actions can complete the full Gecko build within runner limits.
- Install the IPA on the target iOS 15 device and confirm ChatGPT login, text input, file upload, and long-thread rendering.
- Port LightSession-style response trimming only after Gecko login and basic ChatGPT UX are proven.
