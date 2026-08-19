---
description: A command that rewrites or destroys git history is about to run without being asked for.
condition: 'git\s+commit[^\n]*--amend|git\s+push[^\n]*(--force|--force-with-lease|\s-f(\s|$))|git\s+reset[^\n]*--hard|git\s+rebase\s+(-i|--interactive)|git\s+branch\s+-D|git\s+tag\s+-d|git\s+push[^\n]*--delete|git\s+clean[^\n]*-[a-z]*f'
scope: tool
interruptMode: tool-only
---

This command destroys work that cannot be recovered from the reflog by someone who does not know it happened. Amending, force-pushing, hard-resetting, interactive-rebasing, deleting a branch or tag, and `git clean -f` all need Tom to ask for them in the current turn.

If he did ask, say which of his words authorised it and continue.

If he did not, stop and offer the non-destructive route instead:

- Wrong message on the last commit → a new commit, or ask before amending.
- Unwanted changes → `git stash`, or `git restore` a named path.
- Wrong branch state → a new commit that reverses it, so the mistake stays in the history where the next reader can see it.
- Untracked clutter → list what would be deleted and let him confirm.
