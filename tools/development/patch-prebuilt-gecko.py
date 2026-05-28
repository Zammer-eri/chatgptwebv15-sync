#!/usr/bin/env python3

from pathlib import Path
import sys
import zipfile


RUNTIME_PATCH_VERSION = 44
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
CHATGPT_HEALTH_CHILD_METHODS = r"""

  installChatGPTHealthProbe(reason = "install") {
    const win = this.contentWindow;
    if (!win || !win.location || !/^(chatgpt\.com|.*\.chatgpt\.com)$/i.test(win.location.hostname)) {
      return;
    }

    if (this._chatGPTHealthWindow === win) {
      this.scheduleChatGPTHealth(reason);
      return;
    }

    this._chatGPTHealthWindow = win;
    this._chatGPTHealthSeq = 0;
    this._chatGPTHealthHref = "";
    this._chatGPTHealthErrors = [];
    this._chatGPTHealthRejections = [];

    const remember = (list, value) => {
      list.push(String(value || "").slice(0, 240));
      if (list.length > 5) {
        list.shift();
      }
    };

    win.addEventListener(
      "error",
      event => remember(this._chatGPTHealthErrors, event.message || event.error),
      true
    );
    win.addEventListener(
      "unhandledrejection",
      event => remember(this._chatGPTHealthRejections, event.reason),
      true
    );

    const tick = () => {
      if (this._chatGPTHealthWindow !== win || win.closed) {
        return;
      }
      const href = win.location.href;
      if (href !== this._chatGPTHealthHref) {
        this._chatGPTHealthHref = href;
        this.scheduleChatGPTHealth("href");
      }
    };

    win.setTimeout(tick, 250);
    win.setTimeout(tick, 1000);
    win.setTimeout(tick, 3000);
    win.setInterval(tick, 1500);
    this.scheduleChatGPTHealth(reason);
  }

  scheduleChatGPTHealth(reason = "scheduled") {
    const win = this.contentWindow;
    if (!win) {
      return;
    }

    for (const delay of [600, 2000, 5000]) {
      win.setTimeout(() => this.sendChatGPTHealth(`${reason}+${delay}`), delay);
    }
  }

  async sendChatGPTHealth(reason = "probe") {
    const win = this.contentWindow;
    const doc = win?.document;
    if (!win || !doc || !/^(chatgpt\.com|.*\.chatgpt\.com)$/i.test(win.location.hostname)) {
      return;
    }

    const count = selector => {
      try {
        return doc.querySelectorAll(selector).length;
      } catch (_) {
        return -1;
      }
    };

    let indexedDBCount = -1;
    try {
      if (win.indexedDB?.databases) {
        const databases = await win.Promise.race([
          win.indexedDB.databases(),
          new win.Promise(resolve => win.setTimeout(() => resolve(null), 300)),
        ]);
        indexedDBCount = Array.isArray(databases) ? databases.length : -1;
      }
    } catch (_) {}

    const body = doc.body;
    const bodyText = body?.textContent || "";
    const visibleText = body?.innerText || "";
    this.eventDispatcher?.sendRequest({
      type: "GeckoView:ChatGPTHealth",
      seq: ++this._chatGPTHealthSeq,
      reason,
      href: win.location.href,
      readyState: doc.readyState,
      title: doc.title || "",
      bodyTextLength: bodyText.length,
      visibleTextLength: visibleText.length,
      composerCount: count('[contenteditable="true"], textarea, [data-testid*="composer"], form textarea'),
      textareaCount: count("textarea"),
      buttonCount: count("button"),
      testIdCount: count("[data-testid]"),
      articleCount: count("article"),
      mainCount: count("main"),
      navCount: count("nav, aside"),
      localStorageLength: (() => {
        try {
          return win.localStorage?.length ?? -1;
        } catch (_) {
          return -1;
        }
      })(),
      indexedDBCount,
      errorCount: this._chatGPTHealthErrors?.length || 0,
      lastError: this._chatGPTHealthErrors?.at(-1) || "",
      rejectionCount: this._chatGPTHealthRejections?.length || 0,
      lastRejection: this._chatGPTHealthRejections?.at(-1) || "",
    });
  }
"""


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


def patch_text_in_omni(bin_dir: Path, suffix: str, patcher) -> bool:
    changed = False
    for omni_path in bin_dir.rglob("omni.ja"):
        with zipfile.ZipFile(omni_path, "r") as archive:
            entries = {info.filename: archive.read(info.filename) for info in archive.infolist()}
            infos = {info.filename: info for info in archive.infolist()}

        for name, data in list(entries.items()):
            if not name.endswith(suffix):
                continue
            text = data.decode("utf-8")
            new_text = patcher(text)
            if new_text == text:
                continue
            entries[name] = new_text.encode("utf-8")
            changed = True

        if changed:
            with zipfile.ZipFile(omni_path, "w") as archive:
                for name, data in entries.items():
                    info = infos[name]
                    replacement = zipfile.ZipInfo(name, date_time=info.date_time)
                    replacement.compress_type = info.compress_type
                    replacement.external_attr = info.external_attr
                    archive.writestr(replacement, data)
    return changed


def patch_chatgpt_health_child(text: str) -> str:
    if "GeckoView:ChatGPTHealth" in text:
        return text

    marker = "\n  orientation() {"
    if marker not in text:
        return text
    text = text.replace(marker, CHATGPT_HEALTH_CHILD_METHODS + marker, 1)

    pageshow = 'case "pageshow": {\n        this.receivedPageShow();'
    if pageshow in text:
        text = text.replace(
            pageshow,
            pageshow + '\n        this.installChatGPTHealthProbe("pageshow");',
            1,
        )
    return text


def patch_chatgpt_health(bin_dir: Path) -> bool:
    return patch_text_in_omni(
        bin_dir,
        "GeckoViewContentChild.sys.mjs",
        patch_chatgpt_health_child,
    )


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-prebuilt-gecko.py <dist-bin-dir>")

    bin_dir = Path(sys.argv[1])
    extension_prefs_changed = patch_extension_prefs(bin_dir)
    chatgpt_health_changed = patch_chatgpt_health(bin_dir)

    print("Reynard ChatGPT runtime patch:")
    print(f"  runtime patch version: {RUNTIME_PATCH_VERSION}")
    print("  ChatGPT runtime hooks patched: disabled")
    print("  ChatGPT diagnostics query patched: disabled")
    print(f"  ChatGPT health beacon patched: {chatgpt_health_changed}")
    print(f"  extension prefs override patched: {extension_prefs_changed}")


if __name__ == "__main__":
    main()
