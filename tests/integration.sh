#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0

assert_contains() {
  case "$1" in *"$2"*) ;; *) printf 'expected output to contain: %s\n' "$2" >&2; exit 1 ;; esac
  PASS=$((PASS + 1))
}

assert_not_contains() {
  case "$1" in *"$2"*) printf 'expected output not to contain: %s\n' "$2" >&2; exit 1 ;; *) ;; esac
  PASS=$((PASS + 1))
}

test_component_selection() {
  local out
  out="$("$ROOT/install.sh" --codex --config --dry-run 2>&1)"
  assert_contains "$out" "Codex"
  assert_not_contains "$out" "Installing third-party skills"
  assert_not_contains "$out" "Registering MCP servers"
}

test_invalid_profile() {
  local out status=0
  out="$("$ROOT/install.sh" --codex --profile nonsense --dry-run 2>&1)" || status=$?
  [ "$status" -ne 0 ] || { printf 'invalid profile succeeded\n' >&2; exit 1; }
  assert_contains "$out" "invalid profile"
}

test_secret_file_is_data() {
  local tmp sentinel
  tmp="$(mktemp -d)"
  sentinel="$tmp/executed"
  SECRETS_FILE="$tmp/secrets.env"
  printf '%s\n' 'ZAI_API_KEY=test-value' "printf unsafe > '$sentinel'" > "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"

  REPO_ROOT="$ROOT"
  HOME="$tmp"
  DRY_RUN=0
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/secrets.sh"
  scaffold_secrets >/dev/null 2>&1

  [ ! -e "$sentinel" ] || { printf 'secret file executed shell code\n' >&2; exit 1; }
  [ "${ZAI_API_KEY:-}" = test-value ] || { printf 'secret was not exported\n' >&2; exit 1; }
  PASS=$((PASS + 2))
}

test_platform_detection() {
  REPO_ROOT="$ROOT"
  . "$ROOT/lib/platform.sh"
  local os
  os="$(detect_os)"
  case "$os" in macos|linux|windows) ;; *) printf 'unsupported detected OS: %s\n' "$os" >&2; exit 1 ;; esac
  PASS=$((PASS + 1))
}

test_component_selection
test_invalid_profile
test_secret_file_is_data
test_platform_detection
printf '%s integration assertions passed\n' "$PASS"
