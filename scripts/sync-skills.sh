#!/bin/sh
# Recopies vendored skills from the commits manifests/skills.json pins, so an
# upstream change arrives as a reviewable diff rather than silently.
set -eu

repo="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
manifest="$repo/manifests/skills.json"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

jq -r '.sources | to_entries[] | select(.value.commit) | "\(.value.repo) \(.value.commit)"' "$manifest" |
  while read -r url commit; do
    clone="$work/$(basename "$url")"
    git clone -q "$url" "$clone"
    git -C "$clone" checkout -q "$commit"

    jq -r --arg url "$url" \
      '.sources | to_entries[] | select(.value.repo == $url) | .value.skills[]' "$manifest" |
      while read -r skill; do
        src="$(find "$clone" -type d -name "$skill" | head -1)"
        [ -n "$src" ] || { echo "missing upstream: $skill" >&2; continue; }
        rm -rf "$repo/config/skills/$skill"
        cp -R "$src" "$repo/config/skills/$skill"
      done
  done

echo "done; review with: git -C $repo diff --stat config/skills"
