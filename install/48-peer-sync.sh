#!/bin/bash
# Dotfiles sync with the other machine over the cable (dotfiles-peer-sync).
# The timer comes from a host stow package (hosts/m1/stow/peer-sync): only the
# M1 drives the sync, so on the tablet there is nothing to enable.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Dotfiles sync over the cable"

timer="$HOME/.config/systemd/user/dotfiles-peer-sync.timer"
[[ -e $timer ]] || { skip "no dotfiles-peer-sync.timer on $HOST"; exit 0; }
if systemctl --user is-enabled -q dotfiles-peer-sync.timer 2>/dev/null; then
  skip "dotfiles-peer-sync.timer already enabled"
else
  run systemctl --user daemon-reload
  run systemctl --user enable --now dotfiles-peer-sync.timer
fi
