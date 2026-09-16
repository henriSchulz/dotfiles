#!/bin/bash
# Restore shell.json — the bar layout, plugin enablement and idle timers.
#
# It carries:
#
#   - henri.bar as the active bar: henri.workspaces on the left, status icons
#     and the clock (24h, no weather) on the right
#   - henri.menu enabled as a plugin, not a bar widget — a menu+widget plugin
#     is only loaded while it is on the bar or listed under `plugins`
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

# A full restart, not `omarchy-shell shell rescanPlugins`. shell.json itself
# hot-reloads, but step 30 copies QML plugins in, and QML under
# ~/.config/omarchy/plugins/ does not reload without a restart — neither a
# rescan nor a setPluginEnabled toggle picks it up, whatever the shell README
# says. Skipping this leaves the bar running the code it started with.
if have omarchy-restart-shell; then
  info "restarting the shell"
  run omarchy-restart-shell || warn "restart failed (locked session?) — run 'omarchy restart shell' after unlocking"
else
  info "no shell on PATH — the bar comes up on next login"
fi
