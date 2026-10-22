#!/usr/bin/env bash
c=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
cols=${COLUMNS:-$(stty size </dev/tty 2>/dev/null | awk '{print $2}')}
case $cols in '' | *[!0-9]*) cols=120 ;; esac
export COLUMNS=$((cols > 4 ? cols - 4 : 1))
dir=$(ls -d "$c"/plugins/cache/*/claude-hud/*/ 2>/dev/null | sort -V | tail -1)
[ -n "$dir" ] || { printf 'claude-hud not installed'; exit 0; }
bun=$(command -v bun || echo "$HOME/.bun/bin/bun")
[ -x "$bun" ] || { printf 'bun missing'; exit 0; }
exec "$bun" --env-file /dev/null "${dir}src/index.ts"
