#!/bin/bash
# The cable as the way to the screen mirror: an iPad/iPhone on USB starts the tunnel and ipadcast.service
# (system/ipadcast-usb: ipadcast-usb, ipadcast-usb.service, 90-ipadcast-usb.rules). Needs root, once.
#
# Prerequisites: the usbmuxd package (pairing; the "Trust this computer" tap on the device happened before,
# the records are in /var/lib/lockdown) and the pymobiledevice3 venv at ~/.cache/m1power-pmd3
# (see ~/Projects/m1-power/docs/ipad-usb-link.md).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "ipadcast over USB-C"

src="$DOTFILES_ROOT/system/ipadcast-usb"
have usbmuxd || warn "usbmuxd missing: sudo pacman -S usbmuxd"
[[ -x $HOME/.cache/m1power-pmd3/bin/pymobiledevice3 ]] || warn "no pymobiledevice3 at ~/.cache/m1power-pmd3 (docs/ipad-usb-link.md in m1-power)"

run sudo install -Dm755 "$src/ipadcast-usb" /usr/local/bin/ipadcast-usb
run sudo install -Dm755 "$src/ipadcast-usb-kick" /usr/local/bin/ipadcast-usb-kick
run sudo install -Dm755 "$src/ipadcast-ios-open" /usr/local/bin/ipadcast-ios-open
run sudo install -Dm644 "$src/ipadcast-usb.service" /etc/systemd/system/ipadcast-usb.service
run sudo install -Dm644 "$src/ipadcast-usb-kick.service" /etc/systemd/system/ipadcast-usb-kick.service
run sudo install -Dm644 "$src/90-ipadcast-usb.rules" /etc/udev/rules.d/90-ipadcast-usb.rules
run sudo systemctl daemon-reload
run sudo systemctl enable ipadcast-usb-kick.service
run sudo udevadm control --reload

# A device that is plugged in already: unplug and replug the cable. (A faked `udevadm trigger --action=add`
# knocks the device out of its USB configuration; usbmuxd then loses it until it is re-plugged.)
info "plug the cable in again now (or for the first time): the tunnel and the mirror start by themselves"
info "watch it: journalctl -fu ipadcast-usb   |   ipadcast-usb status"
