#!/bin/bash
# F6 (XF86Sleep) opens the Control Center (stow/hypr bindings.lua); logind
# must not also suspend on that key.
#
# Needs root: run `sudo ./install/98-sleep-key.sh` or answer sudo's prompt.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Sleep key ignored by logind"

run sudo install -Dm644 "$DOTFILES_ROOT/system/sleep-key/40-ignore-sleep-key.conf" /etc/systemd/logind.conf.d/40-ignore-sleep-key.conf
info "logind picks it up after: sudo systemctl kill -s HUP systemd-logind"
