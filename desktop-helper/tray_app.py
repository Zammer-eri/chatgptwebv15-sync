import threading
import webbrowser
from pathlib import Path
import tkinter as tk

import pystray
import qrcode
from PIL import Image, ImageTk

from helper import APP_NAME, HelperServerThread, HelperState


BASE_DIR = Path(__file__).resolve().parent
REPO_ROOT = BASE_DIR.parent
ICON_SOURCE = REPO_ROOT / "Downloads" / "ChatGPTWebV15" / "ChatGPTWebView" / "Assets.xcassets" / "AppIcon.appiconset" / "80.png"


class TrayApplication:
    def __init__(self) -> None:
        self.state = HelperState()
        self.server = HelperServerThread(self.state)
        self.qr_window_lock = threading.Lock()
        self.qr_window_open = False
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
        with self.qr_window_lock:
            if self.qr_window_open:
                return
            self.qr_window_open = True

        threading.Thread(target=self._run_qr_window, daemon=True).start()

    def _run_qr_window(self) -> None:
        root = tk.Tk()
        root.title("Pair ChatGPT")
        root.configure(bg="#f4f4f1")
        root.resizable(False, False)

        qr_image = qrcode.make(self.state.pair_url).resize((280, 280), Image.Resampling.NEAREST)
        qr_photo = ImageTk.PhotoImage(qr_image)

        container = tk.Frame(root, bg="#f4f4f1", padx=18, pady=18)
        container.pack()

        title = tk.Label(
            container,
            text="Scan to pair with this desktop",
            font=("Segoe UI", 14, "bold"),
            bg="#f4f4f1",
            fg="#111111",
        )
        title.pack(pady=(0, 10))

        image_label = tk.Label(container, image=qr_photo, bg="#ffffff", bd=0)
        image_label.image = qr_photo
        image_label.pack()

        url_label = tk.Label(
            container,
            text=self.state.pair_url,
            font=("Segoe UI", 10),
            bg="#f4f4f1",
            fg="#333333",
            wraplength=320,
            justify="center",
        )
        url_label.pack(pady=(12, 8))

        helper_label = tk.Label(
            container,
            text="If camera scanning is unavailable, open the pairing URL in Safari on the iPhone.",
            font=("Segoe UI", 9),
            bg="#f4f4f1",
            fg="#666666",
            wraplength=320,
            justify="center",
        )
        helper_label.pack()

        actions = tk.Frame(container, bg="#f4f4f1")
        actions.pack(pady=(14, 0))

        def copy_url() -> None:
            root.clipboard_clear()
            root.clipboard_append(self.state.pair_url)
            root.update()

        copy_button = tk.Button(actions, text="Copy URL", command=copy_url, width=12)
        copy_button.pack(side=tk.LEFT, padx=6)

        open_button = tk.Button(actions, text="Open Pair Page", command=lambda: webbrowser.open(self.state.pair_url), width=12)
        open_button.pack(side=tk.LEFT, padx=6)

        def close_window() -> None:
            with self.qr_window_lock:
                self.qr_window_open = False
            root.destroy()

        root.protocol("WM_DELETE_WINDOW", close_window)
        root.mainloop()

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
