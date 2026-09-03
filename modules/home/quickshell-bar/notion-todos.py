#!/usr/bin/env python3
import argparse
import json
import os
import re
import tempfile
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

API_ROOT = "https://api.notion.com/v1"
API_VERSION = "2026-03-11"
SECRET_FILE = Path(os.environ.get("NOTION_TODOS_SECRET", "/run/secrets/notion-todos"))
ASSIGNEE_ID = "@notion-todos-assignee-id@"


def cache_home() -> Path:
    configured = os.environ.get("XDG_CACHE_HOME")
    return Path(configured) if configured else Path.home() / ".cache"


def state_home() -> Path:
    configured = os.environ.get("XDG_STATE_HOME")
    return Path(configured) if configured else Path.home() / ".local" / "state"


CACHE_DIR = cache_home() / "quickshell-bar"
CACHE_FILE = CACHE_DIR / "notion-todos.json"
COMPLETED_FILE = state_home() / "quickshell-bar" / "notion-completed.json"
VIEWS = ("widget", "mine", "unassigned", "all")
PRIORITY_NAMES = ("high", "medium", "low")
WEEKDAYS = {
    "mon": 0,
    "tue": 1,
    "wed": 2,
    "thu": 3,
    "fri": 4,
    "sat": 5,
    "sun": 6,
}

def local_date() -> date:
    return datetime.now().astimezone().date()


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
    assignee = preferred_property(properties, "people", ("assignee", "assigned to", "person", "people"))
    priority = preferred_property(properties, "select", ("priority",))
    completion = preferred_property(properties, "status", ("status", "state"))
    if completion is None:
        completion = preferred_property(properties, "checkbox", ("done", "complete", "completed"))
    if completion is None:
        completion = preferred_property(properties, "select", ("status", "state"))
    if title is None or due is None or assignee is None or priority is None or completion is None:
        raise NotionError("Task database needs title, due-date, assignee, priority, and status properties")

    completion_name, completion_schema = completion
    completion_type = completion_schema["type"]
    complete_option_ids = []
    complete_option_names = []
    complete_value = None
    status_options = []
    initial_value = None
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
        complete_options = [option for option in options if option.get("id") in complete_option_ids]
        if not complete_options:
            raise NotionError("The completed Notion status group has no option")
        complete_option_names = [option["name"] for option in complete_options]
        complete_value = {"status": {"id": complete_options[0]["id"]}}
        initial_option = next(
            (option for option in options
             if option.get("name", "").casefold() in {"not started", "to do", "todo", "open"}),
            next((option for option in options if option.get("id") not in complete_option_ids), None),
        )
        if initial_option is None:
            raise NotionError("Could not identify the initial Notion status")
        initial_value = {"status": {"id": initial_option["id"]}}
        status_options = [
            {
                "id": option["id"],
                "name": option["name"],
                "completed": option["id"] in complete_option_ids,
            }
            for option in options
        ]
    elif completion_type == "checkbox":
        complete_value = {"checkbox": True}
        initial_value = {"checkbox": False}
        complete_option_ids = ["true"]
        complete_option_names = ["Done"]
        status_options = [
            {"id": "false", "name": "Not started", "completed": False},
            {"id": "true", "name": "Done", "completed": True},
        ]
    else:
        options = completion_schema.get("select", {}).get("options") or []
        complete_options = [
            option for option in options
            if option.get("name", "").casefold().split(maxsplit=1)[0] in {"done", "complete", "completed"}
        ]
        if not complete_options:
            raise NotionError("Could not identify the completed Notion select option")
        complete_option_ids = [option["id"] for option in complete_options]
        complete_option_names = [option["name"] for option in complete_options]
        complete_value = {"select": {"id": complete_options[0]["id"]}}
        initial_option = next(
            (option for option in options
             if option.get("name", "").casefold() in {"not started", "to do", "todo", "open"}),
            next((option for option in options if option.get("id") not in complete_option_ids), None),
        )
        if initial_option is None:
            raise NotionError("Could not identify the initial Notion status")
        initial_value = {"select": {"id": initial_option["id"]}}
        status_options = [
            {
                "id": option["id"],
                "name": option["name"],
                "completed": option["id"] in complete_option_ids,
            }
            for option in options
        ]

    priority_options = (priority[1].get("select") or {}).get("options") or []
    return {
        "dataSourceId": source_id,
        "title": title[0],
        "due": due[0],
        "assignee": assignee[0],
        "priority": priority[0],
        "completion": completion_name,
        "completionType": completion_type,
        "completeOptionIds": complete_option_ids,
        "completeOptionNames": complete_option_names,
        "completeValue": complete_value,
        "initialValue": initial_value,
        "statusOptions": status_options,
        "priorityOptions": [
            {"id": option["id"], "name": option["name"]}
            for option in priority_options
        ],
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

def cache_file(view: str) -> Path:
    return CACHE_FILE if view == "widget" else CACHE_DIR / f"notion-todos-{view}.json"


def completion_filter(schema: dict) -> dict:
    kind = schema["completionType"]
    if kind == "checkbox":
        condition = {"equals": False}
    else:
        condition = {"does_not_equal": schema["completeOptionNames"]}
    return {"property": schema["completion"], kind: condition}


def task_sort_key(task: dict) -> tuple:
    due = task.get("due") or ""
    return (not due, due, task.get("title", "").casefold())


def task_from_page(page: dict, schema: dict, today: str) -> dict:
    properties = page.get("properties") or {}
    title_value = properties.get(schema["title"]) or {}
    due_value = (properties.get(schema["due"]) or {}).get("date")
    completion_value = properties.get(schema["completion"]) or {}
    assignees = (properties.get(schema["assignee"]) or {}).get("people") or []
    priority = (properties.get(schema["priority"]) or {}).get("select")
    completed, restore_value = completion_state(completion_value, schema)
    due_date = due_value["start"][:10] if due_value and due_value.get("start") else ""
    status = completion_value.get(schema["completionType"])
    if schema["completionType"] == "checkbox":
        status_id = "true" if completion_value.get("checkbox") else "false"
        status_name = "Done" if completion_value.get("checkbox") else "Not started"
    else:
        status_id = status.get("id", "") if status else ""
        status_name = status.get("name", "") if status else ""
    return {
        "id": page["id"],
        "title": rich_text(title_value, "title") or "Untitled task",
        "due": due_date,
        "overdue": bool(due_date and due_date < today),
        "url": page.get("url", ""),
        "assignedToMe": any(person.get("id") == ASSIGNEE_ID for person in assignees),
        "unassigned": not assignees,
        "assignees": [
            {"id": person.get("id", ""), "name": person.get("name", "")}
            for person in assignees
        ],
        "statusId": status_id,
        "statusName": status_name,
        "priorityId": priority.get("id", "") if priority else "",
        "priorityName": priority.get("name", "") if priority else "",
        "completed": completed,
        "completionProperty": schema["completion"],
        "completionValue": schema["completeValue"],
        "restoreValue": restore_value,
    }


def completed_today() -> list:
    payload = read_json(COMPLETED_FILE, {})
    today = local_date().isoformat()
    entries = [
        entry for entry in payload.get("items", [])
        if entry.get("completedDate") == today
    ]
    if entries != payload.get("items", []):
        atomic_json(COMPLETED_FILE, {"items": entries})
    return entries


def parse_due(value: str, today: date | None = None) -> str:
    current = today or local_date()
    normalized = value.casefold().removeprefix("@")
    if normalized == "today":
        return current.isoformat()
    if normalized == "tomorrow":
        return (current + timedelta(days=1)).isoformat()
    if normalized in WEEKDAYS:
        distance = (WEEKDAYS[normalized] - current.weekday()) % 7
        return (current + timedelta(days=distance)).isoformat()
    try:
        return date.fromisoformat(normalized).isoformat()
    except ValueError as error:
        raise NotionError(f"Invalid due date: {value}") from error


def parse_capture(value: str, today: date | None = None) -> dict:
    title_parts = []
    due = ""
    priority = ""
    for part in value.split():
        normalized = part.casefold()
        is_date = normalized in {"@today", "@tomorrow"} \
            or normalized.removeprefix("@") in WEEKDAYS \
            or bool(re.fullmatch(r"@\d{4}-\d{2}-\d{2}", normalized))
        is_priority = normalized.removeprefix("!") in PRIORITY_NAMES and normalized.startswith("!")
        if is_date:
            if due:
                raise NotionError("Use only one due-date token")
            due = parse_due(normalized, today)
        elif is_priority:
            if priority:
                raise NotionError("Use only one priority token")
            priority = normalized[1:]
        else:
            title_parts.append(part)
    title = " ".join(title_parts).strip()
    if not title:
        raise NotionError("Task title is required")
    return {"title": title, "due": due, "priority": priority}


def fetch_tasks(view: str = "widget") -> dict:
    if view not in VIEWS:
        raise NotionError(f"Unknown task view: {view}")
    token, database_id = secret()
    schema = discover_schema(token, database_id)
    today = local_date().isoformat()
    filters = [completion_filter(schema)]
    if view in {"widget", "mine"}:
        filters.append({"property": schema["assignee"], "people": {"contains": ASSIGNEE_ID}})
    elif view == "unassigned":
        filters.append({"property": schema["assignee"], "people": {"is_empty": True}})
    if view == "widget":
        filters.append({"property": schema["due"], "date": {"on_or_before": today}})
    query = {
        "filter": filters[0] if len(filters) == 1 else {"and": filters},
        "sorts": [{"property": schema["due"], "direction": "ascending"}],
        "page_size": 100,
    }
    pages = []
    cursor = None
    while True:
        payload = dict(query)
        if cursor:
            payload["start_cursor"] = cursor
        response = api_request(
            token,
            "POST",
            f"/data_sources/{schema['dataSourceId']}/query",
            payload,
        )
        pages.extend(response.get("results") or [])
        if not response.get("has_more"):
            break
        cursor = response.get("next_cursor")

    tasks = []
    for page in pages:
        task = task_from_page(page, schema, today)
        if task["completed"]:
            continue
        if view in {"widget", "mine"} and not task["assignedToMe"]:
            continue
        if view == "unassigned" and not task["unassigned"]:
            continue
        if view == "widget" and (not task["due"] or task["due"] > today):
            continue
        tasks.append(task)

    tasks.sort(key=task_sort_key)
    result = {
        "view": view,
        "assigneeId": ASSIGNEE_ID,
        "items": tasks,
        "completedToday": completed_today(),
        "statusOptions": schema["statusOptions"],
        "priorityOptions": schema["priorityOptions"],
        "todayCount": sum(task["due"] == today for task in tasks),
        "overdueCount": sum(task["overdue"] for task in tasks),
        "updatedAt": datetime.now(timezone.utc).isoformat(),
        "stale": False,
        "error": "",
    }
    atomic_json(cache_file(view), result)
    return result


def cached_failure(error: Exception, view: str = "widget") -> dict:
    cached = read_json(cache_file(view), {})
    matching_cache = cached.get("assigneeId") == ASSIGNEE_ID \
        and cached.get("view") == view
    return {
        "view": view,
        "assigneeId": ASSIGNEE_ID,
        "items": (cached.get("items") or []) if matching_cache else [],
        "completedToday": (cached.get("completedToday") or []) if matching_cache else completed_today(),
        "statusOptions": (cached.get("statusOptions") or []) if matching_cache else [],
        "priorityOptions": (cached.get("priorityOptions") or []) if matching_cache else [],
        "todayCount": cached.get("todayCount", 0) if matching_cache else 0,
        "overdueCount": cached.get("overdueCount", 0) if matching_cache else 0,
        "updatedAt": cached.get("updatedAt", "") if matching_cache else "",
        "stale": True,
        "error": str(error),
    }


def invalidate_caches() -> None:
    for view in VIEWS:
        try:
            cache_file(view).unlink()
        except FileNotFoundError:
            pass


def option(options: list, value: str, label: str) -> dict:
    match = next(
        (candidate for candidate in options
         if candidate.get("id") == value or candidate.get("name", "").casefold() == value.casefold()),
        None,
    )
    if match is None:
        raise NotionError(f"Unknown {label}: {value}")
    return match


def patch_task(token: str, page_id: str, property_name: str, property_value: dict) -> dict:
    return api_request(
        token,
        "PATCH",
        f"/pages/{page_id}",
        {"properties": {property_name: property_value}},
    )


def create_task(value: str) -> dict:
    parsed = parse_capture(value)
    token, database_id = secret()
    schema = discover_schema(token, database_id)
    properties = {
        schema["title"]: {
            "title": [{"type": "text", "text": {"content": parsed["title"]}}],
        },
        schema["assignee"]: {"people": [{"id": ASSIGNEE_ID}]},
        schema["completion"]: schema["initialValue"],
    }
    if parsed["due"]:
        properties[schema["due"]] = {"date": {"start": parsed["due"]}}
    if parsed["priority"]:
        priority = option(schema["priorityOptions"], parsed["priority"], "priority")
        properties[schema["priority"]] = {"select": {"id": priority["id"]}}
    page = api_request(
        token,
        "POST",
        "/pages",
        {
            "parent": {
                "type": "data_source_id",
                "data_source_id": schema["dataSourceId"],
            },
            "properties": properties,
        },
    )
    task = task_from_page(page, schema, local_date().isoformat())
    invalidate_caches()
    return {"ok": True, "item": task}


def update_task(page_id: str, field: str, value: str) -> dict:
    token, database_id = secret()
    schema = discover_schema(token, database_id)
    if field == "title":
        title = value.strip()
        if not title:
            raise NotionError("Task title is required")
        property_name = schema["title"]
        property_value = {
            "title": [{"type": "text", "text": {"content": title}}],
        }
    elif field == "due":
        property_name = schema["due"]
        property_value = {"date": {"start": parse_due(value)}} if value else {"date": None}
    elif field == "priority":
        property_name = schema["priority"]
        if value:
            priority = option(schema["priorityOptions"], value, "priority")
            property_value = {"select": {"id": priority["id"]}}
        else:
            property_value = {"select": None}
    elif field == "status":
        status = option(schema["statusOptions"], value, "status")
        if status.get("completed"):
            return complete_task(page_id)
        property_name = schema["completion"]
        if schema["completionType"] == "checkbox":
            property_value = {"checkbox": status["id"] == "true"}
        else:
            property_value = {schema["completionType"]: {"id": status["id"]}}
    else:
        raise NotionError(f"Unknown task field: {field}")
    page = patch_task(token, page_id, property_name, property_value)
    task = task_from_page(page, schema, local_date().isoformat())
    invalidate_caches()
    return {"ok": True, "item": task}


def assign_task(page_id: str) -> dict:
    token, database_id = secret()
    schema = discover_schema(token, database_id)
    page = patch_task(
        token,
        page_id,
        schema["assignee"],
        {"people": [{"id": ASSIGNEE_ID}]},
    )
    task = task_from_page(page, schema, local_date().isoformat())
    invalidate_caches()
    return {"ok": True, "item": task}


def complete_task(page_id: str) -> dict:
    token, database_id = secret()
    schema = discover_schema(token, database_id)
    page = api_request(token, "GET", f"/pages/{page_id}")
    task = task_from_page(page, schema, local_date().isoformat())
    if task["completed"]:
        raise NotionError("Task is already completed")
    patch_task(token, page_id, schema["completion"], schema["completeValue"])
    journal = read_json(COMPLETED_FILE, {})
    entry = dict(task)
    entry["completedDate"] = local_date().isoformat()
    entry["completedAt"] = datetime.now(timezone.utc).isoformat()
    entries = [
        candidate for candidate in journal.get("items", [])
        if candidate.get("id") != page_id
    ]
    entries.append(entry)
    atomic_json(COMPLETED_FILE, {"items": entries})
    invalidate_caches()
    return {"ok": True, "pageId": page_id, "item": task}


def undo_task(page_id: str) -> dict:
    journal = read_json(COMPLETED_FILE, {})
    task = next(
        (entry for entry in journal.get("items", []) if entry.get("id") == page_id),
        None,
    )
    if task is None:
        raise NotionError("Reopen is no longer available")
    token, database_id = secret()
    schema = discover_schema(token, database_id)
    page = patch_task(
        token,
        page_id,
        task["completionProperty"],
        task["restoreValue"],
    )
    entries = [
        entry for entry in journal.get("items", [])
        if entry.get("id") != page_id
    ]
    atomic_json(COMPLETED_FILE, {"items": entries})
    invalidate_caches()
    restored = task_from_page(page, schema, local_date().isoformat())
    return {"ok": True, "pageId": page_id, "item": restored}


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="notion-todos")
    commands = root.add_subparsers(dest="command", required=True)
    list_command = commands.add_parser("list")
    list_command.add_argument("view", nargs="?", choices=VIEWS, default="widget")
    create = commands.add_parser("create")
    create.add_argument("text")
    update = commands.add_parser("update")
    update.add_argument("page_id")
    update.add_argument("field", choices=("title", "due", "priority", "status"))
    update.add_argument("value")
    assign = commands.add_parser("assign")
    assign.add_argument("page_id")
    complete = commands.add_parser("complete")
    complete.add_argument("page_id")
    reopen = commands.add_parser("reopen")
    reopen.add_argument("page_id")
    undo = commands.add_parser("undo")
    undo.add_argument("page_id")
    parse = commands.add_parser("parse")
    parse.add_argument("text")
    return root


def main() -> None:
    args = parser().parse_args()
    try:
        if args.command == "list":
            try:
                result = fetch_tasks(args.view)
            except (NotionError, OSError, ValueError) as error:
                result = cached_failure(error, args.view)
        elif args.command == "create":
            result = create_task(args.text)
        elif args.command == "update":
            result = update_task(args.page_id, args.field, args.value)
        elif args.command == "assign":
            result = assign_task(args.page_id)
        elif args.command == "complete":
            result = complete_task(args.page_id)
        elif args.command in {"reopen", "undo"}:
            result = undo_task(args.page_id)
        else:
            result = parse_capture(args.text)
        print(json.dumps(result, separators=(",", ":")))
    except (NotionError, OSError, ValueError) as error:
        print(str(error), file=os.sys.stderr)
        raise SystemExit(2) from error


if __name__ == "__main__":
    main()
