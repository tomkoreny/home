---
name: verify-claim
description: Prove or disprove one specific claim about behaviour with repeatable evidence, and report the proof tier. Use before reporting that something works, is fixed, or is faster, when a fix has to be shown rather than asserted, or when a claim needs a `ran-it` / `test-passes` / `type-check-only` / `unverified` label.
---

# Verify a claim

Verification is not a recap of what you changed. It proves or disproves one claim with evidence someone else can re-run.

## 1. Make the claim falsifiable

Restate it with a condition, a metric, and a threshold. "The list scrolls horizontally now" is verifiable. "The code is cleaner" is not — for an unmeasurable claim, either find the measurable version or drop the claim instead of dressing it up.

## 2. Pick the smallest surface that can disprove it

In preference order, stopping at the first one that fits:

1. A failing-then-passing test at an existing seam.
2. A direct call: `curl`, a CLI invocation, `eval` against the real function.
3. The running app driven by a tool: `browser` for web UI, `hub` + the real binary for a TUI or CLI, `debug` for state at a breakpoint.
4. A throwaway harness in `$TMPDIR`.

Reading the diff is not on this list. Neither is a green typecheck, a passing unrelated suite, or the absence of an error message.

## 3. Run it against both states

For a fix, run the check on the broken state first so you know it can fail; for a performance claim, capture a baseline the same way. Same command, same data, same environment, same warmup. An environment difference between baseline and treatment invalidates the comparison.

## 4. Report one verdict and one tier

Verdict is exactly one of `VERIFIED`, `NOT VERIFIED`, `INCONCLUSIVE`. Use `INCONCLUSIVE` when there was no valid baseline, the signal was noisy, or the measurement itself failed — it is a different fact from `NOT VERIFIED`, and neither gets softened into "should now work".

The tier records how the verdict was reached, and is the label the sticky rules ask for:

| Tier | Means |
| --- | --- |
| `ran-it` | You exercised the real user path in the real program and observed the result. |
| `test-passes` | An automated test at a correct seam went red before the fix and green after. |
| `type-check-only` | It compiles and types check. Says nothing about behaviour. |
| `unverified` | You did not exercise it. Say so plainly. |

`type-check-only` on a behavioural change is not a pass. Quote the command you ran and the line of output that carries the signal, redacting secrets as `<REDACTED>`.

## 5. When you cannot verify

Say which of the four surfaces you tried and what stopped you. An absent test seam is itself a finding worth reporting: it means this behaviour cannot be locked down where it lives. Do not substitute a test that passes by construction — an assertion that recomputes the expected value the way the code does can never disagree with the code. Expected values come from an independent source: a known-good literal, a worked example, the spec.

## Done when

- The claim is stated with a metric and threshold.
- One named command exists, has been run at least once, and its output is quoted.
- Exactly one verdict and one tier are reported.
- Nothing was left in the repo: temporary harnesses live in `$TMPDIR`, and tagged debug output is gone.
