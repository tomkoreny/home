#!/usr/bin/env python3
"""Status and display bridge for the SteelSeries Arctis Pro Wireless base.

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

`watch` also owns the base's OLED. It draws a clock with the day and date
under it, and moves that block to a new spot every minute to spread burn-in.
It reads events from stdin, one JSON object per line:
{"lines": ["header", "text", "text"], "seconds": 6}. An event replaces the
clock until it expires; a newer event replaces an older one. Everything stays
PADDING pixels clear of the screen edge.
"""

import datetime
import fcntl
import json
import os
import random
import select
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

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

# The draw command is a 1024-byte feature report: command byte, then 8-row
# pages of one byte per column, least significant bit on top.
DRAW = 0xD2
DRAW_REPORT_SIZE = 1024
WIDTH = 128
HEIGHT = 40
PADDING = 1
INNER_WIDTH = WIDTH - 2 * PADDING
INNER_HEIGHT = HEIGHT - 2 * PADDING
CLOCK_DATE_GAP = 2
FONT_REGULAR = "@fontRegular@"
FONT_BOLD = "@fontBold@"


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


def draw(node: str, frame: bytes) -> None:
    report = bytearray(DRAW_REPORT_SIZE + 1)
    report[1] = DRAW
    report[2 : 2 + len(frame)] = frame
    # HIDIOCSFEATURE(len): _IOWR('H', 0x06, len)
    request = (3 << 30) | (len(report) << 16) | (ord("H") << 8) | 0x06
    fd = os.open(node, os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        fcntl.ioctl(fd, request, report)
    finally:
        os.close(fd)


class Renderer:
    def __init__(self) -> None:
        self.clock_font = ImageFont.truetype(FONT_BOLD, 32)
        self.date_font = ImageFont.truetype(FONT_BOLD, 16)
        self.header_font = ImageFont.truetype(FONT_BOLD, 12)
        self.text_font = ImageFont.truetype(FONT_REGULAR, 12)

    @staticmethod
    def pack(inner: Image.Image) -> bytes:
        # Frames are drawn inside the padding, so nothing can touch the edge.
        image = Image.new("1", (WIDTH, HEIGHT))
        image.paste(inner, (PADDING, PADDING))
        pixels = image.load()
        frame = bytearray(WIDTH * HEIGHT // 8)
        for page in range(HEIGHT // 8):
            for x in range(WIDTH):
                value = 0
                for bit in range(8):
                    if pixels[x, page * 8 + bit]:
                        value |= 1 << bit
                frame[page * WIDTH + x] = value
        return bytes(frame)

    @staticmethod
    def canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
        image = Image.new("1", (INNER_WIDTH, INNER_HEIGHT))
        painter = ImageDraw.Draw(image)
        painter.fontmode = "1"
        return image, painter

    def ink(self, text: str, font) -> Image.Image:
        # textbbox includes the font's empty ascent; lay out by drawn pixels.
        image, painter = self.canvas()
        painter.text((0, 0), text, font=font, fill=1)
        return image.crop(image.getbbox())

    def clock(self, now: datetime.datetime) -> bytes:
        image, _ = self.canvas()
        time_ink = self.ink(now.strftime("%H:%M"), self.clock_font)
        date_ink = self.ink(now.strftime("%a %-d %b"), self.date_font)
        block_width = max(time_ink.width, date_ink.width)
        block_height = time_ink.height + CLOCK_DATE_GAP + date_ink.height
        # Seeded by the minute, so each minute lands somewhere new but a
        # redraw within the same minute keeps its place.
        spot = random.Random(int(now.timestamp()) // 60)
        x = spot.randint(0, max(0, INNER_WIDTH - block_width))
        y = spot.randint(0, max(0, INNER_HEIGHT - block_height))
        image.paste(time_ink, (x + (block_width - time_ink.width) // 2, y))
        image.paste(
            date_ink,
            (
                x + (block_width - date_ink.width) // 2,
                y + time_ink.height + CLOCK_DATE_GAP,
            ),
        )
        return self.pack(image)

    def fit(self, painter: ImageDraw.ImageDraw, text: str, font) -> str:
        # No line fits more than INNER_WIDTH characters, so trimming the input
        # first bounds the measuring loop below for arbitrarily long text.
        text = " ".join(text.split())[: INNER_WIDTH + 1]
        if painter.textlength(text, font=font) <= INNER_WIDTH:
            return text
        while text and painter.textlength(text + "…", font=font) > INNER_WIDTH:
            text = text[:-1]
        return text.rstrip(" -–—·,:;") + "…"

    def event(self, lines: list[str]) -> bytes:
        image, painter = self.canvas()
        for row, line in enumerate(lines[:3]):
            font = self.header_font if row == 0 else self.text_font
            painter.text((0, row * 12), self.fit(painter, line, font), font=font, fill=1)
        return self.pack(image)


def read_events(buffer: bytearray, renderer: Renderer) -> tuple[list[tuple[bytes, float]], bool]:
    """Drain stdin; return rendered events and whether stdin is still open."""
    chunk = os.read(sys.stdin.fileno(), 65536)
    if not chunk:
        return [], False
    buffer.extend(chunk)
    events = []
    while b"\n" in buffer:
        line, _, rest = bytes(buffer).partition(b"\n")
        buffer[:] = rest
        try:
            request = json.loads(line)
            lines = [str(text) for text in request["lines"]]
            seconds = float(request["seconds"])
        except (ValueError, KeyError, TypeError) as error:
            print(f"arctis: ignoring event {line!r}: {error}", file=sys.stderr)
            continue
        events.append((renderer.event(lines), seconds))
    return events, True


def watch() -> None:
    renderer = Renderer()
    previous: dict = {}
    node: str | None = None
    batteries_due = 0.0
    status_due = 0.0
    event: bytes | None = None
    event_deadline = 0.0
    shown: bytes | None = None
    stdin_open = True
    stdin_buffer = bytearray()
    while True:
        now = time.monotonic()
        if now >= status_due:
            status_due = now + STATUS_INTERVAL
            node = find_control_node()
            if node is None:
                state = {"state": "absent"}
            else:
                try:
                    state = read_state(node, now >= batteries_due, previous)
                except (OSError, TimeoutError, ValueError) as error:
                    state = {"state": "error", "error": str(error)}
            if state["state"] in ("on", "off"):
                if now >= batteries_due:
                    batteries_due = now + BATTERY_INTERVAL
            else:
                # Read batteries and redraw as soon as the base answers again.
                batteries_due = 0.0
                shown = None
            if state != previous:
                print(json.dumps(state), flush=True)
                previous = state

        if event is not None and now >= event_deadline:
            event = None
        if node is not None and previous.get("state") in ("on", "off"):
            frame = event if event is not None else renderer.clock(datetime.datetime.now())
            if frame != shown:
                try:
                    draw(node, frame)
                    shown = frame
                except OSError as error:
                    print(f"arctis: draw failed: {error}", file=sys.stderr)

        wall = time.time()
        wakeups = [status_due - now, 60 - wall % 60 + 0.05]
        if event is not None:
            wakeups.append(event_deadline - now)
        timeout = max(0.0, min(wakeups))
        readable = [sys.stdin.fileno()] if stdin_open else []
        ready, _, _ = select.select(readable, [], [], timeout)
        if ready:
            events, stdin_open = read_events(stdin_buffer, renderer)
            if events:
                event, seconds = events[-1]
                event_deadline = time.monotonic() + seconds


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
