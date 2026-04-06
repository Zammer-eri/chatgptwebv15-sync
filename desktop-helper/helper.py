import ctypes
import hashlib
import html
import json
import os
import secrets
import socket
import subprocess
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


APP_NAME = "ChatGPTWebV15 Helper"
SCHEMA_VERSION = 1
DEFAULT_PORT = 48713
CONFIG_VERSION = 2
DEFAULT_REMOTE_HOST = "192.168.137.1"
SESSION_FILE = "session.dat"
CONFIG_FILE = "config.json"
REFRESH_WAIT_SECONDS = 12


class DATA_BLOB(ctypes.Structure):
    _fields_ = [
        ("cbData", ctypes.c_uint32),
        ("pbData", ctypes.POINTER(ctypes.c_byte)),
    ]


def _blob_from_bytes(raw: bytes) -> tuple[DATA_BLOB, ctypes.Array[ctypes.c_char]]:
    buffer = ctypes.create_string_buffer(raw)
    blob = DATA_BLOB(len(raw), ctypes.cast(buffer, ctypes.POINTER(ctypes.c_byte)))
    return blob, buffer


def _bytes_from_blob(blob: DATA_BLOB) -> bytes:
    return ctypes.string_at(blob.pbData, blob.cbData)


def protect_bytes(raw: bytes) -> bytes:
    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    in_blob, in_buffer = _blob_from_bytes(raw)
    out_blob = DATA_BLOB()
    if not crypt32.CryptProtectData(
        ctypes.byref(in_blob),
        "ChatGPTWebV15 Session",
        None,
        None,
        None,
        0,
        ctypes.byref(out_blob),
    ):
        raise ctypes.WinError()

    try:
        return _bytes_from_blob(out_blob)
    finally:
        kernel32.LocalFree(ctypes.cast(out_blob.pbData, ctypes.c_void_p))
        del in_buffer


def unprotect_bytes(raw: bytes) -> bytes:
    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    in_blob, in_buffer = _blob_from_bytes(raw)
    out_blob = DATA_BLOB()
    if not crypt32.CryptUnprotectData(
        ctypes.byref(in_blob),
        None,
        None,
        None,
        None,
        0,
        ctypes.byref(out_blob),
    ):
        raise ctypes.WinError()

    try:
        return _bytes_from_blob(out_blob)
    finally:
        kernel32.LocalFree(ctypes.cast(out_blob.pbData, ctypes.c_void_p))
        del in_buffer


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_json(data: Any) -> str:
    return json.dumps(data, separators=(",", ":"), sort_keys=True)


def bundle_hash(payload: dict[str, Any]) -> str:
    return hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


def is_loopback(host: str) -> bool:
    return host in {"127.0.0.1", "::1", "localhost"}


def discover_lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("8.8.8.8", 80))
            ip = probe.getsockname()[0]
            if ip and not ip.startswith("127."):
                return ip
    except OSError:
        pass

    for candidate in socket.gethostbyname_ex(socket.gethostname())[2]:
        if candidate and not candidate.startswith("127."):
            return candidate

    return "127.0.0.1"


def find_chrome_command() -> list[str] | None:
    candidates = [
        Path(os.environ.get("PROGRAMFILES", "")) / "Google/Chrome/Application/chrome.exe",
        Path(os.environ.get("PROGRAMFILES(X86)", "")) / "Google/Chrome/Application/chrome.exe",
        Path(os.environ.get("LOCALAPPDATA", "")) / "Google/Chrome/Application/chrome.exe",
    ]
    for candidate in candidates:
        if candidate.exists():
            return [str(candidate)]

    return ["chrome.exe"]


def runtime_dir() -> Path:
    path = Path(os.environ.get("APPDATA", Path.home())) / "ChatGPTWebV15Helper"
    path.mkdir(parents=True, exist_ok=True)
    return path


@dataclass
class HelperConfig:
    secret: str
    port: int
    version: int


class HelperState:
    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.condition = threading.Condition(self.lock)
        self.runtime = runtime_dir()
        self.config = self._load_or_create_config()
        self.remote_host = os.environ.get("CHATGPTWEBV15_HELPER_HOST", DEFAULT_REMOTE_HOST)
        self.remote_enabled = False
        self.remote_bind_error: str | None = None
        self.session_bundle: dict[str, Any] | None = None
        self.session_hash: str | None = None
        self.last_update: str | None = None
        self.last_browser_refresh: str | None = None
        self.load_session()

    @property
    def pair_url(self) -> str:
        return f"http://{self.remote_host}:{self.config.port}/pair"

    @property
    def pair_deep_link(self) -> str:
        return f"chatgptwebv15://pair?host={self.remote_host}&port={self.config.port}&secret={self.config.secret}"

    def _load_or_create_config(self) -> HelperConfig:
        config_path = self.runtime / CONFIG_FILE
        if config_path.exists():
            data = json.loads(config_path.read_text(encoding="utf-8"))
            port = int(data.get("port", DEFAULT_PORT))
            if port == 45832:
                port = DEFAULT_PORT
            version = int(data.get("version", 1))
            secret = data.get("secret", secrets.token_urlsafe(32))
            if version < CONFIG_VERSION:
                secret = secrets.token_urlsafe(32)
                version = CONFIG_VERSION
            config = HelperConfig(secret=secret, port=port, version=version)
            config_path.write_text(
                json.dumps({"secret": config.secret, "port": config.port, "version": config.version}, indent=2),
                encoding="utf-8",
            )
            return config

        config = HelperConfig(secret=secrets.token_urlsafe(32), port=DEFAULT_PORT, version=CONFIG_VERSION)
        config_path.write_text(
            json.dumps({"secret": config.secret, "port": config.port, "version": config.version}, indent=2),
            encoding="utf-8",
        )
        return config

    def load_session(self) -> None:
        session_path = self.runtime / SESSION_FILE
        if not session_path.exists():
            return

        try:
            raw = unprotect_bytes(session_path.read_bytes())
            bundle = json.loads(raw.decode("utf-8"))
        except Exception:
            return

        self.session_bundle = bundle
        self.session_hash = bundle_hash(bundle)
        self.last_update = bundle.get("captured_at")

    def save_session(self, payload: dict[str, Any]) -> None:
        session_path = self.runtime / SESSION_FILE
        session_path.write_bytes(protect_bytes(canonical_json(payload).encode("utf-8")))

    def update_bundle(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self.condition:
            payload["schema"] = SCHEMA_VERSION
            payload["captured_at"] = payload.get("captured_at") or utc_now()
            payload["cookies"] = payload.get("cookies", [])
            self.session_bundle = payload
            self.session_hash = bundle_hash(payload)
            self.last_update = payload["captured_at"]
            self.save_session(payload)
            self.condition.notify_all()
            return self.snapshot()

    def snapshot(self) -> dict[str, Any]:
        return {
            "schema": SCHEMA_VERSION,
            "bundle_hash": self.session_hash,
            "captured_at": self.last_update,
            "cookies": (self.session_bundle or {}).get("cookies", []),
            "browser": (self.session_bundle or {}).get("browser", "chrome"),
            "profile": (self.session_bundle or {}).get("profile", "Default"),
        }

    def status(self) -> dict[str, Any]:
        with self.lock:
            cookie_count = len((self.session_bundle or {}).get("cookies", []))
            return {
                "app": APP_NAME,
                "schema": SCHEMA_VERSION,
                "lan_ip": self.remote_host,
                "port": self.config.port,
                "pair_url": self.pair_url,
                "pair_deep_link": self.pair_deep_link,
                "remote_enabled": self.remote_enabled,
                "remote_bind_error": self.remote_bind_error,
                "has_session": self.session_bundle is not None,
                "cookie_count": cookie_count,
                "bundle_hash": self.session_hash,
                "captured_at": self.last_update,
                "last_browser_refresh": self.last_browser_refresh,
            }

    def ensure_fresh(self, known_hash: str | None, reason: str) -> dict[str, Any]:
        with self.condition:
            previous_hash = self.session_hash
            needs_refresh = reason == "logged_out" or not self.session_bundle or known_hash == self.session_hash
            refreshed = False
            refresh_status = "not_needed"

            if needs_refresh:
                refresh_status = self.refresh_chrome_session()
                end_time = time.time() + REFRESH_WAIT_SECONDS
                while time.time() < end_time and previous_hash == self.session_hash:
                    self.condition.wait(timeout=1.0)
                refreshed = previous_hash != self.session_hash
                if refreshed:
                    refresh_status = "updated"
                elif refresh_status == "launched":
                    refresh_status = "no_change"

            payload = self.snapshot()
            payload["refreshed"] = refreshed
            payload["refresh_status"] = refresh_status
            payload["reason"] = reason
            return payload

    def refresh_chrome_session(self) -> str:
        chrome_command = find_chrome_command()
        if not chrome_command:
            return "chrome_missing"

        self.last_browser_refresh = utc_now()
        url = f"https://chatgpt.com/?desktop_sync={int(time.time())}"
        try:
            subprocess.Popen(
                chrome_command + ["--new-tab", url],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return "launched"
        except OSError:
            try:
                os.startfile(url)  # type: ignore[attr-defined]
                return "launched"
            except OSError:
                return "launch_failed"


CURRENT_STATE: HelperState | None = None


class HelperRequestHandler(BaseHTTPRequestHandler):
    server_version = "ChatGPTWebV15Helper/1.0"

    @property
    def state(self) -> HelperState:
        if CURRENT_STATE is None:
            raise RuntimeError("Helper state not initialized")
        return CURRENT_STATE

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self.respond_html(self.render_home())
            return

        if parsed.path == "/health":
            self.respond_json({"ok": True, **self.state.status()})
            return

        if parsed.path == "/pair":
            self.respond_html(self.render_pair_page())
            return

        if parsed.path == "/v1/status":
            if not self.authorized():
                return
            self.respond_json(self.state.status())
            return

        if parsed.path == "/v1/session":
            if not self.authorized():
                return
            self.respond_json(self.state.snapshot())
            return

        self.respond_json({"error": "not_found"}, status=HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        body = self.read_json_body()
        if body is None and parsed.path != "/v1/extension/update":
            return

        if parsed.path == "/v1/extension/update":
            if not is_loopback(self.client_address[0]):
                self.respond_json({"error": "loopback_only"}, status=HTTPStatus.FORBIDDEN)
                return
            payload = body or {}
            self.respond_json(self.state.update_bundle(payload))
            return

        if parsed.path == "/v1/ensure-fresh":
            if not self.authorized():
                return
            known_hash = (body or {}).get("known_hash")
            reason = (body or {}).get("reason", "manual")
            self.respond_json(self.state.ensure_fresh(known_hash, reason))
            return

        self.respond_json({"error": "not_found"}, status=HTTPStatus.NOT_FOUND)

    def read_json_body(self) -> dict[str, Any] | None:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length == 0:
            return {}
        raw = self.rfile.read(length)
        try:
            return json.loads(raw.decode("utf-8"))
        except json.JSONDecodeError:
            self.respond_json({"error": "invalid_json"}, status=HTTPStatus.BAD_REQUEST)
            return None

    def authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        expected = f"Bearer {self.state.config.secret}"
        if header != expected:
            self.respond_json({"error": "unauthorized"}, status=HTTPStatus.UNAUTHORIZED)
            return False
        return True

    def render_home(self) -> str:
        status = self.state.status()
        pair_link = html.escape(status["pair_url"])
        return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{APP_NAME}</title>
  <style>
    body {{ font-family: Segoe UI, sans-serif; max-width: 760px; margin: 40px auto; padding: 0 20px; color: #111; }}
    code, pre {{ background: #f5f5f5; padding: 2px 6px; border-radius: 6px; }}
    .card {{ border: 1px solid #ddd; border-radius: 14px; padding: 18px 20px; margin-bottom: 20px; }}
    a.button {{ display: inline-block; margin-top: 10px; padding: 10px 14px; background: #111; color: white; text-decoration: none; border-radius: 10px; }}
  </style>
</head>
<body>
  <h1>{APP_NAME}</h1>
  <div class="card">
    <h2>Phone pairing</h2>
    <p>Open this URL in Safari on the iPhone that is connected to this PC hotspot:</p>
    <pre>{pair_link}</pre>
    <a class="button" href="/pair">Open pairing page</a>
  </div>
  <div class="card">
    <h2>Status</h2>
    <p>LAN address: <code>{html.escape(status['lan_ip'])}:{status['port']}</code></p>
    <p>Last cookie update: <code>{html.escape(str(status['captured_at']))}</code></p>
    <p>Cookie count: <code>{status['cookie_count']}</code></p>
    <p>Last browser refresh: <code>{html.escape(str(status['last_browser_refresh']))}</code></p>
  </div>
</body>
</html>"""

    def render_pair_page(self) -> str:
        host = self.state.lan_ip
        port = self.state.config.port
        secret = self.state.config.secret
        deep_link = self.state.pair_deep_link
        return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Pair ChatGPTWebV15</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f4f4f1; color: #111; padding: 24px; }}
    .card {{ background: white; border-radius: 18px; padding: 24px; box-shadow: 0 10px 30px rgba(0,0,0,.08); max-width: 560px; margin: 0 auto; }}
    a.button {{ display: inline-block; padding: 14px 18px; background: #111; color: white; text-decoration: none; border-radius: 12px; font-weight: 600; }}
    code {{ display: block; background: #f5f5f5; border-radius: 10px; padding: 10px 12px; margin-top: 12px; overflow-wrap: anywhere; white-space: pre-wrap; }}
  </style>
</head>
<body>
  <div class="card">
    <h1>Pair with this desktop</h1>
    <p>Tap the button below to send the helper connection details into the app.</p>
    <p><a class="button" href="{html.escape(deep_link)}">Connect ChatGPTWebV15</a></p>
    <p>If the button does not open the app, use the hidden setup screen and enter these values manually:</p>
    <code>Host: {html.escape(host)}
Port: {port}
Secret: {html.escape(secret)}</code>
  </div>
</body>
</html>"""

    def respond_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        raw = json.dumps(payload, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def respond_html(self, payload: str, status: HTTPStatus = HTTPStatus.OK) -> None:
        raw = payload.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, format: str, *args: Any) -> None:
        pass


class HelperServerThread(threading.Thread):
    def __init__(self, state: HelperState) -> None:
        super().__init__(daemon=True)
        self.state = state
        global CURRENT_STATE
        CURRENT_STATE = state
        self.local_server = ThreadingHTTPServer(("127.0.0.1", state.config.port), HelperRequestHandler)
        self.remote_server: ThreadingHTTPServer | None = None
        self.remote_thread: threading.Thread | None = None

        try:
            self.remote_server = ThreadingHTTPServer((state.remote_host, state.config.port), HelperRequestHandler)
            self.state.remote_enabled = True
            self.state.remote_bind_error = None
        except OSError as error:
            self.remote_server = None
            self.state.remote_enabled = False
            self.state.remote_bind_error = str(error)

    def run(self) -> None:
        if self.remote_server is not None:
            self.remote_thread = threading.Thread(target=self.remote_server.serve_forever, daemon=True)
            self.remote_thread.start()

        self.local_server.serve_forever()

    def stop(self) -> None:
        self.local_server.shutdown()
        self.local_server.server_close()

        if self.remote_server is not None:
            self.remote_server.shutdown()
            self.remote_server.server_close()


def main() -> None:
    state = HelperState()
    server = HelperServerThread(state)
    server.start()
    print(f"{APP_NAME} listening on http://127.0.0.1:{state.config.port}")
    print(f"Phone pairing page: {state.pair_url}")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        server.stop()


if __name__ == "__main__":
    main()
