#!/bin/bash
# Signing in the Papers fork (~/Projects/papers, branch henri) reads absolute finger positions from the
# trackpad through evdev. This rule gives the logged-in user access to touchpads only (uaccess = seat ACL);
# keyboards and mice stay root/input. Needs root, once. Without it Papers falls back to drawing with the
# button held down.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Trackpad access for signing in Papers"

run sudo install -Dm644 "$DOTFILES_ROOT/system/trackpad-uaccess/70-trackpad-uaccess.rules" /etc/udev/rules.d/70-trackpad-uaccess.rules
run sudo udevadm control --reload
run sudo udevadm trigger --subsystem-match=input --action=change
