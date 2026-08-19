---
description: An edit or write is introducing a placeholder implementation. Land the real behaviour or say what is blocking it.
condition: 'TODO: implement|FIXME: implement|NotImplementedError|unimplemented!\(|throw new Error\("[Nn]ot implemented|// placeholder|# placeholder|for now, just return'
scope: tool
interruptMode: tool-only
---

The edit in flight writes a placeholder where behaviour belongs. Before it lands, pick one:

1. **Implement it.** The information is usually already in context or one `read`/`lsp` call away.
2. **Name the missing prerequisite.** If the real implementation genuinely needs something unavailable (a credential, an undecided schema, an API you cannot reach), say which one, finish every other reachable part of the task, and leave no placeholder body behind.
3. **Deliberate stub, requested or structural.** A test double, an abstract method, a `never`-default exhaustiveness guard, or a scaffold the user asked for is fine. Say in one clause which of these it is and continue.

What is not fine is a placeholder that ships silently inside otherwise-finished work, because the diff then reads as complete to everyone including the next session.
