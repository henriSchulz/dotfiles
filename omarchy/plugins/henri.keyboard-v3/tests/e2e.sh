#!/bin/bash
# End-to-end checks for the on-screen keyboard in its own nested rig (VELUM_RIG_ID=kb), on a headless
# output TB of the NESTED compositor with the virtual pointer (henri.launchpad-v3/tests/vptr): a click
# stands in for a finger (MultiPointTouchArea takes the mouse as a point). The rig never starts
# velum-osk (VELUM_SHELL_RIG): what the keyboard would send to it is read back from `state`.
#
#   tests/e2e.sh          every check (starts the rig if needed)
#   KEEP=1 tests/e2e.sh   leave the rig running
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export VELUM_RIG_ID=kb VELUM_RIG_PLUGINS="henri.keyboard-v3"
R=rig/state/kb
W=1080 H=720                                   # the cast screen's logical size (1620 × 1080 at scale 1.5)
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
for _ in $(seq 20); do sleep 0.5; rig/rig.sh call omarchy.keyboard state >/dev/null 2>&1 && break; done

c() { rig/rig.sh call "$@" 2>/dev/null; }
st() { c omarchy.keyboard state; }
pt() { WAYLAND_DISPLAY=$NWL "$vptr/vptr" TB $W $H "$@"; sleep 0.25; }
shot() { WAYLAND_DISPLAY=$NWL timeout 5 grim -o TB "$R/e2e-$1.png" 2>/dev/null; }
layer() { hyprctl layers -j | jq -e '[.TB.levels[][] | select(.namespace == "velum-surface" and .h < 400)] | length > 0' >/dev/null && echo true || echo false; }
pass=0 fail=0
want() { if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-4s %s\n' "$1" "$2"
         else fail=$((fail + 1)); printf '  FAIL  %-4s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; shot "FAIL-$1"; fi; }
sent() { st | jq -r '.sent | join("|")'; }

# geometry as Layout.js places it on the island (tokens: 860 wide, 14 above the edge, 28 shadow room,
# pad 10/16/10, gap 7, keys 46 high)
CARD=$((16 + 4 * 46 + 3 * 7 + 10))             # the island's height
KX=$(((W - 860) / 2))                          # its left edge
top=$((H - 14 - CARD))                         # taken again from the surface once it is up (a zone below moves it)
row() { echo $((top + 16 + $1 * 53 + 23)); }   # centre of row N

want K01 "starts hidden, no surface" "$(st | jq .shown),$(layer)" "false,false"
hyprctl dispatch 'hl.dsp.event("velum-touch TB")' >/dev/null; sleep 0.4
want K02 "a lifted finger opens nothing" "$(st | jq .shown),$(sent)" "false,"
want K03 "but names the screen" "$(st | jq -r .screen)" "TB"

hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.5
want K04 "the window bar's keyboard button opens it" "$(st | jq .shown),$(layer),$(sent)" "true,true,open"
shot K04-letters
top=$(hyprctl layers -j | jq '[.TB.levels[][] | select(.namespace == "velum-surface" and .h < 400)][0] | .y + .h - 14 - '$CARD)
# q is the second key of row 0, after tab (1.3 units): 13 keys of 13.8 units … take its centre
unit=$(python3 -c "print((860 - 20 - 12 * 7) / 13.8)")
qx=$(python3 -c "print(int($KX + 10 + 1.3 * $unit + 7 + $unit / 2))")
pt m "$qx" "$(row 0)" d s 40 u
want K05 "a tap on q types q" "$(sent | awk -F'|' '{print $NF}')" "text q"
# shift (row 2, first key, 1.4 units of row 2) then q: capital, shift drops again
unit2=$(python3 -c "print((860 - 20 - 10 * 7) / 11.8)")
sx=$(python3 -c "print(int($KX + 10 + 1.4 * $unit2 / 2))")
pt m "$sx" "$(row 2)" d s 40 u
want K06 "shift lights" "$(st | jq .shift)" "true"
pt m "$qx" "$(row 0)" d s 40 u
want K07 "shifted q is Q, then shift is off" "$(sent | awk -F'|' '{print $NF}'),$(st | jq .shift)" "text Q,false"
# delete: last key of row 0
pt m $((KX + 860 - 30)) "$(row 0)" d s 40 u
want K08 "delete presses BackSpace" "$(sent | awk -F'|' '{print $NF}')" "key BackSpace"
# tab: first key of row 0
pt m "$(python3 -c "print(int($KX + 10 + 1.3 * $unit / 2))")" "$(row 0)" d s 40 u
want K20 "tab presses Tab" "$(sent | awk -F'|' '{print $NF}')" "key Tab"
# the mic key: fifth of the bottom row (123 1.4, command 1.1, left 1, right 1 before it; 8 keys of 12.6 units)
unit3=$(python3 -c "print((860 - 20 - 7 * 7) / 12.6)")
mx=$(python3 -c "print(int($KX + 10 + 4.5 * $unit3 + 4 * 7 + $unit3 / 2))")
calls() { tail -1 "$R/home/.cache/voxtype-stub/calls" 2>/dev/null; }
pt m "$mx" "$(row 3)" d s 40 u; sleep 0.4
want K21 "the mic key starts a dictation and holds the bridge" "$(calls),$(st | jq -r .voxState),$(sent | awk -F'|' '{print $NF}')" "record start,recording,hold on"
shot K21-dictating
pt m "$mx" "$(row 3)" d s 40 u; sleep 1
want K22 "tapped again it stops; idle lets the bridge go" "$(calls),$(st | jq -r .voxState),$(sent | awk -F'|' '{print $NF}'),$(st | jq .shown)" "record stop,idle,hold off,true"
# 123: first key of the bottom row
pt m $((KX + 30)) "$(row 3)" d s 40 u
want K09 "123 turns the page" "$(st | jq -r .page)" "numbers"
shot K09-numbers
pt m "$qx" "$(row 0)" d s 40 u
want K10 "the first key there types 1" "$(sent | awk -F'|' '{print $NF}')" "text 1"
# the command key (second of the bottom row, 1.1 of 12.6 units) opens the shortcuts page
cx=$(python3 -c "print(int($KX + 10 + 1.4 * $unit3 + 7 + 1.1 * $unit3 / 2))")
pt m "$cx" "$(row 3)" d s 40 u
want K14 "the command key opens the shortcuts page" "$(st | jq -r .page)" "shortcuts"
shot K14-shortcuts
c omarchy.keyboard tap Copy >/dev/null
want K15 "Copy sends Control-C and turns back" "$(sent | awk -F'|' '{print $NF}'),$(st | jq -r .page)" "combo ctrl c,letters"
pt m "$cx" "$(row 3)" d s 40 u
c omarchy.keyboard tap mod:ctrl >/dev/null
want K16 "a latched modifier goes back to the letters" "$(st | jq -r .page),$(st | jq -c .mods)" 'letters,{"ctrl":"once"}'
shot K16-latched
pt m "$qx" "$(row 0)" d s 40 u
want K17 "the next key makes the combo, the latch lets go" "$(sent | awk -F'|' '{print $NF}'),$(st | jq -c .mods)" "combo ctrl q,{}"
pt m 30 "$(row 0)" d s 40 u
want K18 "a tap beside the island types nothing" "$(sent | awk -F'|' '{print $NF}')" "combo ctrl q"
# the grabber pulled down far enough closes it
pt m $((W / 2)) $((top + 6)) d s 40 g $((W / 2)) $((top + 90)) 12 16 s 40 u
sleep 0.5
want K19 "the grabber pulled down closes it" "$(st | jq .shown),$(sent | awk -F'|' '{print $NF}')" "false,close"
hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.5
# hide: last key of the bottom row
pt m $((KX + 860 - 30)) "$(row 3)" d s 40 u
sleep 0.5
want K11 "the hide key closes it and tells the bridge" "$(st | jq .shown),$(sent | awk -F'|' '{print $NF}'),$(layer)" "false,close,false"
hyprctl dispatch 'hl.dsp.event("velum-touch TB")' >/dev/null; sleep 0.5
want K12 "a finger after closing does not bring it back" "$(st | jq .shown),$(layer)" "false,false"
hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.4
hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.5
want K13 "the button toggles: open, then closed again" "$(st | jq .shown),$(sent | awk -F'|' '{print $NF}')" "false,close"

echo "keyboard e2e: $pass ok, $fail failed"
[[ -n ${KEEP:-} ]] || rig/rig.sh stop >/dev/null
[[ $fail == 0 ]]
