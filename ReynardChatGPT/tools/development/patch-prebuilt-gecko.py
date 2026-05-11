#!/usr/bin/env python3

from pathlib import Path
import sys


EMOJI_RENDERER_MARKER = "installChatGPTShellEmojiRenderer"


EMOJI_RENDERER_METHOD = r'''  installChatGPTShellEmojiRenderer() {
    const win = this.contentWindow;
    const doc = win?.document;
    if (!win || !doc || win.__reynardChatGPTEmojiRendererInstalled) {
      return;
    }

    try {
      Object.defineProperty(win, "__reynardChatGPTEmojiRendererInstalled", {
        value: true,
      });
    } catch (_) {
      win.__reynardChatGPTEmojiRendererInstalled = true;
    }

    const isChatGPT = () => {
      const host = win.location?.hostname || "";
      return host === "chatgpt.com" || host.endsWith(".chatgpt.com");
    };

    const emojiPattern =
      /[\u{1f1e6}-\u{1f1ff}\u{1f300}-\u{1faff}\u{2600}-\u{27bf}]/u;
    const skipParentSelector =
      'script,style,noscript,textarea,input,[contenteditable="true"],[data-reynard-emoji]';
    const segmenter = win.Intl?.Segmenter
      ? new win.Intl.Segmenter(undefined, { granularity: "grapheme" })
      : null;
    let scheduled = false;

    const splitGraphemes = text => {
      if (segmenter) {
        return Array.from(segmenter.segment(text), segment => segment.segment);
      }
      return Array.from(text);
    };

    const emojiCodepoint = text =>
      Array.from(text)
        .map(char => char.codePointAt(0).toString(16))
        .filter(codepoint => codepoint !== "fe0f" && codepoint !== "fe0e")
        .join("-");

    const emojiImage = text => {
      const codepoint = emojiCodepoint(text);
      if (!codepoint) {
        return doc.createTextNode(text);
      }

      const image = doc.createElement("img");
      image.setAttribute("data-reynard-emoji", "true");
      image.setAttribute("alt", text);
      image.setAttribute("draggable", "false");
      image.src = `https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/${codepoint}.png`;
      image.style.width = "1.2em";
      image.style.height = "1.2em";
      image.style.margin = "0 .03em";
      image.style.verticalAlign = "-0.2em";
      image.style.display = "inline-block";
      return image;
    };

    const shouldSkipTextNode = node => {
      const parent = node.parentElement;
      if (!parent || parent.closest(skipParentSelector)) {
        return true;
      }
      return !emojiPattern.test(node.nodeValue || "");
    };

    const renderTextNode = node => {
      if (shouldSkipTextNode(node)) {
        return;
      }

      const fragment = doc.createDocumentFragment();
      for (const segment of splitGraphemes(node.nodeValue || "")) {
        fragment.appendChild(
          emojiPattern.test(segment) ? emojiImage(segment) : doc.createTextNode(segment)
        );
      }
      node.parentNode?.replaceChild(fragment, node);
    };

    const renderEmojiText = () => {
      scheduled = false;
      if (!isChatGPT() || !doc.body) {
        return;
      }

      const walker = doc.createTreeWalker(
        doc.body,
        win.NodeFilter.SHOW_TEXT,
        {
          acceptNode: node =>
            shouldSkipTextNode(node)
              ? win.NodeFilter.FILTER_REJECT
              : win.NodeFilter.FILTER_ACCEPT,
        }
      );

      const nodes = [];
      while (nodes.length < 250) {
        const node = walker.nextNode();
        if (!node) {
          break;
        }
        nodes.push(node);
      }
      for (const node of nodes) {
        renderTextNode(node);
      }
    };

    const scheduleRender = () => {
      if (scheduled) {
        return;
      }
      scheduled = true;
      win.setTimeout(renderEmojiText, 80);
    };

    const style = doc.createElement("style");
    style.setAttribute("data-reynard-emoji", "true");
    style.textContent =
      'img[data-reynard-emoji="true"]{font-size:inherit;line-height:inherit}';
    doc.documentElement?.appendChild(style);

    const observer = new win.MutationObserver(scheduleRender);
    if (doc.documentElement) {
      observer.observe(doc.documentElement, {
        childList: true,
        characterData: true,
        subtree: true,
      });
    }
    scheduleRender();
  }

'''


def patch_geckoview_content_child(bin_dir: Path) -> None:
    path = bin_dir / "actors" / "GeckoViewContentChild.sys.mjs"
    text = path.read_text()
    if EMOJI_RENDERER_MARKER in text:
        return

    original_actor_created = """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
  }
"""
    patched_actor_created = """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
    this.installChatGPTShellEmojiRenderer();
  }
"""

    if original_actor_created not in text:
        raise RuntimeError(f"Cannot find actorCreated hook in {path}")
    text = text.replace(original_actor_created, patched_actor_created, 1)

    marker = "  collectSessionState() {\n"
    if marker not in text:
        raise RuntimeError(f"Cannot find collectSessionState hook in {path}")
    text = text.replace(marker, EMOJI_RENDERER_METHOD + marker, 1)

    original_pageshow = """      case "pageshow": {
        this.receivedPageShow();
        break;
      }
"""
    patched_pageshow = """      case "pageshow": {
        this.installChatGPTShellEmojiRenderer();
        this.receivedPageShow();
        break;
      }
"""
    if original_pageshow not in text:
        raise RuntimeError(f"Cannot find pageshow hook in {path}")
    text = text.replace(original_pageshow, patched_pageshow, 1)

    path.write_text(text)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-prebuilt-gecko.py <dist-bin-dir>")

    bin_dir = Path(sys.argv[1])
    patch_geckoview_content_child(bin_dir)


if __name__ == "__main__":
    main()
