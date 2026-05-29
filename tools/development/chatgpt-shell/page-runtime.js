;(function(root) {
  "use strict";

  const win = root.window || root;
  const COMPOSER_SELECTOR =
    'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  let doc = null;
  let insertingLineBreak = false;

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

  const dispatchInput = element => {
    try {
      element.dispatchEvent(
        new win.InputEvent("input", {
          bubbles: true,
          cancelable: false,
          inputType: "insertLineBreak",
          data: "\n",
        })
      );
    } catch (_) {
      element.dispatchEvent(new win.Event("input", { bubbles: true }));
    }
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
        dispatchInput(editable);
        return true;
      }

      if (doc.execCommand?.("insertLineBreak")) {
        dispatchInput(editable);
        return true;
      }
    } catch (_) {
      return false;
    } finally {
      insertingLineBreak = false;
    }

    return false;
  };

  const installComposerControls = () => {
    if (doc.__embeddedGPTComposerReturnInstalled) {
      return;
    }
    doc.__embeddedGPTComposerReturnInstalled = true;

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
      insertLineBreak(event.target);
    };

    const handleBeforeInput = event => {
      if (
        event.inputType !== "insertParagraph" ||
        insertingLineBreak ||
        !isComposerEditable(event.target)
      ) {
        return;
      }
      event.preventDefault();
      event.stopImmediatePropagation();
      insertLineBreak(event.target);
    };

    doc.addEventListener("keydown", handleReturn, true);
    doc.addEventListener("beforeinput", handleBeforeInput, true);
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
    installComposerControls();
  };

  win.EmbeddedGPTShellRuntime = {
    install,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
