# OMP for herdr-chat's session reader. Joined after pi.py (see
# readers/manifest.json), whose words_of and shown_on it reuses.

def omp_call(name, inp):
    inp = inp if isinstance(inp, dict) else {}
    intent = short(inp.get("i"), 80)
    if name == "bash": return {"k": "shell", "d": short(inp.get("command"), 400)}
    if name == "read":
        p = str(inp.get("path", ""))
        return {"k": "image" if re.search(r"\.(png|jpe?g|gif|webp)$", p, re.I) else "read", "d": leaf(p.split(":")[0]) or intent}
    if name in ("edit", "write"): return {"k": "edit", "d": leaf(inp.get("path")) or intent or name, "n": 1}
    if name in ("grep", "glob"): return {"k": "search", "d": short(inp.get("pattern") or inp.get("path"), 200) or intent}
    return {"k": "other", "d": (name + ": " + intent) if intent else name}

def omp_crumb():
    """The session OMP itself recorded for this terminal: (path, known).

    OMP writes ~/.omp/agent/terminal-sessions/<pty> whenever a session starts or
    changes: the folder on the first line, the session file on the second. A
    file older than the terminal belongs to an earlier owner of that pty.
    `known` without a path is a session OMP has opened but not written yet."""
    for pid in terminal_pids():
        try: tty = os.readlink("/proc/%d/fd/0" % pid)
        except OSError: continue
        if not tty.startswith("/dev/pts/"): continue
        crumb = os.path.join(HOME, ".omp", "agent", "terminal-sessions", "pts-" + tty[len("/dev/pts/"):])
        try:
            if os.path.getmtime(crumb) < A.created / 1000 - 10: return None, False
            with open(crumb, encoding="utf-8", errors="replace") as f: lines = f.read().split("\n")
        except OSError: return None, False
        path = lines[1] if len(lines) > 1 else ""
        if not path: return None, False
        return (path if os.path.isfile(path) else None), True
    return None, False

def omp_folders(cwd):
    """Where OMP keeps a folder's sessions: named after the folder, relative to home when inside it."""
    names = []
    if cwd == HOME or cwd.startswith(HOME + os.sep):
        names.append("-" + re.sub(r"[\\/:]", "-", cwd[len(HOME):].lstrip("\\/")))
    names.append("-" + re.sub(r"[\\/:]", "-", cwd.lstrip("\\/")))
    return [os.path.join(HOME, ".omp", "agent", "sessions", n) for n in names]

def find_omp():
    path, known = omp_crumb()
    if known: return path
    # No pty to go by (macOS, an OMP that keeps no session): the newest log of the terminal's folders.
    since = A.created / 1000 - 10
    files = set()
    for cwd in candidate_cwds():
        for folder in omp_folders(cwd):
            files.update((os.path.getmtime(fp), fp) for fp in glob.glob(os.path.join(folder, "*.jsonl")))
    files = [f for f in files if f[0] >= since]
    if not files: return None
    newest = max(files)
    if A.known and newest[1] == A.known: return A.known
    if A.screen:
        screen = words_of(A.screen)
        hits = [f for f in files if shown_on(f[1], screen)]
        return max(hits)[1] if hits else None
    if len(files) > 1 or A.peers:
        state["need"] = "screen"
        return None
    return newest[1]

def omp_entry(o):
    m = o.get("message") or {}
    role = m.get("role")
    content = m.get("content") or []
    if role == "user":
        said = re.sub(r'(?s)<skill name="([^"]+)"[^>]*>.*?</skill>\s*', r"/skill:\1 ", content_text(content))
        add_message("user", "", *placed_images(said))
    elif role == "assistant":
        for c in content if isinstance(content, list) else []:
            if not isinstance(c, dict): continue
            if c.get("type") == "text": add_message("assistant", "final", c.get("text"))
            elif c.get("type") == "thinking": add_reasoning(c.get("thinking"))
            elif c.get("type") == "toolCall": add_call(omp_call(str(c.get("name", "")), c.get("arguments")), str(c.get("id", "")))
    elif role == "toolResult":
        set_output(str(m.get("toolCallId", "")), "\n".join(str(c.get("text", "")) for c in content if isinstance(c, dict) and c.get("type") == "text"))

def parse_omp(path):
    """An OMP log is a tree: each entry names its parent, and the conversation is
    the branch that ends at the newest entry. Entries carrying `activeLeafId`
    are side records (model usage) that name that end without moving it.
    Entries read since the last pass must continue the branch; when one starts
    another (/tree, a rewind), the whole log is read again."""
    nodes = []
    for line in read_tail(path):
        if '"id":"' not in line: continue
        o = loads(line)
        if isinstance(o, dict) and o.get("id") and o.get("type") != "session": nodes.append(o)
    if state["fresh"]:
        by = {o["id"]: o for o in nodes}
        tip = (nodes[-1].get("activeLeafId") or nodes[-1]["id"]) if nodes else ""
        live, x = set(), by.get(tip)
        while x and x["id"] not in live:
            live.add(x["id"])
            x = by.get(x.get("parentId"))
        branch = [o for o in nodes if o["id"] in live]
    else:
        tip, branch = A.leaf, []
        for o in nodes:
            end = o.get("activeLeafId")
            if not tip or (end or o.get("parentId")) != tip:
                A.offset = 0
                return parse_omp(path)
            if not end:
                tip = o["id"]
                branch.append(o)
    state["chain"] = tip
    for o in branch:
        if o.get("type") == "message": omp_entry(o)

READERS["omp"] = (find_omp, parse_omp)
