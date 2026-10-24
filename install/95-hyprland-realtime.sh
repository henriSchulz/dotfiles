#!/bin/bash
# Hyprland runs SCHED_RR when it holds CAP_SYS_NICE, so a busy app or build
# cannot stall input and frames on this 2-core machine. The pacman hook keeps
# the capability across hyprland updates. Takes effect on the next Hyprland
# start (log out and back in).
#
# Needs root: run `sudo ./install/95-hyprland-realtime.sh` or answer sudo's prompt.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Hyprland realtime scheduling"

run sudo install -Dm644 "$DOTFILES_ROOT/system/hyprland-realtime/hyprland-realtime.hook" /etc/pacman.d/hooks/hyprland-realtime.hook
run sudo setcap cap_sys_nice+ep /usr/bin/Hyprland
info "now: $(getcap /usr/bin/Hyprland)"
