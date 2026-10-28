#!/bin/bash
# End-to-end tests for tablet mode's home screen and home gesture (Home.qml), in the tablet rig of
# tests/e2e.sh (nested Hyprland, headless output TB, virtual pointer standing in for a finger).
#   tests/home-e2e.sh        every case      tests/home-e2e.sh H3    only H3…
#   KEEP=1 …                  leave the rig running; shots in rig/state/tablet/home-*.png
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export VELUM_RIG_ID=tablet VELUM_TOUCH=1 VELUM_TABLET_LAUNCH=1
export VELUM_EDGE_SOCKET=$PWD/rig/state/tablet/edge.sock
export VELUM_RIG_PLUGINS="henri.bar-v3 henri.control-center-v3 henri.clock-v3 henri.power-v3 henri.dock-v3 henri.tablet-v3 henri.menu-v3"
R=rig/state/tablet
FILTER=${1:-}
W=1440 H=960
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
rig/rig.sh shell >/dev/null
for _ in $(seq 20); do sleep 0.5; [[ $(rig/rig.sh call henri.tablet state 2>/dev/null) == *'"active":true'* ]] && break; done

c() { rig/rig.sh call "$@" 2>/dev/null; }
pt() { WAYLAND_DISPLAY=$NWL "$vptr/vptr" TB $W $H "$@"; sleep 0.3; }
shot() { WAYLAND_DISPLAY=$NWL timeout 5 grim -o TB "$R/home-$1.png" 2>/dev/null; }
layer() { hyprctl layers -j | jq -e --arg n "$1" '[.. | objects | select(.namespace? == $n)] | length > 0' >/dev/null && echo true || echo false; }
hm() { c henri.tablet home; }
# a finger on the bottom edge as the cast hands it in (velum-edge), for gestures that start on the
# home screen: there the virtual pointer loses its focus to the layer under it halfway up
edge() { hyprctl dispatch "hl.dsp.event(\"velum-edge TB bottom $1 $2 $3\")" >/dev/null; }
edgePull() {   # edgePull TRAVEL MS REST_MS
  local y=$((H - 6)) n=$(( $2 / 16 )) i
  edge down $X $y
  for ((i = 1; i <= n; i++)); do edge move $X $((y - $1 * i / n)); sleep 0.016; done
  sleep "$(echo "scale=3; $3 / 1000" | bc)"
  edge up $X $((y - $1))
}
wsEmpty() { local id; id=$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .activeWorkspace.id'); hyprctl workspaces -j | jq --argjson i "$id" '[.[] | select(.id == $i) | .windows] | (.[0] // 0) == 0'; }
pass=0 fail=0 failed=()
want() {
  [[ -n $FILTER && $1 != $FILTER* ]] && return
  if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-6s %s\n' "$1" "$2"
  else fail=$((fail + 1)); failed+=("$1"); printf '  FAIL  %-6s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; shot "FAIL-$1"; fi
}
runs() { [[ -z $FILTER || $1 == $FILTER* ]]; }

# three apps, one per workspace (tablet.lua moves each new one to a free workspace)
n=$(hyprctl clients -j | jq 'length')
for i in $(seq $((n + 1)) 3); do hyprctl dispatch "hl.dsp.exec_cmd('foot -T app$i')" >/dev/null; sleep 1.2; done
sleep 1
# one app per workspace on TB (11, 12, 13), as tablet.lua keeps it (the nested config does not load it)
i=0
for a in $(hyprctl clients -j | jq -r 'sort_by(.address) | .[].address'); do
  i=$((i + 1)); hyprctl dispatch "hl.dsp.window.move({ workspace = '1$i', follow = false, window = 'address:$a' })" >/dev/null
done
sleep 0.5
# and fullscreen, as tablet.lua makes every app
for a in $(hyprctl clients -j | jq -r '.[] | select(.fullscreen == 0) | .address'); do
  hyprctl dispatch "hl.dsp.window.fullscreen({ mode = 'fullscreen', window = 'address:$a' })" >/dev/null
done
sleep 0.5
# start on an app, not on the home screen a previous run left
a=$(hyprctl clients -j | jq -r '.[0].address')
hyprctl dispatch "hl.dsp.focus({ window = 'address:$a' })" >/dev/null; sleep 1.2
X=$((W / 2)) B=$((H - 8))

if runs H1; then
  c henri.tablet clearLog >/dev/null
  # up at a steady pace without stopping, let go: home
  ws0=$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .activeWorkspace.id')
  pt m $X $B d s 80 g $X $((B - 420)) 16 12 u
  sleep 1.4; shot H1-home
  want H1a "TB itself moved to an empty workspace" "$(hyprctl monitors -j | jq --argjson w "$ws0" '.[] | select(.name=="TB") | .activeWorkspace.id != $w')" "true"
  want H1 "a steady swipe up: the home screen, an empty workspace" "$(hm | jq -r .mode),$(wsEmpty),$(layer velum-home-screen)" "home,true,true"
  want H1b "the card went into its icon (no switcher on the way)" "$(hm | jq -r '.log | map(select(. == "armed")) | length')" "0"
fi

if runs H2; then
  # up and rest: the App Switcher (from the home screen a pull is enough)
  edgePull 260 220 300
  sleep 1; shot H2-switcher
  want H2 "from home, a pull opens the App Switcher" "$(hm | jq -r '.mode + "," + (.cards | length | tostring)')" "switcher,3"
fi

if runs H3; then
  # tap the newest card (right): it opens, the overlay lets go
  cx=$(hm | jq -r '.area[0]'); pt m $((W / 2 + 300)) $((H / 2)) d s 60 u
  sleep 1.4; shot H3-open
  want H3 "a tap on a card opens its app" "$(hm | jq -r .mode),$(wsEmpty)" "idle,false"
fi

if runs H4; then
  # from an app: up and pause → switcher, swipe the centre-ish card up → closed
  pt m $X $B d s 80 g $X $((B - 220)) 12 16 s 350
  shot H4-armed
  pt u; sleep 1; shot H4-switcher
  before=$(hyprctl clients -j | jq 'length')
  pt m $((W / 2 + 300)) $((H / 2)) d s 60 g $((W / 2 + 300)) 80 8 12 u
  sleep 1.5; shot H4-closed
  want H4 "up and pause from an app: the switcher" "$(c henri.tablet home | jq -r '.log | map(select(. == "switcher")) | length > 0')" "true"
  want H4b "a card swiped up closes its app" "$(hyprctl clients -j | jq 'length')" "$((before - 1))"
fi

if runs H5; then
  # tap the background: home
  pt m 60 $((H / 2)) d s 40 u; sleep 1.4
  want H5 "a tap beside the cards goes home" "$(hm | jq -r .mode),$(wsEmpty)" "home,true"
fi

if runs H6; then
  # on the home screen: an app that is not running starts from its icon; the overlay lets go
  before=$(hyprctl clients -j | jq 'length')
  c henri.tablet homeOpen org.gnome.Papers >/dev/null
  sleep 0.4; mid=$(hm | jq -r .mode)
  sleep 3.5; shot H6-launched
  want H6 "launching: the card grows, then the overlay lets go" "$mid,$(hm | jq -r .mode)" "settle,idle"
  want H6b "the app's window is there" "$(( $(hyprctl clients -j | jq 'length') > before ))" "1"
  a=$(hyprctl clients -j | jq -r '.[] | select(.class | test("Papers"; "i")) | .address' | head -1)
  [[ $a ]] && hyprctl dispatch "hl.dsp.window.close({ window = 'address:$a' })" >/dev/null
fi

if runs H7; then
  # a stuck overlay never blocks the next finger: prepare() aborts it
  c henri.tablet homeOpen org.gnome.Papers >/dev/null; sleep 0.2
  pt m $X $B d s 40 u; sleep 0.4
  want H7 "a new finger on the indicator ends a running launch animation (or it had already let go)" "$(hm | jq -r '.log | (index("abort") != null) or (index("→ idle") != null)')" "true"
  sleep 3
  a=$(hyprctl clients -j | jq -r '.[] | select(.class | test("Papers"; "i")) | .address' | head -1)
  [[ $a ]] && hyprctl dispatch "hl.dsp.window.close({ window = 'address:$a' })" >/dev/null
fi

if runs H8; then
  # on the home screen the cards follow a slow pull and sink back when it lets go low
  pt m 60 $((H / 2)) d s 40 u; sleep 1.4          # (H5 left the home screen up)
  y=$((H - 6)); edge down $X $y
  for i in $(seq 1 6); do edge move $X $((y - 10 * i)); sleep 0.016; done
  sleep 0.1; mid=$(hm | jq -r .mode); shot H8-follow
  edge up $X $((y - 60)); sleep 0.8
  want H8 "a short pull on the home screen: the cards come under the finger, then sink back" "$mid,$(hm | jq -r .mode)" "homeDrag,home"
fi

if runs H9; then
  # from an app: arm the switcher, then pull back to the edge: the app again
  a=$(hyprctl clients -j | jq -r '[.[] | select(.monitor == ('"$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .id')"'))][0].address')
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$a' })" >/dev/null; sleep 1.2
  c henri.tablet clearLog >/dev/null
  y=$((H - 6)); edge down $X $y
  for i in $(seq 1 14); do edge move $X $((y - 14 * i)); sleep 0.016; done
  sleep 0.45
  for i in $(seq 13 -1 1); do edge move $X $((y - 14 * i)); sleep 0.016; done
  edge up $X $((y - 10)); sleep 1.8
  want H9 "armed, then pulled back down: back to the app" "$(hm | jq -r '(.log | index("armed") != null | tostring) + "," + .mode')" "true,idle"
fi

if runs H10; then
  # the fast way in: a whole swipe written to the shell's own socket, as ipadcast sends it
  a=$(hyprctl clients -j | jq -r '[.[] | select(.monitor == ('"$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .id')"'))][0].address')
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$a' })" >/dev/null; sleep 1.2
  python3 - "$VELUM_EDGE_SOCKET" $X $((H - 6)) <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); x, y = int(sys.argv[2]), int(sys.argv[3])
send = lambda p, yy: s.sendall(f"velum-edge TB bottom {p} {x} {yy}\n".encode())
send("down", y)
for i in range(1, 21): send("move", y - 18 * i); time.sleep(0.008)
send("up", y - 360); s.close()
PY
  sleep 1.4
  want H10 "a fast swipe through the edge socket goes home" "$(hm | jq -r .mode),$(c henri.tablet homeStats | jq -r '.[-1].lifts > 10')" "home,true"
fi

if runs H11; then
  # a burst of gestures of every kind, then: no errors, and the screen is not covered
  c henri.tablet clearLog >/dev/null
  python3 - "$VELUM_EDGE_SOCKET" $X $((H - 6)) <<'PY'
import socket, sys, time, random
random.seed(7)
x0, y0 = int(sys.argv[2]), int(sys.argv[3])
for n in range(24):
    s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
    send = lambda p, x, y: s.sendall(f"velum-edge TB bottom {p} {x} {y}\n".encode())
    up, dx, steps, rest = random.choice([360, 120, 220, 40]), random.choice([0, -260, 200, 30]), random.randint(3, 14), random.choice([0, 0, 0.3])
    send("down", x0, y0)
    for i in range(1, steps + 1): send("move", x0 + dx * i // steps, y0 - up * i // steps); time.sleep(0.012)
    time.sleep(rest)
    send("up", x0 + dx, y0 - up); s.close()
    time.sleep(random.choice([0.05, 0.2, 0.6]))
PY
  sleep 4
  errs=$(c henri.tablet home | jq -r '.log | map(select(startswith("error"))) | length')
  mode=$(c henri.tablet home | jq -r .mode)
  [[ $mode == switcher ]] && { pt m 30 $((H / 2)) d s 40 u; sleep 1.5; mode=$(c henri.tablet home | jq -r .mode); }
  want H11 "24 mixed gestures in a row: no errors, the overlay lets go" "$errs,$(echo "$mode" | grep -cE '^(idle|home)$')" "0,1"
fi

if runs H12; then
  # on the home screen: a flick to the left turns the page, one to the right turns it back
  [[ $(hm | jq -r .mode) == home ]] || { edgePull 360 120 0; sleep 1.5; }
  pt m 1100 450 d s 30 g 500 450 6 12 u; sleep 1
  p1=$(hm | jq -r .page)
  pt m 400 450 d s 30 g 1000 450 6 12 u; sleep 1
  # one page only (all apps fit): a flick only rubber-bands and the page stays
  if [[ $(hm | jq -r .pages) -gt 1 ]]; then want H12 "a flick turns the home screen's page and back" "$p1,$(hm | jq -r .page)" "1,0"
  else want H12 "one page: a flick leaves the page where it is" "$p1,$(hm | jq -r .page)" "0,0"; fi
fi

echo "passed $pass, failed $fail${failed:+ (${failed[*]})}"
[[ ${KEEP:-} ]] || rig/rig.sh stop >/dev/null 2>&1
[[ $fail == 0 ]]
