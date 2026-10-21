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
#   hyprmc     Mission Control as a Hyprland plugin, loaded by input.lua through
#              its hyprmc.lua. Missing, F8 and the vertical 4-finger swipe fall
#              back to the QML Mission Control; same rebuild rule as hyprswipe.
#
# Each project owns its own installer — this step only clones and calls them:
#   velum      bin/velum-install    links the checkout to ~/.local/share/velum and builds it; the
#              desktop's shell plugins (henri.*-v3: bar, Control Center, dock …) import Velum from
#              there — without it they do not load, so it comes first
#   finder     bin/finder-install   desktop entry + icon, default file manager; runs from the checkout
#   settings   bin/settings-install  QML tree, launcher, entry, icon into ~/.local
#   mdview     bin/mdview-install    launcher, desktop entry + icon, default app for Markdown; runs from the checkout
#   hyprswipe  scripts/install.sh    builds against the installed Hyprland headers
#   hyprmc     scripts/install.sh    builds against the installed Hyprland headers
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
  "velum           henriSchulz/velum           bin/velum-install"
  "finder          henriSchulz/finder          bin/finder-install"
  "settings        henriSchulz/settings        bin/settings-install"
  "mdview          henriSchulz/mdview          bin/mdview-install"
  "hyprswipe       henriSchulz/hyprswipe       scripts/install.sh"
  "hyprmc          henriSchulz/hyprmc          scripts/install.sh"
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
