#!/bin/bash
# Edge gestures on the Acer's own touchscreen, as the cast screen has them (system/velum-touch):
# a root service grabs the touchscreen, holds back fingers that land at an edge and passes the rest
# on through a uinput copy. Remove:
#   sudo systemctl disable --now velum-touch && sudo rm /etc/systemd/system/velum-touch.service /usr/local/lib/velum/velum-touchd
#
# Needs root: run `sudo ./install/98-velum-touch.sh` or answer sudo's prompt.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Touchscreen edge gestures"

if [[ "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" != "Switch SA5-271" ]]; then
  skip "not the Acer Switch Alpha 12"
  exit 0
fi

src="$DOTFILES_ROOT/system/velum-touch"
user_uid=$(id -u "${SUDO_USER:-$USER}")
run sudo install -Dm755 "$src/velum-touchd" /usr/local/lib/velum/velum-touchd
sed "s/@UID@/$user_uid/" "$src/velum-touch.service" | run sudo install -Dm644 /dev/stdin /etc/systemd/system/velum-touch.service
run sudo systemctl daemon-reload
run sudo systemctl enable velum-touch.service
run sudo systemctl restart velum-touch.service   # a new daemon takes over at once
