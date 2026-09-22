#!/bin/bash
# The voice assistant's safety gate.
#
# henri.assistant runs Antigravity headless, where agy cannot prompt for
# permission itself. Henri has granted it `command(*)` in
# ~/.gemini/antigravity-cli/settings.json (deliberately not written by this
# repo -- handing another agent blanket shell access is his call to make, in
# his own file), so without a gate a misheard sentence would simply run.
#
# The gate is a pre-tool hook: agy calls `agent-guard` before every tool and a
# `deny` from it means the tool never runs. Read-only tools and read-only
# commands pass straight through; anything that could write, delete or change
# stops and waits for Henri to confirm it in the assistant card. Closing the
# card, or not answering within the guard's timeout, is a no.
#
# The hook is scoped to the voice session through HENRI_VOICE=1, which the
# plugin sets on the agy process. Sessions started by hand in a terminal keep
# agy's own interactive review and are left alone.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Voice assistant safety gate"

need_cmd agy "install antigravity-cli first (packages/packages.txt)"

root="$HOME/.gemini/antigravity-cli"
hooks="$root/hooks.json"

if [[ ! -d $root ]]; then
  warn "$(tilde "$root") does not exist yet — run agy once to log in, then re-run this"
  exit 0
fi

# The hook lives in the customization root, not in settings.json and not in a
# plugin: a plugins/<name>/hooks.json validates and imports cleanly but was not
# consulted at run time, while this path is.
run mkdir -p "$root"
# The absolute path is written out rather than "~/...": agy looks like it
# expands home in hook commands, but a gate is the wrong place to rely on
# something that has not been verified.
tmp="$(mktemp)"
cat > "$tmp" <<JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.local/bin/agent-guard"
          }
        ]
      }
    ]
  }
}
JSON
if [[ -f $hooks ]] && cmp -s "$tmp" "$hooks"; then
  skip "hook already installed"
  rm -f "$tmp"
else
  run cp "$tmp" "$hooks"
  rm -f "$tmp"
  info "wrote $(tilde "$hooks")"
fi

if ! grep -q '"allow"' "$root/settings.json" 2>/dev/null; then
  warn "no permissions.allow in $(tilde "$root/settings.json")"
  info "the assistant can only answer, not act, until you grant tools there"
fi
