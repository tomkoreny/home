"""Retire idle OMP sessions in Herdr tabs so open sessions stop piling up.

Run daily by the omp-tab-janitor systemd user timer (see default.nix). For
every Herdr pane where OMP is the foreground process, idle, not focused, and
without a user or assistant message for --min-age-hours, OMP in print mode
reads a digest of the session and decides whether it is done:

- done: OMP exits (Ctrl+D) and the tab closes, or only the pane when the tab
  holds other panes.
- open: a handoff brief is written to ~/.omp/agent/tab-janitor/handoffs/,
  OMP exits, a fresh OMP starts in the same pane with the brief attached and
  replies with the open items, and the tab is renamed.

A session started from a handoff and never used again is skipped, so briefs
are not re-summarised every day. Tabs still carrying Herdr's numeric default
label are named from their session titles. Every action is appended to
~/.omp/agent/tab-janitor/log.jsonl; old sessions stay on disk and resume with
`omp --resume <session file>`.
"""

import argparse
import concurrent.futures
import datetime as dt
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

STATE = Path.home() / ".omp/agent/tab-janitor"
MARKER = "<!-- omp-tab-janitor handoff v1 -->"
START_MESSAGE = "Read the attached handoff from my previous session and follow its last line."
DEFAULT_LABEL = re.compile(r"\d+")
READY = {"idle", "done"}

TRIAGE_PROMPT = """You triage idle coding-agent (omp) sessions for Tom, who wants to close finished terminal tabs and restart stale unfinished ones with a handoff summary.

You get a digest of one session: metadata plus the active branch of the transcript (tool calls collapsed, long texts trimmed).

Decide `status`:
- "done": every request the user made was completed or answered, and nothing remains that needs Tom or the agent to act. An optional closing offer ("if you want, I can also…") does not make it open. A session whose question was answered informationally is done.
- "open": anything still pending: unfinished or interrupted work, the agent's last message waits on a decision/confirmation/info from Tom that the task needs, explicit remaining next steps, something to verify or monitor later, a deploy/commit not yet done, or a blocker. When genuinely unsure, choose "open".

`reason`: one plain sentence explaining the verdict, naming the concrete pending item if open.

`tab_name`: a short lowercase label for the terminal tab, 1-3 words, max 20 characters, plain ASCII without diacritics (e.g. "uredni deska", "unifi radius", "dph podklady"). If the current tab label already describes the topic well and is not just a number, return it unchanged.

`summary`: only for "open" sessions (empty string for "done"). A handoff brief for a fresh agent that will continue in the same working directory without the old transcript. Write it in the language Tom used in the session. Use these markdown sections: Goal, Done so far, Current state, Open items (concrete next steps or the pending question for Tom), Key references (file paths, hosts, commands, IDs, URLs, branch names). Max ~350 words. Use only facts from the digest; never invent.

Answer with exactly one JSON object with the keys status, reason, tab_name and summary, and nothing else."""

NAMING_PROMPT = """You name terminal tabs that each hold one coding-agent session.

The attachment is a JSON list of objects with `tab`, `title` and `first_message`. Give every tab a short lowercase label: 1-3 words, max 20 characters, plain ASCII without diacritics, describing the session's topic (e.g. "uredni deska", "unifi radius", "dph podklady").

Answer with exactly one JSON object mapping each `tab` value to its label, and nothing else."""

# Commands run inside a pane may carry that pane's Herdr context; drop it so
# every call targets the default session. Keep the user's config location.
ENV = {key: value for key, value in os.environ.items() if not key.startswith("HERDR_") or key == "HERDR_CONFIG_PATH"}
log_lock = threading.Lock()


def herdr(*args):
    out = subprocess.run(["herdr", *args], env=ENV, text=True, capture_output=True, timeout=120)
    if out.returncode:
        raise RuntimeError(f"herdr {' '.join(args)}: {out.stderr.strip()}")
    # `pane run` acknowledges with an empty stdout; failures exit non-zero.
    return json.loads(out.stdout)["result"] if out.stdout.strip() else None


def record(**fields):
    fields = {"time": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), **fields}
    with log_lock:
        STATE.mkdir(parents=True, exist_ok=True)
        with open(STATE / "log.jsonl", "a", encoding="utf-8") as handle:
            handle.write(json.dumps(fields, ensure_ascii=False) + "\n")
        detail = fields.get("reason") or fields.get("why")
        print(f"{fields.get('tab', '-')} {fields.get('label', '')!r}: {fields['action']}"
              + (f" ({detail})" if detail else ""), flush=True)


def parse_time(value):
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00")) if value else None


def message_text(message):
    content = message.get("content")
    if isinstance(content, str):
        return content, []
    content = content or []
    text = "\n".join(block.get("text", "") for block in content if block.get("type") == "text")
    tools = [block.get("name") or "?" for block in content if block.get("type") == "toolCall"]
    return text, tools


class Session:
    """The active branch of an OMP session file: title and user/assistant messages."""

    def __init__(self, path):
        self.path = path
        self.title = None
        self.messages = []
        entries, last_id = {}, None
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if entry.get("type") in ("title", "title_change") and entry.get("title"):
                    self.title = entry["title"]
                if "id" in entry:
                    entries[entry["id"]] = entry
                    last_id = entry["id"]
        branch, seen = [], set()
        while last_id in entries and last_id not in seen:
            seen.add(last_id)
            branch.append(entries[last_id])
            last_id = entries[last_id].get("parentId")
        for entry in reversed(branch):
            message = entry.get("message") if entry.get("type") == "message" else None
            if not message or message.get("role") not in ("user", "assistant"):
                continue
            text, tools = message_text(message)
            self.messages.append({
                "role": message["role"],
                "time": entry.get("timestamp"),
                "text": text,
                "tools": tools,
                "stop": message.get("stopReason"),
            })

    @property
    def last_activity(self):
        return parse_time(self.messages[-1]["time"]) if self.messages else None

    @property
    def untouched_handoff(self):
        users = [m for m in self.messages if m["role"] == "user" and m["text"].strip()]
        return len(users) == 1 and MARKER in users[0]["text"]

    @property
    def replied(self):
        return any(m["role"] == "assistant" and m["stop"] == "stop" and m["text"].strip() for m in self.messages)


def trim(text, limit):
    text = text.strip()
    return text if len(text) <= limit else f"{text[:limit // 2]}\n[…]\n{text[-limit // 2:]}"


def digest(pane, session, budget=45000):
    parts = []
    count = len(session.messages)
    for index, message in enumerate(session.messages):
        tail = index >= count - 10
        stamp = (message["time"] or "")[:16]
        if message["role"] == "user" and message["text"].strip():
            parts.append(f"\n### USER [{stamp}]\n{trim(message['text'], 3000 if tail else 1200)}")
        elif message["text"].strip():
            parts.append(f"\n### ASSISTANT [{stamp}]\n{trim(message['text'], 4000 if tail else 500)}")
        elif message["tools"]:
            parts.append(f"(tools: {', '.join(message['tools'])})")
    body = "".join(parts)
    if len(body) > budget:
        body = f"{body[:budget // 4]}\n\n[… middle of session omitted …]\n\n{body[-3 * budget // 4:]}"
    hours = (dt.datetime.now(dt.timezone.utc) - session.last_activity).total_seconds() / 3600
    final = session.messages[-1]["role"] if session.messages else None
    return (
        f"Session title: {session.title}\nWorking directory: {pane['cwd']}\nSession file: {session.path}\n"
        f"Herdr workspace: {pane['workspace']}; current tab label: {pane['label']!r}\n"
        f"Last activity: {hours:.0f} hours ago\n"
        f"Final entry role: {final} (if 'user', the agent never finished replying)\n"
        f"\n## Transcript (active branch; tool calls collapsed)\n{body}"
    )


def omp_json(system, attachment, instruction, model):
    """Ask OMP in print mode, without tools or session, for one JSON object."""
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as handle:
        handle.write(attachment)
    command = ["omp", "-p", "--no-session", "--no-tools", "--no-skills", "--no-rules",
               "--no-extensions", "--no-title", "--no-lsp", "--system-prompt", system]
    if model:
        command += ["--model", model]
    try:
        out = subprocess.run([*command, f"@{handle.name}", instruction], env=ENV, cwd=tempfile.gettempdir(),
                             text=True, capture_output=True, timeout=900)
    finally:
        os.unlink(handle.name)
    if out.returncode:
        raise RuntimeError(f"omp -p exited {out.returncode}: {out.stderr.strip()[-300:]}")
    start, end = out.stdout.find("{"), out.stdout.rfind("}")
    if start < 0 or end < start:
        raise ValueError(f"no JSON object in omp output: {out.stdout.strip()[-300:]}")
    return json.loads(out.stdout[start:end + 1])


def triage(pane, session, model):
    verdict = omp_json(TRIAGE_PROMPT, digest(pane, session), "Triage the attached session digest.", model)
    if verdict.get("status") not in ("done", "open"):
        raise ValueError(f"unexpected status {verdict.get('status')!r}")
    verdict["tab_name"] = str(verdict.get("tab_name") or "").strip()[:24]
    if verdict["status"] == "open" and not str(verdict.get("summary") or "").strip():
        raise ValueError("open verdict without a handoff summary")
    return verdict


def inventory():
    panes = []
    for workspace in herdr("workspace", "list")["workspaces"]:
        tabs = {tab["tab_id"]: tab for tab in herdr("tab", "list", "--workspace", workspace["workspace_id"])["tabs"]}
        for pane in herdr("pane", "list", "--workspace", workspace["workspace_id"])["panes"]:
            tab = tabs[pane["tab_id"]]
            session = pane.get("agent_session") or {}
            panes.append({
                "pane": pane["pane_id"],
                "tab": pane["tab_id"],
                "label": tab["label"],
                "tab_panes": tab["pane_count"],
                "workspace": workspace["label"],
                "agent": pane.get("agent"),
                "status": pane.get("agent_status"),
                "focused": pane.get("focused", False),
                "cwd": pane.get("cwd"),
                "session": session.get("value") if session.get("kind") == "path" else None,
            })
    return panes


def parent_pid(pid):
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8") as handle:
            return int(handle.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        return None


def foreground_omp(pane_id):
    """PID of the OMP the pane's shell runs in the foreground, so Ctrl+D reaches OMP and not the shell."""
    info = herdr("pane", "process-info", "--pane", pane_id)["process_info"]
    procs = info.get("foreground_processes") or []
    omp = [p["pid"] for p in procs if p.get("name") == "omp" and parent_pid(p["pid"]) == info.get("shell_pid")]
    if len(omp) != 1:
        return None
    # OMP forks short-lived children into its own process group; anything else means another program is up.
    if any(p["pid"] != omp[0] and parent_pid(p["pid"]) != omp[0] for p in procs):
        return None
    return omp[0]


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return True


def exit_omp(pane_id, pid):
    herdr("agent", "send-keys", pane_id, "ctrl+d")
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if not alive(pid):
            return True
        time.sleep(0.5)
    # Ctrl+D only exits from an empty editor; dismiss anything it may have opened.
    herdr("agent", "send-keys", pane_id, "esc")
    return False


def still_idle(pane, session):
    """Re-read the pane right before acting: same session, still idle, unfocused, no new messages."""
    current = herdr("pane", "get", pane["pane"])["pane"]
    if (current.get("agent_session") or {}).get("value") != pane["session"]:
        return "the pane now runs another session"
    if current.get("agent_status") not in READY or current.get("focused"):
        return f"the pane is {current.get('agent_status')}{', focused' if current.get('focused') else ''}"
    if Session(pane["session"]).last_activity != session.last_activity:
        return "the session has new messages"
    return None


def wait_for_reply(pane_id, old_path, timeout=600):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        time.sleep(5)
        current = herdr("pane", "get", pane_id)["pane"]
        path = (current.get("agent_session") or {}).get("value")
        if path and path != old_path and os.path.exists(path) and current.get("agent_status") in READY:
            if Session(path).replied:
                return path
    return None


def write_handoff(pane, session, verdict):
    STATE.joinpath("handoffs").mkdir(parents=True, exist_ok=True)
    path = STATE / "handoffs" / f"{Path(session.path).stem.rsplit('_', 1)[-1]}.md"
    last = session.last_activity.strftime("%Y-%m-%d %H:%M UTC")
    path.write_text(
        f"{MARKER}\n# Handoff from a previous omp session\n\n"
        f"This tab was restarted to free memory. The previous session is `{session.path}` "
        f"(title \"{session.title}\", last active {last}). Read that file if a detail below is missing.\n\n"
        f"{verdict['summary'].strip()}\n\n---\n"
        "Do not start working yet. Reply with one or two sentences naming the open items, "
        "then wait for Tom's instructions.\n",
        encoding="utf-8",
    )
    return path


def retire(pane, session, args):
    base = {"tab": pane["tab"], "pane": pane["pane"], "label": pane["label"], "workspace": pane["workspace"],
            "session": session.path, "title": session.title}
    try:
        verdict = triage(pane, session, args.model)
    except (OSError, subprocess.SubprocessError, RuntimeError, ValueError) as error:
        record(**base, action="error", reason=f"triage failed: {error}")
        return
    base.update(verdict=verdict["status"], why=verdict["reason"], new_label=verdict["tab_name"])
    action = "close" if verdict["status"] == "done" else "restart"
    if args.dry_run:
        record(**base, action=f"would {action}")
        return
    try:
        problem = still_idle(pane, session)
        pid = None if problem else foreground_omp(pane["pane"])
        if not problem and pid is None:
            problem = "OMP is not the only foreground process"
        if problem:
            record(**base, action="skipped", reason=problem)
            return
        handoff = write_handoff(pane, session, verdict) if action == "restart" else None
        if not exit_omp(pane["pane"], pid):
            record(**base, action="skipped", reason="OMP did not exit on Ctrl+D; its editor may hold a draft")
            return
        if action == "close":
            if pane["tab_panes"] == 1:
                herdr("tab", "close", pane["tab"])
            else:
                herdr("pane", "close", pane["pane"])
            record(**base, action="closed")
            return
        command = f"omp @{shlex.quote(str(handoff))} {shlex.quote(START_MESSAGE)}"
        herdr("pane", "run", pane["pane"], command)
        new_session = wait_for_reply(pane["pane"], session.path)
        if pane["tab_panes"] == 1 and verdict["tab_name"] and verdict["tab_name"] != pane["label"]:
            herdr("tab", "rename", pane["tab"], verdict["tab_name"])
        record(**base, action="restarted" if new_session else "restarted, no reply yet",
               handoff=str(handoff), new_session=new_session)
    except (OSError, subprocess.SubprocessError, RuntimeError, ValueError, KeyError) as error:
        record(**base, action="error", reason=str(error))


def name_default_tabs(args, only):
    """Name single-pane tabs that still carry Herdr's numeric default label."""
    unnamed = []
    for pane in inventory():
        if only and pane["tab"] not in only:
            continue
        if pane["tab_panes"] != 1 or not DEFAULT_LABEL.fullmatch(pane["label"]) or not pane["session"]:
            continue
        if not os.path.exists(pane["session"]):
            continue
        session = Session(pane["session"])
        first = next((m["text"] for m in session.messages if m["role"] == "user" and m["text"].strip()), "")
        if session.title or first:
            unnamed.append({"tab": pane["tab"], "title": session.title, "first_message": trim(first, 600)})
    if not unnamed:
        return
    try:
        names = omp_json(NAMING_PROMPT, json.dumps(unnamed, ensure_ascii=False, indent=1),
                         "Name the attached tabs.", args.model)
    except (OSError, subprocess.SubprocessError, RuntimeError, ValueError) as error:
        record(action="error", reason=f"tab naming failed: {error}")
        return
    for tab in unnamed:
        name = str(names.get(tab["tab"]) or "").strip()[:24]
        if not name:
            continue
        if args.dry_run:
            record(tab=tab["tab"], title=tab["title"], action="would rename", new_label=name)
            continue
        try:
            herdr("tab", "rename", tab["tab"], name)
            record(tab=tab["tab"], title=tab["title"], action="renamed", new_label=name)
        except (OSError, subprocess.SubprocessError, RuntimeError, ValueError) as error:
            record(tab=tab["tab"], action="error", reason=f"rename failed: {error}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="triage and report, change nothing")
    parser.add_argument("--min-age-hours", type=float, default=24, help="idle time before a session is triaged")
    parser.add_argument("--tab", action="append", default=[], help="only consider this Herdr tab id (repeatable)")
    parser.add_argument("--model", help="model for triage and naming (default: OMP's default model)")
    parser.add_argument("--jobs", type=int, default=3, help="sessions handled in parallel")
    args = parser.parse_args()

    try:
        panes = inventory()
    except (OSError, subprocess.SubprocessError, RuntimeError, ValueError) as error:
        print(f"omp-tab-janitor: cannot reach Herdr: {error}", file=sys.stderr)
        return 1
    only = set(args.tab)
    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=args.min_age_hours)
    candidates = []
    for pane in panes:
        if only and pane["tab"] not in only:
            continue
        if pane["agent"] != "omp" or not pane["session"] or pane["focused"] or pane["status"] not in READY:
            continue
        if not os.path.exists(pane["session"]):
            continue
        session = Session(pane["session"])
        if session.last_activity is None or session.last_activity > cutoff or session.untouched_handoff:
            continue
        candidates.append((pane, session))

    print(f"omp-tab-janitor: {len(candidates)} idle session(s) older than {args.min_age_hours:g}h", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for future in [pool.submit(retire, pane, session, args) for pane, session in candidates]:
            future.result()
    name_default_tabs(args, only)
    return 0


if __name__ == "__main__":
    sys.exit(main())
