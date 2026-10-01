#!/bin/bash
# Chromium on the M1: VP9 instead of AV1 on YouTube.
#
# Hardware video decode in Chromium does NOT work here and must stay off:
# Arch Linux ARM's Chromium has no VA-API, and its V4L2 stateless decoder
# (features AcceleratedVideoDecodeLinuxGL, …ZeroCopyGL, AcceleratedVideoDecoder)
# claims to decode on the M1's AVD but never drives it — the video is solid
# green (found 2026-10-01; an earlier version of this script enabled it after
# checking only the decoder name and the CPU load, never the picture).
#
# What is left is the youtube-vp9 extension (stow/chromium): it hides AV1 from
# YouTube so it serves VP9. Both are decoded on the CPU; VP9 is a little
# cheaper (1080p60, measured 2026-10-01: VP9 3.76 W, AV1 3.95 W).
#
# ~/.config/chromium-flags.conf belongs to Omarchy, so it is edited in place
# rather than stowed; the --load-extension line is extended idempotently.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Chromium: YouTube VP9"

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

# Take the broken hardware-decode features out again where an earlier run added them.
if grep -q 'AcceleratedVideoDecode' "$conf"; then
  info "removing hardware video decode features (green video)"
  run sed -i 's/,AcceleratedVideoDecodeLinuxGL//; s/,AcceleratedVideoDecodeLinuxZeroCopyGL//; s/,AcceleratedVideoDecoder//' "$conf"
fi
extend_flag --load-extension "$extension"
info "restart Chromium to apply"
