# skills

A monorepo of agent skills that install into every AI agent supporting skills — Claude Code, Codex,
OpenClaw, and Gemini. Each top-level directory is one skill: a `SKILL.md` plus any assets it needs.

## Skills

| Skill | What it does |
|-------|--------------|
| [`codex-reviewer`](codex-reviewer/) | Hand any review target — a GitHub PR, a commit range, a single commit, uncommitted work, or specific files — to the OpenAI Codex CLI and get its review back verbatim. Fills the gap that `codex review` can't target a remote PR or a multi-commit range. |
| [`goal-doc`](goal-doc/) | Author a durable, reviewable goal document (本期目标 / 最终目标) and distill it into the concise, verifiable objective the autonomous `/goal` command actually pursues. |

## Install

```bash
./install.sh                 # all skills
./install.sh goal-doc        # one skill by directory name
./install.sh goal-doc codex-reviewer
```

Each skill is copied into every agent root whose parent directory exists, skipping the rest:

| Agent | Path |
|-------|------|
| Claude Code | `~/.claude/skills/<skill>/` |
| Codex | `~/.codex/skills/<skill>/` |
| OpenClaw | `~/.agents/skills/<skill>/` |
| Gemini | `~/.gemini/antigravity/skills/<skill>/` |

Re-run any time to update. Uninstall by deleting those directories. (`README.md` and `DESIGN.md`
are repo docs and are not copied into the installed skill.)

## Adding a skill

Drop a new directory at the repo root containing a `SKILL.md` (plus any `references/` or scripts it
needs) and an optional `README.md`. `./install.sh` discovers it automatically — any top-level dir
with a `SKILL.md` is a skill.
