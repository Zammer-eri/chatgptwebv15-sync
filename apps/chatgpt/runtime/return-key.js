;(function(root) {
  "use strict";

  const win = root.window || root;
  const doc = win.document;
  if (!doc || doc.__reynardChatGPTReturnKeyControlsInstalled) {
    return;
  }
  doc.__reynardChatGPTReturnKeyControlsInstalled = true;

  const COMPOSER_SELECTOR =
    'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  let insertingLineBreak = false;
  let allowNativeLineBreakUntil = 0;
  let suppressComposerSubmitUntil = 0;

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

  const activeComposerEditable = () => {
    if (isComposerEditable(doc.activeElement)) {
      return editableElement(doc.activeElement);
    }

    const editables = Array.from(doc.querySelectorAll(COMPOSER_SELECTOR));
    for (let index = editables.length - 1; index >= 0; index--) {
      const editable = editables[index];
      const rect = editable.getBoundingClientRect?.();
      if (isComposerEditable(editable) && rect?.width > 0 && rect?.height > 0) {
        return editable;
      }
    }
    return null;
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

  const selectionInside = editable => {
    const selection = doc.getSelection?.();
    if (!selection || selection.rangeCount === 0) {
      return false;
    }
    return editable.contains(selection.getRangeAt(0).commonAncestorContainer);
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

  const insertLineBreak = target => {
    if (insertingLineBreak) {
      return true;
    }

    const editable = editableElement(target) || activeComposerEditable();
    if (!editable) {
      return false;
    }

    editable.focus?.();
    insertingLineBreak = true;
    try {
      if (editable instanceof win.HTMLTextAreaElement) {
        const start = editable.selectionStart ?? editable.value.length;
        const end = editable.selectionEnd ?? start;
        editable.setRangeText("\n", start, end, "end");
        dispatchInput(editable, "insertLineBreak", "\n");
        return true;
      }

      if (selectionInside(editable) && doc.execCommand?.("insertText", false, "\n")) {
        dispatchInput(editable, "insertText", "\n");
        return true;
      }

      if (insertTextNewline(editable)) {
        return true;
      }

      if (selectionInside(editable) && doc.execCommand?.("insertLineBreak")) {
        dispatchInput(editable, "insertLineBreak", "\n");
        return true;
      }

      if (selectionInside(editable) && doc.execCommand?.("insertParagraph")) {
        dispatchInput(editable, "insertLineBreak", "\n");
        return true;
      }

      return false;
    } catch (_) {
      return insertTextNewline(editable);
    } finally {
      insertingLineBreak = false;
    }
  };

  const forceReturnToLineBreak = event => {
    event.preventDefault();
    event.stopImmediatePropagation();
    suppressComposerSubmitUntil = win.performance.now() + 500;
    insertLineBreak(event.target);
  };

  const makeReturnBehaveLikeShiftEnter = event => {
    if (event.shiftKey) {
      return true;
    }

    try {
      Object.defineProperty(event, "shiftKey", {
        configurable: true,
        get: () => true,
      });
    } catch (_) {
      return false;
    }

    if (!event.shiftKey) {
      return false;
    }

    allowNativeLineBreakUntil = win.performance.now() + 500;
    suppressComposerSubmitUntil = win.performance.now() + 500;
    return true;
  };

  const handleReturn = event => {
    if (
      event.key !== "Enter" ||
      event.isComposing ||
      event.shiftKey ||
      event.metaKey ||
      event.ctrlKey ||
      event.altKey ||
      !isComposerEditable(event.target)
    ) {
      return;
    }

    if (makeReturnBehaveLikeShiftEnter(event)) {
      return;
    }

    forceReturnToLineBreak(event);
  };

  const handleBeforeInput = event => {
    if (
      win.performance.now() <= allowNativeLineBreakUntil &&
      isComposerEditable(event.target)
    ) {
      return;
    }

    if (
      insertingLineBreak ||
      (event.inputType !== "insertParagraph" &&
        event.inputType !== "insertLineBreak") ||
      !isComposerEditable(event.target)
    ) {
      return;
    }
    forceReturnToLineBreak(event);
  };

  const handleSubmit = event => {
    if (
      win.performance.now() <= suppressComposerSubmitUntil &&
      (isComposerEditable(doc.activeElement) ||
        event.target?.querySelector?.(COMPOSER_SELECTOR))
    ) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  };

  const syncReturnHint = () => {
    for (const editable of doc.querySelectorAll(COMPOSER_SELECTOR)) {
      if (isComposerEditable(editable)) {
        editable.setAttribute("enterkeyhint", "enter");
      }
    }
  };

  for (const target of [win, doc]) {
    target.addEventListener("keydown", handleReturn, true);
    target.addEventListener("keypress", handleReturn, true);
    target.addEventListener("beforeinput", handleBeforeInput, true);
    target.addEventListener("submit", handleSubmit, true);
  }

  new win.MutationObserver(syncReturnHint).observe(doc.documentElement, {
    childList: true,
    subtree: true,
  });
  syncReturnHint();
})(typeof globalThis !== "undefined" ? globalThis : this);
