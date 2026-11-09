#!/bin/bash
# The on-screen keyboard comes by itself in tablet mode (Keyboard.qml, "coming by itself"): a finger
# lifted ("velum-touch") and a text field focused ("focus in" from the bridge) within autoPair of each
# other open it; a terminal, a mouse (no finger) and the window it was put away in do not; a field
# that loses the focus without another taking it within refocus closes it again. Its own nested rig
# (VELUM_RIG_ID=kbauto, VELUM_TOUCH=1) on a headless output TB; windows are foot with their own app
# id. The rig has no bridge: its lines come in through the IPC `bridgeSays`, what the keyboard would
# send to it is read back from `state`.
#
#   tests/autoopen-e2e.sh          every check (starts the rig if needed)
#   KEEP=1 tests/autoopen-e2e.sh   leave the rig running
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export VELUM_RIG_ID=kbauto VELUM_RIG_PLUGINS="henri.keyboard-v3" VELUM_TOUCH=1
R=rig/state/kbauto
# the live tablet-v3 the rig shell also loads would take the live shell's edge socket
mkdir -p $R && export VELUM_EDGE_SOCKET=$PWD/$R/edge.sock

sig() { cat $R/sig 2>/dev/null; }
up() { [[ -n $(sig) ]] && HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl version >/dev/null 2>&1; }
if ! up; then rig/rig.sh start >/dev/null || exit 1; fi
rig/rig.sh sync >/dev/null
export HYPRLAND_INSTANCE_SIGNATURE=$(sig)
hyprctl monitors -j | jq -e '.[] | select(.name=="TB")' >/dev/null || hyprctl output create headless TB >/dev/null
sleep 0.5
hyprctl eval "hl.monitor({ output = 'TB', mode = '1080x720@60', position = '2000x0', scale = 1 })" >/dev/null
d() { hyprctl dispatch "$1" >/dev/null; sleep 0.6; }
d "hl.dsp.focus({ monitor = 'TB' })"
d "hl.dsp.focus({ workspace = '31' })"
rig/rig.sh shell >/dev/null
for _ in $(seq 20); do sleep 0.5; rig/rig.sh call omarchy.keyboard state >/dev/null 2>&1 && break; done

c() { rig/rig.sh call omarchy.keyboard "$@" 2>/dev/null; }
st() { c state; }
shown() { st | jq -r .shown; }
says() { c bridgeSays "$1" >/dev/null; }
lift() { hyprctl dispatch 'hl.dsp.event("velum-touch TB")' >/dev/null; }
tap() { lift; says "focus in"; sleep 0.4; }     # a finger into a field: lift, then the focus
app() { d "hl.dsp.exec_cmd('foot --app-id $1')"; sleep 1; }
focusapp() { d "hl.dsp.focus({ window = 'class:$1' })"; }
last() { st | jq -r '.sent[-1] // ""'; }
pass=0 fail=0
want() { if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-4s %s\n' "$1" "$2"
         else fail=$((fail + 1)); printf '  FAIL  %-4s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; fi; }

want A01 "tablet mode arms fcitx5 at the start" "$(st | jq -r '.sent | index("arm") != null')" "true"
app kaa
tap
want A02 "a finger's tap into a field opens it" "$(shown),$(st | jq -r .auto),$(last)" "true,true,open"
says "focus out"; sleep 0.1; says "focus in"; sleep 0.5
want A03 "the focus going to another field keeps it" "$(shown)" "true"
says "focus out"; sleep 0.6
want A04 "the field losing the focus closes it" "$(shown),$(last)" "false,close"

says "focus in"; sleep 0.4
want A05 "a field focused without a finger (a mouse click) opens nothing" "$(shown)" "false"
lift; sleep 0.7; says "focus in"; sleep 0.4
want A06 "a finger long before the focus opens nothing" "$(shown)" "false"
says "focus in"; lift; sleep 0.4
want A07 "the lift may come after the focus" "$(shown)" "true"

c close >/dev/null; sleep 0.3
tap
want A08 "put away by hand: not again in this window" "$(shown),$(st | jq -r .dismissed)" "false,true"
app kab
tap
want A09 "another window: it comes again" "$(shown),$(st | jq -r .dismissed)" "true,false"
hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.4   # it was up: put away
hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.4   # and opened by hand
says "focus out"; sleep 0.6
want A10 "opened by hand it stays when the field loses the focus" "$(shown)" "true"
c close >/dev/null; sleep 0.3

app foot
tap
want A11 "never in a terminal" "$(shown),$(st | jq -r .terminal)" "false,true"
says "mode physical"; sleep 0.2
want A12 "a real key: fcitx5 left on-screen-keyboard mode" "$(st | jq -r .osk)" "false"
focusapp kab
lift; says "focus in"; sleep 0.4      # the bridge answers "arm" at once with the field it finds focused
want A13 "after a real key a finger arms fcitx5 again" "$(st | jq -r '.sent[-2:] | join(",")')" "arm,open"
want A14 "and the field it found focused opens the keyboard" "$(shown)" "true"

for a in kaa kab foot; do d "hl.dsp.window.close({ window = 'class:$a' })"; done
echo "pass $pass  fail $fail"
[[ ${KEEP:-} ]] || rig/rig.sh stop >/dev/null
[[ $fail == 0 ]]
