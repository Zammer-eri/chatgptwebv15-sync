;(function(root) {
  "use strict";

  const win = root.window || root;
  const registry = win.__reynardChatGPTShellModules || {};
  win.__reynardChatGPTShellModules = registry;

  const LIGHTSESSION_MODES = new Set([
    "lightsession-dom",
    "lightsession-fetch",
    "all",
    "legacy-all",
  ]);
  const EMOJI_MODES = new Set(["emoji", "all", "legacy-all"]);

  const readConfigUpdate = () => {
    try {
      const raw = root.__REYNARD_CHATGPT_SHELL_CONFIG_JSON__;
      return raw ? JSON.parse(raw) : null;
    } catch (_) {
      return null;
    }
  };

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

    const shell = win.__reynardChatGPTShell || {};
    win.__reynardChatGPTShell = shell;

    const configUpdate = readConfigUpdate();
    const context = {
      win,
      doc,
      mode,
      shell,
      configUpdate,
      hasConfigUpdate:
        configUpdate !== null && typeof configUpdate === "object" && !Array.isArray(configUpdate),
      diagnostics: registry.diagnostics,
    };

    registry.diagnostics?.ensure(mode);
    registry.diagnostics?.set(mode, "pageRuntimeInstalled", true);
    registry.diagnostics?.event(mode, "page-runtime-installed", { mode });

    if (EMOJI_MODES.has(mode)) {
      registry.emojiRenderer?.install(context);
    }

    if (LIGHTSESSION_MODES.has(mode)) {
      registry.lightSessionRuntime?.install(context);
    }
  };

  win.ReynardChatGPTShellRuntime = {
    install,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
