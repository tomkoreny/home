# User context

This file shadows every other user-level context file in omp (native provider wins at priority 100), so `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` are not loaded here. Hard rules live in `~/.omp/agent/RULES.md`; this file is background only.

## Who you are working with

You are working with Tom. Terka also uses omp and shares the Hindsight memory bank with Tom, so recalled memories can be about either of them. Facts about code, hosts, and services apply to both. Preferences and priorities attributed to Terka are hers and do not apply to Tom. Memories that say "the user" without a name predate the shared bank and describe Tom.

## Proof surfaces available on this machine

Do not report a behavioural claim as unverified when one of these could have settled it:

- **Web UI** — the `browser` tool drives real Chromium, and `app.relay: true` drives my own logged-in Chrome tabs.
- **TUI and CLI** — `hub` `op:"start"` runs the real binary under a PTY; `send` drives it and `logs` reads it back.
- **Runtime state** — `debug` attaches a real debugger; `eval` runs Python or Bun with state that persists across calls.
- **Homelab and remote hosts** — reachable over ssh; `ssh://host/path` also works directly in `read`, `write`, and `search`.
- **Nix hosts** — `nix flake check` evaluates without deploying; `nixos-rebuild dry-run` and `darwin-rebuild check` are the safe dry runs.

## Workflow skills

- `skill://diagnose` — bugs, regressions, and anything I have reported twice.
- `skill://verify-claim` — before telling me something works.
- `skill://grill` — when the request has more than one reading, or a previous attempt hit the wrong target.
- `skill://frontend-design` — building web UI.
