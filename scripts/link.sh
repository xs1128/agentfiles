#!/bin/sh
# Points ~/.claude at config/. Whatever was there first is moved aside, not deleted.
set -eu

repo="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
target="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
backup="$target/backups/link-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$target"
for entry in CLAUDE.md RTK.md settings.json agents skills workflows mcp \
             hud-statusline.sh statusline.sh; do
  dst="$target/$entry"
  # -L first: a dangling symlink fails -e but still has to be moved.
  if [ -L "$dst" ] || [ -e "$dst" ]; then
    mkdir -p "$backup"
    mv "$dst" "$backup/$entry"
  fi
  ln -s "$repo/config/$entry" "$dst"
  echo "linked $entry"
done

# plugins/ is claude's own writable tree, so only the file we own is linked into it.
mkdir -p "$target/plugins/claude-hud"
dst="$target/plugins/claude-hud/config.json"
if [ -L "$dst" ] || [ -e "$dst" ]; then
  mkdir -p "$backup"
  mv "$dst" "$backup/claude-hud-config.json"
fi
ln -s "$repo/config/plugins/claude-hud/config.json" "$dst"
echo "linked plugins/claude-hud/config.json"

if [ -d "$backup" ]; then
  echo "previous entries moved to $backup"
fi
