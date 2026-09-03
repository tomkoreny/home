import importlib.util
import sys
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

sys.dont_write_bytecode = True


HELPER_PATH = Path(__file__).with_name("notion-todos.py")
SPEC = importlib.util.spec_from_file_location("notion_todos", HELPER_PATH)
notion_todos = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(notion_todos)
notion_todos.ASSIGNEE_ID = "tom-user"


class AssigneeFilterTests(unittest.TestCase):
    def test_fetch_filters_query_and_results_to_configured_assignee(self):
        query_payloads = []

        def api_request(_token, method, path, payload=None):
            if method == "GET" and path == "/databases/database":
                return {"data_sources": [{"id": "source"}]}
            if method == "GET" and path == "/data_sources/source":
                return {
                    "properties": {
                        "Task name": {"type": "title"},
                        "Due date": {"type": "date"},
                        "Assignee": {"type": "people"},
                        "Status": {
                            "type": "status",
                            "status": {
                                "groups": [
                                    {"name": "Complete", "option_ids": ["done"]}
                                ],
                                "options": [
                                    {"id": "open", "name": "Not started"},
                                    {"id": "done", "name": "Done 🙌"},
                                ],
                            },
                        },
                    },
                }
            if method == "POST" and path == "/data_sources/source/query":
                query_payloads.append(payload)
                return {
                    "has_more": False,
                    "results": [
                        self.page("mine", ["tom-user"], "open"),
                        self.page("shared", ["tom-user", "terka-user"], "open"),
                        self.page("theirs", ["terka-user"], "open"),
                        self.page("completed", ["tom-user"], "done"),
                    ],
                }
            raise AssertionError((method, path))

        with (
            mock.patch.object(
                notion_todos, "secret", return_value=("token", "database")
            ),
            mock.patch.object(notion_todos, "api_request", side_effect=api_request),
            mock.patch.object(notion_todos, "atomic_json"),
        ):
            result = notion_todos.fetch_tasks()

        self.assertEqual([item["id"] for item in result["items"]], ["mine", "shared"])
        self.assertEqual(result["assigneeId"], "tom-user")
        self.assertEqual(
            query_payloads[0]["filter"],
            {
                "and": [
                    {
                        "property": "Due date",
                        "date": {"on_or_before": date.today().isoformat()},
                    },
                    {
                        "property": "Assignee",
                        "people": {"contains": "tom-user"},
                    },
                ],
            },
        )

    def test_unscoped_cache_is_not_returned_on_failure(self):
        old_cache = {
            "items": [{"id": "another-users-task"}],
            "todayCount": 1,
            "overdueCount": 0,
            "updatedAt": "yesterday",
        }
        with mock.patch.object(notion_todos, "read_json", return_value=old_cache):
            result = notion_todos.cached_failure(notion_todos.NotionError("offline"))

        self.assertEqual(result["items"], [])
        self.assertEqual(result["todayCount"], 0)
        self.assertEqual(result["overdueCount"], 0)
        self.assertEqual(result["updatedAt"], "")

    @staticmethod
    def page(page_id, assignees, status_id):
        return {
            "id": page_id,
            "url": f"https://notion.example/{page_id}",
            "properties": {
                "Task name": {"title": [{"plain_text": page_id}]},
                "Due date": {"date": {"start": date.today().isoformat()}},
                "Assignee": {"people": [{"id": assignee} for assignee in assignees]},
                "Status": {"status": {"id": status_id}},
            },
        }


if __name__ == "__main__":
    unittest.main()
