#!/bin/bash
# The on-screen keyboard goes by itself (Keyboard.qml, "going by itself"): another window takes the
# focus, its screen shows another workspace, Spotlight (henri.menu-v3, in the rig too) closes when the
# keyboard came with it. Its own nested rig (VELUM_RIG_ID=kbclose, beside e2e.sh's kb) with a headless
# output TB and the rig's own output as a second screen; windows are foot with their own app id. The rig never starts velum-osk:
# what the keyboard would send is read back from `state`.
#
#   tests/autoclose-e2e.sh          every check (starts the rig if needed)
#   KEEP=1 tests/autoclose-e2e.sh   leave the rig running
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export VELUM_RIG_ID=kbclose VELUM_RIG_PLUGINS="henri.keyboard-v3 henri.menu-v3"
R=rig/state/kbclose
# the live tablet-v3 the rig shell also loads would take the live shell's edge socket
mkdir -p $R && export VELUM_EDGE_SOCKET=$PWD/$R/edge.sock

sig() { cat $R/sig 2>/dev/null; }
up() { [[ -n $(sig) ]] && HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl version >/dev/null 2>&1; }
if ! up; then rig/rig.sh start >/dev/null || exit 1; fi
rig/rig.sh sync >/dev/null
# the rig's copies take THIS checkout's Velum module (the plugins import it by an absolute path, which
# is the live checkout)
for p in $VELUM_RIG_PLUGINS; do
  d=$R/home/.config/omarchy/plugins/$p
  [[ -d $d && ! -L $d ]] && grep -rl "file:///home/henri/.local/share/velum" "$d" --include=*.qml --include=*.js | xargs -r sed -i "s|file:///home/henri/.local/share/velum|file://$(dirname "$shell")|g"
done
export HYPRLAND_INSTANCE_SIGNATURE=$(sig)
hyprctl monitors -j | jq -e '.[] | select(.name=="TB")' >/dev/null || hyprctl output create headless TB >/dev/null
sleep 0.5
hyprctl eval "hl.monitor({ output = 'TB', mode = '1080x720@60', position = '2000x0', scale = 1 })" >/dev/null
OTHER=$(hyprctl monitors -j | jq -r '[.[] | select(.name != "TB")][0].name')
d() { hyprctl dispatch "$1" >/dev/null; sleep 0.6; }
d "hl.dsp.focus({ monitor = 'TB' })"
d "hl.dsp.focus({ workspace = '21' })"
rig/rig.sh shell >/dev/null
for _ in $(seq 20); do sleep 0.5; rig/rig.sh call omarchy.keyboard state >/dev/null 2>&1 && break; done

st() { rig/rig.sh call omarchy.keyboard state 2>/dev/null; }
shown() { st | jq -r .shown; }
ev() { d "hl.dsp.event(\"$1\")"; }
app() { d "hl.dsp.exec_cmd('foot --app-id $1')"; sleep 1; }
focusapp() { d "hl.dsp.focus({ window = 'class:$1' })"; }
openkb() { ev "velum-keyboard toggle TB"; }
pass=0 fail=0
want() { if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-4s %s\n' "$1" "$2"
         else fail=$((fail + 1)); printf '  FAIL  %-4s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; fi; }

app kca
openkb
want C01 "opened over a window" "$(shown)" "true"
ev "velum-touch TB"
want C02 "a finger lifted in the same window keeps it" "$(shown)" "true"
app kcb
want C03 "another window takes the focus: it goes" "$(shown),$(st | jq -r '.sent[-1]')" "false,close"

openkb
focusapp kcb
want C04 "the same window focused again keeps it" "$(shown)" "true"
d "hl.dsp.focus({ workspace = '22' })"
want C05 "its screen shows another workspace: it goes" "$(shown)" "false"

d "hl.dsp.focus({ workspace = '21' })"
focusapp kca
openkb
d "hl.dsp.focus({ monitor = '$OTHER' })"
d "hl.dsp.focus({ workspace = '23' })"
d "hl.dsp.focus({ monitor = 'TB' })"
want C06 "another workspace on the other screen and back: it stays" "$(shown)" "true"

ev "velum-menu hidden"
want C07 "Spotlight closing keeps a keyboard opened by its own button" "$(shown)" "true"
openkb
ev "velum-keyboard open TB"
want C08 "the window bar's search opens it" "$(shown)" "true"
ev "velum-menu hidden"
want C09 "Spotlight closing takes the keyboard that came with it" "$(shown)" "false"

ev "menu summon root"; sleep 0.5
ev "velum-keyboard open TB"
want C10 "Spotlight and the keyboard from the search button" "$(shown),$(hyprctl layers -j | jq '[.[].levels[][] | select(.namespace | test("menu|spotlight"; "i"))] | length > 0')" "true,true"
ev "menu close"; sleep 0.5
want C11 "the real Spotlight closing takes it too" "$(shown)" "false"

for a in kca kcb; do d "hl.dsp.window.close({ window = 'class:$a' })"; done
echo "pass $pass  fail $fail"
[[ ${KEEP:-} ]] || rig/rig.sh stop >/dev/null
[[ $fail == 0 ]]
