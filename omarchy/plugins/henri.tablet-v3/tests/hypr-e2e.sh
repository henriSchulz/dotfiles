#!/bin/bash
# End-to-end tests for the Hyprland side of tablet mode (~/.config/hypr/tablet.lua): one app per
# workspace, every app in fullscreen. Its own nested Hyprland (VELUM_RIG_ID=tablet-hypr) with
# tablet.lua loaded through VELUM_HYPR and no shell; two outputs, so a window that lands on the
# wrong screen shows. The mode is switched with henri_tablet.set() in the nested compositor only.
#   tests/hypr-e2e.sh        every case      tests/hypr-e2e.sh W2    only W2…
#   KEEP=1 …                 leave the nested Hyprland running
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export VELUM_RIG_ID=tablet-hypr
R=rig/state/$VELUM_RIG_ID
FILTER=${1:-}
mkdir -p "$R"
echo "dofile(os.getenv('HOME') .. '/.config/hypr/tablet.lua')" > "$R/tablet-hypr.lua"
export VELUM_HYPR=$PWD/$R/tablet-hypr.lua
rig/rig.sh stop >/dev/null 2>&1
rig/rig.sh start >/dev/null || exit 1
export HYPRLAND_INSTANCE_SIGNATURE=$(cat "$R/sig")
hyprctl output create headless TB >/dev/null
sleep 0.5
hyprctl eval "hl.monitor({ output = 'TB', mode = '1440x960@60', position = '2000x0', scale = 1 })" >/dev/null
hyprctl dispatch "hl.dsp.focus({ monitor = 'TB' })" >/dev/null
hyprctl eval 'henri_tablet.set(true)' >/dev/null

pass=0 fail=0 failed=()
want() {                                       # want CASE "description" ACTUAL EXPECTED
  [[ -n $FILTER && $1 != $FILTER* ]] && return
  if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-6s %s\n' "$1" "$2"
  else fail=$((fail + 1)); failed+=("$1"); printf '  FAIL  %-6s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; fi
}
foot() { hyprctl dispatch "hl.dsp.exec_cmd('foot')" >/dev/null; sleep 1.5; }
clients() { hyprctl clients -j; }

foot; foot; foot
want W1 "three apps, three workspaces" "$(clients | jq '[.[].workspace.id] | unique | length')" "3"
want W2 "every app in fullscreen, also the ones a new window came over" "$(clients | jq '[.[] | select(.fullscreen == 0)] | length')" "0"
tb=$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .id')
want W3 "all on TB (not on the other screen's empty workspace 1)" "$(clients | jq --argjson m "$tb" '[.[] | select(.monitor != $m)] | length')" "0"
want W4 "the view follows the newest app" "$(hyprctl activeworkspace -j | jq .id)" "$(clients | jq 'min_by(.focusHistoryID) | .workspace.id')"

# switching on spreads windows that share a workspace, on their own screen
hyprctl eval 'henri_tablet.set(false)' >/dev/null; sleep 0.3
first=$(clients | jq '[.[].workspace.id] | min')
for a in $(clients | jq -r --argjson f "$first" '.[] | select(.workspace.id != $f) | .address'); do
  hyprctl dispatch "hl.dsp.window.move({ workspace = '$first', follow = false, window = 'address:$a' })" >/dev/null
done
hyprctl dispatch "hl.dsp.focus({ monitor = 'WAYLAND-1' })" >/dev/null; sleep 0.3
want W5 "off: all three share a workspace" "$(clients | jq '[.[].workspace.id] | unique | length')" "1"
hyprctl eval 'henri_tablet.set(true)' >/dev/null; sleep 0.5
want W6 "on: spread to three workspaces" "$(clients | jq '[.[].workspace.id] | unique | length')" "3"
want W7 "spread keeps them on TB, though the other screen has focus" "$(clients | jq --argjson m "$tb" '[.[] | select(.monitor != $m)] | length')" "0"
want W8 "spread: all in fullscreen" "$(clients | jq '[.[] | select(.fullscreen == 0)] | length')" "0"

echo "$pass passed, $fail failed${failed[*]:+: ${failed[*]}}"
[[ -n ${KEEP:-} ]] || rig/rig.sh stop >/dev/null 2>&1
[[ $fail == 0 ]]
