#!/bin/bash
# LUKS screen (Plymouth theme velum) with the face of the Velum lock screen (system/plymouth-velum).
#
#   /usr/share/plymouth/themes/velum        the theme: velum.script and PNGs from `assemble`, drawn for this
#                                           machine's panel from the wallpaper and settings in
#                                           /var/lib/velum-greeter. Local only, the PNGs hold SF glyphs.
#   /etc/initcpio/{hooks,install}/velum-clock   sends the time to the script, which has no clock of its own
#   /etc/mkinitcpio.conf.d/velum_clock.conf     puts that hook right after plymouth, before encrypt
#   /etc/plymouth/plymouthd.conf            Theme=velum, DeviceScale=1 (the PNGs are in device pixels)
#
# The wallpaper lives in the initramfs: after a new wallpaper or a Velum change, run this again.
# Back to the stock look: sudo plymouth-set-default-theme omarchy; sudo rm /etc/mkinitcpio.conf.d/velum_clock.conf;
# delete the DeviceScale line in plymouthd.conf; sudo limine-mkinitcpio
#
# The images need the session (nested Hyprland, SF fonts), the install needs root:
#   system/plymouth-velum/assemble <dir> && ask-root 'install/53-plymouth-velum.sh <dir>'
# Run as the user with no argument, it does both through sudo.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "LUKS screen (Plymouth theme velum)"

have plymouth-set-default-theme || { skip "no plymouth"; exit 0; }

src="$DOTFILES_ROOT/system/plymouth-velum"
built="${1:-}"
if [[ -z $built ]]; then
  [[ $(id -u) != 0 ]] || die "as root, name the directory assemble built"
  built="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/velum-plymouth-theme.XXXXXX")"
  trap 'rm -rf "$built"' EXIT
  "$src/assemble" "$built/velum"
  built="$built/velum"
fi
[[ -f $built/velum.script && -f $built/bg.png ]] || die "no theme in $built"

as_root() { if [[ $(id -u) == 0 ]]; then run "$@"; else run sudo "$@"; fi; }

theme=/usr/share/plymouth/themes/velum
as_root rm -rf "$theme.new"
as_root cp -r "$built" "$theme.new"
as_root chown -R root:root "$theme.new"
as_root chmod -R u=rwX,go=rX "$theme.new"
as_root rm -rf "$theme"
as_root mv "$theme.new" "$theme"

as_root install -Dm755 "$src/initcpio/hooks/velum-clock" /etc/initcpio/hooks/velum-clock
as_root install -Dm644 "$src/initcpio/install/velum-clock" /etc/initcpio/install/velum-clock
as_root install -Dm644 "$src/velum_clock.conf" /etc/mkinitcpio.conf.d/velum_clock.conf

as_root plymouth-set-default-theme velum
grep -q '^DeviceScale=' /etc/plymouth/plymouthd.conf \
  || as_root sed -i '/^\[Daemon\]/a DeviceScale=1' /etc/plymouth/plymouthd.conf

if have limine-mkinitcpio; then as_root limine-mkinitcpio; else as_root mkinitcpio -P; fi
info "theme in $theme; takes effect at the next boot"
