#!/bin/bash
# Power tuning for the Acer Switch Alpha 12 (SA5-271) only: runtime PM for
# PCI and some USB devices, PCIe ASPM powersupersave, no NMI watchdog
# (system/tablet-power). Wi-Fi power saving and the battery power profile are
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

# apply now instead of at the next boot
run sudo udevadm control --reload
run sudo udevadm trigger --subsystem-match=pci --subsystem-match=usb --action=add
run sudo sysctl -q --load /etc/sysctl.d/50-tablet-power.conf
run sudo systemd-tmpfiles --create /etc/tmpfiles.d/50-tablet-power-aspm.conf || warn "the BIOS keeps ASPM control — policy stays at default"
