#!/bin/bash
# Install Omarchy shell plugins.
#
# Git-backed plugins are re-added from upstream. henri.menu is a heavily
# modified clone of the built-in omarchy.menu, so it ships as source in this
# repo and is copied into place instead.
#
# Enablement and bar placement are NOT set here — omarchy/shell.json owns that
# and is restored by 50-omarchy-config.sh, which runs last.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Omarchy shell plugins"

need_cmd omarchy "run this on a provisioned Omarchy system"
plugin_dir="$HOME/.config/omarchy/plugins"

# Upstream plugins: "<plugin-id> <git-url>"
upstream=(
  "bibek.menu                            https://github.com/BibekBhusal0/omarchy-better-menu.git"
  "evindor.keystroke                     https://github.com/evindor/keystroke.git"
  "io.github.andyweiboan.missioncontrol  https://github.com/AndyWeiBoan/omarchy-mission-control.git"
  "io.github.grootaiinfinity.hwmon       https://github.com/GrootAiInfinity/omarchy-hwmon.git"
  "io.github.maajix.spotlight            https://github.com/maajix/omarchy-spotlight.git"
  "paudelsamir.minimize-pill             https://github.com/paudelsamir/minimize-pill.git"
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

# henri.keystroke: a 2-commit fork of evindor.keystroke 1.4.2 that swaps the
# Codex integration for Claude Code. It has no remote yet — set
# HENRI_KEYSTROKE_URL once it is pushed somewhere, and it installs like the
# rest. Until then this step is skipped rather than failing the run.
if [[ -d "$plugin_dir/henri.keystroke" ]]; then
  skip "henri.keystroke (already present)"
elif [[ -n ${HENRI_KEYSTROKE_URL:-} ]]; then
  info "adding henri.keystroke from $HENRI_KEYSTROKE_URL"
  run omarchy plugin add "$HENRI_KEYSTROKE_URL" --yes
else
  warn "henri.keystroke has no upstream remote — not installed."
  info "push the fork, then re-run with HENRI_KEYSTROKE_URL=<git-url>"
fi

# henri.menu ships as source in this repo.
src="$DOTFILES_ROOT/omarchy/plugins/henri.menu"
if [[ -d $src ]]; then
  info "syncing henri.menu from repo"
  run mkdir -p "$plugin_dir/henri.menu"
  run rsync -a --delete "$src/" "$plugin_dir/henri.menu/"
fi
