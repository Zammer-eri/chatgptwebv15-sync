;(function(root) {
  "use strict";

  const win = root.window || root;

  const CACHE_REFRESH_MODES = new Set(["all"]);
  const COMPOSER_MODES = new Set(["all"]);
  const CACHE_REFRESH_INTERVAL_MS = 5 * 60 * 1000;
  const COMPOSER_SELECTOR =
    'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  let doc = null;
  let insertingLineBreak = false;
  let selectionStabilizationTimer = 0;

  const isChatGPT = () => {
    const host = win.location?.hostname || "";
    return host === "chatgpt.com" || host.endsWith(".chatgpt.com");
  };

  const storageGet = key => {
    try {
      return win.sessionStorage?.getItem(key) || "";
    } catch (_) {
      return "";
    }
  };

  const storageSet = (key, value) => {
    try {
      win.sessionStorage?.setItem(key, value);
    } catch (_) {}
  };

  const refreshChatGPTCaches = () => {
    const now = Date.now();
    const key = "__reynardChatGPTLastCacheRefresh";
    const lastRefresh = Number(storageGet(key) || 0);
    if (Number.isFinite(lastRefresh) && now - lastRefresh < CACHE_REFRESH_INTERVAL_MS) {
      return;
    }
    storageSet(key, String(now));

    try {
      win.navigator?.serviceWorker
        ?.getRegistrations?.()
        ?.then(registrations => {
          for (const registration of registrations) {
            registration.update?.().catch(() => {});
          }
        })
        ?.catch(() => {});
    } catch (_) {}

    try {
      win.caches
        ?.keys?.()
        ?.then(keys => Promise.all(keys.map(cacheName => win.caches.delete(cacheName))))
        ?.catch(() => {});
    } catch (_) {}
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

      if (doc.execCommand?.("insertLineBreak")) {
        dispatchInput(editable, "insertLineBreak");
        return true;
      }
    } catch (_) {
      return false;
    } finally {
      insertingLineBreak = false;
    }

    return false;
  };

  const nodeInside = (node, ancestor) => {
    if (!node || !ancestor) {
      return false;
    }
    const element =
      node.nodeType === win.Node.ELEMENT_NODE ? node : node.parentElement;
    return element === ancestor || !!ancestor.contains?.(element);
  };

  const selectionInside = editable => {
    const selection = doc.getSelection?.();
    if (!selection || selection.rangeCount === 0) {
      return false;
    }
    return nodeInside(selection.anchorNode, editable) && nodeInside(selection.focusNode, editable);
  };

  const composerSelectionSnapshot = editable => {
    if (!editable || !isComposerEditable(editable)) {
      return null;
    }

    if (editable instanceof win.HTMLTextAreaElement) {
      return {
        editable,
        kind: "textarea",
        start: editable.selectionStart ?? 0,
        end: editable.selectionEnd ?? editable.value.length,
        direction: editable.selectionDirection || "none",
      };
    }

    const selection = doc.getSelection?.();
    if (!selection || selection.rangeCount === 0 || !selectionInside(editable)) {
      return null;
    }

    return {
      editable,
      kind: "contenteditable",
      range: selection.getRangeAt(0).cloneRange(),
    };
  };

  const restoreComposerSelectionIfLost = snapshot => {
    if (!snapshot?.editable?.isConnected || !isComposerEditable(snapshot.editable)) {
      return;
    }

    if (snapshot.kind === "textarea") {
      if (doc.activeElement !== snapshot.editable) {
        return;
      }
      try {
        snapshot.editable.setSelectionRange(snapshot.start, snapshot.end, snapshot.direction);
      } catch (_) {}
      return;
    }

    if (selectionInside(snapshot.editable)) {
      return;
    }

    try {
      const selection = doc.getSelection?.();
      selection?.removeAllRanges();
      selection?.addRange(snapshot.range);
    } catch (_) {}
  };

  const scheduleSelectionStabilization = target => {
    const editable = editableElement(target) || activeComposerEditable();
    const snapshot = composerSelectionSnapshot(editable);
    if (!snapshot) {
      return;
    }

    win.clearTimeout(selectionStabilizationTimer);
    win.requestAnimationFrame?.(() => restoreComposerSelectionIfLost(snapshot));
    selectionStabilizationTimer = win.setTimeout(
      () => restoreComposerSelectionIfLost(snapshot),
      80
    );
  };

  const installComposerControls = () => {
    if (doc.__reynardChatGPTComposerControlsInstalled) {
      return;
    }
    doc.__reynardChatGPTComposerControlsInstalled = true;

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

    const handleSelectionEvent = event => {
      scheduleSelectionStabilization(event.target);
    };

    doc.addEventListener("keydown", handleReturn, true);
    doc.addEventListener("beforeinput", handleBeforeInput, true);
    doc.addEventListener("selectionchange", handleSelectionEvent, true);
    doc.addEventListener("select", handleSelectionEvent, true);
    doc.addEventListener("paste", handleSelectionEvent, true);
    doc.addEventListener("input", handleSelectionEvent, true);
    doc.addEventListener("keyup", handleSelectionEvent, true);
    doc.addEventListener("pointerup", handleSelectionEvent, true);
    doc.addEventListener("touchend", handleSelectionEvent, true);
    new win.MutationObserver(syncReturnHint).observe(doc.documentElement, {
      childList: true,
      subtree: true,
    });
    syncReturnHint();
  };

  const install = options => {
    if (!isChatGPT()) {
      return;
    }

    const mode = options?.mode || root.__REYNARD_CHATGPT_SHIM_MODE__ || "all";
    doc = win.document;
    if (!doc) {
      return;
    }

    if (CACHE_REFRESH_MODES.has(mode)) {
      refreshChatGPTCaches();
    }

    if (COMPOSER_MODES.has(mode)) {
      installComposerControls();
    }
  };

  win.ReynardChatGPTShellRuntime = {
    install,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
