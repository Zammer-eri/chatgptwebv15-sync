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
  const TIMESTAMP_PATTERN = /---\s*Timestamp:\s+[A-Z][a-z]{2},/;
  const SYNTHETIC_RETURN_MAX_FRAMES = 2;

  let dispatchingSyntheticReturn = false;
  let forwardingClick = false;
  let forwardingSubmit = false;
  let sendFlowActive = false;

  const nextFrame = () =>
    new Promise(resolve => {
      if (typeof win.requestAnimationFrame === "function") {
        win.requestAnimationFrame(() => resolve());
      } else {
        win.setTimeout(resolve, 0);
      }
    });

  const waitForTextChange = async (editable, beforeText, maxFrames) => {
    for (let frame = 0; frame < maxFrames; frame++) {
      await nextFrame();
      if (editableText(editable) !== beforeText) {
        return true;
      }
    }
    return false;
  };

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
    return editable?.textContent || "";
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

  const dispatchSelectionChange = () => {
    doc.dispatchEvent(new win.Event("selectionchange", { bubbles: true }));
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
    dispatchSelectionChange();
  };

  const placeCaretAfter = node => {
    const selection = doc.getSelection?.();
    if (!selection) {
      return false;
    }

    const range = doc.createRange();
    range.setStartAfter(node);
    range.setEndAfter(node);
    selection.removeAllRanges();
    selection.addRange(range);
    dispatchSelectionChange();
    return true;
  };

  const selectionInside = editable => {
    const selection = doc.getSelection?.();
    if (!selection || selection.rangeCount === 0) {
      return false;
    }
    return editable.contains(selection.getRangeAt(0).commonAncestorContainer);
  };

  const composerIsActive = editable =>
    doc.activeElement === editable ||
    editable.contains?.(doc.activeElement) ||
    selectionInside(editable);

  const focusIfNeeded = editable => {
    if (!composerIsActive(editable)) {
      editable.focus?.();
    }
  };

  const insertTextNewline = editable => {
    const selection = doc.getSelection?.();
    if (!selection || selection.rangeCount === 0) {
      return false;
    }

    const range = selection.getRangeAt(0);
    if (!editable.contains(range.commonAncestorContainer)) {
      return false;
    }

    range.deleteContents();
    const newline = doc.createTextNode("\n");
    range.insertNode(newline);
    placeCaretAfter(newline);
    dispatchInput(editable, "insertText", "\n");
    return true;
  };

  const insertFallbackLineBreak = editable => {
    if (editable instanceof win.HTMLTextAreaElement) {
      const start = editable.selectionStart ?? editable.value.length;
      const end = editable.selectionEnd ?? start;
      editable.setRangeText("\n", start, end, "end");
      dispatchInput(editable, "insertLineBreak", "\n");
      return true;
    }

    try {
      if (selectionInside(editable) && doc.execCommand?.("insertText", false, "\n")) {
        dispatchInput(editable, "insertText", "\n");
        return true;
      }
    } catch (_) {}

    if (insertTextNewline(editable)) {
      return true;
    }

    try {
      if (selectionInside(editable) && doc.execCommand?.("insertLineBreak")) {
        dispatchInput(editable, "insertLineBreak", "\n");
        return true;
      }
    } catch (_) {
      return insertTextNewline(editable);
    }

    try {
      if (selectionInside(editable) && doc.execCommand?.("insertParagraph")) {
        dispatchInput(editable, "insertLineBreak", "\n");
        return true;
      }
    } catch (_) {
      return insertTextNewline(editable);
    }

    return false;
  };

  const dispatchSyntheticShiftEnter = editable => {
    if (!editable || dispatchingSyntheticReturn) {
      return false;
    }

    dispatchingSyntheticReturn = true;
    try {
      const synthetic = new win.KeyboardEvent("keydown", {
        key: "Enter",
        code: "Enter",
        bubbles: true,
        cancelable: true,
        composed: true,
        shiftKey: true,
      });
      for (const [key, value] of [
        ["keyCode", 13],
        ["which", 13],
        ["charCode", 0],
      ]) {
        try {
          Object.defineProperty(synthetic, key, {
            configurable: true,
            get: () => value,
          });
        } catch (_) {}
      }
      editable.dispatchEvent(synthetic);
      return true;
    } catch (_) {
      return false;
    } finally {
      dispatchingSyntheticReturn = false;
    }
  };

  const insertReturnKeyLineBreak = async editable => {
    focusIfNeeded(editable);

    if (editable instanceof win.HTMLTextAreaElement) {
      return insertFallbackLineBreak(editable);
    }

    placeCaretAtEnd(editable);
    const beforeText = editableText(editable);
    if (dispatchSyntheticShiftEnter(editable)) {
      if (await waitForTextChange(editable, beforeText, SYNTHETIC_RETURN_MAX_FRAMES)) {
        return true;
      }
    }

    return insertFallbackLineBreak(editable);
  };

  const insertEditorText = (editable, text) => {
    focusIfNeeded(editable);

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
      const selection = doc.getSelection?.();
      if (!selection || selection.rangeCount === 0) {
        return false;
      }
      const range = selection.getRangeAt(0);
      if (!editable.contains(range.commonAncestorContainer)) {
        return false;
      }
      const node = doc.createTextNode(text);
      range.deleteContents();
      range.insertNode(node);
      placeCaretAfter(node);
      dispatchInput(editable, "insertText", text);
      return true;
    } catch (_) {
      return false;
    }
  };

  const appendTimestampBlock = async editable => {
    if (!(await insertReturnKeyLineBreak(editable))) {
      return false;
    }
    if (!(await insertReturnKeyLineBreak(editable))) {
      return false;
    }
    if (!insertEditorText(editable, "---")) {
      return false;
    }
    if (!(await insertReturnKeyLineBreak(editable))) {
      return false;
    }
    return insertEditorText(editable, timestampLine());
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

  const stampComposer = async editable => {
    if (!isEnabled() || !editable) {
      return false;
    }

    const currentText = editableText(editable);
    if (!currentText.trim() || TIMESTAMP_PATTERN.test(currentText)) {
      return false;
    }

    return appendTimestampBlock(editable);
  };

  const forwardClick = button => {
    forwardingClick = true;
    try {
      button.click();
    } finally {
      win.setTimeout(() => {
        forwardingClick = false;
      }, 0);
    }
  };

  const forwardSubmit = form => {
    if (typeof form?.requestSubmit !== "function") {
      return false;
    }

    forwardingSubmit = true;
    try {
      form.requestSubmit();
    } finally {
      win.setTimeout(() => {
        forwardingSubmit = false;
      }, 0);
    }
    return true;
  };

  const dismissKeyboard = editable => {
    const blurTarget = isComposerEditable(doc.activeElement)
      ? editableElement(doc.activeElement)
      : editable;

    for (const delayMs of [0, 80]) {
      win.setTimeout(() => {
        try {
          blurTarget?.blur?.();
          doc.activeElement?.blur?.();
        } catch (_) {}
      }, delayMs);
    }
  };

  const runSendFlow = async (editable, forward) => {
    if (sendFlowActive) {
      return;
    }

    sendFlowActive = true;
    try {
      if (await stampComposer(editable)) {
        await nextFrame();
      }
      forward();
      dismissKeyboard(editable);
    } finally {
      win.setTimeout(() => {
        sendFlowActive = false;
      }, 0);
    }
  };

  const handleSendClick = event => {
    if (forwardingClick || forwardingSubmit) {
      return;
    }

    const button = findSendButton(event.target);
    if (!button) {
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();
    runSendFlow(composerForButton(button), () => forwardClick(button));
  };

  const handleSubmit = event => {
    if (forwardingClick || forwardingSubmit) {
      return;
    }

    if (sendFlowActive) {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }

    const form = event.target;
    const editable = activeComposerEditable(form);
    if (!editable || !editableText(editable).trim()) {
      return;
    }

    event.preventDefault();
    event.stopImmediatePropagation();
    runSendFlow(editable, () => {
      if (!forwardSubmit(form)) {
        const button = form.querySelector?.("button[type='submit'],button,[role='button']");
        if (button) {
          forwardClick(button);
        }
      }
    });
  };

  doc.addEventListener("click", handleSendClick, listenerOptions);
  doc.addEventListener("submit", handleSubmit, listenerOptions);
})(typeof globalThis !== "undefined" ? globalThis : this);
