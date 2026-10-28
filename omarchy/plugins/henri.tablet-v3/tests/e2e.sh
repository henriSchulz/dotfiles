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
export VELUM_RIG_PLUGINS="henri.bar-v3 henri.control-center-v3 henri.clock-v3 henri.power-v3 henri.system-menu-v3 henri.dock-v3 henri.tablet-v3 henri.launchpad-v3 henri.missioncontrol-v3 henri.keyboard-v3 henri.menu-v3"
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
  want T01 "a short pull leaves the dock hidden (no dock pull since 2026-10-28)" "$mid" "true"
  want T01b "it ends as a lift, nothing else fired" "$(log | jq -r 'map(select(startswith("lift")|not)) | length'),$(dockHidden)" "0,true"
fi

if runs T02; then
  pt m $X $B d s 80 g $X $((B - 18)) 6 16 s 40 u
  sleep 0.5
  want T02 "a pull that stays low keeps the dock hidden" "$(dockHidden)" "true"
fi

if runs T03; then
  c henri.tablet clearLog >/dev/null
  pt m $X $B d s 60 g $X $((B - 260)) 8 10 u
  sleep 1.2; shot T03
  want T03 "a flick up goes home (tablet mode: the home screen, Home.qml)" "$(c henri.tablet home | jq -r .mode),$(log | jq -r '.[-1]')" "home,home"
  want T03b "the dock-v3 stays away in tablet mode (the home screen has its own)" "$(layer henri-dock)" "false"
  a=$(hyprctl clients -j | jq -r '[.[] | select(.monitor == ('"$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .id')"'))][0].address')
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$a' })" >/dev/null; sleep 1
fi

if runs T04; then
  c henri.tablet clearLog >/dev/null
  # up 170 px at a normal pace, then the finger rests
  pt m $X $B d s 60 g $X $((B - 170)) 20 16 s 450
  shot T04-hold
  mid=$(c henri.tablet home | jq -r '.log | index("armed") != null')
  pt g $X $((B - 230)) 6 16 s 60 u
  sleep 1; shot T04
  want T04 "pull up and pause arms the App Switcher while the finger rests" "$mid" "true"
  want T04b "the App Switcher is up after release" "$(c henri.tablet home | jq -r .mode)" "switcher"
  want T04c "nothing went home" "$(log | jq -r 'index("home") == null')" "true"
  # tap the newest card: back to that app
  pt m $((W / 2)) $((H / 2)) d s 60 u; sleep 1.2
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
  # top edge, right of every item (the battery has its own pull now): Control Center follows the finger
  pt m $((W - 50)) 12 d s 60 g $((W - 50)) 140 20 16 s 60
  mid=$(c henri.control-center-v3 state | jq -c '[.open, .shown]'); shot T06-mid
  pt g $((W - 50)) 260 8 16 s 30 u
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

if runs T10; then
  # the window bar shares the overlay layer with the Control Center and was mapped later, so it stood
  # on top of the open Control Center (Henri, 2026-10-25): an open bar folds when a surface covers the screen
  barUp() { hyprctl layers -j | jq '[.TB.levels[][] | select(.namespace == "velum-surface" and .w < 400)] | length > 0'; }
  c henri.tablet tap TB >/dev/null; sleep 0.5
  before=$(barUp)
  c henri.control-center-v3 open; sleep 0.8; shot T10
  during=$(barUp)
  c henri.control-center-v3 close; sleep 0.9
  want T10 "an open window bar folds under an open Control Center and stays folded" "$before,$during,$(barUp)" "true,false,false"
  c henri.tablet tap TB >/dev/null
  want T10b "it does not open while a surface covers the screen" "$(c henri.control-center-v3 open >/dev/null; sleep 0.8; c henri.tablet tap TB)" ""
  c henri.control-center-v3 close; sleep 0.9
fi

if runs T11; then
  # nothing on the window (Henri, 2026-10-26: a handle in its corner lay over apps' own buttons): a tap
  # on the home indicator opens the window bar above it, it folds back after surface.tablet.windowBar.hold
  barOpen() { c henri.tablet state | jq .windowBarOpen; }
  apps=$(hyprctl clients -j | jq 'length')
  folded=$(barOpen); c henri.tablet clearLog >/dev/null
  pt m $((X - 8)) $((B - 2)) s 100 m $X $B s 150 d s 60 u; sleep 0.4
  opened=$(barOpen); shot T11-open
  want T11 "a tap on the indicator opens the window bar" "$folded,$opened" "false,true"
  want T11a "the tap is no gesture" "$(log)" '["tap"]'
  want T11b "the app is still there" "$(hyprctl clients -j | jq 'length')" "$apps"
  pt d s 60 u; sleep 0.4
  want T11c "a second tap folds it" "$(barOpen)" "false"
  pt d s 60 u; sleep 4.4
  want T11d "the open bar folds back by itself" "$(barOpen)" "false"
fi

view() { c henri.tablet view; }
floating() { hyprctl activewindow -j | jq .floating; }

if runs T12; then
  # a second foot on the next workspace: a double tap goes back to where we came from
  start=$(ws); hyprctl dispatch "hl.dsp.focus({ workspace = '$((start + 1))' })" >/dev/null; sleep 0.4
  [[ $(hyprctl activewindow -j | jq -r .class) == foot ]] || { hyprctl dispatch "hl.dsp.exec_cmd('foot')" >/dev/null; sleep 1.5; }
  other=$(ws); c henri.tablet clearLog >/dev/null
  pt m $((X - 8)) $((B - 2)) s 100 m $X $B s 150 d s 50 u s 120 d s 50 u; sleep 0.6
  want T12 "a double tap goes back to the previous app" "$(ws),$(log | jq -c 'map(select(. == "doubletap"))')" "$start,[\"doubletap\"]"
  want T12b "the window bar the first tap opened is folded again" "$(c henri.tablet state | jq .windowBarOpen)" "false"
fi

if runs T13; then
  c henri.tablet clearLog >/dev/null
  pt m $X $B s 100 d s 800 u; sleep 0.6; shot T13
  want T13 "press and hold opens Spotlight" "$(log | jq -r '.[-1]'),$(layer omarchy-menu || true)" "longpress,$(layer omarchy-menu)"
  want T13b "it is no tap and no gesture" "$(log | jq -c .)" '["longpress"]'
  hyprctl dispatch 'hl.dsp.event("menu toggle root")' >/dev/null; sleep 0.5
fi

if runs T14; then
  was=$(floating)
  pt m $X $((B - 4)) s 100 d s 40 g $X $((B + 5)) 4 16 s 40 u; sleep 0.8; shot T14
  small=$(floating); w=$(hyprctl activewindow -j | jq '.size[0]')
  pt m $X $((B - 4)) s 100 d s 40 g $X $((B + 5)) 4 16 s 40 u; sleep 0.8
  want T14 "a push down floats the app in the middle, again tiles it" "$was,$small,$(floating)" "false,true,false"
  want T14b "the floating window takes floatShare of the width" "$(( w > W * 60 / 100 && w < W * 80 / 100 ))" "1"
fi

if runs T15; then
  # the finger stays down: the indicator follows, the neighbour apps show
  pt m $X $B s 100 d s 40 g $((X - 70)) $B 10 16 s 120
  during=$(view); shot T15-slide
  pt u; sleep 0.6
  want T15 "a sliding finger moves the indicator on this screen" "$(jq -r .slideScreen <<<"$during")" "TB"
  want T15b "the neighbour app beside it is known" "$(jq -r '(.neighbours.prev + .neighbours.next) | length > 0' <<<"$during")" "true"
  want T15c "it lets go at the end" "$(view | jq -r .slideScreen)" ""
fi

if runs T16; then
  # tablet mode makes every app fullscreen: the indicator stays awake there (it sleeps only over a
  # fullscreen app outside tablet mode)
  hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen" })' >/dev/null; sleep 3.6
  slept=$(view | jq .asleep); shot T16-awake
  c henri.tablet clearLog >/dev/null
  pt m $X $B s 100 d s 50 u; sleep 0.5
  want T16 "in tablet mode the indicator stays awake over a fullscreen app" "$slept" "false"
  want T16b "the first finger is a real tap (the window bar)" "$(log | jq -c .),$(c henri.tablet state | jq .windowBarOpen)" '["tap"],true'
  c henri.tablet tap TB >/dev/null; sleep 0.4
  hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen" })' >/dev/null; sleep 0.5
fi


# the open window bar's buttons, from the right: close, fullscreen, keyboard, mic, search
barButton() {                                  # barButton N → "x y" (N = 1 for close …)
  read -r lx ly lw lh <<<"$(hyprctl layers -j | jq -r '[.TB.levels[][] | select(.namespace == "velum-surface" and .w < 600)][0] | "\(.x - 2000) \(.y) \(.w) \(.h)"')"
  local room=$(( (lh - 30) / 2 ))
  echo "$(( lx + lw - room - 3 - 36 * $1 + 18 )) $(( ly + lh / 2 ))"
}
openBar() { pt m $((X - 8)) $((B - 2)) s 100 m $X $B s 150 d s 50 u; sleep 0.7; }
calls() { cat "$R/home/.cache/voxtype-stub/calls" 2>/dev/null | tr '\n' ';'; }

if runs T18; then
  openBar; read -r sx sy <<<"$(barButton 5)"
  pt m $((sx - 6)) $sy s 80 m $sx $sy s 120 d s 50 u; sleep 0.8; shot T18
  want T18 "the search button opens Spotlight and the keyboard" "$(layer omarchy-menu),$(c omarchy.keyboard state | jq .shown)" "true,true"
  hyprctl dispatch 'hl.dsp.event("menu close")' >/dev/null; c omarchy.keyboard close >/dev/null; sleep 0.5
fi

if runs T19; then
  rm -rf "$R/home/.cache/voxtype-stub"
  openBar; read -r mx my <<<"$(barButton 4)"
  pt m $((mx - 6)) $my s 80 m $mx $my s 120 d s 50 u; sleep 1
  rec="$(view | jq -r .dictateOn),$(layer velum-dictation-stop)"; shot T19-recording
  pt m $X $((H / 3)) s 100 d s 50 u; sleep 0.8
  want T19 "the mic starts a dictation, a surface waits for the next tap" "$rec" "TB,true"
  sleep 0.8; shot T19-enter
  want T19c "dictated into foot: Enter goes after the text" "$(view | jq .entered)" "1"
  want T19b "a tap anywhere ends it (voxtype record stop) and the surface goes" "$(view | jq -r .dictateOn),$(layer velum-dictation-stop),$(calls | tr ';' '\n' | grep '^record' | tr '\n' ';')" ",false,record start;record stop;"
fi

if runs T20; then
  # a pull from the top edge (as ipadcast hands it in) opens the menu-bar item above the finger
  edge() { hyprctl dispatch "hl.dsp.event(\"velum-edge TB top $1 $2 $3\")" >/dev/null; }
  pullAt() { c henri.tablet clearLog >/dev/null; edge down "$1" 2; sleep 0.1; edge move "$1" 120; sleep 0.1; edge move "$1" 260; sleep 0.1; edge up "$1" 260; sleep 1; }
  zx() { view | jq -r --arg s "$1" '.zones.TB[$s] | (.[0] + .[1]) / 2 | floor'; }
  for s in controlCenter spaces battery; do
    x=$(zx $s)
    pullAt "$x"; shot "T20-$s"
    island=$(hyprctl layers -j | jq '[.TB.levels[][] | select(.namespace == "velum-surface" and .w >= 300)] | length > 0')
    want "T20-$s" "a pull above the $s item (x $x) opens it" "$(log | jq -r '.[0]'),$island" "cast:top:$s,true"
    hyprctl dispatch 'hl.dsp.event("menu close")' >/dev/null; c henri.control-center-v3 close >/dev/null; c henri.power close >/dev/null; sleep 0.8
  done
fi

echo "passed $pass, failed $fail${failed:+ (${failed[*]})}"
[[ ${KEEP:-} ]] || rig/rig.sh stop >/dev/null
[[ $fail == 0 ]]
