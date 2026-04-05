const RELEVANT_DOMAINS = [
  "chatgpt.com",
  "auth.openai.com",
  "openai.com",
  "chat.openai.com"
];

const DEFAULT_HELPER_BASE = "http://127.0.0.1:48713";
const SNAPSHOT_DEBOUNCE_MS = 1000;
let debounceTimer = null;

async function getHelperBase() {
  const stored = await chrome.storage.local.get({ helperBase: DEFAULT_HELPER_BASE });
  return stored.helperBase || DEFAULT_HELPER_BASE;
}

function isRelevantDomain(domain = "") {
  return RELEVANT_DOMAINS.some((candidate) => domain === candidate || domain.endsWith(`.${candidate}`) || domain.endsWith(candidate));
}

function normalizeCookie(cookie) {
  return {
    domain: cookie.domain,
    name: cookie.name,
    value: cookie.value,
    path: cookie.path,
    secure: cookie.secure,
    httpOnly: cookie.httpOnly,
    session: cookie.session,
    sameSite: cookie.sameSite,
    expirationDate: cookie.expirationDate ?? null
  };
}

async function fetchAllCookies() {
  const seen = new Map();

  for (const domain of RELEVANT_DOMAINS) {
    const cookies = await chrome.cookies.getAll({ domain });
    for (const cookie of cookies) {
      const key = `${cookie.domain}|${cookie.path}|${cookie.name}`;
      seen.set(key, normalizeCookie(cookie));
    }
  }

  return Array.from(seen.values());
}

async function pushSnapshot(reason) {
  const helperBase = await getHelperBase();
  const payload = {
    schema: 1,
    captured_at: new Date().toISOString(),
    reason,
    browser: "chrome",
    profile: "Default",
    cookies: await fetchAllCookies()
  };

  const response = await fetch(`${helperBase}/v1/extension/update`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    throw new Error(`Helper update failed with ${response.status}`);
  }

  return response.json();
}

function scheduleSnapshot(reason) {
  if (debounceTimer) {
    clearTimeout(debounceTimer);
  }

  debounceTimer = setTimeout(() => {
    pushSnapshot(reason).catch((error) => {
      console.warn("ChatGPTWebV15 sync failed", error);
    });
  }, SNAPSHOT_DEBOUNCE_MS);
}

async function refreshChatGPT() {
  const matchingTabs = await chrome.tabs.query({
    url: [
      "https://chatgpt.com/*",
      "https://chat.openai.com/*",
      "https://openai.com/*"
    ]
  });

  if (matchingTabs.length > 0) {
    const tab = matchingTabs[0];
    if (tab.id !== undefined) {
      await chrome.tabs.update(tab.id, { active: true });
      await chrome.tabs.reload(tab.id);
      return { action: "reloaded", tabId: tab.id };
    }
  }

  const tab = await chrome.tabs.create({ url: "https://chatgpt.com/" });
  return { action: "opened", tabId: tab.id };
}

async function helperHealth() {
  const helperBase = await getHelperBase();
  const response = await fetch(`${helperBase}/health`);
  if (!response.ok) {
    throw new Error(`Helper health failed with ${response.status}`);
  }
  return response.json();
}

chrome.cookies.onChanged.addListener((changeInfo) => {
  if (isRelevantDomain(changeInfo.cookie?.domain || "")) {
    scheduleSnapshot("cookie_changed");
  }
});

chrome.runtime.onInstalled.addListener(() => {
  scheduleSnapshot("installed");
});

chrome.runtime.onStartup.addListener(() => {
  scheduleSnapshot("startup");
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    if (message?.type === "sync_now") {
      const result = await pushSnapshot("manual");
      sendResponse({ ok: true, result });
      return;
    }

    if (message?.type === "refresh_chatgpt") {
      const result = await refreshChatGPT();
      sendResponse({ ok: true, result });
      return;
    }

    if (message?.type === "helper_health") {
      const result = await helperHealth();
      sendResponse({ ok: true, result });
      return;
    }

    if (message?.type === "save_helper_base") {
      await chrome.storage.local.set({ helperBase: message.helperBase || DEFAULT_HELPER_BASE });
      sendResponse({ ok: true });
      return;
    }

    if (message?.type === "get_helper_base") {
      sendResponse({ ok: true, helperBase: await getHelperBase() });
      return;
    }

    sendResponse({ ok: false, error: "unknown_message" });
  })().catch((error) => {
    sendResponse({ ok: false, error: String(error) });
  });

  return true;
});
