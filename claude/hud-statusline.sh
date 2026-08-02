#!/usr/bin/env bash
# claude-hud statusline launcher.
#
# settings.json used to inline all of this as one unreadable `bash -c` string
# with an absolute bun path baked in, which broke on any other machine. Same
# behaviour, in a file, with bun resolved at runtime.
#
# Reads the statusline JSON on stdin and passes it straight through to
# claude-hud's bun entrypoint.

set -uo pipefail

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# claude-hud renders to the terminal width; leave 4 columns of margin.
cols="${COLUMNS:-}"
case "$cols" in
  ''|*[!0-9]*) cols="$(stty size </dev/tty 2>/dev/null | awk '{print $2}')" ;;
esac
case "$cols" in
  ''|*[!0-9]*) cols=120 ;;
esac
export COLUMNS=$(( cols > 4 ? cols - 4 : 1 ))

# Plugin cache holds one dir per installed version; take the highest semver.
newest_hud() {
  ls -d "$1"/plugins/cache/*/claude-hud/*/ 2>/dev/null \
    | awk -F/ '{ print $(NF-1) "\t" $0 }' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+[[:space:]]' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
    | tail -1 | cut -f2-
}

plugin_dir="$(newest_hud "$CONFIG_DIR")"

# Secondary profiles (~/.claude-glm) get their own plugin cache, which is empty
# until Claude has fetched into it once. Read the native home's copy meanwhile —
# read-only, so the two caches never fight.
[ -n "$plugin_dir" ] || plugin_dir="$(newest_hud "$HOME/.claude")"

if [ -z "$plugin_dir" ]; then
  printf 'claude-hud not installed (./install.sh --claude)'
  exit 0
fi

# bun is rarely on the PATH a statusline hook inherits.
bun_bin="$(command -v bun 2>/dev/null || true)"
for candidate in "$HOME/.bun/bin/bun" /opt/homebrew/bin/bun /usr/local/bin/bun; do
  [ -n "$bun_bin" ] && break
  [ -x "$candidate" ] && bun_bin="$candidate"
done

if [ -z "$bun_bin" ]; then
  printf 'bun missing — claude-hud cannot render'
  exit 0
fi

# --env-file /dev/null: the HUD must not pick up a project .env.
exec "$bun_bin" --env-file /dev/null "${plugin_dir}src/index.ts"
