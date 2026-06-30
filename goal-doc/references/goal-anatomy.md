# Goal anatomy, examples, and tool lifecycle

Reference for the `goal-doc` skill. Read when you need the full component model, concrete
examples, or the tool-specific setup details for Claude Code vs OpenAI Codex.

## Table of contents
1. Why goals must be verifiable
2. Component model (Codex ↔ Claude Code → unified)
3. The Codex prose template (verbatim)
4. Good vs bad goals
5. 本期目标 vs 最终目标 — a worked pair
6. Tool-specific setup & lifecycle
7. Sources

---

## 1. Why goals must be verifiable

`/goal` runs an agentic loop — plan, act, observe, adjust — and only halts when its stopping
condition is provably true. The completion test is **evidence-based**: the agent compares the
objective against concrete evidence (modified files, command output, test results, benchmark
numbers, generated artifacts). Completion cannot be declared on belief alone.

This is why "make it production-ready" or "improve performance" fail as goals: they produce no
checkable evidence, so the loop has no defensible exit. "Reduce p95 latency below 120 ms on the
checkout benchmark while keeping the correctness suite green" works — every word maps to a number
or a pass/fail. The whole craft of a goal doc is converting intent into observable end-states.

### How a goal reaches the loop

There are two delivery mechanisms; the goal content is identical either way:

1. **Inline prose** — paste `/goal <objective string>` (Claude Code, or Codex once `features.goals`
   is on). This is the common case and the default deliverable of this skill.
2. **Goal tool** — some environments expose `get_goal` / `create_goal`. There, call `get_goal`
   first (don't duplicate an active goal), then `create_goal` with the concise objective string.
   A sibling skill, `define-goal`, specializes in this path and deliberately produces *no* durable
   artifact. `goal-doc` is the complement: it writes the durable 本期/最终 document AND distills the
   same concise objective, so it serves both mechanisms. If `create_goal` isn't present (the common
   case), the inline `/goal` string is the output — never block on a tool that isn't there.

A `create_goal` objective is a single concise string with the verification embedded, scope bounds
when they constrain the work, and a token budget only when the user explicitly asked for one — the
same distilled objective produced in Step 5 of `SKILL.md`.

## 2. Component model

Both tools describe the same anatomy under different headings. The unified template in `SKILL.md`
covers all of them.

| Unified field (SKILL.md)        | Codex cookbook (6) | Codex use-case (5)   | Claude Code (4)      |
|---------------------------------|--------------------|----------------------|----------------------|
| Objective                       | Outcome            | Single objective     | Specific scope       |
| Success criteria + Verification | Verification surface | Validation artifacts | Success criteria + check |
| Must NOT change                 | Constraints        | (in stopping cond.)  | Constraints          |
| Scope & boundaries              | Boundaries         | (in objective)       | Specific scope       |
| Read first                      | (inputs)           | Reference materials  | Contextual info      |
| Working method (checkpoints)    | Iteration policy   | Checkpoint strategy  | —                    |
| Stop / blocked condition        | Blocked stop cond. | Stopping condition   | Turn/time cap (opt.) |
| Context                         | —                  | —                    | Contextual info      |

The two non-obvious fields people skip:
- **Iteration / checkpoint policy** — tell the agent to work in checkpoints and keep a short
  progress log. Long autonomous runs that don't checkpoint lose their place and can't recover.
- **Blocked stop condition** — the agent needs permission to stop and *report* when no defensible
  path remains, instead of thrashing or declaring false victory.

## 3. The Codex prose template (verbatim)

`/goal` consumes prose, so condense the document into one paragraph in this shape:

> `<desired end state>` verified by `<specific evidence>` while preserving `<constraints>`. Use
> `<allowed inputs, tools, or boundaries>`. Between iterations, `<how Codex should choose the next
> best action>`. If blocked or no valid paths remain, `<what Codex should report and what would
> unlock progress>`.

Research-flavored variant (for investigation goals rather than code changes):

> Produce the strongest evidence-backed reproduction of `<topic>` using available materials and
> local resources. Attempt headline results where feasible, verify outputs, and end with a report
> that separates confirmed findings, approximate reconstructions, blocked claims, and remaining
> uncertainty.

## 4. Good vs bad goals

**Performance**
- ✗ `/goal Improve performance`
- ✓ `/goal Reduce p95 latency below 120 ms on the checkout benchmark while keeping the correctness test suite green`

**Refactor**
- ✗ `/goal Improve the authentication system`
- ✓ `/goal Refactor JWT validation in src/auth/middleware.ts to use the shared TokenService class; all tests in tests/auth pass and the public auth API is unchanged`

**Migration**
- ✗ `/goal Migrate the database`
- ✓ `/goal Finish the Postgres migration: the migration script runs clean against the dev DB, all integration tests pass, and no model file under src/models/ changes its public fields`

**Review comments** (evidence = an external check, not just tests)
- ✗ `/goal Keep investigating the PR comments`
- ✓ `/goal Resolve the open review comments on PR 123 that request code changes, touching only the affected auth files and tests, verified by the targeted auth test command plus `gh pr view 123` showing no unresolved change-request threads`

**Constraint examples worth copying**
- `Don't modify any files in src/shared — owned by another team.`
- `Preserve the existing public API surface — no breaking changes to exported functions.`

## 5. 本期目标 vs 最终目标 — a worked pair

Same project, two scopes.

**最终目标 (end goal)** — north-star, broad, decomposes into milestones:
> Ship a privacy-first note app where every summary sentence traces back to its source and the
> core loop runs fully on-device. End-state acceptance: all four roadmap phases merged to main
> with their per-phase success criteria green.

Note it is *made* verifiable ("all four phases merged with criteria green") but is too large for a
single `/goal` run — it frames the milestones rather than being executed directly.

**本期目标 (this milestone)** — one finish line, runnable now:
> Implement Phase 2 RAG chatbot for a single notebook. Done when: `xcodebuild test -scheme App`
> is fully green including new RAGChatServiceTests; a query over a 50-increment notebook returns
> an answer whose citations resolve to real increment IDs; no change to Phase 1 model files.
> Verify with the test command + the citation-resolution test. Out of scope: cloud embeddings,
> custom templates. Stop and report if the on-device embedding model is unavailable.

The end goal is the *why*; the milestone goal is what you actually feed `/goal`.

## 6. Tool-specific setup & lifecycle

### OpenAI Codex
- **Enable**: add to `config.toml`
  ```toml
  [features]
  goals = true
  ```
  or run `codex features enable goals`. If `/goal` isn't in the slash-command list, it's not enabled.
- **Use**: `/goal <objective>` sets it; bare `/goal` shows the current goal.
- **Lifecycle**: `/goal pause`, `/goal resume`, `/goal clear`.
- **States**: `pursuing`, `paused`, `achieved`, `unmet`, `budget-limited`. A goal that hits its
  budget/turn cap without meeting criteria ends `unmet` or `budget-limited` — which is exactly why
  the doc must state a stop condition and a blocked-report instruction.
- Best-practice from the docs: work in checkpoints, keep a short progress log, inspect with `/goal`
  while it runs. "A good goal is bigger than one prompt but smaller than an open-ended backlog."

### Claude Code
- `/goal <objective>` sets a persistent objective; the agent loops until the success condition is
  met or it needs genuine input.
- Reported requirements (verify against your installed version's docs): a recent Claude Code build
  (the feature shipped around v2.1.139); the workspace trust dialog must be accepted, because the
  goal evaluator runs as part of the hooks system. It is unavailable if hooks are disabled —
  `disableAllHooks` at any level, or `allowManagedHooksOnly` in managed settings — and `/goal`
  will tell you why if so.
- Same authoring rules apply: scope, measurable success criteria, a stated check, constraints on
  what shouldn't change, and an optional turn/time cap.

Because the two tools share the same goal anatomy, one well-formed `goal-doc` works for both — only
the enablement and lifecycle commands differ.

## 7. Sources

- OpenAI Codex — Follow a goal: https://developers.openai.com/codex/use-cases/follow-goals
- OpenAI Codex — Using Goals in Codex (cookbook): https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex
- OpenAI Codex — Slash commands: https://developers.openai.com/codex/cli/slash-commands
- Claude Code `/goal` overview (third-party): https://www.mindstudio.ai/blog/claude-code-goal-command-autonomous-tasks
- Claude Code `/goal` implementation notes (third-party): https://labuladong.online/en/ai-coding/claude-code/goal-command/

The Claude Code version/hooks details come from third-party write-ups, not official Anthropic
docs — present them as "reported" and verify against the installed build before relying on them.
