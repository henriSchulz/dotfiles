#!/bin/bash
# Chromium on the M1: hardware video decode and VP9 on YouTube.
#
# Arch Linux ARM's Chromium has no VA-API but ships the V4L2 stateless decoder,
# which drives the M1's AVD decoder once these features are on (VP9 works,
# H.264 fails and falls back, AV1 is not supported by AVD). The youtube-vp9
# extension (stow/chromium) hides AV1 from YouTube so it serves VP9.
# Measured 2026-10-01 (~/Projects/m1-power/messungen.md), 1080p60:
# VP9 hardware 3.26 W, VP9 software 3.76 W, AV1 3.95 W.
#
# ~/.config/chromium-flags.conf belongs to Omarchy, so it is edited in place
# rather than stowed: one --enable-features line (Chromium honours only the
# last one) and one --load-extension line, both extended idempotently.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Chromium: hardware video decode + YouTube VP9"

conf="$HOME/.config/chromium-flags.conf"
features=(AcceleratedVideoDecodeLinuxGL AcceleratedVideoDecodeLinuxZeroCopyGL AcceleratedVideoDecoder)
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

extend_flag --enable-features "${features[@]}"
extend_flag --load-extension "$extension"
info "restart Chromium to apply"
