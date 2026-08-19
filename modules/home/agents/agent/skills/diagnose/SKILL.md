---
name: diagnose
description: Disciplined loop for hard bugs, regressions, and performance problems. Use when the cause is unknown, when a fix has already failed once, when the user reports the same symptom a second time ("still not working", "still the same"), or when the bug only shows up in a running system.
---

# Diagnose

Six phases. Skip one only by saying which and why.

Redact first: build every loop against environment variables, and write `<REDACTED>` in place of any secret that appears in a captured log, header, or config.

## Phase 1 — build a loop that goes red

**This is the skill. Everything after it is mechanical.**

Find a command that fails *because of this bug*, in preference order:

1. A failing test at an existing seam.
2. `curl` or an HTTP client against the running service.
3. A CLI invocation plus a fixture.
4. The real UI driven by `browser`, or the real TUI driven by `hub` + `send`.
5. `debug`: breakpoint at the suspect frame, read the actual state.
6. Replay of a captured request, trace, or log.
7. A throwaway harness in `$TMPDIR`.
8. A bisection harness over commits or config.
9. A differential loop: same input, working system versus broken one.
10. A human-in-the-loop script — last resort, and only for steps the human alone can do (signing in, physical devices). Print the human's observations back as `KEY=value` so the rest stays automated.

Phase 1 is done when you can name **one command you have already run at least once**, quoting the invocation and its output, that is:

- [ ] **Red-capable** — it asserts the user's exact symptom. "Runs without erroring" does not count; it has to be able to catch *this* bug.
- [ ] **Deterministic** — same verdict every run.
- [ ] **Fast** — seconds.
- [ ] **Agent-runnable** — you can run it unattended, as many times as you like.

If you catch yourself reading code to build a theory before that command exists, stop: jumping to a hypothesis is the exact failure this skill prevents. **No red-capable command, no Phase 2.** If a loop genuinely cannot be built, say so, list what you tried, and stop — do not hypothesise without one.

## Phase 2 — reproduce, then minimise

Strip the repro until every remaining element is load-bearing: removing any one of them makes the loop go green. Do not proceed until it is both reproduced and minimal.

## Phase 3 — three to five ranked hypotheses

Write them all down before testing any. A single hypothesis anchors you to the first plausible idea, which is how the second and third failed fix attempts happen.

Each one is falsifiable: "if X is the cause, then changing Y makes the symptom disappear." A hypothesis you cannot state a prediction for is a vibe — sharpen it or drop it. Then test in rank order, cheapest discriminating experiment first.

When the system is a black box to you, ask the source of truth rather than guessing: read the migration order, the deployed manifest, the actual running image tag, the vendor's docs page. A hypothesis contradicted by a file you have not opened is a wasted round trip.

## Phase 4 — instrument

Tag every temporary log with one unique prefix, `[DEBUG-a4f2]`. Cleanup later is then a single `grep`. Untagged logs survive; tagged logs die.

## Phase 5 — regression test, then fix

Write the test before the fix, but only if a correct seam exists. **If no correct seam exists, that is the finding** — note that the architecture prevents this bug from being locked down, and verify on the matching surface instead.

## Phase 6 — close out

- [ ] The loop from Phase 1 now goes green, and its output is quoted.
- [ ] `grep` for the `[DEBUG-...]` prefix returns nothing.
- [ ] Temporary harnesses are outside the repo.
- [ ] The hypothesis that turned out to be correct is stated in the summary, so the next reader learns the cause and not just the patch.
