# ChatGPTWebV15 iOS App

This app keeps the reliable iOS 15 cookie-injection approach, but removes the noisy multi-account overlay and is designed to pair with the desktop session helper.

## Current behavior

- Clean single-account `WKWebView` shell
- Hidden diagnostics via a two-finger triple-tap near the top edge
- Desktop-helper pairing through the `chatgptwebv15://pair` deep link
- Helper-driven cookie refresh on app launch, foreground, and signed-out detection
- Legacy `sessionCookie` fallback retained for compatibility with the old `v1.0` flow

## First-time setup

1. Build and install the app on the device.
2. Run the desktop helper on the Windows PC.
3. Load the unpacked Chrome extension.
4. Sign in to ChatGPT normally in Chrome.
5. On the iPhone, open `http://<pc-ip>:48713/pair` in Safari.
6. Tap `Connect ChatGPTWebV15`.

The app stores the helper host, port, and secret, then refreshes its own session from the desktop browser.

## Why this path exists

On iOS 15, modern OpenAI web login is inconsistent enough that the stable solution is still to mirror a trusted desktop session rather than depend on on-device login flows.
