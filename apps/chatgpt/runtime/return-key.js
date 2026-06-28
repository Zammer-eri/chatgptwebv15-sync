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
  let dispatchingSyntheticReturn = false;
  let suppressComposerSubmitUntil = 0;
  let composerObserver = null;
  const listenerOptions = { capture: true, passive: false };
  const passiveCaptureOptions = { capture: true, passive: true };
  const timeAwareSendFlowActive = () =>
    !!(
      doc.__reynardTimeAwareSendFlowActive ||
      win.__reynardTimeAwareSendFlowActive
    );

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

  const editableText = editable => {
    if (editable instanceof win.HTMLTextAreaElement) {
      return editable.value;
    }
    return editable.textContent || "";
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

  const handleReturn = event => {
    if (
      timeAwareSendFlowActive() ||
      dispatchingSyntheticReturn ||
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

    event.preventDefault();
    event.stopImmediatePropagation();
    suppressComposerSubmitUntil = win.performance.now() + 500;

    const editable = editableElement(event.target) || activeComposerEditable();
    const beforeText = editable ? editableText(editable) : "";
    if (dispatchSyntheticShiftEnter(editable)) {
      win.setTimeout(() => {
        if (editable && editableText(editable) === beforeText) {
          insertLineBreak(editable);
        }
      }, 50);
    } else {
      insertLineBreak(editable || event.target);
    }
  };

  const handleBeforeInput = event => {
    if (timeAwareSendFlowActive() || dispatchingSyntheticReturn) {
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
    if (timeAwareSendFlowActive()) {
      return;
    }

    if (
      win.performance.now() <= suppressComposerSubmitUntil &&
      (isComposerEditable(doc.activeElement) ||
        event.target?.querySelector?.(COMPOSER_SELECTOR))
    ) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  };

  const applyComposerKeyboardAttributes = editable => {
    if (!editable || !isComposerEditable(editable)) {
      return false;
    }

    editable.setAttribute("autocomplete", "off");
    editable.setAttribute("autocorrect", "off");
    editable.setAttribute("autocapitalize", "off");
    editable.setAttribute("spellcheck", "false");
    editable.setAttribute("enterkeyhint", "enter");
    try {
      editable.spellcheck = false;
    } catch (_) {}
    return true;
  };

  const markComposerEditable = target => {
    const editable = editableElement(target);
    if (applyComposerKeyboardAttributes(editable)) {
      return;
    }

    const element = target instanceof win.Element ? target : null;
    if (!element) {
      return;
    }

    if (element.matches?.(COMPOSER_SELECTOR)) {
      applyComposerKeyboardAttributes(element);
    }

    const descendants = element.querySelectorAll?.(COMPOSER_SELECTOR) || [];
    for (const descendant of descendants) {
      applyComposerKeyboardAttributes(descendant);
    }
  };

  const markKnownComposers = () => {
    markComposerEditable(doc.activeElement);
    const editables = doc.querySelectorAll?.(COMPOSER_SELECTOR) || [];
    for (const editable of editables) {
      applyComposerKeyboardAttributes(editable);
    }
  };

  const observeComposerReplacements = () => {
    if (composerObserver || typeof win.MutationObserver !== "function") {
      return;
    }

    const rootNode = doc.documentElement || doc.body;
    if (!rootNode) {
      return;
    }

    composerObserver = new win.MutationObserver(mutations => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes || []) {
          if (node instanceof win.Element) {
            markComposerEditable(node);
          }
        }
      }
    });
    composerObserver.observe(rootNode, { childList: true, subtree: true });
  };

  for (const target of [win, doc]) {
    target.addEventListener("keydown", handleReturn, listenerOptions);
    target.addEventListener("keypress", handleReturn, listenerOptions);
    target.addEventListener("beforeinput", handleBeforeInput, listenerOptions);
    target.addEventListener("submit", handleSubmit, listenerOptions);
  }

  doc.addEventListener("focusin", event => markComposerEditable(event.target), true);
  doc.addEventListener("touchstart", event => markComposerEditable(event.target), passiveCaptureOptions);
  doc.addEventListener("pointerdown", event => markComposerEditable(event.target), passiveCaptureOptions);
  doc.addEventListener("DOMContentLoaded", () => {
    observeComposerReplacements();
    markKnownComposers();
  }, true);
  observeComposerReplacements();
  markKnownComposers();
})(typeof globalThis !== "undefined" ? globalThis : this);
