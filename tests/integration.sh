#!/usr/bin/env bash
# Each test runs in its own subshell: several of them set HOME, DRY_RUN or
# source lib/, and that must not leak into the next one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  case "$1" in *"$2"*) ;; *) printf 'expected output to contain: %s\n' "$2" >&2; exit 1 ;; esac
}

assert_not_contains() {
  case "$1" in *"$2"*) printf 'expected output not to contain: %s\n' "$2" >&2; exit 1 ;; *) ;; esac
}

# A PATH holding only the binaries a case wants the dep check to find.
stub_path() {
  local bin name; bin="$(mktemp -d)"
  for name in "$@"; do printf '#!/usr/bin/env bash\nexit 0\n' > "$bin/$name"; chmod +x "$bin/$name"; done
  printf '%s' "$bin"
}

test_component_selection() {
  local out
  out="$(PATH="$(stub_path codex jq rtk):$PATH" "$ROOT/install.sh" --codex --config --dry-run 2>&1)"
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
  tmp="$(mktemp -d)"; sentinel="$tmp/executed"
  SECRETS_FILE="$tmp/secrets.env"
  printf '%s\n' 'ZAI_API_KEY=test-value' "printf unsafe > '$sentinel'" > "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"

  REPO_ROOT="$ROOT"; HOME="$tmp"; DRY_RUN=0
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/secrets.sh"
  scaffold_secrets >/dev/null 2>&1

  [ ! -e "$sentinel" ] || { printf 'secret file executed shell code\n' >&2; exit 1; }
  [ "${ZAI_API_KEY:-}" = test-value ] || { printf 'secret was not exported\n' >&2; exit 1; }
}

# A file that never names the key must leave an env-supplied one alone,
# install.sh reads an empty key as revoked and deletes the rendered credential.
test_env_secret_survives() {
  local tmp
  tmp="$(mktemp -d)"
  SECRETS_FILE="$tmp/secrets.env"
  printf 'OTHER=1\n' > "$SECRETS_FILE"; chmod 600 "$SECRETS_FILE"

  REPO_ROOT="$ROOT"; HOME="$tmp"; DRY_RUN=0
  . "$ROOT/lib/common.sh"
  . "$ROOT/lib/secrets.sh"
  export ZAI_API_KEY=from-env
  scaffold_secrets >/dev/null 2>&1
  [ "$ZAI_API_KEY" = from-env ] || { printf 'env secret was clobbered\n' >&2; exit 1; }
}

test_platform_detection() {
  REPO_ROOT="$ROOT"
  . "$ROOT/lib/platform.sh"
  case "$(detect_os)" in
    macos|linux|windows|freebsd) ;;
    *) printf 'unsupported detected OS: %s\n' "$(detect_os)" >&2; exit 1 ;;
  esac
}

test_manual_skill_is_preserved() {
  local home out
  home="$(mktemp -d)"
  mkdir -p "$home/.codex/skills/manual"
  out="$(HOME="$home" PATH="$(stub_path codex jq rtk):$PATH" "$ROOT/install.sh" --codex --skills --dry-run 2>&1)"
  assert_not_contains "$out" "skills/manual"
}

# --install-deps is install-only; doctor must not read it as "check nothing".
test_doctor_ignores_install_only_flag() {
  local out
  out="$("$ROOT/doctor.sh" --claude --install-deps 2>&1 || true)"
  assert_contains "$out" "Claude Code"
}

for t in test_component_selection test_invalid_profile test_secret_file_is_data \
         test_env_secret_survives test_platform_detection \
         test_manual_skill_is_preserved test_doctor_ignores_install_only_flag; do
  ( "$t" ) || { printf 'FAIL %s\n' "$t" >&2; exit 1; }
  printf 'ok %s\n' "$t"
done
