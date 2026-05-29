#!/usr/bin/env python3

from pathlib import Path
import sys
import zipfile


RUNTIME_PATCH_VERSION = 46
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

CHATGPT_TAP_PROBE_METHODS = r"""

  installChatGPTTapProbe(reason = "install") {
    const win = this.contentWindow;
    const doc = win?.document;
    if (!win || !doc || !/^(chatgpt\.com|.*\.chatgpt\.com)$/i.test(win.location.hostname)) {
      return;
    }

    if (this._chatGPTTapProbeWindow === win) {
      return;
    }
    this._chatGPTTapProbeWindow = win;
    this._chatGPTTapProbeSeq = 0;

    const trim = value => String(value || "").replace(/\s+/g, " ").slice(0, 180);
    const describe = element => {
      if (!element || element.nodeType !== 1) {
        return null;
      }
      const rect = element.getBoundingClientRect?.();
      return {
        tag: element.tagName || "",
        id: trim(element.id),
        role: trim(element.getAttribute("role")),
        aria: trim(element.getAttribute("aria-label")),
        testid: trim(element.getAttribute("data-testid")),
        type: trim(element.getAttribute("type")),
        text: trim(element.innerText || element.textContent),
        cls: trim(element.className),
        rect: rect ? [
          Math.round(rect.left),
          Math.round(rect.top),
          Math.round(rect.width),
          Math.round(rect.height),
        ].join(",") : "",
      };
    };

    const chainFor = target => {
      const chain = [];
      let node = target;
      for (let i = 0; node && i < 8; i += 1, node = node.parentElement) {
        const item = describe(node);
        if (item) {
          chain.push(item);
        }
      }
      return chain;
    };

    const shouldReport = target => {
      const element = target?.closest?.("button,[role='button'],input,textarea,[contenteditable='true'],[data-testid]");
      if (!element) {
        return false;
      }
      const text = `${element.getAttribute("aria-label") || ""} ${element.getAttribute("data-testid") || ""} ${element.innerText || ""}`;
      const lower = text.toLowerCase();
      return /add|attach|upload|file|photo|image|tool|deep|research|think|model|reason|composer|\+/.test(lower);
    };

    const send = event => {
      if (!shouldReport(event.target)) {
        return;
      }
      const active = doc.activeElement;
      this.eventDispatcher?.sendRequest({
        type: "GeckoView:ChatGPTTapTarget",
        seq: ++this._chatGPTTapProbeSeq,
        reason,
        eventType: event.type,
        href: win.location.href,
        x: Math.round(event.clientX || 0),
        y: Math.round(event.clientY || 0),
        activeTag: active?.tagName || "",
        activeAria: trim(active?.getAttribute?.("aria-label")),
        activeTestid: trim(active?.getAttribute?.("data-testid")),
        chain: chainFor(event.target),
      });
    };

    doc.addEventListener("pointerdown", send, true);
    doc.addEventListener("click", send, true);
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

        omni_changed = False
        for name, data in list(entries.items()):
            if not name.endswith(suffix):
                continue
            text = data.decode("utf-8")
            new_text = patcher(text)
            if new_text == text:
                continue
            entries[name] = new_text.encode("utf-8")
            omni_changed = True
            changed = True

        if omni_changed:
            with zipfile.ZipFile(omni_path, "w") as archive:
                for name, data in entries.items():
                    info = infos[name]
                    replacement = zipfile.ZipInfo(name, date_time=info.date_time)
                    replacement.compress_type = info.compress_type
                    replacement.external_attr = info.external_attr
                    archive.writestr(replacement, data)
    return changed


def patch_chatgpt_tap_probe_child(text: str) -> str:
    if "GeckoView:ChatGPTTapTarget" in text:
        return text

    marker = "\n  orientation() {"
    if marker not in text:
        return text
    text = text.replace(marker, CHATGPT_TAP_PROBE_METHODS + marker, 1)

    pageshow = 'case "pageshow": {\n        this.receivedPageShow();'
    if pageshow in text:
        text = text.replace(
            pageshow,
            pageshow + '\n        this.installChatGPTTapProbe("pageshow");',
            1,
        )

    return text


def patch_chatgpt_tap_probe(bin_dir: Path) -> bool:
    return patch_text_in_omni(
        bin_dir,
        "GeckoViewContentChild.sys.mjs",
        patch_chatgpt_tap_probe_child,
    )


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-prebuilt-gecko.py <dist-bin-dir>")

    bin_dir = Path(sys.argv[1])
    extension_prefs_changed = patch_extension_prefs(bin_dir)
    tap_probe_changed = patch_chatgpt_tap_probe(bin_dir)

    print("Reynard ChatGPT runtime patch:")
    print(f"  runtime patch version: {RUNTIME_PATCH_VERSION}")
    print("  ChatGPT runtime hooks patched: disabled")
    print(f"  ChatGPT tap target probe patched: {tap_probe_changed}")
    print(f"  extension prefs override patched: {extension_prefs_changed}")


if __name__ == "__main__":
    main()
