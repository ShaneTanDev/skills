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
# Heartbeat: codex output is the heartbeat. Total silence (stdout+stderr) for
# CODEX_REVIEW_HEARTBEAT seconds (default 300) = hung -> killed and restarted,
# up to CODEX_REVIEW_RESTARTS times (default 2) before giving up.
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
CR_WT=""; PR_REF=""; BASE_REF=""; CR_OUT=""; HB_OUT="$(mktemp)"; HB_ERR="$(mktemp)"
_cr_cleanup() {
  [ -n "${CR_WT:-}" ]    && git worktree remove --force "$CR_WT" 2>/dev/null || true
  [ -n "${PR_REF:-}" ]   && git update-ref -d "$PR_REF"   2>/dev/null || true
  [ -n "${BASE_REF:-}" ] && git update-ref -d "$BASE_REF" 2>/dev/null || true
  [ -n "${CR_OUT:-}" ]   && rm -f "$CR_OUT" 2>/dev/null || true
  rm -f "$HB_OUT" "$HB_ERR" 2>/dev/null || true
}
trap _cr_cleanup EXIT INT TERM

# --- heartbeat watchdog -------------------------------------------------------
# codex's own output is the heartbeat: it streams progress while healthy. If BOTH
# streams go silent for HB_TIMEOUT seconds the run is hung -> kill, restart (max
# HB_RESTARTS extra attempts), then give up. stderr streams live via tail -f;
# stdout is buffered to a file and emitted verbatim on completion (no interleaving
# races, and a killed attempt never leaks partial review text to the caller).
HB_TIMEOUT="${CODEX_REVIEW_HEARTBEAT:-300}"
HB_RESTARTS="${CODEX_REVIEW_RESTARTS:-2}"
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }

run_hb() {
  local attempt=0 rc hung pid tailpid now
  while :; do
    attempt=$((attempt + 1)); hung=0; rc=0
    : > "$HB_OUT"; : > "$HB_ERR"
    "$@" >>"$HB_OUT" 2>>"$HB_ERR" & pid=$!
    tail -f "$HB_ERR" >&2 & tailpid=$!
    while kill -0 "$pid" 2>/dev/null; do
      sleep 5
      kill -0 "$pid" 2>/dev/null || break   # exited during sleep: not a hang
      now="$(date +%s)"
      if [ $((now - $(mtime "$HB_OUT"))) -ge "$HB_TIMEOUT" ] \
         && [ $((now - $(mtime "$HB_ERR"))) -ge "$HB_TIMEOUT" ]; then
        hung=1
        printf 'codex-reviewer: no heartbeat for %ss — killing codex (attempt %s/%s)\n' \
          "$HB_TIMEOUT" "$attempt" "$((HB_RESTARTS + 1))" >&2
        kill -TERM "$pid" 2>/dev/null || true
        sleep 5
        kill -KILL "$pid" 2>/dev/null || true
        break
      fi
    done
    wait "$pid" || rc=$?
    kill "$tailpid" 2>/dev/null || true; wait "$tailpid" 2>/dev/null || true
    if [ "$hung" -eq 1 ]; then
      if [ "$attempt" -le "$HB_RESTARTS" ]; then
        printf 'codex-reviewer: restarting codex...\n' >&2
        continue
      fi
      die "codex hung $attempt time(s) (no output for ${HB_TIMEOUT}s each) — giving up. Raise CODEX_REVIEW_HEARTBEAT if reviews legitimately run silent longer."
    fi
    cat "$HB_OUT"
    return "$rc"
  done
}
# ------------------------------------------------------------------------------

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
  ( cd "$CR_WT" && run_hb codex review "${RO[@]}" \
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
      run_hb codex review "${RO[@]}" -c "$(trust_here)" --base "$base" "$@"   # tip == HEAD → in place, no worktree
      exit $?
    fi
    review_in_worktree "$tip" "$base" "" "$@"                 # tip != HEAD → worktree
    ;;

  commit)
    need codex
    in_git_repo || die "not inside a git repository"
    sha="${1:-}"; [ -n "$sha" ] || die "usage: commit <sha>"; shift || true
    [ "${1:-}" = "--" ] && shift || true
    git rev-parse --verify --quiet "$sha^{commit}" >/dev/null || die "no such commit: $sha"
    run_hb codex review "${RO[@]}" -c "$(trust_here)" --commit "$sha" "$@"
    ;;

  uncommitted)
    need codex
    in_git_repo || die "not inside a git repository"
    [ "${1:-}" = "--" ] && shift || true
    run_hb codex review "${RO[@]}" -c "$(trust_here)" --uncommitted "$@"
    ;;

  files)
    need codex
    [ "$#" -ge 1 ] || die "usage: files <review prompt mentioning the file paths>"
    if in_git_repo; then EXTRA=(-c "$(trust_here)"); else EXTRA=(--skip-git-repo-check); fi
    CR_OUT="$(mktemp)"
    # transcript/progress → stderr (= the heartbeat); stdout carries ONLY Codex's
    # final review message (-o). Wrapped in a function so run_hb can watchdog it.
    FILES_PROMPT="$*"
    files_exec() { codex exec --sandbox read-only "${EXTRA[@]}" -o "$CR_OUT" "$FILES_PROMPT" 1>&2; }
    run_hb files_exec
    cat "$CR_OUT"
    ;;

  ""|-h|--help|help)
    sed -n '2,15p' "$0"; exit 0 ;;
  *)
    die "unknown subcommand '$cmd' (use: pr | range | commit | uncommitted | files)" ;;
esac
