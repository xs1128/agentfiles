#!/bin/sh
# Points ~/.codex at codex/ and skills/. What was there is moved aside,
# not deleted. Safe to rerun.
set -eu

repo="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
target="${CODEX_HOME:-$HOME/.codex}"
backup="$target/backups/link-$(date +%Y%m%d-%H%M%S)"
manifest="$target/skills/.agentfiles-managed"

mkdir -p "$target/skills"

# rtk. AGENTS.md is Codex's ~/.claude/CLAUDE.md. No @-includes and no
# PreToolUse hook, so RTK.md is inlined and the prefix is an instruction.
dst="$target/AGENTS.md"
# -L first: a dangling symlink fails -e but still has to move.
if [ -L "$dst" ] || [ -e "$dst" ]; then
  mkdir -p "$backup"
  mv "$dst" "$backup/AGENTS.md"
fi
ln -s "$repo/codex/AGENTS.md" "$dst"
echo "linked AGENTS.md"

# Skills. The same directories Claude loads; discovery is $CODEX_HOME/skills.
# Prune our manifest and the name an earlier version of the repo used, or the
# skills it linked and no longer ships stay behind as dead symlinks.
for old in "$manifest" "$target/skills/.agent-config-managed-skills"; do
  [ -f "$old" ] || continue
  while read -r skill; do
    [ -n "$skill" ] || continue
    entry="$target/skills/$skill"
    # Only ever unlink. A real directory there is the user's, not ours.
    [ -L "$entry" ] && rm -f "$entry"
  done < "$old"
  rm -f "$old"
done

linked=0
for src in "$repo"/skills/*/; do
  [ -d "$src" ] || continue
  name="$(basename "$src")"
  dst="$target/skills/$name"
  if [ -L "$dst" ]; then
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    mkdir -p "$backup/skills"
    mv "$dst" "$backup/skills/$name"
  fi
  ln -s "${src%/}" "$dst"
  echo "$name" >> "$manifest"
  linked=$((linked + 1))
done
echo "linked $linked skills into $target/skills"

# Plugins. Codex writes config.toml during sessions, so the enables are appended
# rather than linked. Append-only, and only for a [plugins."..."] header the file
# does not already have: nothing here can rewrite a key Codex or you set, and a
# plugin turned off by hand stays off. Parsing the file would risk more than it
# buys, so this is grep, not TOML.
config="$target/config.toml"
tmpl="$repo/codex/plugins.toml.tmpl"

missing="$(awk -v cfg="$config" '
  BEGIN { while ((getline line < cfg) > 0) seen[line] = 1; close(cfg) }
  /^\[/ { skip = seen[$0]; if (!skip) printf "\n%s\n", $0; next }
  skip || /^#/ || !NF { next }
  { print }
' "$tmpl")"

if [ -n "$missing" ]; then
  if [ -f "$config" ]; then
    mkdir -p "$backup"
    cp "$config" "$backup/config.toml"
    # A file not ending in a newline would swallow the first header.
    [ -n "$(tail -c 1 "$config")" ] && echo '' >> "$config"
  fi
  printf '%s\n' "$missing" >> "$config"
  echo "added $(printf '%s\n' "$missing" | grep -c '^\[') plugin enables to config.toml"
else
  echo "config.toml already has every plugin enable"
fi

if [ -d "$backup" ]; then
  echo "previous entries moved to $backup"
fi
