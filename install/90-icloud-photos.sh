#!/bin/bash
# Set up the iCloud Photos client.
#
# Four things make that app work, and only two of them can be automated:
#
#   source     github.com/henriSchulz/IcloudPhotos — cloned here
#   config     ~/.config/icloud-photos/config.toml — seeded here
#   password   the Apple ID password in the Secret Service keyring — YOU,
#              on first launch, because it needs the 2FA prompt
#   catalog    ~/.local/share/icloud-photos/catalog.sqlite and the thumbnail
#              and full-res caches — rebuilt by the first sync
#
# The catalog and caches are deliberately never copied between machines. They
# are 2.4 GB of derived data keyed to a session that would not survive the
# trip anyway, and the app knows how to rebuild them.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "iCloud Photos"

need_cmd git
src="${ICLOUD_PHOTOS_SRC:-$HOME/Projects/IcloudPhotos}"
url="${ICLOUD_PHOTOS_URL:-https://github.com/henriSchulz/IcloudPhotos.git}"

if [[ -d $src/.git ]]; then
  if [[ -n $(git -C "$src" status --porcelain) ]]; then
    warn "$(tilde "$src") has local changes — leaving it alone, no pull"
  else
    info "updating $(tilde "$src")"
    run git -C "$src" pull --ff-only || warn "pull failed — continuing with the checkout as-is"
  fi
else
  info "cloning into $(tilde "$src")"
  run git clone "$url" "$src"
fi

# The sidecar needs its own venv: pyicloud 2.7.0 exactly, and `rich`, without
# which importing pyicloud fails outright. See the project's CLAUDE.md.
if [[ -d $src/.venv ]]; then
  skip "python venv already present"
elif [[ $DRY_RUN == 1 ]]; then
  info "[dry-run] would create $src/.venv and install sidecar/requirements.txt"
else
  info "creating the sidecar venv"
  run python3 -m venv "$src/.venv"
  run "$src/.venv/bin/pip" install --quiet -r "$src/sidecar/requirements.txt"
fi

# config.toml carries the Apple ID, so it is seeded from this repo rather than
# from the example, which ships a placeholder. The password is NOT in here —
# pyicloud keeps it in the keyring.
conf_src="$DOTFILES_ROOT/icloud-photos/config.toml"
conf_dest="$HOME/.config/icloud-photos/config.toml"
if [[ ! -f $conf_src ]]; then
  warn "missing in repo: icloud-photos/config.toml"
elif [[ -f $conf_dest ]]; then
  skip "config.toml already present"
else
  info "installing config.toml"
  run mkdir -p "$(dirname "$conf_dest")"
  run install -m 600 "$conf_src" "$conf_dest"
fi

# A release build of a GTK4 app is several hundred crates and takes minutes,
# which is too long to spend by default inside a run that is otherwise quick.
if [[ ${ICLOUD_PHOTOS_BUILD:-0} == 1 ]]; then
  need_cmd cargo "install rust, or re-run without ICLOUD_PHOTOS_BUILD=1"
  info "building (this takes a few minutes)"
  run cargo build --release --manifest-path "$src/Cargo.toml"
  info "built: $(tilde "$src")/target/release/icloud-photos-app"
else
  info "not building — re-run with ICLOUD_PHOTOS_BUILD=1, or:"
  info "  cd $(tilde "$src") && cargo run -p icloud-photos-app"
fi

info "on first launch, enter the Apple ID password + 2FA code; it goes to the"
info "keyring and the first sync rebuilds the catalog and thumbnails"
