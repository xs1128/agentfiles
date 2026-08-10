#!/usr/bin/env bash
# Every credential lives in one file outside the repo, mode 600.
# Repo templates reference ${VAR} names only.

SECRETS_FILE="${SECRETS_FILE:-$HOME/.config/agent-secrets.env}"

SECRET_VARS=(
  "ZAI_API_KEY:z.ai coding-plan key. Used by both the Claude GLM profile and pi's zai provider."
)

# Read one named key out of the secrets file without executing it.
# Accepted form: `[export ]KEY=value`, value optionally wrapped in one layer of
# matching ' or " quotes; the last line naming a key wins.
secret_value() {
  local file="$1" key="$2" line val=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line#export }"
    case "$line" in "$key"=*) val="${line#*=}" ;; *) continue ;; esac
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
  done < "$file"
  printf '%s' "$val"
}

# Write a skeleton on first run, then stop: filling it in is a human step.
scaffold_secrets() {
  step "Secrets"
  if [ -f "$SECRETS_FILE" ]; then
    ok "$SECRETS_FILE present"
  else
    if [ "$DRY_RUN" = "1" ]; then
      plan "create $SECRETS_FILE skeleton (chmod 600)"
    else
      mkdir -p "$(dirname "$SECRETS_FILE")"
      {
        echo "# Secrets for agent-config. NOT in git. Keep chmod 600."
        echo "# Fill in, then re-run install.sh."
        echo
        local entry
        for entry in "${SECRET_VARS[@]}"; do
          echo "# ${entry#*:}"
          echo "${entry%%:*}="
          echo
        done
      } > "$SECRETS_FILE"
      chmod 600 "$SECRETS_FILE"
      ok "created $SECRETS_FILE (chmod 600) — fill it in and re-run"
    fi
  fi

  # Never leave a world-readable secrets file.
  if [ -f "$SECRETS_FILE" ]; then
    local mode; mode="$(stat -f '%Lp' "$SECRETS_FILE" 2>/dev/null || stat -c '%a' "$SECRETS_FILE")"
    if [ "$mode" != "600" ]; then
      warn "$SECRETS_FILE is mode $mode; tightening to 600"
      run chmod 600 "$SECRETS_FILE"
    fi
    local entry var value
    for entry in "${SECRET_VARS[@]}"; do
      var="${entry%%:*}"
      value="$(secret_value "$SECRETS_FILE" "$var")"
      printf -v "$var" '%s' "$value"
      export "$var"
    done
  fi

  local entry var unset_count=0
  for entry in "${SECRET_VARS[@]}"; do
    var="${entry%%:*}"
    if [ -n "${!var:-}" ]; then ok "$var set"; else warn "$var unset — templates needing it will be skipped"; unset_count=$((unset_count+1)); fi
  done
  return 0
}
