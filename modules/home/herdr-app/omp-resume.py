#!/usr/bin/env python3
"""Reopen OMP sessions in Herdr app terminals after herdr-core loses them.

herdr-core keeps the terminals of the Herdr app. When the core stops (a reboot,
a logout, a crash), each kept terminal comes back under its old address as a
plain shell in its old folder; the program that ran in it is gone. An OMP
conversation is still on disk then, but nothing reopens it.

While terminals are alive, this records for each address the session file of
the OMP running in it. OMP names that file itself: it writes
~/.omp/agent/terminal-sessions/<pty> (the folder, then the session file)
whenever a session starts or changes, so two sessions in one folder are never
confused. When a recorded terminal is later found recreated with only its
shell in it, `omp --resume <file>` is typed into it.

A terminal counts as recreated when its shell is a different process from the
recorded one. OMP gone from the same shell means the user quit it, and the
record is dropped. At most one session is resumed per pass, so a restart does
not start every OMP at once. The core is never started from here: nothing
happens until the app or `hc` has started it.

usage: omp-resume.py HC
"""

from __future__ import annotations

import json
import os
import shlex
import socket
import subprocess
import sys
import time
from pathlib import Path

INTERVAL = 3  # seconds between passes
RESUME_WINDOW = 600  # a recreated terminal still busy after this is the user's
SETTLE = 30  # after typing a resume, let OMP start before judging the shell
FORGET_AFTER = 30 * 86400  # records of terminals that never came back

HC = sys.argv[1] if len(sys.argv) > 1 else "hc"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
CORE_SOCKET = RUNTIME / "herdr-core" / "default.sock"
STATE = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state") / "herdr-omp-resume/terminals.json"
CRUMBS = Path.home() / ".omp/agent/terminal-sessions"
BOOT = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
BOOT_TIME = next(int(line.split()[1]) for line in Path("/proc/stat").read_text().splitlines() if line.startswith("btime "))
TICKS = os.sysconf("SC_CLK_TCK")


def log(message: str) -> None:
    print(message, flush=True)


def core_running() -> bool:
    """Whether a core answers on its socket. Calling `hc` would start one."""
    try:
        with socket.socket(socket.AF_UNIX) as probe:
            probe.settimeout(2)
            probe.connect(str(CORE_SOCKET))
        return True
    except OSError:
        return False


def hc(*args: str) -> dict:
    # `hc send` holds a message while the terminal has an unsent draft, for up to a minute.
    result = subprocess.run([HC, *args, "--json"], capture_output=True, text=True, timeout=90)
    if result.returncode != 0:
        raise RuntimeError(f"hc {' '.join(args)}: {result.stderr.strip() or result.stdout.strip()}")
    return json.loads(result.stdout)


def start_ticks(pid: int) -> int | None:
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
    except OSError:
        return None
    return int(stat[stat.rindex(")") + 2:].split()[19])


def process_id(pid: int) -> str | None:
    """A name for a process that a reused pid or another boot cannot match."""
    ticks = start_ticks(pid)
    return None if ticks is None else f"{BOOT}:{pid}:{ticks}"


def pty_of(pid: int) -> str | None:
    try:
        tty = os.readlink(f"/proc/{pid}/fd/0")
    except OSError:
        return None
    return "pts-" + tty.removeprefix("/dev/pts/") if tty.startswith("/dev/pts/") else None


def crumb_session(pty: str, since: float) -> tuple[bool, str | None]:
    """(OMP wrote a crumb for this pty since `since`, its session file if that exists)."""
    crumb = CRUMBS / pty
    try:
        if crumb.stat().st_mtime < since:
            return False, None
        lines = crumb.read_text(errors="replace").split("\n")
    except OSError:
        return False, None
    if len(lines) < 2 or not lines[1]:
        return False, None
    return True, lines[1] if os.path.isfile(lines[1]) else None


def note_omp(address: str, records: dict, now: float) -> None:
    """Record, or refresh, the session of the OMP running in a terminal."""
    record = records.get(address)
    if not record or process_id(record["shell_pid"]) != record["shell"]:
        # Unknown, or its shell was replaced since: nothing recorded applies to this OMP.
        records.pop(address, None)
        info = hc("get", address)
        omp = (info.get("foreground") or {}).get("pid")
        shell = process_id(info["pid"])
        pty = pty_of(info["pid"])
        ticks = start_ticks(omp) if omp else None
        if shell is None or pty is None or ticks is None:
            return
        record = {
            "created": info.get("created_ms"),
            "shell": shell,
            "shell_pid": info["pid"],
            "pty": pty,
            "omp_since": BOOT_TIME + ticks / TICKS - 5,
        }
    written, session = crumb_session(record["pty"], record["omp_since"])
    if written and session != record.get("session"):
        if session:
            log(f"{address}: {session}")
            record["session"] = session
        else:
            # A new session OMP has not saved yet: the recorded one is no longer in this terminal.
            record.pop("session", None)
    record["seen"] = now
    record.pop("lost", None)
    record.pop("sent", None)
    records[address] = record


def note_other(address: str, records: dict, now: float, may_resume: bool) -> bool:
    """A recorded terminal without OMP: forget it, or resume it. True when a resume was typed."""
    record = records[address]
    if "session" not in record:
        del records[address]
        return False
    info = hc("get", address)
    shell = process_id(info["pid"])
    if info.get("created_ms") != record["created"]:
        log(f"{address}: another terminal took this address, forgetting {record['session']}")
        del records[address]
        return False
    if shell == record["shell"]:
        if now - record.get("sent", 0) > SETTLE:
            log(f"{address}: OMP was quit, forgetting {record['session']}")
            del records[address]
        return False
    lost = record.setdefault("lost", now)
    idle = (info.get("foreground") or {}).get("pid") == info["pid"]
    if not idle:
        if now - lost > RESUME_WINDOW:
            log(f"{address}: recreated but in use, forgetting {record['session']}")
            del records[address]
        return False
    if not os.path.isfile(record["session"]):
        log(f"{address}: {record['session']} is gone, nothing to resume")
        del records[address]
        return False
    if not may_resume:
        return False
    pty = pty_of(info["pid"])
    if shell is None or pty is None:
        return False
    hc("send", address, "omp --resume " + shlex.quote(record["session"]))
    log(f"{address}: resumed {record['session']}")
    record.update(shell=shell, shell_pid=info["pid"], pty=pty, omp_since=now - 5, sent=now, seen=now)
    record.pop("lost", None)
    return True


def one_pass(records: dict) -> None:
    now = time.time()
    resumed = False
    live = [t for t in hc("ls")["terminals"] if t.get("state") == "live" and "/" not in t["address"]]
    for terminal in live:
        address = terminal["address"]
        try:
            if terminal.get("agent") == "omp":
                note_omp(address, records, now)
            elif address in records:
                resumed = note_other(address, records, now, not resumed) or resumed
        except (RuntimeError, OSError, KeyError, ValueError, subprocess.TimeoutExpired) as error:
            log(f"{address}: skipped this pass: {error}")
    for address in [a for a, r in records.items() if now - r.get("seen", now) > FORGET_AFTER]:
        del records[address]


def main() -> None:
    try:
        records = json.loads(STATE.read_text())
    except (OSError, ValueError):
        records = {}
    saved = json.dumps(records, sort_keys=True)
    while True:
        if core_running():
            try:
                one_pass(records)
            except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as error:
                log(f"pass failed: {error}")
            current = json.dumps(records, sort_keys=True)
            if current != saved:
                STATE.parent.mkdir(parents=True, exist_ok=True)
                scratch = STATE.with_suffix(".tmp")
                scratch.write_text(current)
                scratch.replace(STATE)
                saved = current
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
