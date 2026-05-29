;(function(root) {
  "use strict";

  const win = root.window || root;
  const COMPOSER_SELECTOR =
    '#prompt-textarea,textarea,[contenteditable="true"][role="textbox"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  let doc = null;
  let insertingLineBreak = false;
  let suppressComposerSubmitUntil = 0;

  const isChatGPT = () => {
    const host = win.location?.hostname || "";
    return host === "chatgpt.com" || host.endsWith(".chatgpt.com");
  };

  const visible = element => {
    if (!element?.isConnected) {
      return false;
    }
    const rect = element.getBoundingClientRect?.();
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

  const activeComposerEditable = () => {
    if (isComposerEditable(doc.activeElement)) {
      return editableElement(doc.activeElement);
    }
    return Array.from(doc.querySelectorAll(COMPOSER_SELECTOR))
      .filter(element => isComposerEditable(element) && visible(element))
      .at(-1) || null;
  };

  const dispatchInput = (element, inputType) => {
    try {
      element.dispatchEvent(
        new win.InputEvent("input", {
          bubbles: true,
          cancelable: false,
          inputType,
          data: inputType === "insertLineBreak" ? "\n" : null,
        })
      );
    } catch (_) {
      element.dispatchEvent(new win.Event("input", { bubbles: true }));
    }
  };

  const insertContentEditableLineBreak = editable => {
    const selection = doc.getSelection?.();
    if (!selection || selection.rangeCount === 0) {
      return false;
    }

    const range = selection.getRangeAt(0);
    if (!editable.contains(range.commonAncestorContainer)) {
      return false;
    }

    range.deleteContents();

    const br = doc.createElement("br");
    range.insertNode(br);
    range.setStartAfter(br);
    range.setEndAfter(br);
    selection.removeAllRanges();
    selection.addRange(range);
    dispatchInput(editable, "insertLineBreak");
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
        dispatchInput(editable, "insertLineBreak");
        return true;
      }

      if (insertContentEditableLineBreak(editable)) {
        return true;
      }

      if (doc.execCommand?.("insertLineBreak")) {
        dispatchInput(editable, "insertLineBreak");
        return true;
      }

      if (doc.execCommand?.("insertParagraph")) {
        dispatchInput(editable, "insertLineBreak");
        return true;
      }
    } catch (_) {
      try {
        return insertContentEditableLineBreak(editable);
      } catch (_) {
        return false;
      }
    } finally {
      insertingLineBreak = false;
    }

    return false;
  };

  const installReturnKeyControls = () => {
    if (doc.__reynardChatGPTReturnKeyControlsInstalled) {
      return;
    }
    doc.__reynardChatGPTReturnKeyControlsInstalled = true;

    const syncReturnHint = target => {
      const editable = editableElement(target) || activeComposerEditable();
      if (editable && isComposerEditable(editable)) {
        editable.setAttribute("enterkeyhint", "enter");
      }
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
      event.preventDefault();
      event.stopImmediatePropagation();
      suppressComposerSubmitUntil = win.performance.now() + 300;
      insertLineBreak(event.target);
    };

    const handleBeforeInput = event => {
      if (
        (event.inputType !== "insertParagraph" && event.inputType !== "insertLineBreak") ||
        insertingLineBreak ||
        !isComposerEditable(event.target)
      ) {
        return;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      suppressComposerSubmitUntil = win.performance.now() + 300;
      insertLineBreak(event.target);
    };

    const handleSubmit = event => {
      if (
        win.performance.now() <= suppressComposerSubmitUntil &&
        (isComposerEditable(doc.activeElement) || event.target?.querySelector?.(COMPOSER_SELECTOR))
      ) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    };

    win.addEventListener("keydown", handleReturn, true);
    win.addEventListener("beforeinput", handleBeforeInput, true);
    win.addEventListener("submit", handleSubmit, true);
    win.addEventListener("focusin", event => syncReturnHint(event.target), true);
    syncReturnHint();
  };

  const install = () => {
    if (!isChatGPT()) {
      return;
    }

    doc = win.document;
    if (!doc) {
      return;
    }

    installReturnKeyControls();
  };

  win.EmbeddedGPTShellRuntime = {
    install,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
