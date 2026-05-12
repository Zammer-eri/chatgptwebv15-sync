# ChatGPT iOS 15 Gecko Port

This repository now contains only the Reynard/Gecko-based ChatGPT iOS shell.
The legacy app, desktop helper, and browser extension have been removed.

## Active Project

- `ReynardChatGPT/` - vendored Reynard Browser fork adapted to launch ChatGPT through Gecko on iOS 15.
- `.github/workflows/reynard-ios-build.yml` - fast CI path that packages `ChatGPT-TrollStore.tipa`.

## Build

The CI build uses Reynard's prebuilt Gecko release and applies the local ChatGPT shell runtime patch.

```sh
cd ReynardChatGPT
./tools/development/setup-prebuilt-gecko.sh
./tools/development/build-idevice.sh
./tools/release/build-app.sh
./tools/release/create-ipa.sh
```

See `ReynardChatGPT/CHATGPT_PORT.md` for the current app behavior and build model.
