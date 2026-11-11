#!/bin/bash
# Chromium: the tab-qr extension (stow/chromium) shows the current tab's
# address as a QR code, so the phone camera opens it. Alt+Shift+P or the
# toolbar button; the shortcut can be changed in chrome://extensions/shortcuts.
# Its velum.css and velum-web.css are symlinks into ~/Projects/velum, so the
# popup follows the Velum tokens without a copy (Chromium follows symlinks
# out of unpacked extensions).
#
# ~/.config/chromium-flags.conf belongs to Omarchy, so it is edited in place
# rather than stowed; the --load-extension line is extended idempotently
# (as install/27-chromium-video.sh does), never added a second time.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Chromium: tab QR code extension"

conf="$HOME/.config/chromium-flags.conf"
extension="$HOME/.local/share/chromium-extensions/tab-qr"

[[ -f $conf ]] || { warn "missing $(tilde "$conf") — start Chromium once, then rerun"; exit 0; }
[[ -d $extension ]] || { warn "missing $(tilde "$extension") — run install/20-stow.sh first"; exit 0; }
[[ -f $HOME/Projects/velum/dist/css/velum.css ]] || warn "~/Projects/velum missing — the popup has no Velum styles"

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

extend_flag --load-extension "$extension"
info "restart Chromium to apply"
