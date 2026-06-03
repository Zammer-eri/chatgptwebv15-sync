;(function(root) {
  "use strict";

  const win = root.window || root;
  const doc = win.document;
  if (!doc || doc.__reynardChatGPTTimeAwareInstalled) {
    return;
  }
  doc.__reynardChatGPTTimeAwareInstalled = true;

  const COMPOSER_SELECTOR =
    'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  const STORAGE_PREFIX = "reynard.timeAware.";
  const listenerOptions = { capture: true, passive: false };
  let forwardingClick = false;

  const storageValue = key => {
    try {
      return win.localStorage?.getItem(STORAGE_PREFIX + key) || "";
    } catch (_) {
      return "";
    }
  };

  const isEnabled = () => storageValue("enabled") !== "false";

  const visible = element => {
    const rect = element?.getBoundingClientRect?.();
    return !!rect && rect.width > 0 && rect.height > 0;
  };

  const editableElement = target => {
    const element =
      target instanceof win.Element ? target : target?.parentElement || null;
    return element?.closest?.(COMPOSER_SELECTOR) || null;
  };

  const isComposerEditable = target => {
    const editable = editableElement(target);
    if (!editable || editable.closest("nav,aside")) {
      return false;
    }
    return !!editable.closest(COMPOSER_ROOT_SELECTOR);
  };

  const activeComposerEditable = rootElement => {
    if (isComposerEditable(doc.activeElement)) {
      return editableElement(doc.activeElement);
    }

    const scope = rootElement || doc;
    const editables = Array.from(scope.querySelectorAll?.(COMPOSER_SELECTOR) || []);
    for (let index = editables.length - 1; index >= 0; index--) {
      const editable = editables[index];
      if (isComposerEditable(editable) && visible(editable)) {
        return editable;
      }
    }
    return null;
  };

  const editableText = editable => {
    if (editable instanceof win.HTMLTextAreaElement) {
      return editable.value;
    }
    return editable.textContent || "";
  };

  const dispatchInput = (element, inputType, data) => {
    try {
      element.dispatchEvent(
        new win.InputEvent("input", {
          bubbles: true,
          cancelable: false,
          inputType,
          data,
        })
      );
    } catch (_) {
      element.dispatchEvent(new win.Event("input", { bubbles: true }));
    }
  };

  const resolvedTimeZone = () => {
    const override = storageValue("timeZone").trim();
    if (override) {
      try {
        new Intl.DateTimeFormat(undefined, { timeZone: override }).format(new Date());
        return override;
      } catch (_) {}
    }

    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone || "";
    } catch (_) {
      return "";
    }
  };

  const timestampText = () => {
    const now = new Date();
    const timeZone = resolvedTimeZone();
    let localTime = "";

    try {
      localTime = new Intl.DateTimeFormat(undefined, {
        dateStyle: "medium",
        timeStyle: "medium",
        timeZone: timeZone || undefined,
        timeZoneName: "short",
      }).format(now);
    } catch (_) {
      localTime = now.toString();
    }

    const zoneLabel = timeZone ? ` ${timeZone}` : "";
    return `\n\n[Time context: ${localTime}${zoneLabel}; UTC ${now.toISOString()}]`;
  };

  const placeCaretAtEnd = editable => {
    const selection = doc.getSelection?.();
    if (!selection || editable instanceof win.HTMLTextAreaElement) {
      return;
    }

    const range = doc.createRange();
    range.selectNodeContents(editable);
    range.collapse(false);
    selection.removeAllRanges();
    selection.addRange(range);
  };

  const appendText = (editable, text) => {
    editable.focus?.();

    if (editable instanceof win.HTMLTextAreaElement) {
      const start = editable.value.length;
      const end = editable.value.length;
      editable.setRangeText(text, start, end, "end");
      dispatchInput(editable, "insertText", text);
      return true;
    }

    placeCaretAtEnd(editable);
    try {
      if (doc.execCommand?.("insertText", false, text)) {
        dispatchInput(editable, "insertText", text);
        return true;
      }
    } catch (_) {}

    try {
      editable.appendChild(doc.createTextNode(text));
      dispatchInput(editable, "insertText", text);
      return true;
    } catch (_) {
      return false;
    }
  };

  const findSendButton = target => {
    const element =
      target instanceof win.Element ? target : target?.parentElement || null;
    const button = element?.closest?.("button,[role='button']");
    if (!button || button.disabled || button.getAttribute("aria-disabled") === "true") {
      return null;
    }

    const rootElement = button.closest(COMPOSER_ROOT_SELECTOR);
    if (!rootElement) {
      return null;
    }

    const label = [
      button.getAttribute("aria-label"),
      button.getAttribute("title"),
      button.getAttribute("data-testid"),
      button.textContent,
      button.getAttribute("type"),
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();

    if (label.includes("stop") || label.includes("voice")) {
      return null;
    }

    if (
      label.includes("send") ||
      label.includes("submit") ||
      button.getAttribute("type") === "submit"
    ) {
      return button;
    }

    return null;
  };

  const stampComposer = button => {
    if (!isEnabled()) {
      return false;
    }

    const rootElement = button?.closest?.(COMPOSER_ROOT_SELECTOR);
    const editable = activeComposerEditable(rootElement);
    if (!editable || !editableText(editable).trim()) {
      return false;
    }

    return appendText(editable, timestampText());
  };

  const handleSendClick = event => {
    if (forwardingClick) {
      return;
    }

    const button = findSendButton(event.target);
    if (!button || !stampComposer(button)) {
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();

    win.setTimeout(() => {
      forwardingClick = true;
      try {
        button.click();
      } finally {
        win.setTimeout(() => {
          forwardingClick = false;
        }, 0);
      }
    }, 80);
  };

  doc.addEventListener("click", handleSendClick, listenerOptions);
})(typeof globalThis !== "undefined" ? globalThis : this);
