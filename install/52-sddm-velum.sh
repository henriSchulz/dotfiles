#!/bin/bash
# Login screen (SDDM) with the face of the Velum lock screen, henri.lock-v3 (system/sddm-velum).
#
#   /usr/share/sddm/themes/velum        the theme, root-owned: system/sddm-velum/{Main,Face}.qml plus
#                                       the part of the Velum QML module it uses (`assemble`).
#                                       Re-run this after Velum changes.
#   /var/lib/sddm/.local/share/fonts/velum-greeter
#                                       SF Pro + SF Symbols from ~/.local/share/fonts/sf, for the sddm
#                                       user only (its home is /var/lib/sddm). Local only, never in
#                                       this public repo; missing fonts = system sans + Phosphor icons.
#   /var/lib/velum-greeter              data only, owned by the user: the wallpaper copy and
#                                       theme.conf.user (appearance, variant, lock message), kept up to
#                                       date by velum-greeter-sync (stow/sddm-velum) — no sudo needed.
#   theme.conf.user in the theme dir    a link to /var/lib/velum-greeter/theme.conf.user
#   /etc/sddm.conf.d/zz-velum-theme.conf  [Theme] Current=velum; read last, so it wins over
#                                       Omarchy's 10-theme.conf. Other drop-ins (the ipadcast
#                                       greeter's compositor) are left alone.
# Back to the stock look: sudo rm /etc/sddm.conf.d/zz-velum-theme.conf
#
# Run as the user (it asks sudo for the root steps); `sudo ./install/52-sddm-velum.sh` works too.
# Takes effect at the next login screen; nothing restarts SDDM.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Login screen (SDDM theme velum)"

have sddm-greeter-qt6 || { skip "no sddm-greeter-qt6"; exit 0; }

user="${SUDO_USER:-$USER}"
user_home="$(getent passwd "$user" | cut -d: -f6)"
as_user() {
  if [[ $(id -un) == "$user" ]]; then "$@"
  else sudo -u "$user" -H env XDG_RUNTIME_DIR="/run/user/$(id -u "$user")" "$@"; fi
}

theme=/usr/share/sddm/themes/velum
data=/var/lib/velum-greeter
src="$DOTFILES_ROOT/system/sddm-velum"

# the theme, built as the user (it reads ~), installed as root
build="$(as_user mktemp -d)"
trap 'rm -rf "$build"' EXIT
as_user env USER_HOME="$user_home" "$src/assemble" "$build/velum"
run sudo rm -rf "$theme.new"
run sudo cp -r "$build/velum" "$theme.new"
run sudo chown -R root:root "$theme.new"
run sudo chmod -R u=rwX,go=rX "$theme.new"
run sudo ln -sfn "$data/theme.conf.user" "$theme.new/theme.conf.user"
run sudo rm -rf "$theme"
run sudo mv "$theme.new" "$theme"

# SF fonts for the sddm user (fontconfig reads ~/.local/share/fonts of the greeter's account)
sf="$user_home/.local/share/fonts/sf"
sddm_home="$(getent passwd sddm | cut -d: -f6)"
if [[ -n $sddm_home && -f $sf/SF-Pro.ttf ]]; then
  fontdir="$sddm_home/.local/share/fonts/velum-greeter"
  run sudo install -d -m 755 -o sddm -g sddm "$sddm_home/.local" "$sddm_home/.local/share" "$sddm_home/.local/share/fonts"
  run sudo install -d -m 755 "$fontdir"
  for f in SF-Pro.ttf SFSymbolsFallback.otf; do
    [[ -f $sf/$f ]] && run sudo install -m 644 "$sf/$f" "$fontdir/$f"
  done
  run sudo -u sddm fc-cache "$sddm_home/.local/share/fonts" || warn "fc-cache for sddm failed (fonts still load, a bit slower)"
else
  warn "no SF fonts in $(tilde "$sf") — the login screen uses the system sans and Phosphor icons"
fi

# the data dir the session writes into
run sudo install -d -m 755 -o "$user" -g "$(id -gn "$user")" "$data"

# select the theme (last drop-in wins)
printf '# install/52-sddm-velum.sh in ~/Projects/dotfiles — remove this file for the stock theme\n[Theme]\nCurrent=velum\n' \
  | run sudo install -Dm644 /dev/stdin /etc/sddm.conf.d/zz-velum-theme.conf

# the sync: stow its script + units, enable the path unit, fill the data dir once
need_cmd stow
run as_user stow --dir "$DOTFILES_ROOT/stow" --target "$user_home" --restow sddm-velum
if run as_user systemctl --user daemon-reload 2>/dev/null; then
  run as_user systemctl --user enable --now velum-greeter-sync.path || warn "could not enable velum-greeter-sync.path"
else
  warn "no user systemd bus — enable later: systemctl --user enable --now velum-greeter-sync.path"
fi
run as_user "$user_home/.local/bin/velum-greeter-sync"
info "theme in $theme, wallpaper + settings in $data"
