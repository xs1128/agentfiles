#!/bin/sh
# Sets this config up on mac or linux. Skills and plugins only; MCP needs --mcp.
# Usage: sh install.sh [--no-deps] [--no-bootstrap] [--no-codex] [--mcp]
set -eu

repo="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
bin="$HOME/.local/bin"
deps=1
bootstrap=1
codex=1
mcp=0
for arg in "$@"; do
  case "$arg" in
    --no-deps) deps=0 ;;
    --no-bootstrap) bootstrap=0 ;;
    --no-codex) codex=0 ;;
    --mcp) mcp=1 ;;
    *) echo "usage: install.sh [--no-deps] [--no-bootstrap] [--no-codex] [--mcp]" >&2; exit 2 ;;
  esac
done

if [ ! -d "$repo/claude" ]; then
  echo "install.sh: run this from a clone; it links claude/ out of the repo." >&2
  echo "  git clone git@github.com:xs1128/agentfiles.git ~/.agentfiles && sh ~/.agentfiles/install.sh" >&2
  exit 1
fi

# node only matters for the MCP servers, which are npm packages.
required="curl git jq"
if [ "$mcp" -eq 1 ]; then required="$required node npm"; fi
missing=''
for tool in $required; do
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

# Before the installs: what they drop here must run in this same shell.
PATH="$bin:$HOME/.bun/bin:$PATH"
export PATH

if [ "$deps" -eq 1 ]; then
  if command -v claude >/dev/null 2>&1; then
    claude update || echo "claude update failed; continuing"
  else
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  echo "claude: $(claude --version 2>/dev/null || echo 'not on PATH yet')"

  if [ "$codex" -eq 1 ]; then
    if command -v codex >/dev/null 2>&1; then
      codex update || echo "codex update failed; continuing"
    else
      curl -fsSL https://chatgpt.com/codex/install.sh | sh
    fi
    echo "codex: $(codex --version 2>/dev/null || echo 'not on PATH yet')"
  fi

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

rm -f "$bin/claude-glm"
ln -sf "$repo/scripts/glm.sh" "$bin/glm"
echo "installed $bin/glm"

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

sh "$repo/scripts/link.sh"
if [ "$codex" -eq 1 ]; then
  sh "$repo/scripts/link-codex.sh"
fi

if [ "$bootstrap" -eq 1 ]; then
  if [ "$mcp" -eq 1 ]; then
    sh "$repo/scripts/bootstrap.sh" --mcp
  else
    sh "$repo/scripts/bootstrap.sh"
  fi
fi

echo
echo "done. run 'exec \$SHELL' or open a new terminal, then: claude"
if [ "$codex" -eq 1 ]; then
  echo "or, for the same skills under OpenAI's harness: codex"
fi
echo "for z.ai's GLM instead: glm   (needs ZAI_API_KEY, see .env.example)"
if [ "$mcp" -eq 0 ]; then
  echo "no MCP servers installed; add them with: sh scripts/bootstrap.sh --mcp"
fi
