;(function(root) {
  "use strict";

  const win = root.window || root;
  const COMPOSER_SELECTOR =
    'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  let doc = null;
  let insertingLineBreak = false;
  let nudgingComposerInput = false;
  let composerVisibilityCheckToken = 0;
  let returnVisibilityCheckToken = 0;
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

  const dispatchTextLikeInput = element => {
    nudgingComposerInput = true;
    try {
      element.dispatchEvent(
        new win.InputEvent("input", {
          bubbles: true,
          cancelable: false,
          inputType: "insertText",
          data: "",
        })
      );
    } catch (_) {
      try {
        element.dispatchEvent(new win.Event("input", { bubbles: true }));
      } catch (_) {}
    } finally {
      nudgingComposerInput = false;
    }

    try {
      doc.dispatchEvent(new win.Event("selectionchange"));
    } catch (_) {}
  };

  const viewportBounds = () => {
    const visualViewport = win.visualViewport;
    if (visualViewport) {
      return {
        top: visualViewport.offsetTop || 0,
        bottom: (visualViewport.offsetTop || 0) + visualViewport.height,
      };
    }

    return {
      top: 0,
      bottom: win.innerHeight || doc.documentElement?.clientHeight || 0,
    };
  };

  const focusedEditableRect = editable => {
    if (!(editable instanceof win.HTMLElement)) {
      return null;
    }

    if (editable instanceof win.HTMLTextAreaElement) {
      return editable.getBoundingClientRect?.() || null;
    }

    const selection = doc.getSelection?.();
    if (selection?.rangeCount) {
      const range = selection.getRangeAt(0);
      if (editable.contains(range.commonAncestorContainer)) {
        const rects = range.getClientRects?.();
        if (rects?.length) {
          return rects[rects.length - 1];
        }

        const rect = range.getBoundingClientRect?.();
        if (rect && rect.width >= 0 && rect.height >= 0 && (rect.top || rect.bottom || rect.height)) {
          return rect;
        }
      }
    }

    return editable.getBoundingClientRect?.() || null;
  };

  const composerBelowViewport = editable => {
    if (!editable || !isComposerEditable(editable) || !visible(editable)) {
      return false;
    }

    const rect = focusedEditableRect(editable);
    const viewport = viewportBounds();
    if (!rect || viewport.bottom <= viewport.top) {
      return false;
    }

    return rect.bottom > viewport.bottom - 16;
  };

  const scheduleComposerVisibilityCheck = editable => {
    const token = ++composerVisibilityCheckToken;
    const run = () => {
      if (token !== composerVisibilityCheckToken || !editable?.isConnected) {
        return;
      }

      if (composerBelowViewport(editable)) {
        editable.scrollIntoView?.({ block: "nearest", inline: "nearest" });
      }
    };

    win.requestAnimationFrame?.(() => win.setTimeout(run, 0)) || win.setTimeout(run, 0);
  };

  const nudgeComposerAfterReturn = editable => {
    const token = ++returnVisibilityCheckToken;
    const nudge = () => {
      if (token !== returnVisibilityCheckToken || !editable?.isConnected) {
        return false;
      }

      dispatchTextLikeInput(editable);
      return true;
    };
    const run = () => {
      if (!nudge()) {
        return;
      }

      if (composerBelowViewport(editable)) {
        editable.scrollIntoView?.({ block: "nearest", inline: "nearest" });
      }
    };

    nudge();
    win.requestAnimationFrame?.(() => {
      nudge();
      win.setTimeout(run, 90);
    }) || run();
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
        nudgeComposerAfterReturn(editable);
        return true;
      }

      if (insertContentEditableLineBreak(editable)) {
        nudgeComposerAfterReturn(editable);
        return true;
      }

      if (doc.execCommand?.("insertLineBreak")) {
        dispatchInput(editable, "insertLineBreak");
        nudgeComposerAfterReturn(editable);
        return true;
      }

      if (doc.execCommand?.("insertParagraph")) {
        dispatchInput(editable, "insertLineBreak");
        nudgeComposerAfterReturn(editable);
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

    const handleComposerInput = event => {
      if (nudgingComposerInput || !isComposerEditable(event.target)) {
        return;
      }

      scheduleComposerVisibilityCheck(editableElement(event.target));
    };

    win.addEventListener("keydown", handleReturn, true);
    win.addEventListener("beforeinput", handleBeforeInput, true);
    win.addEventListener("input", handleComposerInput, true);
    win.addEventListener("submit", handleSubmit, true);
    doc.addEventListener("keydown", handleReturn, true);
    doc.addEventListener("beforeinput", handleBeforeInput, true);
    doc.addEventListener("input", handleComposerInput, true);
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
