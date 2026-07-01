---
name: codex-reviewer
description: >-
  Run a read-only Codex (OpenAI codex CLI) code review on something the user names — a GitHub PR
  (number or URL), a range of commits, a single commit, the uncommitted working tree, or specific
  files. Use whenever the user asks to "let codex review", "用 codex review", "codex 看一下", "review
  this PR with codex", "codex review 这些改动 / 这个 commit / 这几个文件", or invokes /codex-reviewer.
  Fills the gap that the official codex review (and /codex:review) cannot target a remote PR or a
  multi-commit range. Review-only: it never edits code, applies patches, or fixes anything.
---

# codex-reviewer

Wrap the local `codex review` CLI to review whatever the user points at, and return Codex's output
**verbatim**. The hard parts (PR fetch, worktree isolation, trust, cleanup) live in the helper
script `codex-review.sh` next to this file — you call it; you do not re-implement it.

## Core constraint (non-negotiable)

- This skill is **review-only**.
- Do **not** fix issues, apply patches, edit files, or say you are about to make changes.
- Your only job: pick the right target, run the helper, and return Codex's output **verbatim** —
  no paraphrasing, no summary, no commentary before or after.
- If the user wants fixes applied, that is a separate, explicit request — stop and confirm first.

## Requirements

- `codex` CLI installed and logged in (`codex login`). PR review also needs `gh` (authenticated)
  and `jq`. If a dependency is missing the helper prints a clear error — relay it.
- Must be run from inside the target git repository.

## How to run it

The helper sits in the **same directory as this SKILL.md**. Invoke it with bash by absolute path.
Default to **foreground** (wait for the result). It prints Codex's review to stdout.

```bash
bash "<dir-of-this-SKILL.md>/codex-review.sh" <subcommand> [args]
```

## Map the user's intent → subcommand

| User wants to review… | Run |
|---|---|
| a GitHub **PR** (`#123`, `123`, or a PR URL) | `codex-review.sh pr <number-or-url>` |
| **multiple commits / a range** | `codex-review.sh range <base-ref> [tip-ref]` |
| their **last N commits** | `codex-review.sh range HEAD~<N>` |
| a **single commit** | `codex-review.sh commit <sha>` |
| **uncommitted** work (staged+unstaged+untracked) | `codex-review.sh uncommitted` |
| their branch **vs a base branch** | `codex-review.sh range <base-branch>` (e.g. `range main`) |
| **specific files** with no diff ("just look at src/foo.ts") | `codex-review.sh files "<review prompt naming the files>"` |

### Commit-range semantics — say which commits, follow Git convention

`range <base> [tip]` reviews `base..tip` and the **base commit is excluded** (everything *after*
base up to tip). `tip` defaults to HEAD.

- "review my last 3 commits" → `range HEAD~3`
- git range `A..B` (B reachable, A not — the Git default) → `range A B`
- **include** commit `A` as the first reviewed commit → `range A^ B` (or tell the user you used `A^`)

The helper **prints the exact commit list** (`git log --oneline base..tip`) to stderr before running,
so the target is confirmed. If you are unsure which commits the user means, run it and show them that
list — do not guess silently.

## Examples

```bash
bash "$D/codex-review.sh" pr 4521
bash "$D/codex-review.sh" pr https://github.com/owner/repo/pull/4521
bash "$D/codex-review.sh" range HEAD~5
bash "$D/codex-review.sh" range main             # branch vs base
bash "$D/codex-review.sh" range abc123^ def456   # commits abc123..def456 inclusive of abc123
bash "$D/codex-review.sh" commit abc123
bash "$D/codex-review.sh" uncommitted
bash "$D/codex-review.sh" files "Review src/auth/token.ts and src/auth/session.ts for security bugs"
```

(`$D` = the directory holding this SKILL.md.)

## Extra Codex args / steering

Pass-through args after `--` reach `codex review` (e.g. focus instructions, `--title`, model config):

```bash
bash "$D/codex-review.sh" range main -- "Focus on the retry/backoff logic and race conditions"
```

To steer model/effort, rely on the user's `~/.codex/config.toml` / project `.codex/config.toml`,
or pass `-c model="..."` after `--`.

## How it stays safe (read-only, layered)

- **Static files** (`files`) → `codex exec --sandbox read-only` (OS-level read-only). Its stdout
  carries **only Codex's final review message**; progress/transcript goes to stderr.
- **PR / non-HEAD range** → runs in a throwaway detached **git worktree**, removed on exit
  (mechanism-level isolation — your real checkout, branches, FETCH_HEAD and remote-tracking refs are
  never touched). Cleanup is trap-guarded, so interrupts/failures don't leak worktrees or refs.
- **uncommitted / current HEAD** → in place; `codex review` is read-only by purpose, plus
  `-c sandbox_mode="read-only"` constrains any shell the model runs.

Trust is handled for you: every call pre-trusts the exact directory for **that invocation only**
(nothing persisted to codex config), so reviews run non-interactively even in repos codex has never
been opened in. Expect no trust prompt; if codex still refuses, relay its error verbatim.

## Heartbeat / hang recovery (built-in, nothing to do)

Every codex run is watchdog-wrapped by the helper: codex's own output stream is the heartbeat. If
it goes completely silent (no stdout and no stderr) for `CODEX_REVIEW_HEARTBEAT` seconds (default
300), the run is declared hung → killed → restarted, up to `CODEX_REVIEW_RESTARTS` extra attempts
(default 2) before failing with a clear error. You will see `no heartbeat … killing codex` /
`restarting codex...` on stderr — that is the watchdog working, not an error to act on. If it gives
up, relay the final error verbatim. Only tune the env vars when the user asks (e.g.
`CODEX_REVIEW_HEARTBEAT=600` for reviews that legitimately think silently for a long time).

## Output mode

- **v1 is foreground on every agent** (Claude Code / Codex / OpenClaw / Gemini) for consistent
  behavior. Wait for the result and return it verbatim.
- Background is a **Claude-only, opt-in** convenience: if (and only if) running in Claude Code and the
  user explicitly asks for background, launch the same `bash …/codex-review.sh …` command as a
  background Bash task and tell them to check back. Do not background on other agents.

## Do not

- Do not modify code or offer to "go ahead and fix it" — relay the review and stop.
- Do not reconstruct the PR/worktree git plumbing inline — always call `codex-review.sh`.
- Do not add `--strict-config` to codex (it rejects valid existing user configs).
