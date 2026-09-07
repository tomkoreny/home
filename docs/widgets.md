<!-- markdownlint-disable MD013 -->

# Desktop widgets

The desktop shell is split into two Quickshell configurations:

- `tom-bar` provides the multi-monitor bar, launcher, timers, Notion tasks,
  work tasks, and notifications.
- `tom-osd` provides volume and brightness indicators, the media popup, and the
  session menu.

Both are Linux-only Home Manager modules. Shared colours and fonts come from
`lib/common/default.nix`; see [theming.md](theming.md) before adding another
hard-coded visual convention.

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
| Herdr | Working-agent count and blocked count | Click to open the Herdr launcher mode; hover for the full working/blocked/idle summary. |
| Timers | Remaining time for the next running timer and `+N` for additional timers | Click to open the timer popup. |
| AI limits | OpenAI Codex weekly limit and Claude five-hour/weekly limits, including compact reset times | Click to invalidate and refresh OMP usage; hover for every reported limit and exact reset time. |
| Notion tasks | Today count and, when non-zero, overdue count | Click to open the focused task manager; hover for freshness or cache errors. |
| Work tasks | Briefcase and actionable assigned count; hidden at zero | Click to open the separate manager; hover for provider and freshness. |
| Audio | PipeWire default-sink volume and mute state | Click to open `pavucontrol`. |
| System tray | Quickshell system-tray items | Left click activates, middle click performs secondary activation, and right click opens the nested menu. |
| Clock | Time and abbreviated date | Click to toggle seconds; hover for the full date. |
| Notifications | Bell/DND state and unread badge | Click to open the notification centre. |
| Session | Power glyph | Click to open the session menu. |

Herdr is sampled every two seconds. AI limits and the compact Notion task list
refresh every five minutes; clicking either widget refreshes it immediately.
The Notion background refresh is intentionally the small `widget` query: Tom's
incomplete tasks due today or earlier. Unassigned and All tasks are fetched only
when those manager tabs open.

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

Enable the widget through `tomkoreny.quickshell-bar.workTasks`:

```nix
workTasks = {
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

## Configuration

The active host config enables the modules in
`homes/x86_64-linux/tom@nixos/default.nix`. A generic configuration is:

```nix
tomkoreny.quickshell-bar = {
  enable = true;
  outputs = [ "DP-1" "DP-2" ];
  primaryOutput = "DP-2";
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
| `modules/home/quickshell-bar/default.nix` | Home Manager options, substitutions, helper packages, installed QML, and `quickshell-bar.service`. |
| `modules/home/quickshell-bar/shell.qml` | Bar windows, status widgets, component wiring, and `tom-bar` IPC. |
| `modules/home/quickshell-bar/Launcher.qml` | Launcher presentation, mode selection, ranking, keyboard behavior, calculator/converter UI. |
| `modules/home/quickshell-bar/LauncherData.qml` | Clipboard, Herdr, camera, and AI provider processes. |
| `modules/home/quickshell-bar/TimerService.qml` | Timer queue, ticking, expiry notification, and sound. |
| `modules/home/quickshell-bar/TimerPopup.qml` | Anchored timer creation and management UI. |
| `modules/home/quickshell-bar/timer-backend.py` | Locked, atomic timer state and duration parsing. |
| `modules/home/quickshell-bar/TodoService.qml` | Compact-widget data, five-minute refresh, optimistic completion, and undo. |
| `modules/home/quickshell-bar/TodoPanel.qml` | Persistent Today/Overdue panel. |
| `modules/home/quickshell-bar/TodoManager.qml` | Focused task views, capture, editing, assignment, completion, and reopen UI. |
| `modules/home/quickshell-bar/notion-todos.py` | Notion schema discovery, queries, mutations, caches, and completion journal. |
| `modules/home/quickshell-bar/WorkTaskService.qml` | Independent work cache, refresh, optimistic status changes, and assignment notifications. |
| `modules/home/quickshell-bar/WorkTaskManager.qml` | Focused work manager, local search, status filter, and workflow action menus. |
| `modules/home/quickshell-bar/work-tasks.py` | Provider-neutral CLI, atomic snapshot/baseline, and serialized refreshes/writes. |
| `modules/home/quickshell-bar/mantis_tasks.py` | Mantis REST identity, pagination, workflow/access metadata, ranking, and guarded status-only PATCH. |
| `modules/home/quickshell-bar/Notifications.qml` | Notification server, banners, history, DND, and centre. |
| `modules/home/quickshell-bar/NotificationCard.qml` | Shared banner/history card presentation and actions. |
| `modules/home/quickshell-osd/default.nix` | OSD options, `desktop-osd`, and `quickshell-osd.service`. |
| `modules/home/quickshell-osd/shell.qml` | Volume, brightness, media, and session overlays plus `tom-osd` IPC. |
