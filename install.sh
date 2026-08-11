#!/bin/sh
# Puts the launcher on $PATH and wires the shell to find it.
# Usage: curl -fsSL .../install.sh | sh [-s -- --alias]
set -eu

RAW=https://raw.githubusercontent.com/xs1128/agentfiles/main/agent
bin="${AGENT_BIN_DIR:-$HOME/.local/bin}"
alias_claude=0
[ "${1:-}" = --alias ] && alias_claude=1

mkdir -p "$bin"
# Piped through sh, $0 is "sh" and there is no local copy to prefer.
here=''
[ -f "$0" ] && here="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
if [ -n "$here" ] && [ -f "$here/agent" ]; then
  cp "$here/agent" "$bin/agent"
else
  curl -fsSL -o "$bin/agent" "$RAW"
fi
chmod +x "$bin/agent"
echo "installed $bin/agent"

# Login shells read different files, and getting this wrong is the whole point of
# automating it.
case "$(basename "${SHELL:-/bin/sh}")" in
  zsh)  rc="$HOME/.zshrc" ;;
  bash) if [ -f "$HOME/.bash_profile" ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
  *)    rc="$HOME/.profile" ;;
esac

if [ -f "$rc" ] && grep -q '^# agentfiles$' "$rc"; then
  echo "$rc already wired"
else
  {
    echo ''
    echo '# agentfiles'
    echo 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac'
    echo 'export PATH'
    if [ "$alias_claude" -eq 1 ]; then echo "alias claude='agent'"; fi
  } >> "$rc"
  echo "wired $rc"
fi

if [ "$alias_claude" -eq 1 ] && command -v claude >/dev/null 2>&1; then
  echo "note: claude is already installed natively at $(command -v claude); the alias now shadows it in new shells"
fi

echo "run 'exec \$SHELL' or open a new terminal, then: agent"
