#!/bin/bash
# Restore shell.json — the bar layout, plugin enablement and idle timers.
#
# This runs LAST, and that ordering is the whole point of the step existing.
# `shibumi-suite install` (step 60) rewrites shell.json to the suite's own
# default layout, which would otherwise discard everything this file carries:
#
#   - the v2Layout slot assignment (henri.menu sitting in the left group,
#     omasettings/omaplug/activity-monitor in the center)
#   - the widgets that are switched off (G7, G14, G15) and the units on G16
#   - presentation: accent color01, large radius, borders on, frost off
#   - idle timers: screensaver after 150s, lock after 300s
#   - omarchy.menu / omarchy.lock / omarchy.idle disabled in favour of
#     henri.menu, lock-explorer and henri.idle
#
# Copied, never symlinked: the shell rewrites this file whenever the bar is
# edited, and a stow symlink here breaks that write.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Omarchy shell state"

src="$DOTFILES_ROOT/omarchy/shell.json"
dest="$HOME/.config/omarchy/shell.json"
[[ -f $src ]] || die "missing in repo: omarchy/shell.json"

if [[ -f $dest ]] && cmp -s "$src" "$dest"; then
  skip "shell.json already matches the repo"
else
  if [[ -f $dest ]]; then
    bak="$dest.pre-dotfiles.$(date +%s)"
    info "backing up existing shell.json -> $(basename "$bak")"
    run cp "$dest" "$bak"
  fi
  info "installing shell.json"
  run install -m 600 "$src" "$dest"
fi

# The shell hot-reloads shell.json, but plugins that were only just copied in
# need a rescan before the bar can reference them.
if have omarchy-shell; then
  info "reloading the shell"
  run omarchy-shell shell rescanPlugins || warn "rescan failed — run 'omarchy restart shell' by hand"
else
  info "no running shell — the bar comes up on next login"
fi
