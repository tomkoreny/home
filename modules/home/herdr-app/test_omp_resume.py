"""Recovery tests for omp-resume.py, against a private herdr-core.

Each test starts a kept terminal, records it as running an OMP session, stops
the core as a reboot does, and lets the next `hc` call bring the terminal back
as a plain shell. `omp` is a stand-in that writes its arguments to a file.
Nothing here touches the user's own core: HOME and XDG_RUNTIME_DIR are scratch.
"""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

HC = shutil.which("hc")
ROOT: Path
SAVED_ENV: dict[str, str]
LOG: list[str] = []
resume = None


def setUpModule():
    global ROOT, SAVED_ENV, resume
    if HC is None:
        raise unittest.SkipTest("herdr-core (hc) is not installed")
    ROOT = Path(tempfile.mkdtemp(prefix="omp-resume-test-"))
    (ROOT / "run").mkdir(mode=0o700)
    (ROOT / "bin").mkdir()
    stand_in = ROOT / "bin" / "omp"
    stand_in.write_text('#!/bin/sh\nprintf \'%s\\n\' "$@" > "$HOME/omp-called"\n')
    stand_in.chmod(0o755)
    SAVED_ENV = dict(os.environ)
    os.environ.clear()
    os.environ.update(
        HOME=str(ROOT),
        XDG_RUNTIME_DIR=str(ROOT / "run"),
        XDG_STATE_HOME=str(ROOT / "state"),
        # The stand-in first; the shells the core starts must not rebuild PATH
        # from /etc/profile, which the two NixOS guards below prevent.
        PATH=f"{ROOT / 'bin'}:{Path(HC).parent}:{SAVED_ENV.get('PATH', '')}",
        SHELL=shutil.which("sh", path=SAVED_ENV.get("PATH")) or "/bin/sh",
        TERM="xterm-256color",
        __NIXOS_SET_ENVIRONMENT_DONE="1",
        __ETC_PROFILE_SOURCED="1",
    )
    spec = importlib.util.spec_from_file_location("omp_resume", Path(__file__).with_name("omp-resume.py"))
    resume = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = resume
    spec.loader.exec_module(resume)
    resume.HC = HC
    resume.log = LOG.append


def tearDownModule():
    if HC is None:
        return
    subprocess.run([HC, "server", "stop"], capture_output=True, timeout=60)
    os.environ.clear()
    os.environ.update(SAVED_ENV)
    shutil.rmtree(ROOT, ignore_errors=True)


def hc(*args):
    result = subprocess.run([HC, *args, "--json"], capture_output=True, text=True, check=True, timeout=60)
    return json.loads(result.stdout)


def wait_for(check, what, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.2)
    raise AssertionError(f"timed out waiting for {what}")


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.called = ROOT / "omp-called"
        self.called.unlink(missing_ok=True)
        LOG.clear()

    def passes(self, records, until=lambda: False, count=5):
        """Runs the service's pass as its loop does, until `until` holds or `count` passes are done."""
        for _ in range(count):
            resume.one_pass(records)
            if until():
                return
            time.sleep(1)

    def recovered_terminal(self):
        """A terminal that ran a recorded OMP session, back as a plain shell after the core stopped."""
        address = hc("run", "--bg", "--keep", "--cwd", str(ROOT))["address"]
        self.addCleanup(subprocess.run, [HC, "kill", address], capture_output=True, timeout=60)
        before = wait_for(lambda: (info := hc("get", address)).get("pid") and info, "the terminal's shell")
        session = ROOT / f"{address}.jsonl"
        session.write_text("{}\n")
        records = {
            address: {
                "created": before["created_ms"],
                "shell": resume.process_id(before["pid"]),
                "shell_pid": before["pid"],
                "pty": resume.pty_of(before["pid"]),
                "omp_since": 0,
                "session": str(session),
                "seen": time.time(),
            }
        }
        subprocess.run([HC, "server", "stop"], check=True, capture_output=True, timeout=60)
        wait_for(lambda: hc("get", address).get("pid") not in (None, before["pid"]), "the terminal to come back")
        return address, records, session

    def test_recreated_shell_gets_its_session_back(self):
        address, records, session = self.recovered_terminal()

        self.passes(records, until=self.called.exists, count=20)

        self.assertTrue(self.called.exists(), f"omp was never started in the returned shell: {LOG}")
        self.assertEqual(self.called.read_text().split("\n")[:2], ["--resume", str(session)])

    def test_returned_pane_taken_over_by_another_program_receives_nothing(self):
        address, records, _ = self.recovered_terminal()
        # `exec` keeps the shell's pid, so the terminal's root process is now cat.
        subprocess.run([HC, "send", address, "exec cat"], check=True, capture_output=True, timeout=60)
        wait_for(lambda: (hc("get", address).get("foreground") or {}).get("name") == "cat", "cat to replace the shell")

        self.passes(records)

        screen = subprocess.run([HC, "read", address], capture_output=True, text=True, timeout=60).stdout
        self.assertNotIn("--resume", screen)
        self.assertFalse(self.called.exists())


if __name__ == "__main__":
    unittest.main()
