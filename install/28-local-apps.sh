#!/bin/bash
# My own apps and the Hyprland plugin, which live in their own repos.
#
# These are private repos, so the clone needs credentials: either `gh auth
# login` beforehand (this step prefers `gh` when it is there) or an SSH key
# GitHub knows. Without either, the clone fails loudly and the rest of the
# install continues — none of these are needed to bring the desktop up, with
# one exception:
#
#   hyprswipe  is `dofile`d by stow/hypr/.config/hypr/input.lua. Missing, the
#              4-finger workspace swipe is silently off (input.lua guards the
#              call); the .so is also tied to the exact Hyprland build, so
#              scripts/install.sh has to run again after a Hyprland update.
#
# Each project owns its own installer — this step only clones and calls them:
#   finder     bin/finder-install   desktop entry + icon, default file manager; runs from the checkout
#   settings   bin/settings-install  QML tree, launcher, entry, icon into ~/.local
#   hyprswipe  scripts/install.sh    builds against the installed Hyprland headers
#   menubar    none — a web component, only ever built in the checkout (npm run build)
#   akku-test  none — install/94 enables the service that runs hintergrund.py
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Own apps and plugins"

need_cmd git

projects="$HOME/Projects"
run mkdir -p "$projects"

# "<directory> <repo> <installer, or - for none>"
repos=(
  "finder          henriSchulz/finder          bin/finder-install"
  "settings        henriSchulz/settings        bin/settings-install"
  "hyprswipe       henriSchulz/hyprswipe       scripts/install.sh"
  "menubar         henriSchulz/menubar         -"
  "akku-test       henriSchulz/akku-test       -"
  "MacOSUICapture  henriSchulz/MacOSUICapture  -"
)

for entry in "${repos[@]}"; do
  read -r dir repo installer <<<"$entry"
  dest="$projects/$dir"

  if [[ -d $dest/.git ]]; then
    skip "$dir already cloned"
  else
    info "cloning $repo -> $(tilde "$dest")"
    if have gh; then
      run gh repo clone "$repo" "$dest" || { warn "clone of $repo failed — skipping $dir"; continue; }
    else
      run git clone "git@github.com:$repo.git" "$dest" || { warn "clone of $repo failed — skipping $dir"; continue; }
    fi
  fi

  [[ $installer == - ]] && continue
  if [[ -x $dest/$installer ]]; then
    info "running $dir/$installer"
    run "$dest/$installer"
  else
    warn "missing $(tilde "$dest/$installer") — $dir not installed"
  fi
done
