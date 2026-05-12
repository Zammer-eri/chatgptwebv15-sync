#!/usr/bin/env python3

import json
from pathlib import Path
import sys


EMOJI_RENDERER_MARKER = "installChatGPTShellEmojiRenderer"
LIGHT_SESSION_MARKER = "installChatGPTShellLightSession"
SHELL_RUNTIME_MARKER = "installChatGPTShellRuntime"


PAGE_WORLD_SCRIPT = r'''(() => {
  "use strict";

  const readConfigUpdate = () => {
    try {
      const raw = globalThis.__REYNARD_CHATGPT_SHELL_CONFIG_JSON__;
      return raw ? JSON.parse(raw) : null;
    } catch (_) {
      return null;
    }
  };

  const win = window;
  const doc = document;
  const host = win.location?.hostname || "";
  if (host !== "chatgpt.com" && !host.endsWith(".chatgpt.com")) {
    return;
  }

  const shell = win.__reynardChatGPTShell || {};
  win.__reynardChatGPTShell = shell;

  const DEFAULT_CONFIG = { enabled: true, keep: 20 };
  const incomingConfig = readConfigUpdate();
  const hasConfigUpdate =
    incomingConfig !== null && typeof incomingConfig === "object";

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

  const previousConfig = shell.lightSessionConfig || null;
  const nextConfig = sanitizeConfig(
    hasConfigUpdate ? incomingConfig : previousConfig || DEFAULT_CONFIG
  );
  const configChanged = Boolean(
    previousConfig &&
      (previousConfig.enabled !== nextConfig.enabled ||
        previousConfig.keep !== nextConfig.keep)
  );
  shell.lightSessionConfig = nextConfig;
  shell.lightSessionConfigReceived =
    shell.lightSessionConfigReceived || hasConfigUpdate;
  win.__codexLightSessionConfig__ = nextConfig;
  win.__codexLightSessionConfigReceived__ = shell.lightSessionConfigReceived;

  const installEmojiRenderer = () => {
    if (shell.emojiRendererInstalled || !doc.documentElement) {
      return;
    }
    shell.emojiRendererInstalled = true;

    const emojiPattern =
      /[\u{1f1e6}-\u{1f1ff}\u{1f300}-\u{1faff}\u{2600}-\u{27bf}]/u;
    const skipParentSelector =
      'script,style,noscript,textarea,input,[contenteditable="true"],[data-reynard-emoji]';
    const segmenter = win.Intl?.Segmenter
      ? new win.Intl.Segmenter(undefined, { granularity: "grapheme" })
      : null;
    let scheduled = false;

    const splitGraphemes = text => {
      if (segmenter) {
        return Array.from(segmenter.segment(text), segment => segment.segment);
      }
      return Array.from(text);
    };

    const emojiCodepoint = (text, keepEmojiPresentation = false) =>
      Array.from(text)
        .map(char => char.codePointAt(0).toString(16))
        .filter(codepoint =>
          codepoint !== "fe0e" && (keepEmojiPresentation || codepoint !== "fe0f")
        )
        .join("-");

    const emojiAssetURLs = codepoints => {
      const urls = [];
      for (const codepoint of codepoints) {
        if (!codepoint || urls.some(url => url.includes(`/${codepoint}.png`))) {
          continue;
        }
        urls.push(
          `https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/${codepoint}.png`
        );
        urls.push(
          `https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.2/assets/72x72/${codepoint}.png`
        );
        urls.push(`https://twemoji.maxcdn.com/v/latest/72x72/${codepoint}.png`);
      }
      return urls;
    };

    const emojiImage = text => {
      const codepoint = emojiCodepoint(text);
      const fallbackCodepoint = emojiCodepoint(text, true);
      if (!codepoint) {
        return doc.createTextNode(text);
      }

      const sources = emojiAssetURLs(
        [codepoint, fallbackCodepoint].filter(
          (value, index, values) => value && values.indexOf(value) === index
        )
      );
      if (!sources.length) {
        return doc.createTextNode(text);
      }

      const image = doc.createElement("img");
      image.setAttribute("data-reynard-emoji", "true");
      image.setAttribute("alt", text);
      image.setAttribute("draggable", "false");
      image.setAttribute("decoding", "async");
      image.setAttribute("referrerpolicy", "no-referrer");
      image.style.width = "1.2em";
      image.style.height = "1.2em";
      image.style.margin = "0 .03em";
      image.style.verticalAlign = "-0.2em";
      image.style.display = "inline-block";
      let sourceIndex = 0;
      image.addEventListener("error", () => {
        sourceIndex += 1;
        if (sourceIndex < sources.length) {
          image.src = sources[sourceIndex];
        }
      });
      image.src = sources[sourceIndex];
      return image;
    };

    const shouldSkipTextNode = node => {
      const parent = node.parentElement;
      if (
        !parent ||
        !parent.isConnected ||
        parent.closest(skipParentSelector)
      ) {
        return true;
      }
      return !emojiPattern.test(node.nodeValue || "");
    };

    const renderTextNode = node => {
      if (shouldSkipTextNode(node)) {
        return;
      }

      const fragment = doc.createDocumentFragment();
      for (const segment of splitGraphemes(node.nodeValue || "")) {
        fragment.appendChild(
          emojiPattern.test(segment)
            ? emojiImage(segment)
            : doc.createTextNode(segment)
        );
      }
      node.parentNode?.replaceChild(fragment, node);
    };

    const messageRootSelector =
      'article[data-testid^="conversation-turn-"],[data-message-author-role]';
    const collectMessageRoots = () => {
      const roots = [];
      for (const element of doc.querySelectorAll(messageRootSelector)) {
        const root =
          element.closest('article[data-testid^="conversation-turn-"]') ||
          element.closest("[data-message-author-role]") ||
          element;
        if (!root || roots.some(existing => existing === root || existing.contains(root))) {
          continue;
        }
        roots.push(root);
      }
      return roots;
    };

    const renderEmojiText = () => {
      scheduled = false;
      if (!doc.body) {
        scheduleRender(300);
        return;
      }

      const roots = collectMessageRoots();
      if (!roots.length) {
        scheduleRender(600);
        return;
      }
      const nodes = [];
      for (const root of roots) {
        const walker = doc.createTreeWalker(
          root,
          win.NodeFilter.SHOW_TEXT,
          {
            acceptNode: node =>
              shouldSkipTextNode(node)
                ? win.NodeFilter.FILTER_REJECT
                : win.NodeFilter.FILTER_ACCEPT,
          }
        );

        while (nodes.length < 250) {
          const node = walker.nextNode();
          if (!node) {
            break;
          }
          nodes.push(node);
        }
      }

      for (const node of nodes) {
        renderTextNode(node);
      }
      if (nodes.length === 250) {
        scheduleRender(300);
      }
    };

    const scheduleRender = (delay = 300) => {
      if (scheduled) {
        return;
      }
      scheduled = true;
      win.setTimeout(renderEmojiText, delay);
    };

    const style = doc.createElement("style");
    style.setAttribute("data-reynard-emoji", "true");
    style.textContent =
      'img[data-reynard-emoji="true"]{font-size:inherit;line-height:inherit}';
    doc.documentElement.appendChild(style);

    const observer = new win.MutationObserver(() => scheduleRender());
    observer.observe(doc.documentElement, {
      childList: true,
      characterData: true,
      subtree: true,
    });
    scheduleRender(1200);
  };

  const STATUS_ID = "codex-lightsession-status";
  const STATUS_STYLE_ID = "codex-lightsession-status-style";
  const HIDDEN_ROLES = new Set(["system", "tool", "thinking"]);

  const ensureStatusStyle = () => {
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

  const ensureStatusElement = () => {
    if (!doc.body) {
      return null;
    }

    ensureStatusStyle();

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

  const showStatus = (text, timeoutMs = 0, state = "active") => {
    const container = ensureStatusElement();
    if (!container) {
      return false;
    }
    const pill = container.firstElementChild;
    if (!pill) {
      return false;
    }

    pill.textContent = text;
    container.setAttribute("data-state", state);
    container.classList.add("visible");

    if (shell.lightSessionStatusTimer) {
      win.clearTimeout(shell.lightSessionStatusTimer);
      shell.lightSessionStatusTimer = null;
    }

    if (timeoutMs && timeoutMs > 0) {
      shell.lightSessionStatusTimer = win.setTimeout(() => {
        container.classList.remove("visible");
        shell.lightSessionStatusTimer = null;
      }, timeoutMs);
    }
    return true;
  };

  const hideStatus = () => {
    const container = doc.getElementById(STATUS_ID);
    if (!container) {
      return;
    }
    if (shell.lightSessionStatusTimer) {
      win.clearTimeout(shell.lightSessionStatusTimer);
      shell.lightSessionStatusTimer = null;
    }
    container.classList.remove("visible");
  };

  if (!nextConfig.enabled) {
    shell.lightSessionStatusShown = false;
    hideStatus();
  }

  const installLightSession = () => {
    if (!doc.documentElement) {
      return;
    }

    const restoreLightSessionElement = element => {
      const previousDisplay = element.getAttribute(
        "data-reynard-lightsession-display"
      );
      if (previousDisplay && previousDisplay !== "__unset__") {
        element.style.display = previousDisplay;
      } else {
        element.style.removeProperty("display");
      }
      element.removeAttribute("data-reynard-lightsession-hidden");
      element.removeAttribute("data-reynard-lightsession-display");
    };

    const restoreLightSessionDOM = () => {
      for (const element of doc.querySelectorAll("[data-reynard-lightsession-hidden]")) {
        restoreLightSessionElement(element);
      }
    };

    const getMessageRole = element => {
      const roleElement = element.matches("[data-message-author-role]")
        ? element
        : element.querySelector("[data-message-author-role]");
      const role = roleElement?.getAttribute("data-message-author-role") || "";
      if (role && !HIDDEN_ROLES.has(role)) {
        return role;
      }
      const testID = element.getAttribute("data-testid") || "";
      if (testID.startsWith("conversation-turn-")) {
        return "message";
      }
      return "";
    };

    const collectLightSessionMessages = () => {
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

      messages.sort((left, right) => {
        if (left === right) {
          return 0;
        }
        return left.compareDocumentPosition(right) & win.Node.DOCUMENT_POSITION_PRECEDING
          ? 1
          : -1;
      });

      return messages;
    };

    const countTurns = messages => {
      let total = 0;
      let previousRole = null;
      for (const element of messages) {
        const role = getMessageRole(element);
        if (role && role !== previousRole) {
          total += 1;
          previousRole = role;
        }
      }
      return total;
    };

    const applyLightSessionDOM = () => {
      const config = sanitizeConfig(shell.lightSessionConfig || DEFAULT_CONFIG);
      if (!config.enabled) {
        restoreLightSessionDOM();
        if (hasConfigUpdate && configChanged) {
          showStatus("LightSession disabled", 1800, "disabled");
        } else {
          hideStatus();
        }
        shell.lightSessionDomSignature = "disabled";
        return;
      }

      const messages = collectLightSessionMessages();
      if (!messages.length) {
        if (
          config.enabled &&
          (!shell.lightSessionStatusShown || (hasConfigUpdate && configChanged)) &&
          showStatus(
            "LightSession enabled - limit " + config.keep,
            2200,
            "active"
          )
        ) {
          shell.lightSessionStatusShown = true;
        }
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

      const totalTurns = countTurns(messages);
      const shownTurns = Math.min(totalTurns, config.keep);
      const messageSet = new Set(messages);
      for (const element of doc.querySelectorAll("[data-reynard-lightsession-hidden]")) {
        if (!messageSet.has(element) || keepSet.has(element)) {
          restoreLightSessionElement(element);
        }
      }

      const signature = [
        "enabled",
        config.keep,
        messages.length,
        hiddenCount,
        totalTurns,
      ].join(":");

      if (signature !== shell.lightSessionDomSignature || hasConfigUpdate) {
        shell.lightSessionDomSignature = signature;
        if (hiddenCount > 0) {
          if (showStatus(
            "LightSession: showing " +
              shownTurns +
              "/" +
              totalTurns +
              " turn(s) - hidden " +
              hiddenCount,
            3200,
            "active"
          )) {
            shell.lightSessionStatusShown = true;
          }
        } else if (!shell.lightSessionStatusShown) {
          if (showStatus(
            "LightSession enabled - limit " + config.keep,
            2200,
            "active"
          )) {
            shell.lightSessionStatusShown = true;
          }
        }
      }
    };

    if (!shell.lightSessionDomInstalled) {
      shell.lightSessionDomInstalled = true;
      let domScheduled = false;
      const scheduleLightSessionDOM = (delay = 250) => {
        if (domScheduled) {
          return;
        }
        domScheduled = true;
        win.setTimeout(() => {
          domScheduled = false;
          applyLightSessionDOM();
        }, delay);
      };
      const observer = new win.MutationObserver(() => scheduleLightSessionDOM());
      observer.observe(doc.documentElement, {
        childList: true,
        subtree: true,
      });
      for (const delay of [0, 500, 1500, 3000]) {
        win.setTimeout(() => applyLightSessionDOM(), delay);
      }
    }

    applyLightSessionDOM();
    return;

    if (shell.lightSessionFetchPatched) {
      return;
    }
    shell.lightSessionFetchPatched = true;

    const isVisibleMessage = node => {
      const role = node?.message?.author?.role;
      return Boolean(role) && !HIDDEN_ROLES.has(role);
    };

    const trimMapping = (data, limit) => {
      const mapping = data?.mapping;
      const currentNode = data?.current_node;
      if (!mapping || !currentNode || !mapping[currentNode]) {
        return null;
      }

      const path = [];
      let cursor = currentNode;
      const visited = new Set();

      while (cursor) {
        const node = mapping[cursor];
        if (!node || visited.has(cursor)) {
          break;
        }
        visited.add(cursor);
        path.push(cursor);
        cursor = node.parent || null;
      }

      path.reverse();

      let visibleTotal = 0;
      let lastVisibleRole = null;
      for (const nodeId of path) {
        const node = mapping[nodeId];
        if (node && isVisibleMessage(node)) {
          const role = node.message?.author?.role || "";
          if (role !== lastVisibleRole) {
            visibleTotal += 1;
            lastVisibleRole = role;
          }
        }
      }

      const effectiveLimit = Math.max(1, limit);
      let turnCount = 0;
      let cutIndex = 0;
      let lastRole = null;

      for (let index = path.length - 1; index >= 0; index -= 1) {
        const nodeId = path[index];
        const node = mapping[nodeId];
        if (!node || !isVisibleMessage(node)) {
          continue;
        }

        const role = node.message?.author?.role || "";
        if (role !== lastRole) {
          turnCount += 1;
          lastRole = role;
        }

        if (turnCount > effectiveLimit) {
          cutIndex = index + 1;
          break;
        }
      }

      const keptRaw = path.slice(cutIndex);
      const kept = keptRaw.filter(nodeId => {
        const node = mapping[nodeId];
        return Boolean(node) && isVisibleMessage(node);
      });

      if (!kept.length) {
        return null;
      }

      const originalRootId = path[0];
      const originalRootNode = originalRootId ? mapping[originalRootId] : null;
      const hasOriginalRoot = Boolean(
        originalRootId && originalRootNode && !isVisibleMessage(originalRootNode)
      );

      const newMapping = {};
      let visibleKept = 0;
      let previousRole = null;
      if (hasOriginalRoot) {
        newMapping[originalRootId] = Object.assign({}, originalRootNode, {
          parent: null,
          children: kept[0] ? [kept[0]] : [],
        });
      }

      for (let index = 0; index < kept.length; index += 1) {
        const nodeId = kept[index];
        const originalNode = mapping[nodeId];
        const previousId =
          index === 0 ? (hasOriginalRoot ? originalRootId : null) : kept[index - 1];
        const nextId = kept[index + 1] || null;

        if (!originalNode) {
          continue;
        }

        newMapping[nodeId] = Object.assign({}, originalNode, {
          parent: previousId || null,
          children: nextId ? [nextId] : [],
        });

        const role = originalNode.message?.author?.role || "";
        if (isVisibleMessage(originalNode) && role !== previousRole) {
          visibleKept += 1;
          previousRole = role;
        }
      }

      const root = hasOriginalRoot ? originalRootId : kept[0];
      const current = kept[kept.length - 1];
      if (!root || !current) {
        return null;
      }

      for (const [nodeId, node] of Object.entries(newMapping)) {
        if (node.parent && !newMapping[node.parent]) {
          return null;
        }
        for (const childId of node.children || []) {
          if (!newMapping[childId]) {
            return null;
          }
        }
        if (nodeId !== root && node.parent === null) {
          return null;
        }
      }

      return {
        mapping: newMapping,
        current_node: current,
        root,
        visibleKept,
        visibleTotal,
      };
    };

    const isConversationRequest = (method, url) =>
      method === "GET" &&
      /^\/backend-api\/(conversation|shared_conversation)\/[^/]+\/?$/.test(
        url.pathname
      );

    const isJsonResponse = response =>
      (response.headers.get("content-type") || "")
        .toLowerCase()
        .includes("application/json");

    const createModifiedResponse = (originalResponse, modifiedData) => {
      const headers = new Headers(originalResponse.headers);
      headers.delete("content-length");
      headers.delete("content-encoding");
      headers.set("content-type", "application/json; charset=utf-8");

      const response = new Response(JSON.stringify(modifiedData), {
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

    const nativeFetch = win.fetch.bind(win);
    let firstConversationConfigWait = true;

    win.fetch = async function(...args) {
      const [input, init] = args;
      let urlString;
      let method;

      if (typeof Request !== "undefined" && input instanceof Request) {
        urlString = input.url;
        method = (init?.method || input.method || "GET").toUpperCase();
      } else if (typeof URL !== "undefined" && input instanceof URL) {
        urlString = input.href;
        method = (init?.method || "GET").toUpperCase();
      } else {
        urlString = String(input);
        method = (init?.method || "GET").toUpperCase();
      }

      const url = new URL(urlString, win.location.href);
      if (!isConversationRequest(method, url)) {
        return nativeFetch(...args);
      }

      if (firstConversationConfigWait && !shell.lightSessionConfigReceived) {
        firstConversationConfigWait = false;
        await new Promise(resolve => win.setTimeout(resolve, 100));
      }

      const config = sanitizeConfig(shell.lightSessionConfig || DEFAULT_CONFIG);
      if (!config.enabled) {
        return nativeFetch(...args);
      }

      const response = await nativeFetch(...args);
      try {
        if (!isJsonResponse(response)) {
          return response;
        }

        const json = await response.clone().json().catch(() => null);
        if (!json || typeof json !== "object" || !json.mapping || !json.current_node) {
          return response;
        }

        const trimmed = trimMapping(json, config.keep);
        if (!trimmed) {
          return response;
        }

        const removed = Math.max(0, trimmed.visibleTotal - trimmed.visibleKept);
        if (removed <= 0) {
          showStatus(
            "LightSession: kept " +
              trimmed.visibleKept +
              "/" +
              trimmed.visibleTotal +
              " turn(s) (limit " +
              config.keep +
              ")",
            2600,
            "active"
          );
          return response;
        }

        const removedPercent =
          trimmed.visibleTotal > 0
            ? Math.round((removed / trimmed.visibleTotal) * 100)
            : 0;
        showStatus(
          "LightSession: kept " +
            trimmed.visibleKept +
            "/" +
            trimmed.visibleTotal +
            " turn(s) (limit " +
            config.keep +
            ") - removed " +
            removed +
            " (~" +
            removedPercent +
            "%)",
          3400,
          "active"
        );

        return createModifiedResponse(
          response,
          Object.assign({}, json, {
            mapping: trimmed.mapping,
            current_node: trimmed.current_node,
            root: trimmed.root,
          })
        );
      } catch (_) {
        return response;
      }
    };
  };

  installEmojiRenderer();
  installLightSession();
})();'''


EMOJI_RENDERER_METHOD = r'''  installChatGPTShellEmojiRenderer() {
    const win = this.contentWindow;
    const doc = win?.document;
    if (!win || !doc || doc.__reynardChatGPTEmojiRendererInstalled) {
      return;
    }

    try {
      Object.defineProperty(doc, "__reynardChatGPTEmojiRendererInstalled", {
        value: true,
      });
    } catch (_) {
      doc.__reynardChatGPTEmojiRendererInstalled = true;
    }

    const isChatGPT = () => {
      const host = win.location?.hostname || "";
      return host === "chatgpt.com" || host.endsWith(".chatgpt.com");
    };

    const emojiPattern =
      /[\u{1f1e6}-\u{1f1ff}\u{1f300}-\u{1faff}\u{2600}-\u{27bf}]/u;
    const skipParentSelector =
      'script,style,noscript,textarea,input,[contenteditable="true"],[data-reynard-emoji]';
    const segmenter = win.Intl?.Segmenter
      ? new win.Intl.Segmenter(undefined, { granularity: "grapheme" })
      : null;
    let scheduled = false;

    const splitGraphemes = text => {
      if (segmenter) {
        return Array.from(segmenter.segment(text), segment => segment.segment);
      }
      return Array.from(text);
    };

    const emojiCodepoint = (text, keepEmojiPresentation = false) =>
      Array.from(text)
        .map(char => char.codePointAt(0).toString(16))
        .filter(codepoint =>
          codepoint !== "fe0e" && (keepEmojiPresentation || codepoint !== "fe0f")
        )
        .join("-");

    const emojiAssetURLs = codepoints => {
      const urls = [];
      for (const codepoint of codepoints) {
        if (!codepoint || urls.some(url => url.includes(`/${codepoint}.png`))) {
          continue;
        }
        urls.push(
          `https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/72x72/${codepoint}.png`
        );
        urls.push(
          `https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.2/assets/72x72/${codepoint}.png`
        );
      }
      return urls;
    };

    const emojiImage = text => {
      const codepoint = emojiCodepoint(text);
      const fallbackCodepoint = emojiCodepoint(text, true);
      if (!codepoint) {
        return doc.createTextNode(text);
      }

      const sources = emojiAssetURLs(
        [codepoint, fallbackCodepoint].filter(
          (value, index, values) => value && values.indexOf(value) === index
        )
      );
      if (!sources.length) {
        return doc.createTextNode(text);
      }

      const image = doc.createElement("img");
      image.setAttribute("data-reynard-emoji", "true");
      image.setAttribute("alt", text);
      image.setAttribute("draggable", "false");
      image.setAttribute("decoding", "async");
      image.setAttribute("referrerpolicy", "no-referrer");
      image.style.width = "1.2em";
      image.style.height = "1.2em";
      image.style.margin = "0 .03em";
      image.style.verticalAlign = "-0.2em";
      image.style.display = "inline-block";
      let sourceIndex = 0;
      image.addEventListener(
        "error",
        () => {
          sourceIndex += 1;
          if (sourceIndex < sources.length) {
            image.src = sources[sourceIndex];
          }
        }
      );
      image.src = sources[sourceIndex];
      return image;
    };

    const shouldSkipTextNode = node => {
      const parent = node.parentElement;
      if (
        !parent ||
        !parent.isConnected ||
        parent.closest(skipParentSelector)
      ) {
        return true;
      }
      return !emojiPattern.test(node.nodeValue || "");
    };

    const renderTextNode = node => {
      if (shouldSkipTextNode(node)) {
        return;
      }

      const fragment = doc.createDocumentFragment();
      for (const segment of splitGraphemes(node.nodeValue || "")) {
        fragment.appendChild(
          emojiPattern.test(segment) ? emojiImage(segment) : doc.createTextNode(segment)
        );
      }
      node.parentNode?.replaceChild(fragment, node);
    };

    const renderEmojiText = () => {
      scheduled = false;
      if (!isChatGPT() || !doc.body) {
        return;
      }

      const walker = doc.createTreeWalker(
        doc.body,
        win.NodeFilter.SHOW_TEXT,
        {
          acceptNode: node =>
            shouldSkipTextNode(node)
              ? win.NodeFilter.FILTER_REJECT
              : win.NodeFilter.FILTER_ACCEPT,
        }
      );

      const nodes = [];
      while (nodes.length < 250) {
        const node = walker.nextNode();
        if (!node) {
          break;
        }
        nodes.push(node);
      }
      for (const node of nodes) {
        renderTextNode(node);
      }
      if (nodes.length === 250) {
        scheduleRender();
      }
    };

    const scheduleRender = () => {
      if (scheduled) {
        return;
      }
      scheduled = true;
      win.setTimeout(renderEmojiText, 80);
    };

    const style = doc.createElement("style");
    style.setAttribute("data-reynard-emoji", "true");
    style.textContent =
      'img[data-reynard-emoji="true"]{font-size:inherit;line-height:inherit}';
    doc.documentElement?.appendChild(style);

    const observer = new win.MutationObserver(scheduleRender);
    if (doc.documentElement) {
      observer.observe(doc.documentElement, {
        childList: true,
        characterData: true,
        subtree: true,
      });
    }
    scheduleRender();
  }

'''


LIGHT_SESSION_METHOD = r'''  installChatGPTShellLightSession(configUpdate = null) {
    const win = this.contentWindow;
    const doc = win?.document;
    if (!win || !doc) {
      return;
    }

    const DEFAULT_CONFIG = { enabled: true, keep: 20 };
    const HIDDEN_ROLES = new Set(["system", "tool", "thinking"]);
    const STATUS_ID = "codex-lightsession-status";
    const STATUS_STYLE_ID = "codex-lightsession-status-style";

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

    const previousConfig = win.__codexLightSessionConfig__ || null;
    const nextConfig = sanitizeConfig(configUpdate || previousConfig || DEFAULT_CONFIG);
    const hasConfigUpdate = configUpdate !== null && typeof configUpdate === "object";
    const configChanged = Boolean(
      previousConfig &&
        (previousConfig.enabled !== nextConfig.enabled ||
          previousConfig.keep !== nextConfig.keep)
    );
    win.__codexLightSessionConfig__ = nextConfig;
    if (hasConfigUpdate) {
      win.__codexLightSessionConfigReceived__ = true;
    }

    const isChatGPT = () => {
      const host = win.location?.hostname || "";
      return host === "chatgpt.com" || host.endsWith(".chatgpt.com");
    };

    const ensureStatusStyle = () => {
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

    const ensureStatusElement = () => {
      ensureStatusStyle();

      let container = doc.getElementById(STATUS_ID);
      if (container) {
        return container;
      }

      container = doc.createElement("div");
      container.id = STATUS_ID;
      const pill = doc.createElement("div");
      pill.className = "pill";
      container.appendChild(pill);
      (doc.body || doc.documentElement).appendChild(container);
      return container;
    };

    const showStatus = (text, timeoutMs = 0, state = "active") => {
      const container = ensureStatusElement();
      const pill = container.firstElementChild;
      if (!pill) {
        return;
      }

      pill.textContent = text;
      container.setAttribute("data-state", state);
      container.classList.add("visible");

      if (win.__codexLightSessionStatusTimer__) {
        win.clearTimeout(win.__codexLightSessionStatusTimer__);
        win.__codexLightSessionStatusTimer__ = null;
      }

      if (timeoutMs && timeoutMs > 0) {
        win.__codexLightSessionStatusTimer__ = win.setTimeout(() => {
          container.classList.remove("visible");
          win.__codexLightSessionStatusTimer__ = null;
        }, timeoutMs);
      }
    };

    const hideStatus = () => {
      const container = doc.getElementById(STATUS_ID);
      if (!container) {
        return;
      }
      if (win.__codexLightSessionStatusTimer__) {
        win.clearTimeout(win.__codexLightSessionStatusTimer__);
        win.__codexLightSessionStatusTimer__ = null;
      }
      container.classList.remove("visible");
    };

    if (!isChatGPT()) {
      return;
    }

    if (win.__codexLightSessionConfig__.enabled) {
      if (
        !doc.__reynardChatGPTLightSessionStatusShown ||
        (hasConfigUpdate && configChanged)
      ) {
        doc.__reynardChatGPTLightSessionStatusShown = true;
        showStatus(
          "LightSession enabled - limit " + win.__codexLightSessionConfig__.keep,
          2200,
          "active"
        );
      }
    } else {
      doc.__reynardChatGPTLightSessionStatusShown = false;
      if (hasConfigUpdate && configChanged) {
        showStatus("LightSession disabled", 1800, "disabled");
      } else {
        hideStatus();
      }
    }

    if (doc.__reynardChatGPTLightSessionInstalled) {
      return;
    }

    try {
      Object.defineProperty(doc, "__reynardChatGPTLightSessionInstalled", {
        value: true,
      });
    } catch (_) {
      doc.__reynardChatGPTLightSessionInstalled = true;
    }

    const isVisibleMessage = node => {
      const role = node?.message?.author?.role;
      return Boolean(role) && !HIDDEN_ROLES.has(role);
    };

    const trimMapping = (data, limit) => {
      const mapping = data?.mapping;
      const currentNode = data?.current_node;
      if (!mapping || !currentNode || !mapping[currentNode]) {
        return null;
      }

      const path = [];
      let cursor = currentNode;
      const visited = new Set();

      while (cursor) {
        const node = mapping[cursor];
        if (!node || visited.has(cursor)) {
          break;
        }
        visited.add(cursor);
        path.push(cursor);
        cursor = node.parent || null;
      }

      path.reverse();

      let visibleTotal = 0;
      let lastVisibleRole = null;
      for (const nodeId of path) {
        const node = mapping[nodeId];
        if (node && isVisibleMessage(node)) {
          const role = node.message?.author?.role || "";
          if (role !== lastVisibleRole) {
            visibleTotal += 1;
            lastVisibleRole = role;
          }
        }
      }

      const effectiveLimit = Math.max(1, limit);
      let turnCount = 0;
      let cutIndex = 0;
      let lastRole = null;

      for (let index = path.length - 1; index >= 0; index -= 1) {
        const nodeId = path[index];
        const node = mapping[nodeId];
        if (!node || !isVisibleMessage(node)) {
          continue;
        }

        const role = node.message?.author?.role || "";
        if (role !== lastRole) {
          turnCount += 1;
          lastRole = role;
        }

        if (turnCount > effectiveLimit) {
          cutIndex = index + 1;
          break;
        }
      }

      const keptRaw = path.slice(cutIndex);
      const kept = keptRaw.filter(nodeId => {
        const node = mapping[nodeId];
        return Boolean(node) && isVisibleMessage(node);
      });

      if (!kept.length) {
        return null;
      }

      const originalRootId = path[0];
      const originalRootNode = originalRootId ? mapping[originalRootId] : null;
      const hasOriginalRoot = Boolean(
        originalRootId && originalRootNode && !isVisibleMessage(originalRootNode)
      );

      const newMapping = {};
      let visibleKept = 0;
      let previousRole = null;
      if (hasOriginalRoot) {
        newMapping[originalRootId] = Object.assign({}, originalRootNode, {
          parent: null,
          children: kept[0] ? [kept[0]] : [],
        });
      }

      for (let index = 0; index < kept.length; index += 1) {
        const nodeId = kept[index];
        const originalNode = mapping[nodeId];
        const previousId =
          index === 0 ? (hasOriginalRoot ? originalRootId : null) : kept[index - 1];
        const nextId = kept[index + 1] || null;

        if (!originalNode) {
          continue;
        }

        newMapping[nodeId] = Object.assign({}, originalNode, {
          parent: previousId || null,
          children: nextId ? [nextId] : [],
        });

        const role = originalNode.message?.author?.role || "";
        if (isVisibleMessage(originalNode) && role !== previousRole) {
          visibleKept += 1;
          previousRole = role;
        }
      }

      const root = hasOriginalRoot ? originalRootId : kept[0];
      const current = kept[kept.length - 1];
      if (!root || !current) {
        return null;
      }

      for (const [nodeId, node] of Object.entries(newMapping)) {
        if (node.parent && !newMapping[node.parent]) {
          return null;
        }
        for (const childId of node.children || []) {
          if (!newMapping[childId]) {
            return null;
          }
        }
        if (nodeId !== root && node.parent === null) {
          return null;
        }
      }

      return {
        mapping: newMapping,
        current_node: current,
        root,
        visibleKept,
        visibleTotal,
      };
    };

    const isConversationRequest = (method, url) =>
      method === "GET" &&
      /^\/backend-api\/(conversation|shared_conversation)\/[^/]+\/?$/.test(
        url.pathname
      );

    const isJsonResponse = response =>
      (response.headers.get("content-type") || "")
        .toLowerCase()
        .includes("application/json");

    const createModifiedResponse = (originalResponse, modifiedData) => {
      const headers = new win.Headers(originalResponse.headers);
      headers.delete("content-length");
      headers.delete("content-encoding");
      headers.set("content-type", "application/json; charset=utf-8");

      const response = new win.Response(JSON.stringify(modifiedData), {
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

    const nativeFetch = win.fetch.bind(win);
    let firstConversationConfigWait = true;

    win.fetch = async function(...args) {
      const [input, init] = args;
      let urlString;
      let method;

      if (win.Request && input instanceof win.Request) {
        urlString = input.url;
        method = (init?.method || input.method || "GET").toUpperCase();
      } else if (win.URL && input instanceof win.URL) {
        urlString = input.href;
        method = (init?.method || "GET").toUpperCase();
      } else {
        urlString = String(input);
        method = (init?.method || "GET").toUpperCase();
      }

      const url = new win.URL(urlString, win.location.href);
      if (!isConversationRequest(method, url)) {
        return nativeFetch(...args);
      }

      if (firstConversationConfigWait && !win.__codexLightSessionConfigReceived__) {
        firstConversationConfigWait = false;
        await new Promise(resolve => win.setTimeout(resolve, 100));
      }

      const config = sanitizeConfig(win.__codexLightSessionConfig__ || DEFAULT_CONFIG);
      if (!config.enabled) {
        return nativeFetch(...args);
      }

      const response = await nativeFetch(...args);
      try {
        if (!isJsonResponse(response)) {
          return response;
        }

        const json = await response.clone().json().catch(() => null);
        if (!json || typeof json !== "object" || !json.mapping || !json.current_node) {
          return response;
        }

        const trimmed = trimMapping(json, config.keep);
        if (!trimmed) {
          return response;
        }

        const removed = Math.max(0, trimmed.visibleTotal - trimmed.visibleKept);
        if (removed <= 0) {
          showStatus(
            "LightSession: kept " + trimmed.visibleKept + "/" + trimmed.visibleTotal +
              " turn(s) (limit " + config.keep + ")",
            2600,
            "active"
          );
          return response;
        }

        const removedPercent = trimmed.visibleTotal > 0
          ? Math.round((removed / trimmed.visibleTotal) * 100)
          : 0;
        showStatus(
          "LightSession: kept " + trimmed.visibleKept + "/" + trimmed.visibleTotal +
            " turn(s) (limit " + config.keep + ") - removed " + removed +
            " (~" + removedPercent + "%)",
          3400,
          "active"
        );

        return createModifiedResponse(
          response,
          Object.assign({}, json, {
            mapping: trimmed.mapping,
            current_node: trimmed.current_node,
            root: trimmed.root,
          })
        );
      } catch (_) {
        return response;
      }
    };
  }

'''


SHELL_RUNTIME_METHOD = r'''  installChatGPTShellRuntime(configUpdate = null) {
    const run = update => {
      const win = this.contentWindow;
      const doc = win?.document;
      if (!win || !doc?.nodePrincipal) {
        return;
      }

      const host = win.location?.hostname || "";
      if (host !== "chatgpt.com" && !host.endsWith(".chatgpt.com")) {
        return;
      }

      if (update !== null && typeof update === "object") {
        this._chatGPTShellLastConfig = update;
      }

      try {
        const sandbox = Cu.Sandbox([doc.nodePrincipal], {
          sandboxName: "Reynard ChatGPT shell page runtime",
          sandboxPrototype: win,
          sameZoneAs: win,
          originAttributes: doc.nodePrincipal.originAttributes,
          wantXrays: false,
        });
        sandbox.__REYNARD_CHATGPT_SHELL_CONFIG_JSON__ = JSON.stringify(
          this._chatGPTShellLastConfig || null
        );
        Cu.evalInSandbox(
          __REYNARD_CHATGPT_PAGE_SCRIPT__,
          sandbox,
          null,
          "reynard-chatgpt-shell.js",
          1
        );
      } catch (error) {
        debug`Cannot install ChatGPT page runtime: ${error}`;
      }
    };

    run(configUpdate);

    const win = this.contentWindow;
    if (!win || this._chatGPTShellRuntimeHooksInstalled) {
      return;
    }

    this._chatGPTShellRuntimeHooksInstalled = true;
    const rerun = () => run(null);
    for (const eventName of ["DOMContentLoaded", "pageshow", "load"]) {
      win.addEventListener(eventName, rerun, {
        capture: true,
        mozSystemGroup: true,
      });
    }
    for (const delay of [0, 250, 1000, 2500]) {
      win.setTimeout(rerun, delay);
    }
  }

'''.replace("__REYNARD_CHATGPT_PAGE_SCRIPT__", json.dumps(PAGE_WORLD_SCRIPT))


def patch_geckoview_content_child(bin_dir: Path) -> None:
    path = bin_dir / "actors" / "GeckoViewContentChild.sys.mjs"
    text = path.read_text()
    if (
        EMOJI_RENDERER_MARKER in text
        and LIGHT_SESSION_MARKER in text
        and SHELL_RUNTIME_MARKER in text
    ):
        return

    actor_created_variants = [
        (
            """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
  }
""",
            """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
    this.installChatGPTShellRuntime();
  }
""",
        ),
        (
            """  actorCreated() {
    super.actorCreated();

    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
  }
""",
            """  actorCreated() {
    super.actorCreated();

    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
    this.installChatGPTShellRuntime();
  }
""",
        ),
        (
            """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
    this.installChatGPTShellEmojiRenderer();
    this.installChatGPTShellLightSession();
  }
""",
            """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
    this.installChatGPTShellRuntime();
  }
""",
        ),
        (
            """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
    this.installChatGPTShellEmojiRenderer();
  }
""",
            """  actorCreated() {
    this.pageShow = new Promise(resolve => {
      this.receivedPageShow = resolve;
    });
    this.installChatGPTShellRuntime();
  }
""",
        ),
    ]

    if SHELL_RUNTIME_MARKER not in text:
        for original_actor_created, patched_actor_created in actor_created_variants:
            if original_actor_created in text:
                text = text.replace(original_actor_created, patched_actor_created, 1)
                break
        else:
            raise RuntimeError(f"Cannot find actorCreated hook in {path}")

    marker = "  collectSessionState() {\n"
    if marker not in text:
        raise RuntimeError(f"Cannot find collectSessionState hook in {path}")
    methods_to_insert = ""
    if EMOJI_RENDERER_MARKER not in text:
        methods_to_insert += EMOJI_RENDERER_METHOD
    if LIGHT_SESSION_MARKER not in text:
        methods_to_insert += LIGHT_SESSION_METHOD
    if SHELL_RUNTIME_MARKER not in text:
        methods_to_insert += SHELL_RUNTIME_METHOD
    if methods_to_insert:
        text = text.replace(marker, methods_to_insert + marker, 1)

    original_pageshow = """      case "pageshow": {
        this.receivedPageShow();
        break;
      }
"""
    patched_pageshow = """      case "DOMContentLoaded": {
        this.installChatGPTShellRuntime();
        break;
      }
      case "pageshow": {
        this.installChatGPTShellRuntime();
        this.receivedPageShow();
        break;
      }
"""
    emoji_only_pageshow = """      case "pageshow": {
        this.installChatGPTShellEmojiRenderer();
        this.receivedPageShow();
        break;
      }
"""
    if original_pageshow in text:
        text = text.replace(original_pageshow, patched_pageshow, 1)
    elif emoji_only_pageshow in text:
        text = text.replace(emoji_only_pageshow, patched_pageshow, 1)
    elif '      case "DOMContentLoaded": {\n        this.installChatGPTShellRuntime();' not in text:
        raise RuntimeError(f"Cannot find pageshow hook in {path}")

    original_receive = """      case "ContainsFormData": {
        return this.containsFormData();
      }
"""
    patched_receive = """      case "ChatGPTShell:UpdateLightSession": {
        this.installChatGPTShellRuntime(message.data || {});
        break;
      }
      case "ContainsFormData": {
        return this.containsFormData();
      }
"""
    if "ChatGPTShell:UpdateLightSession" not in text:
        if original_receive not in text:
            raise RuntimeError(f"Cannot find receiveMessage hook in {path}")
        text = text.replace(original_receive, patched_receive, 1)

    path.write_text(text)


def patch_geckoview_startup(bin_dir: Path) -> None:
    path = bin_dir / "chrome" / "geckoview" / "content" / "geckoview.js"
    text = path.read_text()
    if "DOMContentLoaded: { capture: true, mozSystemGroup: true }" in text:
        return

    event_anchor = """              events: {
                mozcaretstatechanged: { capture: true, mozSystemGroup: true },
                pageshow: { mozSystemGroup: true },
              },
"""
    event_patch = """              events: {
                mozcaretstatechanged: { capture: true, mozSystemGroup: true },
                DOMContentLoaded: { capture: true, mozSystemGroup: true },
                pageshow: { mozSystemGroup: true },
              },
"""
    if event_anchor not in text:
        raise RuntimeError(f"Cannot find GeckoViewContent actor event hook in {path}")
    text = text.replace(event_anchor, event_patch, 1)
    path.write_text(text)


def patch_geckoview_content_module(bin_dir: Path) -> None:
    path = bin_dir / "modules" / "GeckoViewContent.sys.mjs"
    text = path.read_text()
    if "GeckoView:UpdateLightSession" in text:
        return

    listener_anchor = '      "GeckoView:UpdateInitData",\n'
    if listener_anchor not in text:
        raise RuntimeError(f"Cannot find listener hook in {path}")
    text = text.replace(
        listener_anchor,
        '      "GeckoView:UpdateLightSession",\n' + listener_anchor,
        1,
    )

    switch_anchor = """      case "GeckoView:UpdateInitData":
        this.sendToAllChildren(aEvent, aData);
        break;
"""
    switch_patch = """      case "GeckoView:UpdateLightSession":
        this._updateLightSession(aData);
        break;
      case "GeckoView:UpdateInitData":
        this.sendToAllChildren(aEvent, aData);
        this._updateLightSession(
          aData?.settings?.chatGPTLightSession ||
            this.settings?.chatGPTLightSession ||
            this._chatGPTShellLightSessionConfig ||
            {}
        );
        break;
"""
    if switch_anchor not in text:
        raise RuntimeError(f"Cannot find update switch hook in {path}")
    text = text.replace(switch_anchor, switch_patch, 1)

    method_anchor = "  async _hasCookieBannerRuleForBrowsingContextTree(aCallback) {\n"
    method_patch = """  async _updateLightSession(aData) {
    try {
      const nextConfig =
        aData && typeof aData === "object"
          ? aData
          : this.settings?.chatGPTLightSession ||
            this._chatGPTShellLightSessionConfig ||
            {};
      this._chatGPTShellLightSessionConfig = nextConfig;
      this.sendToAllChildren("ChatGPTShell:UpdateLightSession", nextConfig);
    } catch (error) {
      debug`Cannot update LightSession config: ${error}`;
    }
  }

"""
    if method_anchor not in text:
        raise RuntimeError(f"Cannot find LightSession method hook in {path}")
    text = text.replace(method_anchor, method_patch + method_anchor, 1)

    path.write_text(text)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-prebuilt-gecko.py <dist-bin-dir>")

    bin_dir = Path(sys.argv[1])
    patch_geckoview_content_child(bin_dir)
    patch_geckoview_startup(bin_dir)
    patch_geckoview_content_module(bin_dir)


if __name__ == "__main__":
    main()
