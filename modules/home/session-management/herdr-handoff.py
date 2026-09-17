"""Hand off running local sessions to the activated Herdr release, never restart them."""

import json
import os
import subprocess
import sys


def main():
    herdr = sys.argv[1]
    # Activation can run inside a pane. Do not inherit its socket, session,
    # remote target, or nested-launch guard. Keep the user's config location.
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("HERDR_") or key == "HERDR_CONFIG_PATH"
    }

    def invoke(*args):
        return subprocess.run(
            [herdr, *args],
            env=environment,
            text=True,
            capture_output=True,
            check=True,
            timeout=120,
        ).stdout

    def warn(session, error):
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(
            f"herdr-handoff: {session}: {detail}; no stop/restart attempted. "
            "Check `herdr status` for this session before retrying.",
            file=sys.stderr,
        )

    try:
        sessions = json.loads(invoke("session", "list", "--json"))["sessions"]
    except (OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
        warn("session discovery", error)
        return

    for session in sessions:
        if not session["running"]:
            continue
        name = session["name"]
        target = ["--session", name]
        try:
            status = json.loads(invoke(*target, "status", "--json"))
            server, client = status["server"], status["client"]
            if not server["running"] or server["version"] == client["version"]:
                continue
            if not (server.get("capabilities") or {}).get("live_handoff", False):
                warn(name, "running server does not advertise live handoff")
                continue
            print(f"herdr-handoff: {name}: {server['version']} -> {client['version']}", flush=True)
            invoke(
                *target, "server", "live-handoff",
                "--import-exe", herdr,
                "--expected-version", client["version"],
                "--expected-protocol", str(client["protocol"]),
            )
            updated = json.loads(invoke(*target, "status", "--json"))["server"]
            if not updated["running"] or updated["version"] != client["version"]:
                warn(name, "handoff returned without the expected server version")
                continue
            print(f"herdr-handoff: {name}: running {updated['version']}", flush=True)
        except (OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
            warn(name, error)


if __name__ == "__main__":
    main()
