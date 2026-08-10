#!/usr/bin/env bash
# OS and package-manager adapter used by setup.

detect_os() {
  [ -n "${AGENT_CONFIG_OS:-}" ] && { printf '%s\n' "$AGENT_CONFIG_OS"; return; }
  case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin) printf 'macos\n' ;;
    Linux) printf 'linux\n' ;;
    FreeBSD) printf 'freebsd\n' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows\n' ;;
    *) printf 'unsupported\n' ;;
  esac
}

detect_package_manager() {
  local name
  for name in brew apt-get dnf yum pacman zypper apk pkg winget.exe; do
    command -v "$name" >/dev/null 2>&1 && { printf '%s\n' "$name"; return; }
  done
  printf 'none\n'
}

_sudo() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
}

# Ask before the implicit path touches the system; --install-deps is consent
# already given, so it does not come through here.
confirm() {
  [ "${ASSUME_YES:-0}" = 1 ] && return 0
  [ -t 0 ] || return 1
  local reply; printf '%s [y/N] ' "$1"; read -r reply
  case "$reply" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

install_tui_dependencies() {
  command -v go >/dev/null 2>&1 && return 0
  confirm "Install Go? This may use sudo or an upstream install script." || {
    printf 'Skipped. Install Go yourself, or rerun with ASSUME_YES=1.\n' >&2
    return 1
  }
  platform_install_tool go
}

platform_install_tool() {
  local tool="$1" os manager package="$1"
  os="$(detect_os)"; manager="$(detect_package_manager)"
  printf 'Installing %s for %s…\n' "$tool" "$os"

  case "$tool" in
    claude|codex|pi)
      command -v npm >/dev/null 2>&1 || platform_install_tool node
      case "$tool" in
        claude) npm install -g @anthropic-ai/claude-code ;;
        codex) npm install -g @openai/codex ;;
        pi) npm install -g @mariozechner/pi-coding-agent ;;
      esac
      return ;;
    rtk)
      if [ "$os" = windows ]; then
        powershell.exe -NoProfile -Command '$d="$HOME\.local\bin"; New-Item -ItemType Directory -Force $d | Out-Null; $z="$env:TEMP\rtk.zip"; Invoke-WebRequest https://github.com/rtk-ai/rtk/releases/latest/download/rtk-x86_64-pc-windows-msvc.zip -OutFile $z; Expand-Archive -Force $z $d'
      else
        curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh
      fi
      return ;;
    bun)
      if [ "$os" = windows ]; then powershell.exe -NoProfile -Command 'irm bun.sh/install.ps1 | iex'; else curl -fsSL https://bun.sh/install | bash; fi
      return ;;
    python3) package=python3 ;;
    node) package=nodejs ;;
  esac

  case "$manager:$tool" in
    apt-get:go) package=golang-go ;;
    dnf:go|yum:go) package=golang ;;
    apt-get:node) _sudo apt-get update; _sudo apt-get install -y nodejs npm; return ;;
    apk:node) _sudo apk add nodejs npm; return ;;
    pacman:node) _sudo pacman -Sy --noconfirm --needed nodejs npm; return ;;
    brew:python3) package=python ;;
  esac

  case "$manager" in
    brew) brew install "$package" ;;
    apt-get) _sudo apt-get update; _sudo apt-get install -y "$package" ;;
    dnf|yum) _sudo "$manager" install -y "$package" ;;
    pacman) _sudo pacman -Sy --noconfirm --needed "$package" ;;
    zypper) _sudo zypper --non-interactive install "$package" ;;
    apk) _sudo apk add "$package" ;;
    pkg) _sudo pkg install -y "$package" ;;
    winget.exe)
      case "$tool" in go) package=GoLang.Go;; git) package=Git.Git;; python3) package=Python.Python.3.13;; node) package=OpenJS.NodeJS.LTS;; jq) package=jqlang.jq;; esac
      winget.exe install --exact --id "$package" --accept-package-agreements --accept-source-agreements ;;
    none)
      if [ "$os" = macos ]; then
        printf 'Homebrew is missing; installing it first…\n'
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
        brew install "$package"
      else
        printf 'No supported package manager found. Install Go, then rerun ./setup.\n' >&2
        return 1
      fi
      ;;
    *) printf 'Unsupported platform: %s\n' "$os" >&2; return 1 ;;
  esac

  command -v "$tool" >/dev/null 2>&1 || printf '%s installed but is not yet on PATH; restart the shell.\n' "$tool" >&2
}
