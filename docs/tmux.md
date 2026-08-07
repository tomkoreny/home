# tmux manual

This documents the declaratively managed tmux setup for `tom` on NixOS (tmux 3.7b).

## Quick start

Opening Ghostty runs `mux`, which creates or attaches to a tmux session named `main`.

```console
mux                 # create or attach to the main session
mux work            # create or attach to a session named work
mux list            # list sessions; "mux ls" is equivalent
tmux attach -t work # attach using tmux directly
```

Inside tmux, press **Ctrl-b**, release it, and then press the command key. This manual writes that sequence as `C-b key`. For example, `C-b c` means:

1. Hold Ctrl and press b.
2. Release both keys.
3. Press c.

The prefix remains tmux's standard `C-b`. `M-` means Alt/Meta, so `C-b M-Left` means prefix followed by Alt-Left.

## Mental model

- A **server** owns all tmux state and processes.
- A **session** is a workspace, such as `main` or `work`.
- A **window** is like a terminal tab inside a session.
- A **pane** is one terminal region inside a window.
- A **client** is a visible terminal attached to a session.

Detaching a client does not stop its session, shells, or programs. This is tmux's main benefit: leave work running and return later.

## Everyday workflow

1. Open Ghostty; it attaches to `main` automatically.
2. Create a window with `C-b c`.
3. Split it with `C-b %` (left/right) or `C-b "` (top/bottom).
4. Move between panes with `C-b` plus an arrow key.
5. Detach with `C-b d`.
6. Return by opening Ghostty or running `mux`.

For a separate workspace, run `mux project-name`. If this is run from inside tmux, `mux` creates the session if needed and switches the current client to it.

Session names accepted by `mux` may contain letters, numbers, dots, dashes, and underscores.

## Essential keybindings

### Help and tmux itself

| Key | Action |
|---|---|
| `C-b ?` | Show all current prefix keybindings |
| `C-b /` | Prompt for a key and describe its binding |
| `C-b :` | Open the tmux command prompt |
| `C-b R` | Reload `~/.config/tmux/tmux.conf` |
| `C-b C-b` | Send a literal `C-b` to the program in the pane |
| `C-b ~` | Show tmux messages |

Press `q` to leave most chooser/help screens.

### Sessions and clients

| Key | Action |
|---|---|
| `C-b d` | Detach this client; work keeps running |
| `C-b s` | Choose a session interactively |
| `C-b $` | Rename the current session |
| `C-b (` / `C-b )` | Switch to the previous/next session |
| `C-b L` | Return to the last session |
| `C-b D` | Choose a client to detach |

### Windows

Windows and panes start at index **1**. Window numbers are automatically compacted after a window closes.

| Key | Action |
|---|---|
| `C-b c` | Create a window |
| `C-b 1` … `C-b 9` | Select a numbered window |
| `C-b n` / `C-b p` | Next/previous window |
| `C-b C-n` / `C-b C-p` | Next/previous window; added by tmux-sensible |
| `C-b l` or `C-b b` | Return to the last window |
| `C-b w` | Choose a window from a tree |
| `C-b ,` | Rename the current window |
| `C-b &` | Kill the current window after confirmation |
| `C-b .` | Move the current window to another index |
| `C-b Space` | Cycle through pane layouts |
| `C-b E` | Spread panes evenly |

Closing the shell in the last pane also closes its window. Killing a window terminates every process in all of its panes.

### Panes

| Key | Action |
|---|---|
| `C-b %` | Split into left and right panes |
| `C-b "` | Split into top and bottom panes |
| `C-b Arrow` | Select the pane in that direction |
| `C-b o` | Select the next pane |
| `C-b ;` | Return to the previously active pane |
| `C-b q` | Display pane numbers; press a shown number to select it |
| `C-b z` | Zoom/unzoom the active pane |
| `C-b x` | Kill the active pane after confirmation |
| `C-b {` / `C-b }` | Swap the pane up/down |
| `C-b C-Arrow` | Resize by one cell; repeatable |
| `C-b M-Arrow` | Resize by five cells; repeatable |
| `C-b >` | Open the pane menu |

## Scrolling, selection, and clipboard

The history limit is **100,000 lines per pane**, and copy mode uses vi keys.

### Keyboard workflow

1. Enter copy mode with `C-b [`.
2. Navigate with vi keys.
3. Press `Space` to begin a selection.
4. Move to extend the selection.
5. Press `Enter` to copy and leave copy mode.
6. Paste the newest tmux buffer with `C-b ]`.

Useful copy-mode keys:

| Key in copy mode | Action |
|---|---|
| `h j k l` | Move left/down/up/right |
| `w`, `b`, `e` | Move by words |
| `0`, `$`, `^` | Start/end/first non-blank character of line |
| `g` / `G` | Top/bottom of history |
| `C-u` / `C-d` | Half-page up/down |
| `C-b` / `C-f` | Page up/down |
| `/text` / `?text` | Search forward/backward |
| `n` / `N` | Repeat/reverse the last search |
| `Space` | Begin selection |
| `V` | Select a complete line |
| `v` | Toggle rectangular selection |
| `o` | Move to the other end of the selection |
| `Enter` | Copy selection and exit |
| `q` | Exit without copying |

`set-clipboard` is enabled. With Ghostty's OSC 52 support, text copied by tmux should also become the desktop clipboard contents. `C-b ]` always pastes from tmux's own buffer even if desktop clipboard integration is unavailable.

Other buffer commands:

| Key | Action |
|---|---|
| `C-b #` | List paste buffers |
| `C-b =` | Choose a buffer |
| `C-b -` | Delete the newest buffer |

## Mouse controls

Mouse mode is enabled.

- Click a pane to focus it.
- Drag a pane border to resize it.
- Use the wheel over a pane to enter/scroll copy mode.
- Drag over text to select it; releasing copies it.
- Double-click a word or triple-click a line to copy it.
- Middle-click a pane to paste the latest tmux buffer.
- Right-click a pane or status entry for tmux's context menu.
- Click a window in the status bar to select it.
- Scroll over the status bar to move through windows.

A full-screen program such as Neovim may handle mouse events itself. Terminal-level selection can usually be forced with Shift while dragging, depending on Ghostty's bindings.

## Saving and restoring sessions

The deployed setup uses:

- **tmux-resurrect** for snapshots;
- **tmux-continuum** to save every **10 minutes**;
- automatic restoration when a new tmux server starts.

| Key | Action |
|---|---|
| `C-b C-s` | Save a snapshot now |
| `C-b C-r` | Restore the latest snapshot now |

Snapshots are stored under `~/.tmux/resurrect/`.

A snapshot includes sessions, windows, panes, ordering, pane layouts, working directories, focus, and a conservative set of running programs. Resurrect only restarts these programs by default: `vi`, `vim`, `nvim`, `emacs`, `man`, `less`, `more`, `tail`, `top`, `htop`, `irssi`, `weechat`, and `mutt`. Other panes normally return as shells in their saved directories.

This is not process hibernation: unsaved editor state, generic application memory, and pane scrollback are not preserved. Pane-content capture is not enabled. Save important application data normally before rebooting.

## Shell command cheat sheet

```console
tmux list-sessions              # list sessions
tmux list-windows               # list windows in the attached session
tmux list-panes                 # list panes in the current window
tmux attach -t main             # attach to main
tmux detach                     # detach the current client
tmux rename-session -t old new  # rename a session
tmux kill-session -t work       # terminate one session and its processes
tmux kill-server                # terminate ALL sessions and their processes
```

Prefer detaching over killing. `tmux kill-server` is destructive.

## Deployed behavior and appearance

The active generated configuration currently provides:

- `C-b` prefix and tmux-sensible defaults;
- windows and panes numbered from 1;
- automatic window renumbering;
- vi keys in copy mode and the status prompts;
- mouse support;
- 24-hour clock;
- 100,000 lines of history per pane;
- a 10 ms escape delay;
- Catppuccin Mocha colors supplied by Stylix;
- `tmux-256color` and explicit Ghostty RGB/true-color support;
- terminal clipboard integration;
- resurrect and continuum persistence.

The sensible plugin also increases message visibility to four seconds, refreshes the status every five seconds, and supplies `C-b b` and `C-b R`.

## Configuration maintenance

The live config is:

```text
~/.config/tmux/tmux.conf
```

It is a Home Manager-managed symlink into the Nix store, so do **not** edit it directly. The rich tmux, `mux`, persistence, and Ghostty integration are declared in:

```text
modules/home/session-management/default.nix
```

The `tom@nixos` profile also enables tmux in:

```text
homes/x86_64-linux/tom@nixos/default.nix
```

After changing the declarative configuration, apply it with:

```console
home-manager switch --flake ".#tom@nixos"
```

Then use `C-b R` in an existing server if it has not picked up the new config. Use `tmux show-options -g` and `tmux list-keys` to inspect the effective running configuration rather than guessing which defaults or plugins won.