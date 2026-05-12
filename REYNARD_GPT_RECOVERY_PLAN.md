# Reynard GPT Implementation Plan

Date: 2026-05-12

Purpose: keep the Reynard-based ChatGPT iOS app stable, make emoji render
correctly by default, and make LightSession a safe optional long-chat
performance feature.

This is an implementation plan. Work it in order; do not skip gates.

## Final Goal

- ChatGPT remains usable and stable on the current iOS 15/TrollStore path.
- Emoji renders correctly by default through native rendering if possible.
- Any emoji fallback is local, scoped, kill-switchable, and never CDN-backed.
- LightSession is optional, fail-open, and can be disabled without breaking
  normal ChatGPT.
- The fast prebuilt release path remains viable unless evidence proves native
  emoji needs a custom Gecko build.

## Current Starting Flaws

- `patch-prebuilt-gecko.py` installs emoji and LightSession unconditionally, so
  there is no true baseline mode.
- The emoji fallback currently requests remote Twemoji CDN URLs, which is outside
  release scope.
- There is no bundled emoji matrix or diagnostic route to classify native emoji
  behavior.
- LightSession defaults to enabled in Swift and JS before its safety gates are
  proven.
- The current page runtime returns before the fetch patch, so active
  LightSession behavior is DOM hiding/status rather than payload trimming.
- The conversation trimmer is embedded inside generated shim strings, so it is
  hard to review and has no fixture tests.
- Saving LightSession settings forces a selected-tab reload even though native
  runtime config updates already exist.
- Settings copy claims payload trimming even when the reachable runtime path may
  be DOM-only.

## Fixed Context

- Fast CI path downloads upstream Reynard `0.3.0` `Reynard.ipa` and extracts the
  prebuilt `GeckoView.framework`.
- Current fast path applies `patch-prebuilt-gecko.py` shim version `21`.
- Current fast path can patch packaged JS modules and prefs; it cannot compile
  local C++/Rust Gecko patches into `XUL`.
- CI uses the fast prebuilt path.
- Local full Gecko source target is `FIREFOX_150_0_2_RELEASE` from
  `ReynardChatGPT/engine/release.txt`.
- Upstream Reynard `0.3.0` says it uses `FIREFOX_150_0_RELEASE` and added
  Firefox add-on support.
- Existing native LightSession plumbing must be reused:
  - `UserDefaults` key: `lightSessionSettings`
  - `LightSessionSettings`
  - `LightSessionSettingsStore`
  - `GeckoSession.updateLightSession(enabled:keep:)`
  - `GeckoView:UpdateLightSession`
  - initial session setting: `chatGPTLightSession`
- Add-on manager/session hooks are currently disabled because early WebExtension
  messages can crash Gecko on iOS 15.6.

## Primary Files

- `ReynardChatGPT/tools/development/setup-prebuilt-gecko.sh`
- `ReynardChatGPT/tools/development/patch-prebuilt-gecko.py`
- `ReynardChatGPT/browser/GeckoView/GeckoSession/GeckoSession.swift`
- `ReynardChatGPT/browser/Reynard/Client/Support/LightSessionSettings.swift`
- `ReynardChatGPT/browser/Reynard/Client/Interface/BrowserViewController.swift`
- `ReynardChatGPT/browser/Reynard/Client/Interface/Views/Library/Settings/SettingsView.swift`
- `ReynardChatGPT/browser/Reynard/Client/Controllers/AddonsController.swift`
- `.github/workflows/reynard-ios-build.yml`

Recommended new files:

- `ReynardChatGPT/tools/development/chatgpt-shell/page-runtime.js`
- `ReynardChatGPT/tools/development/chatgpt-shell/diagnostics.js`
- `ReynardChatGPT/tools/development/chatgpt-shell/emoji-renderer.js`
- `ReynardChatGPT/tools/development/chatgpt-shell/lightsession-trimmer.js`
- `ReynardChatGPT/tools/development/chatgpt-shell/lightsession-runtime.js`
- `ReynardChatGPT/tools/development/chatgpt-shell/tests/lightsession-trimmer.test.mjs`
- `ReynardChatGPT/tools/development/chatgpt-shell/fixtures/*.json`
- `ReynardChatGPT/browser/Reynard/Client/Resources/ChatGPTDiagnostics/emoji-matrix.html`

## Non-Negotiable Rules

- Do not ship remote emoji assets.
- Do not ship fetch response rewriting without fixture tests.
- Do not replace existing native settings storage or transport.
- Do not make WebExtension the first LightSession implementation path.
- Do not make full Gecko rebuild the first emoji implementation path.
- Do not mix iOS app extensions with Firefox WebExtensions.
- Do not break JIT helper behavior, child process startup, TrollStore packaging,
  or app-extension packaging.
- Increment `SHIM_VERSION` and the CI cache key whenever the extracted prebuilt
  payload contents change.

## Shim Mode Contract

Add `REYNARD_CHATGPT_SHIM_MODE` to `setup-prebuilt-gecko.sh` and pass it to
`patch-prebuilt-gecko.py`.

Supported modes:

- `baseline`: no ChatGPT page runtime, no emoji fallback, no LightSession DOM or
  fetch behavior.
- `emoji`: emoji diagnostics and local emoji fallback only.
- `lightsession-dom`: LightSession config/status and DOM hiding only.
- `lightsession-fetch`: LightSession config/status and fetch trimming only.
- `all`: production candidate runtime after gates pass.
- `legacy-all`: current behavior compatibility mode for comparison only; never
  use as the release target.

Default mode policy:

- During Phase 1, keep CI behavior-compatible by using `legacy-all` only for
  comparison builds.
- For release candidates, use `all` only after Phase 5 passes.
- If `REYNARD_CHATGPT_SHIM_MODE` is unset after Phase 5, default to `all`.
- LightSession default setting is off until fetch trimming passes tests and
  device validation; existing saved user settings are respected.

Marker/cache policy:

- Include release tag, asset, shim version, and shim mode in
  `engine/prebuilt-gecko/.release`.
- Include shim version and mode in the GitHub Actions cache key.
- Print release tag, asset, shim version, and mode in build logs.

## Diagnostics Contract

Add one stable diagnostics channel used by every mode except `baseline`.

Minimum build diagnostics:

- prebuilt Reynard release tag
- prebuilt asset name
- shim version
- shim mode
- whether prefs were appended
- whether ChatGPT runtime hooks were patched

Minimum runtime diagnostics:

- current shim mode
- whether ChatGPT page runtime installed
- whether emoji fallback installed
- whether LightSession config was received
- whether `window.fetch` was patched
- first matching conversation URL observed
- trim result: kept count, total visible count, skipped reason, or error

Diagnostics must not log conversation content.

## Phase 1: Shim Modes And Safe Defaults

Goal: make behavior selectable and observable before deeper changes.

Implementation checklist:

- [ ] Add `REYNARD_CHATGPT_SHIM_MODE` parsing in `setup-prebuilt-gecko.sh`.
- [ ] Add a mode argument to `patch-prebuilt-gecko.py`.
- [ ] Split page runtime injection so each mode installs only its intended
      feature set.
- [ ] Add `legacy-all` to reproduce the current unconditional runtime for
      comparison only.
- [ ] Make `baseline` skip ChatGPT page runtime patching.
- [ ] Add build diagnostics and update `.release` marker format.
- [ ] Increment `SHIM_VERSION` and update `.github/workflows/reynard-ios-build.yml`
      cache key.
- [ ] Change default LightSession settings fallback to disabled in
      `LightSessionSettings.swift` and `GeckoSession.swift`.
- [ ] Keep any existing saved `lightSessionSettings` value intact.

Exit gate:

- `baseline` build launches, loads ChatGPT, keeps login state, and accepts text
  input.
- `legacy-all` build still matches current behavior closely enough for
  comparison.
- Build logs make the selected mode unambiguous.

## Phase 2: Remove Remote Emoji Fallback

Goal: eliminate the CDN behavior before any emoji release candidate.

Implementation checklist:

- [ ] Remove all `cdn.jsdelivr.net`, `twemoji.maxcdn.com`, and other remote emoji
      URLs from production runtime code.
- [ ] If no local assets are bundled yet, emoji fallback must fail open by
      leaving original text untouched.
- [ ] Add an `rg`-based CI or script check that fails if remote Twemoji URLs
      remain in non-test runtime code.
- [ ] Keep native emoji rendering as the preferred path.

Exit gate:

- No production runtime path can request remote emoji assets.
- ChatGPT text remains copyable/selectable when fallback is inactive.

## Phase 3: Emoji Matrix And Classification

Goal: prove whether emoji failure is engine-level, shell-specific,
ChatGPT-specific, or not reproducible.

Implementation checklist:

- [ ] Add bundled `emoji-matrix.html` with exact samples for simple emoji,
      variation selector 16, ZWJ sequences, skin tones, flags/regional
      indicators, keycaps, tag sequences if relevant, and mixed text.
- [ ] Show Unicode codepoints beside each sample.
- [ ] Add a deterministic way to load the matrix on device, such as a debug menu
      action, hidden diagnostics URL, or documented local file route.
- [ ] Run matrix in `baseline`, `emoji`, and `all`.
- [ ] Add optional diagnostics for computed font family and message text
      codepoints on affected ChatGPT message nodes.

Decision tree:

- If `baseline` fails on the local matrix, treat this as engine/font fallback.
- If `baseline` passes but `all` fails, treat this as shell prefs/CSS/runtime.
- If the matrix passes but ChatGPT replies fail, treat this as ChatGPT-specific
  content/style/streaming behavior.
- If all pass, record emoji as not reproducible for that build.

Exit gate:

- The emoji issue is classified with a build tag, shim mode, device/iOS version,
  and matrix result.

## Phase 4: Emoji Fix

Goal: make emoji correct by default without speculative engine work.

Implementation checklist for shell-specific failure:

- [ ] Fix only the prefs/CSS/runtime code causing the regression.
- [ ] Re-run the matrix in `baseline`, `emoji`, and `all`.
- [ ] Re-test ChatGPT replies with mixed text and emoji.

Implementation checklist for engine-global failure:

- [ ] Test an unmodified upstream Reynard `0.3.0` build on the same device.
- [ ] If upstream fails, test a newer upstream prebuilt if available.
- [ ] If no passing prebuilt exists, choose one:
      - local scoped emoji fallback as temporary default, or
      - full custom Gecko build with local font patches.
- [ ] Use full Gecko font patches only after the fast prebuilt path is proven
      unable to render native emoji.

Local fallback rules if needed:

- [ ] Bundle local assets only.
- [ ] Scope scanning to ChatGPT message content only.
- [ ] Debounce mutation handling.
- [ ] Mark processed nodes.
- [ ] Preserve original text in `alt`/accessible text and fail open.
- [ ] Add a kill switch through shim mode or a generated pref.

Exit gate:

- Local matrix passes in the production candidate.
- ChatGPT replies render emoji correctly.
- No remote emoji asset requests occur.
- Long-chat pages do not slow down from emoji scanning.

## Phase 5: Extract And Test LightSession Trimmer

Goal: make payload trimming reviewable before enabling fetch rewriting.

Implementation checklist:

- [ ] Move trimming logic into
      `tools/development/chatgpt-shell/lightsession-trimmer.js`.
- [ ] Make the function accept `(conversationJson, keepCount)` and return a
      structured result:
      - `changed`
      - `data`
      - `visibleKept`
      - `visibleTotal`
      - `skipReason`
      - `error`
- [ ] Never mutate the input fixture object.
- [ ] Preserve top-level metadata not related to `mapping`, `current_node`, and
      `root`.
- [ ] Preserve the visible kept path.
- [ ] Preserve hidden/system/tool/thinking nodes attached to kept visible turns
      when their relationship is required by the conversation graph.
- [ ] Return explicit skip reasons for short, empty, malformed, cyclic, branched
      unknown, and unsupported shapes.
- [ ] Add Node test command:
      `node --test tools/development/chatgpt-shell/tests/*.test.mjs`.
- [ ] Add CI step for the trimmer tests before packaging.

Minimum fixtures:

- short chat under limit
- long old chat
- empty/new conversation
- shared conversation
- tool-call conversation
- hidden/system nodes
- thinking/extended mode nodes if available
- branched conversation if available
- malformed JSON-like object
- unknown future shape

Exit gate:

- Tests pass locally and in CI.
- Reviewer can inspect the trimmer without reading generated Python string
  literals.

## Phase 6: LightSession Fetch Mode

Goal: enable real payload trimming behind a tested and observable gate.

Implementation checklist:

- [ ] Move runtime fetch wrapper into
      `tools/development/chatgpt-shell/lightsession-runtime.js`.
- [ ] Generate/inject runtime JS from source modules instead of maintaining
      duplicated giant string literals.
- [ ] Remove the unreachable `return` before fetch patching in the
      `lightsession-fetch` and `all` modes only.
- [ ] Keep `lightsession-dom` available only as a fallback/status comparison
      mode.
- [ ] Intercept only `GET /backend-api/conversation/<id>`.
- [ ] Intercept only `GET /backend-api/shared_conversation/<id>`.
- [ ] Do not intercept streaming, `/me`, `/models`, `/settings`, `/textdocs`,
      `/stream_status`, or unrelated endpoints.
- [ ] Clone the response before reading it.
- [ ] Parse only JSON responses with expected conversation shape.
- [ ] On any exception, return the original response.
- [ ] If no visible turns are removed, return the original response.
- [ ] When modified, remove `content-length` and `content-encoding`.
- [ ] Preserve status, status text, content type, response URL, and response type
      as far as Gecko allows.
- [ ] Log fetch-patched, first matching URL, skip reason, kept/total, and errors
      without logging content.

Exit gate:

- With LightSession off, behavior matches `baseline`.
- With LightSession on, short chats show all-visible/waiting state.
- With LightSession on, long chats report kept/trimmed counts.
- Long chats do not blank.
- Disabling LightSession makes future fetches return original responses.

## Phase 7: LightSession Settings UX

Goal: make the native setting truthful and non-disruptive.

Implementation checklist:

- [ ] Remove forced selected-tab reload from normal
      `lightSessionSettingsDidChange` once runtime config update is reliable.
- [ ] Add an explicit "restore full history" or reload action only if needed.
- [ ] Update Settings footer copy so it does not claim payload trimming unless
      fetch mode is active in that build.
- [ ] Ensure status pill hides when disabled.
- [ ] Ensure status pill does not overlap the ChatGPT composer.
- [ ] Persist settings across app restart.

Exit gate:

- Toggling LightSession off is immediate for future requests.
- Toggling settings does not unexpectedly reload the active chat in normal use.
- UI copy matches actual mode behavior.

## Phase 8: WebExtension Spike

Goal: decide whether WebExtension should replace actor injection later.

Do this only after Phases 1-7 pass.

Implementation checklist:

- [ ] Package a tiny built-in test extension.
- [ ] Prove install/ensure without AMO signing in this iOS package layout.
- [ ] Run a content script at `document_start`.
- [ ] Inject page-world script before the first ChatGPT conversation fetch.
- [ ] Write a visible marker only on `chatgpt.com`.
- [ ] Survive cold start, reload, SPA navigation, background, and resume.
- [ ] Confirm no iOS 15 launch crash.

Exit gate:

- WebExtension is either a proven future path or explicitly deferred.

## Phase 9: Performance And Release Review

Goal: confirm targeted changes improved behavior without hurting the stable app.

Measure only changed candidate builds:

- cold launch to ChatGPT visible
- long old chat open time
- typing latency after long chat load
- blank/crash count
- memory trend after navigating several chats

Release gate:

- `all` mode passes Gate A baseline behavior with LightSession off.
- Emoji works by default.
- LightSession on improves long-chat usability or at least reduces DOM/payload
  load without blanking.
- LightSession off remains no worse than baseline.
- No remote emoji requests.
- CI builds `ChatGPT-TrollStore.tipa`.
- Device smoke test covers launch, login state, text input, chat load, settings
  toggle, reload gesture, and app background/resume.

## External References

- Reynard `0.3.0` release:
  https://github.com/minh-ton/reynard-browser/releases/tag/0.3.0
- GeckoView WebExtension built-in API docs:
  https://mozilla.github.io/geckoview/javadoc/mozilla-central/org/mozilla/geckoview/WebExtensionController.html
- MDN content script docs:
  https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/manifest.json/content_scripts
- MDN execution worlds:
  https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/scripting/ExecutionWorld
- Open source LightSession reference:
  https://github.com/11me/light-session
