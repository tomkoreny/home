import importlib.util
import sys
import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True

HELPER_PATH = Path(__file__).with_name("notion-todos.py")
SPEC = importlib.util.spec_from_file_location("notion_todos", HELPER_PATH)
notion_todos = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(notion_todos)
notion_todos.ASSIGNEE_ID = "tom-user"


class TodoHelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.path_patches = [
            mock.patch.object(notion_todos, "CACHE_DIR", root / "cache"),
            mock.patch.object(notion_todos, "CACHE_FILE", root / "cache" / "widget.json"),
            mock.patch.object(notion_todos, "COMPLETED_FILE", root / "completed.json"),
        ]
        for patch in self.path_patches:
            patch.start()

    def tearDown(self):
        for patch in reversed(self.path_patches):
            patch.stop()
        self.temporary.cleanup()

    def test_widget_and_manager_views_filter_independently(self):
        today = datetime.now().astimezone().date()
        pages = [
            self.page("mine", ["tom-user"], due=today.isoformat()),
            self.page("shared", ["tom-user", "terka-user"], due=today.isoformat()),
            self.page("future", ["tom-user"], due=(today + timedelta(days=1)).isoformat()),
            self.page("inbox", ["tom-user"], due=""),
            self.page("theirs", ["terka-user"], due=today.isoformat()),
            self.page("unassigned", [], due=today.isoformat()),
            self.page("completed", ["tom-user"], due=today.isoformat(), status_id="done"),
        ]
        queries = []

        def api_request(_token, method, path, payload=None):
            self.assertEqual((method, path), ("POST", "/data_sources/source/query"))
            queries.append(payload)
            return {"has_more": False, "results": pages}

        with (
            mock.patch.object(notion_todos, "secret", return_value=("token", "database")),
            mock.patch.object(notion_todos, "discover_schema", return_value=self.schema()),
            mock.patch.object(notion_todos, "api_request", side_effect=api_request),
        ):
            widget = notion_todos.fetch_tasks("widget")
            mine = notion_todos.fetch_tasks("mine")
            unassigned = notion_todos.fetch_tasks("unassigned")
            all_tasks = notion_todos.fetch_tasks("all")

        self.assertEqual([item["id"] for item in widget["items"]], ["mine", "shared"])
        self.assertEqual(
            [item["id"] for item in mine["items"]],
            ["mine", "shared", "future", "inbox"],
        )
        self.assertEqual([item["id"] for item in unassigned["items"]], ["unassigned"])
        self.assertEqual(
            [item["id"] for item in all_tasks["items"]],
            ["mine", "shared", "theirs", "unassigned", "future", "inbox"],
        )
        self.assertEqual(
            queries[0]["filter"],
            {
                "and": [
                    {"property": "Status", "status": {"does_not_equal": ["Done"]}},
                    {"property": "Assignee", "people": {"contains": "tom-user"}},
                    {
                        "property": "Due date",
                        "date": {"on_or_before": today.isoformat()},
                    },
                ],
            },
        )
        self.assertEqual(
            queries[2]["filter"]["and"][1],
            {"property": "Assignee", "people": {"is_empty": True}},
        )

    def test_capture_parser_uses_only_explicit_suffix_tokens(self):
        today = date(2026, 9, 3)
        self.assertEqual(
            notion_todos.parse_capture("Call Alex @tomorrow !high", today),
            {"title": "Call Alex", "due": "2026-09-04", "priority": "high"},
        )
        self.assertEqual(
            notion_todos.parse_capture("Plan Friday @fri", today),
            {"title": "Plan Friday", "due": "2026-09-04", "priority": ""},
        )
        self.assertEqual(
            notion_todos.parse_capture("Email @alex about !important", today),
            {
                "title": "Email @alex about !important",
                "due": "",
                "priority": "",
            },
        )
        with self.assertRaisesRegex(notion_todos.NotionError, "only one due-date"):
            notion_todos.parse_capture("Task @today @tomorrow", today)

    def test_create_sets_inbox_defaults_and_shorthand_properties(self):
        requests = []
        tomorrow = (datetime.now().astimezone().date() + timedelta(days=1)).isoformat()

        def api_request(_token, method, path, payload=None):
            requests.append((method, path, payload))
            return self.page(
                "created",
                ["tom-user"],
                due=tomorrow,
                priority_id="high",
            )

        with (
            mock.patch.object(notion_todos, "secret", return_value=("token", "database")),
            mock.patch.object(notion_todos, "discover_schema", return_value=self.schema()),
            mock.patch.object(notion_todos, "api_request", side_effect=api_request),
            mock.patch.object(notion_todos, "invalidate_caches"),
        ):
            result = notion_todos.create_task("Capture proof @tomorrow !high")

        self.assertTrue(result["ok"])
        method, path, payload = requests[0]
        self.assertEqual((method, path), ("POST", "/pages"))
        self.assertEqual(
            payload["parent"],
            {"type": "data_source_id", "data_source_id": "source"},
        )
        self.assertEqual(
            payload["properties"]["Task name"]["title"][0]["text"]["content"],
            "Capture proof",
        )
        self.assertEqual(
            payload["properties"]["Assignee"],
            {"people": [{"id": "tom-user"}]},
        )
        self.assertEqual(payload["properties"]["Due date"], {"date": {"start": tomorrow}})
        self.assertEqual(payload["properties"]["Priority"], {"select": {"id": "high"}})
        self.assertEqual(payload["properties"]["Status"], {"status": {"id": "open"}})

    def test_plain_capture_omits_due_date_and_priority(self):
        requests = []

        def api_request(_token, method, path, payload=None):
            requests.append((method, path, payload))
            return self.page("created", ["tom-user"], due="")

        with (
            mock.patch.object(notion_todos, "secret", return_value=("token", "database")),
            mock.patch.object(notion_todos, "discover_schema", return_value=self.schema()),
            mock.patch.object(notion_todos, "api_request", side_effect=api_request),
            mock.patch.object(notion_todos, "invalidate_caches"),
        ):
            notion_todos.create_task("Inbox idea")

        properties = requests[0][2]["properties"]
        self.assertNotIn("Due date", properties)
        self.assertNotIn("Priority", properties)
        self.assertEqual(properties["Assignee"], {"people": [{"id": "tom-user"}]})
        self.assertEqual(properties["Status"], {"status": {"id": "open"}})

    def test_update_and_assign_use_schema_backed_properties(self):
        requests = []

        def api_request(_token, method, path, payload=None):
            requests.append((method, path, payload))
            return self.page("task", ["tom-user"], due="2026-09-05", priority_id="medium")

        with (
            mock.patch.object(notion_todos, "secret", return_value=("token", "database")),
            mock.patch.object(notion_todos, "discover_schema", return_value=self.schema()),
            mock.patch.object(notion_todos, "api_request", side_effect=api_request),
            mock.patch.object(notion_todos, "invalidate_caches"),
        ):
            notion_todos.update_task("task", "due", "2026-09-05")
            notion_todos.update_task("task", "priority", "medium")
            notion_todos.update_task("task", "status", "progress")
            notion_todos.assign_task("task")

        self.assertEqual(
            [request[2]["properties"] for request in requests],
            [
                {"Due date": {"date": {"start": "2026-09-05"}}},
                {"Priority": {"select": {"id": "medium"}}},
                {"Status": {"status": {"id": "progress"}}},
                {"Assignee": {"people": [{"id": "tom-user"}]}},
            ],
        )

    def test_completion_journal_survives_restart_and_reopens_prior_status(self):
        requests = []
        pages = [
            self.page("task", ["tom-user"], status_id="progress"),
            self.page("task", ["tom-user"], status_id="done"),
            self.page("task", ["tom-user"], status_id="progress"),
        ]

        def api_request(_token, method, path, payload=None):
            requests.append((method, path, payload))
            return pages.pop(0)

        with (
            mock.patch.object(notion_todos, "secret", return_value=("token", "database")),
            mock.patch.object(notion_todos, "discover_schema", return_value=self.schema()),
            mock.patch.object(notion_todos, "api_request", side_effect=api_request),
            mock.patch.object(notion_todos, "invalidate_caches"),
        ):
            notion_todos.complete_task("task")
            self.assertEqual([item["id"] for item in notion_todos.completed_today()], ["task"])
            result = notion_todos.undo_task("task")

        self.assertEqual(result["item"]["statusId"], "progress")
        self.assertEqual(notion_todos.completed_today(), [])
        self.assertEqual(
            requests[1][2]["properties"],
            {"Status": {"status": {"id": "done"}}},
        )
        self.assertEqual(
            requests[2][2]["properties"],
            {"Status": {"status": {"id": "progress"}}},
        )

    def test_cache_is_scoped_to_view_and_assignee(self):
        notion_todos.atomic_json(
            notion_todos.cache_file("mine"),
            {
                "view": "all",
                "assigneeId": "tom-user",
                "items": [{"id": "another-users-task"}],
            },
        )
        result = notion_todos.cached_failure(notion_todos.NotionError("offline"), "mine")
        self.assertEqual(result["items"], [])

    @staticmethod
    def schema():
        return {
            "dataSourceId": "source",
            "title": "Task name",
            "due": "Due date",
            "assignee": "Assignee",
            "priority": "Priority",
            "completion": "Status",
            "completionType": "status",
            "completeOptionIds": ["done"],
            "completeOptionNames": ["Done"],
            "completeValue": {"status": {"id": "done"}},
            "initialValue": {"status": {"id": "open"}},
            "statusOptions": [
                {"id": "open", "name": "Not started", "completed": False},
                {"id": "progress", "name": "In progress", "completed": False},
                {"id": "done", "name": "Done", "completed": True},
            ],
            "priorityOptions": [
                {"id": "high", "name": "High"},
                {"id": "medium", "name": "Medium"},
                {"id": "low", "name": "Low"},
            ],
        }

    @staticmethod
    def page(
        page_id,
        assignees,
        *,
        due=None,
        status_id="open",
        priority_id="",
    ):
        if due is None:
            due = datetime.now().astimezone().date().isoformat()
        status_names = {
            "open": "Not started",
            "progress": "In progress",
            "done": "Done",
        }
        priority_names = {
            "high": "High",
            "medium": "Medium",
            "low": "Low",
        }
        return {
            "id": page_id,
            "url": f"https://notion.example/{page_id}",
            "properties": {
                "Task name": {"title": [{"plain_text": page_id}]},
                "Due date": {"date": {"start": due} if due else None},
                "Assignee": {
                    "people": [
                        {"id": assignee, "name": assignee}
                        for assignee in assignees
                    ],
                },
                "Priority": {
                    "select": {
                        "id": priority_id,
                        "name": priority_names[priority_id],
                    } if priority_id else None,
                },
                "Status": {
                    "status": {
                        "id": status_id,
                        "name": status_names[status_id],
                    },
                },
            },
        }


if __name__ == "__main__":
    unittest.main()
