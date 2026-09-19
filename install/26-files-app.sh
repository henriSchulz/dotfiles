#!/bin/bash
# Files (Nautilus) in the henri-ui / Finder style.
#
# The stylesheet itself is stowed (stow/gtk → ~/.config/gtk-4.0); this writes
# the theme colors it imports and sets Finder's icon sizes (64 px grid, 16 px list).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Files app (henri-ui)"

run "$HOME/.local/bin/henri-ui-gtk-colors"

if command -v gsettings >/dev/null; then
  run gsettings set org.gnome.nautilus.icon-view default-zoom-level small-plus
  run gsettings set org.gnome.nautilus.list-view default-zoom-level small
else
  skip "gsettings missing — icon sizes left as they are"
fi
