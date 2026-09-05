#!/usr/bin/env python3
"""Explicit public-video handoff; native stdout is reserved for framed replies."""

import argparse
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import re
import select
import shutil
import signal
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import time
from urllib.parse import parse_qs, urlsplit

MPV = "@mpv@"
YT_DLP = "@ytDlp@"
STREAMLINK = "@streamlink@"
WL_PASTE = "@wlPaste@"
NOTIFY_SEND = "@notifySend@"
CHROMIUM = "@chromium@"
NATIVE_ORIGIN = "chrome-extension://keeppgjpejmhgehmknpjopikndfkajnl/"
STARTUP_TIMEOUT = 90
MAX_MESSAGE = 64 * 1024
MAX_IPC_LINE = 1024 * 1024
VIDEO_ID = re.compile(r"[A-Za-z0-9_-]{11}")
CHANNEL = re.compile(r"[A-Za-z0-9_]{1,25}")
CLIP = re.compile(r"[A-Za-z0-9_-]{1,200}")
RESERVED_CHANNELS = {
    "directory", "downloads", "drops", "inventory", "jobs", "login", "logout",
    "messages", "p", "payments", "prime", "products", "search", "settings",
    "signup", "store", "subscriptions", "turbo", "videos", "wallet",
}


@dataclass(frozen=True)
class Request:
    url: str
    service: str
    start: float | None = None


def timestamp(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("Start time must be a finite, nonnegative number of seconds.")
    try:
        number = float(value)
    except OverflowError as exc:
        raise ValueError("Start time is too large.") from exc
    if not math.isfinite(number) or number < 0:
        raise ValueError("Start time must be a finite, nonnegative number of seconds.")
    return number


def url_timestamp(value):
    if re.fullmatch(r"\d+(?:\.\d+)?", value):
        return timestamp(float(value))
    match = re.fullmatch(r"(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s)?", value)
    if not match or not any(match.groups()):
        raise ValueError("Invalid YouTube timestamp in URL.")
    return timestamp(sum(float(part or 0) * scale for part, scale in zip(match.groups(), (3600, 60, 1))))


def validate_request(message):
    if not isinstance(message, dict) or set(message) - {"url", "start"}:
        raise ValueError("Expected a URL and an optional start time only.")
    url = message.get("url")
    if not isinstance(url, str) or not url or len(url) > 8192:
        raise ValueError("Provide one YouTube or Twitch video URL.")
    if any(character.isspace() or ord(character) < 32 or ord(character) == 127 for character in url):
        raise ValueError("The video URL must not contain whitespace or control characters.")
    parsed = urlsplit(url)
    if parsed.scheme not in {"http", "https"} or parsed.username is not None or parsed.password is not None:
        raise ValueError("Only public HTTP(S) YouTube and Twitch URLs are supported.")
    if parsed.port is not None:
        raise ValueError("Video URLs must not specify a port.")
    host = parsed.hostname
    path = parsed.path.rstrip("/")
    query = parse_qs(parsed.query, keep_blank_values=True, max_num_fields=100)
    start = timestamp(message["start"]) if "start" in message else None
    video = None
    if host in {"youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"}:
        if path == "/watch" and len(query.get("v", [])) == 1:
            video = query["v"][0]
        else:
            match = re.fullmatch(r"/(?:shorts|live)/([A-Za-z0-9_-]{11})", path)
            if match:
                video = match[1]
    elif host in {"youtu.be", "www.youtu.be"}:
        video = path.removeprefix("/")
    if video is not None and VIDEO_ID.fullmatch(video):
        if start is None:
            fragment = parse_qs(parsed.fragment, keep_blank_values=True, max_num_fields=100)
            for values in (query.get("t"), query.get("start"), query.get("time_continue"), fragment.get("t")):
                if values is not None:
                    if len(values) != 1:
                        raise ValueError("The URL contains ambiguous start times.")
                    start = url_timestamp(values[0])
                    break
        return Request(f"https://www.youtube.com/watch?v={video}", "youtube", start)
    twitch_path = None
    if host in {"twitch.tv", "www.twitch.tv", "m.twitch.tv"}:
        parts = path.split("/")[1:]
        if len(parts) == 1 and CHANNEL.fullmatch(parts[0]) and parts[0].lower() not in RESERVED_CHANNELS:
            twitch_path = parts[0].lower()
        elif len(parts) == 2 and parts[0] == "videos" and re.fullmatch(r"\d{1,30}", parts[1]):
            twitch_path = "/".join(parts)
        elif len(parts) == 3 and CHANNEL.fullmatch(parts[0]) and parts[1] == "clip" and CLIP.fullmatch(parts[2]):
            twitch_path = "/".join(parts)
        if twitch_path is not None:
            canonical = f"https://www.twitch.tv/{twitch_path}"
    elif host == "clips.twitch.tv" and CLIP.fullmatch(path.removeprefix("/")):
        twitch_path = path.removeprefix("/")
        canonical = f"https://clips.twitch.tv/{twitch_path}"
    if twitch_path is not None:
        if start is not None:
            raise ValueError("Position handoff is supported for YouTube only, not Twitch.")
        return Request(canonical, "twitch")
    raise ValueError("Use a YouTube watch/shorts/live video or a Twitch channel/video/clip URL.")


def read_exact(stream, length):
    chunks = bytearray()
    while len(chunks) < length:
        chunk = stream.read(length - len(chunks))
        if not chunk:
            raise ValueError("The native message ended before its declared length.")
        chunks.extend(chunk)
    return bytes(chunks)


def read_frame(stream):
    length = struct.unpack("=I", read_exact(stream, 4))[0]
    if not 0 < length <= MAX_MESSAGE:
        raise ValueError(f"Native message length must be between 1 and {MAX_MESSAGE} bytes.")
    return json.loads(read_exact(stream, length).decode("utf-8"))


def encode_frame(message):
    payload = json.dumps(message, ensure_ascii=True, allow_nan=False, separators=(",", ":")).encode("utf-8")
    return struct.pack("=I", len(payload)) + payload


def clean_error(error):
    # Never relay terminal escape sequences from media tools or remote metadata.
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", str(error))
    return "".join(character for character in text if character in "\n\t" or ord(character) >= 32 and ord(character) != 127)[-4000:]


def notify_failure(error):
    try:
        subprocess.run(
            [NOTIFY_SEND, "--app-name=WebPlayback", "--urgency=normal", "--", "Play in mpv failed", clean_error(error)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def runtime_directory():
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    try:
        info = os.stat(runtime)
    except OSError as exc:
        raise ValueError("No usable XDG_RUNTIME_DIR; run this from your logged-in desktop session.") from exc
    if not os.path.isabs(runtime) or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("XDG_RUNTIME_DIR must be an absolute, private directory owned by your user.")
    directory = Path(tempfile.mkdtemp(prefix="web-playback-", dir=runtime))
    if len(os.fsencode(directory / "mpv.sock")) >= 108:
        directory.rmdir()
        raise ValueError("XDG_RUNTIME_DIR is too long for an mpv IPC socket.")
    return directory


def log_detail(paths):
    details = []
    for path in paths:
        try:
            with path.open("rb") as stream:
                stream.seek(0, os.SEEK_END)
                stream.seek(max(0, stream.tell() - 2500))
                text = clean_error(stream.read().decode("utf-8", errors="replace")).strip()
            if text:
                details.append(f"{path.stem}: {text}")
        except OSError:
            pass
    return "\n".join(details)


def stop_processes(processes):
    # Each child owns a session, including its extractor/browser descendants.
    for process in processes:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 3
    for process in processes:
        try:
            process.wait(timeout=max(0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            pass
    for process in processes:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


def parent_present(channel):
    if select.select([channel], [], [], 0)[0] and not channel.recv(1, socket.MSG_PEEK):
        raise RuntimeError("The requesting browser or launcher exited before playback started.")


def check_children(player, producer):
    if producer is not None and producer.poll() not in (None, 0):
        raise RuntimeError(f"Streamlink exited with status {producer.returncode}.")
    if player.poll() is not None:
        raise RuntimeError(f"mpv exited before playback with status {player.returncode}.")


def await_playback(player, producer, ipc_path, channel, source, deadline):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as ipc:
        while True:
            parent_present(channel)
            check_children(player, producer)
            if time.monotonic() >= deadline:
                raise RuntimeError("mpv did not start playback within 90 seconds.")
            try:
                ipc.connect(str(ipc_path))
                break
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.05)
        ipc.settimeout(1)
        # Attach before loading: never mistake file-loaded/spawned for playback,
        # and never miss the first playback-restart on a short clip.
        command = {"command": ["loadfile", source, "replace"], "request_id": 1}
        ipc.sendall(json.dumps(command).encode("utf-8") + b"\n")
        pending = bytearray()
        while time.monotonic() < deadline:
            parent_present(channel)
            check_children(player, producer)
            ready, _, _ = select.select([ipc, channel], [], [], min(0.25, max(0, deadline - time.monotonic())))
            if ipc not in ready:
                continue
            chunk = ipc.recv(65536)
            if not chunk:
                raise RuntimeError("mpv closed its control connection before playback.")
            pending.extend(chunk)
            while b"\n" in pending:
                line, _, remaining = pending.partition(b"\n")
                pending = bytearray(remaining)
                if len(line) > MAX_IPC_LINE:
                    raise RuntimeError("mpv sent an oversized control message.")
                try:
                    event = json.loads(line)
                except (ValueError, UnicodeError) as exc:
                    raise RuntimeError("mpv sent an invalid control message.") from exc
                if not isinstance(event, dict):
                    raise RuntimeError("mpv sent an invalid control event.")
                if event.get("request_id") == 1 and event.get("error") != "success":
                    raise RuntimeError(f"mpv rejected the video: {event.get('error', 'unknown error')}.")
                if event.get("event") == "end-file":
                    raise RuntimeError(f"mpv ended before playback: {event.get('error') or event.get('reason', 'unknown error')}.")
                if event.get("event") == "playback-restart":
                    check_children(player, producer)
                    return
            if len(pending) > MAX_IPC_LINE:
                raise RuntimeError("mpv sent an oversized control message.")
        raise RuntimeError("mpv did not start playback within 90 seconds.")


def supervise(request, channel):
    directory = None
    processes = []
    logs = []
    replied = False
    producer = None
    try:
        deadline = time.monotonic() + STARTUP_TIMEOUT
        directory = runtime_directory()
        config = directory / "config"
        config.mkdir()
        environment = os.environ.copy()
        environment["TMPDIR"] = str(directory)
        environment.pop("MPV_HOME", None)
        ipc_path = directory / "mpv.sock"
        player_args = [
            MPV, f"--config-dir={config}", "--load-scripts=yes", "--load-auto-profiles=no",
            "--audio-client-name=WebPlayback", "--wayland-app-id=WebPlayback", "--x11-name=WebPlayback",
            "--hwdec=auto-safe",
            "--idle=once", "--keep-open=no", "--pause=no", "--input-terminal=no", "--term-status-msg=",
            "--msg-level=all=warn", f"--input-ipc-server={ipc_path}",
        ]
        if request.service == "youtube":
            player_args.extend([
                "--ytdl=yes", f"--script-opts-append=ytdl_hook-ytdl_path={YT_DLP}",
                "--ytdl-raw-options=ignore-config=,no-playlist=",
            ])
            if request.start is not None:
                player_args.append(f"--start={request.start:.6f}")
            source = request.url
        else:
            player_args.append("--ytdl=no")
            source = "-"
            stream_log = directory / "streamlink.log"
            logs.append(stream_log)
            with stream_log.open("wb") as output:
                producer = subprocess.Popen(
                    [STREAMLINK, "--no-config", "--no-plugin-cache", "--no-plugin-sideloading",
                     "--webbrowser", "yes", "--webbrowser-executable", CHROMIUM, "--webbrowser-headless", "yes",
                     "--webbrowser-timeout", "45", "--ringbuffer-size", "16M", "--hls-live-edge", "3",
                     "--stream-segment-threads", "2", "--stream-timeout", "30", "--loglevel", "info",
                     "--stdout", request.url, "best"],
                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=output,
                    cwd=directory, env=environment, start_new_session=True,
                )
                processes.append(producer)
        player_log = directory / "mpv.log"
        logs.append(player_log)
        with player_log.open("wb") as output:
            player = subprocess.Popen(
                player_args, stdin=producer.stdout if producer else subprocess.DEVNULL,
                stdout=output, stderr=output, cwd=directory, env=environment, start_new_session=True,
            )
            processes.append(player)
        if producer:
            producer.stdout.close()
        await_playback(player, producer, ipc_path, channel, source, deadline)
        parent_present(channel)
        channel.sendall(encode_frame({"ok": True}))
        replied = True
        channel.close()
        # Closing the native port cannot affect this detached supervisor or its
        # media sessions once actual playback has been acknowledged.
        while player.poll() is None:
            if producer is not None and producer.poll() not in (None, 0):
                raise RuntimeError(f"Streamlink stopped with status {producer.returncode}.")
            time.sleep(0.25)
    except Exception as exc:
        detail = log_detail(logs)
        error = clean_error(f"{exc}\n{detail}" if detail else exc)
        if replied:
            notify_failure(error)
        else:
            try:
                channel.sendall(encode_frame({"ok": False, "error": error}))
            except OSError:
                pass
    finally:
        channel.close()
        stop_processes(processes)
        if directory is not None:
            shutil.rmtree(directory, ignore_errors=True)


def interrupted(signum, frame):
    raise InterruptedError("Playback was interrupted.")


def launch(request, native=False):
    parent, child = socket.socketpair()
    try:
        pid = os.fork()
    except OSError:
        parent.close()
        child.close()
        raise
    if pid == 0:
        parent.close()
        try:
            os.setsid()
            signal.signal(signal.SIGTERM, interrupted)
            signal.signal(signal.SIGINT, interrupted)
            signal.signal(signal.SIGHUP, signal.SIG_IGN)
            with open(os.devnull, "r+b", buffering=0) as null:
                for descriptor in (0, 1, 2):
                    os.dup2(null.fileno(), descriptor)
            supervise(request, child)
        finally:
            os._exit(0)
    child.close()
    with parent:
        parent.settimeout(STARTUP_TIMEOUT + 5)
        if native:
            # Browser pipe closure cancels a pending handoff, even if Chromium
            # closes stdin without sending this host a termination signal.
            ready, _, _ = select.select([parent, sys.stdin.fileno()], [], [], STARTUP_TIMEOUT + 5)
            if sys.stdin.fileno() in ready:
                raise RuntimeError("The browser disconnected before playback was acknowledged.")
            if parent not in ready:
                raise RuntimeError("Playback worker timed out before confirming playback.")
        with parent.makefile("rb") as response:
            try:
                return read_frame(response)
            except (OSError, ValueError) as exc:
                raise RuntimeError("Playback worker failed or timed out before confirming playback.") from exc


def native_main():
    try:
        # sendNativeMessage creates one host per request; no persistent listener.
        if len(sys.argv) > 3 or len(sys.argv) == 3 and sys.argv[2] != NATIVE_ORIGIN:
            raise ValueError("This native host only accepts the configured WebPlayback extension.")
        request = validate_request(read_frame(sys.stdin.buffer))
        result = launch(request, native=True)
    except Exception as exc:
        result = {"ok": False, "error": clean_error(exc)}
    try:
        sys.stdout.buffer.write(encode_frame(result))
        sys.stdout.buffer.flush()
    except (BrokenPipeError, OSError):
        return 1
    return 0 if result.get("ok") else 1


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--native":
        # Chromium appends the requesting extension's origin to native argv.
        return native_main()
    parser = argparse.ArgumentParser(description="Play one public YouTube or Twitch URL in an independent mpv window.")
    parser.add_argument("url", nargs="?")
    parser.add_argument("--start", type=float, help="YouTube start position in seconds")
    parser.add_argument("--clipboard", action="store_true", help="Read a video URL from the Wayland clipboard")
    args = parser.parse_args()
    try:
        if args.clipboard:
            if args.url:
                raise ValueError("Choose either a URL or --clipboard, not both.")
            clipboard = subprocess.run(
                [WL_PASTE, "--no-newline", "--type", "text"], stdin=subprocess.DEVNULL,
                capture_output=True, timeout=5, check=False,
            )
            if clipboard.returncode:
                raise ValueError(f"Could not read text from the clipboard: {clipboard.stderr.decode('utf-8', errors='replace').strip()}")
            url = clipboard.stdout.decode("utf-8").strip()
        else:
            url = args.url
        message = {"url": url}
        if args.start is not None:
            message["start"] = args.start
        result = launch(validate_request(message))
        if not result.get("ok"):
            raise RuntimeError(result.get("error", "Playback failed."))
    except Exception as exc:
        error = clean_error(exc)
        print(f"web-playback: {error}", file=sys.stderr)
        notify_failure(error)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
