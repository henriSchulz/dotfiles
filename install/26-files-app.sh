#!/bin/bash
# GTK apps in the henri-ui style (Finder among them; Nautilus is gone).
#
# The stylesheet itself is stowed (stow/gtk → ~/.config/gtk-4.0); this writes
# the theme colors it imports.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Files app (henri-ui)"

run "$HOME/.local/bin/henri-ui-gtk-colors"
