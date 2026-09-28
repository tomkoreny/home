"""MantisBT REST adapter; common task storage lives in work-tasks.py.

Rules checked against upstream release-2.27.1 (Polaris) and release-2.28.4:
api/rest/restcore/issues_rest.php, core/commands/{ConfigsGet,ProjectUsersGet}Command.php,
core/{access,bug}_api.php, and api/soap/{mc_api,mc_issue_api}.php.
The older REST update does not enforce the UI workflow; enforce it here as well.
"""

import http.client
import json
import re
import ssl
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class TaskError(RuntimeError):
    """An error safe to display without credentials or a server response body."""


def integer(value, field, minimum=0):
    if isinstance(value, bool) or not isinstance(value, (str, int)):
        raise TaskError(f"Mantis returned invalid {field}")
    if isinstance(value, str) and not re.fullmatch(r"[0-9]+", value):
        raise TaskError(f"Mantis returned invalid {field}")
    number = int(value)
    if number < minimum:
        raise TaskError(f"Mantis returned invalid {field}")
    return number


def object_id(value, field, minimum=1):
    if not isinstance(value, dict) or "id" not in value:
        raise TaskError(f"Mantis returned missing {field}")
    return integer(value["id"], field, minimum)


def text(value, field):
    if not isinstance(value, str) or not value.strip():
        raise TaskError(f"Mantis returned invalid {field}")
    return value.strip()


def timestamp(value):
    value = text(value, "updated_at")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            raise ValueError("missing timezone")
        return parsed.astimezone(timezone.utc).isoformat()
    except ValueError as error:
        raise TaskError("Mantis returned invalid updated_at") from error


def base_url(value):
    if not isinstance(value, str):
        raise TaskError("Work task baseUrl must be an HTTPS URL")
    try:
        parsed = urlsplit(value)
    except ValueError as error:
        raise TaskError("Work task baseUrl is not a valid HTTPS URL") from error
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or any(ord(char) <= 32 for char in value)
    ):
        raise TaskError(
            "Work task baseUrl must be an HTTPS URL without credentials, query or fragment"
        )
    try:
        _ = parsed.port
    except ValueError as error:
        raise TaskError("Work task baseUrl has an invalid port") from error
    return value.rstrip("/")


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        # Never carry Authorization to a redirected host, path, or HTTP endpoint.
        return None


class MantisProvider:
    PAGE_SIZE = 100
    OPTIONS = (
        "status_enum_string",
        "status_enum_workflow",
        "set_status_threshold",
        "bug_resolved_status_threshold",
        "bug_closed_status_threshold",
        "update_bug_threshold",
        "update_bug_status_threshold",
        "bug_readonly_status_threshold",
        "update_readonly_bug_threshold",
        "webservice_readwrite_access_level_threshold",
        "bug_submit_status",
        "report_bug_threshold",
    )

    def __init__(self, config):
        self.base = base_url(config.get("baseUrl"))
        try:
            self.token = Path(config["tokenFile"]).read_text().strip()
        except (OSError, UnicodeError, KeyError, TypeError) as error:
            raise TaskError("Cannot read work task token file") from error
        if not self.token or any(
            ord(char) <= 32 or ord(char) >= 127 for char in self.token
        ):
            raise TaskError("Work task token file must contain one raw API token")
        self.opener = build_opener(NoRedirects())
        self.user_id = None
        self.global_access = None
        self.rules = {}

    def http_error(self, error):
        message = f"Mantis HTTP {error.code}"
        if error.code == 412:
            return TaskError(message + ": issue changed; refresh before trying again")
        if 300 <= error.code < 400:
            return TaskError(message + ": redirects are not allowed; check baseUrl")
        # Accept only the structured message field, never HTML, headers or details.
        try:
            if error.headers.get_content_type() != "application/json":
                return TaskError(message)
            body = json.loads(error.read(65536))
            detail = body.get("message") if isinstance(body, dict) else None
            if isinstance(detail, str):
                detail = detail.replace(self.token, "[REDACTED]")
                if (
                    len(detail) <= 500
                    and "<" not in detail
                    and ">" not in detail
                    and not re.search(
                        r"authorization|bearer\s|token\s*[:=]", detail, re.IGNORECASE
                    )
                ):
                    detail = " ".join(detail.split())
                    if detail:
                        message += ": " + detail
        except (ValueError, OSError, http.client.HTTPException):
            pass
        return TaskError(message)

    def request(self, method, path, payload=None, etag=None):
        headers = {"Authorization": self.token, "Accept": "application/json"}
        data = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(payload, separators=(",", ":")).encode()
        if etag is not None:
            headers["If-Match"] = etag
        request = Request(
            self.base + "/api/rest" + path, data=data, headers=headers, method=method
        )
        try:
            with self.opener.open(request, timeout=25) as response:
                if response.headers.get_content_type() != "application/json":
                    raise TaskError(
                        "Mantis returned a non-JSON response; check REST access"
                    )
                result = json.load(response)
                if not isinstance(result, dict):
                    raise TaskError("Mantis returned an invalid JSON object")
                return result, response.headers.get("ETag")
        except HTTPError as error:
            raise self.http_error(error) from error
        except (TimeoutError, URLError, ssl.SSLError, OSError, http.client.HTTPException) as error:
            raise TaskError(
                "Cannot reach Mantis REST API (connection, TLS or timeout failure)"
            ) from error
        except (ValueError, UnicodeError) as error:
            raise TaskError("Mantis returned invalid JSON") from error

    def identify(self):
        user, _ = self.request("GET", "/users/me")
        self.user_id = object_id(user, "user id")
        self.global_access = object_id(user.get("access_level"), "user access level", 0)
        return str(self.user_id)

    def pages(self, path, key, params=()):
        page = 1
        seen = set()
        while True:
            query = list(params) + [("page_size", self.PAGE_SIZE), ("page", page)]
            result, _ = self.request("GET", path + "?" + urlencode(query))
            rows = result.get(key)
            if not isinstance(rows, list):
                raise TaskError(f"Mantis returned invalid {key} page")
            if not rows:
                return
            for row in rows:
                row_id = object_id(row, key + " id")
                if row_id in seen:
                    # A moving or repeated page is not a complete assignment snapshot.
                    raise TaskError(
                        f"Mantis {key} pages changed during refresh; refresh again"
                    )
                seen.add(row_id)
                yield row
            # Fetch through the empty page, even if a server caps page_size.
            page += 1

    @staticmethod
    def threshold(value, field):
        if isinstance(value, list):
            return [integer(level, field) for level in value]
        return integer(value, field)

    @staticmethod
    def permits(level, threshold):
        # access_compare_level: arrays are exact membership, not minimum levels.
        return (
            level in threshold
            if isinstance(threshold, list)
            else threshold < 100 and level >= threshold
        )

    def project_rules(self, project_id):
        if project_id in self.rules:
            return self.rules[project_id]
        query = [("project_id", project_id)] + [
            ("option[]", name) for name in self.OPTIONS
        ]
        response, _ = self.request("GET", "/config?" + urlencode(query))
        entries = response.get("configs")
        if not isinstance(entries, list):
            raise TaskError("Mantis returned invalid project configuration")
        config = {}
        for entry in entries:
            if (
                not isinstance(entry, dict)
                or not isinstance(entry.get("option"), str)
                or "value" not in entry
            ):
                raise TaskError("Mantis returned invalid project configuration entry")
            config[entry["option"]] = entry["value"]
        missing = set(self.OPTIONS) - config.keys()
        if missing:
            raise TaskError(
                f"Mantis project {project_id} is missing required configuration: "
                + ", ".join(sorted(missing))
            )
        statuses = config["status_enum_string"]
        if not isinstance(statuses, list) or not statuses:
            raise TaskError("Mantis returned invalid status enumeration")
        names = {}
        for status in statuses:
            status_id = object_id(status, "status id", 0)
            if status_id in names:
                raise TaskError("Mantis returned duplicate status ids")
            names[status_id] = text(
                status.get("label") or status.get("name"), "status name"
            )
        workflow = config["status_enum_workflow"]
        if workflow == []:
            workflow = {}
        if not isinstance(workflow, dict):
            raise TaskError("Mantis returned invalid status workflow")
        transitions = {}
        for source, enum in workflow.items():
            source_id = integer(source, "workflow status")
            if source_id not in names or not isinstance(enum, str):
                raise TaskError("Mantis returned invalid workflow entry")
            targets = []
            for choice in enum.split(",") if enum.strip() else []:
                parts = choice.strip().split(":", 1)
                if len(parts) != 2 or not parts[1].strip():
                    raise TaskError("Mantis returned invalid workflow target")
                target = integer(parts[0], "workflow target")
                if target not in names or target in targets:
                    raise TaskError(
                        "Mantis returned unknown or duplicate workflow target"
                    )
                targets.append(target)
            transitions[source_id] = targets
        overrides = config["set_status_threshold"]
        if overrides == []:
            overrides = {}
        if not isinstance(overrides, dict):
            raise TaskError("Mantis returned invalid status thresholds")
        thresholds = {
            integer(key, "status threshold id"): integer(value, "status threshold")
            for key, value in overrides.items()
        }
        for name in (
            "bug_resolved_status_threshold",
            "bug_closed_status_threshold",
            "bug_readonly_status_threshold",
            "bug_submit_status",
            "webservice_readwrite_access_level_threshold",
        ):
            config[name] = integer(config[name], name)
        for name in (
            "update_bug_threshold",
            "update_bug_status_threshold",
            "update_readonly_bug_threshold",
            "report_bug_threshold",
        ):
            config[name] = self.threshold(config[name], name)
        access = None
        for user in self.pages(
            f"/projects/{project_id}/users", "users", [("include_access_levels", 1)]
        ):
            if object_id(user, "project user id") == self.user_id:
                access = object_id(user.get("access_level"), "project access level", 0)
        if access is None:
            raise TaskError(
                f"Mantis project {project_id} did not expose your effective access level"
            )
        # Administrators bypass local overrides in access_get_project_level and
        # user_get_access_level, whereas the users listing exposes the override.
        if self.global_access >= 90:
            access = self.global_access
        rules = {
            "config": config,
            "names": names,
            "workflow": transitions,
            "thresholds": thresholds,
            "access": access,
        }
        self.rules[project_id] = rules
        return rules

    def task(self, issue, rules):
        issue_id = object_id(issue, "issue id")
        title = text(issue.get("summary"), "issue summary")
        status_id = object_id(issue.get("status"), "issue status", 0)
        project_id = object_id(issue.get("project"), "issue project")
        project_name = text(issue["project"].get("name"), "project name")
        handler = issue.get("handler")
        owner = object_id(handler, "issue handler", 0) if handler is not None else 0
        priority = object_id(issue.get("priority"), "issue priority", 0)
        sticky = issue.get("sticky")
        if type(sticky) is not bool and not (type(sticky) is int and sticky in (0, 1)):
            raise TaskError("Mantis returned invalid issue sticky flag")
        # Mantis enum values are small integers; keep rank exact for QML doubles.
        if priority >= 10000 or status_id >= 10000:
            raise TaskError(
                "Mantis priority or status is outside the supported enum range"
            )
        names, config, access = rules["names"], rules["config"], rules["access"]
        if status_id not in names:
            raise TaskError(
                f"Mantis issue {issue_id} has a status missing from project configuration"
            )
        active = (
            owner == self.user_id
            and status_id < config["bug_resolved_status_threshold"]
        )
        writable = (
            active
            and self.permits(
                access, config["webservice_readwrite_access_level_threshold"]
            )
            and self.permits(access, config["update_bug_threshold"])
            and self.permits(access, config["update_bug_status_threshold"])
            and (
                status_id < config["bug_readonly_status_threshold"]
                or self.permits(access, config["update_readonly_bug_threshold"])
            )
        )
        actions = []
        if writable:
            # Missing source in a defined workflow means all statuses, as in
            # bug_check_workflow; an explicitly empty source means none.
            for target in rules["workflow"].get(status_id, list(names)):
                default = (
                    config["report_bug_threshold"]
                    if target == config["bug_submit_status"]
                    else config["update_bug_status_threshold"]
                )
                required = rules["thresholds"].get(target, default)
                if target != status_id and self.permits(access, required):
                    actions.append(
                        {
                            "id": str(target),
                            "label": names[target],
                            "statusId": str(target),
                            "statusName": names[target],
                            "actionable": target
                            < config["bug_resolved_status_threshold"],
                        }
                    )
        return {
            "id": str(issue_id),
            "title": title,
            "statusId": str(status_id),
            "statusName": names[status_id],
            "url": f"{self.base}/view.php?id={issue_id}",
            "actionable": active,
            "rank": (0 if sticky else 100000000)
            + (9999 - priority) * 10000
            + status_id,
            "updatedAt": timestamp(issue.get("updated_at")),
            "searchTerms": f"{issue_id} {project_id} {project_name} {names[status_id]}",
            "actions": actions,
        }

    def fetch(self):
        account = self.identify()
        items = []
        options = {}
        for issue in self.pages("/issues", "issues", [("filter_id", "assigned")]):
            project_id = object_id(issue.get("project"), "issue project")
            rules = self.project_rules(project_id)
            task = self.task(issue, rules)
            if task["actionable"]:
                items.append(task)
            for status_id, name in rules["names"].items():
                # A provider-wide filter must not silently mislabel a status
                # that is customized differently across projects.
                if status_id in options and options[status_id] != name:
                    options[status_id] = str(status_id)
                else:
                    options[status_id] = name
        return {
            "account": account,
            "items": items,
            "statusOptions": [
                {"id": str(key), "name": options[key]} for key in sorted(options)
            ],
        }

    def issue(self, issue_id):
        result, etag = self.request("GET", f"/issues/{issue_id}")
        return self.single_issue(result, issue_id), etag

    @staticmethod
    def single_issue(result, issue_id):
        issues = result.get("issues")
        if (
            not isinstance(issues, list)
            or len(issues) != 1
            or object_id(issues[0], "issue id") != issue_id
        ):
            raise TaskError("Mantis returned an invalid issue response")
        return issues[0]

    def transition(self, issue_id, action_id, expected_status, account):
        issue_id = integer(issue_id, "requested issue id", 1)
        action_id = str(integer(action_id, "requested action id"))
        expected_status = str(integer(expected_status, "expected status id"))
        if self.identify() != account:
            raise TaskError(
                "Work task account changed; refresh before changing a status"
            )
        issue, etag = self.issue(issue_id)
        project_id = object_id(issue.get("project"), "issue project")
        rules = self.project_rules(project_id)
        task = self.task(issue, rules)
        if not task["actionable"]:
            raise TaskError(
                "Issue is no longer an actionable task assigned to you; refresh"
            )
        if task["statusId"] != expected_status:
            raise TaskError("Issue status changed; refresh before trying again")
        action = next(
            (entry for entry in task["actions"] if entry["id"] == action_id), None
        )
        if action is None:
            raise TaskError("This status transition is no longer permitted; refresh")
        if not etag or any(ord(char) < 32 or ord(char) == 127 for char in etag):
            raise TaskError(
                "Mantis did not provide a valid ETag; refusing an unprotected status change"
            )
        # Both inspected releases enforce If-Match before merging this status-
        # only patch with the existing issue. Never retry an ambiguous mutation.
        response, _ = self.request(
            "PATCH",
            f"/issues/{issue_id}",
            {"status": {"id": int(action_id)}},
            etag=etag,
        )
        updated = self.single_issue(response, issue_id)
        if object_id(updated.get("project"), "updated project") != project_id:
            raise TaskError(
                "Mantis returned a changed project after updating; refresh to reconcile"
            )
        result = self.task(updated, rules)
        if result["statusId"] != action["statusId"]:
            raise TaskError(
                "Mantis did not return the requested status; refresh to reconcile"
            )
        return result
