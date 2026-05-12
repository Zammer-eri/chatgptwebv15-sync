# Reynard GPT Recovery Plan

Date: 2026-05-12

Purpose: keep the Reynard-based ChatGPT iOS app stable, remove unproven
LightSession behavior, and make emoji diagnosis visible from the app UI with
copyable build evidence.

This plan replaces the earlier LightSession implementation plan. LightSession
is no longer in scope for this recovery pass.

## Goal

- ChatGPT launches as the first page and remains usable on the iOS 15
  TrollStore path.
- Emoji behavior is proven with an in-app diagnostic page, not guessed from
  symptoms.
- Settings exposes the diagnostic path the user can actually reach from the
  app shell.
- The fast prebuilt Reynard release path remains the release path unless logs
  prove it cannot support native emoji.
- GitHub Actions publishes `ChatGPT-TrollStore.tipa`.

## Removed Scope

- No LightSession settings UI.
- No LightSession native bridge.
- No LightSession JavaScript runtime.
- No conversation payload trimming.
- No fetch rewriting.
- No stale settings copy claiming LightSession behavior.

If long-chat trimming is revisited later, it needs a new plan, fixture tests,
and device logs before any runtime code ships.

## Non-Negotiable Rules

- Do not ship remote emoji assets.
- Do not guess from user reports when a diagnostic can be exposed.
- Do not rely on an address bar as the only diagnostic entry point.
- Do not add custom Gecko/font prefs without evidence from the emoji matrix.
- Do not compile local Gecko as the first response to emoji failure.
- Do not break JIT helper behavior, child process startup, TrollStore
  packaging, or app-extension packaging.
- Increment `SHIM_VERSION` and the CI cache key whenever the prebuilt Gecko
  payload changes.

## Diagnostic Contract

Settings > ChatGPT must expose:

- `Emoji Matrix`: opens a bundled local Gecko diagnostic page.
- `Copy Diagnostic Info`: copies version/build, Gecko version, device/iOS, the
  prebuilt build marker JSON, emoji fallback status, and LightSession removal
  status.

The user should be able to send only:

- a screenshot of the Emoji Matrix page
- copied diagnostic info
- the GitHub Actions build log URL or failed job log

That evidence must be enough to classify the emoji issue.

## Build Marker Contract

The fast prebuilt setup writes `reynard-chatgpt-build.json` into the packaged
Gecko framework area with:

- upstream Reynard release tag
- upstream asset name
- shim version
- shim mode
- whether custom prefs were appended
- LightSession status

The build log must also print the selected release, asset, shim version, shim
mode, and LightSession status.

## Shim Mode Contract

`REYNARD_CHATGPT_SHIM_MODE` supports only:

- `baseline`: no ChatGPT page runtime patches.
- `emoji`: emoji diagnostics/runtime only.
- `all`: current production candidate runtime.

LightSession modes are removed.

## Verification Gates

Before commit:

- `rg` shows no LightSession production code remains, except explicit
  diagnostic/marker strings saying it was removed.
- `rg` shows no remote emoji CDN URLs remain in production runtime code.
- `node --check` passes for each ChatGPT shell JavaScript file.
- `python -m py_compile` passes for `patch-prebuilt-gecko.py`.
- `git diff --check` passes.
- A mock patcher run proves `baseline` does not inject the runtime.
- A mock patcher run proves `all` injects the runtime and contains no
  LightSession runtime code.
- The matrix source uses numeric HTML entities, not literal emoji bytes, so the
  diagnostic page itself cannot become mojibake from file encoding.

After CI publishes a TIPA:

- Install `ChatGPT-TrollStore.tipa`.
- Launch app cold.
- Confirm ChatGPT appears without browser chrome.
- Open Settings with the right-edge swipe.
- Open Settings > ChatGPT > Emoji Matrix and screenshot it.
- Open Settings > ChatGPT > Copy Diagnostic Info and paste the copied text.
- Send a normal ChatGPT message containing mixed text and emoji.
- Background and resume app once.

## Evidence-Based Emoji Decision Tree

- Matrix fails in `baseline`: engine/font fallback issue.
- Matrix passes in `baseline` but fails in `all`: shim/runtime/prefs issue.
- Matrix passes but ChatGPT messages fail: ChatGPT CSS/content/streaming issue.
- Matrix and ChatGPT messages both pass: emoji issue is not reproduced for that
  build and device.

## Current Expected TIPA

On a successful GitHub Actions run, the release asset is:

- `ChatGPT-TrollStore.tipa`

It uses upstream Reynard prebuilt Gecko from release `0.3.0`, with the local
ChatGPT shell changes and the ChatGPT diagnostic marker bundled.
