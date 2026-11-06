"""SSH forced command that lets the car's display read and answer this host's herdr agents.

car-display on the car's Raspberry Pi lists Tom's agents, shows their recent output and
sends a reply typed on the car's screen. sshd runs this for every connection with the
car's key and puts the requested command in SSH_ORIGINAL_COMMAND. It is split with
shlex (never handed to a shell) and must be exactly one of:

    herdr agent list
    herdr agent read TARGET --source recent-unwrapped --lines N
    herdr agent prompt TARGET TEXT

TARGET is a pane ID (w7:p2K) or an agent name, N is 1 to 500, TEXT is one line of
printable text up to 4000 characters. herdr itself refuses a prompt to an agent that
shows an approval (agent_blocked) without sending it; the car never sends keystrokes,
so it cannot answer an approval. Every call is appended to a JSON-lines audit log.
"""

import json
import os
import re
import shlex
import sys
import time

HERDR = "@herdr@"

TARGET = re.compile(r"[A-Za-z0-9][A-Za-z0-9:_-]{0,63}")
LINES = re.compile(r"[1-9][0-9]{0,2}")
MAX_LINES = 500
MAX_TEXT = 4000

LOG_DIR = os.path.join(os.path.expanduser("~"), ".local", "state", "herdr-car-gate")


def client():
    return (os.environ.get("SSH_CLIENT") or "").split(" ")[0]


def log(entry):
    try:
        os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
        with open(os.path.join(LOG_DIR, "log.jsonl"), "a") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    except OSError:
        pass


def deny(reason, argv):
    log({"ts": time.time(), "client": client(), "denied": reason, "argv": [a[:200] for a in argv]})
    print(json.dumps({"error": {"code": "car_gate_denied", "message": reason}}), file=sys.stderr)
    sys.exit(126)


def refusal(argv):
    """Why argv is not one of the car's three requests, or None when it is."""
    if argv == ["agent", "list"]:
        return None
    if len(argv) == 7 and argv[:2] == ["agent", "read"] and argv[3:6] == ["--source", "recent-unwrapped", "--lines"]:
        if not TARGET.fullmatch(argv[2]):
            return "not an agent target: %s" % argv[2][:80]
        if not LINES.fullmatch(argv[6]) or int(argv[6]) > MAX_LINES:
            return "lines must be 1 to %d" % MAX_LINES
        return None
    if len(argv) == 4 and argv[:2] == ["agent", "prompt"]:
        if not TARGET.fullmatch(argv[2]):
            return "not an agent target: %s" % argv[2][:80]
        text = argv[3]
        if not text.strip() or len(text) > MAX_TEXT or not text.isprintable():
            return "a prompt is one line of printable text up to %d characters" % MAX_TEXT
        return None
    return "not allowed: %s" % " ".join(argv[:2])[:80]


def main():
    raw = os.environ.get("SSH_ORIGINAL_COMMAND", "")
    try:
        argv = shlex.split(raw)
    except ValueError as e:
        deny("unparsable command: %s" % e, [raw[:200]])
    if argv[:1] == ["herdr"]:
        argv = argv[1:]
    reason = refusal(argv)
    if reason is not None:
        deny(reason, argv)

    log({"ts": time.time(), "client": client(), "argv": [a if len(a) <= 2000 else a[:2000] + "..." for a in argv]})

    env = {k: v for k, v in os.environ.items() if not k.startswith("HERDR_")}
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    os.execve(HERDR, [HERDR] + argv, env)


if __name__ == "__main__":
    main()
