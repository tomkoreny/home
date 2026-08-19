---
description: Filler, sycophancy, and AI-tell vocabulary in a reply. Rewrite the sentence around the fact instead.
condition: '(?i)\b(delve|delving|tapestry|testament to|pivotal moment|evolving landscape|seamlessly|it is important to note|in order to|due to the fact that|Great question|You.re absolutely right|I hope this helps|Let me know if you|Certainly!|Of course!|Additionally,|Furthermore,|Moreover,)'
scope: text
interruptMode: prose-only
---

You just started a sentence that reads as machine-generated. The partial reply was discarded before it reached the user; write the sentence again.

The fix is never a synonym. Each of these phrases marks a sentence that is carrying no fact:

- `Additionally,` / `Furthermore,` / `Moreover,` — the next clause either belongs in the previous sentence or is a separate line. Drop the connective.
- `it is important to note` / `in order to` / `due to the fact that` — delete, `to`, `because`.
- `Great question` / `You're absolutely right` / `I hope this helps` / `Let me know if you` — delete the whole sentence. The answer is the response.
- `delve`, `tapestry`, `testament to`, `pivotal`, `evolving landscape`, `seamlessly` — name the mechanism or the number instead. "Seamlessly integrates" is either "calls `foo()` directly" or it is nothing.

Prevention beats cleanup: a rewrite pass over already-generated prose reliably misses these, which is why this fires mid-stream rather than at the end.
