;(function(root) {
  "use strict";

  const win = root.window || root;
  const registry = win.__reynardChatGPTShellModules || {};
  win.__reynardChatGPTShellModules = registry;

  const EMOJI_MODES = new Set(["emoji", "all"]);

  const isChatGPT = () => {
    const host = win.location?.hostname || "";
    return host === "chatgpt.com" || host.endsWith(".chatgpt.com");
  };

  const install = options => {
    if (!isChatGPT()) {
      return;
    }

    const mode = options?.mode || root.__REYNARD_CHATGPT_SHIM_MODE__ || "all";
    const doc = win.document;
    if (!doc) {
      return;
    }

    const context = {
      win,
      doc,
      mode,
    };

    if (EMOJI_MODES.has(mode)) {
      registry.emojiRenderer?.install(context);
    }

  };

  win.ReynardChatGPTShellRuntime = {
    install,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
