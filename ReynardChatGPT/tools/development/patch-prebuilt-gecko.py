#!/usr/bin/env python3

import json
import os
from pathlib import Path
import sys


SHIM_VERSION = 24
VALID_MODES = {
    "baseline",
    "emoji",
    "all",
}
RUNTIME_MODES = VALID_MODES - {"baseline"}
SHELL_RUNTIME_MARKER = "installChatGPTShellRuntime"
SCRIPT_DIR = Path(__file__).resolve().parent
SHELL_DIR = SCRIPT_DIR / "chatgpt-shell"
PAGE_RUNTIME_FILES = [
    "diagnostics.js",
    "emoji-renderer.js",
    "page-runtime.js",
]


def normalize_mode(value: str | None) -> str:
    mode = (value or "all").strip()
    if mode not in VALID_MODES:
        raise SystemExit(
            "Unsupported REYNARD_CHATGPT_SHIM_MODE "
            f"{mode!r}; expected one of: {', '.join(sorted(VALID_MODES))}"
        )
    return mode


def read_page_runtime(mode: str) -> str:
    sources = []
    for filename in PAGE_RUNTIME_FILES:
        path = SHELL_DIR / filename
        sources.append(f"\n/* {filename} */\n")
        sources.append(path.read_text(encoding="utf-8"))

    bootstrap = (
        "\n;window.ReynardChatGPTShellRuntime.install({"
        f"mode: {json.dumps(mode)}"
        "});\n"
    )
    return "(() => {\n  \"use strict\";\n" + "\n".join(sources) + bootstrap + "\n})();"


def shell_runtime_method(mode: str) -> str:
    page_script = json.dumps(read_page_runtime(mode))
    mode_json = json.dumps(mode)
    return f'''  installChatGPTShellRuntime() {{
    const run = () => {{
      const win = this.contentWindow;
      const doc = win?.document;
      if (!win || !doc?.nodePrincipal) {{
        return;
      }}

      const host = win.location?.hostname || "";
      if (host !== "chatgpt.com" && !host.endsWith(".chatgpt.com")) {{
        return;
      }}

      try {{
        const sandbox = Cu.Sandbox([doc.nodePrincipal], {{
          sandboxName: "Reynard ChatGPT shell page runtime",
          sandboxPrototype: win,
          sameZoneAs: win,
          originAttributes: doc.nodePrincipal.originAttributes,
          wantXrays: false,
        }});
        sandbox.__REYNARD_CHATGPT_SHIM_MODE__ = {mode_json};
        Cu.evalInSandbox(
          {page_script},
          sandbox,
          null,
          "reynard-chatgpt-shell.js",
          1
        );
      }} catch (error) {{
        debug`Cannot install ChatGPT page runtime: ${{error}}`;
      }}
    }};

    run();

    const win = this.contentWindow;
    if (!win || this._chatGPTShellRuntimeHooksInstalled) {{
      return;
    }}

    this._chatGPTShellRuntimeHooksInstalled = true;
    for (const eventName of ["DOMContentLoaded", "pageshow", "load"]) {{
      win.addEventListener(eventName, () => run(), {{
        capture: true,
        mozSystemGroup: true,
      }});
    }}
    for (const delay of [0, 250, 1000, 2500]) {{
      win.setTimeout(() => run(), delay);
    }}
  }}

'''


def patch_geckoview_content_child(bin_dir: Path, mode: str) -> bool:
    if mode not in RUNTIME_MODES:
        return False

    path = bin_dir / "actors" / "GeckoViewContentChild.sys.mjs"
    text = path.read_text(encoding="utf-8")
    original_text = text

    actor_created_variants = [
        (
            """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
  }
""",
            """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
    this.installChatGPTShellRuntime();
  }
""",
        ),
        (
            """  actorCreated() {
    super.actorCreated();

    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
  }
""",
            """  actorCreated() {
    super.actorCreated();

    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
    this.installChatGPTShellRuntime();
  }
""",
        ),
    ]

    if SHELL_RUNTIME_MARKER not in text:
        for original_actor_created, patched_actor_created in actor_created_variants:
            if original_actor_created in text:
                text = text.replace(original_actor_created, patched_actor_created, 1)
                break
        else:
            raise RuntimeError(f"Cannot find actorCreated hook in {path}")

        marker = "  collectSessionState() {\n"
        if marker not in text:
            raise RuntimeError(f"Cannot find collectSessionState hook in {path}")
        text = text.replace(marker, shell_runtime_method(mode) + marker, 1)

    original_pageshow = """      case "pageshow": {
        this.receivedPageShow();
        break;
      }
"""
    patched_pageshow = """      case "DOMContentLoaded": {
        this.installChatGPTShellRuntime();
        break;
      }
      case "pageshow": {
        this.installChatGPTShellRuntime();
        this.receivedPageShow();
        break;
      }
"""
    if original_pageshow in text:
        text = text.replace(original_pageshow, patched_pageshow, 1)
    elif '      case "DOMContentLoaded": {\n        this.installChatGPTShellRuntime();' not in text:
        raise RuntimeError(f"Cannot find pageshow hook in {path}")

    if text != original_text:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def patch_geckoview_startup(bin_dir: Path, mode: str) -> bool:
    if mode not in RUNTIME_MODES:
        return False

    path = bin_dir / "chrome" / "geckoview" / "content" / "geckoview.js"
    text = path.read_text(encoding="utf-8")
    if "DOMContentLoaded: { capture: true, mozSystemGroup: true }" in text:
        return False

    event_anchor = """              events: {
                mozcaretstatechanged: { capture: true, mozSystemGroup: true },
                pageshow: { mozSystemGroup: true },
              },
"""
    event_patch = """              events: {
                mozcaretstatechanged: { capture: true, mozSystemGroup: true },
                DOMContentLoaded: { capture: true, mozSystemGroup: true },
                pageshow: { mozSystemGroup: true },
              },
"""
    if event_anchor not in text:
        raise RuntimeError(f"Cannot find GeckoViewContent actor event hook in {path}")
    path.write_text(text.replace(event_anchor, event_patch, 1), encoding="utf-8")
    return True


def main() -> None:
    if len(sys.argv) not in (2, 3):
        raise SystemExit("usage: patch-prebuilt-gecko.py <dist-bin-dir> [baseline|emoji|all]")

    mode = normalize_mode(
        sys.argv[2] if len(sys.argv) == 3 else os.environ.get("REYNARD_CHATGPT_SHIM_MODE")
    )
    bin_dir = Path(sys.argv[1])
    content_child_changed = patch_geckoview_content_child(bin_dir, mode)
    startup_changed = patch_geckoview_startup(bin_dir, mode)

    print("Reynard ChatGPT shim patch diagnostics:")
    print(f"  shim version: {SHIM_VERSION}")
    print(f"  shim mode: {mode}")
    print(f"  ChatGPT runtime hooks requested: {mode in RUNTIME_MODES}")
    print("  emoji fallback: native-apple-color-emoji-css")
    print(
        "  ChatGPT runtime hooks patched: "
        f"{content_child_changed or startup_changed}"
    )
    print("  LightSession: removed")


if __name__ == "__main__":
    main()
