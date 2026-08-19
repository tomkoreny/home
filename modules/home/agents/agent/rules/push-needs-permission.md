---
description: A push is about to run. Resolve the remote host and check it against the allowed list first.
condition: 'git\s+push'
scope: tool
interruptMode: tool-only
---

Before this push runs, resolve where it actually goes. `origin` is a name, not a destination: run `git remote get-url <remote>` and read the host and namespace.

**Push freely** to Tom's own remotes:

- `git.tomkoreny.com/*`
- `gitea.home.tomkoreny.com/*`
- `github.com/tomkoreny/*`
- `github.com/TomAndTer/*`

**Ask first**, naming the resolved URL and the branch, for everything else. That includes client and work organisations (`github.com/corsearch`, `github.com/IT2GO-cz`, `github.com/astrabytesyncltd`, every `gitlab.com` namespace) and any third-party upstream that exists here as a fork (`lvgl`, `holodeck-b2b`, `emilybache`). A host or namespace not on either list is treated as "ask".

State which list the remote landed on in one clause, then either push or ask. This fires once per session, so make the check count: if a later push in the same session targets a different remote, resolve that one too.
