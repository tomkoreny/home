"""Rebalance dwindle on playback/placement changes, never on focus changes."""

import argparse
import asyncio
import json
import math
import os
import socket
import time
from pathlib import Path

from aspect_x11 import AspectHints
from inotify_simple import INotify, flags
from Xlib import error as xerror

RUNTIME = Path(os.environ["XDG_RUNTIME_DIR"]) / "hyprland-aspect"
FIT_SCRIPT = "@fitScript@"
EVENTS = {
    "openwindow",
    "closewindow",
    "movewindowv2",
    "changefloatingmode",
    "fullscreen",
    "windowtitlev2",
    "monitoraddedv2",
    "monitorremoved",
    "moveworkspacev2",
    "configreloaded",
}


async def ipc(command):
    path = (
        Path(os.environ["XDG_RUNTIME_DIR"])
        / "hypr"
        / os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
        / ".socket.sock"
    )
    reader, writer = await asyncio.open_unix_connection(path)
    try:
        writer.write(command.encode())
        await writer.drain()
        return (await asyncio.wait_for(reader.read(), 5)).decode()
    finally:
        writer.close()
        await writer.wait_closed()


def mpv_ratios():
    result = {}
    # Do not apply a leftover file to a different process after PID reuse.
    boot = time.time() - time.clock_gettime(time.CLOCK_BOOTTIME)
    ticks = os.sysconf("SC_CLK_TCK")
    for path in RUNTIME.glob("mpv-*.json"):
        try:
            data = json.loads(path.read_text())
            pid, aspect = data["pid"], data["aspect"]
            if type(pid) is not int or path.name != f"mpv-{pid}.json":
                continue
            if (
                not isinstance(aspect, (int, float))
                or not math.isfinite(aspect)
                or aspect <= 0
            ):
                continue
            stat = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
            started = boot + int(stat[19]) / ticks
            if path.stat().st_mtime >= started - 1:
                result[pid] = aspect
        except (OSError, ValueError, KeyError, IndexError, TypeError):
            continue
    return result


async def playback_state(hints):
    clients = json.loads(await ipc("j/clients"))
    mpv, x11 = mpv_ratios(), hints.ratios()
    result = {}
    for client in clients:
        if (
            not client["mapped"]
            or client["hidden"]
            or client["floating"]
            or client["fullscreen"]
        ):
            continue
        # The publisher identifies the mpv process even when a launcher sets
        # a custom app ID (e.g. WebPlayback) or changes the window title.
        ratio = mpv.get(client["pid"])
        if ratio is None and client["class"] == "multiviewer" and client["xwayland"]:
            ratio = x11.get((client["pid"], client["title"]))
        if ratio is not None:
            result[client["address"]] = ratio
    return clients, result


async def fit(ratios):
    if not ratios:
        return ratios
    # Both address strings and the path are generated locally, not window titles.
    values = ",".join(
        f"[{json.dumps(address)}]={ratio:.12g}" for address, ratio in ratios.items()
    )
    command = f"eval local fit = dofile({json.dumps(FIT_SCRIPT)}); fit({{{values}}})"
    response = await ipc(command)
    if response.strip() != "ok":
        raise RuntimeError(f"aspect fitting failed: {response.strip()}")
    return ratios


def placement_state(clients, ratios):
    workspaces = {c["workspace"]["id"] for c in clients if c["address"] in ratios}
    return sorted(ratios.items()), sorted(
        (
            c["address"],
            c["workspace"]["id"],
            c["monitor"],
            c["at"],
            c["size"],
            c["floating"],
            c["fullscreen"],
            c["hidden"],
            c["mapped"],
        )
        for c in clients
        if c["workspace"]["id"] in workspaces
    )


async def watch():
    RUNTIME.mkdir(mode=0o700, exist_ok=True)
    loop = asyncio.get_running_loop()
    changed = asyncio.Event()
    failed = loop.create_future()
    notify = INotify(nonblocking=True)
    notify.add_watch(str(RUNTIME), flags.MOVED_TO | flags.CLOSE_WRITE | flags.DELETE)
    hints = AspectHints()
    hints.refresh()
    trigger = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    trigger_path = RUNTIME / "trigger.sock"
    trigger_path.unlink(missing_ok=True)
    trigger.bind(str(trigger_path))
    trigger.setblocking(False)

    def metadata_changed():
        if any(
            event.name.startswith("mpv-") and event.name.endswith(".json")
            for event in notify.read(timeout=0)
        ):
            changed.set()

    def x11_changed():
        try:
            if hints.drain():
                changed.set()
        except (OSError, xerror.ConnectionClosedError, xerror.XError) as error:
            loop.remove_reader(hints.fileno())
            failed.set_exception(error)

    def triggered():
        trigger.recv(1024)
        changed.set()

    loop.add_reader(notify.fileno(), metadata_changed)
    loop.add_reader(hints.fileno(), x11_changed)
    loop.add_reader(trigger.fileno(), triggered)

    async def events():
        path = (
            Path(os.environ["XDG_RUNTIME_DIR"])
            / "hypr"
            / os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
            / ".socket2.sock"
        )
        reader, writer = await asyncio.open_unix_connection(path)
        try:
            while line := await reader.readline():
                if line.decode().partition(">>")[0] in EVENTS:
                    changed.set()
            raise ConnectionError("Hyprland event socket closed")
        finally:
            writer.close()
            await writer.wait_closed()

    async def rebalance():
        last_state = None
        changed.set()
        while True:
            await changed.wait()
            # Coalesce map/title/hints bursts, including late playback metadata.
            await asyncio.sleep(0.15)
            changed.clear()
            clients, ratios = await playback_state(hints)
            state = placement_state(clients, ratios)
            if state != last_state:
                await fit(ratios)
                # Ignore duplicate title/hints notifications and our own resize
                # effects. Focus alone must never keep refining an imperfect fit.
                clients = json.loads(await ipc("j/clients"))
                last_state = placement_state(clients, ratios)

    async def metadata_failure():
        await failed

    print("Watching playback aspect metadata and Hyprland placement events", flush=True)
    try:
        async with asyncio.TaskGroup() as group:
            group.create_task(events())
            group.create_task(rebalance())
            group.create_task(metadata_failure())
    finally:
        for fd in (notify.fileno(), hints.fileno(), trigger.fileno()):
            loop.remove_reader(fd)
        notify.close()
        hints.close()
        trigger.close()
        trigger_path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--inspect",
        action="store_true",
        help="print recognized playback aspect ratios without resizing",
    )
    mode.add_argument(
        "--once",
        action="store_true",
        help="rebalance once and print recognized playback ratios",
    )
    mode.add_argument(
        "--trigger",
        action="store_true",
        help="request rebalancing after an explicit layout operation",
    )
    args = parser.parse_args()
    if args.trigger:
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as trigger:
            trigger.sendto(b"fit", str(RUNTIME / "trigger.sock"))
    elif args.inspect or args.once:
        hints = AspectHints()
        try:
            hints.refresh()

            async def once():
                _, ratios = await playback_state(hints)
                if args.once:
                    await fit(ratios)
                return ratios

            print(json.dumps(asyncio.run(once()), indent=2))
        finally:
            hints.close()
    else:
        asyncio.run(watch())


if __name__ == "__main__":
    main()
