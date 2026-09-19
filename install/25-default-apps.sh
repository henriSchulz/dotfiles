#!/bin/bash
# Default applications for file types, written to ~/.config/mimeapps.list.
#
# The .desktop files come from the stow packages (step 20), so this runs
# after them. Only the listed types are touched; everything else in
# mimeapps.list stays as the machine has it.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Default applications"

need_cmd xdg-mime "run install/10-packages.sh first"

# mime type → desktop file
defaults=(
  "text/markdown mdview.desktop"
  "text/x-markdown mdview.desktop"
)

apps="$HOME/.local/share/applications"

# Pick up the stowed .desktop files and icons so launchers see them at once.
if have update-desktop-database; then
  run update-desktop-database "$apps"
fi
if have gtk-update-icon-cache && [[ -d $HOME/.local/share/icons/hicolor ]]; then
  run gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" || true
fi

for entry in "${defaults[@]}"; do
  read -r mime desktop <<<"$entry"
  if [[ ! -e $apps/$desktop && $DRY_RUN != 1 ]]; then
    warn "$desktop not found in $(tilde "$apps") — is its stow package installed?"
    continue
  fi
  if [[ $(xdg-mime query default "$mime" 2>/dev/null) == "$desktop" ]]; then
    skip "$mime already opens with $desktop"
    continue
  fi
  info "$mime → $desktop"
  run xdg-mime default "$desktop" "$mime"
done
