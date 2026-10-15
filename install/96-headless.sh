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

info "enabling headless-status.service"
run sudo systemctl daemon-reload
run sudo systemctl enable --now headless-status.service
info "logind picks the lid setting up after: sudo systemctl restart systemd-logind (ends no sessions, but the greeter may flicker)"
