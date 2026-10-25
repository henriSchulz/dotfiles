#!/bin/bash
# Dotfiles sync with the other machine over the cable (dotfiles-peer-sync), and the
# sync status for the menu bar (sync-status).
# The timer comes from a host stow package (hosts/m1/stow/peer-sync): only the
# M1 drives the sync, so on the tablet there is nothing to enable.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Dotfiles sync over the cable"

# sync-status.timer (hosts/m1/stow/sync-status) feeds the Sync group of henri.cast-v3.
for t in dotfiles-peer-sync sync-status; do
  if [[ ! -e $HOME/.config/systemd/user/$t.timer ]]; then
    skip "no $t.timer on $HOST"
  elif systemctl --user is-enabled -q "$t.timer" 2>/dev/null; then
    skip "$t.timer already enabled"
  else
    run systemctl --user daemon-reload
    run systemctl --user enable --now "$t.timer"
  fi
done
