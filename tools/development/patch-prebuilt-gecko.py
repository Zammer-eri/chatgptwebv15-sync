#!/usr/bin/env python3

from pathlib import Path
import sys
import json


RUNTIME_PATCH_VERSION = 44
SCRIPT_DIR = Path(__file__).resolve().parent
SHELL_RUNTIME_MARKER = "installEmbeddedGPTReturnRuntime"
PAGE_RUNTIME_FILE = SCRIPT_DIR / "chatgpt-shell" / "page-runtime.js"
EXTENSION_PREFS_BEGIN = "// BEGIN Reynard ChatGPT shell extension prefs"
EXTENSION_PREFS_END = "// END Reynard ChatGPT shell extension prefs"
EXTENSION_PREF_OVERRIDES = f"""{EXTENSION_PREFS_BEGIN}
// This shell does not expose browser add-ons. Keep the inherited Gecko
// extension manager from scanning, installing, or waking extension state.
pref("extensions.isembedded", false);
pref("extensions.enabledScopes", 0);
pref("extensions.getAddons.cache.enabled", false);
pref("extensions.installDistroAddons", false);
pref("extensions.systemAddon.update.enabled", false);
pref("extensions.update.autoUpdateDefault", false);
pref("extensions.update.enabled", false);
pref("extensions.webextensions.early_background_wakeup_on_request", false);
pref("extensions.webextensions.remote", false);
pref("xpinstall.enabled", false);
pref("xpinstall.signatures.required", true);
pref("xpinstall.whitelist.add", "");
pref("xpinstall.whitelist.fileRequest", false);
{EXTENSION_PREFS_END}
"""


def read_page_runtime() -> str:
    page_script = PAGE_RUNTIME_FILE.read_text(encoding="utf-8")
    bootstrap = "\n;window.EmbeddedGPTShellRuntime.install();\n"
    return "(() => {\n  \"use strict\";\n" + page_script + bootstrap + "\n})();"


def shell_runtime_method() -> str:
    page_script = json.dumps(read_page_runtime())
    return f'''  installEmbeddedGPTReturnRuntime() {{
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
          sandboxName: "Embedded GPT composer return runtime",
          sandboxPrototype: win,
          sameZoneAs: win,
          originAttributes: doc.nodePrincipal.originAttributes,
          wantXrays: false,
        }});
        Cu.evalInSandbox(
          {page_script},
          sandbox,
          null,
          "embedded-gpt-composer-return.js",
          1
        );
      }} catch (error) {{
        debug`Cannot install Embedded GPT composer return runtime: ${{error}}`;
      }}
    }};

    run();

    const win = this.contentWindow;
    if (!win || this._embeddedGPTComposerReturnHooksInstalled) {{
      return;
    }}

    this._embeddedGPTComposerReturnHooksInstalled = true;
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


def patch_geckoview_content_child(bin_dir: Path) -> bool:
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
    this.installEmbeddedGPTReturnRuntime();
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
    this.installEmbeddedGPTReturnRuntime();
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
        text = text.replace(marker, shell_runtime_method() + marker, 1)

    original_pageshow = """      case "pageshow": {
        this.receivedPageShow();
        break;
      }
"""
    patched_pageshow = """      case "DOMContentLoaded": {
        this.installEmbeddedGPTReturnRuntime();
        break;
      }
      case "pageshow": {
        this.installEmbeddedGPTReturnRuntime();
        this.receivedPageShow();
        break;
      }
"""
    if original_pageshow in text:
        text = text.replace(original_pageshow, patched_pageshow, 1)
    elif '      case "DOMContentLoaded": {\n        this.installEmbeddedGPTReturnRuntime();' not in text:
        raise RuntimeError(f"Cannot find pageshow hook in {path}")

    if text != original_text:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def patch_geckoview_startup(bin_dir: Path) -> bool:
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


def patch_extension_prefs(bin_dir: Path) -> bool:
    prefs_dir = bin_dir / "defaults" / "pref"
    prefs_dir.mkdir(parents=True, exist_ok=True)
    path = prefs_dir / "reynard-chatgpt-shell.js"
    text = path.read_text(encoding="utf-8") if path.exists() else ""

    if EXTENSION_PREFS_BEGIN in text and EXTENSION_PREFS_END in text:
        start = text.index(EXTENSION_PREFS_BEGIN)
        end = text.index(EXTENSION_PREFS_END) + len(EXTENSION_PREFS_END)
        replacement = EXTENSION_PREF_OVERRIDES.rstrip()
        prefix = text[:start].rstrip()
        suffix = text[end:].lstrip("\n")
        new_text = (prefix + "\n" if prefix else "") + replacement + "\n" + suffix
    else:
        prefix = text.rstrip()
        new_text = (prefix + "\n\n" if prefix else "") + EXTENSION_PREF_OVERRIDES

    if new_text == text:
        return False

    path.write_text(new_text, encoding="utf-8")
    return True


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-prebuilt-gecko.py <dist-bin-dir>")

    bin_dir = Path(sys.argv[1])
    content_child_changed = patch_geckoview_content_child(bin_dir)
    startup_changed = patch_geckoview_startup(bin_dir)
    extension_prefs_changed = patch_extension_prefs(bin_dir)

    print("Reynard ChatGPT runtime patch:")
    print(f"  runtime patch version: {RUNTIME_PATCH_VERSION}")
    print(f"  ChatGPT composer return hooks patched: {content_child_changed or startup_changed}")
    print("  ChatGPT diagnostics query patched: disabled")
    print(f"  extension prefs override patched: {extension_prefs_changed}")


if __name__ == "__main__":
    main()
