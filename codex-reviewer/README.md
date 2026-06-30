# codex-reviewer

Hand any review target to the **OpenAI Codex CLI** and get its review back, verbatim — a GitHub
**PR (number or URL)**, a **range of commits**, a single commit, your uncommitted work, or specific
files.

It fills the gap in the official `codex review` / [`/codex:review` plugin](https://github.com/openai/codex-plugin-cc):
those only target local git state and **cannot review a remote PR or a multi-commit range**. This
skill adds both, on top of the same `codex review` engine.

**Review-only.** It never edits code, applies patches, or fixes anything. Output comes back verbatim.

## Quick start

From the repo root:

```bash
./install.sh codex-reviewer       # or ./install.sh to install every skill
```

Then just ask your agent:

> let codex review PR #4521
> 用 codex review 我最近 3 个 commit
> codex 看一下 src/auth 这几个文件有没有安全问题

Or call the helper directly (see [CLI usage](#cli-usage)).

## Requirements

| Tool | Needed for | Setup |
|------|-----------|-------|
| `codex` | everything | `npm i -g @openai/codex`, then `codex login` |
| `gh` | PR review only | `brew install gh`, then `gh auth login` |
| `jq` | PR review only | preinstalled on macOS |

Run from inside the target git repository (except `files`, which works anywhere). No codex trust
setup needed — the skill pre-trusts each run's directory for that invocation only.

## Install

This skill ships in the [`skills`](../) monorepo. From the repo root:

```bash
./install.sh codex-reviewer       # this skill only
./install.sh                      # every skill in the repo
```

Copies `SKILL.md` + `codex-review.sh` into each agent's skill dir whose parent exists
(`~/.claude/skills/codex-reviewer/`, `~/.codex/…`, `~/.agents/…`, `~/.gemini/antigravity/…`).
Re-run any time to update; uninstall by deleting those dirs.

## Usage

### Ask naturally

The skill triggers on phrases like:

- "let codex review this PR" / "review PR #123 with codex"
- "用 codex review 这个 PR / 这些改动 / 这几个文件"
- "codex 看一下我最近 5 个 commit"
- "codex review my uncommitted changes"

The agent maps your intent to a subcommand below and relays Codex's review back unchanged.

### CLI usage

`$D` = the installed skill dir, e.g. `~/.claude/skills/codex-reviewer`.

```bash
# GitHub PR — the headline feature. Number or URL; fork PRs work; private repos work
# as long as git can auth to GitHub (see Troubleshooting).
bash "$D/codex-review.sh" pr 4521
bash "$D/codex-review.sh" pr https://github.com/owner/repo/pull/4521

# Multiple commits / ranges — the other thing the official review can't do.
bash "$D/codex-review.sh" range HEAD~5             # last 5 commits
bash "$D/codex-review.sh" range main               # current branch vs main
bash "$D/codex-review.sh" range abc123 def456      # abc123..def456 (abc123 excluded)
bash "$D/codex-review.sh" range abc123^ def456     # ...including abc123

# Same as official codex review:
bash "$D/codex-review.sh" commit abc123            # one commit
bash "$D/codex-review.sh" uncommitted              # staged + unstaged + untracked

# Static look at files (no diff needed; works outside git repos too):
bash "$D/codex-review.sh" files "Review src/auth/token.ts and session.ts for security bugs"
```

### Range semantics (worth 10 seconds)

`range <base> [tip]` reviews `base..tip` — **base itself is excluded**, Git convention. `tip`
defaults to `HEAD`. Want commit `A` included as the first reviewed commit? Pass `A^`:

```bash
bash "$D/codex-review.sh" range A^ B
```

Before calling Codex, the helper prints the **exact commit list** it is about to review
(`git log --oneline base..tip`), so an off-by-one never slips through silently.

### Steering the review

Anything after `--` is passed to `codex review` — focus text, `-c` config, etc.:

```bash
bash "$D/codex-review.sh" range main -- "Focus on the retry/backoff logic and race conditions"
bash "$D/codex-review.sh" pr 4521 -- -c model="gpt-5.4-mini"
```

Model/effort defaults come from your own codex config (`~/.codex/config.toml`, or a project-level
`.codex/config.toml`) — the skill adds nothing on top.

## How it works

| Target | Mechanism |
|---|---|
| **PR** | `gh` resolves number/base/title; base-repo URL is derived from the PR's own URL (independent of your remotes, fork-safe) → fetched into a private `refs/codex-reviewer/*` namespace with `--no-write-fetch-head` → review runs in a throwaway **detached worktree** → trap-guarded cleanup. Your checkout, branches, `FETCH_HEAD`, and remote-tracking refs are never touched. |
| **range** (tip = HEAD) | `codex review --base <base>` in place — no worktree overhead. |
| **range** (tip ≠ HEAD) | Same worktree isolation as PR, checked out at `tip`. |
| **commit / uncommitted** | `codex review --commit <sha>` / `--uncommitted` in place. |
| **files** | `codex exec --sandbox read-only` — stdout carries only Codex's final review; progress goes to stderr. |

Read-only is layered and honest:

1. `files` → **OS-level** read-only sandbox.
2. PR / non-HEAD ranges → **mechanism-level**: a disposable worktree that is deleted afterwards.
3. In-place reviews → `codex review` is review-only by design, plus `sandbox_mode="read-only"`
   constrains any shell command the model runs.

Every call also pre-trusts its directory for **that invocation only** (never persisted), so reviews
run non-interactively even in repos codex has never been opened in.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `gh pr view failed` | Not a GitHub repo, wrong PR id, or `gh` not logged in → `gh auth login` |
| `git fetch failed ... gh auth setup-git` | Private repo and git lacks GitHub credentials → run `gh auth setup-git` once |
| `missing dependency: ...` | Install the named tool (`codex` / `gh` / `jq`) |
| codex says not logged in | `codex login` |
| Review output contains codex CLI warnings | Cosmetic — `codex review` has no clean-output flag; the review text is at the end |

## vs the official `/codex:review`

| | official `codex review` / plugin | this skill |
|---|---|---|
| uncommitted / branch-vs-base / single commit | ✓ | ✓ |
| **a specific GitHub PR** | ✗ | ✓ (worktree-isolated, fork-safe) |
| **multi-commit range** | ✗ (single `--commit` only) | ✓ (`range`, Git semantics) |
| static file review without a diff | ✗ | ✓ (`files`) |
| touches your checkout | runs in place | PR/range never touch it |
| agents | Claude Code only | Claude Code, Codex, OpenClaw, Gemini |

---

Validated against codex-cli 0.139.0 (real PR + real multi-commit runs; trust, sandbox, and cleanup
paths exercised). The git plumbing lives in `codex-review.sh` — agents call it; nothing is
reconstructed inline.
