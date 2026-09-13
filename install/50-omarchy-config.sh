#!/bin/bash
# Restore the parts of ~/.config/omarchy that this setup owns.
#
# These files are COPIED, never symlinked: Omarchy rewrites them at runtime
# (`omarchy theme set`, bar edits, the shell saving shell.json), and a
# read-only stow symlink in that path causes write failures. This is the
# "generate what Omarchy writes, link what only I write" split from README.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Omarchy configuration"

dest_root="$HOME/.config/omarchy"
run mkdir -p "$dest_root/defaults"

# "<repo-relative path>  <mode>"
files=(
  "shell.json      600"
  "keystroke.json  644"
  "defaults/agent  644"
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

info "shell.json reloads on save; restart the shell or re-login to apply fully"
