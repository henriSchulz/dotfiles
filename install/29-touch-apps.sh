#!/bin/bash
# Touch in the Chromium-based apps, as on an iPad: long press opens the context menu, scrolling
# bounces at the end of a page, a swipe in from the left/right edge of a page goes back/forward.
#
# What each toolkit does with a finger on this machine (checked 2026-11-09):
#   GTK4 / GTK3   kinetic scrolling and long press in text fields come with the toolkit; GTK's
#                 menus get Velum's touch look from velum-gtk-touch.css (VelumSettings). Nothing here.
#   WebKitGTK     (mdview, Tauri apps) long press = context menu, kinetic scrolling: its own.
#   Chromium      long press = context menu and kinetic fling are on by default with touch events;
#   + web apps    the bounce (ElasticOverscroll) and the edge swipe for back/forward
#                 (OverscrollHistoryNavigation) are switched on here. Web apps (omarchy-launch-webapp)
#                 are Chromium windows and read the same flags file.
#   Electron      VS Code (code-flags.conf) and Signal (signal-desktop-flags.conf): touch events
#                 forced on and the bounce; their context menus are the apps' own and open on the
#                 long press Chromium turns into a contextmenu event.
#   Qt            no Qt app besides the shell is installed; Qt Widgets has no long press → menu of
#                 its own (would need QTapAndHoldGesture per app).
#
# Chromium reads only the last --enable-features line, so the features are added to the existing
# line (as install/27-chromium-video.sh does), never as a second one. chromium-flags.conf belongs
# to Omarchy and is edited in place; the Electron files are created if missing. Restart the apps
# to apply.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Touch in Chromium and Electron apps"

touch_features=(ElasticOverscroll OverscrollHistoryNavigation)

# Append missing comma-separated values to the line "$flag=…" in $conf, or add the line.
extend_flag() {
  local conf="$1" flag="$2"; shift 2
  local line current value
  line=$(grep -m1 -- "^$flag=" "$conf" || true)
  current="${line#"$flag="}"
  for value in "$@"; do
    [[ ",$current," == *",$value,"* ]] || current="${current:+$current,}$value"
  done
  if [[ -z $line ]]; then
    info "$(tilde "$conf"): adding $flag"
    run bash -c 'printf "%s\n" "$1" >> "$2"' _ "$flag=$current" "$conf"
  elif [[ $line != "$flag=$current" ]]; then
    info "$(tilde "$conf"): extending $flag"
    run python3 - "$conf" "$line" "$flag=$current" <<'PY'
import sys
path, old, new = sys.argv[1:]
lines = open(path).read().split("\n")
open(path, "w").write("\n".join(new if l == old else l for l in lines))
PY
  else
    skip "$(tilde "$conf"): $flag already set"
  fi
}

# Add a switch without a value once.
add_switch() {
  local conf="$1" switch="$2"
  if grep -qx -- "$switch" "$conf"; then
    skip "$(tilde "$conf"): $switch already set"
  else
    info "$(tilde "$conf"): adding $switch"
    run bash -c 'printf "%s\n" "$1" >> "$2"' _ "$switch" "$conf"
  fi
}

chromium_conf="$HOME/.config/chromium-flags.conf"
if [[ -f $chromium_conf ]]; then
  add_switch "$chromium_conf" --touch-events=enabled
  extend_flag "$chromium_conf" --enable-features "${touch_features[@]}"
else
  warn "missing $(tilde "$chromium_conf") — start Chromium once, then rerun"
fi

# Electron apps: only those installed. The edge swipe is a browser feature, so only the bounce.
for app in code:code-flags.conf signal-desktop:signal-desktop-flags.conf; do
  have "${app%%:*}" || { skip "${app%%:*} not installed"; continue; }
  conf="$HOME/.config/${app#*:}"
  [[ -f $conf ]] || run touch "$conf"
  add_switch "$conf" --touch-events=enabled
  extend_flag "$conf" --enable-features ElasticOverscroll
done

info "restart Chromium, VS Code and Signal to apply"
