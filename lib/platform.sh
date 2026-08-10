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

install_tui_dependencies() {
  command -v go >/dev/null 2>&1 && return 0

  local os manager
  os="$(detect_os)"
  manager="$(detect_package_manager)"
  printf 'Go is missing; installing it for %s via %s…\n' "$os" "$manager"

  case "$manager" in
    brew) brew install go ;;
    apt-get) _sudo apt-get update; _sudo apt-get install -y golang-go ;;
    dnf) _sudo dnf install -y golang ;;
    yum) _sudo yum install -y golang ;;
    pacman) _sudo pacman -Sy --noconfirm --needed go ;;
    zypper) _sudo zypper --non-interactive install go ;;
    apk) _sudo apk add go ;;
    pkg) _sudo pkg install -y go ;;
    winget.exe) winget.exe install --exact --id GoLang.Go --accept-package-agreements --accept-source-agreements ;;
    none)
      if [ "$os" = macos ]; then
        printf 'Homebrew is missing; installing it first…\n'
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
        brew install go
      else
        printf 'No supported package manager found. Install Go, then rerun ./setup.\n' >&2
        return 1
      fi
      ;;
    *) printf 'Unsupported platform: %s\n' "$os" >&2; return 1 ;;
  esac

  command -v go >/dev/null 2>&1 || {
    printf 'Go installed but is not yet on PATH; restart the shell and rerun ./setup.\n' >&2
    return 1
  }
}
