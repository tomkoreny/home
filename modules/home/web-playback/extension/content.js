(() => {
  const YOUTUBE_HOSTS = new Set(["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"]);
  const TWITCH_RESERVED = new Set([
    "directory", "downloads", "jobs", "p", "search", "settings", "subscriptions",
    "inventory", "wallet", "drops", "friends", "messages", "login", "signup",
    "turbo", "prime", "store", "videos", "clip", "clips", "moderator", "dashboard",
  ]);
  const PLAYER_SELECTOR = '.html5-video-player, [data-a-target="video-player"], [data-test-selector="video-player"], .video-player';
  const RELEVANT_SELECTOR = `video, ${PLAYER_SELECTOR}`;
  const host = document.createElement("div");
  host.setAttribute("data-web-playback-control", "");
  const root = host.attachShadow({ mode: "closed" });
  const style = document.createElement("style");
  style.textContent = `
    :host {
      all: initial;
      position: absolute;
      top: 12px;
      right: 12px;
      z-index: 100;
      display: flex;
      flex-direction: column;
      align-items: flex-end;
      gap: 6px;
      max-width: calc(100% - 24px);
      font-family: inherit;
      color-scheme: dark;
      pointer-events: none;
    }
    button {
      font-family: inherit;
      font-size: 13px;
      font-weight: 600;
      line-height: 1.3;
      color: #fff;
      background: #202020;
      border: 1px solid #a6a6a6;
      border-radius: 4px;
      padding: 7px 10px;
      cursor: pointer;
      pointer-events: auto;
    }
    button:hover:not(:disabled) { background: #363636; }
    button:focus-visible { outline: 3px solid #fff; outline-offset: 3px; }
    button:disabled { color: #d4d4d4; cursor: wait; }
    .message {
      box-sizing: border-box;
      max-width: min(320px, 100%);
      margin: 0;
      padding: 8px 10px;
      border-radius: 4px;
      background: #202020;
      color: #fff;
      font-family: inherit;
      font-size: 13px;
      line-height: 1.45;
      overflow-wrap: anywhere;
      pointer-events: auto;
    }
    .message:empty { display: none; }
    .message[data-error] { border-left: 3px solid #ff8a91; }
  `;
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = "Play in mpv";
  button.title = "Play in mpv (Alt+Shift+M)";
  const status = document.createElement("p");
  status.className = "message";
  status.id = "web-playback-status";
  status.setAttribute("role", "status");
  status.setAttribute("aria-live", "polite");
  status.setAttribute("aria-atomic", "true");
  button.setAttribute("aria-describedby", status.id);
  root.append(style, button, status);

  let activeVideo = null;
  let container = null;
  let originalPosition = null;
  let currentUrl = location.href;
  let revision = 0;
  let mediaRevision = 0;
  let pending = false;
  let scheduled = false;

  function page() {
    const url = new URL(location.href);
    if (YOUTUBE_HOSTS.has(url.hostname)) {
      const id = url.hostname === "youtu.be"
        ? url.pathname.slice(1).replace(/\/$/, "")
        : url.pathname === "/watch"
          ? url.searchParams.get("v")
          : url.pathname.match(/^\/(?:shorts|live)\/([\w-]{11})\/?$/)?.[1];
      return typeof id === "string" && /^[\w-]{11}$/.test(id) ? { youtube: true, id } : null;
    }
    if (url.hostname === "clips.twitch.tv") {
      return /^\/[A-Za-z0-9_-]+\/?$/.test(url.pathname) && url.pathname !== "/embed"
        ? { youtube: false, id: url.pathname } : null;
    }
    if (!["twitch.tv", "www.twitch.tv", "m.twitch.tv"].includes(url.hostname)) return null;
    if (/^\/videos\/\d+\/?$/.test(url.pathname) ||
        /^\/[A-Za-z0-9_]+\/clip\/[A-Za-z0-9_-]+\/?$/.test(url.pathname)) {
      return { youtube: false, id: url.pathname };
    }
    const channel = url.pathname.match(/^\/([A-Za-z0-9_]{1,25})\/?$/)?.[1];
    return channel && !TWITCH_RESERVED.has(channel.toLowerCase())
      ? { youtube: false, id: channel.toLowerCase() } : null;
  }

  function message(text, error = false) {
    status.setAttribute("role", error ? "alert" : "status");
    status.setAttribute("aria-live", error ? "assertive" : "polite");
    status.toggleAttribute("data-error", error);
    status.textContent = text;
  }

  function selectVideo() {
    const activeShort = document.querySelector("ytd-reel-video-renderer[is-active] video");
    if (location.pathname.startsWith("/shorts/") && activeShort) return activeShort;
    let best = null;
    let bestArea = 0;
    for (const video of document.querySelectorAll("video")) {
      const bounds = video.getBoundingClientRect();
      const area = Math.max(0, Math.min(bounds.right, innerWidth) - Math.max(bounds.left, 0)) *
        Math.max(0, Math.min(bounds.bottom, innerHeight) - Math.max(bounds.top, 0));
      if (area > bestArea && getComputedStyle(video).visibility !== "hidden") {
        best = video;
        bestArea = area;
      }
    }
    return best;
  }

  function mediaChanged() {
    mediaRevision++;
    schedule();
  }

  function detach() {
    host.remove();
    if (container && originalPosition !== null && container.style.position === "relative") {
      container.style.position = originalPosition;
    }
    container = null;
    originalPosition = null;
  }

  function refresh() {
    scheduled = false;
    if (location.href !== currentUrl) {
      currentUrl = location.href;
      revision++;
      message("");
    }
    const video = page() ? selectVideo() : null;
    if (video !== activeVideo) {
      for (const event of ["emptied", "loadstart", "loadedmetadata"]) {
        activeVideo?.removeEventListener(event, mediaChanged);
        video?.addEventListener(event, mediaChanged);
      }
      activeVideo = video;
      mediaRevision++;
      message("");
    }
    if (!video) {
      detach();
      return;
    }
    const fullscreen = document.fullscreenElement;
    const nextContainer = fullscreen?.contains(video) && fullscreen !== video
      ? fullscreen : video.closest(PLAYER_SELECTOR) || video.parentElement;
    if (nextContainer !== container || !host.isConnected) {
      detach();
      container = nextContainer;
      if (getComputedStyle(container).position === "static") {
        originalPosition = container.style.position;
        container.style.position = "relative";
      }
      container.append(host);
    }
    button.disabled = pending;
    button.textContent = pending ? "Opening mpv…" : "Play in mpv";
    button.setAttribute("aria-busy", String(pending));
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(refresh, 100);
  }

  function adPlaying(video) {
    const player = video.closest(".html5-video-player");
    return Boolean(player?.classList.contains("ad-showing") ||
      player?.classList.contains("ad-interrupting") ||
      video.closest("ytd-reel-video-renderer[is-ad]"));
  }

  function isLive(video) {
    const player = video.closest(".html5-video-player");
    if (player?.classList.contains("ytp-live")) return true;
    const badge = player?.querySelector(".ytp-live-badge");
    return Boolean(badge && badge.getClientRects().length && getComputedStyle(badge).visibility !== "hidden");
  }

  function youtubeVideoId(video) {
    const id = video.closest("[video-id]")?.getAttribute("video-id");
    if (id && /^[\w-]{11}$/.test(id)) return id;
    const link = video.closest(".html5-video-player")?.querySelector("a.ytp-title-link");
    if (!link?.href) return null;
    try {
      return new URL(link.href).searchParams.get("v");
    } catch {
      return null;
    }
  }

  function stillCaptured(captured) {
    return captured.url === location.href && captured.revision === revision &&
      captured.mediaRevision === mediaRevision && captured.video === activeVideo &&
      captured.video.isConnected && captured.source === captured.video.currentSrc &&
      captured.sourceObject === captured.video.srcObject &&
      page()?.id === captured.id && (!captured.youtube ||
        (!adPlaying(captured.video) && youtubeVideoId(captured.video) === captured.playerId));
  }

  async function handoff() {
    if (pending) return { accepted: true };
    refresh();
    const content = page();
    if (!content || !activeVideo) {
      return { accepted: false, error: "Open a visible YouTube or Twitch video first." };
    }
    if (content.youtube && adPlaying(activeVideo)) {
      message("Wait for the YouTube advertisement to finish, then choose Play in mpv.", true);
      return { accepted: true };
    }
    if (!activeVideo.readyState || (!activeVideo.currentSrc && !activeVideo.srcObject)) {
      message("The video is still loading. Try Play in mpv when playback is ready.", true);
      return { accepted: true };
    }
    const playerId = content.youtube ? youtubeVideoId(activeVideo) : null;
    if (playerId && playerId !== content.id) {
      message("The selected video is still loading. Try Play in mpv once it appears.", true);
      return { accepted: true };
    }
    const captured = {
      ...content,
      url: location.href,
      video: activeVideo,
      source: activeVideo.currentSrc,
      sourceObject: activeVideo.srcObject,
      playerId,
      revision,
      mediaRevision,
    };
    const request = { type: "web-playback:open", url: captured.url };
    if (content.youtube && Number.isFinite(activeVideo.duration) && activeVideo.duration > 0 &&
        Number.isFinite(activeVideo.currentTime) && !isLive(activeVideo)) {
      request.start = Math.max(0, activeVideo.currentTime);
    }
    pending = true;
    message("");
    refresh();
    // Return acceptance immediately; the native reply alone decides whether to pause.
    (async () => {
      try {
        const reply = await chrome.runtime.sendMessage(request);
        refresh();
        if (!stillCaptured(captured)) return;
        if (reply?.ok === true) {
          captured.video.pause();
          message("Playing in mpv. Browser playback paused.");
        } else {
          message(`Could not open mpv. ${typeof reply?.error === "string" ? reply.error : "No valid response from the native host."}`, true);
        }
      } catch (error) {
        refresh();
        if (stillCaptured(captured)) {
          message(`Could not open mpv. ${error.message || "Reload this page and check that the extension and native host are enabled."}`, true);
        }
      } finally {
        pending = false;
        refresh();
      }
    })();
    return { accepted: true };
  }

  button.addEventListener("click", (event) => {
    event.stopPropagation();
    void handoff();
  });
  chrome.runtime.onMessage.addListener((request, _sender, sendResponse) => {
    if (request?.type !== "web-playback:invoke") return false;
    handoff().then(sendResponse, (error) => sendResponse({ accepted: false, error: error.message }));
    return true;
  });

  function navigationChanged() {
    revision++;
    message("");
    schedule();
  }
  window.navigation?.addEventListener("navigate", navigationChanged);
  window.addEventListener("popstate", navigationChanged);
  window.addEventListener("hashchange", navigationChanged);
  window.addEventListener("resize", schedule, { passive: true });
  window.addEventListener("scroll", schedule, { passive: true, capture: true });
  document.addEventListener("yt-navigate-start", navigationChanged);
  document.addEventListener("yt-navigate-finish", schedule);
  document.addEventListener("fullscreenchange", schedule);
  document.addEventListener("loadedmetadata", schedule, true);
  // Child-list changes catch player replacement without observing class/focus churn.
  new MutationObserver((records) => {
    if (location.href !== currentUrl || (activeVideo && !activeVideo.isConnected) ||
        (container && !host.isConnected)) {
      schedule();
      return;
    }
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (node.nodeType === Node.ELEMENT_NODE &&
            (node.matches(RELEVANT_SELECTOR) || node.querySelector(RELEVANT_SELECTOR))) {
          schedule();
          return;
        }
      }
    }
  }).observe(document.documentElement, { childList: true, subtree: true });
  refresh();
})();
