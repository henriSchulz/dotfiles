#!/bin/bash
# Headless-friendly MacBook: no suspend on lid close, keyboard-backlight status
# codes before and during login (root daemon), sounds in the session
# (stow/bin/.local/bin/headless-events, started from autostart.lua).
#
# Needs root: run `sudo ./install/96-headless.sh` or answer sudo's prompt.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Headless status (lid, LED daemon)"

src="$DOTFILES_ROOT/system/headless"

[[ -e /sys/class/leds/kbd_backlight ]] || { skip "no kbd_backlight on this machine"; exit 0; }

run sudo install -Dm644 "$src/30-headless-lid.conf" /etc/systemd/logind.conf.d/30-headless-lid.conf
run sudo install -Dm755 "$src/headless-statusd" /usr/local/bin/headless-statusd
run sudo install -Dm644 "$src/headless-status.service" /etc/systemd/system/headless-status.service
run sudo install -Dm755 "$src/headless-test" /usr/local/bin/headless-test

sddm_uid=$(id -u sddm 2>/dev/null || true)
if [[ -n $sddm_uid ]]; then
  run sudo install -Dm644 "$src/sddm-slice-cpu.conf" "/etc/systemd/system/user-$sddm_uid.slice.d/10-cpu.conf"
fi

info "enabling headless-status.service"
run sudo systemctl daemon-reload
run sudo systemctl disable headless-status.service 2>/dev/null || true   # old multi-user.target link
run sudo systemctl enable headless-status.service
run sudo systemctl restart headless-status.service
# Whatever the greeter's user manager is still doing in a session is not needed.
[[ -n $sddm_uid ]] && run sudo systemctl stop "user@$sddm_uid.service" 2>/dev/null || true
info "logind picks the lid setting up after: sudo systemctl restart systemd-logind (ends no sessions, but the greeter may flicker)"
