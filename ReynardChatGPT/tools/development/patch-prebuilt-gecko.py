#!/usr/bin/env python3

from pathlib import Path
import sys


FOCUS_GUARD_MARKER = "installChatGPTShellFocusGuard"


FOCUS_GUARD_METHOD = r'''  installChatGPTShellFocusGuard() {
    const win = this.contentWindow;
    const doc = win?.document;
    if (!win || !doc || win.__reynardChatGPTFocusGuardInstalled) {
      return;
    }

    try {
      Object.defineProperty(win, "__reynardChatGPTFocusGuardInstalled", {
        value: true,
      });
    } catch (_) {
      win.__reynardChatGPTFocusGuardInstalled = true;
    }

    const state = {
      lastEditable: null,
      lastDraft: "",
      lastPointerAt: 0,
      lastPointerTarget: null,
      allowBlurUntil: 0,
      pendingPreserve: false,
    };

    const isChatGPT = () => {
      const host = win.location?.hostname || "";
      return host === "chatgpt.com" || host.endsWith(".chatgpt.com");
    };

    const isElement = element => element && element.nodeType === 1;

    const textValue = element => {
      if (!isElement(element)) {
        return "";
      }
      if (typeof element.value === "string") {
        return element.value;
      }
      return element.textContent || "";
    };

    const normalizedText = element =>
      textValue(element).replace(/\u200b/g, "").trim();

    const labelText = (element, includeText = false) => {
      if (!isElement(element)) {
        return "";
      }
      const parts = [
        element.id,
        element.getAttribute("name"),
        element.getAttribute("data-testid"),
        element.getAttribute("aria-label"),
        element.getAttribute("placeholder"),
        element.getAttribute("data-placeholder"),
        element.getAttribute("title"),
      ];
      if (includeText) {
        parts.push(element.textContent);
      }
      return parts
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
    };

    const isEditableElement = element => {
      if (!isElement(element)) {
        return false;
      }

      const localName = element.localName;
      if (localName === "textarea") {
        return true;
      }
      if (localName === "input") {
        return typeof element.mozIsTextField === "function"
          ? element.mozIsTextField(false)
          : !/^(button|checkbox|file|hidden|image|radio|range|reset|submit)$/i.test(
              element.type || ""
            );
      }

      return (
        element.isContentEditable ||
        element.getAttribute("contenteditable") === "true" ||
        element.getAttribute("role") === "textbox"
      );
    };

    const hasSendControl = root => {
      if (!isElement(root)) {
        return false;
      }
      for (const control of root.querySelectorAll('button,[role="button"]')) {
        if (/\bsend\b|send-button|submit/.test(labelText(control, true))) {
          return true;
        }
      }
      return false;
    };

    const composerRoot = element => {
      if (!isElement(element)) {
        return null;
      }
      return (
        element.closest(
          'form,[data-testid*="composer"],[class*="composer"],main'
        ) || element.parentElement
      );
    };

    const isComposerEditable = element => {
      if (!isEditableElement(element)) {
        return false;
      }

      const label = labelText(element);
      if (
        /prompt-textarea|composer|message|ask anything|ask chatgpt|prompt/.test(
          label
        )
      ) {
        return true;
      }

      const root = composerRoot(element);
      return Boolean(
        root &&
          (hasSendControl(root) ||
            /composer/.test(labelText(root)) ||
            /ask anything|message chatgpt/.test(labelText(root)))
      );
    };

    const hasDraft = element => normalizedText(element).length > 0;

    const findComposerEditable = () => {
      const selectors = [
        "#prompt-textarea",
        'textarea[name="prompt-textarea"]',
        'textarea[data-testid*="prompt"]',
        'textarea[placeholder]',
        '[contenteditable="true"][role="textbox"]',
        '[contenteditable="true"][data-placeholder]',
        '[contenteditable="true"][aria-label]',
        '[role="textbox"][aria-label]',
      ].join(",");

      for (const candidate of doc.querySelectorAll(selectors)) {
        if (isComposerEditable(candidate)) {
          return candidate;
        }
      }
      return null;
    };

    const rememberEditable = element => {
      if (!isComposerEditable(element)) {
        return;
      }
      state.lastEditable = element;
      state.lastDraft = normalizedText(element);
    };

    const elementContains = (parent, child) =>
      isElement(parent) && isElement(child) && (parent === child || parent.contains(child));

    const shouldProtectFocus = element => {
      if (!isChatGPT() || !isComposerEditable(element) || !hasDraft(element)) {
        return false;
      }

      const now = Date.now();
      if (now < state.allowBlurUntil) {
        return false;
      }

      if (
        state.lastPointerTarget &&
        now - state.lastPointerAt < 900 &&
        !elementContains(element, state.lastPointerTarget)
      ) {
        return false;
      }

      return true;
    };

    const preserveComposerFocus = element => {
      const remembered = element || state.lastEditable;
      if (!shouldProtectFocus(remembered)) {
        return;
      }

      const target =
        remembered?.isConnected && isComposerEditable(remembered)
          ? remembered
          : findComposerEditable();
      if (!target || !hasDraft(target) || doc.activeElement === target) {
        return;
      }

      try {
        target.focus({ preventScroll: true });
      } catch (_) {
        target.focus();
      }
      rememberEditable(target);
    };

    const schedulePreserveComposerFocus = element => {
      if (state.pendingPreserve) {
        return;
      }
      state.pendingPreserve = true;
      win.queueMicrotask(() => {
        state.pendingPreserve = false;
        preserveComposerFocus(element);
      });
    };

    const onFocusIn = event => {
      rememberEditable(event.target);
    };

    const onInput = event => {
      rememberEditable(event.target);
    };

    const onPointerStart = event => {
      state.lastPointerAt = Date.now();
      state.lastPointerTarget = event.target;

      const active = isComposerEditable(doc.activeElement)
        ? doc.activeElement
        : state.lastEditable;
      if (!elementContains(active, event.target)) {
        state.allowBlurUntil = Date.now() + 1400;
      }
    };

    const onKeyDown = event => {
      if (!isComposerEditable(doc.activeElement)) {
        return;
      }
      if (
        event.key === "Escape" ||
        (event.key === "Enter" &&
          !event.shiftKey &&
          !event.altKey &&
          !event.ctrlKey &&
          !event.metaKey)
      ) {
        state.allowBlurUntil = Date.now() + 1400;
      }
    };

    const onFocusExit = event => {
      if (!shouldProtectFocus(event.target)) {
        return;
      }

      event.stopImmediatePropagation();
      preserveComposerFocus(event.target);
      schedulePreserveComposerFocus(event.target);
      win.requestAnimationFrame(() => preserveComposerFocus(event.target));
    };

    win.addEventListener("focusin", onFocusIn, true);
    win.addEventListener("input", onInput, true);
    win.addEventListener("beforeinput", onInput, true);
    win.addEventListener("pointerdown", onPointerStart, true);
    win.addEventListener("touchstart", onPointerStart, true);
    win.addEventListener("mousedown", onPointerStart, true);
    win.addEventListener("keydown", onKeyDown, true);
    win.addEventListener("blur", onFocusExit, true);
    win.addEventListener("focusout", onFocusExit, true);

    const observer = new win.MutationObserver(() => {
      if (
        state.lastEditable &&
        state.lastDraft &&
        !isComposerEditable(doc.activeElement)
      ) {
        schedulePreserveComposerFocus(state.lastEditable);
      }
    });

    if (doc.documentElement) {
      observer.observe(doc.documentElement, {
        childList: true,
        subtree: true,
      });
    }
  }

'''


def patch_geckoview_content_child(bin_dir: Path) -> None:
    path = bin_dir / "actors" / "GeckoViewContentChild.sys.mjs"
    text = path.read_text()
    if FOCUS_GUARD_MARKER in text:
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
    this.installChatGPTShellFocusGuard();
  }
"""

    if original_actor_created not in text:
        raise RuntimeError(f"Cannot find actorCreated hook in {path}")
    text = text.replace(original_actor_created, patched_actor_created, 1)

    marker = "  collectSessionState() {\n"
    if marker not in text:
        raise RuntimeError(f"Cannot find collectSessionState hook in {path}")
    text = text.replace(marker, FOCUS_GUARD_METHOD + marker, 1)

    original_pageshow = """      case "pageshow": {
        this.receivedPageShow();
        break;
      }
"""
    patched_pageshow = """      case "pageshow": {
        this.installChatGPTShellFocusGuard();
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
