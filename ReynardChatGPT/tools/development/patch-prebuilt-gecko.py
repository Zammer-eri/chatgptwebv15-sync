#!/usr/bin/env python3

from pathlib import Path
import sys


EMOJI_RENDERER_MARKER = "installChatGPTShellEmojiRenderer"
LIGHT_SESSION_MARKER = "installChatGPTShellLightSession"


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
      'script,style,noscript,textarea,input,button,a,code,pre,kbd,samp,select,option,[role="button"],[contenteditable="true"],[data-reynard-emoji]';
    const emojiContainerSelector =
      '[data-message-author-role],[data-testid^="conversation-turn"],article,main';
    const segmenter = win.Intl?.Segmenter
      ? new win.Intl.Segmenter(undefined, { granularity: "grapheme" })
      : null;
    let renderTimer = null;

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

    const emojiAssetURL = codepoint =>
      `https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.2/assets/72x72/${codepoint}.png`;

    const emojiImage = text => {
      const codepoint = emojiCodepoint(text);
      const fallbackCodepoint = emojiCodepoint(text, true);
      if (!codepoint) {
        return doc.createTextNode(text);
      }

      const image = doc.createElement("img");
      image.setAttribute("data-reynard-emoji", "true");
      image.setAttribute("alt", text);
      image.setAttribute("draggable", "false");
      image.setAttribute("decoding", "async");
      image.src = emojiAssetURL(codepoint);
      image.style.width = "1.2em";
      image.style.height = "1.2em";
      image.style.margin = "0 .03em";
      image.style.verticalAlign = "-0.2em";
      image.style.display = "inline-block";
      image.addEventListener(
        "error",
        () => {
          if (fallbackCodepoint && fallbackCodepoint !== codepoint) {
            image.src = emojiAssetURL(fallbackCodepoint);
            image.addEventListener(
              "error",
              () => image.replaceWith(doc.createTextNode(text)),
              { once: true }
            );
            return;
          }

          image.replaceWith(doc.createTextNode(text));
        },
        { once: true }
      );
      return image;
    };

    const shouldSkipTextNode = node => {
      const parent = node.parentElement;
      if (
        !parent ||
        !parent.isConnected ||
        parent.closest(skipParentSelector) ||
        !parent.closest(emojiContainerSelector)
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
      renderTimer = null;
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
      while (nodes.length < 120) {
        const node = walker.nextNode();
        if (!node) {
          break;
        }
        nodes.push(node);
      }
      for (const node of nodes) {
        renderTextNode(node);
      }
      if (nodes.length === 120) {
        scheduleRender();
      }
    };

    const scheduleRender = () => {
      if (renderTimer) {
        win.clearTimeout(renderTimer);
      }
      renderTimer = win.setTimeout(renderEmojiText, 160);
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
    const configChanged = Boolean(
      previousConfig &&
        (previousConfig.enabled !== nextConfig.enabled ||
          previousConfig.keep !== nextConfig.keep)
    );
    win.__codexLightSessionConfig__ = nextConfig;

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

    const showStatus = (text, timeoutMs) => {
      const container = ensureStatusElement();
      const pill = container.firstElementChild;
      if (!pill) {
        return;
      }

      pill.textContent = text;
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

    if (!isChatGPT()) {
      return;
    }

    if (
      win.__codexLightSessionConfig__.enabled &&
      (!doc.__reynardChatGPTLightSessionStatusShown || (configUpdate && configChanged))
    ) {
      doc.__reynardChatGPTLightSessionStatusShown = true;
      showStatus(
        "LightSession enabled - limit " + win.__codexLightSessionConfig__.keep,
        2200
      );
    } else if (!win.__codexLightSessionConfig__.enabled && configUpdate && configChanged) {
      doc.__reynardChatGPTLightSessionStatusShown = false;
      showStatus("LightSession disabled", 1800);
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

      if (visibleTotal <= effectiveLimit) {
        return {
          unchanged: true,
          visibleKept: visibleTotal,
          visibleTotal,
        };
      }

      const kept = path.slice(cutIndex).filter(nodeId => Boolean(mapping[nodeId]));

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
      const current = currentNode;
      if (!root || !current) {
        return null;
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

        if (trimmed.unchanged) {
          showStatus(
            "LightSession: kept " + trimmed.visibleKept + "/" + trimmed.visibleTotal +
              " turn(s) (limit " + config.keep + ")",
            2600
          );
          return response;
        }

        const removed = Math.max(0, trimmed.visibleTotal - trimmed.visibleKept);
        const removedPercent = trimmed.visibleTotal > 0
          ? Math.round((removed / trimmed.visibleTotal) * 100)
          : 0;
        showStatus(
          "LightSession: kept " + trimmed.visibleKept + "/" + trimmed.visibleTotal +
            " turn(s) (limit " + config.keep + ") - removed " + removed +
            " (~" + removedPercent + "%)",
          3400
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


def patch_geckoview_content_child(bin_dir: Path) -> None:
    path = bin_dir / "actors" / "GeckoViewContentChild.sys.mjs"
    text = path.read_text()
    if EMOJI_RENDERER_MARKER in text and LIGHT_SESSION_MARKER in text:
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
    this.installChatGPTShellEmojiRenderer();
    this.installChatGPTShellLightSession();
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
    this.installChatGPTShellEmojiRenderer();
    this.installChatGPTShellLightSession();
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
    this.installChatGPTShellEmojiRenderer();
    this.installChatGPTShellLightSession();
  }
""",
        ),
    ]

    if LIGHT_SESSION_MARKER not in text:
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
    if methods_to_insert:
        text = text.replace(marker, methods_to_insert + marker, 1)

    original_pageshow = """      case "pageshow": {
        this.receivedPageShow();
        break;
      }
"""
    patched_pageshow = """      case "pageshow": {
        this.installChatGPTShellEmojiRenderer();
        this.installChatGPTShellLightSession();
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

    original_receive = """      case "ContainsFormData": {
        return this.containsFormData();
      }
"""
    patched_receive = """      case "ChatGPTShell:UpdateLightSession": {
        this.installChatGPTShellLightSession(message.data || {});
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
        break;
"""
    if switch_anchor not in text:
        raise RuntimeError(f"Cannot find update switch hook in {path}")
    text = text.replace(switch_anchor, switch_patch, 1)

    method_anchor = "  async _hasCookieBannerRuleForBrowsingContextTree(aCallback) {\n"
    method_patch = """  async _updateLightSession(aData) {
    try {
      const actor =
        this.browser.browsingContext.currentWindowGlobal.getActor(
          "GeckoViewContent"
        );
      actor?.sendAsyncMessage("ChatGPTShell:UpdateLightSession", aData || {});
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
    patch_geckoview_content_module(bin_dir)


if __name__ == "__main__":
    main()
