#!/bin/sh
set -eu
r=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
c=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
x=${CODEX_HOME:-$HOME/.codex}
bak=$HOME/.agentfiles-backup/$(date +%Y%m%d-%H%M%S)
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"

for t in curl git jq unzip; do command -v $t >/dev/null || { echo "install $t first" >&2; exit 1; }; done
command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash
command -v codex >/dev/null || curl -fsSL https://chatgpt.com/codex/install.sh | sh
command -v bun >/dev/null || curl -fsSL https://bun.sh/install | bash
command -v rtk >/dev/null || curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh

link() {
  [ "$(readlink "$2")" = "$1" ] && return
  mkdir -p "$(dirname "$2")"
  if [ -L "$2" ]; then rm "$2"
  elif [ -e "$2" ]; then mkdir -p "$bak"; mv "$2" "$bak/$(echo "$2" | tr / _)"; fi
  ln -s "$1" "$2"
}
for f in CLAUDE.md RTK.md agents workflows output-styles hud-statusline.sh; do link "$r/claude/$f" "$c/$f"; done
link "$r/claude/hud.json" "$c/plugins/claude-hud/config.json"
link "$r/skills" "$c/skills"
link "$r/mcp" "$c/mcp"
link "$r/skills" "$HOME/.agents/skills"
link "$r/codex/AGENTS.md" "$x/AGENTS.md"
link "$r/bin/glm" "$HOME/.local/bin/glm"
find "$x/skills" -maxdepth 1 -type l -lname "$r/*" -exec rm {} + 2>/dev/null || true

s=$c/settings.json
o=$(for d in "$r"/skills/*/; do basename "$d"; done | jq -R '{(.): "user-invocable-only"}' | jq -s 'add // {}')
{ cat "$s" 2>/dev/null || echo '{}'; } | jq --slurpfile n "$r/claude/settings.json" --argjson o "$o" '
  def m($a; $b): if ($a|type) == "object" and ($b|type) == "object" then reduce ($b|keys[]) as $k ($a; .[$k] = m($a[$k]; $b[$k]))
    elif ($a|type) == "array" and ($b|type) == "array" then $a + ($b - $a) else $b end;
  m(.; $n[0]) | .skillOverrides = $o + (.skillOverrides // {})' > "$s.new"
if [ -L "$s" ] || ! cmp -s "$s.new" "$s"; then mv "$s.new" "$s"; else rm "$s.new"; fi

t=$x/config.toml
[ -e "$t" ] || : > "$t"
for kv in 'model_context_window = 1000000' 'model_auto_compact_token_limit = 200000'; do
  grep -q "^${kv%% *} *=" "$t" || { printf '%s\n' "$kv" | cat - "$t" > "$t.new"; mv "$t.new" "$t"; }
done
for f in "$r"/mcp/*.json; do
  n=$(basename "$f" .json)
  grep -q "^\[mcp_servers\.$n\]" "$t" || jq -r --arg n "$n" '.mcpServers[$n] | "\n[mcp_servers.\($n)]\n"
    + (if .url then "url = \(.url | tojson)\n" else "command = \(.command | tojson)\nargs = \(.args // [] | tojson)\n" end)
    + "enabled = false\n"
    + (if .env then "\n[mcp_servers.\($n).env]\n" + ([.env | to_entries[] | "\(.key) = \(.value | tojson)"] | join("\n")) + "\n" else "" end)' "$f" >> "$t"
done
chmod 600 "$t"

for m in JuliusBrussee/caveman jarrodwatts/claude-hud; do [ -d "$c/plugins/marketplaces/${m#*/}" ] || claude plugin marketplace add "$m" >/dev/null; done
for p in caveman@caveman claude-hud@claude-hud; do claude plugin install "$p" >/dev/null; done

case ${SHELL:-} in */zsh) rc=$HOME/.zshrc ;; */bash) rc=$HOME/.bashrc ;; *) rc=$HOME/.profile ;; esac
grep -qs agentfiles "$rc" || printf '\n# agentfiles\nexport PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"\n' >> "$rc"

echo "done: $(ls -d "$r"/skills/*/ | wc -l | tr -d ' ') skills and $(ls "$r"/mcp | wc -l | tr -d ' ') mcp servers, all off. open a new shell."
