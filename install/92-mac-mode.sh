#!/bin/bash
# Poll the mt-bridge Mac's server/desktop mode into a local status file, so
# the henri.control-center plugin's Mac Mode tile never shells out at panel-
# open time.
#
#   script   ~/.local/bin/mac-mode-poll — stowed by 20-stow.sh
#   timer    mac-mode-poll.timer, every 15s — enabled here
#   Mac side mac-mode script + LaunchAgent — lives in the private mt-bridge
#            repo, not here; the timer just logs SSH failures until it's
#            installed there
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Mac mode poll"

info "enabling mac-mode-poll.timer"
run systemctl --user enable --now mac-mode-poll.timer
