#!/usr/bin/env bash
# codex-reviewer — read-only Codex review for PRs, commit ranges, the working tree, or files.
#
# Subcommands:
#   pr <number|url> [-- <extra codex review args>]   Review a GitHub PR (worktree-isolated)
#   range <base-ref> [tip-ref] [-- <args>]           Review base...tip (base EXCLUDED; tip default HEAD)
#   commit <sha> [-- <args>]                          Review a single commit
#   uncommitted [-- <args>]                           Review staged+unstaged+untracked
#   files <review prompt mentioning the files>       Static read-only review (no diff) via codex exec
#
# Read-only by design. Never edits code. Returns Codex output verbatim on stdout.
set -euo pipefail

die()  { printf 'codex-reviewer: %s\n' "$1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1 (please install it)"; }
in_git_repo() { git rev-parse --git-dir >/dev/null 2>&1; }

# read-only sandbox for the model's own shell commands (sandbox_mode verified valid on codex-cli 0.139.0)
RO=(-c 'sandbox_mode="read-only"')

# codex gates on per-directory trust ("Not inside a trusted directory") even for review. Since every
# call here is read-only-sandboxed, pre-trust the repo root for THIS invocation only (-c does not
# persist to config.toml). pwd -P: codex canonicalizes /var → /private/var on macOS.
repo_root_p() { local r; r="$(git rev-parse --show-toplevel)"; (cd "$r" && pwd -P); }
trust_here() { printf 'projects."%s".trust_level="trusted"' "$(repo_root_p)"; }

# Cleanup state must be SCRIPT-GLOBAL: the EXIT trap fires after the creating function returns,
# so function-local vars would be out of scope (and trip `set -u`). One trap, guarded no-ops.
CR_WT=""; PR_REF=""; BASE_REF=""; CR_OUT=""
_cr_cleanup() {
  [ -n "${CR_WT:-}" ]    && git worktree remove --force "$CR_WT" 2>/dev/null || true
  [ -n "${PR_REF:-}" ]   && git update-ref -d "$PR_REF"   2>/dev/null || true
  [ -n "${BASE_REF:-}" ] && git update-ref -d "$BASE_REF" 2>/dev/null || true
  [ -n "${CR_OUT:-}" ]   && rm -f "$CR_OUT" 2>/dev/null || true
}
trap _cr_cleanup EXIT INT TERM

# Prefer an existing remote URL that already points at the same OWNER/REPO (its auth — ssh or https
# credential helper — already works, which matters for private repos). Fall back to the HTTPS .git URL.
pick_fetch_url() {
  local pr_url="$1" https_url="$2" slug u
  slug="${pr_url#https://github.com/}"; slug="${slug%/pull/*}"   # OWNER/REPO
  while read -r u; do
    case "$u" in
      *"$slug"|*"$slug.git"|*"$slug/"|*":$slug"|*":$slug.git") printf '%s\n' "$u"; return 0 ;;
    esac
  done < <(git remote -v 2>/dev/null | awk '$3=="(fetch)"{print $2}')
  printf '%s\n' "$https_url"
}

# Run codex review at a detached worktree checked out to <tip>, comparing against <base>.
# Non-invasive: never touches the user's checkout. trap guarantees cleanup on any exit/interrupt.
review_in_worktree() {
  local tip="$1" base="$2" title="$3"; shift 3
  CR_WT="$(mktemp -d)"; CR_WT="$(cd "$CR_WT" && pwd -P)"   # global + physical path → matches codex trust key
  git worktree add --detach "$CR_WT" "$tip" >/dev/null
  ( cd "$CR_WT" && codex review "${RO[@]}" \
      -c "projects.\"$CR_WT\".trust_level=\"trusted\"" \
      --base "$base" ${title:+--title "$title"} "$@" )
}

cmd="${1:-}"; shift || true
case "$cmd" in
  pr)
    need codex; need gh; need jq
    in_git_repo || die "not inside a git repository"
    target="${1:-}"; [ -n "$target" ] || die "usage: pr <number|url>"; shift || true
    [ "${1:-}" = "--" ] && shift || true
    pr_json="$(gh pr view "$target" --json number,title,url,baseRefName 2>/dev/null)" \
      || die "gh pr view failed for '$target' (not a PR, wrong repo, or gh not authenticated — try: gh auth login)"
    n="$(jq -r .number      <<<"$pr_json")"
    base="$(jq -r .baseRefName <<<"$pr_json")"
    title="$(jq -r .title    <<<"$pr_json")"
    url="$(jq -r .url        <<<"$pr_json")"          # https://github.com/OWNER/REPO/pull/N
    base_repo_url="${url%/pull/*}.git"
    fetch_url="$(pick_fetch_url "$url" "$base_repo_url")"

    run_id="$(date +%s)-$$"
    PR_REF="refs/codex-reviewer/pr-$n-$run_id"
    BASE_REF="refs/codex-reviewer/base-$n-$run_id"
    if ! git fetch --no-write-fetch-head "$fetch_url" \
          "+refs/pull/$n/head:$PR_REF" \
          "+refs/heads/$base:$BASE_REF"; then
      die "git fetch failed from $fetch_url — for a private repo run: gh auth setup-git"
    fi
    printf '== reviewing PR #%s: %s (base: %s) ==\n' "$n" "$title" "$base" >&2
    review_in_worktree "$PR_REF" "$BASE_REF" "$title" "$@"
    ;;

  range)
    need codex
    in_git_repo || die "not inside a git repository"
    base="${1:-}"; [ -n "$base" ] || die "usage: range <base-ref> [tip-ref]"; shift || true
    tip="HEAD"
    if [ -n "${1:-}" ] && [ "${1:-}" != "--" ]; then tip="$1"; shift || true; fi
    [ "${1:-}" = "--" ] && shift || true
    git rev-parse --verify --quiet "$base^{commit}" >/dev/null || die "no such base ref: $base"
    git rev-parse --verify --quiet "$tip^{commit}"  >/dev/null || die "no such tip ref: $tip"
    # safety net: print the EXACT commits that will be reviewed, so the user confirms the target
    printf '== commits to be reviewed (%s..%s; base excluded) ==\n' "$base" "$tip" >&2
    git --no-pager log --oneline "$base..$tip" >&2 || true
    printf '== end (%s commits) ==\n' "$(git rev-list --count "$base..$tip" 2>/dev/null || echo '?')" >&2
    if [ "$(git rev-parse "$tip")" = "$(git rev-parse HEAD)" ]; then
      exec codex review "${RO[@]}" -c "$(trust_here)" --base "$base" "$@"   # tip == HEAD → in place, no worktree
    fi
    review_in_worktree "$tip" "$base" "" "$@"                 # tip != HEAD → worktree
    ;;

  commit)
    need codex
    in_git_repo || die "not inside a git repository"
    sha="${1:-}"; [ -n "$sha" ] || die "usage: commit <sha>"; shift || true
    [ "${1:-}" = "--" ] && shift || true
    git rev-parse --verify --quiet "$sha^{commit}" >/dev/null || die "no such commit: $sha"
    exec codex review "${RO[@]}" -c "$(trust_here)" --commit "$sha" "$@"
    ;;

  uncommitted)
    need codex
    in_git_repo || die "not inside a git repository"
    [ "${1:-}" = "--" ] && shift || true
    exec codex review "${RO[@]}" -c "$(trust_here)" --uncommitted "$@"
    ;;

  files)
    need codex
    [ "$#" -ge 1 ] || die "usage: files <review prompt mentioning the file paths>"
    if in_git_repo; then EXTRA=(-c "$(trust_here)"); else EXTRA=(--skip-git-repo-check); fi
    CR_OUT="$(mktemp)"
    # transcript/progress → stderr; stdout carries ONLY Codex's final review message (-o)
    codex exec --sandbox read-only "${EXTRA[@]}" -o "$CR_OUT" "$*" 1>&2
    cat "$CR_OUT"
    ;;

  ""|-h|--help|help)
    sed -n '2,11p' "$0"; exit 0 ;;
  *)
    die "unknown subcommand '$cmd' (use: pr | range | commit | uncommitted | files)" ;;
esac
