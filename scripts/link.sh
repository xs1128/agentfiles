#!/bin/sh
# Points ~/.claude at claude/. What was there is moved aside, not deleted.
set -eu

repo="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
target="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
backup="$target/backups/link-$(date +%Y%m%d-%H%M%S)"

link() {
  dst="$target/$2"
  # -L first: a dangling symlink fails -e but still has to move.
  if [ -L "$dst" ] || [ -e "$dst" ]; then
    mkdir -p "$backup/$(dirname "$2")"
    mv "$dst" "$backup/$2"
  fi
  ln -s "$1" "$dst"
  echo "linked $2"
}

mkdir -p "$target"
for entry in CLAUDE.md RTK.md settings.json agents workflows mcp output-styles \
             hud-statusline.sh statusline.sh; do
  link "$repo/claude/$entry" "$entry"
done

# Outside claude/ because Codex loads the same directories.
link "$repo/skills" skills

# plugins/ is claude's own writable tree, so only link the file we own.
mkdir -p "$target/plugins/claude-hud"
link "$repo/claude/plugins/claude-hud/config.json" plugins/claude-hud/config.json

if [ -d "$backup" ]; then
  echo "previous entries moved to $backup"
fi
