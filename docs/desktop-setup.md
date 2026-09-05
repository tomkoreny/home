# Desktop setup notes

Quick reference for the Hyprland desktop tweaks. Changes live in
`modules/home/hyprland/`, `modules/home/mako/`, and
`homes/x86_64-linux/tom@nixos/default.nix`.

> Pretty version: open `docs/reference.html` in a browser.

Widget reference:
[Quickshell bar, launcher, task, notification, and OSD widgets](widgets.md).

## Keyboard: splitkb Aurora Corne · Miryoku (QWERTY)

The primary keyboard is a **splitkb Aurora Corne** running **Miryoku** in QMK
firmware, **QWERTY** base (`MIRYOKU_ALPHAS=QWERTY`; Colemak-DH is on the Extra
layer). Keymap lives in `~/qmk_userspace/users/miryoku_553`. This shapes every
keybind decision:

- Modifiers are **home-row holds** — Super/GUI, Alt, Ctrl, Shift.
- Numbers and symbols live on **thumb-activated layers** (Num/Sym/Fun).
- Prefer **single-mod binds**, ideally `Super + <letter on the opposite hand>`.
- Chorded mods (`Super+Shift`) and the number row (workspace switching) are
  awkward to press and are candidates for a Miryoku-aware revision.

## Keybindings

| Keys                    | Action                                              |
| ----------------------- | --------------------------------------------------- |
| `Super + B`             | Launch Helium browser                               |
| `Super + D`             | Proofread selection & rewrite with Czech diacritics |
| `Super + Shift + V`     | Clipboard history (cliphist via wofi)               |
| `Super + Shift + M`     | Play a copied YouTube/Twitch link in mpv             |
| `Alt + Shift + M`       | Hand off the current browser video to mpv            |
| `Print`                 | Screenshot a region (saved + copied)                |
| `Super + Print`         | Screenshot the whole monitor                        |
| `Super + Shift + Print` | Screenshot the active window                        |

Screenshots use **hyprshot** (→ `~/Pictures` + clipboard). Clipboard history
uses **cliphist**.

## YouTube and Twitch in mpv

Enabled for `tom@nixos` through `tomkoreny.web-playback.enable`. The launcher,
native-messaging host, and browser extension live in `modules/home/web-playback/`.
Apply the Home Manager configuration or your normal system rebuild, then fully
exit and relaunch Helium so its declaratively loaded extension is picked up.
There is no need to install a userscript or give the extension your cookies.

- **Browser:** use the player-corner **Play in mpv** button, the extension toolbar
  action, or **Alt + Shift + M**. YouTube's current position transfers; Twitch
  joins the live stream (VODs/clips open without a position transfer). The webpage
  pauses only after mpv reports playback, never just because a process started.
  If you navigate during startup, the reply cannot pause the replacement video.
- **Clipboard:** copy a supported link and press **Super + Shift + M**. YouTube
  timestamps such as `?t=2m` are preserved; playlist parameters are discarded.
  This entry point does not control or pause any browser tab.
- **Terminal:** `web-playback 'https://youtu.be/VIDEO_ID'`, optionally with
  `--start SECONDS`, or `web-playback --clipboard`.

YouTube uses the pinned yt-dlp (including its JavaScript runtime); Twitch uses
Streamlink. Both launch an independent mpv with normal MPRIS media controls and
the `WebPlayback` identity, separate from Jellyfin's queue and camera settings.
Closing the browser does not stop acknowledged playback. Failures are shown on
the page or as a desktop notification for clipboard/terminal launches.

This is guest playback: no account cookies, automatic redirects, watch-history
sync, or recommendation/queue transfer. Keep restricted content in the browser.
YouTube extractor restrictions can still prevent playback. Streamlink may pause
through Twitch ad breaks and may launch its explicitly pinned, isolated Chromium
for integrity checks; it never discovers or drives Helium.

The extension and native host are installed for **Helium only**. Chromium is used
only for isolated verification and Streamlink's integrity checks, not as the
viewing browser. macOS and Terka's profile are not enabled.
Boundary checks: `python3 -B modules/home/web-playback/test_playback.py`.

## Czech diacritics

### 1. Type directly — tap `V+M`, then the letter

A firmware **CZ layer** (`~/qmk_userspace/users/miryoku_553`, branch
`feat/czech-diacritics-layer`) puts every Czech accent on its own QWERTY letter
key via QMK Unicode. The **V+M combo toggles** it on/off; everything else falls
through to the base layer. All 15 letters: á č ď é ě í ň ó ř š ť ú ů ý ž
(u→ů, ú on j, ě on w). Works in GTK/Electron apps (Linux Unicode mode); capital
accents and terminals/Qt need `Super+D`. See `docs/reference.html`.

### 2. Whole phrases / fix-ups — `Super + D`

Highlight any text, press `Super + D`. The `diacritics-fix` script runs the
selection through the authenticated `claude` CLI to add diacritics + fix typos,
then types it back over the selection.

- Script: defined in `modules/home/hyprland/default.nix` (`writeShellScriptBin`).
- Requires the `claude` CLI to be logged in; uses your Claude subscription and
  takes a second or two (a "Proofreading…" notification shows while it runs).

## Text expansion (Espanso)

Tom's Linux session runs Espanso on Wayland. Snippets are declared in
`modules/home/espanso/default.nix`; edit them there and apply the configuration,
not the generated YAML under `~/.config/espanso/`.

| Trigger | Expansion |
| --- | --- |
| `;email` or `;@` | `tom@tomkoreny.com` |
| `;name` | `Tom Koreny` |
| `;web` | `https://tomkoreny.com` |
| `;date` | Current local date, `YYYY-MM-DD` |

For the initial installation, run `sudo nixos-rebuild switch --flake .#nixos`,
then log out completely and back in (or reboot) to pick up the new
`seat0-input` group. Espanso starts with the graphical session.
Check it with `systemctl --user status espanso`.

Permissions live in `modules/nixos/espanso/default.nix`. The unprivileged
daemon can read seat0 event devices and write `/dev/uinput`; it is not given
the global `input` group or `CAP_DAC_OVERRIDE`, which would expose seat1's
keyboard. This does grant other processes running as Tom raw seat0 input
access too. Terka's profile and macOS do not enable Espanso.

The keyboard layout is explicitly US, matching the QMK/Hyprland setup.
After connecting a new keyboard, run `systemctl --user restart espanso`;
Espanso's Wayland backend discovers devices at startup.

## Gotcha: new files must be git-tracked

This is a flake on a git repo, so **Nix ignores untracked files**. After adding
a new module/file, `git add` it before `sw`, or the rebuild won't see it.
