#!/bin/bash
# The MacTahoe icon theme, which the dock's iconOverrides point at
# (omarchy/henri.dock.json: foot, Files). Without it those dock tiles fall back
# to generic icons. stow/bin's henri-macos-icons fetches it from upstream —
# it is GPL-3.0 and 220 MB, so it is never part of this repo.
#
# The shell indexes icons once at startup: after a first install,
# omarchy-restart-shell (step 70 does) before the dock shows them.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "MacTahoe icons"

if [[ -d $HOME/.local/share/icons/MacTahoe && -d $HOME/.local/share/icons/MacTahoe-dark ]]; then
  skip "MacTahoe already in ~/.local/share/icons (henri-macos-icons updates it)"
  exit 0
fi

need_cmd git "install git first"
run "$HOME/.local/bin/henri-macos-icons"
