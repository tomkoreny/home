"""Tests of path_in_order (path-order.sh), which puts the Mac's PATH in one order.

The inputs are the three orders shell start-up was seen to leave on the Mac,
with the directories shortened to names.

  python3 -B modules/home/shell/test_path_order.py
"""

import shutil
import subprocess
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

SCRIPT = Path(__file__).with_name("path-order.sh")
NIX = ["/home/.nix-profile/bin", "/etc/profiles/per-user/tom/bin", "/run/current-system/sw/bin", "/nix/default/bin"]
OWN = ["/home/.local/bin", "/home/npm/bin", "/home/pnpm", "/home/pnpm/bin"]
HOMEBREW = ["/opt/homebrew/bin", "/opt/homebrew/sbin"]
SYSTEM = ["/usr/local/bin", "/cryptex/usr/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", "/Library/Apple/usr/bin"]
STANDARD = NIX + OWN + HOMEBREW + SYSTEM

# A login shell from a clean environment: nix-darwin's list, Homebrew put in
# front by `brew shellenv`, pnpm by ~/.bashrc.
CLEAN = ["/home/pnpm", "/home/pnpm/bin", *HOMEBREW, *NIX, "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
# A terminal of the Herdr app before 2026-11-15.
NESTED = [
    "/etc/profiles/per-user/tom/bin",
    "/home/pnpm",
    "/home/pnpm/bin",
    *SYSTEM,
    "/home/.nix-profile/bin",
    "/run/current-system/sw/bin",
    "/nix/default/bin",
    "/home/.local/bin",
    "/opt/homebrew/bin",
]
# `bash -lc`: no Homebrew.
NOT_INTERACTIVE = [*NIX, "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]


def path_helper(path: list[str]) -> list[str]:
    """What /etc/profile does to PATH in a login shell: the system directories first."""
    return SYSTEM + [entry for entry in path if entry not in SYSTEM]


def in_order(path: list[str]) -> list[str]:
    done = subprocess.run(
        ["bash", "-c", '. "$0"; path_in_order "$@"', str(SCRIPT), *(":".join(part) for part in (path, NIX, OWN, HOMEBREW, SYSTEM))],
        check=True,
        capture_output=True,
        text=True,
    )
    return done.stdout.rstrip("\n").split(":")


class PathInOrder(unittest.TestCase):
    def test_every_start_up_order_ends_the_same(self):
        for name, path in (("clean", CLEAN), ("nested", NESTED), ("not interactive", NOT_INTERACTIVE)):
            with self.subTest(name):
                self.assertEqual(in_order(path), STANDARD)

    def test_what_was_put_in_front_stays_in_front(self):
        venv = ["/project/.venv/bin", "/nix/store/abc-nodejs/bin"]
        self.assertEqual(in_order(venv + STANDARD), venv + STANDARD)

    def test_it_stays_in_front_in_a_login_shell_started_from_there(self):
        venv = ["/project/.venv/bin"]
        self.assertEqual(in_order(path_helper(venv + STANDARD)), venv + STANDARD)

    def test_what_was_added_behind_goes_between_homebrew_and_the_system(self):
        added = "/Applications/Ghostty.app/Contents/MacOS"
        expected = NIX + OWN + HOMEBREW + [added] + SYSTEM
        self.assertEqual(in_order(CLEAN + [added]), expected)
        self.assertEqual(in_order(path_helper(expected)), expected)

    def test_repeats_and_empty_entries_go(self):
        self.assertEqual(in_order(["/x", "", "/x", *CLEAN, "/usr/bin", "/y", "/y"]), ["/x"] + NIX + OWN + HOMEBREW + ["/y"] + SYSTEM)

    def test_names_that_a_shell_would_expand_are_kept_as_they_are(self):
        odd = ["/tmp/*", "/with space/bin"]
        self.assertEqual(in_order(odd + STANDARD), odd + STANDARD)


if __name__ == "__main__":
    if shutil.which("bash") is None:
        raise SystemExit("bash is not installed")
    unittest.main()
