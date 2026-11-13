#!/usr/bin/env python3
"""Which programs use this machine's memory and CPU, as JSON for the bar's hover.

Processes are grouped by the name of their executable (a Nix wrapper's
`.name-wrapped` counts as `name`), so fifteen OMP sessions are one row.
Another person's processes carry their owner, as in `node (terka)`.

Memory is PSS: a page several processes share is split between them, so the
rows add up to what is in use, where RSS counts a browser's shared pages once
per helper. Another user's PSS cannot be read; its anonymous and shmem pages
stand in.

CPU is what a program used between two readings SAMPLE seconds apart; 100 is
one core, as in htop.

Prints {"memory": [{"name", "count", "kib"}], "cpu": [{"name", "count", "percent"}]},
the largest first.
"""

from __future__ import annotations

import json
import os
import pwd
import time

SAMPLE = 0.5
MEMORY_ROWS = 6
CPU_ROWS = 4
TICKS = os.sysconf("SC_CLK_TCK")
KERNEL_THREAD = 0x00200000  # PF_KTHREAD in /proc/<pid>/stat's flags


def readings() -> dict[str, tuple[str, int, bool]]:
    """pid -> (start time, CPU ticks used so far, is a kernel thread)."""
    found = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as file:
                stat = file.read()
        except OSError:
            continue
        fields = stat[stat.rindex(")") + 2:].split()
        found[pid] = (fields[19], int(fields[11]) + int(fields[12]), bool(int(fields[6]) & KERNEL_THREAD))
    return found


def owner_tag(pid: str) -> str:
    """ " (terka)" for a process of another person on this machine, else nothing."""
    uid = os.stat(f"/proc/{pid}").st_uid
    if uid == os.getuid() or uid < 1000:
        return ""
    try:
        return f" ({pwd.getpwuid(uid).pw_name})"
    except KeyError:
        return ""  # a container's user, unknown on the host


def program(pid: str) -> str:
    try:
        name = os.path.basename(os.readlink(f"/proc/{pid}/exe")).removesuffix(" (deleted)")
    except OSError:
        # Another user's process hides its exe link but not its command line.
        # Its first word: next-server, for one, puts its version after it. The
        # command name is no use here: node's is "MainThread".
        with open(f"/proc/{pid}/cmdline", "rb") as file:
            command = file.read().split(b"\0", 1)[0].decode(errors="replace")
        name = os.path.basename(command).split(" ", 1)[0].rstrip(":")
        if not name:
            with open(f"/proc/{pid}/comm") as file:
                name = file.read().strip()
    if name.startswith(".") and name.endswith("-wrapped"):
        name = name[1:-len("-wrapped")]
    return name + owner_tag(pid)


def memory_kib(pid: str) -> int:
    try:
        with open(f"/proc/{pid}/smaps_rollup") as file:
            for line in file:
                if line.startswith("Pss:"):
                    return int(line.split()[1])
    except PermissionError:
        pass
    total = 0
    with open(f"/proc/{pid}/status") as file:
        for line in file:
            if line.startswith(("RssAnon:", "RssShmem:")):
                total += int(line.split()[1])
    return total


def main() -> None:
    before = readings()
    started = time.monotonic()
    time.sleep(SAMPLE)
    after = readings()
    elapsed = time.monotonic() - started

    groups: dict[str, dict] = {}
    for pid, (start, ticks, kernel) in after.items():
        try:
            name = "kernel" if kernel else program(pid)
            kib = 0 if kernel else memory_kib(pid)
        except OSError:
            continue  # it exited since the reading
        group = groups.setdefault(name, {"name": name, "count": 0, "kib": 0, "ticks": 0})
        # The kernel's hundreds of threads are one thing to the reader.
        group["count"] = 1 if kernel else group["count"] + 1
        group["kib"] += kib
        earlier = before.get(pid)
        if earlier and earlier[0] == start:
            group["ticks"] += ticks - earlier[1]

    for group in groups.values():
        group["percent"] = round(group.pop("ticks") / TICKS / elapsed * 100)
    by_memory = sorted(groups.values(), key=lambda group: group["kib"], reverse=True)
    by_cpu = sorted(groups.values(), key=lambda group: group["percent"], reverse=True)
    print(json.dumps({
        "memory": [{key: group[key] for key in ("name", "count", "kib")} for group in by_memory[:MEMORY_ROWS] if group["kib"]],
        "cpu": [{key: group[key] for key in ("name", "count", "percent")} for group in by_cpu[:CPU_ROWS] if group["percent"]],
    }))


if __name__ == "__main__":
    main()
