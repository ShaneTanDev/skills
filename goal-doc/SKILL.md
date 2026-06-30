---
name: goal-doc
description: >-
  Author a detailed, durable goal document (本期目标 current-milestone, or 最终目标 final/end goal)
  and distill it into the concise, verifiable objective the autonomous `/goal` command (Claude Code
  and OpenAI Codex) actually pursues. Use whenever the user wants a written, reviewable goal
  document or GOAL.md, wants to plan a milestone/phase for autonomous execution, or wants to turn a
  vague aim ("make it production-ready", "finish Phase 2", "ship the migration") into a measurable
  objective with success criteria, verification commands, constraints, and a stop condition.
  Triggers: "写个目标文档", "goal doc", "本期目标", "最终目标", "给 /goal 写目标", "set a goal for
  /goal", "define a milestone/end goal". The durable-document complement to a one-line goal-tool
  objective — reach for it even when the user only describes an open-ended objective an agent should
  chase autonomously.
---

# goal-doc

Shape the user's intent into a goal an autonomous agent can pursue **honestly**, then write it
down. Two artifacts come out of this skill:

1. **The detailed goal document** — durable, reviewable, the 本期目标 or 最终目标 record.
2. **The concise objective** — one measurable string, verification embedded, that you paste into
   `/goal` (or pass to a `create_goal` tool if the environment has one).

The document is the context a human reads and reasons about; the concise objective is what the
agentic loop consumes. Both must clear the same bar: **measurable outcome over activity**.

## The one rule that matters

`/goal` runs a loop — plan → act → observe → adjust — and only halts when its stopping condition
is *provably* true. Completion is evidence-based: a command exit code, a test result, a benchmark
number, a file that exists, a diff that's absent. It is never "I believe it's done." So every
success criterion must name evidence an agent can produce. "The app is production-ready" never
terminates; "all tests in `test/auth` pass and `npm run lint` is clean" does. Converting intent
into observable end-states is most of this skill's value.

Do not transcribe a weak goal. **Repair it first**, and say what you changed:
- Rewrite vague goals into measurable ones when local context makes the rewrite safe.
- Reject pure-activity goals — "make progress", "keep investigating", "improve things", "work on
  X" — unless you sharpen them into a verifiable outcome.
- Ask exactly one concise clarifying question only when the missing detail would change the
  intended outcome or how it's validated (see Clarifying questions). Otherwise pick the most
  honest validator available and proceed.

## Step 1 — Confirm a goal doc is actually wanted, and pick the scope

If the user only wants ordinary implementation work, just do the work — don't force a goal doc.
When a goal *is* the point, confirm (or infer) the scope:

- **本期目标 (current-milestone goal)** — bigger than one prompt, smaller than an open-ended
  backlog. One milestone / sprint / phase with a finish line checkable *today*. The sweet spot for
  `/goal`; default here.
- **最终目标 (final / end goal)** — the north-star end state. Still made verifiable (give it
  acceptance criteria), but broader; it usually *decomposes into* several 本期目标. Capture both
  the vision and the milestone path. An agent should normally run `/goal` against the nearest
  milestone goal, not chase the whole end goal in one run — unless the end goal genuinely has a
  single verifiable finish line.

## Step 2 — Gather real inputs (do not invent)

A goal with a made-up test command is worthless. Find the truth in the repo before writing:

- **Verification commands** — how this project actually builds, tests, lints. Read CI config,
  `package.json` / `Makefile` / scripts, README, or ask. Real command, real target.
- **Reference materials** the agent must read first — roadmap, spec, design doc, the issue, exact
  source paths in play.
- **Current state** — branch, what's already done, what's explicitly out of scope.
- **Constraints** — protected files / public APIs, behaviors that must stay green, conventions or
  business logic not visible from the code alone.

## Step 3 — Make it quantitative

Prefer numbers that represent real success, not decorative precision. Pick the validator type that
fits the domain:

- **Bugs** — reproduction first, fix second; a failing-then-passing validator when possible.
- **Tests** — the exact command and the required pass condition.
- **Performance** — the metric, target threshold, measurement method, and number of runs (e.g.
  "p95 < 120 ms across 3 consecutive runs of the checkout benchmark").
- **Quality** — an observable acceptance bar: lint/typecheck/test pass, N reviewed examples, or a
  user-approved artifact.
- **Research** — the decision the research must enable, the sources/systems in scope, and the
  evidence standard (confirmed vs approximate vs blocked).
- **Operations** — healthy state, monitoring window, failure threshold, rollback/escalation trigger.
- **Artifact constraints** — file paths, affected modules, allowed commands, output formats, target
  environment, deadline, or maximum blast radius.

## Step 4 — Write the detailed goal document

Save to `docs/goals/<YYYY-MM-DD>-<scope>-<slug>.md` (follow the project's convention if it has one;
a single living `GOAL.md` at the repo root is fine for one standing goal). Fill every field with
concrete, checkable content — drop a field only if it truly doesn't apply, never leave a placeholder:

```markdown
# Goal: <one-line objective>

- Scope: 本期目标 (milestone <name>) | 最终目标 (end goal)
- Date: <YYYY-MM-DD>
- Owner / project: <name>

## Objective
<One sentence — a single aim that guides all work. Bigger than one prompt, smaller than a backlog.>

## Success criteria — the verifiable end state
- [ ] <criterion 1 — observable, with the evidence/threshold implied>
- [ ] <criterion 2>
Each item is something the agent can PROVE, not believe.

## Verification — how "done" is proven
- Command: `<exact command>` → expected: <pass / exit 0 / specific output / threshold>
- Artifact: <file, benchmark number, or output that must exist or pass>
Completion may be declared only on this evidence.

## Must NOT change — constraints / no-regression
- <protected files or dirs, public API surface, behaviors that must stay green>

## Scope & boundaries
- In scope: <paths, components>
- Out of scope: <explicitly excluded — name it so the agent doesn't wander>
- Allowed tools / resources: <e.g. network off, specific CLIs, no new deps, max blast radius>

## Read first — reference materials
- <files, specs, issues to read before acting — exact paths>

## Working method — checkpoints
- Work in checkpoints; after each, run the verification above and append a short progress note to
  <path>.
- Commit cadence: <atomic per task / per checkpoint>.

## Stop / blocked condition
- Stop when: every success criterion passes (achieved), OR <turn / time / token-budget cap>, OR no
  defensible path remains (blocked).
- If blocked: report what was tried, why it's stuck, and what would unlock progress — don't thrash.
- Ask the user instead of grinding when: <the specific trigger>.

## Context — not obvious from the code
- <conventions, business logic, gotchas the agent would otherwise miss>
```

## Step 5 — Distill the concise objective (the thing `/goal` consumes)

Collapse the document into one tight objective with the verification embedded. Two forms — put both
at the bottom of the doc so the user can copy one:

**Condensed prose** (Codex pattern, verbatim shape):
> `<desired end state>` verified by `<specific evidence>` while preserving `<constraints>`. Use
> `<allowed inputs, tools, or boundaries>`. Between iterations, `<how to choose the next best
> action>`. If blocked or no valid paths remain, `<what to report and what would unlock progress>`.

**File reference:**
> `/goal Pursue the goal in docs/goals/<file>.md until every item under "Success criteria" passes; verify with the commands in that file; stop and report if blocked.`

**If a goal tool is available** (`get_goal` / `create_goal` — e.g. Codex with `features.goals`, or a
goal-enabled Claude Code): call `get_goal` first. If no active goal exists and the objective clears
the Quality Bar, register the concise objective with `create_goal` (objective string with
verification embedded; scope bounds when they constrain the work; a token budget only if the user
asked for one). If an active goal already matches the intent, keep using it — don't duplicate. If
it conflicts, ask whether to finish the current goal or start a separate goal-backed thread. In
environments without the goal tool (the common case), the paste-ready `/goal` string above is the
deliverable.

## Goal Quality Bar — self-check before handing over

The objective and document should answer all five:
- What concrete thing will be true when this is done?
- What evidence will prove it? (a stranger could run the verification and get an unambiguous pass/fail)
- What quantitative or binary threshold defines success?
- What scope boundaries matter — including what must NOT change?
- What should cause the agent to stop and ask, instead of looping forever?

If any answer is missing or fuzzy, fix it before finishing. And: is this one finish line, not a
backlog? Split a multi-finish goal into separate docs.

### Close the gaming holes (the part that bites)

An autonomous agent optimizes for the *letter* of the criteria. Assume good faith but design as if
it didn't: for each success criterion ask "could this pass while the intent is missed?" The
recurring holes — close each one in the doc:

- **Tiny denominators** — "≥ 90%" over 5 items is just 4/5 vs 5/5. Make the denominator big enough
  that the percentage means what you think (e.g. ≥ 20 labeled cases), and state denominator + rounding.
- **Stub / fake substitutes** — a criterion about real-world quality passes with a mock provider or a
  hand-tuned fixture. Mandate the *real* implementation and realistic inputs (e.g. paraphrased
  queries, not verbatim copies of the source).
- **Tests that don't run** — a test file that exists but isn't in the build target, or runs zero
  assertions. Require proof the test *executed* (non-zero count for that class), not just an overall
  green suite.
- **Post-filter scope** — "the results are correctly scoped" can pass while the underlying query is
  unscoped. Require the constraint at the source (the fetch predicate), not applied afterward.
- **Circular / undefined units** — "delta = the expected count" when the policy that sets the count
  is undefined. Pin the policy.
- **Unverified side-claims** — a criterion ("the old store still loads") with no assertion behind it.
  Every criterion needs a check that actually exercises it, or the agent will quietly skip it.

## Step 6 — Independent adversarial review (don't grade your own homework)

A goal doc is high-leverage: an agent pursues it for hours, so a gameable or ambiguous goal is
expensive to get wrong. You wrote it, so your self-check is biased — get an *independent* adversarial
read before handing it over.

- **In Claude Code**: invoke the **codex-reviewer** skill on the saved goal file, asking specifically
  whether the goal is verifiable, a single finish line, internally consistent, and *gameable* (could
  an agent satisfy the letter while missing the intent).
- **Elsewhere**: run `codex review` on the file, or dispatch a fresh subagent with those same questions.

Then triage every finding: fix the real holes — ambiguous thresholds, gameable bars, unverified
criteria, smuggled scope — directly in the doc. For a finding you judge wrong, say *why* and leave
it; don't fix on autopilot. If you made substantial changes, re-review. If no independent reviewer is
available, run the "Close the gaming holes" checklist above yourself, deliberately, before finishing.

## Clarifying questions

Ask only when a reasonable rewrite would risk pursuing the wrong outcome. Keep it short and aimed at
the missing validator or scope boundary:
- "What metric should define success here: latency, cost, accuracy, or user-visible behavior?"
- "Which environment should I verify against: local, staging, or production?"
- "What is the minimum evidence you want before I mark this goal complete?"

If the user can't give a metric, propose the most honest binary validator available and ask them to
confirm.

## Going deeper

For the full component model (the Codex ↔ Claude-Code mapping), more good-vs-bad examples, a
本期 vs 最终 worked pair, and tool-specific setup + lifecycle (`features.goals`,
`/goal pause | resume | clear`, goal states, Claude Code requirements and caveats), read
`references/goal-anatomy.md`.
