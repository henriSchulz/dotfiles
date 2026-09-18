#!/bin/bash
# Restore the parts of ~/.config/omarchy that this setup owns.
#
# These files are COPIED, never symlinked: Omarchy rewrites them at runtime
# (`omarchy theme set`, bar edits, the shell saving shell.json), and a
# read-only stow symlink in that path causes write failures. This is the
# "generate what Omarchy writes, link what only I write" split from README.md.
#
# shell.json is NOT here — 70-omarchy-shell.sh restores it and restarts the
# shell, so the bar comes up with the plugins step 30 put in place.
#
# Deliberately excluded: omasettings.json, which pins a monitor profile
# ("Messeltronik Dresden GmbH MD20461") belonging to one specific machine.
# OmaSettings regenerates it per machine — see README.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Omarchy configuration"

dest_root="$HOME/.config/omarchy"
run mkdir -p "$dest_root/defaults" "$dest_root/hooks/theme-set.d"

# "<repo-relative path>  <mode>"
files=(
  "keystroke.json  644"
  "omadock.json    644"
  "dock.json       644"
  "menu.json       644"
  "defaults/agent  644"
  "hooks/theme-set.d/global-wallpaper  755"
)

for entry in "${files[@]}"; do
  read -r rel mode <<<"$entry"
  src="$DOTFILES_ROOT/omarchy/$rel"
  dest="$dest_root/$rel"
  [[ -f $src ]] || { warn "missing in repo: omarchy/$rel"; continue; }

  if [[ -f $dest ]] && cmp -s "$src" "$dest"; then
    skip "$rel"
    continue
  fi
  if [[ -f $dest ]]; then
    bak="$dest.pre-dotfiles.$(date +%s)"
    info "backing up existing $rel -> $(basename "$bak")"
    run cp "$dest" "$bak"
  fi
  info "installing $rel"
  run install -m "$mode" "$src" "$dest"
done
