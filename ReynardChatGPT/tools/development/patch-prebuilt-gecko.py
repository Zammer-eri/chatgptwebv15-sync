#!/usr/bin/env python3

import json
import os
from pathlib import Path
import sys


SHIM_VERSION = 22
VALID_MODES = {
    "baseline",
    "emoji",
    "lightsession-dom",
    "lightsession-fetch",
    "all",
    "legacy-all",
}
RUNTIME_MODES = VALID_MODES - {"baseline"}
LIGHTSESSION_MODES = {
    "lightsession-dom",
    "lightsession-fetch",
    "all",
    "legacy-all",
}
SHELL_RUNTIME_MARKER = "installChatGPTShellRuntime"
SCRIPT_DIR = Path(__file__).resolve().parent
SHELL_DIR = SCRIPT_DIR / "chatgpt-shell"
PAGE_RUNTIME_FILES = [
    "diagnostics.js",
    "emoji-renderer.js",
    "lightsession-trimmer.js",
    "lightsession-runtime.js",
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
    return f'''  installChatGPTShellRuntime(configUpdate = null) {{
    const run = update => {{
      const win = this.contentWindow;
      const doc = win?.document;
      if (!win || !doc?.nodePrincipal) {{
        return;
      }}

      const host = win.location?.hostname || "";
      if (host !== "chatgpt.com" && !host.endsWith(".chatgpt.com")) {{
        return;
      }}

      if (update !== null && typeof update === "object") {{
        this._chatGPTShellLastConfig = update;
      }}

      try {{
        const sandbox = Cu.Sandbox([doc.nodePrincipal], {{
          sandboxName: "Reynard ChatGPT shell page runtime",
          sandboxPrototype: win,
          sameZoneAs: win,
          originAttributes: doc.nodePrincipal.originAttributes,
          wantXrays: false,
        }});
        sandbox.__REYNARD_CHATGPT_SHELL_CONFIG_JSON__ = JSON.stringify(
          this._chatGPTShellLastConfig || null
        );
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

    run(configUpdate);

    const win = this.contentWindow;
    if (!win || this._chatGPTShellRuntimeHooksInstalled) {{
      return;
    }}

    this._chatGPTShellRuntimeHooksInstalled = true;
    const rerun = () => run(null);
    for (const eventName of ["DOMContentLoaded", "pageshow", "load"]) {{
      win.addEventListener(eventName, rerun, {{
        capture: true,
        mozSystemGroup: true,
      }});
    }}
    for (const delay of [0, 250, 1000, 2500]) {{
      win.setTimeout(rerun, delay);
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

    original_receive = """      case "ContainsFormData": {
        return this.containsFormData();
      }
"""
    patched_receive = """      case "ChatGPTShell:UpdateLightSession": {
        this.installChatGPTShellRuntime(message.data || {});
        break;
      }
      case "ContainsFormData": {
        return this.containsFormData();
      }
"""
    if "ChatGPTShell:UpdateLightSession" not in text:
        if original_receive not in text:
            raise RuntimeError(f"Cannot find receiveMessage hook in {path}")
        text = text.replace(original_receive, patched_receive, 1)

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


def patch_geckoview_content_module(bin_dir: Path, mode: str) -> bool:
    if mode not in LIGHTSESSION_MODES:
        return False

    path = bin_dir / "modules" / "GeckoViewContent.sys.mjs"
    text = path.read_text(encoding="utf-8")
    original_text = text
    if "GeckoView:UpdateLightSession" in text:
        return False

    listener_anchor = '      "GeckoView:UpdateInitData",\n'
    if listener_anchor not in text:
        raise RuntimeError(f"Cannot find listener hook in {path}")
    text = text.replace(
        listener_anchor,
        '      "GeckoView:UpdateLightSession",\n' + listener_anchor,
        1,
    )

    switch_anchor = """      case "GeckoView:UpdateInitData":
        this.sendToAllChildren(aEvent, aData);
        break;
"""
    switch_patch = """      case "GeckoView:UpdateLightSession":
        this._updateLightSession(aData);
        break;
      case "GeckoView:UpdateInitData":
        this.sendToAllChildren(aEvent, aData);
        this._updateLightSession(
          aData?.settings?.chatGPTLightSession ||
            this.settings?.chatGPTLightSession ||
            this._chatGPTShellLightSessionConfig ||
            {}
        );
        break;
"""
    if switch_anchor not in text:
        raise RuntimeError(f"Cannot find update switch hook in {path}")
    text = text.replace(switch_anchor, switch_patch, 1)

    method_anchor = "  async _hasCookieBannerRuleForBrowsingContextTree(aCallback) {\n"
    method_patch = """  async _updateLightSession(aData) {
    try {
      const nextConfig =
        aData && typeof aData === "object"
          ? aData
          : this.settings?.chatGPTLightSession ||
            this._chatGPTShellLightSessionConfig ||
            {};
      this._chatGPTShellLightSessionConfig = nextConfig;
      this.sendToAllChildren("ChatGPTShell:UpdateLightSession", nextConfig);
    } catch (error) {
      debug`Cannot update LightSession config: ${error}`;
    }
  }

"""
    if method_anchor not in text:
        raise RuntimeError(f"Cannot find LightSession method hook in {path}")
    text = text.replace(method_anchor, method_patch + method_anchor, 1)

    if text != original_text:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def main() -> None:
    if len(sys.argv) not in (2, 3):
        raise SystemExit(
            "usage: patch-prebuilt-gecko.py <dist-bin-dir> [baseline|emoji|"
            "lightsession-dom|lightsession-fetch|all|legacy-all]"
        )

    mode = normalize_mode(sys.argv[2] if len(sys.argv) == 3 else os.environ.get("REYNARD_CHATGPT_SHIM_MODE"))
    bin_dir = Path(sys.argv[1])
    content_child_changed = patch_geckoview_content_child(bin_dir, mode)
    startup_changed = patch_geckoview_startup(bin_dir, mode)
    content_module_changed = patch_geckoview_content_module(bin_dir, mode)

    print("Reynard ChatGPT shim patch diagnostics:")
    print(f"  shim version: {SHIM_VERSION}")
    print(f"  shim mode: {mode}")
    print(f"  ChatGPT runtime hooks requested: {mode in RUNTIME_MODES}")
    print(
        "  ChatGPT runtime hooks patched: "
        f"{content_child_changed or startup_changed}"
    )
    print(
        "  LightSession native bridge patched: "
        f"{content_module_changed}"
    )


if __name__ == "__main__":
    main()
