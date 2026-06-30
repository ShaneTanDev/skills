#!/usr/bin/env bash
# Install skills from this monorepo to every AI agent that supports skills.
#   ./install.sh              install all skills (every top-level dir with a SKILL.md)
#   ./install.sh goal-doc ... install only the named skill(s)
# A skill installs into each agent root whose parent dir already exists; the rest are skipped.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AGENT_ROOTS=(
  "$HOME/.claude/skills"
  "$HOME/.codex/skills"
  "$HOME/.agents/skills"
  "$HOME/.gemini/antigravity/skills"
)

list_skills() {
  for d in "$DIR"/*/; do
    [ -f "${d}SKILL.md" ] && basename "$d"
  done
}

install_one() {
  local name="$1" src="$DIR/$name"
  [ -f "$src/SKILL.md" ] || { echo "    ✗ $name: no SKILL.md, skipping"; return; }
  for root in "${AGENT_ROOTS[@]}"; do
    [ -d "$root" ] || continue
    local dest="$root/$name"
    mkdir -p "$dest"
    cp -r "$src/." "$dest/"
    rm -f "$dest/README.md" "$dest/DESIGN.md"   # ponytail: repo docs, not skill content
    chmod +x "$dest"/*.sh 2>/dev/null || true
    echo "    ✓ $name → $(echo "$root" | sed "s|$HOME|~|")"
  done
}

echo "==> Installing skills to AI agents..."
if [ "$#" -gt 0 ]; then
  for name in "$@"; do install_one "$name"; done
else
  while IFS= read -r name; do install_one "$name"; done < <(list_skills)
fi
echo "==> Done."
