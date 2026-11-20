"""Tests of gate.py, the forced command behind Hermes' SSH key.

The gate runs the way sshd runs it: as a process with the request in
SSH_ORIGINAL_COMMAND. The old herdr is a stand-in that prints its arguments.
herdr-core is the installed one, against a private core with a stand-in
`omp`, so the commands the gate builds are read by the real CLI; those tests
are skipped where it is not installed. Nothing here touches the user's own
core or log: HOME, XDG_RUNTIME_DIR and XDG_STATE_HOME are scratch.

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
ENV: dict[str, str]
GATE: Path  # gate.py with the stand-in herdr and the installed herdr-core
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


def setUpModule():
    global ROOT, WORK, ENV, GATE, GATE_NO_CORE, CORE_CALLED
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

    # OMP as far as the gate and the core care: it starts where it is told and reads what is typed.
    program("omp", '#!/bin/sh\necho "omp in $(pwd): $*"\nwhile IFS= read -r line; do echo "got: $line"; done\n')
    herdr = program("herdr-stand-in", f"#!{sys.executable}\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n")
    noted = program("core-stand-in", f'#!/bin/sh\necho called >> "{CORE_CALLED}"\n')

    source = Path(__file__).with_name("gate.py").read_text().replace("@herdr@", str(herdr))
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


def hc(*args):
    """Ask the private core directly, past the gate."""
    # `--json` goes before `--`: after it, it would be the program's argument.
    cut = args.index("--") if "--" in args else len(args)
    command = [HC, *args[:cut], "--json", *args[cut:]]
    result = subprocess.run(command, env=ENV, capture_output=True, text=True, check=True, timeout=60)
    return json.loads(result.stdout)


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
            # The folder: given, whole, existing, in the home directory.
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
            if terminal["state"] == "live":
                hc("kill", terminal["address"])
            hc("rm", terminal["address"])

    def ok(self, command, **env):
        result = gate(command, **env)
        self.assertEqual(result.returncode, 0, f"{command!r}: {result.stderr}")
        self.assertEqual(last_log()["argv"], shlex.split(command))
        self.assertNotIn("denied", last_log())
        return result.stdout

    def test_status(self):
        self.assertEqual(json.loads(self.ok("herdr-core server status"))["pid"], hc("server", "status")["pid"])
        self.assertEqual(json.loads(self.ok("hc server status --json"))["pid"], hc("server", "status")["pid"])

    def test_a_session_from_start_to_removal(self):
        started = json.loads(self.ok(f"herdr-core run --bg --name scratch --cwd {WORK} -- omp --flag 'first task'"))
        address = started["address"]
        info = hc("get", address)
        self.assertEqual(info["argv"], ["omp", "--flag", "first task"])
        self.assertEqual(info["cwd"], str(WORK))
        self.assertEqual(info["name"], "scratch")
        self.assertEqual(info["labels"], {"started-by": "hermes"})
        self.assertIsNone(info["parent"])

        self.assertEqual([t["address"] for t in json.loads(self.ok("hc ls"))["terminals"]], [address])
        listed = json.loads(self.ok("herdr-core ls --all --label started-by=hermes --json"))["terminals"]
        self.assertEqual([t["name"] for t in listed], ["scratch"])
        self.assertEqual(json.loads(self.ok("herdr-core get scratch"))["address"], address)

        self.ok("herdr-core send -- scratch '--not a flag; $HOME'")
        self.ok(f"herdr-core keys {address} a b enter")
        wait_for(lambda: "got: ab" in gate("herdr-core read scratch").stdout, "the keys to arrive")
        screen = self.ok("herdr-core read --lines 20 scratch")
        self.assertIn(f"omp in {WORK}: --flag first task", screen)
        self.assertIn("got: --not a flag; $HOME", screen)
        self.assertEqual(json.loads(self.ok("herdr-core wait --timeout 1 scratch"))["reason"], "timeout")
        sent = json.loads(self.ok("herdr-core send --force --wait --timeout=1 -- scratch again"))
        self.assertEqual(sent["wait"]["reason"], "timeout")

        self.assertEqual(json.loads(self.ok("herdr-core kill scratch"))["state"], "finished")
        self.assertEqual(json.loads(self.ok("herdr-core rm scratch")), {"removed": address})
        self.assertEqual(hc("ls", "--all")["terminals"], [])

    def test_a_terminal_hermes_did_not_start_is_read_only(self):
        address = hc("run", "--bg", "--no-parent", "--name", "toms", "--cwd", str(WORK), "--", "omp")["address"]
        self.assertEqual(json.loads(self.ok("herdr-core get toms"))["address"], address)
        self.assertIn(f"omp in {WORK}", self.ok(f"herdr-core read {address}"))
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
        self.assertNotIn("got:", gate("herdr-core read toms").stdout)

    def test_no_typing_into_a_shell_under_hermes_label(self):
        # What a kept terminal is after a reboot: its labels, and a shell.
        shell = ["--label", "started-by=hermes", "--", "sh"]
        address = hc("run", "--bg", "--no-parent", "--name", "recovered", "--cwd", str(WORK), *shell)["address"]
        self.assertEqual(self.assertDenied('herdr-core send recovered "touch typed"'), "recovered runs sh, not omp")
        self.assertEqual(self.assertDenied(f"herdr-core keys {address} a enter"), f"{address} runs sh, not omp")
        self.assertFalse((WORK / "typed").exists())
        self.assertNotIn("touch typed", gate("herdr-core read recovered").stdout)
        self.assertEqual(json.loads(self.ok("herdr-core kill recovered"))["state"], "finished")

    def test_a_tab_only_in_a_space_that_exists(self):
        space = ["--label", "herdr.space=sp0123abc", "--", "omp"]
        hc("run", "--bg", "--no-parent", "--name", "toms", "--cwd", str(WORK), *space)
        started = json.loads(self.ok(f"herdr-core run --cwd {WORK} --label herdr.space=sp0123abc -- omp"))
        self.assertEqual(hc("get", started["address"])["labels"], {"started-by": "hermes", "herdr.space": "sp0123abc"})
        reason = self.assertDenied(f"herdr-core run --cwd {WORK} --label herdr.space=sp9999 -- omp")
        self.assertEqual(reason, "no live terminal is in that space: herdr.space=sp9999")
        self.assertEqual(len(hc("ls", "--all")["terminals"]), 2)

    def test_another_session_cannot_be_chosen(self):
        address = hc("run", "--bg", "--no-parent", "--cwd", str(WORK), "--", "omp")["address"]
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
