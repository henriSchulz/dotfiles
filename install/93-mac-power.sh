#!/bin/bash
# Power over the USB-C cable to the mt-bridge Mac (Control Center → Mac →
# Power). The user-side script mac-power is stowed by 20-stow.sh; this
# installs the root half: mt-power-role, which flips the port's USB-PD power
# role, and the sudoers line that lets mac-power call it without a password.
# The Mac half (mt-charge + its sudoers line) is macos/power/install-power.sh
# in the mt-bridge repo, run with sudo on the Mac.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Mac power over the cable"
need_cmd sudo

src="$DOTFILES_ROOT/usr/local/bin/mt-power-role" dst=/usr/local/bin/mt-power-role
if [[ -f $dst ]] && cmp -s "$src" "$dst"; then
  skip "$dst"
else
  info "installing $dst"
  run sudo install -o root -g root -m 755 "$src" "$dst"
fi

src="$DOTFILES_ROOT/etc/sudoers.d/mt-power" dst=/etc/sudoers.d/mt-power
if sudo test -f "$dst" && sudo cmp -s "$src" "$dst"; then
  skip "$dst"
else
  run sudo visudo -cf "$src" >/dev/null
  info "installing $dst"
  run sudo install -o root -g root -m 440 "$src" "$dst"
fi

# Whether run as the user (sudo per step, like the other scripts) or as root
# via `sudo 93-mac-power.sh`, mac-power belongs to the login user.
info "applying the stored wish (default: off)"
if [[ $(id -u) == 0 && -n ${SUDO_USER:-} ]]; then
  run sudo -u "$SUDO_USER" -i "$(getent passwd "$SUDO_USER" | cut -d: -f6)/.local/bin/mac-power" reconcile >/dev/null
else
  run "$HOME/.local/bin/mac-power" reconcile >/dev/null
fi
