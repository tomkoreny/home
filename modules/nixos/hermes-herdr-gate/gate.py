"""SSH forced command that lets Hermes drive this host's herdr agents.

sshd runs this for every connection with the Hermes key and puts the
requested command in SSH_ORIGINAL_COMMAND. It is split with shlex (never
handed to a shell), checked against an allowlist and executed directly.
Every call is appended to a JSON-lines audit log.

The first word picks the program, and each has its own allowlist:
`herdr-core` or `hc` is the server the Herdr app's terminals run in, anything
else is the older herdr, with or without `herdr` in front.

herdr

Allowed: reading state (list/get/read/wait), prompts and keystrokes to
agents, creating workspaces/tabs/panes, starting agents, and closing single
panes and tabs (Tom asks Hermes to close finished agents).
Not allowed: shells, `pane run`/`send-text`, closing whole workspaces, focus
changes on Tom's screen, server/session management, `--env`, and selecting
another session or machine.

herdr-core

Hermes may start an OMP session, talk to it and follow it, and see what else
runs. CORE_ALLOWED has the verbs and their flags. Every other verb and flag
is denied (`exec`, `file`, `attach`, `label`, `server start|stop|restart`,
`--on`, `--parent`, ...), and so is a terminal of another machine (`mac/t7`).

- `server status`, `ls`, `get`, `read`, `wait`: any terminal of this machine.
- `run --cwd FOLDER -- omp [ARGS...]` starts the session. herdr-core makes a
  terminal and starts its program in one command, and without a program it
  starts a shell, so the program has to be the word `omp`; what follows goes
  to OMP unchecked, as with `herdr agent start`. FOLDER is under the home
  directory. The gate adds `--bg`, `--no-parent` and the label
  `started-by=hermes`.
  `--label herdr.space=ID`, the one label Hermes may set, shows the terminal
  in the Herdr app as a new tab of that space; without it the app does not
  show the terminal. The space must have a live terminal already: the app
  leaves Tom's focus where it is for such a tab (observed, app 0.1.16), and an
  ID it does not know would make a new space.
- `send`, `keys`, `kill`, `rm`: only a terminal carrying `started-by=hermes`,
  which Hermes cannot set any other way. `send` and `keys` also need OMP to be
  the program in it: after a reboot herdr-core brings a kept terminal back as
  a plain shell with its labels, where typed text would be a command.

Every herdr-core call starts a core when none runs, `server status` too. The
gate tries the core's socket first and answers `herdr_core_not_running`
(exit 69) itself, so Hermes never starts one.
"""

import json
import os
import re
import shlex
import socket
import subprocess
import sys
import time

HERDR = "@herdr@"
HERDR_CORE = "@herdr_core@"

ALLOWED = {
    "agent": {"list", "get", "read", "prompt", "send-keys", "wait", "start", "rename"},
    "pane": {"list", "get", "read", "split", "wait-output", "send-keys", "close"},
    "workspace": {"list", "get", "create"},
    "tab": {"list", "get", "create", "close"},
    "api": {"snapshot"},
    "status": {"server"},
}

FORBIDDEN_FLAGS = ("--env", "--session", "--machine", "--remote", "--focus", "--takeover")

# herdr-core, per verb: how Hermes writes it, its flags (True: the flag takes
# a value) and how many words it takes at least and at most (None: any
# number). `run` takes `--bg` because herdr-core's manual tells agents to
# write it; the gate sets it either way.
CORE_ALLOWED = {
    "server": ("server status [--json]", {"--json": False}, 1, 1),
    "ls": ("ls [--all] [--label K=V] [--json]", {"--all": False, "--label": True, "--json": False}, 0, 0),
    "get": ("get [--json] TERMINAL", {"--json": False}, 1, 1),
    "read": ("read [--lines N] [--json] TERMINAL", {"--lines": True, "--json": False}, 1, 1),
    "wait": ("wait [--timeout SECONDS] [--json] TERMINAL", {"--timeout": True, "--json": False}, 1, 1),
    "run": (
        "run [--name NAME] --cwd FOLDER [--label herdr.space=ID] [--json] -- omp [ARGS...]",
        {"--bg": False, "--name": True, "--cwd": True, "--label": True, "--json": False},
        1,
        None,
    ),
    "send": (
        "send [--wait] [--timeout SECONDS] [--if idle|working] [--force] [--json] -- TERMINAL TEXT",
        {"--wait": False, "--timeout": True, "--if": True, "--force": False, "--json": False},
        2,
        2,
    ),
    "keys": ("keys [--json] TERMINAL KEY...", {"--json": False}, 2, None),
    "kill": ("kill [--json] TERMINAL", {"--json": False}, 1, 1),
    "rm": ("rm [--json] TERMINAL", {"--json": False}, 1, 1),
}
# Verbs whose first word is a terminal. The last four reach only Hermes' own.
CORE_OWN = ("send", "keys", "kill", "rm")
CORE_TERMINAL = ("get", "read", "wait") + CORE_OWN
OWN_LABEL = "started-by=hermes"
# An address (t7) or a name on this machine; `mac/t7` is another machine's.
TERMINAL = re.compile(r"[a-z0-9][a-z0-9._-]{0,31}")
SPACE_LABEL = re.compile(r"herdr\.space=[A-Za-z0-9]{1,64}")
CORE_NOT_RUNNING = 69  # sysexits' EX_UNAVAILABLE

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


def log_call(argv):
    log({"ts": time.time(), "client": client(), "argv": [a if len(a) <= 2000 else a[:2000] + "..." for a in argv]})


def deny(reason, argv):
    log({"ts": time.time(), "client": client(), "denied": reason, "argv": argv})
    print(json.dumps({"error": {"code": "hermes_gate_denied", "message": reason}}), file=sys.stderr)
    sys.exit(126)


def core_words(argv, allowed, program):
    """Split a herdr-core command into (flags, words) the way its CLI reads it.

    A flag is `--x`, `--x=value`, or `--x value` when it takes one. What follows
    `--` is never a flag. For `run` (program), neither is what follows the
    program's name: that goes to the program.
    """
    flags, words = [], []
    rest = iter(argv[2:])
    for arg in rest:
        if arg == "--":
            words.extend(rest)
        elif arg.startswith("-"):
            name, given, value = arg.partition("=")
            if name not in allowed:
                deny("flag not allowed: %s" % arg[:80], argv)
            if not allowed[name]:
                if given:
                    deny("flag takes no value: %s" % name, argv)
                flags.append((name, None))
            else:
                if not given:
                    value = next(rest, None)
                if value is None:
                    deny("flag needs a value: %s" % name, argv)
                flags.append((name, value))
        else:
            words.append(arg)
            if program:
                words.extend(rest)
    return flags, words


def core_run(flags, words, argv):
    """The flags `run` gets, the gate's own and Hermes' checked ones, and the space label if given."""
    home = os.path.realpath(os.path.expanduser("~"))
    given = ["--bg", "--no-parent", "--label=" + OWN_LABEL]
    cwd = space = None
    for flag, value in flags:
        if flag == "--name" and not TERMINAL.fullmatch(value):
            deny("not a name (1-32 of a-z 0-9 - _ .): %s" % value[:80], argv)
        if flag == "--label":
            if not SPACE_LABEL.fullmatch(value):
                deny("label not allowed: %s" % value[:80], argv)
            space = value
        if flag == "--cwd":
            # Resolved, so a link in the home directory cannot lead out of it.
            cwd = os.path.realpath(value)
            if not os.path.isabs(value) or not os.path.isdir(cwd) or os.path.commonpath([home, cwd]) != home:
                deny("--cwd must be an existing folder under %s, given from /: %s" % (home, value[:200]), argv)
            value = cwd
        if flag != "--bg":
            given.append(flag if value is None else "%s=%s" % (flag, value))
    if cwd is None:
        deny("usage: herdr-core %s" % CORE_ALLOWED["run"][0], argv)
    if words[0] != "omp":
        deny("only omp may be started: %s" % words[0][:80], argv)
    return given, space


def core_running(env):
    """Whether a core answers on its socket. Asking herdr-core would start one."""
    try:
        with socket.socket(socket.AF_UNIX) as probe:
            probe.settimeout(2)
            probe.connect(os.path.join(env["XDG_RUNTIME_DIR"], "herdr-core", "default.sock"))
        return True
    except OSError:
        return False


def core_list(env, *flags):
    """The terminals `herdr-core ls` gives with these flags."""
    listing = subprocess.run([HERDR_CORE, "ls", "--json", *flags], capture_output=True, text=True, env=env, timeout=30, check=True)
    return json.loads(listing.stdout)["terminals"]


def core_own(verb, target, env, argv):
    """The address of the one terminal Hermes started that `target` names; denied when there is none."""
    mine = [t for t in core_list(env, "--all", "--label=" + OWN_LABEL) if target in (t["address"], t.get("name"))]
    live = [t for t in mine if t["state"] == "live"]
    # `rm` is for a finished one. A live one goes on to herdr-core, which says to kill it first.
    found = ([t for t in mine if t["state"] != "live"] or live) if verb == "rm" else live
    if len(found) != 1:
        deny("not a %sterminal Hermes started: %s" % ("" if verb == "rm" else "live ", target), argv)
    if verb in ("send", "keys") and found[0].get("agent") != "omp":
        deny("%s runs %s, not omp" % (target, found[0].get("agent")), argv)
    return found[0]["address"]


def core(argv):
    """Check a herdr-core command, whose first word is `herdr-core` or `hc`, and run it."""
    if len(argv) < 2:
        deny("usage: herdr-core <verb> ...", argv)
    verb = argv[1]
    if verb not in CORE_ALLOWED:
        deny("not allowed: herdr-core %s" % verb[:80], argv)
    usage, allowed, least, most = CORE_ALLOWED[verb]
    flags, words = core_words(argv, allowed, verb == "run")
    if len(words) < least or (most is not None and len(words) > most):
        deny("usage: herdr-core %s" % usage, argv)
    if verb == "server" and words != ["status"]:
        deny("not allowed: herdr-core server %s" % words[0][:80], argv)
    if verb in CORE_TERMINAL and not TERMINAL.fullmatch(words[0]):
        deny("not a terminal of this machine: %s" % words[0][:80], argv)
    space = None
    if verb == "run":
        given, space = core_run(flags, words, argv)
    else:
        given = [flag if value is None else "%s=%s" % (flag, value) for flag, value in flags]

    env = {k: v for k, v in os.environ.items() if not k.startswith("HC_")}
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    if not core_running(env):
        reason = "herdr-core is not running on this host, and Hermes may not start it"
        log({"ts": time.time(), "client": client(), "unavailable": reason, "argv": argv})
        print(json.dumps({"error": {"code": "herdr_core_not_running", "message": reason}}), file=sys.stderr)
        sys.exit(CORE_NOT_RUNNING)
    if space and not core_list(env, "--label=" + space):
        deny("no live terminal is in that space: %s" % space, argv)
    if verb in CORE_OWN:
        words[0] = core_own(verb, words[0], env, argv)

    log_call(argv)
    if verb == "server":
        command = [HERDR_CORE, "server", "status"] + given
    else:
        # Words go after `--`: herdr-core never reads one of them as a flag.
        command = [HERDR_CORE, verb] + given + (["--"] + words if words else [])
    os.execve(HERDR_CORE, command, env)


def main():
    raw = os.environ.get("SSH_ORIGINAL_COMMAND", "")
    try:
        argv = shlex.split(raw)
    except ValueError as e:
        deny("unparsable command: %s" % e, [raw[:200]])
    if argv[:1] in (["herdr-core"], ["hc"]):
        return core(argv)
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

    log_call(argv)

    env = {k: v for k, v in os.environ.items() if not k.startswith("HERDR_")}
    env.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    os.execve(HERDR, [HERDR] + argv, env)


if __name__ == "__main__":
    main()
