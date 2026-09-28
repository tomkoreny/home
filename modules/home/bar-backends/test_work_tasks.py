import copy
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from urllib.parse import parse_qs, urlsplit

sys.dont_write_bytecode = True
HELPER_PATH = Path(__file__).with_name("work-tasks.py")
SPEC = importlib.util.spec_from_file_location("work_tasks", HELPER_PATH)
work_tasks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(work_tasks)
MantisProvider = work_tasks.MantisProvider
TaskError = work_tasks.TaskError


def task(task_id="1", status="open", actionable=True):
    return {
        "id": task_id,
        "title": "A task",
        "statusId": status,
        "statusName": status,
        "url": "https://example.com/task/" + task_id,
        "actionable": actionable,
        "rank": 1,
        "updatedAt": "2026-09-07T10:00:00+00:00",
        "searchTerms": "A task",
        "actions": [],
    }


class MemoryProvider:
    def __init__(self):
        self.items = [task()]
        self.failure = False

    def fetch(self):
        if self.failure:
            raise TaskError("Mantis HTTP 503")
        return {
            "account": "account",
            "items": copy.deepcopy(self.items),
            "statusOptions": [{"id": "open", "name": "Open"}],
        }

    def transition(self, issue_id, action_id, expected_status, account):
        self.items = [task(issue_id, action_id)]
        return copy.deepcopy(self.items[0])


class BaselineTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        patch = mock.patch.dict("os.environ", {"XDG_STATE_HOME": self.temporary.name})
        patch.start()
        self.addCleanup(patch.stop)
        self.store = work_tasks.Store(
            {
                "provider": "mantisbt",
                "baseUrl": "https://example.com",
                "tokenFile": "/unused/token",
            }
        )
        self.provider = MemoryProvider()
        self.factory = lambda: self.provider

    def test_first_sync_failure_and_reassignment_notifications(self):
        self.assertEqual(work_tasks.refresh(self.store, self.factory)["events"], [])
        self.provider.items.append(task("2"))
        self.provider.failure = True
        failed = work_tasks.refresh(self.store, self.factory)
        self.assertTrue(failed["stale"])
        self.assertEqual([item["id"] for item in failed["items"]], ["1"])
        self.assertEqual(failed["events"], [])
        with self.assertRaisesRegex(TaskError, "stale"):
            work_tasks.transition(self.store, self.factory, "1", "working", "open")
        self.provider.failure = False
        assigned = work_tasks.refresh(self.store, self.factory)
        self.assertEqual([event["id"] for event in assigned["events"]], ["2"])
        self.assertEqual(work_tasks.refresh(self.store, self.factory)["events"], [])
        self.provider.items = []
        work_tasks.refresh(self.store, self.factory)
        self.provider.items = [task("2")]
        self.assertEqual(
            [
                event["id"]
                for event in work_tasks.refresh(self.store, self.factory)["events"]
            ],
            ["2"],
        )

    def test_own_transition_and_restart_do_not_emit_assignments(self):
        work_tasks.refresh(self.store, self.factory)
        work_tasks.transition(self.store, self.factory, "1", "working", "open")
        cached = self.store.cached()
        self.assertTrue(cached["stale"])
        self.assertEqual(cached["items"][0]["statusId"], "working")
        self.assertEqual(cached["events"], [])
        self.assertEqual(work_tasks.refresh(self.store, self.factory)["events"], [])

    def test_incomplete_provider_snapshot_does_not_replace_baseline(self):
        work_tasks.refresh(self.store, self.factory)
        self.provider.items = [task("2"), {"id": "3"}]
        self.assertTrue(work_tasks.refresh(self.store, self.factory)["stale"])
        self.provider.items = [task("1"), task("2"), task("3")]
        events = work_tasks.refresh(self.store, self.factory)["events"]
        self.assertEqual([event["id"] for event in events], ["2", "3"])


class MantisBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.provider = object.__new__(MantisProvider)
        self.provider.base = "https://example.com"
        self.provider.user_id = 12
        self.provider.global_access = 55
        self.provider.rules = {}
        self.issue = {
            "id": 123,
            "summary": "Assigned work",
            "project": {"id": 14, "name": "Project"},
            "handler": {"id": 12},
            "status": {"id": 50},
            "priority": {"id": 30},
            "sticky": False,
            "updated_at": "2026-09-07T10:00:00+00:00",
        }
        self.rules = {
            "access": 55,
            "names": {20: "Feedback", 50: "Assigned", 60: "Testing", 80: "Resolved"},
            "workflow": {50: [60, 20, 80]},
            "thresholds": {20: 70, 80: 55},
            "config": {
                "bug_resolved_status_threshold": 80,
                "bug_readonly_status_threshold": 80,
                "update_readonly_bug_threshold": 70,
                "update_bug_threshold": 40,
                "update_bug_status_threshold": 55,
                "bug_submit_status": 20,
                "report_bug_threshold": 25,
                "webservice_readwrite_access_level_threshold": 25,
            },
        }

    def test_workflow_and_status_override_intersection_with_project_permissions(self):
        self.assertEqual(
            [
                action["id"]
                for action in self.provider.task(self.issue, self.rules)["actions"]
            ],
            ["60", "80"],
        )
        self.rules["config"]["update_bug_threshold"] = [40, 70]
        self.assertEqual(self.provider.task(self.issue, self.rules)["actions"], [])
        self.rules["config"]["update_bug_threshold"] = 40
        self.rules["access"] = 25
        self.assertEqual(self.provider.task(self.issue, self.rules)["actions"], [])

    def test_project_specific_resolved_and_readonly_boundaries(self):
        self.rules["config"]["bug_readonly_status_threshold"] = 50
        item = self.provider.task(self.issue, self.rules)
        self.assertTrue(item["actionable"])
        self.assertEqual(item["actions"], [])
        self.rules["config"]["bug_resolved_status_threshold"] = 50
        self.assertFalse(self.provider.task(self.issue, self.rules)["actionable"])

    def test_pagination_does_not_treat_short_page_as_complete(self):
        responses = {1: [{"id": 1}], 2: [{"id": 2}], 3: []}

        def request(method, path):
            page = int(parse_qs(urlsplit(path).query)["page"][0])
            return {"issues": responses[page]}, None

        self.provider.request = request
        self.assertEqual(
            [item["id"] for item in self.provider.pages("/issues", "issues")], [1, 2]
        )
        responses[2] = [{"id": 1}]
        with self.assertRaisesRegex(TaskError, "pages changed"):
            list(self.provider.pages("/issues", "issues"))

    def test_transition_rechecks_owner_and_status_before_mutation(self):
        stored = copy.deepcopy(self.issue)

        def request(method, path, payload=None, etag=None):
            if method == "PATCH":
                stored["status"] = payload["status"]
            return {"issues": [copy.deepcopy(stored)]}, '"revision"'

        self.provider.request = request
        self.provider.identify = lambda: "12"
        self.provider.project_rules = lambda project: self.rules
        stored["handler"] = {"id": 13}
        with self.assertRaisesRegex(TaskError, "assigned to you"):
            self.provider.transition("123", "60", "50", "12")
        self.assertEqual(stored["status"]["id"], 50)
        stored["handler"] = {"id": 12}
        with self.assertRaisesRegex(TaskError, "status changed"):
            self.provider.transition("123", "60", "20", "12")
        self.assertEqual(stored["status"]["id"], 50)

    def test_missing_permission_metadata_is_not_assumed(self):
        self.provider.request = lambda method, path: ({"configs": []}, None)
        with self.assertRaisesRegex(TaskError, "missing required configuration"):
            self.provider.project_rules(14)


if __name__ == "__main__":
    unittest.main()
