#!/usr/bin/env python3

from pathlib import Path
import sys


RUNTIME_PATCH_VERSION = 42
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


def patch_geckoview_content_module(bin_dir: Path) -> bool:
    path = bin_dir / "chrome" / "geckoview" / "modules" / "GeckoViewContent.sys.mjs"
    if not path.exists():
        path = bin_dir / "modules" / "GeckoViewContent.sys.mjs"
    text = path.read_text(encoding="utf-8")
    original_text = text

    if '"GeckoView:GetChatGPTDiagnostics"' not in text:
        text = text.replace(
            '      "GeckoView:ContainsFormData",\n',
            '      "GeckoView:ContainsFormData",\n      "GeckoView:GetChatGPTDiagnostics",\n',
            1,
        )
        text = text.replace(
            '      case "GeckoView:ContainsFormData":\n        this._containsFormData(aCallback);\n        break;\n',
            '      case "GeckoView:ContainsFormData":\n        this._containsFormData(aCallback);\n        break;\n'
            '      case "GeckoView:GetChatGPTDiagnostics":\n        this._getChatGPTDiagnostics(aCallback);\n        break;\n',
            1,
        )

    if "_getChatGPTDiagnostics" not in text:
        text = text.replace(
            "  async _hasCookieBannerRuleForBrowsingContextTree(aCallback) {\n",
            """  async _getChatGPTDiagnostics(aCallback) {
    try {
      const actor =
        this.browser?.browsingContext?.currentWindowGlobal?.getActor("GeckoViewContent") ||
        this.actor;
      aCallback.onSuccess(actor ? await actor.sendQuery("GetChatGPTDiagnostics") : null);
    } catch (error) {
      aCallback.onError(`Cannot get ChatGPT diagnostics, error: ${error}`);
    }
  }

  async _hasCookieBannerRuleForBrowsingContextTree(aCallback) {
""",
            1,
        )

    if text != original_text:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def patch_geckoview_content_child(bin_dir: Path) -> bool:
    path = bin_dir / "actors" / "GeckoViewContentChild.sys.mjs"
    text = path.read_text(encoding="utf-8")
    original_text = text

    if "collectChatGPTDiagnostics" not in text:
        text = text.replace(
            "  orientation() {\n",
            """  collectChatGPTDiagnostics() {
    const { contentWindow } = this;
    const doc = contentWindow?.document;
    if (!contentWindow || !doc) {
      return { error: "missing contentWindow/document" };
    }

    const count = selector => {
      try {
        return doc.querySelectorAll(selector).length;
      } catch (_) {
        return -1;
      }
    };
    const textLength = element => {
      try {
        return (element?.innerText || element?.textContent || "").length;
      } catch (_) {
        return -1;
      }
    };
    const exists = selector => count(selector) > 0;
    const keys = storage => {
      try {
        return Object.keys(storage || {}).slice(0, 80);
      } catch (_) {
        return null;
      }
    };
    const errorSample = () => {
      const text = (doc.body?.innerText || "").slice(0, 20000);
      const match = text.match(/(.{0,120}(error|failed|unable|something went wrong|network|cloudflare|sign in|login).{0,120})/i);
      return match ? match[1] : null;
    };
    const resources = () => {
      try {
        return contentWindow.performance
          .getEntriesByType("resource")
          .filter(entry => /chatgpt|openai|oaistatic|oaiusercontent/.test(entry.name))
          .slice(-40)
          .map(entry => {
            let url;
            try {
              url = new URL(entry.name);
            } catch (_) {
              url = null;
            }
            return {
              host: url?.host || null,
              path: url?.pathname?.slice(0, 120) || entry.name.slice(0, 120),
              initiatorType: entry.initiatorType || null,
              duration: Math.round(entry.duration || 0),
              transferSize: entry.transferSize || 0,
              encodedBodySize: entry.encodedBodySize || 0,
            };
          });
      } catch (_) {
        return [];
      }
    };

    return {
      href: contentWindow.location?.href || null,
      readyState: doc.readyState,
      visibilityState: doc.visibilityState,
      title: doc.title,
      bodyTextLength: textLength(doc.body),
      mainTextLength: textLength(doc.querySelector("main")),
      appRootTextLength: textLength(doc.querySelector("#__next, [data-nextjs-root], main")),
      bodyChildCount: doc.body?.children?.length || 0,
      messageCount: count("[data-message-author-role]"),
      articleCount: count("article"),
      conversationNodeCount: count('[data-testid*="conversation"], [data-testid*="message"]'),
      composerCount: count('textarea, [contenteditable="true"][role="textbox"], [contenteditable="true"]'),
      navCount: count("nav"),
      mainExists: exists("main"),
      errorSample: errorSample(),
      localStorageKeys: keys(contentWindow.localStorage),
      sessionStorageKeys: keys(contentWindow.sessionStorage),
      serviceWorkerController: contentWindow.navigator?.serviceWorker?.controller?.scriptURL || null,
      resourceSample: resources(),
    };
  }

  orientation() {
""",
            1,
        )

    if 'case "GetChatGPTDiagnostics"' not in text:
        text = text.replace(
            '      case "ContainsFormData": {\n        return this.containsFormData();\n      }\n',
            '      case "ContainsFormData": {\n        return this.containsFormData();\n      }\n'
            '      case "GetChatGPTDiagnostics": {\n        return this.collectChatGPTDiagnostics();\n      }\n',
            1,
        )

    if text != original_text:
        path.write_text(text, encoding="utf-8")
        return True
    return False


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
    content_module_changed = patch_geckoview_content_module(bin_dir)
    content_child_changed = patch_geckoview_content_child(bin_dir)
    extension_prefs_changed = patch_extension_prefs(bin_dir)

    print("Reynard ChatGPT runtime patch:")
    print(f"  runtime patch version: {RUNTIME_PATCH_VERSION}")
    print("  ChatGPT runtime hooks patched: disabled")
    print(f"  ChatGPT diagnostics query patched: {content_module_changed or content_child_changed}")
    print(f"  extension prefs override patched: {extension_prefs_changed}")


if __name__ == "__main__":
    main()
