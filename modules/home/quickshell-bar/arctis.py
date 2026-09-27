#!/usr/bin/env python3
"""Status bridge for the SteelSeries Arctis Pro Wireless base station.

The base answers vendor queries on HID interface 0 of USB 1038:1290. Each
query is an output report [command, 0xAA, 0...]; the reply is one input report
whose leading bytes carry the value. Command bytes come from
https://chameth.com/reverse-engineering-arctis-pro-wireless-headset/.

`watch` prints one JSON object per line whenever the observed state changes:
  {"state": "absent"}                              base station not plugged in
  {"state": "off", "spare": 4}                     headset powered off
  {"state": "on", "headset": 3, "spare": 4}        headset powered on
  {"state": "error", "error": "..."}               base present but unreadable
Battery values are the base's own 0-4 bar scale. A spare value of 0 also
covers an empty charging slot; the protocol does not distinguish the two.
"""

import fcntl
import json
import os
import select
import sys
import time
from pathlib import Path

HID_ID = "0003:00001038:00001290"
REPORT_SIZE = 32
REPLY_TIMEOUT = 1.0
STATUS_INTERVAL = 2.0
BATTERY_INTERVAL = 60.0

QUERY_HEADSET_BATTERY = 0x40
QUERY_STATUS = 0x41
QUERY_SPARE_BATTERY = 0x42
STATUS_ON = 0x04
STATUS_OFF = 0x02


def find_control_node() -> str | None:
    for node in sorted(Path("/sys/class/hidraw").iterdir()):
        try:
            lines = (node / "device" / "uevent").read_text().splitlines()
        except OSError:
            continue
        uevent = dict(line.split("=", 1) for line in lines if "=" in line)
        if uevent.get("HID_ID") == HID_ID and uevent.get("HID_PHYS", "").endswith("/input0"):
            return f"/dev/{node.name}"
    return None


def query(fd: int, command: int) -> int:
    # Leading 0 is the hidraw report number; this interface has no report IDs.
    os.write(fd, bytes([0, command, 0xAA]) + bytes(REPORT_SIZE - 2))
    ready, _, _ = select.select([fd], [], [], REPLY_TIMEOUT)
    if not ready:
        raise TimeoutError(f"no reply to query 0x{command:02x}")
    return os.read(fd, REPORT_SIZE)[0]


def battery(value: int) -> int:
    if not 0 <= value <= 4:
        raise ValueError(f"battery value {value} is outside 0-4")
    return value


def read_state(node: str, want_batteries: bool, previous: dict) -> dict:
    # A fresh descriptor per cycle survives replugs, and its input queue only
    # holds replies to our own queries. flock serializes other helper calls.
    fd = os.open(node, os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        status = query(fd, QUERY_STATUS)
        if status not in (STATUS_ON, STATUS_OFF):
            raise ValueError(f"unknown headset status 0x{status:02x}")
        state = {"state": "on" if status == STATUS_ON else "off"}
        # Re-read batteries when due or when the headset changes power state.
        if want_batteries or previous.get("state") != state["state"]:
            state["spare"] = battery(query(fd, QUERY_SPARE_BATTERY))
            if status == STATUS_ON:
                state["headset"] = battery(query(fd, QUERY_HEADSET_BATTERY))
        else:
            for key in ("spare", "headset"):
                if key in previous:
                    state[key] = previous[key]
        return state
    finally:
        os.close(fd)


def watch() -> None:
    previous: dict = {}
    batteries_due = 0.0
    while True:
        now = time.monotonic()
        node = find_control_node()
        if node is None:
            state = {"state": "absent"}
        else:
            try:
                state = read_state(node, now >= batteries_due, previous)
            except (OSError, TimeoutError, ValueError) as error:
                state = {"state": "error", "error": str(error)}
        if state.get("state") in ("on", "off") and now >= batteries_due:
            batteries_due = now + BATTERY_INTERVAL
        elif state.get("state") not in ("on", "off"):
            # Read batteries immediately once the base answers again.
            batteries_due = 0.0
        if state != previous:
            print(json.dumps(state), flush=True)
            previous = state
        time.sleep(STATUS_INTERVAL)


def main() -> int:
    if sys.argv[1:] != ["watch"]:
        print("usage: arctis watch", file=sys.stderr)
        return 2
    try:
        watch()
    except (BrokenPipeError, KeyboardInterrupt):
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
