#!/usr/bin/env python3
import argparse
import json
import os
import tempfile
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

API_ROOT = "https://api.notion.com/v1"
API_VERSION = "2026-03-11"
SECRET_FILE = Path("/run/secrets/notion-todos")


def cache_home() -> Path:
    configured = os.environ.get("XDG_CACHE_HOME")
    return Path(configured) if configured else Path.home() / ".cache"


def state_home() -> Path:
    configured = os.environ.get("XDG_STATE_HOME")
    return Path(configured) if configured else Path.home() / ".local" / "state"


CACHE_FILE = cache_home() / "quickshell-bar" / "notion-todos.json"
UNDO_FILE = state_home() / "quickshell-bar" / "notion-todo-undo.json"


class NotionError(RuntimeError):
    pass


def read_json(path: Path, fallback):
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return fallback


def atomic_json(path: Path, payload) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f"{path.name}.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(payload, stream, separators=(",", ":"))
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def secret() -> tuple[str, str]:
    payload = read_json(SECRET_FILE, {})
    token = payload.get("token")
    database_id = payload.get("databaseId")
    if not isinstance(token, str) or not token:
        raise NotionError("Notion token is unavailable")
    if not isinstance(database_id, str) or not database_id:
        raise NotionError("Notion task database is not configured")
    return token, database_id


def api_request(token: str, method: str, path: str, payload=None) -> dict:
    body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode()
    request = urllib.request.Request(
        f"{API_ROOT}{path}",
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Notion-Version": API_VERSION,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        try:
            detail = json.load(error).get("message", "")
        except (json.JSONDecodeError, AttributeError):
            detail = ""
        message = detail or f"Notion returned HTTP {error.code}"
        raise NotionError(message) from error
    except (urllib.error.URLError, TimeoutError) as error:
        raise NotionError("Could not reach Notion") from error


def preferred_property(properties: dict, property_type: str, names: tuple[str, ...]) -> tuple[str, dict] | None:
    candidates = [(name, value) for name, value in properties.items() if value.get("type") == property_type]
    for preferred in names:
        for name, value in candidates:
            if name.casefold() == preferred:
                return name, value
    return candidates[0] if candidates else None


def discover_schema(token: str, database_id: str) -> dict:
    database = api_request(token, "GET", f"/databases/{database_id}")
    sources = database.get("data_sources") or []
    if not sources:
        raise NotionError("The Notion database has no data source")
    source_id = sources[0].get("id")
    source = api_request(token, "GET", f"/data_sources/{source_id}")
    properties = source.get("properties") or {}

    title = preferred_property(properties, "title", ("task", "name", "title"))
    due = preferred_property(properties, "date", ("due", "due date", "date", "deadline"))
    completion = preferred_property(properties, "status", ("status", "state"))
    if completion is None:
        completion = preferred_property(properties, "checkbox", ("done", "complete", "completed"))
    if completion is None:
        completion = preferred_property(properties, "select", ("status", "state"))
    if title is None or due is None or completion is None:
        raise NotionError("Task database needs title, due-date, and status or checkbox properties")

    completion_name, completion_schema = completion
    completion_type = completion_schema["type"]
    complete_option_ids = []
    complete_value = None
    if completion_type == "status":
        status = completion_schema.get("status") or {}
        groups = status.get("groups") or []
        complete_group = next(
            (group for group in groups if "complete" in group.get("name", "").casefold()
             or "done" in group.get("name", "").casefold()),
            None,
        )
        if complete_group is None:
            raise NotionError("Could not identify the completed Notion status group")
        complete_option_ids = complete_group.get("option_ids") or []
        options = status.get("options") or []
        complete_option = next((option for option in options if option.get("id") in complete_option_ids), None)
        if complete_option is None:
            raise NotionError("The completed Notion status group has no option")
        complete_value = {"status": {"id": complete_option["id"]}}
    elif completion_type == "checkbox":
        complete_value = {"checkbox": True}
    else:
        options = completion_schema.get("select", {}).get("options") or []
        complete_option = next(
            (option for option in options if option.get("name", "").casefold() in {"done", "complete", "completed"}),
            None,
        )
        if complete_option is None:
            raise NotionError("Could not identify the completed Notion select option")
        complete_option_ids = [complete_option.get("id")]
        complete_value = {"select": {"id": complete_option["id"]}}

    return {
        "dataSourceId": source_id,
        "title": title[0],
        "due": due[0],
        "completion": completion_name,
        "completionType": completion_type,
        "completeOptionIds": complete_option_ids,
        "completeValue": complete_value,
    }


def rich_text(value: dict, property_type: str) -> str:
    parts = value.get(property_type) or []
    return "".join(part.get("plain_text", "") for part in parts).strip()


def completion_state(value: dict, schema: dict) -> tuple[bool, dict]:
    kind = schema["completionType"]
    if kind == "checkbox":
        checked = bool(value.get("checkbox"))
        return checked, {"checkbox": checked}
    option = value.get(kind)
    if option is None:
        return False, {kind: None}
    completed = option.get("id") in schema["completeOptionIds"]
    restore = {kind: {"id": option["id"]}}
    return completed, restore


def fetch_tasks() -> dict:
    token, database_id = secret()
    schema = discover_schema(token, database_id)
    today = date.today().isoformat()
    query = {
        "filter": {"property": schema["due"], "date": {"on_or_before": today}},
        "sorts": [{"property": schema["due"], "direction": "ascending"}],
        "page_size": 100,
    }
    pages = []
    cursor = None
    while True:
        if cursor:
            query["start_cursor"] = cursor
        response = api_request(token, "POST", f"/data_sources/{schema['dataSourceId']}/query", query)
        pages.extend(response.get("results") or [])
        if not response.get("has_more"):
            break
        cursor = response.get("next_cursor")

    tasks = []
    for page in pages:
        properties = page.get("properties") or {}
        title_value = properties.get(schema["title"]) or {}
        due_value = (properties.get(schema["due"]) or {}).get("date")
        completion_value = properties.get(schema["completion"]) or {}
        if due_value is None or not due_value.get("start"):
            continue
        completed, restore_value = completion_state(completion_value, schema)
        if completed:
            continue
        due_date = due_value["start"][:10]
        tasks.append({
            "id": page["id"],
            "title": rich_text(title_value, "title") or "Untitled task",
            "due": due_date,
            "overdue": due_date < today,
            "url": page.get("url", ""),
            "completionProperty": schema["completion"],
            "completionValue": schema["completeValue"],
            "restoreValue": restore_value,
        })

    tasks.sort(key=lambda task: (task["due"], task["title"].casefold()))
    result = {
        "items": tasks,
        "todayCount": sum(task["due"] == today for task in tasks),
        "overdueCount": sum(task["overdue"] for task in tasks),
        "updatedAt": datetime.now(timezone.utc).isoformat(),
        "stale": False,
        "error": "",
    }
    atomic_json(CACHE_FILE, result)
    return result


def cached_failure(error: Exception) -> dict:
    cached = read_json(CACHE_FILE, {})
    return {
        "items": cached.get("items") or [],
        "todayCount": cached.get("todayCount", 0),
        "overdueCount": cached.get("overdueCount", 0),
        "updatedAt": cached.get("updatedAt", ""),
        "stale": True,
        "error": str(error),
    }


def update_page(page_id: str, property_name: str, property_value: dict) -> None:
    token, _ = secret()
    api_request(token, "PATCH", f"/pages/{page_id}", {"properties": {property_name: property_value}})


def complete_task(page_id: str) -> dict:
    cached = read_json(CACHE_FILE, {})
    task = next((item for item in cached.get("items", []) if item.get("id") == page_id), None)
    if task is None:
        raise NotionError("Task is no longer in the current list")
    update_page(page_id, task["completionProperty"], task["completionValue"])
    undo = read_json(UNDO_FILE, {})
    undo[page_id] = task
    atomic_json(UNDO_FILE, undo)
    items = [item for item in cached.get("items", []) if item.get("id") != page_id]
    cached["items"] = items
    cached["todayCount"] = sum(not item.get("overdue", False) for item in items)
    cached["overdueCount"] = sum(item.get("overdue", False) for item in items)
    atomic_json(CACHE_FILE, cached)
    return {"ok": True, "pageId": page_id}


def undo_task(page_id: str) -> dict:
    undo = read_json(UNDO_FILE, {})
    task = undo.get(page_id)
    if task is None:
        raise NotionError("Undo is no longer available")
    update_page(page_id, task["completionProperty"], task["restoreValue"])
    del undo[page_id]
    atomic_json(UNDO_FILE, undo)
    cached = read_json(CACHE_FILE, {})
    items = [item for item in cached.get("items", []) if item.get("id") != page_id]
    items.append(task)
    items.sort(key=lambda item: (item["due"], item["title"].casefold()))
    cached["items"] = items
    cached["todayCount"] = sum(not item.get("overdue", False) for item in items)
    cached["overdueCount"] = sum(item.get("overdue", False) for item in items)
    atomic_json(CACHE_FILE, cached)
    return {"ok": True, "pageId": page_id}


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="notion-todos")
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("list")
    complete = commands.add_parser("complete")
    complete.add_argument("page_id")
    undo = commands.add_parser("undo")
    undo.add_argument("page_id")
    return root


def main() -> None:
    args = parser().parse_args()
    try:
        if args.command == "list":
            try:
                result = fetch_tasks()
            except (NotionError, OSError, ValueError) as error:
                result = cached_failure(error)
        elif args.command == "complete":
            result = complete_task(args.page_id)
        else:
            result = undo_task(args.page_id)
        print(json.dumps(result, separators=(",", ":")))
    except (NotionError, OSError, ValueError) as error:
        print(str(error), file=os.sys.stderr)
        raise SystemExit(2) from error


if __name__ == "__main__":
    main()
