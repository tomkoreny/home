---
name: grill
description: Interview the user to a shared understanding before building. Use when a request has more than one reasonable reading, spans several modules or hosts, when a previous attempt was reverted for hitting the wrong target, or when the user asks to be grilled, quizzed, or challenged on a plan.
---

# Grill

Map the request as a design tree: every decision branches into the decisions hanging off it. Work the tree in rounds.

## The frontier

The **frontier** is every decision whose prerequisites are already settled — the questions answerable now without guessing at answers you have not heard yet. Ask the whole frontier in one round, never one question at a time. A question whose answer depends on another question still open in this round belongs to a later round.

Deliver a round through the `ask` tool: one entry per frontier question, 2–5 concrete options each, and a `recommended` index on every one. The recommendation is not optional — it is what makes a round answerable in one word, and stating it forces you to have a position.

Each round of answers reshapes the tree: settled decisions push the frontier outward. Recompute and ask the next round.

## Facts are your job, decisions are the user's

Never ask the user for something the repo, the filesystem, a log, or a tool can answer. If a frontier question needs a fact from the environment, dispatch a `scout` for it and keep going — a running exploration is just an unsettled prerequisite, so only its dependents wait. Ask the rest of the frontier now.

What genuinely belongs to the user: priorities, tradeoffs they will live with, scope boundaries, anything about intent or taste.

Third category, and the most common mistake: a question whose answer you could get by *running something*. Behaviour, timing, layout, output, whether a config takes effect. That is not theirs to answer either. A throwaway probe answers it faster and hands them a result to react to instead of a decision to make.

## Termination

The session ends when the frontier is empty: every branch visited, nothing silently assumed. Then restate the shared understanding in a few lines — target files or hosts, the observable outcome, and what you are deliberately *not* doing — and wait for confirmation before building.

Never answer your own questions on the user's behalf. A grilling that resolves itself has done nothing.

## Recording

Decisions that are hard to reverse, surprising without context, and the result of a real tradeoff go into the repo, not just the reply: append them to the project's `AGENTS.md`, `CLAUDE.md`, or `.omp/AGENTS.md`, one to three sentences each. All three conditions have to hold. Easy to reverse means you will just reverse it; unsurprising means nobody will wonder why; no real alternative means there is nothing to record beyond doing the obvious thing.
