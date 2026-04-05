import os
import sys
import threading
import webbrowser
from pathlib import Path

import pystray
import qrcode
from PIL import Image

from helper import APP_NAME, HelperServerThread, HelperState


BASE_DIR = Path(__file__).resolve().parent
REPO_ROOT = BASE_DIR.parent
ICON_SOURCE = REPO_ROOT / "Downloads" / "ChatGPTWebV15" / "ChatGPTWebView" / "Assets.xcassets" / "AppIcon.appiconset" / "80.png"


class TrayApplication:
    def __init__(self) -> None:
        self.state = HelperState()
        self.server = HelperServerThread(self.state)
        self.icon = pystray.Icon(
            "chatgptwebv15-helper",
            icon=self.load_icon_image(),
            title=APP_NAME,
            menu=pystray.Menu(
                pystray.MenuItem("Open Status Page", self.open_status_page),
                pystray.MenuItem("Open Pairing Page", self.open_pairing_page),
                pystray.MenuItem("Show Pair QR", self.show_pair_qr),
                pystray.MenuItem("Refresh ChatGPT in Chrome", self.refresh_chrome),
                pystray.MenuItem("Quit", self.quit_app),
            ),
        )

    def load_icon_image(self) -> Image.Image:
        if ICON_SOURCE.exists():
            return Image.open(ICON_SOURCE).convert("RGBA")

        return Image.new("RGBA", (64, 64), (17, 17, 17, 255))

    def run(self) -> None:
        self.server.start()
        self.icon.run(setup=self.on_ready)

    def on_ready(self, icon: pystray.Icon) -> None:
        icon.visible = True

    def open_status_page(self, icon: pystray.Icon, item: pystray.MenuItem) -> None:
        webbrowser.open(f"http://127.0.0.1:{self.state.config.port}/")

    def open_pairing_page(self, icon: pystray.Icon, item: pystray.MenuItem) -> None:
        webbrowser.open(self.state.pair_url)

    def show_pair_qr(self, icon: pystray.Icon, item: pystray.MenuItem) -> None:
        qr_dir = self.state.runtime
        qr_path = qr_dir / "pair-qr.png"
        image = qrcode.make(self.state.pair_url)
        image.save(qr_path)
        os.startfile(str(qr_path))  # type: ignore[attr-defined]

    def refresh_chrome(self, icon: pystray.Icon, item: pystray.MenuItem) -> None:
        self.state.refresh_chrome_session()

    def quit_app(self, icon: pystray.Icon, item: pystray.MenuItem) -> None:
        self.server.stop()
        icon.stop()


def main() -> None:
    app = TrayApplication()
    app.run()


if __name__ == "__main__":
    main()
