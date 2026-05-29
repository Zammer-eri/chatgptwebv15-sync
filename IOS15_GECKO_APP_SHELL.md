# iOS 15 Gecko App Shell Playbook

Use this when turning an unsupported web app into a minimal iOS 15 app shell with Reynard/Gecko.
The goal is not to keep a browser. The goal is a single-purpose app that loads one service reliably.

## Base Idea

Start from Reynard Browser for its Gecko engine on iOS, then strip it into an app shell:

- One initial URL, for example `https://chatgpt.com`, Uber, Deliveroo, etc.
- Minimal browser UI.
- No tab UI unless the target app truly needs tabs.
- No generic address bar workflow unless debugging needs it.
- External links route outside the shell.
- Login/auth/challenge hosts stay inside Gecko.
- Downloads and files are handled by the shell.
- Refresh is normal app/browser reload behavior, with optional cache clear only if the target site needs it.

## What To Keep

Keep only what the web app needs to survive:

- Gecko session creation, load/reload, navigation delegates.
- Login and challenge flows.
- File picker/upload support.
- Download handling if the service creates files.
- External link routing.
- Basic keyboard avoidance.
- JIT/runtime support if the engine needs it. Do not casually strip JIT.

For delivery/ride apps like Uber or Deliveroo, expect to keep:

- Location permission flow.
- Login/OAuth/payment challenge hosts.
- External map/payment links routed out if they are not part of core flow.

## What To Strip

Usually remove:

- Multi-tab UI.
- Browser history/bookmarks.
- Desktop-only chrome.
- Extension/add-on surfaces.
- Generic settings pages.
- Browser onboarding/update UI.
- Address/search workflow if the app always loads one URL.
- Any diagnostics/logging once the issue is fixed.

Strip gradually. After each strip, test login, navigation, keyboard, upload, download, and relaunch.

## User Agent

Keep UA simple:

- Default: iOS/mobile Gecko if it works.
- Optional fallback: Android mobile Firefox UA.
- Do not hardcode desktop UA unless the target website requires it.
- If the user changes UA, save the setting and force a page reload so Gecko applies the new session settings.

Useful pattern:

- Row: `Android User Agent` toggle.
- Save button appears only when value changed.
- Save writes preference, updates Gecko session settings, reloads selected tab.

## External Links

Rule of thumb:

- Main app host stays embedded.
- Auth/challenge hosts stay embedded.
- File/download hosts stay embedded long enough for Gecko to emit download events.
- Normal content/source links open in Safari or system browser.
- New-window source/snippet links should route out, not create a hidden tab or reused session.

Example allow-in-Gecko host groups:

- App host: `chatgpt.com`, `*.chatgpt.com`
- Auth: `auth.openai.com`, `accounts.google.com`, `appleid.apple.com`
- Files: `files.oaiusercontent.com`, cloud blob download hosts

For Uber/Deliveroo equivalents, identify:

- Main domain.
- Login domains.
- Payment domains.
- File/receipt domains.
- Map/deep-link domains.

## Downloads

Needed pieces:

- Register Gecko content events for external responses / save PDF.
- Convert Gecko response into a local download request.
- Show a small prompt: `Download File?`
- On accept, start download and open the Downloads view.
- Downloads view should read both the manifest and raw files in `Documents/Downloads`.
- Tapping a file should preview it with Quick Look.
- If Quick Look cannot preview it, use iOS `Open In`, not generic share.

For compact UI:

- Plain list, not large grouped settings cells.
- Small icon, one-line filename, one-line size/status.
- Scroll inside the panel.

## Keyboard

Pick deterministic behavior per app.

For ChatGPT-style composer:

- Return key inserts newline, like desktop `Shift + Enter`.
- Sending is only through the website send button.
- Scope any JS hook to the app host and composer element only.

Avoid global keyboard hacks. If JS is needed, inject it through the Gecko runtime patch and keep it narrow.

## Cache / Reload

Start with normal reload.

Only add cache clearing if the target web app has a proven stale-cache blank-screen problem. If added, keep it explicit and scoped:

- Stop current session.
- Clear app cache/temp/URLCache.
- Reload selected tab.

Do not add broad logging or health checks unless actively diagnosing.

## UI Shell Pattern

A good minimal shell:

- Web app fills the screen.
- Hidden gestures expose shell tools.
- Left edge: small utility card with UA and Downloads.
- Right edge: reload.
- Outside tap dismisses overlays.
- Overlay uses blur/dim, stays compact, and should not look like a full browser.

## Build Notes

Fast CI model:

- Download Reynard prebuilt IPA.
- Extract Gecko runtime into `engine/prebuilt-gecko`.
- Apply local runtime patches.
- Build wrapper app.
- Package TrollStore TIPA.

When changing runtime JS or Gecko patching:

- Bump runtime patch version.
- Include changed runtime files in cache fingerprint.
- Update GitHub Actions cache key.

## Port Checklist

1. Set app URL.
2. Strip browser UI.
3. Keep login/auth hosts embedded.
4. Route normal external links out.
5. Add UA fallback if needed.
6. Keep upload/file picker.
7. Add download prompt/list if needed.
8. Decide keyboard Return behavior.
9. Test fresh install, login, relaunch, background/foreground, fast navigation, upload, download, external links.
10. Remove diagnostics and dead code after the behavior is stable.
