#!/usr/bin/env python3
"""SketchyBar plugin behind the macOS status island.

One script serves every widget so the bar items stay thin: SketchyBar runs
`widgets.py <widget>` on each item's schedule (routine, click, subscribed
event) and this script shells out to the same backends the Quickshell bar uses
on Linux (`notion-todos`, `work-tasks`, `quickshell-timer`, `herdr`, `omp`) and
pushes the result back with `sketchybar --set`. Popup rows are rebuilt from the
data while their popup is open, and row clicks come back here as
`widgets.py <widget> row ...`.
"""

import json
import math
import os
import re
import shlex
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

SKETCHYBAR = "@sketchybar@"
NOTION = "@notion@"
WORK = "@work@"  # empty when work tasks are disabled
WORK_LABEL = "@workLabel@"
TIMER = "@timer@"
HERDR = "@herdr@"
HERDR_VIEW = "@herdrView@"
OMP = "@omp@"
# <provider>-<tone>.png for every provider id and COLOR key: SketchyBar cannot
# tint images, so the logos are pre-rendered in each status colour.
LOGO_DIR = "@logoDir@"
AEROSPACE = "@aerospace@"  # empty when AeroSpace is disabled
COLOR = {
    "accent": "@accent@",
    "accentSurface": "@accentSurface@",
    "surface": "@surface@",
    "muted": "@muted@",
    "subdued": "@subdued@",
    "text": "@text@",
}

# Must match the space.* items in sketchybarrc and the AeroSpace bindings.
WORKSPACES = [str(number) for number in range(1, 11)] + ["S"]

AI_SLOTS = 4
AI_PROVIDERS = {"openai-codex": ("Codex", ["7d"]), "anthropic": ("Claude", ["5h", "7d"])}

ICON_CHECK = "\U000f012c"
ICON_CLOSE = "\U000f0156"
ICON_TIMER = "\U000f051b"
ICON_BRIEFCASE = "\uf0b1"
ICON_CLOCK = "\U000f0954"
ICON_CALENDAR = "\U000f00ed"
ICON_PLUS = "\U000f0415"
ICON_PAUSE = "\U000f03e4"
ICON_PLAY = "\U000f040a"
ICON_REFRESH = "\U000f0450"
ICON_BATTERY = ["\U000f008e"] + [chr(0xF007A + step) for step in range(9)] + ["\U000f0079"]
ICON_BATTERY_CHARGING = "\U000f0084"

CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "sketchybar-bar"
SELF = [sys.executable, os.path.abspath(__file__)]


# --- sketchybar plumbing -----------------------------------------------------


def sketchybar(*args: str) -> None:
    subprocess.run([SKETCHYBAR, *args], stdout=subprocess.DEVNULL, check=False)


def query(name: str) -> dict:
    result = subprocess.run([SKETCHYBAR, "--query", name], capture_output=True, text=True, check=False)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return {}


def popup_open(name: str) -> bool:
    return query(name).get("popup", {}).get("drawing") == "on"


def row_command(widget: str, *args: str) -> str:
    return " ".join(shlex.quote(part) for part in [*SELF, widget, *args])


def rebuild_popup(owner: str, rows: list[dict]) -> None:
    """Show `rows` in the popup of `owner` in one sketchybar call.

    Each row is {"label", "color"?, "icon"?, "click"?}; rows without a click
    command are inert headers. Rows are updated in place and surplus ones
    hidden, never removed: removing a popup's last item closes its window,
    and on SketchyBar 2.24 the window that comes back after re-adding rows
    stays below other windows (measured), so an open popup vanished on the
    first periodic refresh.
    """
    existing = set(query(owner).get("popup", {}).get("items") or [])
    args = []
    for index, row in enumerate(rows):
        name = f"{owner}.row.{index}"
        if name not in existing:
            args += ["--add", "item", name, f"popup.{owner}"]
        args += [
            "--set",
            name,
            "drawing=on",
            f"label={row['label']}",
            f"label.color={row.get('color', COLOR['text'])}",
            f"icon={row.get('icon', '')}",
            f"icon.color={row.get('color', COLOR['text'])}",
            f"click_script={row.get('click', '')}",
        ]
    for name in existing:
        suffix = name.removeprefix(f"{owner}.row.")
        if suffix.isdigit() and int(suffix) >= len(rows):
            args += ["--set", name, "drawing=off"]
    sketchybar(*args)
    mark_popup_change()


# Creating or resizing a popup window makes SketchyBar fire a burst of
# mouse.exited.global/entered.global events (measured: seven within 55ms, with
# the pointer nowhere near the bar). Exits inside this window are ignored so a
# popup opened from the keyboard is not closed by its own appearance.
POPUP_SETTLE_SECONDS = 1.0


def mark_popup_change() -> None:
    cache_path("popup-changed").touch()


def popup_settling() -> bool:
    try:
        return time.time() - cache_path("popup-changed").stat().st_mtime < POPUP_SETTLE_SECONDS
    except FileNotFoundError:
        return False


def notify(title: str, body: str, sound: bool = False) -> None:
    script = f'display notification {applescript(body)} with title {applescript(title)}'
    if sound:
        script += ' sound name "Glass"'
    subprocess.run(["/usr/bin/osascript", "-e", script], check=False)


def applescript(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def ask(title: str, prompt: str) -> str:
    """Text input through a native dialog; empty when cancelled."""
    script = (
        f"text returned of (display dialog {applescript(prompt)} default answer \"\""
        f" with title {applescript(title)} buttons {{\"Cancel\", \"OK\"}} default button \"OK\")"
    )
    result = subprocess.run(["/usr/bin/osascript", "-e", script], capture_output=True, text=True, check=False)
    return result.stdout.strip() if result.returncode == 0 else ""


def run_json(command: list[str], timeout: int = 45) -> dict | None:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"{command[0]}: {error}", file=sys.stderr)
        return None
    if result.returncode != 0:
        print(result.stderr.strip(), file=sys.stderr)
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def detach(command: list[str]) -> None:
    subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def open_url(url: str) -> None:
    if url:
        detach(["/usr/bin/open", url])


def cache_path(name: str) -> Path:
    CACHE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    return CACHE_DIR / name


def read_cache(name: str) -> dict | None:
    try:
        return json.loads(cache_path(name).read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def write_cache(name: str, payload: dict) -> None:
    cache_path(name).write_text(json.dumps(payload, separators=(",", ":")))


def format_duration(minutes: int) -> str:
    """Compact reset countdown, mirroring the Quickshell bar (no spaces)."""
    minutes = max(0, minutes)
    days, rest = divmod(minutes, 1440)
    hours, mins = divmod(rest, 60)
    if days:
        return f"{days}d{hours}h"
    if hours:
        return f"{hours}h{mins:02d}m"
    return f"{mins}m"


def format_remaining(milliseconds: int) -> str:
    seconds = max(0, math.ceil(milliseconds / 1000))
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes}:{secs:02d}"


def show(name: str, visible: bool, *settings: str) -> None:
    sketchybar("--set", name, f"drawing={'on' if visible else 'off'}", *settings)


def toggle_popup(name: str) -> bool:
    opened = not popup_open(name)
    sketchybar("--set", "/.*/", "popup.drawing=off")
    if opened:
        sketchybar("--set", name, "popup.drawing=on")
        mark_popup_change()
    return opened


# --- AeroSpace workspace strip -----------------------------------------------


def aerospace_lines(*args: str) -> list[list[str]]:
    result = subprocess.run([AEROSPACE, *args], capture_output=True, text=True, timeout=10, check=False)
    if result.returncode != 0:
        return []
    return [line.split("\t") for line in result.stdout.splitlines() if line]


def spaces(args: list[str]) -> None:
    """Show each monitor's occupied or visible workspaces, like WorkspaceStrip.qml."""
    if args[:1] == ["click"]:
        subprocess.run([AEROSPACE, "workspace", os.environ.get("NAME", "").removeprefix("space.")], check=False)
    workspaces = []
    if AEROSPACE:
        workspaces = aerospace_lines(
            "list-workspaces", "--monitor", "all",
            "--format", "%{workspace}%{tab}%{monitor-appkit-nsscreen-screens-id}%{tab}%{workspace-is-visible}",
        )
    occupied = {line[0] for line in aerospace_lines("list-workspaces", "--monitor", "all", "--empty", "no")} if AEROSPACE else set()
    state = {line[0]: (line[1], line[2] == "true") for line in workspaces if len(line) == 3}

    commands = []
    for name in WORKSPACES:
        item = f"space.{name}"
        display, visible = state.get(name, ("", False))
        if not display or not (visible or name in occupied):
            commands += ["--set", item, "drawing=off"]
            continue
        commands += [
            "--set", item, "drawing=on", f"display={display}",
            f"background.drawing={'on' if visible else 'off'}",
            f"icon.color={COLOR['accent'] if visible else COLOR['subdued']}",
        ]
    commands += ["--set", "sep.front_app", f"drawing={'on' if state else 'off'}"]

    # DesktopBar.qml's singleWindowMode: one tiled window on the focused
    # workspace turns the bar solid black and flattens both islands into it.
    # SketchyBar has one bar for all displays, so the focused monitor decides.
    tiled = [line for line in aerospace_lines("list-windows", "--workspace", "focused", "--format", "%{window-layout}")
             if line[0] != "floating"] if AEROSPACE else []
    single = len(tiled) == 1
    # Only touch the bar and islands when the mode flips: these handlers run
    # on every focus change, and a `--bar` update is suspected (not isolated)
    # of closing open popups.
    current = int(str(query("bar").get("color", "0x0")), 16)
    if (current == 0xFF000000) == single:
        sketchybar(*commands)
        return
    commands += ["--bar", f"color={'0xff000000' if single else '0x00000000'}"]
    for island in ("workspace", "status"):
        commands += [
            "--set", island,
            f"background.color={'0x00000000' if single else COLOR['surface']}",
            f"background.border_width={0 if single else 1}",
            f"background.corner_radius={0 if single else 8}",
        ]
    sketchybar(*commands)


# --- front app / clock / battery ---------------------------------------------


def front_app(args: list[str]) -> None:
    name = os.environ.get("INFO", "")
    if not name:
        result = subprocess.run(
            ["/usr/bin/osascript", "-e", 'tell application "System Events" to get name of first process whose frontmost is true'],
            capture_output=True,
            text=True,
            check=False,
        )
        name = result.stdout.strip()
    sketchybar("--set", "front_app", f"label={name}")


def clock(args: list[str]) -> None:
    now = datetime.now()
    if args[:1] == ["click"]:
        toggle_popup("clock")
    sketchybar("--set", "clock", f"label={ICON_CLOCK} {now:%H:%M}  {ICON_CALENDAR} {now:%a %-d %b}")
    if popup_open("clock"):
        rebuild_popup("clock", [{"label": f"{now:%A, %-d %B %Y}"}])


def battery(args: list[str]) -> None:
    result = subprocess.run(["/usr/bin/pmset", "-g", "batt"], capture_output=True, text=True, check=False)
    match = re.search(r"(\d+)%;\s*([a-z ]+?);", result.stdout)
    if not match:
        show("battery", False)
        return
    percent = int(match.group(1))
    state = match.group(2).strip()
    charging = state in ("charging", "finishing charge", "charged") or "AC Power" in result.stdout
    icon = ICON_BATTERY_CHARGING if charging else ICON_BATTERY[min(10, round(percent / 10))]
    color = COLOR["muted"] if percent <= 15 and not charging else COLOR["text"]
    show("battery", True, f"label={icon} {percent}%", f"label.color={color}")


# --- herdr -------------------------------------------------------------------


def herdr(args: list[str]) -> None:
    if args[:1] == ["row"]:
        detach([HERDR_VIEW, args[1]])
        sketchybar("--set", "herdr", "popup.drawing=off")
        return
    opened = toggle_popup("herdr") if args[:1] == ["click"] else popup_open("herdr")

    payload = run_json([HERDR, "api", "snapshot"], timeout=10)
    snapshot = (payload or {}).get("result", {}).get("snapshot") if payload else None
    if not isinstance(snapshot, dict):
        sketchybar("--set", "herdr", "label=π –", f"label.color={COLOR['subdued']}")
        if opened:
            rebuild_popup("herdr", [{"label": "Herdr · unavailable", "color": COLOR["subdued"]}])
        return

    agents = snapshot.get("agents") or []
    working = sum(1 for agent in agents if agent.get("agent_status") == "working")
    blocked = sum(1 for agent in agents if agent.get("agent_status") == "blocked")
    idle = sum(1 for agent in agents if agent.get("agent_status") in ("idle", "done"))
    label = f"π {working}  {ICON_CLOSE} {blocked}" if blocked else f"π {working}"
    color = COLOR["muted"] if blocked else COLOR["accent"] if working else COLOR["subdued"]
    sketchybar("--set", "herdr", f"label={label}", f"label.color={color}")

    if not opened:
        return
    parts = [f"{count} {word}" for count, word in ((working, "working"), (blocked, "blocked"), (idle, "idle")) if count]
    rows = [{"label": "Herdr · " + (" · ".join(parts) if parts else "no agents"), "color": COLOR["subdued"]}]
    workspaces = {ws.get("workspace_id"): ws.get("label") for ws in snapshot.get("workspaces") or []}
    for pane in snapshot.get("panes") or []:
        pane_id = pane.get("pane_id", "")
        title = pane.get("terminal_title_stripped") or pane.get("terminal_title") or pane_id
        workspace = workspaces.get(pane.get("workspace_id")) or pane.get("workspace_id", "")
        status = pane.get("agent_status") or "terminal"
        agent = pane.get("agent") or "terminal"
        status_color = {"working": COLOR["accent"], "blocked": COLOR["muted"]}.get(status, COLOR["text"])
        rows.append(
            {
                "label": f"{workspace} · {agent} · {status}   {title[:60]}",
                "color": status_color,
                "click": row_command("herdr", "row", pane_id),
            }
        )
    rebuild_popup("herdr", rows)


# --- timers ------------------------------------------------------------------


def timer_snapshot(command: list[str]) -> dict | None:
    """Run a timer command; `tick` also sweeps expired timers and announces them."""
    snapshot = run_json([TIMER, *command], timeout=10)
    if snapshot is None:
        return None
    for expired in snapshot.get("expired", []):
        notify("Timer finished", expired["name"], sound=True)
    return snapshot


def timers(args: list[str]) -> None:
    command = ["tick"]
    if args[:1] == ["new"]:
        query_text = ask("New timer", "Duration and name, for example 20m pasta")
        if not query_text:
            return
        command = ["add", query_text]
    elif args[:1] == ["row"]:
        button = os.environ.get("BUTTON", "left")
        timer_id, paused = args[1], args[2] == "paused"
        command = ["cancel", timer_id] if button == "right" else ["resume" if paused else "pause", timer_id]
    opened = toggle_popup("timers") if args[:1] == ["click"] else popup_open("timers")

    snapshot = timer_snapshot(command)
    if snapshot is None:
        sketchybar("--set", "timers", f"label={ICON_TIMER} !", f"label.color={COLOR['muted']}")
        return
    now = snapshot["now"]
    active = snapshot["timers"]
    running = [t for t in active if not t["paused"]]
    if running:
        head = running[0]
        label = f"{ICON_TIMER} {format_remaining(head['deadlineMs'] - now)}"
        if len(active) > 1:
            label += f" +{len(active) - 1}"
        color = COLOR["accent"]
    else:
        label, color = ICON_TIMER, COLOR["subdued"]
    sketchybar("--set", "timers", f"label={label}", f"label.color={color}")

    if not opened:
        return
    rows = [{"label": "New timer…", "icon": ICON_PLUS, "color": COLOR["accent"], "click": row_command("timers", "new")}]
    for timer in active:
        remaining = timer["remainingMs"] if timer["paused"] else timer["deadlineMs"] - now
        rows.append(
            {
                "label": f"{timer['name']}  {format_remaining(remaining)}   (click pauses, right-click cancels)",
                "icon": ICON_PLAY if timer["paused"] else ICON_PAUSE,
                "color": COLOR["subdued"] if timer["paused"] else COLOR["text"],
                "click": row_command("timers", "row", timer["id"], "paused" if timer["paused"] else "running"),
            }
        )
    rebuild_popup("timers", rows)


# --- AI usage ----------------------------------------------------------------


def ai_accounts(payload: dict) -> list[dict]:
    accounts = []
    for index, report in enumerate(payload.get("reports") or []):
        provider = report.get("provider")
        if provider not in AI_PROVIDERS:
            continue
        limits = [
            limit
            for limit in report.get("limits") or []
            if isinstance((limit.get("amount") or {}).get("remaining"), (int, float))
        ]
        if not limits:
            continue
        metadata = report.get("metadata") or {}
        accounts.append(
            {
                "provider": provider,
                "email": metadata.get("email") or "",
                "key": f"{provider}:{metadata.get('accountId') or metadata.get('email') or index}",
                "limits": limits,
            }
        )
    order = list(AI_PROVIDERS)
    accounts.sort(key=lambda account: (order.index(account["provider"]), account["email"]))
    return accounts


def ai_window(account: dict, window_id: str) -> dict:
    for limit in account["limits"]:
        scope = limit.get("scope") or {}
        if scope.get("windowId") == window_id and not scope.get("tier") and not scope.get("modelId"):
            return {"remaining": limit["amount"]["remaining"], "resetsAt": (limit.get("window") or {}).get("resetsAt")}
    return {"remaining": None, "resetsAt": None}


def ai_tone(remaining: float | None) -> str:
    if remaining is None:
        return "subdued"
    if remaining <= 10:
        return "muted"
    if remaining <= 25:
        return "accent"
    return "text"


def label_width(name: str) -> int:
    """Rendered width of an item whose label is its only content."""
    rects = query(name).get("bounding_rects") or {}
    return max((int(rect["size"][0]) for rect in rects.values()), default=0)


def stack_lines(slot: int, lines: list[tuple[str, str]]) -> None:
    """Draw one or two lines in the ai.N.top/ai.N.bot pair, left-aligned.

    SketchyBar labels are single-line, so the top line is a zero-width item
    anchored at the bottom item's right edge that draws leftward over it; both
    labels then get the wider of the two measured widths. The zero-width top
    item does not push the bottom one, so both carry the same 6pt gap to the
    separator and end at the same x.
    """
    top, bottom = f"ai.{slot}.top", f"ai.{slot}.bot"
    if len(lines) == 1:
        text, tone = lines[0]
        sketchybar(
            "--set", top, "drawing=off",
            "--set", bottom, "drawing=on", "padding_right=6", f"label={text}", f"label.color={COLOR[tone]}",
            "label.y_offset=0", "label.width=dynamic",
        )
        return
    (first, first_tone), (second, second_tone) = lines
    sketchybar(
        "--set", top, "drawing=on", "padding_right=6", f"label={first}", f"label.color={COLOR[first_tone]}",
        "label.y_offset=5", "label.width=dynamic",
        "--set", bottom, "drawing=on", "padding_right=6", f"label={second}", f"label.color={COLOR[second_tone]}",
        "label.y_offset=-5", "label.width=dynamic",
    )
    width = max(label_width(top), label_width(bottom))
    sketchybar("--set", top, f"label.width={width}", "--set", bottom, f"label.width={width}")


def ai_usage(args: list[str]) -> None:
    # Clicks can land on the logo (ai.N) or either text line (ai.N.top/bot).
    name = ".".join(os.environ.get("NAME", "ai.0").split(".")[:2])
    if args[:1] == ["refresh"]:
        subprocess.run([OMP, "usage", "invalidate"], capture_output=True, check=False)
        sketchybar("--set", "/.*/", "popup.drawing=off")
    opened_name = None
    if args[:1] == ["click"]:
        opened_name = name if toggle_popup(name) else None
    else:
        opened_name = next((f"ai.{slot}" for slot in range(AI_SLOTS) if popup_open(f"ai.{slot}")), None)

    payload = run_json([OMP, "usage", "--json"], timeout=50)
    stale = payload is None
    if payload is None:
        payload = read_cache("ai-usage.json") or {}
    else:
        write_cache("ai-usage.json", payload)
    accounts = ai_accounts(payload)
    now = int(time.time() * 1000)
    generated = payload.get("generatedAt") or now

    for slot in range(AI_SLOTS):
        item = f"ai.{slot}"
        if slot >= len(accounts):
            sketchybar(*[arg for part in (item, f"{item}.top", f"{item}.bot") for arg in ("--set", part, "drawing=off")])
            continue
        account = accounts[slot]
        provider_label, windows = AI_PROVIDERS[account["provider"]]
        lines = []
        worst = None
        for window_id in windows:
            window = ai_window(account, window_id)
            icon = ICON_TIMER if window_id == "5h" else ICON_CALENDAR
            if window["remaining"] is None:
                lines.append([f"{icon} --", "subdued"])
            else:
                reset = format_duration((window["resetsAt"] - now) // 60_000) if window["resetsAt"] else "--"
                lines.append([f"{icon} {round(window['remaining'])}% {reset}", ai_tone(window["remaining"])])
                worst = window["remaining"] if worst is None else min(worst, window["remaining"])
        if stale:
            lines[-1][0] += f" {ICON_CLOSE}"
        show(item, True, f"icon.background.image={LOGO_DIR}/{account['provider']}-{ai_tone(worst)}.png")
        stack_lines(slot, [tuple(line) for line in lines])
        if opened_name != item:
            continue
        age = format_duration((now - generated) // 60_000)
        rows = [
            {"label": f"AI limits · updated {age} ago" + (" · stale" if stale else ""), "color": COLOR["subdued"]},
            {"label": f"{provider_label} · {account['email']}", "color": COLOR["accent"]},
        ]
        for limit in account["limits"]:
            resets_at = (limit.get("window") or {}).get("resetsAt")
            if resets_at:
                when = datetime.fromtimestamp(resets_at / 1000)
                reset = f"resets in {format_duration((resets_at - now) // 60_000)} ({when:%a %-d %b %H:%M})"
            else:
                reset = "reset unavailable"
            rows.append({"label": f"{limit.get('label', '?')} · {round(limit['amount']['remaining'])}% · {reset}"})
        rows.append({"label": "Refresh usage", "icon": ICON_REFRESH, "color": COLOR["accent"], "click": row_command("ai", "refresh")})
        rebuild_popup(item, rows)


# --- Notion todos ------------------------------------------------------------


def todo_sort_key(item: dict) -> tuple:
    return (item.get("due") or "9999-99-99", (item.get("title") or "").lower())


def todos(args: list[str]) -> None:
    command = None
    if args[:1] == ["new"]:
        text = ask("New Notion task", "Task title; @today, @fri, @2026-10-01 and !high/!low set due date and priority")
        if not text:
            return
        command = ["create", text]
    elif args[:1] == ["row"]:
        cached = read_cache("todos.json") or {}
        item = next((entry for entry in cached.get("items", []) if entry.get("id") == args[1]), {})
        if os.environ.get("BUTTON", "left") == "right":
            open_url(item.get("url", ""))
            return
        command = ["complete", args[1]]
    opened = toggle_popup("todos") if args[:1] == ["click"] else popup_open("todos")

    if command:
        result = run_json([NOTION, *command])
        if result is None:
            notify("Notion", f"{command[0]} failed")
    payload = run_json([NOTION, "list"]) or {"items": [], "stale": True, "error": "notion-todos failed"}
    items = sorted(payload.get("items") or [], key=todo_sort_key)
    write_cache("todos.json", {"items": items})
    today = datetime.now().strftime("%Y-%m-%d")
    today_count = sum(1 for item in items if item.get("due") == today)
    overdue_count = sum(1 for item in items if item.get("overdue"))
    label = f"{ICON_CHECK} {today_count}  {ICON_CLOSE} {overdue_count}" if overdue_count else f"{ICON_CHECK} {today_count}"
    color = COLOR["muted"] if overdue_count else COLOR["accent"] if today_count else COLOR["subdued"]
    sketchybar("--set", "todos", f"label={label}", f"label.color={color}")

    if not opened:
        return
    if payload.get("stale"):
        header = f"Notion tasks · stale · {payload.get('error') or 'waiting for refresh'}"
    else:
        header = f"{overdue_count} overdue · {today_count} today · click completes, right-click opens"
    rows = [
        {"label": header, "color": COLOR["subdued"]},
        {"label": "New task…", "icon": ICON_PLUS, "color": COLOR["accent"], "click": row_command("todos", "new")},
    ]
    for item in items:
        due = item.get("due") or ""
        rows.append(
            {
                "label": f"{item.get('title', '')[:70]}   {due}",
                "icon": ICON_CLOSE if item.get("overdue") else ICON_CHECK,
                "color": COLOR["muted"] if item.get("overdue") else COLOR["text"],
                "click": row_command("todos", "row", item.get("id", "")),
            }
        )
    rebuild_popup("todos", rows)


# --- work tasks --------------------------------------------------------------


def work(args: list[str]) -> None:
    if not WORK:
        show("work", False)
        show("sep.work", False)
        return
    if args[:1] == ["row"]:
        open_url(args[1])
        sketchybar("--set", "work", "popup.drawing=off")
        return
    opened = toggle_popup("work") if args[:1] == ["click"] else popup_open("work")

    payload = run_json([WORK, "list"], timeout=55) or {"items": [], "stale": True, "error": "work-tasks failed", "events": []}
    for event in payload.get("events") or []:
        if event.get("kind") == "assigned":
            notify("Assigned to you", event.get("title", ""))
    items = [item for item in payload.get("items") or [] if item.get("actionable")]
    stale = bool(payload.get("stale"))
    visible = bool(items)
    label = f"{ICON_BRIEFCASE} {len(items)}" + (" !" if stale else "")
    color = COLOR["muted"] if stale else COLOR["accent"]
    show("work", visible, f"label={label}", f"label.color={color}")
    show("sep.work", visible)

    if not opened or not visible:
        return
    if stale:
        header = f"{WORK_LABEL} · stale · {payload.get('error') or 'waiting for refresh'}"
    else:
        header = f"{WORK_LABEL} · {len(items)} actionable tasks assigned to you · click opens"
    rows = [{"label": header, "color": COLOR["subdued"]}]
    for item in items:
        rows.append(
            {
                "label": f"{item.get('title', '')[:70]}   {item.get('statusName', '')}",
                "click": row_command("work", "row", item.get("url", "")),
            }
        )
    rebuild_popup("work", rows)


WIDGETS = {
    "spaces": spaces,
    "front_app": front_app,
    "clock": clock,
    "battery": battery,
    "herdr": herdr,
    "timers": timers,
    "ai": ai_usage,
    "todos": todos,
    "work": work,
}


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in WIDGETS:
        print(f"usage: widgets.py {{{'|'.join(WIDGETS)}}} [action ...]", file=sys.stderr)
        sys.exit(2)
    if os.environ.get("SENDER") == "mouse.exited.global":
        if not popup_settling():
            sketchybar("--set", "/.*/", "popup.drawing=off")
        return
    WIDGETS[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
