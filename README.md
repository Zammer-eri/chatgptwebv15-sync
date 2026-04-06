# ChatGPTWebV15

An iOS 15 ChatGPT shell built around desktop-session syncing instead of fragile on-device login.

## What changed

- The iOS app is now a clean single-account shell.
- The old floating account switcher flow is gone from the app code.
- A local Windows helper and Chrome extension keep the iPhone session aligned with the logged-in desktop browser.
- The app icon now uses the current official ChatGPT App Store artwork.

## Repository layout

- `Downloads/ChatGPTWebV15/`
  The iOS app project.
- `desktop-helper/`
  Lightweight Windows helper that stores and serves the latest browser cookie bundle.
- `chrome-extension/`
  Chrome MV3 extension that pushes ChatGPT/OpenAI cookies into the helper.

## Desktop setup

1. Start the tray helper:

   ```powershell
   python .\desktop-helper\tray_app.py
   ```

   Or run the lightweight console helper if you only want the HTTP bridge:

   ```powershell
   python .\desktop-helper\helper.py
   ```

2. Optionally install it into Windows Startup:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\desktop-helper\install-startup.ps1
   ```

3. Load the unpacked Chrome extension from `chrome-extension/`.
4. Sign in to ChatGPT normally in Chrome.
5. On the iPhone, use the tray menu `Show Pair QR` and scan it, or open the helper pairing page shown by the helper, then tap the deep link to connect the app.

## iPhone behavior

- On launch, foreground, and logged-out detection, the app asks the helper for the latest cookie bundle.
- If the desktop browser is still signed in, the phone session is refreshed without DevTools or manual token copying.
- If the helper is unavailable, the app falls back to the existing local cookie store and the legacy single-token path.

## Hidden controls

- In the app, use a `two-finger triple-tap` near the top edge to open diagnostics.

## Notes

- This still depends on the desktop Chrome session being the source of truth.
- If Chrome itself truly needs a new login, you sign in there once and the phone app can recover on the next sync.
- `.github/workflows/ios-build.yml` now builds an unsigned TrollStore-oriented IPA as `ChatGPT-unsigned.ipa` and publishes it to the rolling prerelease tag `ci-unsigned-latest`.
