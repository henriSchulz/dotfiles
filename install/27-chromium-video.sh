#!/bin/bash
# Chromium on the M1: VP9 instead of AV1 on YouTube, hardware decode when the
# decoder driver can do it.
#
# Arch Linux ARM's Chromium has no VA-API; its V4L2 stateless decoder
# (features AcceleratedVideoDecodeLinuxGL, …ZeroCopyGL, AcceleratedVideoDecoder)
# drives the M1's AVD. With the stock apple-avd module that shows a solid
# green video (the driver rejects every frame, found 2026-10-01); with the
# patched module from ~/Projects/m1-power/avd it decodes VP9 correctly and
# saves 0.34 W at 1080p60. chromium-hwdec-sync (stow/chromium) therefore turns
# the features on only while the patched module is in use, here and at every
# login, so a kernel update that brings the stock module back cannot leave
# Chromium green.
#
# The youtube-vp9 extension (stow/chromium) hides AV1 from YouTube so it
# serves VP9: AVD has no AV1, and in software VP9 is cheaper (1080p60:
# VP9 3.76 W, AV1 3.95 W).
#
# ~/.config/chromium-flags.conf belongs to Omarchy, so it is edited in place
# rather than stowed; the --load-extension line is extended idempotently.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Chromium: YouTube VP9, hardware decode"

conf="$HOME/.config/chromium-flags.conf"
extension="$HOME/.local/share/chromium-extensions/youtube-vp9"

if [[ $(uname -m) != aarch64 ]]; then skip "not an ARM machine"; exit 0; fi
[[ -f $conf ]] || { warn "missing $(tilde "$conf") — start Chromium once, then rerun"; exit 0; }

# Append missing comma-separated values to the line starting with $1, or add the line.
extend_flag() {
  local flag="$1"; shift
  local line current value
  line=$(grep -m1 -- "^$flag=" "$conf" || true)
  current="${line#"$flag="}"
  for value in "$@"; do
    [[ ",$current," == *",$value,"* ]] || current="${current:+$current,}$value"
  done
  if [[ -z $line ]]; then
    info "adding $flag"
    run bash -c 'printf "%s\n" "$1" >> "$2"' _ "$flag=$current" "$conf"
  elif [[ $line != "$flag=$current" ]]; then
    info "extending $flag"
    run python3 - "$conf" "$line" "$flag=$current" <<'PY'
import sys
path, old, new = sys.argv[1:]
lines = open(path).read().split("\n")
open(path, "w").write("\n".join(new if l == old else l for l in lines))
PY
  else
    skip "$flag already set"
  fi
}

# Hardware decode features: on with the patched apple-avd, off otherwise.
if [[ -x $HOME/.local/bin/chromium-hwdec-sync ]]; then
  run "$HOME/.local/bin/chromium-hwdec-sync"
  run systemctl --user enable chromium-hwdec-sync.service
else
  warn "chromium-hwdec-sync missing — run install/20-stow.sh first"
fi
extend_flag --load-extension "$extension"
info "restart Chromium to apply"
