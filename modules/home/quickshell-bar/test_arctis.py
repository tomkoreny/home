import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import arctis  # noqa: E402


class Stop(Exception):
    pass


class UnplugDuringSaveDelayTests(unittest.TestCase):
    """A change is unsaved for SAVE_DELAY; unplugging then drops it on the base."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.state = Path(temporary.name) / "settings.json"
        self.state.write_text(json.dumps({"eq": 0}))
        self.clock = 0.0
        self.plugged = True
        self.waits = 0
        read_end, write_end = os.pipe()
        self.addCleanup(os.close, read_end)
        self.addCleanup(os.close, write_end)
        os.write(write_end, b'{"set": "eq", "value": 2}\n')
        self.stdin = mock.Mock(fileno=lambda: read_end)

    def send(self, node, command, *values):
        if not self.plugged:
            raise OSError("No such device")

    def select(self, readable, writable, errors, timeout):
        self.waits += 1
        if self.waits == 1:
            return readable, [], []
        # Unplug right after the change, well inside the save delay.
        self.plugged = False
        if self.clock >= 10 or self.waits > 200:
            raise Stop
        self.clock += timeout
        return [], [], []

    def run_watch(self) -> list[dict]:
        output = io.StringIO()
        patches = [
            mock.patch.object(arctis, "STATE_FILE", self.state),
            mock.patch.object(arctis, "Renderer", mock.Mock()),
            mock.patch.object(arctis, "draw", mock.Mock()),
            mock.patch.object(arctis, "send", self.send),
            mock.patch.object(
                arctis, "find_control_node", lambda: "/dev/hidraw-test" if self.plugged else None
            ),
            mock.patch.object(
                arctis, "read_state", lambda *args: {"state": "on", "headset": 4, "spare": 4}
            ),
            mock.patch.object(arctis, "select", mock.Mock(select=self.select)),
            mock.patch.object(
                arctis, "time", mock.Mock(monotonic=lambda: self.clock, time=lambda: 30 + self.clock)
            ),
            mock.patch.object(sys, "stdin", self.stdin),
        ]
        with contextlib.ExitStack() as stack:
            for patch in patches:
                stack.enter_context(patch)
            stack.enter_context(contextlib.redirect_stdout(output))
            with self.assertRaises(Stop):
                arctis.watch()
        return [json.loads(line) for line in output.getvalue().splitlines()]

    def test_unplug_before_save_keeps_waiting_and_restores_saved_values(self):
        reports = self.run_watch()
        # A pending save with no device must not turn every wait into zero.
        self.assertGreaterEqual(self.clock, 10)
        self.assertEqual(json.loads(self.state.read_text()), {"eq": 0})
        self.assertEqual(
            [report["settings"] for report in reports if "settings" in report],
            [{"eq": 0}, {"eq": 2}, {"eq": 0}],
        )
        self.assertEqual(
            [report["settingError"] for report in reports if "settingError" in report],
            ["The base was unplugged before saving, so the last change was lost."],
        )


if __name__ == "__main__":
    unittest.main()
