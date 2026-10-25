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

# geometry as Layout.js places it on a 1080 px wide screen (tokens: pad 6/8, gap 7, keys 50 high)
KB=$((8 + 4 * 50 + 3 * 7 + 10))                # keyboard height
top=$((H - KB))
row() { echo $((top + 8 + $1 * 57 + 25)); }    # centre of row N

want K01 "starts hidden, no surface" "$(st | jq .shown),$(layer)" "false,false"
hyprctl dispatch 'hl.dsp.event("velum-touch TB")' >/dev/null; sleep 0.4
want K02 "a lifted finger reaches the bridge as touch" "$(sent)" "touch"
want K03 "and names the screen" "$(st | jq -r .screen)" "TB"

c omarchy.keyboard open >/dev/null; sleep 0.5
want K04 "open by hand shows the surface" "$(st | jq .shown),$(layer)" "true,true"
shot K04-letters
# q is the first key of row 0; letter width = (1080 - 12 - 10*7) / 12.5 units … take its centre
unit=$(python3 -c "print((1080 - 12 - 11 * 7) / 12.5)")
qx=$(python3 -c "print(int(6 + $unit / 2))")
pt m "$qx" "$(row 0)" d s 40 u
want K05 "a tap on q types q" "$(sent | awk -F'|' '{print $NF}')" "text q"
# shift (row 2, first key, 1.4 units of row 2) then q: capital, shift drops again
unit2=$(python3 -c "print((1080 - 12 - 10 * 7) / 11.8)")
sx=$(python3 -c "print(int(6 + 1.4 * $unit2 / 2))")
pt m "$sx" "$(row 2)" d s 40 u
want K06 "shift lights" "$(st | jq .shift)" "true"
pt m "$qx" "$(row 0)" d s 40 u
want K07 "shifted q is Q, then shift is off" "$(sent | awk -F'|' '{print $NF}'),$(st | jq .shift)" "text Q,false"
# delete: last key of row 0
pt m $((W - 30)) "$(row 0)" d s 40 u
want K08 "delete presses BackSpace" "$(sent | awk -F'|' '{print $NF}')" "key BackSpace"
# 123: first key of the bottom row
pt m 40 "$(row 3)" d s 40 u
want K09 "123 turns the page" "$(st | jq -r .page)" "numbers"
shot K09-numbers
pt m "$qx" "$(row 0)" d s 40 u
want K10 "the first key there types 1" "$(sent | awk -F'|' '{print $NF}')" "text 1"
# hide: last key of the bottom row
pt m $((W - 30)) "$(row 3)" d s 40 u
sleep 0.5
want K11 "the hide key closes it and tells the bridge" "$(st | jq .shown),$(sent | awk -F'|' '{print $NF}'),$(layer)" "false,close,false"

echo "keyboard e2e: $pass ok, $fail failed"
[[ -n ${KEEP:-} ]] || rig/rig.sh stop >/dev/null
[[ $fail == 0 ]]
