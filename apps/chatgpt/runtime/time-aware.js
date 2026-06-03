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
  const passiveCaptureOptions = { capture: true, passive: true };
  let forwardingClick = false;
  let forwardingSubmit = false;
  let lastStamp = null;
  const RECENT_STAMP_MS = 1200;
  const TIMESTAMP_PATTERN = /---\s*Timestamp:\s+[A-Z][a-z]{2},/;

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

  const activeComposerEditable = scope => {
    if (isComposerEditable(doc.activeElement)) {
      return editableElement(doc.activeElement);
    }

    const rootElement = scope?.querySelectorAll ? scope : doc;
    const editables = Array.from(rootElement.querySelectorAll(COMPOSER_SELECTOR));
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
        new Intl.DateTimeFormat("en-US", { timeZone: override }).format(new Date());
        return override;
      } catch (_) {}
    }

    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone || "";
    } catch (_) {
      return "";
    }
  };

  const timestampLine = () => {
    const now = new Date();
    const timeZone = resolvedTimeZone();
    let parts = {};

    try {
      parts = Object.fromEntries(
        new Intl.DateTimeFormat("en-US", {
          weekday: "short",
          month: "short",
          day: "2-digit",
          year: "numeric",
          hour: "2-digit",
          minute: "2-digit",
          hour12: true,
          timeZone: timeZone || undefined,
        })
          .formatToParts(now)
          .map(part => [part.type, part.value])
      );
    } catch (_) {
      return `Timestamp: ${now.toString()}${timeZone ? ` ${timeZone}` : ""}`;
    }

    const zoneLabel = timeZone || "Local";
    return `Timestamp: ${parts.weekday}, ${parts.month} ${parts.day}, ${parts.year} at ${parts.hour}:${parts.minute} ${parts.dayPeriod} ${zoneLabel}`;
  };

  const timestampText = () => `\n\n---\n${timestampLine()}`;

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

  const placeCaretAfter = node => {
    const selection = doc.getSelection?.();
    if (!selection) {
      return;
    }

    const range = doc.createRange();
    range.setStartAfter(node);
    range.setEndAfter(node);
    selection.removeAllRanges();
    selection.addRange(range);
  };

  const appendTextNodes = (editable, text) => {
    const selection = doc.getSelection?.();
    if (!selection || selection.rangeCount === 0) {
      return false;
    }

    const range = selection.getRangeAt(0);
    if (!editable.contains(range.commonAncestorContainer)) {
      return false;
    }

    const fragment = doc.createDocumentFragment();
    let lastNode = null;
    const lines = text.split("\n");
    for (let index = 0; index < lines.length; index++) {
      if (lines[index]) {
        lastNode = doc.createTextNode(lines[index]);
        fragment.appendChild(lastNode);
      }

      if (index < lines.length - 1) {
        lastNode = doc.createElement("br");
        fragment.appendChild(lastNode);
      }
    }

    range.deleteContents();
    range.insertNode(fragment);
    if (lastNode) {
      placeCaretAfter(lastNode);
    }
    dispatchInput(editable, "insertText", text);
    return true;
  };

  const insertEditorLineBreak = editable => {
    try {
      if (doc.execCommand?.("insertLineBreak")) {
        dispatchInput(editable, "insertLineBreak", "\n");
        return true;
      }
    } catch (_) {}

    try {
      const selection = doc.getSelection?.();
      if (!selection || selection.rangeCount === 0) {
        return false;
      }

      const range = selection.getRangeAt(0);
      if (!editable.contains(range.commonAncestorContainer)) {
        return false;
      }

      const br = doc.createElement("br");
      range.deleteContents();
      range.insertNode(br);
      placeCaretAfter(br);
      dispatchInput(editable, "insertLineBreak", "\n");
      return true;
    } catch (_) {
      return false;
    }
  };

  const insertEditorText = (editable, text) => {
    try {
      if (doc.execCommand?.("insertText", false, text)) {
        dispatchInput(editable, "insertText", text);
        return true;
      }
    } catch (_) {}

    return appendTextNodes(editable, text);
  };

  const appendTimestampBlock = (editable, line) => {
    placeCaretAtEnd(editable);
    return (
      insertEditorLineBreak(editable) &&
      insertEditorLineBreak(editable) &&
      insertEditorText(editable, "---") &&
      insertEditorLineBreak(editable) &&
      insertEditorText(editable, line)
    );
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

    const timestampPrefix = "\n\n---\n";
    if (text.startsWith(timestampPrefix)) {
      const line = text.slice(timestampPrefix.length);
      if (appendTimestampBlock(editable, line)) {
        return true;
      }
    }

    placeCaretAtEnd(editable);
    if (appendTextNodes(editable, text)) {
      return true;
    }

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

  const buttonLabel = button =>
    [
      button.getAttribute("aria-label"),
      button.getAttribute("title"),
      button.getAttribute("data-testid"),
      button.getAttribute("type"),
      button.textContent,
    ]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();

  const composerForButton = button => {
    const rootElement = button.closest(COMPOSER_ROOT_SELECTOR);
    return activeComposerEditable(rootElement) || activeComposerEditable(doc);
  };

  const isLikelySendButton = button => {
    if (!button || button.disabled || button.getAttribute("aria-disabled") === "true") {
      return false;
    }

    const editable = composerForButton(button);
    if (!editable || !editableText(editable).trim()) {
      return false;
    }

    const label = buttonLabel(button);
    if (
      label.includes("stop") ||
      label.includes("voice") ||
      label.includes("microphone") ||
      label.includes("attach") ||
      label.includes("upload") ||
      label.includes("menu")
    ) {
      return false;
    }

    if (
      label.includes("send") ||
      label.includes("submit") ||
      label.includes("composer-submit") ||
      button.getAttribute("type") === "submit"
    ) {
      return true;
    }

    const rootElement = button.closest("form");
    const editableRect = editable.getBoundingClientRect?.();
    const buttonRect = button.getBoundingClientRect?.();
    return (
      !!rootElement &&
      !!editableRect &&
      !!buttonRect &&
      visible(button) &&
      buttonRect.left >= editableRect.left &&
      buttonRect.right >= editableRect.right - 96
    );
  };

  const findSendButton = target => {
    const element =
      target instanceof win.Element ? target : target?.parentElement || null;
    const button = element?.closest?.("button,[role='button']");
    return isLikelySendButton(button) ? button : null;
  };

  const stampComposer = editable => {
    if (!isEnabled() || !editable) {
      return { ok: false, changed: false };
    }

    const currentText = editableText(editable);
    if (!currentText.trim()) {
      return { ok: false, changed: false };
    }

    const now = win.performance.now();
    if (lastStamp?.editable === editable && now - lastStamp.at < RECENT_STAMP_MS) {
      return { ok: true, changed: false };
    }

    if (
      currentText.includes(lastStamp?.text || "\u0000") ||
      TIMESTAMP_PATTERN.test(currentText)
    ) {
      return { ok: true, changed: false };
    }

    const text = timestampText();
    if (!appendText(editable, text)) {
      return { ok: false, changed: false };
    }

    lastStamp = { editable, text, at: now };
    return { ok: true, changed: true };
  };

  const stampButtonComposer = button => stampComposer(composerForButton(button));

  const handleEarlySend = event => {
    if (forwardingClick || forwardingSubmit) {
      return;
    }

    const button = findSendButton(event.target);
    if (button) {
      stampButtonComposer(button);
    }
  };

  const handleSendClick = event => {
    if (forwardingClick) {
      return;
    }

    const button = findSendButton(event.target);
    if (!button) {
      return;
    }

    const result = stampButtonComposer(button);
    if (!result.ok || !result.changed) {
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

  const handleSubmit = event => {
    if (forwardingSubmit) {
      return;
    }

    const form = event.target;
    const editable = activeComposerEditable(form);
    const result = stampComposer(editable);
    if (!result.ok || !result.changed || typeof form?.requestSubmit !== "function") {
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();

    win.setTimeout(() => {
      forwardingSubmit = true;
      try {
        form.requestSubmit();
      } finally {
        win.setTimeout(() => {
          forwardingSubmit = false;
        }, 0);
      }
    }, 80);
  };

  doc.addEventListener("pointerdown", handleEarlySend, passiveCaptureOptions);
  doc.addEventListener("touchstart", handleEarlySend, passiveCaptureOptions);
  doc.addEventListener("mousedown", handleEarlySend, passiveCaptureOptions);
  doc.addEventListener("click", handleSendClick, listenerOptions);
  doc.addEventListener("submit", handleSubmit, listenerOptions);
})(typeof globalThis !== "undefined" ? globalThis : this);
