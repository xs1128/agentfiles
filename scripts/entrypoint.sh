#!/bin/sh
# Claude writes to its config dir, and apptainer gives us a read-only rootfs and
# someone else's $HOME. So the image's config is a template: it is copied into a
# bound, writable state dir, and CLAUDE_CONFIG_DIR points there.
set -eu

img=/opt/agent-config
state="${AGENT_STATE:-/state}"

mkdir -p "$state"
if [ "$(cat "$state/.version" 2>/dev/null || true)" != "$(cat "$img/.version")" ]; then
  for entry in CLAUDE.md RTK.md settings.json agents skills workflows mcp profiles \
               hud-statusline.sh statusline.sh plugins; do
    rm -rf "$state/$entry"
    cp -a "$img/$entry" "$state/$entry"
  done
  cp "$img/.version" "$state/.version"
fi

export CLAUDE_CONFIG_DIR="$state"
exec claude "$@"
