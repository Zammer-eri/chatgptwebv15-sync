;(function(root) {
  "use strict";

  const win = root.window || root;
  const COMPOSER_SELECTOR =
    'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  const COMPOSER_HOST_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"]';
  const KEYBOARD_MARGIN = 12;
  let doc = null;
  let insertingLineBreak = false;
  let suppressComposerSubmitUntil = 0;
  let keyboardHeight = 0;
  let keyboardAnimationDuration = 0;
  let keyboardAnimatingUntil = 0;
  let keyboardAdjustmentToken = 0;
  let adjustedComposerHost = null;
  let adjustedComposerHostStyle = null;

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

  const activeComposerEditable = () => {
    if (isComposerEditable(doc.activeElement)) {
      return editableElement(doc.activeElement);
    }

    return (
      Array.from(doc.querySelectorAll(COMPOSER_SELECTOR))
        .filter(element => isComposerEditable(element) && visible(element))
        .at(-1) || null
    );
  };

  const viewportBounds = () => {
    const visualViewport = win.visualViewport;
    if (visualViewport) {
      return {
        top: visualViewport.offsetTop || 0,
        bottom: (visualViewport.offsetTop || 0) + visualViewport.height,
        height: visualViewport.height,
      };
    }

    const height = win.innerHeight || doc.documentElement?.clientHeight || 0;
    return { top: 0, bottom: height, height };
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
        if (rect && (rect.top || rect.bottom || rect.height)) {
          return rect;
        }
      }
    }

    return editable.getBoundingClientRect?.() || null;
  };

  const composerHost = editable => {
    const firstHost =
      editable.closest("form") ||
      editable.closest(COMPOSER_HOST_SELECTOR) ||
      editable.parentElement;
    if (!firstHost || firstHost === doc.body || firstHost === doc.documentElement) {
      return editable;
    }

    let host = firstHost;
    let parent = host.parentElement;
    const viewportHeight = win.innerHeight || doc.documentElement?.clientHeight || 0;
    while (parent && parent !== doc.body && parent !== doc.documentElement) {
      const hostRect = host.getBoundingClientRect?.();
      const parentRect = parent.getBoundingClientRect?.();
      if (!hostRect || !parentRect || parentRect.height <= 0) {
        break;
      }

      const className =
        typeof parent.className === "string" ? parent.className : "";
      const dataTestId = parent.getAttribute?.("data-testid") || "";
      const looksComposerOwned = /composer/i.test(`${className} ${dataTestId}`);
      const position = win.getComputedStyle?.(parent)?.position || "";
      const positioned = position === "fixed" || position === "sticky";
      const nearSameBottom = Math.abs(parentRect.bottom - hostRect.bottom) <= 80;
      const reasonableHeight =
        !viewportHeight || parentRect.height <= viewportHeight * 0.55;

      if (
        parentRect.width >= hostRect.width &&
        reasonableHeight &&
        (looksComposerOwned || positioned || nearSameBottom)
      ) {
        host = parent;
        parent = parent.parentElement;
        continue;
      }

      break;
    }

    return host;
  };

  const restoreComposerKeyboardAdjustment = () => {
    if (adjustedComposerHost && adjustedComposerHostStyle) {
      adjustedComposerHost.style.transform = adjustedComposerHostStyle.transform;
      adjustedComposerHost.style.transition = adjustedComposerHostStyle.transition;
      adjustedComposerHost.style.willChange = adjustedComposerHostStyle.willChange;
    }
    adjustedComposerHost = null;
    adjustedComposerHostStyle = null;
    doc?.documentElement?.style.removeProperty("--embedded-gpt-keyboard-inset");
  };

  const rememberComposerHostStyle = host => {
    if (adjustedComposerHost === host) {
      return;
    }

    restoreComposerKeyboardAdjustment();
    adjustedComposerHost = host;
    adjustedComposerHostStyle = {
      transform: host.style.transform || "",
      transition: host.style.transition || "",
      willChange: host.style.willChange || "",
    };
  };

  const keyboardTransition = () => {
    if (win.performance.now() > keyboardAnimatingUntil) {
      return "none";
    }

    const duration = Math.max(0.01, keyboardAnimationDuration);
    return `transform ${duration}s cubic-bezier(0.2, 0, 0, 1)`;
  };

  const ensureCaretVisible = (editable, lift, targetBottom) => {
    const rect = focusedEditableRect(editable);
    if (!rect) {
      return;
    }

    const adjustedBottom = rect.bottom - lift;
    if (adjustedBottom <= targetBottom - KEYBOARD_MARGIN) {
      return;
    }

    const overflow = adjustedBottom - targetBottom + KEYBOARD_MARGIN;
    if (editable.scrollHeight > editable.clientHeight) {
      editable.scrollTop += overflow;
      return;
    }

    editable.scrollIntoView?.({ block: "nearest", inline: "nearest" });
  };

  const applyKeyboardAdjustment = () => {
    if (!doc || keyboardHeight <= 0) {
      restoreComposerKeyboardAdjustment();
      return;
    }

    const editable = activeComposerEditable();
    if (!editable || !visible(editable)) {
      restoreComposerKeyboardAdjustment();
      return;
    }

    const host = composerHost(editable);
    const rect = host.getBoundingClientRect?.();
    const viewport = viewportBounds();
    if (!rect || viewport.bottom <= viewport.top) {
      return;
    }

    const viewportKeyboardDelta = Math.max(
      0,
      (win.innerHeight || viewport.bottom) - viewport.height
    );
    const keyboardAlreadyInViewport =
      viewportKeyboardDelta > keyboardHeight * 0.5;
    const keyboardTop = keyboardAlreadyInViewport
      ? viewport.bottom
      : viewport.bottom - keyboardHeight;
    const targetBottom = Math.max(
      viewport.top + 96,
      keyboardTop - KEYBOARD_MARGIN
    );
    const requestedLift = Math.max(0, Math.ceil(rect.bottom - targetBottom));
    const maxLiftBeforeTopClips = Math.max(
      0,
      Math.floor(rect.top - (viewport.top + KEYBOARD_MARGIN))
    );
    const lift = Math.min(requestedLift, maxLiftBeforeTopClips || requestedLift);

    rememberComposerHostStyle(host);
    doc.documentElement.style.setProperty(
      "--embedded-gpt-keyboard-inset",
      `${keyboardHeight}px`
    );

    if (lift <= 0) {
      host.style.transform = adjustedComposerHostStyle.transform;
      host.style.transition = keyboardTransition();
      host.style.willChange = adjustedComposerHostStyle.willChange;
      return;
    }

    const originalTransform = adjustedComposerHostStyle.transform;
    host.style.transform = `translate3d(0, ${-lift}px, 0)${
      originalTransform ? ` ${originalTransform}` : ""
    }`;
    host.style.transition = keyboardTransition();
    host.style.willChange = "transform";
    ensureCaretVisible(editable, lift, targetBottom);
  };

  const scheduleKeyboardAdjustment = () => {
    const token = ++keyboardAdjustmentToken;
    const run = () => {
      if (token === keyboardAdjustmentToken) {
        applyKeyboardAdjustment();
      }
    };

    run();
    win.requestAnimationFrame?.(() => {
      run();
      win.setTimeout(run, 80);
      win.setTimeout(run, 220);
    }) || win.setTimeout(run, 0);
  };

  const setKeyboardInset = message => {
    const nextHeight = Number(message?.height ?? message ?? 0);
    const nextDuration = Number(message?.duration ?? 0);
    keyboardHeight = Number.isFinite(nextHeight) ? Math.max(0, nextHeight) : 0;
    keyboardAnimationDuration =
      Number.isFinite(nextDuration) && nextDuration > 0 ? nextDuration : 0;
    keyboardAnimatingUntil =
      win.performance.now() + keyboardAnimationDuration * 1000 + 80;
    scheduleKeyboardAdjustment();
  };

  const installKeyboardAvoidance = () => {
    if (doc.__embeddedGPTKeyboardAvoidanceInstalled) {
      return;
    }
    doc.__embeddedGPTKeyboardAvoidanceInstalled = true;

    for (const eventName of ["focusin", "input", "selectionchange"]) {
      doc.addEventListener(eventName, scheduleKeyboardAdjustment, true);
    }
    win.addEventListener("resize", scheduleKeyboardAdjustment, true);
    win.visualViewport?.addEventListener?.("resize", scheduleKeyboardAdjustment, true);
    win.visualViewport?.addEventListener?.("scroll", scheduleKeyboardAdjustment, true);
    new win.MutationObserver(scheduleKeyboardAdjustment).observe(doc.documentElement, {
      childList: true,
      subtree: true,
    });
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
    installKeyboardAvoidance();
    scheduleKeyboardAdjustment();
  };

  win.EmbeddedGPTShellRuntime = {
    install,
    setKeyboardInset,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
