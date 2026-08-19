---
description: A commit is about to credit the agent or a model. Commits are authored by Tom alone.
condition: '(?im)^\s*co-authored-by:\s*(claude|codex|gpt|openai|omp|agent|cursor|copilot|.*noreply@)|noreply@anthropic\.com|generated with \[?(claude|codex|omp)|🤖 generated'
scope: tool
interruptMode: tool-only
---

The commit in flight credits a model or the agent. Remove it and commit again.

Every commit is authored by `Tom Koreny <tom@tomkoreny.com>` and no one else. That means no `Co-authored-by:` trailer naming a model, no `noreply@anthropic.com`, no "Generated with" line, no robot emoji, and no "as requested by the agent" phrasing in the body. The message describes the change, not who or what typed it.

Nothing else about the commit needs to change. Keep the subject and body you already wrote, drop the attribution lines, and re-run the command.

One legitimate exception: a rule file, changelog, or piece of documentation that quotes such a trailer in order to talk about it. Say that is what you are doing and continue.
