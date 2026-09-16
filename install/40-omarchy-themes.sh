#!/bin/bash
# Install Omarchy themes and apply the active one.
#
# dune, mac-transparent and outpost come from upstream. cupertino,
# cupertino-dark and img-7075 are local, hand-built themes with no remote, so
# they ship in this repo.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Omarchy themes"

need_cmd omarchy "run this on a provisioned Omarchy system"
theme_dir="$HOME/.config/omarchy/themes"
ACTIVE_THEME="${ACTIVE_THEME:-outpost}"

# Upstream themes: "<dir-name> <git-url>"
upstream=(
  "dune             https://github.com/OldJobobo/omarchy-dune-theme"
  "mac-transparent  https://github.com/phoscoder/omarchy-mac-transparent-theme"
  "outpost          https://github.com/simoz/omarchy-outpost-theme.git"
)

for entry in "${upstream[@]}"; do
  read -r name url <<<"$entry"
  if [[ -d "$theme_dir/$name" ]]; then
    skip "$name"
  else
    info "installing $name"
    run omarchy theme install "$url"
  fi
done

# Local themes from this repo.
run mkdir -p "$theme_dir"
for src in "$DOTFILES_ROOT"/omarchy/themes/*/; do
  [[ -d $src ]] || continue
  name="$(basename "$src")"
  info "syncing theme $name"
  run mkdir -p "$theme_dir/$name/backgrounds"
  # No --delete: keeps wallpapers that live only on this machine (below).
  run rsync -a "$src" "$theme_dir/$name/"
done

# The cupertino and img-7075 themes both reference IMG_7075.png, a 32 MB
# personal photo kept out of this public repo. Drop it in any of the places
# below (or pass IMG_7075_PATH) and this links it into both themes.
wallpaper="${IMG_7075_PATH:-}"
if [[ -z $wallpaper ]]; then
  for candidate in \
    "$HOME/Pictures/Wallpaper/IMG_7075.png" \
    "$HOME/Pictures/Wallpapers/IMG_7075.png" \
    "$HOME/Wallpapers/IMG_7075.png"; do
    [[ -f $candidate ]] && { wallpaper="$candidate"; break; }
  done
  wallpaper="${wallpaper:-$HOME/Pictures/Wallpaper/IMG_7075.png}"
fi

if [[ -f $wallpaper ]]; then
  info "wallpaper: ${wallpaper/#$HOME/~}"
  for name in cupertino img-7075; do
    dest="$theme_dir/$name/backgrounds/IMG_7075.png"
    if [[ -f $dest ]]; then
      skip "wallpaper already in $name"
    else
      info "linking wallpaper into $name"
      run cp "$wallpaper" "$dest"
    fi
  done
else
  warn "IMG_7075.png not found at $wallpaper"
  info "the cupertino and img-7075 themes will fall back to their other backgrounds"
  info "set IMG_7075_PATH=<path> to place it"
fi

info "applying theme: $ACTIVE_THEME"
run omarchy theme set "$ACTIVE_THEME"
