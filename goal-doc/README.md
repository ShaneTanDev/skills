# goal-doc

Author a **durable, reviewable goal document** (本期目标 current-milestone, or 最终目标 final/end
goal) and distill it into the **concise, verifiable objective** the autonomous `/goal` command
(Claude Code and OpenAI Codex) actually pursues.

It turns a vague aim — "make it production-ready", "finish Phase 2", "ship the migration" — into a
measurable objective with success criteria, verification commands, constraints, and a stop
condition. Two artifacts come out:

1. **The detailed goal document** — the human-readable 本期目标 / 最终目标 record.
2. **The concise objective** — one measurable string, verification embedded, that you paste into
   `/goal`.

Both clear the same bar: **measurable outcome over activity**. A goal that can't be *proven* done
never terminates the loop.

## Quick start

From the repo root:

```bash
./install.sh goal-doc             # or ./install.sh to install every skill
```

Then just ask your agent:

> 写个本期目标文档，把 Phase 2 的迁移收尾
> set a goal for /goal: make the auth module production-ready
> 给 /goal 写个目标，把 checkout 的 p95 压到 120ms 以下

## Requirements

None of its own — it reads your repo to find the *real* build/test/lint commands. It pairs with:

| Tool | Used for |
|------|----------|
| `/goal` command | consumes the concise objective the skill produces |
| `codex-reviewer` skill / `codex review` | Step 6 reviews — used when the codex CLI is installed; falls back to a fresh sub-agent when it isn't |

## Install

This skill ships in the [`skills`](../) monorepo. From the repo root:

```bash
./install.sh goal-doc             # this skill only
./install.sh                      # every skill in the repo
```

Copies `SKILL.md` + `references/goal-anatomy.md` into each agent's skill dir whose parent exists
(`~/.claude/skills/goal-doc/`, `~/.codex/…`, `~/.agents/…`, `~/.gemini/antigravity/…`). Re-run any
time to update; uninstall by deleting those dirs.

## What it does

The skill runs a fixed sequence so the goal an agent chases for hours is honest and ungameable:

| Step | What happens |
|---|---|
| 1. Scope | Confirm a goal doc is wanted; pick **本期目标** (milestone, the default) or **最终目标** (end goal). |
| 2. Gather | Read the repo for the *real* verification commands, reference materials, current state, constraints — never invent a test command. |
| 3. Quantify | Pick the validator that fits the domain (bugs, tests, performance, quality, research, ops) and make it numeric/binary. |
| 4. Write doc | Save `docs/goals/<date>-<scope>-<slug>.md` (or a single `GOAL.md`) with every field concrete. |
| 5. Distill | Collapse it into one paste-ready `/goal` objective with verification embedded. |
| 6. Review ×2 | **Two independent adversarial rounds** — Codex (via `codex-reviewer`) when the codex CLI is installed, a fresh sub-agent otherwise. Write → review → fix → review → only then the final doc. Brief: verifiable? single finish line? consistent? *gameable*? |

### The one rule that matters

`/goal` only halts when its stopping condition is **provably** true — an exit code, a test result, a
benchmark number, a file that exists. Never "I believe it's done." So every success criterion must
name evidence an agent can produce. *"The app is production-ready"* never terminates; *"all tests in
`test/auth` pass and `npm run lint` is clean"* does.

### Closing the gaming holes

An autonomous agent optimizes for the *letter* of the criteria. The skill bakes in the recurring
traps to close — tiny denominators (`≥90%` over 5 items), stub/fake substitutes, tests that exist
but never run, post-filter scope, circular units, unverified side-claims.

## Going deeper

`references/goal-anatomy.md` has the full component model (the Codex ↔ Claude Code mapping),
good-vs-bad examples, a 本期 vs 最终 worked pair, and tool-specific setup + lifecycle
(`features.goals`, `/goal pause | resume | clear`, goal states).

---

The skill body lives in `SKILL.md`; agents read it directly. Pairs with the
[codex-reviewer](../codex-reviewer/) skill for Step 6.
