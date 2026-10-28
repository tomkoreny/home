"""SSH forced command that lets Hermes drive this host's herdr agents.

sshd runs this for every connection with the Hermes key and puts the
requested command in SSH_ORIGINAL_COMMAND. It is split with shlex (never
handed to a shell), checked against an allowlist of herdr subcommands and
executed directly. Every call is appended to a JSON-lines audit log.

Allowed: reading state (list/get/read/wait), prompts and keystrokes to
agents, creating workspaces/tabs/panes, starting agents, and closing single
panes and tabs (Tom asks Hermes to close finished agents).
Not allowed: shells, `pane run`/`send-text`, closing whole workspaces, focus
changes on Tom's screen, server/session management, `--env`, and selecting
another session or machine.
"""

import json
import os
import shlex
import sys
import time

HERDR = "@herdr@"

ALLOWED = {
    "agent": {"list", "get", "read", "prompt", "send-keys", "wait", "start", "rename"},
    "pane": {"list", "get", "read", "split", "wait-output", "send-keys", "close"},
    "workspace": {"list", "get", "create"},
    "tab": {"list", "get", "create", "close"},
    "api": {"snapshot"},
    "status": {"server"},
}

FORBIDDEN_FLAGS = ("--env", "--session", "--machine", "--remote", "--focus", "--takeover")

LOG_DIR = os.path.join(os.path.expanduser("~"), ".local", "state", "herdr-hermes-gate")


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
    log({"ts": time.time(), "client": client(), "denied": reason, "argv": argv})
    print(json.dumps({"error": {"code": "hermes_gate_denied", "message": reason}}), file=sys.stderr)
    sys.exit(126)


def main():
    raw = os.environ.get("SSH_ORIGINAL_COMMAND", "")
    try:
        argv = shlex.split(raw)
    except ValueError as e:
        deny("unparsable command: %s" % e, [raw[:200]])
    if argv[:1] == ["herdr"]:
        argv = argv[1:]
    if len(argv) < 2:
        deny("usage: herdr <group> <verb> ...", argv)
    group, verb = argv[0], argv[1]
    if verb not in ALLOWED.get(group, ()):
        deny("not allowed: %s %s" % (group, verb), argv)
    # Flags are checked only up to `--`: what follows `agent start ... --`
    # goes to the agent executable itself.
    head = argv[: argv.index("--")] if "--" in argv else argv
    for arg in head:
        if arg.split("=", 1)[0] in FORBIDDEN_FLAGS:
            deny("flag not allowed: %s" % arg, argv)

    log({"ts": time.time(), "client": client(), "argv": [a if len(a) <= 2000 else a[:2000] + "..." for a in argv]})

    env = {k: v for k, v in os.environ.items() if not k.startswith("HERDR_")}
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    os.execve(HERDR, [HERDR] + argv, env)


if __name__ == "__main__":
    main()
