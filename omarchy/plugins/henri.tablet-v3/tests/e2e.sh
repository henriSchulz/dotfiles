#!/bin/bash
# End-to-end tests for the tablet mode in its own nested rig (VELUM_RIG_ID=tablet, VELUM_TOUCH=1),
# with a real pointer: the virtual pointer of henri.launchpad-v3/tests/vptr on a headless output
# TB of the NESTED compositor, never the live session. A finger reaches the shell as a
# synthesized mouse, so drags at human speed stand in for touch; real touch is only testable
# on the tablet itself.
#
#   tests/e2e.sh          every case (starts the rig if needed)
#   tests/e2e.sh T03      only cases whose id starts with T03
#   KEEP=1 tests/e2e.sh   leave the rig running
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export VELUM_RIG_ID=tablet VELUM_TOUCH=1
export VELUM_RIG_PLUGINS="henri.bar-v3 henri.control-center-v3 henri.clock-v3 henri.power-v3 henri.system-menu-v3 henri.dock-v3 henri.tablet-v3 henri.launchpad-v3 henri.missioncontrol-v3"
R=rig/state/tablet
FILTER=${1:-}
W=1440 H=960                                  # the tablet's logical size (2160 × 1440 at scale 1.5)
vptr=$shell/henri.launchpad-v3/tests/vptr
[[ -x $vptr/vptr ]] || "$vptr/build.sh"

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
hyprctl monitors -j | jq -e ".[] | select(.name==\"TB\" and .width==$W)" >/dev/null || { echo "no TB output"; exit 1; }
rig/rig.sh shell >/dev/null
for _ in $(seq 20); do sleep 0.5; [[ $(rig/rig.sh call henri.tablet state 2>/dev/null) == *'"active":true'* ]] && break; done

c() { rig/rig.sh call "$@" 2>/dev/null; }
pt() { WAYLAND_DISPLAY=$NWL "$vptr/vptr" TB $W $H "$@"; sleep 0.3; }
shot() { WAYLAND_DISPLAY=$NWL timeout 5 grim -o TB "$R/e2e-$1.png" 2>/dev/null; }
layer() { hyprctl layers -j | jq -e --arg n "$1" '[.. | objects | select(.namespace? == $n)] | length > 0' >/dev/null && echo true || echo false; }
ws() { hyprctl activeworkspace -j | jq .id; }
log() { c henri.tablet state | jq -c .log; }
dockHidden() { c dock state | jq .hidden; }

pass=0 fail=0 failed=()
want() {                                       # want CASE "description" ACTUAL EXPECTED
  [[ -n $FILTER && $1 != $FILTER* ]] && return
  if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-6s %s\n' "$1" "$2"
  else fail=$((fail + 1)); failed+=("$1"); printf '  FAIL  %-6s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; shot "FAIL-$1"; fi
}
runs() { [[ -z $FILTER || $1 == $FILTER* ]]; }

# a window on the workspace, so the dock hides (an empty space keeps it out, as a home screen)
if [[ $(hyprctl clients -j | jq 'length') == 0 ]]; then
  hyprctl dispatch "hl.dsp.exec_cmd('foot')" >/dev/null; sleep 1.5
fi
sleep 1
X=$((W / 2)) B=$((H - 8))                      # finger on the home indicator

if runs T00; then
  want T00 "tablet mode is on and the home zone reserves its height" \
    "$(c henri.tablet state | jq .active),$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .reserved[3]')" "true,20"
  want T00b "with a window on the space the dock is hidden" "$(dockHidden)" "true"
  shot T00
fi

if runs T01; then
  c henri.tablet clearLog >/dev/null
  # slow pull up 60 px over ~0.5 s, hold a moment, let go
  pt m $X $B d s 80 g $X $((B - 60)) 30 16 s 60
  mid=$(dockHidden); shot T01-mid
  pt u
  want T01 "a short pull moves the dock under the finger" "$mid" "false"
  want T01b "let go past half its height, the dock stays out" "$(dockHidden)" "false"
  want T01c "no other gesture fired" "$(log | jq -r 'map(select(startswith("dock")|not)) | length')" "0"
  sleep 4.8
  want T01d "after dockHold the dock hides again" "$(dockHidden)" "true"
fi

if runs T02; then
  pt m $X $B d s 80 g $X $((B - 18)) 6 16 s 40 u
  sleep 0.5
  want T02 "a pull that stays low lets the dock go back" "$(dockHidden)" "true"
fi

if runs T03; then
  c henri.tablet clearLog >/dev/null
  pt m $X $B d s 60 g $X $((B - 260)) 8 10 u
  sleep 0.9; shot T03
  want T03 "a flick up goes home (Mission Control)" "$(layer mission-control),$(log | jq -r '.[-1]')" "true,home"
  want T03b "the dock went back" "$(dockHidden)" "true"
  hyprctl dispatch 'hl.dsp.event("mission-control hide")' >/dev/null; sleep 0.6
fi

if runs T04; then
  c henri.tablet clearLog >/dev/null
  # up 170 px at a normal pace, then the finger rests
  pt m $X $B d s 60 g $X $((B - 170)) 20 16 s 450
  shot T04-hold
  mid=$(log | jq -r 'index("switcher:start") != null')
  pt g $X $((B - 230)) 6 16 s 60 u
  sleep 1; shot T04
  want T04 "pull up and pause opens the App Switcher" "$mid" "true"
  want T04b "Mission Control is up after release" "$(layer mission-control)" "true"
  want T04c "nothing went home" "$(log | jq -r 'index("home") == null')" "true"
  hyprctl dispatch 'hl.dsp.event("mission-control toggle")' >/dev/null; sleep 0.8
fi

if runs T05; then
  # two workspaces with a window each, both on TB (m±1 only walks the monitor's own)
  for n in 11 12; do
    hyprctl dispatch "hl.dsp.focus({ monitor = 'TB' })" >/dev/null
    hyprctl dispatch "hl.dsp.focus({ workspace = '$n' })" >/dev/null; sleep 0.3
    [[ $(hyprctl activeworkspace -j | jq .windows) == 0 ]] && { hyprctl dispatch "hl.dsp.exec_cmd('foot')" >/dev/null; sleep 1.2; }
  done
  hyprctl dispatch "hl.dsp.focus({ workspace = '11' })" >/dev/null; sleep 0.5
  before=$(ws)
  pt m $((X + 100)) $B d s 60 g $((X - 120)) $B 16 16 s 40 u
  sleep 0.5; a=$(ws)
  pt m $((X - 100)) $B d s 60 g $((X + 120)) $B 16 16 s 40 u
  sleep 0.5; b=$(ws)
  want T05 "slide left along the edge: next app" "$before,$a" "11,12"
  want T05b "slide right: previous app" "$b" "11"
fi

if runs T06; then
  # top edge, right third: Control Center follows the finger
  pt m $((W - 200)) 12 d s 60 g $((W - 200)) 140 20 16 s 60
  mid=$(c henri.control-center-v3 state | jq -c '[.open, .shown]'); shot T06-mid
  pt g $((W - 200)) 260 8 16 s 30 u
  sleep 0.7; shot T06
  want T06 "pulling the right of the bar grows the island before release" "$mid" "[false,true]"
  want T06b "released far enough, Control Center is open" "$(c henri.control-center-v3 state | jq .open)" "true"
  c henri.control-center-v3 close; sleep 0.6
fi

if runs T07; then
  pt m 200 12 d s 60 g 200 160 20 16 s 60
  shot T07-mid
  pt g 200 420 10 16 s 30 u
  sleep 0.8; shot T07
  want T07 "pulling the left of the bar opens Notification Center" "$(c omarchy.clock centerState | jq .opened 2>/dev/null || c omarchy.clock centerState)" "true"
  c omarchy.clock close; sleep 0.8
fi

if runs T08; then
  # a plain tap on the island still opens Control Center (the drag handler never takes a tap)
  cx=$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .width / 2')
  pt m $cx 14 d s 70 u
  sleep 0.7
  want T08 "a tap on the island still opens Control Center" "$(c henri.control-center-v3 state | jq .open)" "true"
  c henri.control-center-v3 close; sleep 0.6
fi

if runs T09; then
  pt m 200 12 d s 60 g 200 30 6 16 s 30 g 200 14 6 16 u
  sleep 0.7
  want T09 "a short pull down and back leaves Notification Center shut" "$(c omarchy.clock centerState | jq .opened 2>/dev/null)" "false"
fi

echo "passed $pass, failed $fail${failed:+ (${failed[*]})}"
[[ ${KEEP:-} ]] || rig/rig.sh stop >/dev/null
[[ $fail == 0 ]]
