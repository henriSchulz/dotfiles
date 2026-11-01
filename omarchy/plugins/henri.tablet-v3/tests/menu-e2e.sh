#!/bin/bash
# End-to-end tests for the context menu of a home screen icon (IconMenu.qml, iPadOS: touch and hold),
# in the tablet rig of tests/home-e2e.sh (nested Hyprland, headless output TB, virtual pointer
# standing in for a finger). Apps are never launched (VELUM_TABLET_LAUNCH stays unset: uwsm-app
# would start them in the live session); the log shows what would have run.
# The rig shares XDG_STATE_HOME with the session: a drop in edit mode writes the live
# home-layout.json, so the file is backed up and put back on exit.
#   tests/menu-e2e.sh        every case      tests/menu-e2e.sh M3    only M3…
#   KEEP=1 …                 leave the rig running; shots in rig/state/tablet/menu-*.png
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export VELUM_RIG_ID=tablet VELUM_TOUCH=1
unset VELUM_TABLET_LAUNCH
export VELUM_EDGE_SOCKET=$PWD/rig/state/tablet/edge.sock
export VELUM_RIG_PLUGINS="henri.bar-v3 henri.control-center-v3 henri.clock-v3 henri.power-v3 henri.dock-v3 henri.tablet-v3 henri.menu-v3"
R=rig/state/tablet
FILTER=${1:-}
W=1440 H=960
vptr=$shell/henri.launchpad-v3/tests/vptr
[[ -x $vptr/vptr ]] || "$vptr/build.sh"
layout=${XDG_STATE_HOME:-$HOME/.local/state}/velum/home-layout.json
backup=$R/home-layout.backup.json
if [[ -f $layout ]]; then
  cp -p "$layout" "$backup"
  trap 'cat "$backup" > "$layout"' EXIT
fi

sig() { cat $R/sig 2>/dev/null; }
up() { [[ -n $(sig) ]] && HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl version >/dev/null 2>&1; }
if ! up; then rig/rig.sh start >/dev/null || exit 1; fi
rig/rig.sh sync >/dev/null
export HYPRLAND_INSTANCE_SIGNATURE=$(sig)
NWL=$(hyprctl instances -j | jq -r --arg s "$HYPRLAND_INSTANCE_SIGNATURE" '.[] | select(.instance==$s) | .wl_socket')
hyprctl monitors -j | jq -e '.[] | select(.name=="TB")' >/dev/null || hyprctl output create headless TB >/dev/null
sleep 0.5
hyprctl eval "hl.monitor({ output = 'TB', mode = '${W}x${H}@60', position = '2000x0', scale = 1 })" >/dev/null
hyprctl dispatch "hl.dsp.focus({ monitor = 'TB' })" >/dev/null
sleep 0.5
rig/rig.sh shell >/dev/null
for _ in $(seq 20); do sleep 0.5; [[ $(rig/rig.sh call henri.tablet state 2>/dev/null) == *'"active":true'* ]] && break; done
sleep 1.5

c() { rig/rig.sh call "$@" 2>/dev/null; }
pt() { WAYLAND_DISPLAY=$NWL "$vptr/vptr" TB $W $H "$@"; sleep 0.3; }
shot() { WAYLAND_DISPLAY=$NWL timeout 5 grim -o TB "$R/menu-$1.png" 2>/dev/null; }
hm() { c henri.tablet home; }
icon() { local r; r=$(c henri.tablet homeIcon TB "$1"); echo "$(jq -r '(.x + .w / 2) | floor' <<<"$r") $(jq -r '(.y + .w / 2) | floor' <<<"$r")"; }
pass=0 fail=0 failed=()
want() {
  [[ -n $FILTER && $1 != $FILTER* ]] && return
  if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-6s %s\n' "$1" "$2"
  else fail=$((fail + 1)); failed+=("$1"); printf '  FAIL  %-6s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; shot "FAIL-$1"; fi
}

# the home screen on TB
hyprctl dispatch "hl.dsp.focus({ workspace = 'emptynm' })" >/dev/null; sleep 1.2
c henri.tablet clearLog >/dev/null

read -r fx fy < <(icon foot)
pt m "$fx" "$fy" d s 650 u; sleep 0.6; shot M1-dock
want M1 "touch and hold a dock icon: its context menu" "$(hm | jq -r .menu)" "foot"
want M1b "a quick tap beside it closes it" "$(pt m 200 300 d s 60 u; sleep 0.7; hm | jq -r .menu)" ""

pt m "$fx" "$fy" d s 650 g $((fx + 20)) $((fy - 140)) 10 16 s 120 u; sleep 0.6
want M2 "hold, slide onto New Window, lift: a new window of the app" "$(hm | jq -r '.log | map(select(startswith("menu foot"))) | last')" "menu foot new"
want M2b "the menu went away and the launch card grew" "$(hm | jq -r '.menu + "," + (.log | map(select(startswith("tap foot"))) | length > 0 | tostring)')" ",true"
sleep 3.5

read -r kx ky < <(icon keepass)
pt m "$kx" "$ky" d s 650; sleep 0.4; shot M3-grid
want M3 "touch and hold a grid icon: its menu, no edit mode yet" "$(hm | jq -r '.menu + "," + (.editing | tostring)')" "keepass,false"
pt g $((kx - 60)) $((ky + 60)) 8 16 s 200; sleep 0.3; shot M3-drag
want M3b "the held icon moved off the menu: edit mode, the menu gone" "$(hm | jq -r '.menu + "," + (.editing | tostring)')" ",true"
pt g "$kx" "$ky" 8 16 s 900 u; sleep 0.8
pt m 1300 900 d s 60 u; sleep 0.6

pt m "$kx" "$ky" d s 650 u; sleep 0.6
row=$(hm | jq -r .menu)
# Edit Home Screen is the last row: under New Window
pt m $((kx + 40)) $((ky + 147)) d s 60 u; sleep 0.8
want M4 "Edit Home Screen from the menu" "$row,$(hm | jq -r '.editing | tostring')" "keepass,true"
pt m 1300 900 d s 60 u; sleep 0.6

echo "passed $pass, failed $fail${failed[*]:+: ${failed[*]}}"
[[ -n ${KEEP:-} ]] || rig/rig.sh stop >/dev/null 2>&1
[[ $fail == 0 ]]
