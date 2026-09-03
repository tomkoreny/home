#!/usr/bin/env python3
import argparse
import fcntl
import json
import os
import re
import tempfile
import time
import uuid
from contextlib import contextmanager
from pathlib import Path


def state_home() -> Path:
    configured = os.environ.get("XDG_STATE_HOME")
    return Path(configured) if configured else Path.home() / ".local" / "state"


STATE_DIR = state_home() / "quickshell-bar"
STATE_FILE = STATE_DIR / "timers.json"
LOCK_FILE = STATE_DIR / "timers.lock"
BOOT_ID = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
DURATION_PART = re.compile(r"\s*(\d+)\s*([dhms])", re.IGNORECASE)
UNIT_SECONDS = {"d": 86400, "h": 3600, "m": 60, "s": 1}


def now_ms() -> int:
    return int(time.time() * 1000)


def empty_state() -> dict:
    return {"bootId": BOOT_ID, "timers": []}


def load_state() -> dict:
    try:
        state = json.loads(STATE_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return empty_state()
    if state.get("bootId") != BOOT_ID or not isinstance(state.get("timers"), list):
        return empty_state()
    return state


def save_state(state: dict) -> None:
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="timers.", dir=STATE_DIR)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(state, stream, separators=(",", ":"))
            stream.write("\n")
        os.replace(temporary, STATE_FILE)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


@contextmanager
def locked_state():
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    with LOCK_FILE.open("a+") as lock:
        os.chmod(LOCK_FILE, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load_state()
        yield state
        save_state(state)


def parse_timer(query: str) -> tuple[int, str]:
    position = 0
    seconds = 0
    matched = False
    while match := DURATION_PART.match(query, position):
        matched = True
        seconds += int(match.group(1)) * UNIT_SECONDS[match.group(2).lower()]
        position = match.end()
    if not matched or seconds < 1:
        raise ValueError("Use a duration such as 20m, 1h 30m, or 45s")
    if seconds > 7 * 86400:
        raise ValueError("Timers cannot exceed seven days")
    name = query[position:].strip() or "Timer"
    return seconds * 1000, name


def public_timer(timer: dict, timestamp: int) -> dict:
    remaining = timer["remainingMs"] if timer["paused"] else max(0, timer["deadlineMs"] - timestamp)
    return {
        "id": timer["id"],
        "name": timer["name"],
        "durationMs": timer["durationMs"],
        "deadlineMs": timer["deadlineMs"] if not timer["paused"] else 0,
        "remainingMs": remaining,
        "paused": timer["paused"],
    }


def response(state: dict, expired: list[dict] | None = None) -> dict:
    timestamp = now_ms()
    timers = [public_timer(timer, timestamp) for timer in state["timers"]]
    timers.sort(key=lambda timer: (timer["paused"], timer["remainingMs"], timer["name"].lower()))
    return {"now": timestamp, "timers": timers, "expired": expired or []}


def find_timer(state: dict, timer_id: str) -> dict:
    for timer in state["timers"]:
        if timer["id"] == timer_id:
            return timer
    raise ValueError("Timer no longer exists")


def run(args: argparse.Namespace) -> dict:
    with locked_state() as state:
        timestamp = now_ms()
        if args.command == "add":
            duration, name = parse_timer(args.query)
            state["timers"].append({
                "id": uuid.uuid4().hex[:12],
                "name": name,
                "durationMs": duration,
                "deadlineMs": timestamp + duration,
                "remainingMs": duration,
                "paused": False,
            })
            return response(state)

        if args.command == "pause":
            timer = find_timer(state, args.timer_id)
            if not timer["paused"]:
                timer["remainingMs"] = max(0, timer["deadlineMs"] - timestamp)
                timer["paused"] = True
            return response(state)

        if args.command == "resume":
            timer = find_timer(state, args.timer_id)
            if timer["paused"]:
                timer["deadlineMs"] = timestamp + timer["remainingMs"]
                timer["paused"] = False
            return response(state)

        if args.command == "cancel":
            timer = find_timer(state, args.timer_id)
            state["timers"].remove(timer)
            return response(state)

        expired = []
        if args.command == "tick":
            active = []
            for timer in state["timers"]:
                if not timer["paused"] and timer["deadlineMs"] <= timestamp:
                    expired.append({"id": timer["id"], "name": timer["name"]})
                else:
                    active.append(timer)
            state["timers"] = active
        return response(state, expired)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="quickshell-timer")
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("list")
    commands.add_parser("tick")
    add = commands.add_parser("add")
    add.add_argument("query")
    for name in ("pause", "resume", "cancel"):
        command = commands.add_parser(name)
        command.add_argument("timer_id")
    return root


def main() -> None:
    args = parser().parse_args()
    try:
        print(json.dumps(run(args), separators=(",", ":")))
    except ValueError as error:
        print(str(error), file=os.sys.stderr)
        raise SystemExit(2) from error


if __name__ == "__main__":
    main()
