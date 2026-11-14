"""Tests of the Mac backup controller (backup.sh) against a scratch restic repository.

Each test runs the controller's `main` as launchd would at one of its slots.
Three things are stood in for: the Mac is always on mains power and at home,
and the snapshot job is restic started here, the way that job starts it, on a
scratch folder. A file nobody may read makes restic write a snapshot without
it and exit with status 3, which on the Mac is what a missing Full Disk
Access grant does.

  nix shell nixpkgs#restic nixpkgs#jq -c python3 -B modules/darwin/backup/test_backup.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

SCRIPT = Path(__file__).with_name("backup.sh")
HOST = "testmac"
TAG = "unconfirmed"
DAY = 24 * 60 * 60

STAND_INS = """
on_mains() { true; }
at_home() { true; }
take_snapshot() {
  if [ -n "$SNAPSHOT_TIME" ]; then
    "$RESTIC" backup --host "$HOST" --tag "$UNCONFIRMED" --time "$SNAPSHOT_TIME" "$SOURCE" >> "$LOG" 2>&1
    echo $?
  else
    echo "$SNAPSHOT_STATUS"
  fi
}
"""


def setUpModule():
    for tool in ("restic", "jq", "bash"):
        if shutil.which(tool) is None:
            raise unittest.SkipTest(f"{tool} is not installed")
    if os.geteuid() == 0:
        raise unittest.SkipTest("root can read every file, so no snapshot would be incomplete")


class Controller(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="mac-backup-test-"))
        self.addCleanup(self.remove_scratch)
        self.source = self.root / "Users"
        self.source.mkdir()
        (self.source / "note.txt").write_text("anyone may read this\n")
        self.private = self.source / "private.txt"
        self.private.write_text("this needs the grant\n")
        self.status = self.root / "db" / "status.json"
        self.log = self.root / "backup.log"
        (self.root / "password").write_text("test\n")
        self.restic = self.root / "restic"
        self.restic.write_text(
            "#!/bin/sh\n"
            f'exec restic --repo "{self.root}/repo" --password-file "{self.root}/password" '
            f'--cache-dir "{self.root}/cache" "$@"\n'
        )
        self.restic.chmod(0o755)
        subprocess.run([self.restic, "init"], check=True, capture_output=True)

    def remove_scratch(self):
        self.private.chmod(0o600)
        shutil.rmtree(self.root)

    def slot(self, when: str = "", *, readable: bool = True, job_status: int = 0) -> int:
        """One of the controller's slots; returns its exit status.

        With `when`, the snapshot job runs restic and the snapshot carries that
        time. Without, the job only reports `job_status`.
        """
        self.private.chmod(0o600 if readable else 0o000)
        env = {
            **os.environ,
            "RESTIC": str(self.restic),
            "JQ": "jq",
            "HOST": HOST,
            "STATUS": str(self.status),
            "LOG": str(self.log),
            "SNAPSHOT_JOB": "unused",
            "SNAPSHOT_PROGRAM": "/the/pinned/restic",
            "UNCONFIRMED": TAG,
            "MINIO_HOST": "unused",
            "MINIO_PORT": "0",
            "SOURCE": str(self.source),
            "SNAPSHOT_TIME": when,
            "SNAPSHOT_STATUS": str(job_status),
            "STAND_INS": STAND_INS,
        }
        with self.log.open("a") as log:
            return subprocess.run(
                ["bash", "-u", "-c", '. "$0"; eval "$STAND_INS"; main', str(SCRIPT)],
                env=env,
                stdout=log,
                stderr=log,
            ).returncode

    def backup_without_the_controller(self, when: str) -> None:
        subprocess.run(
            [self.restic, "backup", "--host", HOST, "--time", when, self.source], check=True, capture_output=True
        )

    def a_day_passes(self) -> None:
        recorded = self.recorded()
        for field in ("finishedAt", "lastSuccessAt", "lastIncompleteAt"):
            if recorded[field]:
                recorded[field] -= DAY
        self.status.write_text(json.dumps(recorded))

    def recorded(self) -> dict:
        return json.loads(self.status.read_text())

    def snapshots(self) -> dict[str, list[str]]:
        """The repository's snapshots: time to the minute -> tags."""
        listed = subprocess.run([self.restic, "snapshots", "--json"], check=True, capture_output=True, text=True)
        return {snapshot["time"][:16]: snapshot.get("tags") or [] for snapshot in json.loads(listed.stdout)}

    def test_complete_run_is_confirmed_and_the_next_slot_rests(self):
        self.assertEqual(self.slot("2026-03-02 10:00:00"), 0)
        self.assertEqual(self.snapshots(), {"2026-03-02T10:00": []})
        recorded = self.recorded()
        self.assertEqual((recorded["result"], recorded["error"]), ("success", ""))
        self.assertEqual(recorded["lastSuccessAt"], recorded["finishedAt"])

        self.assertEqual(self.slot("2026-03-02 13:00:00"), 0)
        self.assertEqual(list(self.snapshots()), ["2026-03-02T10:00"])

    def test_incomplete_run_is_reported_stays_marked_and_is_not_repeated_that_day(self):
        self.assertNotEqual(self.slot("2026-03-02 10:00:00", readable=False), 0)
        self.assertEqual(self.snapshots(), {"2026-03-02T10:00": [TAG]})
        recorded = self.recorded()
        self.assertEqual(recorded["result"], "incomplete")
        self.assertIn("/the/pinned/restic have Full Disk Access", recorded["error"])
        self.assertIn("private.txt", recorded["error"])
        self.assertEqual(recorded["lastSuccessAt"], 0)

        self.slot("2026-03-02 13:00:00", readable=False)
        self.assertEqual(list(self.snapshots()), ["2026-03-02T10:00"])
        self.a_day_passes()
        self.slot("2026-03-03 10:00:00", readable=False)
        self.assertEqual(self.snapshots(), {"2026-03-02T10:00": [TAG], "2026-03-03T10:00": [TAG]})

    # restic keeps the last snapshot of each day, and the oldest one while a
    # policy still has room, so both tests below start a day earlier than the
    # snapshots they are about.

    def test_incomplete_snapshot_is_never_kept_in_place_of_a_complete_one(self):
        # The last snapshot of 2 March is the incomplete one.
        self.slot("2026-03-01 10:00:00")
        self.a_day_passes()
        self.slot("2026-03-02 10:00:00")
        self.a_day_passes()
        self.slot("2026-03-02 22:00:00", readable=False)
        self.a_day_passes()
        self.assertEqual(self.slot("2026-03-03 10:00:00"), 0)
        self.assertEqual(
            self.snapshots(),
            {
                "2026-03-01T10:00": [],
                "2026-03-02T10:00": [],
                "2026-03-02T22:00": [TAG],
                "2026-03-03T10:00": [],
            },
        )

    def test_incomplete_run_removes_nothing(self):
        # Two snapshots on 2 March: retention drops the earlier one as soon
        # as it is applied, which the last step shows.
        for when in ("2026-03-01 08:00:00", "2026-03-02 08:00:00", "2026-03-02 12:00:00"):
            self.backup_without_the_controller(when)
        self.slot("2026-03-03 10:00:00", readable=False)
        self.assertEqual(
            self.snapshots(),
            {
                "2026-03-01T08:00": [],
                "2026-03-02T08:00": [],
                "2026-03-02T12:00": [],
                "2026-03-03T10:00": [TAG],
            },
        )

        self.a_day_passes()
        self.assertEqual(self.slot("2026-03-04 10:00:00"), 0)
        self.assertEqual(
            self.snapshots(),
            {
                "2026-03-01T08:00": [],
                "2026-03-02T12:00": [],
                "2026-03-03T10:00": [TAG],
                "2026-03-04T10:00": [],
            },
        )

    def test_success_without_a_new_snapshot_confirms_nothing(self):
        self.slot("2026-03-02 10:00:00", readable=False)
        self.a_day_passes()
        self.assertNotEqual(self.slot(job_status=0), 0)
        self.assertEqual(self.snapshots(), {"2026-03-02T10:00": [TAG]})
        self.assertEqual(self.recorded()["result"], "failure")

    def test_failed_run_is_tried_again_at_the_next_slot(self):
        self.assertNotEqual(self.slot(job_status=1), 0)
        recorded = self.recorded()
        self.assertEqual(recorded["result"], "failure")
        self.assertIn("status 1", recorded["error"])

        self.assertEqual(self.slot("2026-03-02 13:00:00"), 0)
        self.assertEqual(self.recorded()["result"], "success")
        self.assertEqual(self.snapshots(), {"2026-03-02T13:00": []})


if __name__ == "__main__":
    unittest.main()
