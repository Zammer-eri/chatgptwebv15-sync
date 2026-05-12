;(function(root) {
  "use strict";

  const win = root.window || root;
  const registry = win.__reynardChatGPTShellModules || {};
  win.__reynardChatGPTShellModules = registry;

  const DEFAULT_CONFIG = { enabled: false, keep: 20 };
  const STATUS_ID = "codex-lightsession-status";
  const STATUS_STYLE_ID = "codex-lightsession-status-style";
  const HIDDEN_ROLES = new Set(["system", "tool", "thinking"]);

  const sanitizeConfig = value => {
    const keepValue = Number(value && value.keep);
    const boundedKeep = Number.isFinite(keepValue)
      ? Math.min(100, Math.max(1, Math.round(keepValue)))
      : DEFAULT_CONFIG.keep;

    return {
      enabled:
        value && typeof value.enabled === "boolean"
          ? value.enabled
          : DEFAULT_CONFIG.enabled,
      keep: boundedKeep,
    };
  };

  const getMessageRole = element => {
    const roleElement = element.matches?.("[data-message-author-role]")
      ? element
      : element.querySelector?.("[data-message-author-role]");
    const role = roleElement?.getAttribute("data-message-author-role") || "";
    if (role && !HIDDEN_ROLES.has(role)) {
      return role;
    }
    const testID = element.getAttribute?.("data-testid") || "";
    return testID.startsWith("conversation-turn-") ? "message" : "";
  };

  const ensureStatusStyle = doc => {
    if (doc.getElementById(STATUS_STYLE_ID)) {
      return;
    }
    const style = doc.createElement("style");
    style.id = STATUS_STYLE_ID;
    style.textContent = `
      #${STATUS_ID} {
        position: fixed;
        top: calc(env(safe-area-inset-top, 0px) + 12px);
        left: 16px;
        right: 16px;
        z-index: 2147483646;
        display: flex;
        justify-content: center;
        pointer-events: none;
        opacity: 0;
        transform: translateY(-6px);
        transition: opacity 160ms ease, transform 160ms ease;
      }
      #${STATUS_ID}.visible {
        opacity: 1;
        transform: translateY(0);
      }
      #${STATUS_ID} .pill {
        max-width: min(100%, 720px);
        padding: 9px 14px;
        border-radius: 12px;
        background: rgba(24, 135, 84, 0.96);
        color: #ffffff;
        font: 600 12px/1.3 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        box-shadow: 0 8px 22px rgba(0, 0, 0, 0.22);
        white-space: normal;
        text-align: center;
        overflow-wrap: anywhere;
      }
      #${STATUS_ID}[data-state="disabled"] .pill {
        background: rgba(63, 63, 70, 0.92);
        color: #f4f4f5;
      }
    `;
    (doc.head || doc.documentElement).appendChild(style);
  };

  const ensureStatusElement = doc => {
    if (!doc.body) {
      return null;
    }
    ensureStatusStyle(doc);
    let container = doc.getElementById(STATUS_ID);
    if (container) {
      return container;
    }
    container = doc.createElement("div");
    container.id = STATUS_ID;
    const pill = doc.createElement("div");
    pill.className = "pill";
    container.appendChild(pill);
    doc.body.appendChild(container);
    return container;
  };

  const showStatus = (context, text, timeoutMs, state) => {
    const container = ensureStatusElement(context.doc);
    if (!container) {
      return false;
    }
    const pill = container.firstElementChild;
    if (!pill) {
      return false;
    }
    pill.textContent = text;
    container.setAttribute("data-state", state || "active");
    container.classList.add("visible");
    if (context.shell.lightSessionStatusTimer) {
      context.win.clearTimeout(context.shell.lightSessionStatusTimer);
      context.shell.lightSessionStatusTimer = null;
    }
    if (timeoutMs > 0) {
      context.shell.lightSessionStatusTimer = context.win.setTimeout(() => {
        container.classList.remove("visible");
        context.shell.lightSessionStatusTimer = null;
      }, timeoutMs);
    }
    return true;
  };

  const hideStatus = context => {
    const container = context.doc.getElementById(STATUS_ID);
    if (!container) {
      return;
    }
    if (context.shell.lightSessionStatusTimer) {
      context.win.clearTimeout(context.shell.lightSessionStatusTimer);
      context.shell.lightSessionStatusTimer = null;
    }
    container.classList.remove("visible");
  };

  const restoreElement = element => {
    const previousDisplay = element.getAttribute("data-reynard-lightsession-display");
    if (previousDisplay && previousDisplay !== "__unset__") {
      element.style.display = previousDisplay;
    } else {
      element.style.removeProperty("display");
    }
    element.removeAttribute("data-reynard-lightsession-hidden");
    element.removeAttribute("data-reynard-lightsession-display");
  };

  const restoreDOM = doc => {
    for (const element of doc.querySelectorAll("[data-reynard-lightsession-hidden]")) {
      restoreElement(element);
    }
  };

  const collectMessages = doc => {
    const selectors = [
      'main article[data-testid^="conversation-turn-"]',
      'main [data-testid^="conversation-turn-"]',
      "main [data-message-author-role]",
      'article[data-testid^="conversation-turn-"]',
      "[data-message-author-role]",
    ];
    const messages = [];
    for (const selector of selectors) {
      for (const element of doc.querySelectorAll(selector)) {
        const root =
          element.closest('article[data-testid^="conversation-turn-"]') ||
          element.closest('[data-testid^="conversation-turn-"]') ||
          element.closest("[data-message-author-role]") ||
          element;
        if (
          !root ||
          !getMessageRole(root) ||
          root.closest("form,textarea,input,[contenteditable='true']")
        ) {
          continue;
        }
        if (messages.some(existing => existing === root || existing.contains(root))) {
          continue;
        }
        messages.push(root);
      }
    }
    messages.sort((left, right) =>
      left.compareDocumentPosition(right) & win.Node.DOCUMENT_POSITION_PRECEDING ? 1 : -1
    );
    return messages;
  };

  const countTurns = messages => {
    let total = 0;
    let previousRole = null;
    for (const message of messages) {
      const role = getMessageRole(message);
      if (role && role !== previousRole) {
        total += 1;
        previousRole = role;
      }
    }
    return total;
  };

  const applyDOM = context => {
    const config = sanitizeConfig(context.shell.lightSessionConfig || DEFAULT_CONFIG);
    if (!config.enabled) {
      restoreDOM(context.doc);
      hideStatus(context);
      context.shell.lightSessionDomSignature = "disabled";
      return;
    }

    const messages = collectMessages(context.doc);
    if (!messages.length) {
      showStatus(context, "LightSession enabled - limit " + config.keep, 2200, "active");
      return;
    }

    const keepSet = new Set();
    let keptTurns = 0;
    let lastRole = null;
    for (let index = messages.length - 1; index >= 0; index -= 1) {
      const role = getMessageRole(messages[index]);
      if (role && role !== lastRole) {
        keptTurns += 1;
        lastRole = role;
      }
      if (keptTurns > config.keep) {
        break;
      }
      keepSet.add(messages[index]);
    }

    let hiddenCount = 0;
    for (const element of messages) {
      if (keepSet.has(element)) {
        continue;
      }
      if (!element.hasAttribute("data-reynard-lightsession-display")) {
        element.setAttribute(
          "data-reynard-lightsession-display",
          element.style.display || "__unset__"
        );
      }
      element.setAttribute("data-reynard-lightsession-hidden", "true");
      element.style.setProperty("display", "none", "important");
      hiddenCount += 1;
    }

    const messageSet = new Set(messages);
    for (const element of context.doc.querySelectorAll("[data-reynard-lightsession-hidden]")) {
      if (!messageSet.has(element) || keepSet.has(element)) {
        restoreElement(element);
      }
    }

    const totalTurns = countTurns(messages);
    const shownTurns = Math.min(totalTurns, config.keep);
    const signature = ["dom", config.keep, messages.length, hiddenCount, totalTurns].join(":");
    if (signature !== context.shell.lightSessionDomSignature) {
      context.shell.lightSessionDomSignature = signature;
      showStatus(
        context,
        hiddenCount > 0
          ? "LightSession: showing " +
              shownTurns +
              "/" +
              totalTurns +
              " turn(s) - hidden " +
              hiddenCount
          : "LightSession enabled - limit " + config.keep,
        hiddenCount > 0 ? 3200 : 2200,
        "active"
      );
    }
  };

  const installDOM = context => {
    if (context.shell.lightSessionDomInstalled || !context.doc.documentElement) {
      applyDOM(context);
      return;
    }
    context.shell.lightSessionDomInstalled = true;
    let scheduled = false;
    const schedule = (delay = 250) => {
      if (scheduled) {
        return;
      }
      scheduled = true;
      context.win.setTimeout(() => {
        scheduled = false;
        applyDOM(context);
      }, delay);
    };
    const observer = new context.win.MutationObserver(() => schedule());
    observer.observe(context.doc.documentElement, { childList: true, subtree: true });
    for (const delay of [0, 500, 1500, 3000]) {
      context.win.setTimeout(() => applyDOM(context), delay);
    }
  };

  const isConversationRequest = (method, url) =>
    method === "GET" &&
    /^\/backend-api\/(conversation|shared_conversation)\/[^/]+\/?$/.test(url.pathname);

  const requestInfo = (winObject, args) => {
    const input = args[0];
    const init = args[1];
    if (winObject.Request && input instanceof winObject.Request) {
      return {
        url: new winObject.URL(input.url, winObject.location.href),
        method: (init?.method || input.method || "GET").toUpperCase(),
      };
    }
    if (winObject.URL && input instanceof winObject.URL) {
      return {
        url: new winObject.URL(input.href, winObject.location.href),
        method: (init?.method || "GET").toUpperCase(),
      };
    }
    return {
      url: new winObject.URL(String(input), winObject.location.href),
      method: (init?.method || "GET").toUpperCase(),
    };
  };

  const isJsonResponse = response =>
    (response.headers.get("content-type") || "").toLowerCase().includes("application/json");

  const modifiedResponse = (context, originalResponse, modifiedData) => {
    const headers = new context.win.Headers(originalResponse.headers);
    headers.delete("content-length");
    headers.delete("content-encoding");
    headers.set("content-type", "application/json; charset=utf-8");
    const response = new context.win.Response(JSON.stringify(modifiedData), {
      status: originalResponse.status,
      statusText: originalResponse.statusText,
      headers,
    });
    try {
      if (originalResponse.url) {
        Object.defineProperty(response, "url", { value: originalResponse.url });
      }
      if (originalResponse.type) {
        Object.defineProperty(response, "type", { value: originalResponse.type });
      }
    } catch (_) {}
    return response;
  };

  const recordTrim = (context, payload) => {
    context.diagnostics?.set(context.mode, "trimResult", payload);
    context.diagnostics?.event(context.mode, "lightsession-trim", payload);
  };

  const installFetch = context => {
    if (context.shell.lightSessionFetchPatched || typeof context.win.fetch !== "function") {
      return;
    }
    const trimmer = win.ReynardChatGPTLightSessionTrimmer;
    if (!trimmer?.trimConversation) {
      context.diagnostics?.event(context.mode, "lightsession-fetch-unavailable", {
        reason: "missing-trimmer",
      });
      return;
    }

    const nativeFetch = context.win.fetch.bind(context.win);
    context.shell.lightSessionFetchPatched = true;
    context.diagnostics?.set(context.mode, "fetchPatched", true);

    context.win.fetch = async function(...args) {
      let info;
      try {
        info = requestInfo(context.win, args);
      } catch (_) {
        return nativeFetch(...args);
      }

      if (!isConversationRequest(info.method, info.url)) {
        return nativeFetch(...args);
      }

      const sanitizedURL = context.diagnostics?.sanitizedConversationURL(info.url.href);
      if (sanitizedURL && !context.shell.firstConversationURL) {
        context.shell.firstConversationURL = sanitizedURL;
        context.diagnostics?.set(context.mode, "firstConversationURL", sanitizedURL);
      }

      const config = sanitizeConfig(context.shell.lightSessionConfig || DEFAULT_CONFIG);
      if (!config.enabled) {
        recordTrim(context, { skipped: true, skipReason: "disabled" });
        return nativeFetch(...args);
      }

      const response = await nativeFetch(...args);
      try {
        if (!isJsonResponse(response)) {
          recordTrim(context, { skipped: true, skipReason: "non-json" });
          return response;
        }

        const json = await response.clone().json().catch(() => null);
        const trimmed = trimmer.trimConversation(json, config.keep);
        recordTrim(context, {
          changed: trimmed.changed,
          visibleKept: trimmed.visibleKept,
          visibleTotal: trimmed.visibleTotal,
          skipReason: trimmed.skipReason,
          error: trimmed.error,
        });

        if (!trimmed.changed) {
          return response;
        }

        showStatus(
          context,
          "LightSession: kept " +
            trimmed.visibleKept +
            "/" +
            trimmed.visibleTotal +
            " turn(s) (limit " +
            config.keep +
            ")",
          3200,
          "active"
        );
        return modifiedResponse(context, response, trimmed.data);
      } catch (error) {
        recordTrim(context, {
          changed: false,
          visibleKept: 0,
          visibleTotal: 0,
          skipReason: null,
          error: error && error.message ? String(error.message) : String(error),
        });
        return response;
      }
    };
  };

  const updateConfig = context => {
    const previousConfig = context.shell.lightSessionConfig || null;
    const nextConfig = sanitizeConfig(
      context.hasConfigUpdate ? context.configUpdate : previousConfig || DEFAULT_CONFIG
    );
    context.shell.lightSessionConfig = nextConfig;
    context.shell.lightSessionConfigReceived =
      Boolean(context.shell.lightSessionConfigReceived) || context.hasConfigUpdate;
    context.win.__codexLightSessionConfig__ = nextConfig;
    context.win.__codexLightSessionConfigReceived__ =
      context.shell.lightSessionConfigReceived;
    context.diagnostics?.set(
      context.mode,
      "lightSessionConfigReceived",
      context.shell.lightSessionConfigReceived
    );
    if (!nextConfig.enabled) {
      restoreDOM(context.doc);
      hideStatus(context);
    }
  };

  const install = context => {
    updateConfig(context);
    const mode = context.mode;
    if (mode === "lightsession-dom" || mode === "legacy-all") {
      installDOM(context);
    }
    if (mode === "lightsession-fetch" || mode === "all") {
      installFetch(context);
    }
  };

  registry.lightSessionRuntime = {
    install,
    sanitizeConfig,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
