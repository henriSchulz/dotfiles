#!/bin/bash
# Install Omarchy shell plugins.
#
# Git-backed plugins are re-added from upstream. The henri.* plugins are
# modified clones of built-in Omarchy plugins, so they ship as source in this
# repo and are copied into place instead.
#
# Enablement and bar placement are NOT set here — omarchy/shell.json owns that
# and is restored by 70-omarchy-shell.sh, which runs last of all.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Omarchy shell plugins"

need_cmd omarchy "run this on a provisioned Omarchy system"
need_cmd rsync "run install/10-packages.sh first"
plugin_dir="$HOME/.config/omarchy/plugins"

# Upstream plugins: "<plugin-id> <git-url>"
upstream=(
  "bibek.menu                            https://github.com/BibekBhusal0/omarchy-better-menu.git"
  "evindor.keystroke                     https://github.com/evindor/keystroke.git"
  "expose.window-overview                https://github.com/kristofferR/omarchy-expose.git"
  "henri.keystroke                       https://github.com/henriSchulz/keystroke.git"
  "henri.missioncontrol                  https://github.com/henriSchulz/omarchy-mission-control.git"
  "io.github.sirjul1337.lock-explorer    https://github.com/SirJul1337/omarchy-lock-explorer.git"
  "omadock                               https://github.com/thepathless/omadock.git"
  "omaplug                               https://github.com/fross100/omaplug.git"
  "stappmus.activity-monitor             https://github.com/stappmus/omarchy-activity-monitor.git"
)

for entry in "${upstream[@]}"; do
  read -r id url <<<"$entry"
  if [[ -d "$plugin_dir/$id" ]]; then
    skip "$id"
  else
    info "adding $id"
    run omarchy plugin add "$url" --yes
  fi
done

# Local plugins ship as source in this repo:
#   henri.menu  — clone of omarchy.menu, a Spotlight-style launcher
#   henri.idle  — clone of omarchy.idle, drives omarchy-screensaver-themed
#                 (that script comes from the `bin` stow package, step 20)
#   henri.bar   — clone of omarchy.bar: translucent macOS-style menu bar
#   henri.workspaces — clone of omarchy.workspaces, occupied workspaces only
#   henri.clock — clone of omarchy.clock, German day and month names
#   henri.system-menu — own plugin, macOS-style Apple menu behind the
#                 Omarchy logo in the bar's left corner
#   henri.active-window — clone of omarchy.active-window, app name that opens
#                 the app's settings (app-settings, `bin` stow package)
#   io.github.nipsen.dell-power — NIPSEN/omarchy-dell-power (MIT) with the
#                 bar glyph swapped for the macOS battery (HUi.BatteryGlyph)
for src in "$DOTFILES_ROOT"/omarchy/plugins/*/; do
  [[ -d $src ]] || continue
  id="$(basename "$src")"
  info "syncing $id from repo"
  run mkdir -p "$plugin_dir/$id"
  run rsync -a --delete "$src" "$plugin_dir/$id/"
done
