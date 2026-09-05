const HOST = "com.tomkoreny.web_playback";
const DEFAULT_TITLE = "Play in mpv (Alt+Shift+M)";
const SITE_HOSTS = new Set([
  "youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be",
  "twitch.tv", "www.twitch.tv", "m.twitch.tv", "clips.twitch.tv",
]);
const pendingTabs = new Set();

function supportedOrigin(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && SITE_HOSTS.has(url.hostname) && !url.port;
  } catch {
    return false;
  }
}

function nativeError(message) {
  if (/host not found|not registered|not installed/i.test(message)) {
    return "The mpv native host is not installed or registered. Enable web playback in the system configuration and restart the browser.";
  }
  return `The mpv native host could not complete playback: ${message}`;
}

chrome.action.onClicked.addListener(async (tab) => {
  if (tab.id === undefined) return;
  try {
    const reply = await chrome.tabs.sendMessage(tab.id, { type: "web-playback:invoke" });
    if (!reply?.accepted) throw new Error(reply?.error || "Open a YouTube or Twitch video first.");
    await chrome.action.setBadgeText({ tabId: tab.id, text: "" });
    await chrome.action.setTitle({ tabId: tab.id, title: DEFAULT_TITLE });
  } catch (error) {
    const message = /receiving end|connection/i.test(error.message)
      ? "Open a YouTube or Twitch video, then reload the page if the extension was just enabled."
      : error.message;
    await Promise.allSettled([
      chrome.action.setBadgeText({ tabId: tab.id, text: "!" }),
      chrome.action.setBadgeBackgroundColor({ tabId: tab.id, color: "#a91d28" }),
      chrome.action.setTitle({ tabId: tab.id, title: `Play in mpv: ${message}` }),
    ]);
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "web-playback:open") return false;
  if (sender.id !== chrome.runtime.id || sender.frameId !== 0 || !sender.tab ||
      !supportedOrigin(sender.url) || typeof message.url !== "string" ||
      message.url.length > 4096 || !supportedOrigin(message.url)) {
    sendResponse({ ok: false, error: "This page cannot request mpv playback." });
    return false;
  }
  if (message.start !== undefined &&
      (typeof message.start !== "number" || !Number.isFinite(message.start) || message.start < 0)) {
    sendResponse({ ok: false, error: "The playback position is invalid." });
    return false;
  }
  const tabId = sender.tab.id;
  if (pendingTabs.has(tabId)) {
    sendResponse({ ok: false, error: "A playback request is already opening in this tab." });
    return false;
  }
  pendingTabs.add(tabId);
  let finished = false;
  let timer;
  const finish = (reply) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    pendingTabs.delete(tabId);
    sendResponse(reply);
  };
  timer = setTimeout(() => finish({
    ok: false,
    error: "Timed out waiting for mpv to start playback. Browser playback was left unchanged.",
  }), 120_000);
  const request = { url: message.url };
  if (message.start !== undefined) request.start = message.start;
  try {
    chrome.runtime.sendNativeMessage(HOST, request, (reply) => {
      const error = chrome.runtime.lastError;
      if (error) {
        finish({ ok: false, error: nativeError(error.message) });
      } else if (reply?.ok === true) {
        finish({ ok: true });
      } else {
        finish({
          ok: false,
          error: typeof reply?.error === "string" ? reply.error : "The mpv native host returned an invalid response.",
        });
      }
    });
  } catch (error) {
    finish({ ok: false, error: nativeError(error.message) });
  }
  return true;
});
