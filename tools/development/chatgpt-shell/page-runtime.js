;(function(root) {
  "use strict";

  const win = root.window || root;

  const COMPOSER_SELECTOR =
    'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  const RECOVERY_PARAM = "__reynard_recovery";
  const RECOVERY_CHECK_DELAYS = [12000, 25000, 45000];
  let doc = null;
  let insertingLineBreak = false;
  let suppressComposerSubmitUntil = 0;
  let shellRecoveryInProgress = false;

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

  const visibleElementMatching = (rootElement, selector, predicate) => {
    if (!rootElement) {
      return false;
    }
    return Array.from(rootElement.querySelectorAll(selector)).some(element => {
      if (!visible(element)) {
        return false;
      }
      return predicate ? predicate(element) : true;
    });
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

  const recoveryURL = () => {
    try {
      return new URL(win.location.href);
    } catch (_) {
      return null;
    }
  };

  const hasRecoveryMarker = () => {
    const url = recoveryURL();
    return url?.searchParams.has(RECOVERY_PARAM) || false;
  };

  const reloadWithRecoveryMarker = () => {
    const url = recoveryURL();
    if (!url) {
      win.location.reload();
      return;
    }

    url.searchParams.set(RECOVERY_PARAM, String(Date.now()));
    win.location.replace(url.toString());
  };

  const clearRecoveryMarkerIfHealthy = () => {
    const url = recoveryURL();
    if (!url?.searchParams.has(RECOVERY_PARAM) || hasInitialShellSpinner()) {
      return;
    }

    url.searchParams.delete(RECOVERY_PARAM);
    win.history.replaceState(win.history.state, "", url.toString());
  };

  const hasInitialShellSpinner = () => {
    const main = doc.querySelector("main") || doc.body;
    if (!main || !activeComposerEditable()) {
      return false;
    }

    const hasConversationContent = visibleElementMatching(
      main,
      '[data-message-author-role],article,[data-testid*="conversation"],[data-testid*="message"]'
    );
    if (hasConversationContent) {
      return false;
    }

    return visibleElementMatching(
      main,
      '[class*="animate-spin"],[aria-busy="true"],[role="status"],[role="progressbar"],svg',
      element => {
        const className = String(element.getAttribute("class") || "");
        return (
          className.includes("animate-spin") ||
          element.getAttribute("aria-busy") === "true" ||
          element.getAttribute("role") === "status" ||
          element.getAttribute("role") === "progressbar"
        );
      }
    );
  };

  const deleteDatabase = name =>
    new Promise(resolve => {
      if (!name || !win.indexedDB?.deleteDatabase) {
        resolve();
        return;
      }

      try {
        const request = win.indexedDB.deleteDatabase(name);
        request.onsuccess = () => resolve();
        request.onerror = () => resolve();
        request.onblocked = () => resolve();
      } catch (_) {
        resolve();
      }
    });

  const clearChatGPTSiteState = async () => {
    try {
      win.localStorage?.clear();
    } catch (_) {}

    try {
      win.sessionStorage?.clear();
    } catch (_) {}

    try {
      if (win.navigator?.serviceWorker?.getRegistrations) {
        const registrations = await win.navigator.serviceWorker.getRegistrations();
        await Promise.all(registrations.map(registration => registration.unregister()));
      }
    } catch (_) {}

    try {
      if (win.caches?.keys) {
        const keys = await win.caches.keys();
        await Promise.all(keys.map(key => win.caches.delete(key)));
      }
    } catch (_) {}

    try {
      if (win.indexedDB?.databases) {
        const databases = await win.indexedDB.databases();
        await Promise.all(databases.map(database => deleteDatabase(database.name)));
      }
    } catch (_) {}
  };

  const recoverStuckShellIfNeeded = async () => {
    if (shellRecoveryInProgress || hasRecoveryMarker()) {
      clearRecoveryMarkerIfHealthy();
      return;
    }

    if (!hasInitialShellSpinner()) {
      return;
    }

    shellRecoveryInProgress = true;
    await clearChatGPTSiteState();
    reloadWithRecoveryMarker();
  };

  const installStuckShellRecovery = () => {
    if (doc.__reynardChatGPTStuckShellRecoveryInstalled) {
      clearRecoveryMarkerIfHealthy();
      return;
    }
    doc.__reynardChatGPTStuckShellRecoveryInstalled = true;

    for (const delay of RECOVERY_CHECK_DELAYS) {
      win.setTimeout(() => {
        recoverStuckShellIfNeeded();
      }, delay);
    }
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
    installStuckShellRecovery();
  };

  win.ReynardChatGPTShellRuntime = {
    install,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
