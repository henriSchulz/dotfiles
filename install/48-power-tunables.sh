#!/bin/bash
# Power tunables that need root: runtime PM for the on-package PCI devices
# (udev) and two sysctls. Both files ship under etc/ in this repo. They are
# permanent, trade-off-free settings — the ones with a visible cost (Wi-Fi
# power save, audio codec timeout) deliberately stay out, and the rendering
# switch lives in henri.control-center-v2 → Experiments instead.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Power tunables (udev + sysctl)"
need_cmd sudo
for rel in udev/rules.d/60-henri-runtime-pm.rules sysctl.d/60-henri-power.conf; do
  src="$DOTFILES_ROOT/etc/$rel" dst="/etc/$rel"
  if [[ -f $dst ]] && cmp -s "$src" "$dst"; then
    skip "$dst"
  else
    info "installing $dst"
    run sudo install -D -m 644 "$src" "$dst"
  fi
done
info "applying now"
run sudo udevadm control --reload
run sudo udevadm trigger --subsystem-match=pci --action=add
run sudo sysctl -q --system
