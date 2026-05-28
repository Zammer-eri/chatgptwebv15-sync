;(function(root) {
  "use strict";

  const win = root.window || root;

  const CACHE_REFRESH_MODES = new Set(["chatgpt", "all"]);
  const RETURN_KEY_MODES = new Set(["chatgpt", "all"]);
  const CACHE_REFRESH_INTERVAL_MS = 5 * 60 * 1000;
  const CACHE_PURGE_VERSION = "chatgpt-v34";
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

  const persistentStorageGet = key => {
    try {
      return win.localStorage?.getItem(key) || "";
    } catch (_) {
      return storageGet(key);
    }
  };

  const persistentStorageSet = (key, value) => {
    try {
      win.localStorage?.setItem(key, value);
    } catch (_) {
      storageSet(key, value);
    }
  };

  const refreshChatGPTCaches = () => {
    const purgeKey = "__reynardChatGPTCachePurgeVersion";
    if (persistentStorageGet(purgeKey) !== CACHE_PURGE_VERSION) {
      persistentStorageSet(purgeKey, CACHE_PURGE_VERSION);
      const cacheDeletion = win.caches
        ?.keys?.()
        ?.then(keys => Promise.all(keys.map(cacheName => win.caches.delete(cacheName))))
        ?.catch(() => {});
      const serviceWorkerCleanup = win.navigator?.serviceWorker
        ?.getRegistrations?.()
        ?.then(registrations =>
          Promise.all(
            registrations.map(registration =>
              registration
                .unregister()
                .catch(() => registration.update?.().catch(() => {}))
            )
          )
        )
        ?.catch(() => {});

      Promise.all([cacheDeletion, serviceWorkerCleanup]).finally(() => {
        win.setTimeout(() => {
          try {
            win.location.replace(win.location.href);
          } catch (_) {}
        }, 250);
      });
      return;
    }

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
        event.inputType !== "insertParagraph" ||
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

    if (RETURN_KEY_MODES.has(mode)) {
      installReturnKeyControls();
    }
  };

  win.ReynardChatGPTShellRuntime = {
    install,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
