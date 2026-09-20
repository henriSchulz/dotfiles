#!/bin/bash
# Set up the one-way iCloud calendar mirror the clock plugin reads.
#
# Four things make the calendar popup show events, and only three of them
# can be automated:
#
#   config     ~/.config/vdirsyncer/config  — stowed by 20-stow.sh
#   timer      vdirsyncer-sync.timer, every 15 minutes — enabled here
#   password   an app-specific password in the Secret Service keyring — YOU,
#              once, because it has to be minted at appleid.apple.com and the
#              account's 2FA means the Apple ID password itself will not do
#   vdir       ~/.local/share/calendars/ — filled by the first sync
#
# The vdir is deliberately never copied between machines: it is derived data
# that the first sync rebuilds in seconds.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "iCloud calendars"

need_cmd vdirsyncer "run install/10-packages.sh first"

apple_id="henri.schulz.bs@icloud.com"
config="$HOME/.config/vdirsyncer/config"

if [[ ! -e $config ]]; then
  warn "missing $(tilde "$config") — run install/20-stow.sh first"
  exit 0
fi

# The password is the gate: discover and sync both fail without it, and they
# fail slowly, against Apple's servers. Check the keyring first instead.
if secret-tool lookup service icloud-caldav username "$apple_id" >/dev/null 2>&1; then
  info "app-specific password found in the keyring"
else
  warn "no app-specific password in the keyring yet — the timer will fail until:"
  warn "  1. mint one at appleid.apple.com → Sign-In and Security → App-Specific Passwords"
  warn "  2. secret-tool store --label=\"iCloud CalDAV\" \\"
  warn "       service icloud-caldav username $apple_id"
  warn "  3. vdirsyncer discover && vdirsyncer sync"
fi

# Enabling is safe without the password: the timer simply logs failures until
# one is stored, and then starts working without anyone re-running this.
info "enabling vdirsyncer-sync.timer"
run systemctl --user enable --now vdirsyncer-sync.timer

info "events land in $(tilde "$HOME/.local/share/calendars")"
info "check a day by hand: omarchy-calendar-events --from $(date +%F) --to $(date +%F)"
