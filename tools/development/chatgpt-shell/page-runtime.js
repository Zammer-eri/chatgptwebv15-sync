;(function(root) {
  "use strict";

  const win = root.window || root;
  const COMPOSER_SELECTOR =
    'textarea,[contenteditable="true"][role="textbox"],[contenteditable="true"]';
  const COMPOSER_ROOT_SELECTOR =
    'form,[data-testid*="composer"],[class*="composer"],main';
  const SEND_BUTTON_SELECTOR =
    '[data-testid="send-button"],button[aria-label*="Send"],button[type="submit"]';
  const TIME_AWARE_ENABLED_KEY = "EmbeddedGPT.timeAware.enabled";
  const TIME_AWARE_TIMEZONE_KEY = "EmbeddedGPT.timeAware.timezone";
  const DEFAULT_TIMEZONE = "Europe/Paris";
  let doc = null;
  let suppressComposerSubmitUntil = 0;
  let sendingAfterTimestamp = false;
  let timeAwareEnabled = true;
  let timeAwareTimezone = DEFAULT_TIMEZONE;

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

  const normalizeTimezone = timezone => {
    const candidate = timezone || DEFAULT_TIMEZONE;
    try {
      new Intl.DateTimeFormat("en-US", { timeZone: candidate }).format(new Date());
      return candidate;
    } catch (_) {
      return DEFAULT_TIMEZONE;
    }
  };

  const loadTimeAwareSettings = () => {
    try {
      const storedEnabled = win.localStorage?.getItem(TIME_AWARE_ENABLED_KEY);
      timeAwareEnabled = storedEnabled === null ? true : storedEnabled === "true";
      timeAwareTimezone = normalizeTimezone(
        win.localStorage?.getItem(TIME_AWARE_TIMEZONE_KEY)
      );
    } catch (_) {
      timeAwareEnabled = true;
      timeAwareTimezone = DEFAULT_TIMEZONE;
    }
  };

  const saveTimeAwareSettings = settings => {
    if (typeof settings?.enabled === "boolean") {
      timeAwareEnabled = settings.enabled;
    }
    if (typeof settings?.timezone === "string") {
      timeAwareTimezone = normalizeTimezone(settings.timezone);
    }

    try {
      win.localStorage?.setItem(TIME_AWARE_ENABLED_KEY, String(timeAwareEnabled));
      win.localStorage?.setItem(TIME_AWARE_TIMEZONE_KEY, timeAwareTimezone);
    } catch (_) {}
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

  const getText = element => {
    if (!element) {
      return "";
    }
    if (typeof element.value === "string") {
      return element.value;
    }
    return (element.textContent || "").replace(/\u00a0/g, " ");
  };

  const timestampText = () => {
    const now = new Date();
    const formatter = new Intl.DateTimeFormat("en-US", {
      weekday: "short",
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: true,
      timeZone: timeAwareTimezone,
    });
    const parts = formatter.formatToParts(now).reduce((result, part) => {
      result[part.type] = part.value;
      return result;
    }, {});
    const formatted =
      `${parts.weekday}, ${parts.month} ${parts.day}, ${parts.year} ` +
      `at ${parts.hour}:${parts.minute} ${parts.dayPeriod}`;
    return `\n\n---\nTimestamp: ${formatted} ${timeAwareTimezone}`;
  };

  const focusToEnd = element => {
    element.focus?.();
    if (typeof element.selectionStart === "number" && typeof element.value === "string") {
      const end = element.value.length;
      element.setSelectionRange(end, end);
      return;
    }

    if (element.isContentEditable) {
      const selection = doc.getSelection?.();
      if (!selection) {
        return;
      }
      const range = doc.createRange();
      range.selectNodeContents(element);
      range.collapse(false);
      selection.removeAllRanges();
      selection.addRange(range);
    }
  };

  const dispatchInput = element => {
    try {
      element.dispatchEvent(new win.InputEvent("input", { bubbles: true }));
    } catch (_) {
      element.dispatchEvent(new win.Event("input", { bubbles: true }));
    }
  };

  const appendText = (element, text) => {
    focusToEnd(element);

    if (typeof element.value === "string") {
      const nextValue = element.value + text;
      const proto = Object.getPrototypeOf(element);
      const setter =
        Object.getOwnPropertyDescriptor(element, "value")?.set ||
        Object.getOwnPropertyDescriptor(proto, "value")?.set;
      if (setter) {
        setter.call(element, nextValue);
      } else {
        element.value = nextValue;
      }
      dispatchInput(element);
      return true;
    }

    try {
      if (doc.execCommand?.("insertText", false, text)) {
        dispatchInput(element);
        return true;
      }
    } catch (_) {}

    try {
      element.appendChild(doc.createTextNode(text));
      dispatchInput(element);
      return true;
    } catch (_) {
      return false;
    }
  };

  const ensureTimestamp = () => {
    if (!timeAwareEnabled) {
      return true;
    }

    const editable = activeComposerEditable();
    const text = getText(editable);
    if (!editable || !text.trim() || text.includes("Timestamp:")) {
      return true;
    }

    return appendText(editable, timestampText());
  };

  const clickSendButton = button => {
    sendingAfterTimestamp = true;
    win.setTimeout(() => {
      try {
        button.click();
      } finally {
        win.setTimeout(() => {
          sendingAfterTimestamp = false;
        }, 0);
      }
    }, 80);
  };

  const markReturnAsLineBreak = event => {
    suppressComposerSubmitUntil = win.performance.now() + 300;
    event.stopImmediatePropagation();
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

    const handleSendClick = event => {
      if (sendingAfterTimestamp || !timeAwareEnabled) {
        return;
      }

      const button = event.target?.closest?.(SEND_BUTTON_SELECTOR);
      if (!button) {
        return;
      }

      const editable = activeComposerEditable();
      const text = getText(editable);
      if (!text.trim() || text.includes("Timestamp:")) {
        return;
      }

      event.preventDefault();
      event.stopImmediatePropagation();

      if (ensureTimestamp()) {
        clickSendButton(button);
      }
    };

    win.addEventListener("keydown", handleReturn, true);
    win.addEventListener("beforeinput", handleBeforeInput, true);
    win.addEventListener("click", handleSendClick, true);
    win.addEventListener("submit", handleSubmit, true);
    doc.addEventListener("keydown", handleReturn, true);
    doc.addEventListener("beforeinput", handleBeforeInput, true);
    doc.addEventListener("click", handleSendClick, true);
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

    loadTimeAwareSettings();
    installReturnKeyControls();
  };

  win.EmbeddedGPTShellRuntime = {
    install,
    configureTimeAware: saveTimeAwareSettings,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
