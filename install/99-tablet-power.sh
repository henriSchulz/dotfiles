#!/bin/bash
# Power tuning for the Acer Switch Alpha 12 (SA5-271) only: runtime PM for
# PCI and some USB devices, PCIe ASPM powersupersave, no NMI watchdog
# (system/tablet-power), plus hidraw access to the keyboard for its backlight
# (henri-kbdlight-hid), mitigations=off + THP madvise on the kernel command line
# and no cups. Wi-Fi power saving and the battery power profile are
# left alone on purpose — Henri chose a stable connection and "balanced".
# The M1 has its own power rules in ~/Projects/m1-power; nothing here runs there.
#
# Needs root: run `sudo ./install/99-tablet-power.sh` or answer sudo's prompt.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Tablet power tuning"

if [[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" != "Switch SA5-271" ]]; then
  skip "not the Acer Switch Alpha 12"
  exit 0
fi

src="$DOTFILES_ROOT/system/tablet-power"
run sudo install -Dm644 "$src/50-tablet-power.rules" /etc/udev/rules.d/50-tablet-power.rules
run sudo install -Dm644 "$src/50-tablet-power.conf" /etc/sysctl.d/50-tablet-power.conf
run sudo install -Dm644 "$src/50-tablet-power-aspm.conf" /etc/tmpfiles.d/50-tablet-power-aspm.conf
# kernel command line: mitigations=off, THP madvise (see the file); takes effect at the next boot
run sudo install -Dm644 "$src/tablet-performance.conf" /etc/limine-entry-tool.d/tablet-performance.conf
run sudo limine-update
# no printing: disabling cups.service takes cups.socket and cups.path along
# (back with `systemctl enable --now cups.socket`)
run sudo systemctl disable --now cups.service
# hidraw of the detachable keyboard for the logged-in user: henri-kbdlight-hid switches its backlight
run sudo install -Dm644 "$src/70-acer-kbd-hidraw.rules" /etc/udev/rules.d/70-acer-kbd-hidraw.rules
# the keyboard cover's top row as the M1's Apple row (and real F-keys with Fn where it can)
run sudo install -Dm644 "$DOTFILES_ROOT/system/acer-keys/90-acer-hawaii-keys.hwdb" /etc/udev/hwdb.d/90-acer-hawaii-keys.hwdb
run sudo rm -f /etc/udev/hwdb.d/90-acer-hawaii-no-numlock.hwdb
run sudo systemd-hwdb update

# Cover touchpad: firmware flags fingers as palms mid-swipe, the gesture cancels.
# Hyprland reads quirks at startup.
run sudo install -Dm644 "$DOTFILES_ROOT/system/acer-keys/local-overrides.quirks" /etc/libinput/local-overrides.quirks

# apply now instead of at the next boot
run sudo udevadm control --reload
run sudo udevadm trigger --subsystem-match=pci --subsystem-match=usb --subsystem-match=hidraw --action=add
run sudo udevadm trigger --subsystem-match=input --action=change
run sudo sysctl -q --load /etc/sysctl.d/50-tablet-power.conf
run sudo systemd-tmpfiles --create /etc/tmpfiles.d/50-tablet-power-aspm.conf || warn "the BIOS keeps ASPM control — policy stays at default"
