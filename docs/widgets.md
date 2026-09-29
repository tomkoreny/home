<!-- markdownlint-disable MD013 -->

# Desktop widgets

The desktop shell is split into two Quickshell configurations:

- `tom-bar` provides the multi-monitor bar, launcher, timers, Notion tasks,
  work tasks, and notifications.
- `tom-osd` provides volume and brightness indicators, the media popup, and the
  session menu.

Both are Linux-only Home Manager modules. The data helpers behind the timers,
Notion tasks, and work tasks live in `modules/home/bar-backends/` and are
shared with the macOS bar (see [macOS bar](#macos-bar)). Shared colours and
fonts come from `lib/common/default.nix`; see [theming.md](theming.md) before
adding another hard-coded visual convention.

## Quick reference

| Surface | Open or use it | Main implementation |
| --- | --- | --- |
| Application launcher | `Super + R` | `Launcher.qml`, `LauncherData.qml` |
| AI launcher | `Super + A` or `? question` | `Launcher.qml`, `LauncherData.qml` |
| Herdr panes | `Super + H` or `h query` | `Launcher.qml`, `LauncherData.qml` |
| Cameras | `Super + U` or `cam query` | `Launcher.qml`, `LauncherData.qml` |
| Clipboard history | `Super + Shift + V` or `clip query` | `Launcher.qml`, `LauncherData.qml` |
| Timer creation | Click the timer in the bar or enter `timer 20m pasta` | `TimerPopup.qml`, `TimerService.qml`, `timer-backend.py` |
| Notion task manager | `Super + T` or click the task count in the bar | `TodoManager.qml`, `notion-todos.py` |
| Direct task capture | `Super + Shift + T` | `TodoManager.qml`, `notion-todos.py` |
| Work task manager | `Super + W` or click the briefcase count | `WorkTaskManager.qml`, `WorkTaskService.qml`, `work-tasks.py`, `mantis_tasks.py` |
| Notification centre | `Super + N` or click the bell | `Notifications.qml`, `NotificationCard.qml` |
| Sound popover | Click the volume in the bar | `VolumePopup.qml` |
| Arctis headset settings | Click the headset battery icons in the bar | `HeadsetSettingsPopup.qml`, `HeadsetService.qml`, `arctis.py` |
| Session menu | `Super + Escape` or click the power icon | `modules/home/quickshell-osd/shell.qml` |
| Volume OSD | Audio volume and mute keys | `modules/home/quickshell-osd/` |
| Brightness OSD | Monitor brightness keys | `modules/home/quickshell-osd/` |
| Media popup | Track or playback-state change | `modules/home/quickshell-osd/shell.qml` |

The shortcuts are declared in
`modules/home/hyprland/config/hyprland/main.lua`. Home Manager explicitly
refreshes the camera, clipboard, and task bindings in the running compositor
because reloading that Lua configuration otherwise retains the old callbacks.

## Bar

`modules/home/quickshell-bar/shell.qml` creates one 36-pixel top bar on every
connector listed in `tomkoreny.quickshell-bar.outputs`.

### Workspace island

Every configured output gets a workspace island on the left. It shows only the
positive-numbered Hyprland workspaces assigned to that monitor. Click a number
to activate it.

When a workspace contains exactly one window, the bar uses a black background
and removes the floating-island treatment. With zero or multiple windows, the
bar remains transparent around the two islands.

### Primary status island

Only `primaryOutput` gets the right-hand status island. Its items are ordered as
follows:

| Widget | Display | Interaction |
| --- | --- | --- |
| NixOS upgrade | Red `upgrade` when the last hourly auto-upgrade failed, or `no upgrade` when none has finished for 24 hours; hidden otherwise | Click to open the `nixos-upgrade.service` journal; hover for the first Nix error and the time of the last successful upgrade. |
| Herdr | Working-agent count and blocked count | Click to open the Herdr launcher mode; hover for the full working/blocked/idle summary. |
| Timers | Remaining time for the next running timer and `+N` for additional timers | Click to open the timer popup. |
| AI limits | OpenAI Codex weekly limit and Claude five-hour/weekly limits, including compact reset times | Click to invalidate and refresh OMP usage; hover for every reported limit and exact reset time. |
| Notion tasks | Today count and, when non-zero, overdue count | Click to open the focused task manager; hover for freshness or cache errors. |
| Work tasks | Briefcase and actionable assigned count; hidden at zero | Click to open the separate manager; hover for provider and freshness. |
| Audio | PipeWire default-sink volume and mute state, then the Arctis headset battery while the headset is on and the spare battery charging in its base | Click the volume to open the sound popover; middle-click to toggle mute; click a battery to open the Arctis settings; hover for the volume and both batteries. |
| System tray | Quickshell system-tray items | Left click activates, middle click performs secondary activation, and right click opens the nested menu. |
| Clock | Time and abbreviated date; hidden while the Arctis base answers, because its OLED shows the clock | Click to toggle seconds; hover for the full date. |
| Notifications | Bell/DND state and unread badge | Click to open the notification centre. |
| Session | Power glyph | Click to open the session menu. |

Herdr is sampled every two seconds. AI limits and the compact Notion task list
refresh every five minutes; clicking either widget refreshes it immediately.
The Notion background refresh is intentionally the small `widget` query: Tom's
incomplete tasks due today or earlier. Unassigned and All tasks are fetched only
when those manager tabs open.

The upgrade widget reads `/var/lib/nixos-upgrade-status/status.json`, which the
`nixos-upgrade` unit's `ExecStopPost` hook rewrites after every run (see
`systems/x86_64-linux/nixos/default.nix`). The file is checked once a minute. A
new failure streak also sends one critical desktop notification; the hourly
retries of the same streak stay quiet.

## Launcher

The launcher opens on the currently focused monitor. Without a mode prefix it
searches desktop applications and launches the selected desktop entry through
`uwsm app`.

### Modes

| Prefix | Mode | Example | Enter action |
| --- | --- | --- | --- |
| none | Applications | `ghostty` | Launch the selected application. |
| `=` | Calculator | `= 18 / 3` | Copy the `qalc` result. |
| `u` + space | Unit conversion | `u 10 km to mi` | Copy the `qalc` result. |
| `?` | AI | `? explain zfs snapshots` | Submit the question; after the answer arrives, copy it. |
| `timer` + space | Timer | `timer 20m pasta` | Create the timer and close the launcher. |
| `clip` + space | Clipboard | `clip invoice` | Copy the selected cliphist entry. Image entries load thumbnails lazily. |
| `h` + space | Herdr panes | `h nixos` | Open the selected pane. `Shift + Enter` takes over the pane. |
| `cam` + space | Cameras | `cam door` | Open one Protect stream; the first result opens an automatically arranged grid. |

Direct shortcuts lock the launcher to their respective mode, so the user does
not need to type the prefix.

### Keyboard behavior

- `Down` or `Ctrl + N`: next result.
- `Up` or `Ctrl + P`: previous result.
- `Enter`: activate, submit, or copy the current result.
- `Ctrl + Enter`: keep calculator, conversion, or AI output open after copying.
- `Shift + Enter`: resume a completed AI answer in OMP, or take over the selected
  Herdr pane.
- `Escape`: cancel an active AI request first; otherwise close the launcher.

AI in the launcher is deliberately one-shot. It does not expose tools or a
multi-turn chat UI; `Shift + Enter` hands the stored session to OMP when more
work is needed.

## Timers

Click the timer glyph in the bar to open the anchored popup. Enter a duration
followed by an optional name, or use the `5m`, `10m`, `25m`, and `1h` presets.
Accepted duration units are days, hours, minutes, and seconds and may be
combined:

```text
45s tea
20m pasta
1h 30m deep work
```

Timers cannot exceed seven days. Each row can be paused, resumed, or cancelled.
When a timer expires, the service sends a persistent critical notification and
plays the configured sound.

Timer state is written atomically to
`~/.local/state/quickshell-bar/timers.json`. It is guarded by a file lock and is
bound to the current boot ID, so stale timers do not resume after a reboot.

## Notion tasks

The Notion database is authoritative. There is no offline write queue: writes
are optimistic in the UI, but a failed request restores the previous task and
shows the error.

### Compact Today panel

The persistent panel below the top-right bar shows up to eight tasks assigned to
Tom and due today or earlier. An unchecked box completes immediately. The task
title opens the Notion page, the refresh button bypasses the five-minute wait,
and Undo is available for eight seconds after a completion.

If Notion is unavailable after a successful prior fetch, the panel keeps the
scoped cache visible and marks it stale.

### Focused manager

`Super + T` opens the manager on the focused monitor. The task-count bar widget
opens the same surface.

- **My tasks** groups open tasks into Overdue, Today, Upcoming, and Inbox.
- **Unassigned** shows incomplete tasks with no assignee and offers **Assign to
  me**.
- **All** shows every incomplete task. Tasks assigned to somebody else are
  read-only and identify their assignee.
- Search filters the currently loaded view locally.

Click an owned task row to edit its title, due date, priority, or three-state
Notion status. The status pill cycles status; the checkbox always completes the
task directly. The external-link action opens the page in Notion.

Completed today is a local journal of tasks completed through Quickshell. Expand
it to inspect a completed task and use its checked box to reopen it with the
status it had before completion. It is not a general query of everything marked
Done in Notion.

### Capture

`Super + Shift + T` focuses capture directly. New tasks default to Tom,
`Not started`, no due date, and no priority. Explicit tokens can be included
anywhere in the input:

| Token | Meaning |
| --- | --- |
| `@today` | Due today. |
| `@tomorrow` | Due tomorrow. |
| `@mon` through `@sun` | Due on the next occurrence, including today. |
| `@YYYY-MM-DD` | Exact due date. |
| `!high`, `!medium`, `!low` | Priority. |

Example:

```text
Send renewal quote @tomorrow !high
```

- `Enter`: create and close.
- `Ctrl + Enter`: create and keep capture open.
- `Tab`: parse the tokens into explicit due-date and priority controls before
  creation.
- `Escape`: close without creating.

### Notion data and local state

The helper discovers the database's title, due, assignee, priority, and status
properties instead of hard-coding their display names. The SOPS secret defined
by `modules/home/quickshell-bar/default.nix` supplies the API token and database
ID; do not put either value in QML or documentation.

Caches and local state:

```text
~/.cache/quickshell-bar/notion-todos.json
~/.cache/quickshell-bar/notion-todos-mine.json
~/.cache/quickshell-bar/notion-todos-unassigned.json
~/.cache/quickshell-bar/notion-todos-all.json
~/.local/state/quickshell-bar/notion-completed.json
```

The four query caches are separate so a broad manager result cannot replace the
small desktop-widget result. Any successful mutation invalidates all four.

## Work tasks

Work tasks are independent of personal Notion tasks. One configured provider is
active at a time; Polaris uses the MantisBT adapter. There is no creation,
assignment editing, commenting, or inline detail view.

`Super + W` or the primary bar's briefcase opens the manager on the focused
monitor. The shortcut remains available when the count is zero and the bar
indicator is hidden.

- Rows show title and status only. The title opens the provider's canonical URL.
- The status pill opens the provider's permitted workflow actions, not a generic
  completion checkbox. Resolved tasks leave the actionable list.
- Search matches titles and adapter keywords, including issue IDs and projects.
- The provider status filter survives close/reopen within the running session.
- Ordering uses adapter rank, then most recently updated first. Mantis ranks
  sticky issues first, then higher priority, then status.
- Arrow keys select a row; Enter opens it; Tab from the selected row focuses its
  status pill. Escape closes the action menu before closing the manager.

### Freshness and writes

The manager loads its cache immediately, refreshes when opened, and polls every
five minutes. Refresh is also available manually. Failed refreshes preserve the
last successful snapshot, display an error, and disable status writes. There is
no offline write queue.

Status changes are optimistic, serialized, and rolled back on failure. Before a
write, the Mantis adapter rechecks the account, assignment, current status,
project permissions, and configured workflow. The status-only PATCH uses the
fresh issue ETag with `If-Match`; conflicts are not silently retried.

The adapter requires workflow and permission metadata rather than guessing.
It conservatively enforces both generic status-update permission and per-status
thresholds, including the stricter REST restriction present in MantisBT 2.28.4.
Lower-access accounts on older releases may therefore have fewer offered
actions than that older REST endpoint itself accepts.

### Assignment notifications and storage

The first successful sync establishes a silent baseline. Later successful
polls notify only when an issue enters the actionable-assigned set, including
reassignment after an observed departure. Changes away and back between polls
cannot be detected. Other updates do not notify.

Assignment notifications use the existing notification server and DND policy.
They show the assignment event and task title, with an Open action for the
canonical URL.

`work-tasks.py` owns the provider-neutral snapshot and assignment baseline;
`mantis_tasks.py` owns Mantis REST, workflow, and access checks. Cache and baseline
are committed together atomically under:

```text
~/.local/state/quickshell-bar/work-tasks/<provider-config-hash>/state.json
```

The directory is private (`0700`) and the state file is `0600`. State is scoped
to provider configuration and the notification baseline resets silently when
the authenticated account changes.

Enable the widget through `tomkoreny.bar-backends.workTasks` (shared by the
Linux and macOS bars):

```nix
tomkoreny.bar-backends.workTasks = {
  enable = true;
  provider = "mantisbt";
  baseUrl = "https://polaris.i2ginfra.cz";
  label = "Polaris";
  sopsFile = ../../../secrets/polaris/work-tasks.json;
};
```

The encrypted JSON's `token` key becomes a raw, mode-`0400` SOPS secret. Neither
the token nor issue data is placed in QML or the generated Nix-store config.
The installed `work-tasks cache` command is network-free; `work-tasks list`
refreshes the cache and advances the notification baseline. Do not use `list`
as passive inspection while the bar is running: it consumes assignment events.

## Sound popover

Click the volume in the bar to open the sound popover. Middle-click the volume
to toggle mute without opening it.

- **Output** has a mute button, a volume slider, and the output devices.
  Clicking a device makes it the default sink.
- **Input** has the same controls for the default source. The line under the
  slider names the applications recording from it, or says it is not in use.
- **Apps** lists each application playing audio, with its own mute button and
  slider. The section is hidden when nothing is playing.
- **More settings** closes the popover and opens `pavucontrol`.

Drag or click a slider to set a level from 0 to 100 percent, or scroll over it
to move two percent at a time. Quickshell does not treat
`Audio/Source/Virtual` nodes as audio devices, so virtual microphones such as
noise-suppression filters do not appear in the input list.

## Arctis Pro Wireless

The bar talks to the SteelSeries Arctis Pro Wireless base station over its
vendor HID interface, USB `1038:1290`. `arctis.py` is the only process that
opens the device; `HeadsetService.qml` runs it as `arctis watch`. The
`services.udev.packages = [ pkgs.headsetcontrol ]` line in
`systems/x86_64-linux/nixos/default.nix` gives the logged-in user access to it.

The command bytes come from
[Chameth's reverse-engineering notes](https://chameth.com/reverse-engineering-arctis-pro-wireless-headset/),
each checked against the base's own menu. The base answers queries but cannot
report its settings, and it does not tell the PC when its volume knob turns.

### Batteries and power

The helper asks whether the headset is on every two seconds and reads both
batteries every minute. Batteries use the base's own four-bar scale. The bar
shows the headset battery while the headset is on and the spare battery while
one is charging in the base. A spare reading of zero also means the slot is
empty, so it is not shown.

`tomkoreny.quickshell-bar.headsetFallbackSink` names the sink that becomes the
default while the headset is off; on this host it is the VX2705 HDMI output.
Switching off moves the default there, and switching on moves it back. Each
move happens only while the sink it leaves is still the default, so an output
picked by hand is left alone.

### OLED clock

The helper keeps the time, with the day and date under it, on the base's
128x40 OLED. The block moves to a new spot every minute to spread burn-in, and
it stays one pixel clear of the edge. A track change from the active MPRIS
player replaces it for six seconds with the title and artist. Notifications
are not shown there.

### Settings popover

Click a headset battery icon to change the base's settings:

| Setting | Command | Values |
| --- | --- | --- |
| Equalizer preset | `0x2E` | 0 Balanced, 1 Immersion, 2 Performance, 3 Entertainment, 4 Music, 5 Voice, 6 Profile 1 |
| Sidetone | `0x39` | 0 to 9; the base menu shows about `value * 10 / 9` |
| Mic mute LED | `0x3E` | 0 to 10, in tenths of full brightness |
| Auto-off | `0x3C` | 0 for never, otherwise 10-minute steps up to 120 minutes |
| Volume limiter | `0x27` | 0 off, 1 on |
| OLED brightness | `0x85` | 0 to 10 |
| Screen mode | `0x89` | 0 dim, 1 off, 2 screensaver |

Each change applies at once. Changes stay unsaved on the base until the helper
sends the save command, `0x09`, 1.5 seconds after the last change. HeadsetControl
uses `0x90` for this model, which does not persist anything on this firmware.
If the base is unplugged before that save, it drops the change, and the popover
says so.

Because the base cannot report its settings, the popover shows the values last
sent from this PC, kept in `~/.local/state/arctis/settings.json`. Changes made
in the base's own menu do not appear in the popover. There is no known command
for the base's screen timeout.

Run the helper's regression test with Pillow available:

```bash
nix shell --impure --expr 'with import <nixpkgs> {}; python3.withPackages (p: [ p.pillow ])' \
  -c python3 modules/home/quickshell-bar/test_arctis.py
```

## Notifications

Quickshell is the notification server while the bar module is enabled; the Mako
module is disabled in that configuration.

Normal banners appear at the top right of the primary output for seven seconds.
Hover pauses that timeout. Critical banners remain until dismissed, and up to
five banners may be visible at once.

The notification centre retains up to 50 entries in memory. Opening it marks all
entries read and hides outstanding banners. It provides:

- the notification's default action by clicking its card;
- per-card dismissal;
- **Clear all**;
- **DND**, which suppresses normal banners but still allows critical banners;
- `Escape` or a click outside the panel to close.

The bar badge is the unread count, not the total retained history count.

## OSD and session overlays

`modules/home/quickshell-osd/` is a separate Quickshell process named `tom-osd`.
It is pinned to `tomkoreny.quickshell-osd.output`.

### Volume and brightness

The media keys call the `desktop-osd` controller:

- volume changes the PipeWire default sink by five percent and displays the
  resulting value or mute state;
- brightness changes VCP code 10 on the monitor selected by
  `monitorSerial`, verifies the DDC write, and displays the resulting percentage;
- concurrent DDC brightness writes are serialized with a runtime lock.

The microphone-mute key controls the PipeWire default source directly and does
not currently show an OSD.

### Media popup

Track and playback-state changes show a three-second popup with album art,
title, artist, player identity, progress, duration, and play/pause state. Player
selection prefers an active Jellyfin MPV Shim instance, then a playing player,
then a player with track metadata, then the first MPRIS player.

Media-key routing follows the same intent: use Jellyfin MPV Shim while it is
Playing or Paused; otherwise ignore that shim and target another player.

### Session menu

The full-screen session overlay offers Sleep, Reboot, and Shutdown. Sleep runs
immediately. Reboot and Shutdown require a second confirmation step. Arrow-key
focus navigation, Enter, mouse activation, outside click, and Escape are all
supported.

## macOS bar

`modules/home/sketchybar/` renders the status island on macOS with
[SketchyBar](https://felixkratz.github.io/SketchyBar/). Quickshell needs
Wayland layer-shell and Hyprland IPC, so only the data side is shared: the same
`notion-todos`, `work-tasks`, and `quickshell-timer` helpers from
`modules/home/bar-backends/` plus `herdr api snapshot` and `omp usage --json`.
`tomkoreny.sketchybar.enable = true` in `homes/aarch64-darwin/tom@macos`
turns it on; it enables `tomkoreny.bar-backends` itself and reads
`tomkoreny.bar-backends.workTasks` for the work provider.

The bar is transparent with a front-app island on the left and the status
island on the right, ordered herdr, timers, AI usage (one slot per account,
provider logo plus the same windows as the Linux bar), Notion tasks, work
tasks, clock, and battery. Every item runs `sketchybar-widgets <widget>`
(`widgets.py`) on its schedule; a click toggles the item's popup:

| Item | Popup rows | Row actions |
| --- | --- | --- |
| herdr | one row per pane: workspace, agent, status, title | click opens it with `herdr-view` in Ghostty |
| timers | `New timer…` (native text dialog, `20m pasta`), then each timer with its remaining time | click pauses or resumes, right-click cancels |
| AI usage | update age, account, every limit with reset time, `Refresh usage` | refresh runs `omp usage invalidate` |
| Notion tasks | counts header, `New task…` (same capture tokens as Linux), then today's and overdue tasks | click completes, right-click opens in Notion |
| work tasks | provider header, then actionable tasks with their status | click opens the issue |

Timer expiry and newly assigned work issues use macOS notifications through
`osascript`. Not ported: the task manager and editing views, work status
transitions, and the launcher.

The module sets the native menu bar to auto-hide (`_HIHideMenuBar`) and draws
the bar with `topmost=window`, because without a tiling window manager nothing
reserves the top strip. macOS only reads that default at login or when it gets
`AppleInterfaceMenuBarHidingChangedNotification`, so the `applyMenuBarHiding`
activation step posts it; without it the native bar keeps covering SketchyBar
until the next login. The native menu bar, Control Center, and app menus
slide in when the mouse touches the top edge. The launchd agent
`org.nix-community.home.sketchybar` logs to `~/Library/Logs/sketchybar.log`;
`sketchybar --reload` re-runs the installed `~/.config/sketchybar/sketchybarrc`.

## Configuration

The active host config enables the modules in
`homes/x86_64-linux/tom@nixos/default.nix`. A generic configuration is:

```nix
tomkoreny.quickshell-bar = {
  enable = true;
  outputs = [ "DP-1" "DP-2" ];
  primaryOutput = "DP-2";
  headsetFallbackSink = "alsa_output.pci-0000_01_00.1.hdmi-stereo";
};

tomkoreny.quickshell-osd = {
  enable = true;
  output = "DP-2";
  monitorSerial = "MONITOR-SERIAL";
};
```

`primaryOutput` must be present in `outputs`; both modules reject empty required
values during evaluation. New QML files must be added to the corresponding
`xdg.configFile` set and git-tracked before evaluating the flake.

## IPC and operations

Useful direct calls:

```bash
qs -c tom-bar ipc call launcher toggle
qs -c tom-bar ipc call launcher ai
qs -c tom-bar ipc call launcher clipboard
qs -c tom-bar ipc call launcher herdr
qs -c tom-bar ipc call launcher cameras
qs -c tom-bar ipc call timers popup
qs -c tom-bar ipc call volume popup
qs -c tom-bar ipc call headset settings
qs -c tom-bar ipc call todos toggle
qs -c tom-bar ipc call todos capture
qs -c tom-bar ipc call workTasks toggle
qs -c tom-bar ipc call notifications toggle
qs -c tom-osd ipc call media reveal
qs -c tom-osd ipc call session reveal
```

Service control and logs:

```bash
systemctl --user restart quickshell-bar.service quickshell-osd.service
systemctl --user status quickshell-bar.service quickshell-osd.service
qs -c tom-bar log -n -t 200
qs -c tom-osd log -n -t 200
```

Safe repository checks after a widget change:

```bash
nix build '.#homeConfigurations."tom@nixos".activationPackage'
nix flake check
```

For an actual UI change, also activate the Home Manager generation, restart the
relevant service, and exercise the changed surface. A successful Nix evaluation
does not prove QML interaction, monitor placement, focus, or compositor input.

## Source map

| File | Responsibility |
| --- | --- |
| `modules/home/bar-backends/default.nix` | Shared `tomkoreny.bar-backends` options, SOPS secrets, and the `quickshell-timer`, `notion-todos`, and `work-tasks` helper packages. |
| `modules/home/quickshell-bar/default.nix` | Home Manager options, substitutions, installed QML, and `quickshell-bar.service`. |
| `modules/home/quickshell-bar/shell.qml` | Bar windows, status widgets, component wiring, and `tom-bar` IPC. |
| `modules/home/quickshell-bar/Launcher.qml` | Launcher presentation, mode selection, ranking, keyboard behavior, calculator/converter UI. |
| `modules/home/quickshell-bar/LauncherData.qml` | Clipboard, Herdr, camera, and AI provider processes. |
| `modules/home/quickshell-bar/TimerService.qml` | Timer queue, ticking, expiry notification, and sound. |
| `modules/home/quickshell-bar/TimerPopup.qml` | Anchored timer creation and management UI. |
| `modules/home/quickshell-bar/VolumePopup.qml` | Sound popover: volume, mute, device choice, recording apps, and per-app volume. |
| `modules/home/quickshell-bar/HeadsetService.qml` | Runs `arctis.py`; exposes headset state, batteries, and last-set settings. |
| `modules/home/quickshell-bar/HeadsetAudioSwitch.qml` | Moves the default sink with the headset's power switch. |
| `modules/home/quickshell-bar/HeadsetDisplayFeed.qml` | Sends track changes to the base's OLED. |
| `modules/home/quickshell-bar/HeadsetSettingsPopup.qml` | Arctis base settings popover. |
| `modules/home/quickshell-bar/arctis.py` | Arctis base HID bridge: status, batteries, OLED drawing, and settings with delayed save. |
| `modules/home/bar-backends/timer-backend.py` | Locked, atomic timer state and duration parsing. |
| `modules/home/quickshell-bar/TodoService.qml` | Compact-widget data, five-minute refresh, optimistic completion, and undo. |
| `modules/home/quickshell-bar/TodoPanel.qml` | Persistent Today/Overdue panel. |
| `modules/home/quickshell-bar/TodoManager.qml` | Focused task views, capture, editing, assignment, completion, and reopen UI. |
| `modules/home/bar-backends/notion-todos.py` | Notion schema discovery, queries, mutations, caches, and completion journal. |
| `modules/home/quickshell-bar/WorkTaskService.qml` | Independent work cache, refresh, optimistic status changes, and assignment notifications. |
| `modules/home/quickshell-bar/WorkTaskManager.qml` | Focused work manager, local search, status filter, and workflow action menus. |
| `modules/home/bar-backends/work-tasks.py` | Provider-neutral CLI, atomic snapshot/baseline, and serialized refreshes/writes. |
| `modules/home/bar-backends/mantis_tasks.py` | Mantis REST identity, pagination, workflow/access metadata, ranking, and guarded status-only PATCH. |
| `modules/home/quickshell-bar/Notifications.qml` | Notification server, banners, history, DND, and centre. |
| `modules/home/quickshell-bar/NotificationCard.qml` | Shared banner/history card presentation and actions. |
| `modules/home/quickshell-osd/default.nix` | OSD options, `desktop-osd`, and `quickshell-osd.service`. |
| `modules/home/quickshell-osd/shell.qml` | Volume, brightness, media, and session overlays plus `tom-osd` IPC. |
| `modules/home/sketchybar/default.nix` | macOS `tomkoreny.sketchybar` module: plugin substitutions, rasterised provider logos, launchd agent, menu bar auto-hide. |
| `modules/home/sketchybar/sketchybarrc` | SketchyBar layout: islands, item order, separators, fonts, popup style. |
| `modules/home/sketchybar/widgets.py` | All macOS widgets: data fetch, labels, popup rows, row actions, notifications. |
