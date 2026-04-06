# Desktop Helper

Runs a local HTTP bridge plus a Windows tray app for session syncing.

## Run

Visible console mode:

```powershell
python .\desktop-helper\helper.py
```

Tray mode:

```powershell
python .\desktop-helper\tray_app.py
```

Or use `desktop-helper\launch-hidden.vbs` to start the tray app without a console window.

## Tray actions

- Open status page
- Open pairing page
- Show pairing QR in a temporary window
- Refresh ChatGPT in Chrome
- Quit

## Pair

1. Start the tray app on the PC.
2. Use the tray menu `Show Pair QR` and scan it with the iPhone camera.
3. The QR opens the helper pairing page in Safari.
4. Tap `Connect ChatGPTWebV15`.

## Extension endpoint

The Chrome extension pushes cookie snapshots to:

```text
http://127.0.0.1:48713/v1/extension/update
```
