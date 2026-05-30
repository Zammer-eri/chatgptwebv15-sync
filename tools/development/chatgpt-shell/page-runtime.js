;(function(root) {
  "use strict";

  const win = root.window || root;
  const COMPOSER_SELECTOR =
    'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  let doc = null;
  let insertingLineBreak = false;
  let suppressComposerSubmitUntil = 0;

  const isChatGPT = () => {
    const host = win.location?.hostname || "";
    return host === "chatgpt.com" || host.endsWith(".chatgpt.com");
  };

  const editableElement = target => {
    const element =
      target instanceof win.Element ? target : target?.parentElement || null;
    return element?.closest?.(COMPOSER_SELECTOR) || null;
  };

  const visible = element => {
    if (!element?.isConnected) {
      return false;
    }
    const rect = element.getBoundingClientRect?.();
    return !!rect && rect.width > 0 && rect.height > 0;
  };

  const isComposerEditable = target => {
    const editable = editableElement(target);
    if (!editable || editable.closest("nav,aside")) {
      return false;
    }
    return !!editable.closest(COMPOSER_ROOT_SELECTOR);
  };

  const dispatchInput = (element, inputType = "insertText", data = null) => {
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
    dispatchInput(editable, "insertLineBreak", "\n");
    return true;
  };

  const insertLineBreak = target => {
    if (insertingLineBreak) {
      return true;
    }

    const editable = editableElement(target);
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

      if (insertContentEditableLineBreak(editable)) {
        return true;
      }

      if (doc.execCommand?.("insertLineBreak")) {
        dispatchInput(editable, "insertLineBreak", "\n");
        return true;
      }

      if (doc.execCommand?.("insertParagraph")) {
        dispatchInput(editable, "insertLineBreak", "\n");
        return true;
      }

      return false;
    } finally {
      insertingLineBreak = false;
    }
  };

  const markReturnAsLineBreak = event => {
    event.preventDefault();
    suppressComposerSubmitUntil = win.performance.now() + 300;
    event.stopImmediatePropagation();
    insertLineBreak(event.target);
  };

  const installReturnKeyControls = () => {
    if (doc.__reynardChatGPTReturnKeyControlsInstalled) {
      return;
    }
    doc.__reynardChatGPTReturnKeyControlsInstalled = true;

    const syncReturnHint = () => {
      for (const editable of doc.querySelectorAll(COMPOSER_SELECTOR)) {
        if (isComposerEditable(editable)) {
          editable.setAttribute("enterkeyhint", "enter");
        }
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
      markReturnAsLineBreak(event);
    };

    const handleBeforeInput = event => {
      if (
        (event.inputType !== "insertParagraph" && event.inputType !== "insertLineBreak") ||
        insertingLineBreak ||
        !isComposerEditable(event.target)
      ) {
        return;
      }
      markReturnAsLineBreak(event);
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
    doc.addEventListener("keydown", handleReturn, true);
    doc.addEventListener("beforeinput", handleBeforeInput, true);
    doc.addEventListener("submit", handleSubmit, true);
    new win.MutationObserver(syncReturnHint).observe(doc.documentElement, {
      childList: true,
      subtree: true,
    });
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
