#!/bin/bash
# Syncthing between the M1 and the tablet — over the USB-C Ethernet cable only.
#
# Documents, Uni, Work and Pictures are kept the same on both machines. No
# server and no third-party service is involved: global and local discovery,
# relays, NAT/UPnP, STUN, usage reporting, crash reporting and the upgrade
# check are all off; Syncthing listens only on this machine's cable address
# and knows the other machine only by its cable address. Without the cable
# nothing syncs. ~/Documents/Notizen is left out (mdview syncs it itself).
#
# The config is written before Syncthing first starts, because a stock first
# start announces itself to the public discovery servers at once.
#
# Needs the other machine's device ID (`syncthing device-id` there):
#   SYNCTHING_PEER_ID=XXXXXXX-... ./install_all.sh 47
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Syncthing (cable only)"

need_cmd syncthing "run install/10-packages.sh first"

case "$(hostname)" in
  m1)     own=10.55.0.1 peer=tablet peer_ip=10.55.0.2 ;;
  tablet) own=10.55.0.2 peer=m1     peer_ip=10.55.0.1 ;;
  *) skip "hostname $(hostname) is neither m1 nor tablet"; exit 0 ;;
esac

if systemctl --user is-enabled -q syncthing.service 2>/dev/null; then
  skip "already set up (syncthing.service enabled)"
  exit 0
fi
[[ -n ${SYNCTHING_PEER_ID:-} ]] || die "set SYNCTHING_PEER_ID to the device ID of $peer"

for d in Documents Uni Work Pictures; do
  [[ -e $HOME/$d/.stignore ]] && continue
  if [[ $d == Documents ]]; then src=stignore-documents; else src=stignore-common; fi
  run install -Dm644 "$DOTFILES_ROOT/syncthing/$src" "$HOME/$d/.stignore"
done

[[ -f $HOME/.local/state/syncthing/config.xml ]] || run syncthing generate --no-port-probing
run "$DOTFILES_ROOT/syncthing/configure.py" "$own" "$peer" "$SYNCTHING_PEER_ID" "$peer_ip"
run sudo ufw allow proto tcp from 10.55.0.0/24 to "$own" port 22000 comment syncthing-cable
run systemctl --user enable --now syncthing.service
info "this machine: $(syncthing device-id)"
