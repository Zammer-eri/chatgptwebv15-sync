const helperBaseInput = document.getElementById("helperBase");
const statusNode = document.getElementById("status");

function setStatus(value) {
  statusNode.textContent = value;
}

function sendMessage(message) {
  return chrome.runtime.sendMessage(message);
}

async function initialize() {
  const response = await sendMessage({ type: "get_helper_base" });
  if (response?.ok) {
    helperBaseInput.value = response.helperBase;
  }
}

document.getElementById("save").addEventListener("click", async () => {
  const helperBase = helperBaseInput.value.trim();
  const response = await sendMessage({ type: "save_helper_base", helperBase });
  setStatus(response?.ok ? `Saved ${helperBase}` : `Save failed: ${response?.error}`);
});

document.getElementById("sync").addEventListener("click", async () => {
  const response = await sendMessage({ type: "sync_now" });
  setStatus(response?.ok ? JSON.stringify(response.result, null, 2) : `Sync failed: ${response?.error}`);
});

document.getElementById("refresh").addEventListener("click", async () => {
  const response = await sendMessage({ type: "refresh_chatgpt" });
  setStatus(response?.ok ? JSON.stringify(response.result, null, 2) : `Refresh failed: ${response?.error}`);
});

document.getElementById("health").addEventListener("click", async () => {
  const response = await sendMessage({ type: "helper_health" });
  setStatus(response?.ok ? JSON.stringify(response.result, null, 2) : `Health failed: ${response?.error}`);
});

initialize().catch((error) => {
  setStatus(String(error));
});
