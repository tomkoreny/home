#!/usr/bin/env python3
"""Provider-neutral task CLI with a locked, atomic assignment baseline."""

import argparse
import fcntl
import hashlib
import json
import os
import sys
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from mantis_tasks import MantisProvider, TaskError, base_url


def now():
    return datetime.now(timezone.utc).isoformat()


def empty_snapshot():
    return {
        "items": [],
        "statusOptions": [],
        "updatedAt": "",
        "stale": True,
        "error": "",
        "events": [],
    }


def load_config():
    path = Path(os.environ.get("WORK_TASKS_CONFIG", "@workConfig@"))
    try:
        config = json.loads(path.read_text())
    except (OSError, ValueError, UnicodeError) as error:
        raise TaskError("Cannot read work task JSON configuration") from error
    if not isinstance(config, dict) or config.get("provider") != "mantisbt":
        raise TaskError("Work task configuration requires provider mantisbt")
    config["baseUrl"] = base_url(config.get("baseUrl"))
    if (
        not isinstance(config.get("tokenFile"), str)
        or not Path(config["tokenFile"]).is_absolute()
    ):
        raise TaskError("Work task tokenFile must be an absolute path")
    if not isinstance(config.get("label"), str) or not config["label"].strip():
        raise TaskError("Work task configuration requires a label")
    return config


def sort_tasks(items):
    # Stable passes keep the common contract independent of provider semantics.
    items.sort(key=lambda item: item["id"])
    items.sort(key=lambda item: item["updatedAt"], reverse=True)
    items.sort(key=lambda item: item["rank"])
    return items


def validate_task(item):
    if not isinstance(item, dict):
        raise TaskError("Task provider returned an invalid task")
    for key in (
        "id",
        "title",
        "statusId",
        "statusName",
        "url",
        "updatedAt",
        "searchTerms",
    ):
        if not isinstance(item.get(key), str) or not item[key]:
            raise TaskError(f"Task provider returned invalid {key}")
    if type(item.get("actionable")) is not bool or type(item.get("rank")) is not int:
        raise TaskError("Task provider returned invalid task ordering or actionability")
    if not isinstance(item.get("actions"), list):
        raise TaskError("Task provider returned invalid actions")
    action_ids = set()
    for action in item["actions"]:
        if not isinstance(action, dict):
            raise TaskError("Task provider returned invalid action")
        for key in ("id", "label", "statusId", "statusName"):
            if not isinstance(action.get(key), str) or not action[key]:
                raise TaskError("Task provider returned invalid action fields")
        if type(action.get("actionable")) is not bool or action["id"] in action_ids:
            raise TaskError(
                "Task provider returned invalid actionability or duplicate actions"
            )
        action_ids.add(action["id"])
    return item


def validate_snapshot(snapshot):
    if not isinstance(snapshot, dict) or not isinstance(snapshot.get("items"), list):
        raise TaskError("Task provider returned an invalid snapshot")
    seen = set()
    for item in snapshot["items"]:
        validate_task(item)
        if not item["actionable"] or item["id"] in seen:
            raise TaskError("Task provider returned non-actionable or duplicate tasks")
        seen.add(item["id"])
    if not isinstance(snapshot.get("statusOptions"), list):
        raise TaskError("Task provider returned invalid status options")
    option_ids = set()
    for option in snapshot["statusOptions"]:
        if (
            not isinstance(option, dict)
            or not isinstance(option.get("id"), str)
            or not option["id"]
            or not isinstance(option.get("name"), str)
            or not option["name"]
            or option["id"] in option_ids
        ):
            raise TaskError("Task provider returned invalid status option")
        option_ids.add(option["id"])
    return snapshot


class Store:
    def __init__(self, config):
        root = Path(
            os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
        )
        identity = [config["provider"], config["baseUrl"], config["tokenFile"]]
        key = hashlib.sha256(
            json.dumps(identity, separators=(",", ":")).encode()
        ).hexdigest()[:24]
        self.directory = root / "quickshell-bar" / "work-tasks" / key
        self.path = self.directory / "state.json"

    def prepare(self):
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.directory.parent, 0o700)
        os.chmod(self.directory, 0o700)

    @contextmanager
    def locked(self):
        self.prepare()
        fd = os.open(self.directory / "lock", os.O_CREAT | os.O_RDWR, 0o600)
        try:
            os.fchmod(fd, 0o600)
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    def read(self):
        try:
            state = json.loads(self.path.read_text())
            if not isinstance(state, dict) or state.get("version") != 1:
                return None
            validate_snapshot(state["snapshot"])
            if (
                not isinstance(state["account"], str)
                or not state["account"]
                or not isinstance(state["baseline"], list)
                or any(not isinstance(item, str) for item in state["baseline"])
                or not isinstance(state["snapshot"].get("updatedAt"), str)
                or type(state["needsRefresh"]) is not bool
            ):
                return None
            return state
        except (OSError, ValueError, UnicodeError, KeyError, TypeError, TaskError):
            return None

    def write(self, state):
        # Cache and baseline share one replace: no crash window between files.
        fd, temporary = tempfile.mkstemp(prefix="state.", dir=self.directory)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w") as stream:
                json.dump(state, stream, separators=(",", ":"), ensure_ascii=False)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, self.path)
        finally:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass

    def cached(self, error=""):
        state = self.read()
        snapshot = dict(state["snapshot"]) if state else empty_snapshot()
        # A new service must obtain its own successful live refresh before writes.
        snapshot.update(stale=True, error=error, events=[])
        return snapshot

    def mark_stale(self, state):
        if state and not state["needsRefresh"]:
            state["needsRefresh"] = True
            self.write(state)


def refresh(store, provider_factory):
    with store.locked():
        state = store.read()
        try:
            result = provider_factory().fetch()
            validate_snapshot(result)
            if not isinstance(result.get("account"), str) or not result["account"]:
                raise TaskError("Task provider returned invalid account identity")
            items = sort_tasks(result["items"])
            previous = (
                set(state["baseline"])
                if state and state["account"] == result["account"]
                else None
            )
            events = (
                []
                if previous is None
                else [
                    {
                        "id": item["id"],
                        "title": item["title"],
                        "url": item["url"],
                        "kind": "assigned",
                    }
                    for item in items
                    if item["id"] not in previous
                ]
            )
            snapshot = {
                "items": items,
                "statusOptions": result["statusOptions"],
                "updatedAt": now(),
                "stale": False,
                "error": "",
                "events": [],
            }
            store.write(
                {
                    "version": 1,
                    "account": result["account"],
                    "snapshot": snapshot,
                    "baseline": [item["id"] for item in items],
                    "needsRefresh": False,
                }
            )
            return dict(snapshot, events=events)
        except (TaskError, OSError) as error:
            # Preserve the successful snapshot and baseline, but block writes.
            try:
                store.mark_stale(state)
            except OSError:
                pass
            message = (
                str(error)
                if isinstance(error, TaskError)
                else "Cannot save work task state"
            )
            return store.cached(message)


def transition(store, provider_factory, issue_id, action_id, expected_status):
    with store.locked():
        state = store.read()
        if not state or state["needsRefresh"]:
            raise TaskError("Work tasks are stale; refresh before changing a status")
        try:
            item = validate_task(
                provider_factory().transition(
                    issue_id, action_id, expected_status, state["account"]
                )
            )
            items = [
                task for task in state["snapshot"]["items"] if task["id"] != item["id"]
            ]
            baseline = set(state["baseline"])
            baseline.discard(item["id"])
            if item["actionable"]:
                items.append(item)
                baseline.add(item["id"])
            state["snapshot"] = dict(
                state["snapshot"], items=sort_tasks(items), events=[]
            )
            state["baseline"] = sorted(baseline)
            store.write(state)
            return {"item": item}
        except (TaskError, OSError):
            # An HTTP timeout or malformed success can mean the mutation happened.
            # Never retry it, and require a refresh to reconcile before another write.
            try:
                store.mark_stale(state)
            except OSError:
                pass
            raise


def main():
    parser = argparse.ArgumentParser(prog="work-tasks")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("cache")
    commands.add_parser("list")
    update = commands.add_parser("transition")
    update.add_argument("id")
    update.add_argument("action_id")
    update.add_argument("expected_status_id")
    args = parser.parse_args()
    try:
        config = load_config()
        store = Store(config)
        factory = lambda: MantisProvider(config)
        if args.command == "cache":
            result = store.cached()
        elif args.command == "list":
            result = refresh(store, factory)
        else:
            result = transition(
                store, factory, args.id, args.action_id, args.expected_status_id
            )
        print(json.dumps(result, separators=(",", ":"), ensure_ascii=False))
    except (TaskError, OSError) as error:
        message = (
            str(error)
            if isinstance(error, TaskError)
            else "Cannot access work task state"
        )
        if args.command in ("cache", "list"):
            print(
                json.dumps(dict(empty_snapshot(), error=message), separators=(",", ":"))
            )
        else:
            print(message, file=sys.stderr)
            raise SystemExit(2) from None


if __name__ == "__main__":
    main()
