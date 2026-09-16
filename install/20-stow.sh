#!/bin/bash
# Symlink everything under stow/ into $HOME with GNU Stow.
#
# Only configs this setup actually owns live in stow/. Configs that are
# byte-identical to Omarchy's defaults are deliberately NOT stowed, so package
# updates keep improving them. See README.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Dotfile symlinks (stow)"

need_cmd stow "run install/10-packages.sh first"

cd "$DOTFILES_ROOT/stow"
mapfile -t packages < <(find . -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)
((${#packages[@]})) || { skip "nothing to stow"; exit 0; }

# Clear anything real sitting where a symlink needs to go. Stow refuses to
# clobber real files, so this is what makes a fresh machine work unattended.
for pkg in "${packages[@]}"; do
  while IFS= read -r rel; do
    clear_for_stow "$HOME/$rel" "$DOTFILES_ROOT/stow/$pkg/$rel"
  done < <(cd "$pkg" && find . -type f -printf '%P\n')
done

# Real dirs so stow does not fold them into this repo (other apps write there).
run mkdir -p "$HOME/.local/share/icons/hicolor/scalable/apps"

info "stowing: ${packages[*]}"
run stow --dir "$DOTFILES_ROOT/stow" --target "$HOME" --restow "${packages[@]}"
