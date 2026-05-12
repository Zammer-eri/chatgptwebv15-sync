;(function(root) {
  "use strict";

  const win = root.window || root;
  const registry = win.__reynardChatGPTShellModules || {};
  win.__reynardChatGPTShellModules = registry;

  const KEY = "__reynardChatGPTDiagnostics";
  const MAX_EVENTS = 80;

  const clone = value => {
    try {
      return JSON.parse(JSON.stringify(value));
    } catch (_) {
      return null;
    }
  };

  const sanitizedConversationURL = value => {
    try {
      const url = new win.URL(String(value), win.location?.href || "https://chatgpt.com");
      url.pathname = url.pathname.replace(
        /^\/backend-api\/(conversation|shared_conversation)\/[^/]+\/?$/,
        "/backend-api/$1/<id>"
      );
      url.search = "";
      url.hash = "";
      return url.pathname;
    } catch (_) {
      return null;
    }
  };

  const ensure = mode => {
    const previous = win[KEY] && typeof win[KEY] === "object" ? win[KEY] : {};
    const diagnostics = Object.assign(
      {
        version: 1,
        shimMode: mode || "unknown",
        pageRuntimeInstalled: false,
        emojiFallbackInstalled: false,
        emojiFallbackReason: null,
        lightSessionConfigReceived: false,
        fetchPatched: false,
        firstConversationURL: null,
        trimResult: null,
        events: [],
      },
      previous
    );

    diagnostics.shimMode = mode || diagnostics.shimMode || "unknown";
    if (!Array.isArray(diagnostics.events)) {
      diagnostics.events = [];
    }

    win[KEY] = diagnostics;
    win.__reynardChatGPTGetDiagnostics = () => clone(win[KEY]);
    return diagnostics;
  };

  const set = (mode, key, value) => {
    const diagnostics = ensure(mode);
    diagnostics[key] = value;
    return diagnostics;
  };

  const event = (mode, name, detail) => {
    const diagnostics = ensure(mode);
    diagnostics.events.push({
      at: Date.now(),
      name,
      detail: clone(detail) || null,
    });
    if (diagnostics.events.length > MAX_EVENTS) {
      diagnostics.events.splice(0, diagnostics.events.length - MAX_EVENTS);
    }
    return diagnostics;
  };

  registry.diagnostics = {
    ensure,
    set,
    event,
    sanitizedConversationURL,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
