// Content script shipped in the patched Stylus by ./default.nix, which replaces
// @accent@ with the shared accent. The Catppuccin YouTube userstyle already
// recolors the in-page logo, but the tab favicon is a red PNG that CSS cannot
// reach, so every icon link is pointed at the same play button in the accent.
const ICON =
  "data:image/svg+xml," +
  encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 -4 28 28">' +
      '<path fill="@accent@" d="M27.4 3.1A3.5 3.5 0 0 0 25 .6C22.8 0 14 0 14 0S5.2 0 3 .6A3.5 3.5 0 0 0 .6 3.1C0 5.3 0 10 0 10s0 4.7.6 6.9A3.5 3.5 0 0 0 3 19.4c2.2.6 11 .6 11 .6s8.8 0 11-.6a3.5 3.5 0 0 0 2.4-2.5c.6-2.2.6-6.9.6-6.9s0-4.7-.6-6.9Z"/>' +
      '<path fill="#fff" d="m11.2 14.3 7.3-4.3-7.3-4.3Z"/>' +
      "</svg>",
  );

function recolor() {
  for (const link of document.querySelectorAll('link[rel~="icon"]')) {
    if (link.href !== ICON) {
      link.type = "image/svg+xml";
      link.href = ICON;
    }
  }
}

// The script runs before <head> exists, and YouTube swaps icon links while it
// navigates without reloading, so watch the head for added or changed links.
function watch(head) {
  recolor();
  new MutationObserver(recolor).observe(head, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["href", "rel"],
  });
}

if (document.head) {
  watch(document.head);
} else {
  const waitForHead = new MutationObserver(() => {
    if (document.head) {
      waitForHead.disconnect();
      watch(document.head);
    }
  });
  waitForHead.observe(document.documentElement, { childList: true });
}
