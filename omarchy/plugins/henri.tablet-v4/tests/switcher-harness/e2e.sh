#!/bin/bash
# Headless e2e of the App Switcher, the gesture navigation and the widgets (harness.sh): real foot windows
# in the harness's own nested Hyprland, real pointer input through the virtual pointer (vptr) where it
# matters, a synthetic finger with real timing (harness `glide`) for exact flings. Closes ONLY the rig's
# foot windows. Screenshots light and dark → shell/rig/state/v4sw/shots/.
#   e2e.sh [keep]     keep: leave the rig running afterwards
set -u
here=$(cd "$(dirname "$0")" && pwd); h=$here/harness.sh
pass=0 fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); echo "ok   $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
st() { "$h" call state; }
q() { st | jq -r "$1"; }
titles() { "$h" clients | jq -r 'length'; }

"$h" up >/dev/null || exit 1
"$h" call close; "$h" call widgets false; "$h" call picker false; "$h" call dark false
"$h" foot 4 >/dev/null; sleep 1; "$h" call refresh; sleep 0.5

# E1 open: every window as a card with its picture, newest in the middle
"$h" call open; sleep 1.2
ok "E1 four cards with pictures" '[[ $(q "[.sw.windows[] | select(.picture)] | length") == 4 && $(q .sw.centred) == 3 ]]'
"$h" shot open-light >/dev/null
# E2 fling: the row carries on and settles on a card
"$h" call glide switcher 900 480 1300 480 80 5 0; sleep 0.2; "$h" shot fling-mid >/dev/null; sleep 1.2
ok "E2 fling settles on a card further than the finger went" '[[ $(q "(.sw.target / .sw.step) as \$k | (\$k | floor) == \$k") == true && $(q ".sw.centred") -le 1 ]]'
# E3 rubber past the end, back to it after the finger rests
"$h" call glide switcher 300 480 1400 480 300 15 1500; sleep 0.9
ok "E3 rubber past the end, bounded" '[[ $(q "(.sw.offset > (.sw.step * 3)) and (.sw.offset < (.sw.step * 3 + 1440 * 0.12))") == true ]]'
sleep 1.6
ok "E3 settles back on the last card" '[[ $(q ".sw.offset == .sw.step * 3") == true ]]'
# E4 a card pushed up a little and held drops back
"$h" call glide switcher 720 480 725 380 300 12 1200; sleep 2
ok "E4 short lift drops back" '[[ $(q .sw.n) == 4 && $(titles) == 4 ]]'
# E5 flicked up: closed, the rig's foot window is gone, the gap closes
"$h" call glide switcher 720 480 725 300 60 4 0; sleep 0.12; "$h" shot close-fly >/dev/null; sleep 1
ok "E5 flick up closes the window" '[[ $(q .sw.n) == 3 && $(titles) == 3 && $(q ".log[-1]") == closeWindow* ]]'
# E6 a real pointer tap on the middle card switches to it
want=$(q '.sw.windows[.sw.centred].address')
"$h" ptr m 720 600 s 50 d s 60 u; for f in 1 2 3 4 5; do sleep 0.07; "$h" shot launch-$f >/dev/null; done; sleep 0.3
got=$(HYPRLAND_INSTANCE_SIGNATURE=$(cat "$here/../../../rig/state/v4sw/sig") hyprctl activewindow -j | jq -r .address)
ok "E6 tap switches (focus moved to $want)" '[[ $(q .open) == false && $got == "$want" ]]'
# E7 gesture navigation with the real pointer
"$h" ptr m 720 950 d g 720 750 12 16 s 300 u; sleep 0.8
ok "E7 up + rest opens the switcher" '[[ $(q .open) == true && $(q .nav.last) == switcher ]]'
"$h" ptr m 720 100 d u; sleep 0.8
ok "E8 tap beside closes" '[[ $(q .open) == false && $(q ".log[-1]") == closed ]]'
"$h" ptr m 720 950 d g 720 920 3 20 s 200 u; sleep 0.6
ok "E7 short pull sinks back" '[[ $(q .open) == false && $(q .nav.last) == back ]]'
"$h" ptr m 720 950 d g 720 750 4 10 u; sleep 0.8
ok "E7 flick without a way home = switcher" '[[ $(q .open) == true && $(q .nav.last) == switcher ]]'
"$h" call close; sleep 0.6; "$h" call widgets true; sleep 0.3
"$h" ptr m 720 950 d g 720 750 4 10 u; sleep 0.6
ok "E7 flick with a way home = home" '[[ $(q .nav.last) == home && $(q .open) == false ]]'
# E8 Escape (a key into the nested compositor only)
"$h" call open; sleep 1; "$h" ptr m 100 100
nwl=$(HYPRLAND_INSTANCE_SIGNATURE= hyprctl instances -j | jq -r --arg s "$(cat "$here/../../../rig/state/v4sw/sig")" '.[] | select(.instance==$s) | .wl_socket')
WAYLAND_DISPLAY=$nwl timeout 3 wtype -k Escape; sleep 0.6
ok "E8 Escape closes" '[[ $(q .open) == false ]]'
# entrance frames under a driven progress (as a finger brings it)
for p in 0.25 0.6; do "$h" call drive $p; sleep 0.5; "$h" shot "enter-$p" >/dev/null; done; "$h" call undrive false; sleep 0.8
# E9 widgets with real data, light and dark; the picker
"$h" call widgets true; sleep 2; "$h" shot widgets-light >/dev/null
"$h" call dark true; sleep 0.5; "$h" shot widgets-dark >/dev/null
"$h" call picker true; sleep 1.2; "$h" shot picker-dark >/dev/null
"$h" call dark false; sleep 0.4; "$h" shot picker-light >/dev/null
"$h" ptr m 270 720 d u; sleep 0.8
ok "E9 picker: a tap adds the widget and nothing else" '[[ $(q ".log[-1]") == "add battery" && $(q .picker.open) == false ]]'
"$h" call picker true; sleep 1; "$h" ptr m 720 150 d u; sleep 0.6
ok "E9 picker: a tap above the sheet closes" '[[ $(q ".log[-1]") == "picker closed" ]]'
# E10 Clear all closes every window of the rig, then the switcher; dark shot first
"$h" call widgets false; "$h" call dark true; "$h" call open; sleep 1.2; "$h" shot open-dark >/dev/null; "$h" call dark false
"$h" ptr m 720 786 d u; sleep 1.2
ok "E10 Clear all closes every window" '[[ $(titles) == 0 && $(q .open) == false ]]'
"$h" call open; sleep 1; "$h" shot empty-light >/dev/null; "$h" call close
echo "$pass passed, $fail failed — shots in $(cd "$here/../../../rig/state/v4sw/shots" && pwd)"
[[ ${1:-} == keep ]] || "$h" down >/dev/null
[[ $fail == 0 ]]
