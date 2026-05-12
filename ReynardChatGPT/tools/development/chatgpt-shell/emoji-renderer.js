;(function(root) {
  "use strict";

  const win = root.window || root;
  const registry = win.__reynardChatGPTShellModules || {};
  win.__reynardChatGPTShellModules = registry;

  const EMOJI_PATTERN =
    /[\u{1f1e6}-\u{1f1ff}\u{1f300}-\u{1faff}\u{2600}-\u{27bf}]/u;

  const codepoints = text =>
    Array.from(text || "")
      .map(character => character.codePointAt(0).toString(16))
      .join("-");

  const STYLE_ID = "reynard-chatgpt-native-emoji-font";

  const installNativeEmojiFontCSS = doc => {
    if (!doc?.head || doc.getElementById(STYLE_ID)) {
      return false;
    }

    const style = doc.createElement("style");
    style.id = STYLE_ID;
    style.textContent = `
      [data-message-author-role],
      article[data-testid^="conversation-turn-"],
      textarea,
      input,
      [contenteditable="true"] {
        font-family: "Apple Color Emoji", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif !important;
      }
    `;
    doc.head.appendChild(style);
    return true;
  };

  const collectSamples = doc => {
    const samples = [];
    const selector =
      'article[data-testid^="conversation-turn-"],[data-message-author-role]';
    const roots = doc.querySelectorAll(selector);
    for (const root of roots) {
      if (samples.length >= 20) {
        break;
      }
      const text = root.textContent || "";
      if (!EMOJI_PATTERN.test(text)) {
        continue;
      }
      samples.push({
        codepoints: codepoints(text.match(EMOJI_PATTERN)?.[0] || ""),
        fontFamily: win.getComputedStyle(root).fontFamily || "",
      });
    }
    return samples;
  };

  const install = context => {
    const diagnostics = registry.diagnostics;
    const mode = context.mode;
    const doc = context.doc;

    if (!doc?.documentElement) {
      return;
    }

    const cssInstalled = installNativeEmojiFontCSS(doc);
    diagnostics?.set(mode, "emojiFallbackInstalled", true);
    diagnostics?.set(mode, "emojiFallbackReason", "native-apple-color-emoji-css");
    diagnostics?.event(mode, "emoji-native-font-css", {
      installed: cssInstalled,
    });

    if (doc.__reynardChatGPTEmojiDiagnosticsInstalled) {
      return;
    }
    doc.__reynardChatGPTEmojiDiagnosticsInstalled = true;

    const scan = () => {
      installNativeEmojiFontCSS(doc);
      const samples = collectSamples(doc);
      if (samples.length) {
        diagnostics?.set(mode, "emojiSamples", samples);
      }
    };

    const observer = new win.MutationObserver(() => win.setTimeout(scan, 150));
    observer.observe(doc.documentElement, {
      childList: true,
      characterData: true,
      subtree: true,
    });
    win.setTimeout(scan, 800);
  };

  registry.emojiRenderer = {
    install,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
