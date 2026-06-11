;(function(root) {
  "use strict";

  const win = root.window || root;
  const doc = win.document;
  if (!doc || doc.__reynardChatGPTForegroundRecoveryInstalled) {
    return;
  }
  doc.__reynardChatGPTForegroundRecoveryInstalled = true;

  const MIN_BACKGROUND_MS = 5000;
  const PROBE_TIMEOUT_MS = 4000;
  const RETRY_DELAY_MS = 750;

  let hiddenAt = doc.hidden ? Date.now() : 0;
  let recoveryGeneration = 0;

  const delay = milliseconds =>
    new Promise(resolve => win.setTimeout(resolve, milliseconds));

  const notifyConnectionHandlers = () => {
    if (!win.navigator?.onLine) {
      return;
    }

    try {
      win.dispatchEvent(new win.Event("online"));
      win.dispatchEvent(new win.Event("focus"));
      doc.dispatchEvent(new win.Event("visibilitychange"));
    } catch (_) {}
  };

  const hasComposerDraft = () => {
    const editables = Array.from(
      doc.querySelectorAll(
        'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]'
      )
    );
    return editables.some(editable => {
      const rect = editable.getBoundingClientRect?.();
      if (!rect || rect.width <= 0 || rect.height <= 0) {
        return false;
      }
      const text =
        editable instanceof win.HTMLTextAreaElement
          ? editable.value
          : editable.textContent;
      return !!text?.trim();
    });
  };

  const probeNetwork = async generation => {
    if (
      generation !== recoveryGeneration ||
      doc.hidden ||
      !win.navigator?.onLine
    ) {
      return true;
    }

    const controller =
      typeof win.AbortController === "function"
        ? new win.AbortController()
        : null;
    const timeoutID = win.setTimeout(
      () => controller?.abort(),
      PROBE_TIMEOUT_MS
    );

    try {
      await win.fetch(
        `${win.location.origin}/robots.txt?reynard_resume=${Date.now()}`,
        {
          cache: "no-store",
          credentials: "same-origin",
          redirect: "follow",
          signal: controller?.signal,
        }
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      win.clearTimeout(timeoutID);
    }
  };

  const recoverAfterForeground = async () => {
    const backgroundDuration = hiddenAt ? Date.now() - hiddenAt : 0;
    hiddenAt = 0;
    if (backgroundDuration < MIN_BACKGROUND_MS || doc.hidden) {
      return;
    }

    const generation = ++recoveryGeneration;
    notifyConnectionHandlers();

    if (await probeNetwork(generation)) {
      return;
    }

    await delay(RETRY_DELAY_MS);
    notifyConnectionHandlers();
    if (
      generation === recoveryGeneration &&
      !(await probeNetwork(generation)) &&
      !doc.hidden &&
      win.navigator?.onLine &&
      !hasComposerDraft()
    ) {
      win.location.reload();
    }
  };

  doc.addEventListener(
    "visibilitychange",
    () => {
      if (doc.hidden) {
        hiddenAt = Date.now();
        recoveryGeneration++;
        return;
      }
      recoverAfterForeground();
    },
    true
  );

  win.addEventListener(
    "pagehide",
    () => {
      hiddenAt = Date.now();
      recoveryGeneration++;
    },
    true
  );

  win.addEventListener(
    "pageshow",
    event => {
      if (event.persisted) {
        recoverAfterForeground();
      }
    },
    true
  );
})(typeof globalThis !== "undefined" ? globalThis : this);
