# ChatGPT iOS 15 Gecko Port

This repository now contains only the Reynard/Gecko-based ChatGPT iOS shell.
The legacy app, desktop helper, and browser extension have been removed.

## Layout

- `browser/` - iOS app wrapper and GeckoView bridge.
- `tools/` - development, prebuilt Gecko setup, and release packaging scripts.
- `patches/` - Gecko/iOS patch set used by the full source build path.
- `engine/` - engine metadata plus ignored fetched Gecko payloads.
- `.github/workflows/reynard-ios-build.yml` - manual CI packaging workflow for `ChatGPT-TrollStore.tipa`.

## Build

The CI build uses Reynard's prebuilt Gecko release and applies the local ChatGPT shell runtime patch.

```sh
./tools/development/setup-prebuilt-gecko.sh
./tools/development/build-idevice.sh
./tools/release/build-app.sh
./tools/release/create-ipa.sh
```

See `CHATGPT_PORT.md` for the current app behavior and build model.
