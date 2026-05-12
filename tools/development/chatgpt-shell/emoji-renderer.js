;(function(root) {
  "use strict";

  const win = root.window || root;
  const registry = win.__reynardChatGPTShellModules || {};
  win.__reynardChatGPTShellModules = registry;

  const EMOJI_PATTERN =
    /[\u{1f1e6}-\u{1f1ff}\u{1f300}-\u{1faff}\u{2600}-\u{27bf}]/u;
  const SKIP_PARENT_SELECTOR =
    'script,style,noscript,textarea,input,button,a,code,pre,kbd,samp,select,option,[role="button"],[contenteditable="true"],[data-reynard-emoji]';

  const splitGraphemes = text => {
    const segmenter = win.Intl?.Segmenter
      ? new win.Intl.Segmenter(undefined, { granularity: "grapheme" })
      : null;
    if (segmenter) {
      return Array.from(segmenter.segment(text), segment => segment.segment);
    }
    return Array.from(text);
  };

  const emojiCodepoint = (text, keepEmojiPresentation = false) =>
    Array.from(text)
      .map(character => character.codePointAt(0).toString(16))
      .filter(codepoint =>
        codepoint !== "fe0e" && (keepEmojiPresentation || codepoint !== "fe0f")
      )
      .join("-");

  const emojiAssetURLs = codepointValues => {
    const urls = [];
    for (const codepoint of codepointValues) {
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

  const makeEmojiImage = (doc, text) => {
    const codepoint = emojiCodepoint(text);
    const fallbackCodepoint = emojiCodepoint(text, true);
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
      } else {
        image.replaceWith(doc.createTextNode(text));
      }
    });
    image.src = sources[sourceIndex];
    return image;
  };

  const install = context => {
    const doc = context.doc;
    if (!doc?.documentElement || doc.__reynardChatGPTEmojiRendererInstalled) {
      return;
    }
    doc.__reynardChatGPTEmojiRendererInstalled = true;

    let scheduled = false;

    const shouldSkipTextNode = node => {
      const parent = node.parentElement;
      if (!parent || !parent.isConnected || parent.closest(SKIP_PARENT_SELECTOR)) {
        return true;
      }
      return !EMOJI_PATTERN.test(node.nodeValue || "");
    };

    const renderTextNode = node => {
      if (shouldSkipTextNode(node)) {
        return;
      }

      const fragment = doc.createDocumentFragment();
      for (const segment of splitGraphemes(node.nodeValue || "")) {
        fragment.appendChild(
          EMOJI_PATTERN.test(segment)
            ? makeEmojiImage(doc, segment)
            : doc.createTextNode(segment)
        );
      }
      node.parentNode?.replaceChild(fragment, node);
    };

    const renderEmojiText = () => {
      scheduled = false;
      if (!doc.body) {
        return;
      }

      const walker = doc.createTreeWalker(doc.body, win.NodeFilter.SHOW_TEXT, {
        acceptNode: node =>
          shouldSkipTextNode(node)
            ? win.NodeFilter.FILTER_REJECT
            : win.NodeFilter.FILTER_ACCEPT,
      });

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
    doc.documentElement.appendChild(style);

    const observer = new win.MutationObserver(scheduleRender);
    observer.observe(doc.documentElement, {
      childList: true,
      characterData: true,
      subtree: true,
    });
    scheduleRender();
  };

  registry.emojiRenderer = {
    install,
  };
})(typeof globalThis !== "undefined" ? globalThis : this);
