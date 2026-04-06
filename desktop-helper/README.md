# Desktop Helper

Runs a local HTTP bridge plus a Windows tray app for session syncing.

The helper binds Chrome-extension traffic to `127.0.0.1` and phone pairing traffic to the Windows hotspot address `192.168.137.1` by default. This avoids exposing the pairing page on unrelated network interfaces.

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

If you update from an older helper build, the pairing secret is rotated automatically. Re-pair the phone after restarting the helper.

## Extension endpoint

The Chrome extension pushes cookie snapshots to:

```text
http://127.0.0.1:48713/v1/extension/update
```
