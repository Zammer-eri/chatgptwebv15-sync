#!/usr/bin/env python3

from pathlib import Path
import sys


EMOJI_RENDERER_MARKER = "installChatGPTShellEmojiRenderer"
DIAGNOSTICS_MARKER = "installChatGPTShellDiagnostics"


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


DIAGNOSTICS_METHOD = r'''  installChatGPTShellDiagnostics() {
    const win = this.contentWindow;
    const doc = win?.document;
    if (!win || !doc || win.__reynardChatGPTDiagnosticsInstalled) {
      return;
    }

    try {
      Object.defineProperty(win, "__reynardChatGPTDiagnosticsInstalled", {
        value: true,
      });
    } catch (_) {
      win.__reynardChatGPTDiagnosticsInstalled = true;
    }

    const isChatGPT = () => {
      const host = win.location?.hostname || "";
      return host === "chatgpt.com" || host.endsWith(".chatgpt.com");
    };

    const clean = value =>
      String(value ?? "")
        .replace(/\s+/g, " ")
        .slice(0, 140);

    const isEditable = element => {
      if (!element) {
        return false;
      }
      return (
        (win.HTMLInputElement && element instanceof win.HTMLInputElement) ||
        (win.HTMLTextAreaElement && element instanceof win.HTMLTextAreaElement) ||
        element.isContentEditable === true
      );
    };

    const elementSummary = element => {
      if (!element) {
        return "nil";
      }

      const tag = element.localName || element.nodeName || "unknown";
      const parts = [tag];
      if (element.id) {
        parts.push(`#${clean(element.id)}`);
      }
      if (element.className && typeof element.className === "string") {
        parts.push(`.${clean(element.className).replace(/\s+/g, ".")}`);
      }

      for (const name of ["data-testid", "aria-label", "role", "contenteditable", "name", "type"]) {
        const value = element.getAttribute?.(name);
        if (value) {
          parts.push(`[${name}=${clean(value)}]`);
        }
      }

      return parts.join("");
    };

    const editableTextLength = element => {
      if (!isEditable(element)) {
        return 0;
      }
      if (typeof element.value === "string") {
        return element.value.length;
      }
      return (element.textContent || "").length;
    };

    const editableHasDraft = element => {
      if (!isEditable(element)) {
        return false;
      }
      const value =
        typeof element.value === "string" ? element.value : element.textContent || "";
      return value.replace(/\u200b/g, "").trim().length > 0;
    };

    const streamingActive = () => {
      const candidates = doc.querySelectorAll("button,[role='button'],[data-testid]");
      for (const element of candidates) {
        const signature = clean(
          `${element.getAttribute?.("aria-label") || ""} ${
            element.getAttribute?.("data-testid") || ""
          } ${element.textContent || ""}`
        );
        if (/\b(stop|interrupt|cancel response|stop generating)\b/i.test(signature)) {
          return true;
        }
      }
      return false;
    };

    const activeState = () => {
      const active = doc.activeElement;
      return {
        activeElement: elementSummary(active),
        activeEditable: isEditable(active),
        activeTextLength: editableTextLength(active),
        hasDraft: editableHasDraft(active),
        streaming: streamingActive(),
        visibilityState: doc.visibilityState,
        innerHeight: win.innerHeight,
        visualViewportHeight: Math.round(win.visualViewport?.height || 0),
        visualViewportOffsetTop: Math.round(win.visualViewport?.offsetTop || 0),
      };
    };

    const dispatchDiagnostic = (diagnosticEvent, extra = {}) => {
      if (!isChatGPT()) {
        return;
      }

      const payload = {
        type: "GeckoView:ChatGPTShellDiagnostic",
        diagnosticEvent,
        source: "page",
        url: clean(win.location?.href || ""),
        ...activeState(),
        ...extra,
      };

      try {
        this.eventDispatcher?.sendRequest(payload);
      } catch (error) {
        try {
          console.warn("ChatGPT shell diagnostic dispatch failed", error);
        } catch (_) {}
      }
    };

    const keyName = event => {
      if (!event?.key) {
        return "";
      }
      return event.key.length === 1 ? "character" : event.key;
    };

    let lastStateSignature = "";
    let stateScheduled = false;

    const dispatchStateIfChanged = diagnosticEvent => {
      stateScheduled = false;
      if (!isChatGPT()) {
        return;
      }

      const state = activeState();
      const signature = JSON.stringify(state);
      if (signature === lastStateSignature) {
        return;
      }
      lastStateSignature = signature;
      dispatchDiagnostic(diagnosticEvent, { stateSignature: signature });
    };

    const scheduleStateCheck = diagnosticEvent => {
      if (stateScheduled) {
        return;
      }
      stateScheduled = true;
      win.setTimeout(() => dispatchStateIfChanged(diagnosticEvent), 180);
    };

    const eventOptions = { capture: true, passive: true };
    for (const eventName of ["focusin", "focusout", "blur", "input", "beforeinput"]) {
      doc.addEventListener(
        eventName,
        event => {
          dispatchDiagnostic(eventName, {
            target: elementSummary(event.target),
            relatedTarget: elementSummary(event.relatedTarget),
            inputType: clean(event.inputType || ""),
            isComposing: event.isComposing === true,
          });
        },
        eventOptions
      );
    }

    for (const eventName of ["keydown", "keyup"]) {
      doc.addEventListener(
        eventName,
        event => {
          dispatchDiagnostic(eventName, {
            target: elementSummary(event.target),
            key: keyName(event),
            code: event.key?.length === 1 ? "character" : clean(event.code || ""),
            metaKey: event.metaKey === true,
            altKey: event.altKey === true,
            ctrlKey: event.ctrlKey === true,
            shiftKey: event.shiftKey === true,
          });
        },
        eventOptions
      );
    }

    doc.addEventListener(
      "selectionchange",
      () => scheduleStateCheck("selectionchange"),
      eventOptions
    );
    doc.addEventListener(
      "visibilitychange",
      () => dispatchDiagnostic("visibilitychange"),
      eventOptions
    );
    win.visualViewport?.addEventListener(
      "resize",
      () => dispatchDiagnostic("visualViewport.resize"),
      eventOptions
    );
    win.visualViewport?.addEventListener(
      "scroll",
      () => scheduleStateCheck("visualViewport.scroll"),
      eventOptions
    );

    const observer = new win.MutationObserver(() => scheduleStateCheck("mutation"));
    if (doc.documentElement) {
      observer.observe(doc.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["aria-label", "data-testid", "disabled", "class"],
      });
    }

    dispatchDiagnostic("diagnostics.installed");
  }

'''


def patch_geckoview_content_child(bin_dir: Path) -> None:
    path = bin_dir / "actors" / "GeckoViewContentChild.sys.mjs"
    text = path.read_text()
    if EMOJI_RENDERER_MARKER in text and DIAGNOSTICS_MARKER in text:
        return

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
    this.installChatGPTShellEmojiRenderer();
    this.installChatGPTShellDiagnostics();
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
    this.installChatGPTShellEmojiRenderer();
    this.installChatGPTShellDiagnostics();
  }
""",
        ),
    ]

    for original_actor_created, patched_actor_created in actor_created_variants:
        if original_actor_created in text:
            text = text.replace(original_actor_created, patched_actor_created, 1)
            break
    else:
        raise RuntimeError(f"Cannot find actorCreated hook in {path}")

    marker = "  collectSessionState() {\n"
    if marker not in text:
        raise RuntimeError(f"Cannot find collectSessionState hook in {path}")
    text = text.replace(marker, EMOJI_RENDERER_METHOD + DIAGNOSTICS_METHOD + marker, 1)

    original_pageshow = """      case "pageshow": {
        this.receivedPageShow();
        break;
      }
"""
    patched_pageshow = """      case "pageshow": {
        this.installChatGPTShellEmojiRenderer();
        this.installChatGPTShellDiagnostics();
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
