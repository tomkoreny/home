"""Tests of gate.py, the forced command behind Hermes' SSH key.

The gate runs the way sshd runs it: as a process with the request in
SSH_ORIGINAL_COMMAND. The old herdr is a stand-in that prints its arguments.
herdr-core is the installed one, against a private core with a stand-in
`omp`, so the commands the gate builds are read by the real CLI; those tests
are skipped where it is not installed. Another machine is a second private
core, reached through a command instead of ssh. Nothing here touches the
user's own core or log: HOME, XDG_RUNTIME_DIR and XDG_STATE_HOME are scratch.

  python3 -B modules/nixos/hermes-herdr-gate/test_gate.py
"""

import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

HC = shutil.which("herdr-core")
ROOT: Path
WORK: Path
OMP: Path  # the stand-in the gate starts, by its whole path
ENV: dict[str, str]
GATE: Path  # gate.py with the stand-in herdr and OMP and the installed herdr-core
GATE_NO_CORE: Path  # the same with a herdr-core that only notes it was called
CORE_CALLED: Path

# The old herdr's allowlist as it was before herdr-core was added.
OLD_ALLOWED = {
    "agent": ["list", "get", "read", "prompt", "send-keys", "wait", "start", "rename"],
    "pane": ["list", "get", "read", "split", "wait-output", "send-keys", "close"],
    "workspace": ["list", "get", "create"],
    "tab": ["list", "get", "create", "close"],
    "api": ["snapshot"],
    "status": ["server"],
}

# OMP as far as the gate and the core care: it reports a status, which is
# what makes a terminal an agent to herdr-core, starts where it is told, reads
# what is typed, and can put another program in front of itself.
OMP_STAND_IN = r"""#!/bin/sh
printf '\033]7501;state=idle\033\\'
echo "omp in $(pwd): $*"
[ "$1" = --shell-in-front ] && sh -i
while IFS= read -r line; do echo "got: $line"; done
"""


def setUpModule():
    global ROOT, WORK, OMP, ENV, GATE, GATE_NO_CORE, CORE_CALLED
    ROOT = Path(tempfile.mkdtemp(prefix="hermes-gate-test-")).resolve()
    WORK = ROOT / "work"
    WORK.mkdir()
    (ROOT / "run").mkdir(mode=0o700)
    (ROOT / "no-core").mkdir(mode=0o700)
    (ROOT / "bin").mkdir()
    (ROOT / "out").symlink_to("/etc")
    CORE_CALLED = ROOT / "core-called"

    def program(name, text):
        path = ROOT / "bin" / name
        path.write_text(text)
        path.chmod(0o755)
        return path

    OMP = program("omp", OMP_STAND_IN)
    herdr = program("herdr-stand-in", f"#!{sys.executable}\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n")
    noted = program("core-stand-in", f'#!/bin/sh\necho called >> "{CORE_CALLED}"\n')

    source = Path(__file__).with_name("gate.py").read_text()
    source = source.replace("@herdr@", str(herdr)).replace("@omp@", str(OMP))
    GATE = ROOT / "gate.py"
    GATE.write_text(source.replace("@herdr_core@", HC or str(noted)))
    GATE_NO_CORE = ROOT / "gate-no-core.py"
    GATE_NO_CORE.write_text(source.replace("@herdr_core@", str(noted)))

    path = os.environ.get("PATH", "")
    ENV = dict(
        HOME=str(ROOT),
        XDG_RUNTIME_DIR=str(ROOT / "run"),
        XDG_STATE_HOME=str(ROOT / "state"),
        # The stand-in OMP first; the guards keep a shell the core starts from
        # rebuilding PATH out of the system profile.
        PATH=f"{ROOT / 'bin'}:{path}",
        SHELL=shutil.which("sh") or "/bin/sh",
        TERM="xterm-256color",
        __NIXOS_SET_ENVIRONMENT_DONE="1",
        __ETC_PROFILE_SOURCED="1",
        SSH_CLIENT="192.0.2.7 50000 22",
    )


def tearDownModule():
    shutil.rmtree(ROOT, ignore_errors=True)


def gate(command, script=None, **env):
    """Run the gate on one request, as sshd would."""
    return subprocess.run(
        [sys.executable, "-B", str(script or GATE)],
        env={**ENV, **env, "SSH_ORIGINAL_COMMAND": command},
        capture_output=True,
        text=True,
        timeout=60,
    )


def last_log():
    lines = (ROOT / ".local/state/herdr-hermes-gate/log.jsonl").read_text().splitlines()
    return json.loads(lines[-1])


def hc(*args, env=None):
    """Ask a private core directly, past the gate: this machine's, or another's with its env."""
    # `--json` goes before `--`: after it, it would be the program's argument.
    cut = args.index("--") if "--" in args else len(args)
    command = [HC, *args[:cut], "--json", *args[cut:]]
    result = subprocess.run(command, env=env or ENV, capture_output=True, text=True, check=True, timeout=60)
    return json.loads(result.stdout)


def screen(terminal, env=None):
    result = subprocess.run([HC, "read", "--", terminal], env=env or ENV, capture_output=True, text=True, check=True)
    return result.stdout


def in_front(terminal):
    """The program herdr-core reports in front of a terminal, None until it knows."""
    return (hc("get", terminal).get("foreground") or {}).get("name")


def reported(terminal):
    """The status herdr-core lists for a terminal, None when its program reports none."""
    return next(t.get("status") for t in hc("ls", "--all")["terminals"] if t["address"] == terminal)


def wait_for(check, what, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.2)
    raise AssertionError(f"timed out waiting for {what}")


class GateTestCase(unittest.TestCase):
    def assertDenied(self, command, script=None, **env):
        result = gate(command, script, **env)
        self.assertEqual(result.returncode, 126, f"{command!r} was not denied: {result.stdout}{result.stderr}")
        self.assertEqual(result.stdout, "")
        error = json.loads(result.stderr)["error"]
        self.assertEqual(error["code"], "hermes_gate_denied")
        entry = last_log()
        self.assertEqual(entry["denied"], error["message"])
        self.assertEqual(entry["client"], "192.0.2.7")
        return error["message"]


class OldHerdr(GateTestCase):
    def passes(self, command, argv):
        result = gate(command)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), argv)
        entry = last_log()
        del entry["ts"]
        self.assertEqual(entry, {"client": "192.0.2.7", "argv": argv})

    def test_every_allowed_verb_reaches_herdr(self):
        for group, verbs in OLD_ALLOWED.items():
            for verb in verbs:
                with self.subTest(group=group, verb=verb):
                    self.passes(f"herdr {group} {verb}", [group, verb])

    def test_arguments_reach_herdr_as_written(self):
        self.passes("agent list", ["agent", "list"])
        self.passes(
            "herdr agent read w7:p2K --source recent-unwrapped --lines 40",
            ["agent", "read", "w7:p2K", "--source", "recent-unwrapped", "--lines", "40"],
        )
        self.passes(
            'herdr agent prompt w7:p2K "run the tests; then $HOME" --wait',
            ["agent", "prompt", "w7:p2K", "run the tests; then $HOME", "--wait"],
        )
        # After `--` the words are the agent's own, forbidden names included.
        self.passes(
            "herdr agent start fix --kind omp --pane w7:p2K -- --session last",
            ["agent", "start", "fix", "--kind", "omp", "--pane", "w7:p2K", "--", "--session", "last"],
        )

    def test_the_rest_is_denied(self):
        for command in (
            "",
            "herdr",
            "herdr --version",
            "herdr pane run w7:p2K id",
            "herdr pane send-text w7:p2K id",
            "herdr workspace close w7",
            "herdr server stop",
            "herdr session attach main",
            "herdr agent list --session other",
            "herdr agent list --machine=box",
            "herdr tab create --focus",
            "herdr agent start fix --kind omp --pane w7:p2K --env A=B",
            'herdr agent prompt w7:p2K "no closing quote',
        ):
            with self.subTest(command=command):
                self.assertDenied(command)


class HerdrCoreDenied(GateTestCase):
    """Refused on the request alone: the core is neither asked nor started."""

    def test_denied_without_calling_herdr_core(self):
        work = WORK
        for command in (
            "herdr-core",
            "hc --help",
            "herdr-core frobnicate t1",
            "herdr-core agent list",
            # Commands, files, takeover, labels, other machines, the core itself.
            "herdr-core exec sh -c id",
            "herdr-core exec --env A=B -- id",
            "herdr-core file read /etc/passwd",
            "herdr-core put t1 /etc/passwd",
            "herdr-core attach t1",
            "herdr-core label t1 started-by=hermes",
            "herdr-core keep t1",
            "herdr-core interrupt t1",
            "herdr-core events",
            "herdr-core templates",
            "herdr-core machine ls",
            "herdr-core connect --session other",
            "herdr-core update",
            "herdr-core schema",
            "herdr-core server",
            "herdr-core server start",
            "herdr-core server stop",
            "herdr-core server restart --fresh",
            "herdr-core server status extra",
            # `run` without a program is a shell; one string is a shell line.
            "herdr-core run",
            f"herdr-core run --cwd {work}",
            f"herdr-core run --cwd {work} -- sh -c id",
            f"herdr-core run --cwd {work} bash",
            f"herdr-core run --cwd {work} -- 'omp; id'",
            f"herdr-core run --cwd {work} -- /bin/omp",
            f"herdr-core run --cwd {work} -- --on macos omp",
            # OMP alone: its flags would move it, reopen a session or load code.
            f"herdr-core run --cwd {work} -- omp --cwd /etc",
            f"herdr-core run --cwd {work} -- omp --resume last",
            f"herdr-core run --cwd {work} -- omp -c",
            f"herdr-core run --cwd {work} -- omp --hook {work}/hook.ts",
            f"herdr-core run --cwd {work} -- omp 'do this'",
            f"herdr-core run --cwd {work} omp --model opus",
            # The folder: given, from /, existing, in the home directory.
            "herdr-core run -- omp",
            "herdr-core run --cwd",
            "herdr-core run --cwd /etc -- omp",
            "herdr-core run --cwd work -- omp",
            f"herdr-core run --cwd {ROOT}/.. -- omp",
            f"herdr-core run --cwd {ROOT}/out -- omp",
            f"herdr-core run --cwd {ROOT}/missing -- omp",
            # Flags of `run` Hermes has no use for.
            f"herdr-core run --on macos --cwd {work} -- omp",
            f"herdr-core run --on=macos --cwd {work} -- omp",
            f"herdr-core run --parent t1 --cwd {work} -- omp",
            f"herdr-core run --keep --cwd {work} -- omp",
            f"herdr-core run --rm --cwd {work} -- omp",
            f"herdr-core run --outlive-parent --cwd {work} -- omp",
            f"herdr-core run --label started-by=tom --cwd {work} -- omp",
            f"herdr-core run --label herdr.tab=tb1 --cwd {work} -- omp",
            f"herdr-core run --name 'two words' --cwd {work} -- omp",
            f"herdr-core run --bg=yes --cwd {work} -- omp",
            # Terminals: one of this machine, and the words each verb takes.
            "herdr-core get",
            "herdr-core get t1 t2",
            "herdr-core get macos/t1",
            "herdr-core read macos/t1",
            "herdr-core send macos/t1 hello",
            "herdr-core kill macos/t1",
            "herdr-core send t1",
            "herdr-core send t1 two words",
            "herdr-core send --on macos t1 hello",
            "herdr-core keys t1",
            "herdr-core wait --children all",
            "herdr-core wait --output ready t1",
            "herdr-core read --session other t1",
            "herdr-core ls extra",
            "herdr-core get -h",
        ):
            with self.subTest(command=command):
                self.assertDenied(command, GATE_NO_CORE, XDG_RUNTIME_DIR=str(ROOT / "no-core"))
        self.assertFalse(CORE_CALLED.exists(), "a denied request reached herdr-core")
        self.assertEqual(os.listdir(ROOT / "no-core"), [])

    def test_reasons_name_what_was_wrong(self):
        for command, reason in (
            ("herdr-core exec id", "not allowed: herdr-core exec"),
            (f"herdr-core run --on macos --cwd {WORK} -- omp", "flag not allowed: --on"),
            (f"herdr-core run --cwd {WORK} -- sh -c id", "only omp may be started: sh"),
            (
                f"herdr-core run --cwd {WORK} -- omp --resume last",
                "omp takes no arguments here: send its prompt with `herdr-core send`",
            ),
            ("herdr-core get macos/t1", "not a terminal of this machine: macos/t1"),
        ):
            with self.subTest(command=command):
                self.assertEqual(self.assertDenied(command, GATE_NO_CORE), reason)


@unittest.skipUnless(HC and sys.platform == "linux", "herdr-core is not installed")
class HerdrCore(GateTestCase):
    """Against a private core, started here: the gate itself never starts one."""

    @classmethod
    def setUpClass(cls):
        hc("server", "start")

    @classmethod
    def tearDownClass(cls):
        hc("server", "stop")

    def tearDown(self):
        for terminal in hc("ls", "--all")["terminals"]:
            if "/" in terminal["address"]:
                continue  # another machine's, which goes with its core
            if terminal["state"] == "live":
                hc("kill", terminal["address"])
            hc("rm", terminal["address"])

    def ok(self, command, **env):
        result = gate(command, **env)
        self.assertEqual(result.returncode, 0, f"{command!r}: {result.stderr}")
        self.assertEqual(last_log()["argv"], shlex.split(command))
        self.assertNotIn("denied", last_log())
        return result.stdout

    def start(self, name, *program, labels=("started-by=hermes",)):
        """A terminal started past the gate, and the address it got."""
        labelled = [word for label in labels for word in ("--label", label)]
        return hc("run", "--bg", "--no-parent", "--name", name, "--cwd", str(WORK), *labelled, "--", *program)["address"]

    def agent(self, name):
        """An agent that is not Hermes': OMP, in front and reporting its status."""
        address = self.start(name, "omp", labels=())
        wait_for(lambda: in_front(address) == "omp" and reported(address) == "idle", "OMP to report its status")
        return address

    def test_status(self):
        self.assertEqual(json.loads(self.ok("herdr-core server status"))["pid"], hc("server", "status")["pid"])
        self.assertEqual(json.loads(self.ok("hc server status --json"))["pid"], hc("server", "status")["pid"])

    def test_a_session_from_start_to_removal(self):
        started = json.loads(self.ok(f"herdr-core run --bg --name scratch --cwd {WORK} -- omp"))
        address = started["address"]
        info = hc("get", address)
        self.assertEqual(info["argv"], [str(OMP)])
        self.assertEqual(info["cwd"], str(WORK))
        self.assertEqual(info["name"], "scratch")
        self.assertEqual(info["labels"], {"started-by": "hermes"})
        self.assertIsNone(info["parent"])
        wait_for(lambda: in_front(address) == "omp", "herdr-core to see OMP in front")

        self.assertEqual([t["address"] for t in json.loads(self.ok("hc ls"))["terminals"]], [address])
        listed = json.loads(self.ok("herdr-core ls --all --label started-by=hermes --json"))["terminals"]
        self.assertEqual([t["name"] for t in listed], ["scratch"])
        self.assertEqual(json.loads(self.ok("herdr-core get scratch"))["address"], address)

        self.ok("herdr-core send -- scratch '--not a flag; $HOME'")
        self.ok(f"herdr-core keys {address} a b enter")
        wait_for(lambda: "got: ab" in gate("herdr-core read scratch").stdout, "the keys to arrive")
        shown = self.ok("herdr-core read --lines 20 scratch")
        self.assertIn(f"omp in {WORK}:", shown)
        self.assertIn("got: --not a flag; $HOME", shown)
        self.assertEqual(json.loads(self.ok("herdr-core wait --timeout 1 scratch"))["reason"], "timeout")
        sent = json.loads(self.ok("herdr-core send --force --wait --timeout=1 -- scratch again"))
        self.assertIn("wait", sent, "herdr-core answers --wait with what the wait saw")

        self.assertEqual(json.loads(self.ok("herdr-core kill scratch"))["state"], "finished")
        self.assertIn("got: again", self.ok("herdr-core read scratch"), "a finished terminal of Hermes' can still be read")
        self.assertEqual(json.loads(self.ok("herdr-core rm scratch")), {"removed": address})
        self.assertEqual(hc("ls", "--all")["terminals"], [])

    def test_a_template_called_omp_does_not_run_in_its_place(self):
        template = ROOT / ".config/herdr-core/templates/omp.md"
        template.parent.mkdir(parents=True, exist_ok=True)
        template.write_text("---\nname: omp\ndescription: not OMP\ncommand: sh\n---\nBe a shell.\n")
        self.addCleanup(template.unlink)
        self.assertEqual([t["name"] for t in hc("templates")["templates"]], ["omp"])
        started = json.loads(self.ok(f"herdr-core run --cwd {WORK} -- omp"))
        info = hc("get", started["address"])
        self.assertEqual(info["argv"], [str(OMP)])
        self.assertIsNone(info["template"])

    def test_a_terminal_hermes_did_not_start_is_read_only(self):
        address = self.agent("toms")
        self.assertEqual(json.loads(self.ok("herdr-core get toms"))["address"], address)
        self.assertIn(f"omp in {WORK}", self.ok(f"herdr-core read {address}"))
        self.assertEqual(json.loads(self.ok("herdr-core wait --timeout 1 toms"))["terminal"], address)
        for command in (
            "herdr-core send toms hello",
            f"herdr-core send {address} hello",
            "herdr-core keys toms a enter",
            "herdr-core kill toms",
            f"herdr-core rm {address}",
        ):
            with self.subTest(command=command):
                self.assertIn("Hermes started", self.assertDenied(command))
        self.assertEqual(hc("get", address)["state"], "live")
        self.assertNotIn("got:", screen("toms"))

    def test_a_plain_shell_is_neither_listed_nor_read(self):
        agent = self.agent("toms")
        shell = self.start("shell", "sh", labels=())
        wait_for(lambda: in_front(shell) == "sh", "herdr-core to see the shell")
        hc("send", shell, "echo key-$((40 + 2))")
        wait_for(lambda: "key-42" in screen(shell), "the shell's output")
        for listing in ("herdr-core ls", "herdr-core ls --all --json"):
            with self.subTest(listing=listing):
                self.assertEqual([t["address"] for t in json.loads(self.ok(listing))["terminals"]], [agent])
        for command in (
            "herdr-core get shell",
            f"herdr-core get {shell}",
            "herdr-core read shell",
            f"herdr-core read --lines 50 {shell}",
            "herdr-core wait --timeout 1 shell",
        ):
            with self.subTest(command=command):
                reason = self.assertDenied(command)
                self.assertIn("not an agent or a terminal Hermes started", reason)

    def test_no_typing_unless_omp_is_in_front(self):
        # A shell under Hermes' label is what a kept terminal is after a reboot,
        # and a shell in front of OMP is OMP's own doing. Both would run the text.
        for name, program in (("recovered", ["sh"]), ("behind", [str(OMP), "--shell-in-front"])):
            with self.subTest(name=name):
                address = self.start(name, *program)
                wait_for(lambda: in_front(address) == "sh", "herdr-core to see the shell in front")
                reason = f"omp is not the program in front of {name}: sh"
                self.assertEqual(self.assertDenied(f'herdr-core send {name} "touch typed"'), reason)
                self.assertEqual(self.assertDenied(f"herdr-core send --force {name} 'touch typed'"), reason)
                self.assertIn("omp is not the program in front", self.assertDenied(f"herdr-core keys {address} a enter"))
                self.assertFalse((WORK / "typed").exists())
                self.assertNotIn("touch typed", screen(name))
                self.assertEqual(json.loads(self.ok(f"herdr-core kill {name}"))["state"], "finished")

    def test_a_tab_only_in_a_space_that_exists(self):
        # Any live terminal makes a space one that exists, a shell too.
        self.start("toms", "sh", labels=("herdr.space=sp0123abc",))
        started = json.loads(self.ok(f"herdr-core run --cwd {WORK} --label herdr.space=sp0123abc -- omp"))
        self.assertEqual(hc("get", started["address"])["labels"], {"started-by": "hermes", "herdr.space": "sp0123abc"})
        reason = self.assertDenied(f"herdr-core run --cwd {WORK} --label herdr.space=sp9999 -- omp")
        self.assertEqual(reason, "no live terminal of this machine is in that space: herdr.space=sp9999")
        self.assertEqual(len(hc("ls", "--all")["terminals"]), 2)

    def test_other_machines_stay_out(self):
        far = ROOT / "far"
        (far / "run").mkdir(parents=True, mode=0o700)
        far_env = {**ENV, "HOME": str(far), "XDG_RUNTIME_DIR": str(far / "run"), "XDG_STATE_HOME": str(far / "state")}
        via = shlex.join(["env", "-i", *(f"{key}={value}" for key, value in far_env.items()), "sh", "-c"])
        hc("machine", "add", "--via", via, "--name", "far")
        self.addCleanup(subprocess.run, [HC, "server", "stop"], env=far_env, capture_output=True, timeout=60)
        self.addCleanup(subprocess.run, [HC, "machine", "rm", "far"], env=ENV, capture_output=True, timeout=60)
        # A terminal there that looks like Hermes' own in every way but the machine.
        labels = ["--label", "started-by=hermes", "--label", "herdr.space=spfar"]
        hc("run", "--bg", "--no-parent", "--name", "scratch", "--cwd", str(far), *labels, "--", "omp", env=far_env)
        wait_for(
            lambda: [t.get("name") for t in hc("ls", "--label", "started-by=hermes")["terminals"] if t["address"].startswith("far/")] == ["scratch"],
            "herdr-core to list the other machine's terminal",
        )

        listing = json.loads(self.ok("herdr-core ls"))
        self.assertEqual(listing["terminals"], [])
        self.assertNotIn("machines", listing)
        for command in (
            "herdr-core get scratch",
            "herdr-core read scratch",
            "herdr-core send scratch hello",
            "herdr-core keys scratch a enter",
            "herdr-core kill scratch",
            "herdr-core rm scratch",
            f"herdr-core run --cwd {WORK} --label herdr.space=spfar -- omp",
        ):
            with self.subTest(command=command):
                self.assertDenied(command)
        self.assertEqual(hc("get", "scratch", env=far_env)["state"], "live")
        self.assertNotIn("got:", screen("scratch", far_env))
        self.assertEqual([t["address"] for t in hc("ls", "--all")["terminals"] if "/" not in t["address"]], [])

    def test_another_session_cannot_be_chosen(self):
        address = self.agent("toms")
        listed = json.loads(self.ok("herdr-core ls", HC_SESSION="other", HC_SOCKET=str(ROOT / "other.sock")))
        self.assertEqual([t["address"] for t in listed["terminals"]], [address])

    def test_no_core_is_reported_and_none_is_started(self):
        no_core = ROOT / "no-core"
        for command in ("herdr-core server status", "herdr-core ls", f"herdr-core run --cwd {WORK} -- omp"):
            with self.subTest(command=command):
                result = gate(command, XDG_RUNTIME_DIR=str(no_core))
                self.assertEqual(result.returncode, 69, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(json.loads(result.stderr)["error"]["code"], "herdr_core_not_running")
                self.assertIn("unavailable", last_log())
        self.assertEqual(os.listdir(no_core), [])


if __name__ == "__main__":
    unittest.main()
