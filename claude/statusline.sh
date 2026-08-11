#!/usr/bin/env bash
# FALLBACK ONLY: not wired by default. settings.json points statusLine at
# hud-statusline.sh (the claude-hud plugin). This is the pure-bash/jq version,
# kept for machines where bun or the plugin is unavailable; to use it, swap the
# statusLine command in claude/settings.json to
#   bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh"
#
# Native Claude statusline: caveman badge + official subscription usage.
# Uses the v2.1.x statusline JSON (.rate_limits / .context_window): the same
# numbers the app's /usage shows. rate_limits is only present on a SUBSCRIPTION
# login (not API billing) and only after the first API response of the session.
input=$(cat)

cm=$(bash "$HOME/.claude/plugins/marketplaces/caveman/hooks/caveman-statusline.sh" 2>/dev/null)

if ! command -v jq >/dev/null 2>&1; then
  printf '%s claude' "$cm"; exit 0
fi

j() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }

model=$(j '.model.display_name'); model=${model:-claude}
dir=$(j '.workspace.current_dir'); dir=${dir:-$(j '.cwd')}; dir=${dir:-.}
case "$dir" in "$HOME") dir="~" ;; "$HOME"/*) dir="~${dir#"$HOME"}" ;; esac

cost=$(j '.cost.total_cost_usd'); cost=${cost:-0}
rl5=$(j '.rate_limits.five_hour.used_percentage')
rl5r=$(j '.rate_limits.five_hour.resets_at')
rl7=$(j '.rate_limits.seven_day.used_percentage')
rl7r=$(j '.rate_limits.seven_day.resets_at')
ctx=$(j '.context_window.used_percentage')

# colour by severity: <50 green(71), <80 yellow(220), else red(203)
pcol() { if   [ "$1" -ge 80 ]; then printf 203; elif [ "$1" -ge 50 ]; then printf 220; else printf 71; fi; }
rem() { s=$(( $1 - $(date +%s) )); [ "$s" -lt 0 ] && s=0; d=$((s/86400)); h=$(((s%86400)/3600)); m=$(((s%3600)/60)); if [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"; elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"; else printf '%dm' "$m"; fi; }

C='\033[38;5;240m│\033[0m'   # dim separator
out=$(printf '%s \033[1m%s\033[0m %b %s' "$cm" "$model" "$C" "$dir")

# --- 5-hour limit (the headline) ---
if [ -n "$rl5" ]; then
  p=$(printf '%.0f' "$rl5"); col=$(pcol "$p")
  seg=$(printf '\033[38;5;%sm5h %s%%\033[0m' "$col" "$p")
  [ -n "$rl5r" ] && seg="$seg$(printf ' \033[38;5;240m⟳%s\033[0m' "$(rem "$rl5r")")"
  out="$out $(printf '%b' "$C") $seg"
else
  out="$out $(printf '%b' "$C") $(printf '\033[38;5;240m5h ·\033[0m')"
fi

# --- 7-day limit (if present) ---
if [ -n "$rl7" ]; then
  p=$(printf '%.0f' "$rl7"); col=$(pcol "$p")
  seg=$(printf '\033[38;5;%sm7d %s%%\033[0m' "$col" "$p")
  [ -n "$rl7r" ] && seg="$seg$(printf ' \033[38;5;240m⟳%s\033[0m' "$(rem "$rl7r")")"
  out="$out $(printf '%b' "$C") $seg"
fi

# --- context window ---
if [ -n "$ctx" ]; then
  p=$(printf '%.0f' "$ctx"); col=$(pcol "$p")
  out="$out $(printf '%b' "$C") $(printf '\033[38;5;%smctx %s%%\033[0m' "$col" "$p")"
fi

# --- session cost ---
out="$out $(printf '%b' "$C") $(printf '\033[38;5;220m$%.4f\033[0m' "$cost")"

printf '%b' "$out"
