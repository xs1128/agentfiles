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

# Config. Codex writes config.toml during sessions, so our top-level settings
# and plugin enables are merged rather than linked. Nothing already set is
# rewritten.
config="$target/config.toml"
settings="$repo/codex/config.toml.tmpl"
tmpl="$repo/codex/plugins.toml.tmpl"
config_existed=0
[ -f "$config" ] && config_existed=1 || : > "$config"
config_backed_up=0

backup_config() {
  if [ "$config_existed" -eq 1 ] && [ "$config_backed_up" -eq 0 ]; then
    mkdir -p "$backup"
    cp "$config" "$backup/config.toml"
    config_backed_up=1
  fi
}

missing_settings="$(awk -v cfg="$config" '
  BEGIN {
    while ((getline line < cfg) > 0) {
      if (line ~ /^\[/) break
      key = line
      sub(/[[:space:]]*=.*/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != line) seen[key] = 1
    }
    close(cfg)
  }
  /^[[:space:]]*#/ || !NF { next }
  {
    key = $0
    sub(/[[:space:]]*=.*/, "", key)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
    if (!seen[key]) print
  }
' "$settings")"

if [ -n "$missing_settings" ]; then
  backup_config
  tmp="$(mktemp "$target/.config.toml.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  printf '%s\n' "$missing_settings" | awk '
    FILENAME == "-" { additions[++count] = $0; next }
    !added && /^\[/ {
      for (i = 1; i <= count; i++) print additions[i]
      print ""
      added = 1
    }
    { print }
    END {
      if (!added) {
        if (NR) print ""
        for (i = 1; i <= count; i++) print additions[i]
      }
    }
  ' - "$config" > "$tmp"
  mv "$tmp" "$config"
  trap - EXIT HUP INT TERM
  echo "added missing context settings to config.toml"
fi

missing="$(awk -v cfg="$config" '
  BEGIN { while ((getline line < cfg) > 0) seen[line] = 1; close(cfg) }
  /^\[/ { skip = seen[$0]; if (!skip) printf "\n%s\n", $0; next }
  skip || /^#/ || !NF { next }
  { print }
' "$tmpl")"

if [ -n "$missing" ]; then
  backup_config
  # A file not ending in a newline would swallow the first header.
  [ -n "$(tail -c 1 "$config")" ] && echo '' >> "$config"
  printf '%s\n' "$missing" >> "$config"
  echo "added $(printf '%s\n' "$missing" | grep -c '^\[') plugin enables to config.toml"
else
  echo "config.toml already has every plugin enable"
fi

if [ -d "$backup" ]; then
  echo "previous entries moved to $backup"
fi
