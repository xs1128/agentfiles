#!/bin/sh
# Sets this config up on a mac or linux box: dependencies, then ~/.claude, then
# the plugins and MCP servers the manifests pin. No sudo.
# Usage: sh install.sh [--no-deps] [--no-bootstrap]
set -eu

repo="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
bin="$HOME/.local/bin"
deps=1
bootstrap=1
for arg in "$@"; do
  case "$arg" in
    --no-deps) deps=0 ;;
    --no-bootstrap) bootstrap=0 ;;
    *) echo "usage: install.sh [--no-deps] [--no-bootstrap]" >&2; exit 2 ;;
  esac
done

if [ ! -d "$repo/config" ]; then
  echo "install.sh: run this from a clone; it links config/ out of the repo." >&2
  echo "  git clone https://github.com/xs1128/agentfiles && sh agentfiles/install.sh" >&2
  exit 1
fi

# What no installer of ours can put there for free.
missing=''
for tool in node npm git jq; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  echo "install.sh: missing:$missing" >&2
  case "$(uname -s)" in
    Darwin) echo "  brew install$missing" >&2 ;;
    *)      echo "  sudo apt install$missing   (or your distro's equivalent)" >&2 ;;
  esac
  exit 1
fi

mkdir -p "$bin"

if [ "$deps" -eq 1 ]; then
  # A system node puts its global prefix somewhere only root can write, and this
  # install is meant to be sudo-free.
  if [ ! -w "$(npm root -g 2>/dev/null || echo /)" ]; then
    npm config set prefix "$HOME/.local"
    echo "npm global prefix moved to $HOME/.local (it was not writable)"
  fi

  if command -v claude >/dev/null 2>&1; then
    echo "claude already installed: $(command -v claude)"
  else
    npm install -g @anthropic-ai/claude-code
  fi

  # claude-hud's statusline runs under bun.
  if command -v bun >/dev/null 2>&1 || [ -x "$HOME/.bun/bin/bun" ]; then
    echo "bun already installed"
  else
    curl -fsSL https://bun.sh/install | bash
  fi

  if command -v rtk >/dev/null 2>&1 || [ -x "$bin/rtk" ]; then
    echo "rtk already installed"
  else
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh
  fi
fi

ln -sf "$repo/scripts/glm.sh" "$bin/claude-glm"
echo "installed $bin/claude-glm"

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
    echo 'for d in "$HOME/.local/bin" "$HOME/.bun/bin"; do'
    echo '  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac'
    echo 'done'
    echo 'export PATH'
  } >> "$rc"
  echo "wired $rc"
fi

# The steps below need what was just installed, which is not on this shell's PATH yet.
PATH="$bin:$HOME/.bun/bin:$PATH"
export PATH

sh "$repo/scripts/link.sh"

if [ "$bootstrap" -eq 1 ]; then
  sh "$repo/scripts/bootstrap.sh"
fi

echo
echo "done. run 'exec \$SHELL' or open a new terminal, then: claude"
echo "for z.ai's GLM instead: claude-glm   (needs ZAI_API_KEY, see .env.example)"
