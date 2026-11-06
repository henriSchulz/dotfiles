#!/bin/bash
# The Safari screen mirror over the cable stays OFF, for good (Henri, 2026-11-06: "dauerhaft deaktivieren",
# asked of several agents before; it kept coming back). The iPad is the Mac's screen through ipad-cast
# (~/Projects/ipad-cast: jailbroken iPad, ipadcastd + ipad-link.service), not through Safari.
#
# Why it came back: 90-ipadcast-usb.rules starts ipadcast-usb.service from udev (SYSTEMD_WANTS) on every
# iPad/iPhone plug-in; the unit is static, so `systemctl disable` did nothing. Off means: no udev rule,
# both units masked. system/ipadcast-usb/ keeps the files for reference only — this script never installs them.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "ipadcast over USB-C (Safari mirror): kept off"

run sudo rm -f /etc/udev/rules.d/90-ipadcast-usb.rules
for u in ipadcast-usb.service ipadcast-usb-kick.service; do
  # a real unit file in /etc/systemd/system blocks the mask symlink: move it aside first
  if [[ -f /etc/systemd/system/$u && ! -L /etc/systemd/system/$u ]]; then
    run sudo install -d /var/lib/ipadcast-usb/off
    run sudo mv "/etc/systemd/system/$u" "/var/lib/ipadcast-usb/off/$u"
  fi
done
run sudo systemctl daemon-reload
run sudo systemctl mask ipadcast-usb.service ipadcast-usb-kick.service
run sudo udevadm control --reload
info "Safari mirror off: no udev rule, ipadcast-usb(.service|-kick.service) masked"
