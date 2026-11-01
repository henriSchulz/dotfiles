#!/bin/bash
# End-to-end tests for the Hyprland side of tablet mode (~/.config/hypr/tablet.lua): one app per
# workspace, the windows of one app stacked on its workspace, each filling the screen (monocle), the
# top one in fullscreen. Apps are foot windows with their own app id (foot --app-id a …). Its own nested Hyprland (VELUM_RIG_ID=tablet-hypr) with
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
app() { hyprctl dispatch "hl.dsp.exec_cmd('foot --app-id $1')" >/dev/null; sleep 1.5; }
clients() { hyprctl clients -j; }
tbsize() { hyprctl monitors -j | jq -c '.[] | select(.name=="TB") | [.width, .height]'; }

app a; app b; app c
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

# more windows of one app: on its workspace, each the screen's size, the newest on top in fullscreen
ws_a=$(clients | jq '.[] | select(.class=="a") | .workspace.id')
hyprctl dispatch "hl.dsp.focus({ workspace = '$(clients | jq '.[] | select(.class=="c") | .workspace.id')' })" >/dev/null; sleep 0.3
app a; app a
want W9 "a's new windows on a's workspace" "$(clients | jq -c '[.[] | select(.class=="a") | .workspace.id] | unique')" "[$ws_a]"
want W10 "the view follows them there" "$(hyprctl activeworkspace -j | jq .id)" "$ws_a"
want W11 "one fullscreen window there: the newest" "$(clients | jq -r --argjson w "$ws_a" '[.[] | select(.workspace.id == $w and .fullscreen != 0)] | map(.focusHistoryID) | tostring')" "[0]"
want W12 "a's windows under it fill the screen too" "$(clients | jq -c --argjson w "$ws_a" '[.[] | select(.workspace.id == $w) | .size] | unique')" "[$(tbsize)]"
want W13 "the apps keep their own workspaces" "$(clients | jq '[.[].workspace.id] | unique | length')" "3"
want W14 "b and c still in fullscreen" "$(clients | jq '[.[] | select(.class != "a" and .fullscreen == 0)] | length')" "0"
under=$(clients | jq -r --argjson w "$ws_a" '[.[] | select(.workspace.id == $w and .fullscreen == 0)][0].address')
hyprctl dispatch "hl.dsp.focus({ window = 'address:$under' })" >/dev/null; sleep 0.3
want W15 "focusing a window under it takes over the fullscreen" "$(clients | jq -r --arg a "$under" '.[] | select(.address == $a) | .fullscreen')" "2"

# switching on gathers an app's windows that were spread over workspaces
hyprctl eval 'henri_tablet.set(false)' >/dev/null; sleep 0.3
for a in $(clients | jq -r '.[] | select(.class=="a") | .address' | tail -2); do
  hyprctl dispatch "hl.dsp.window.move({ workspace = '20', follow = false, window = 'address:$a' })" >/dev/null
done
hyprctl dispatch "hl.dsp.window.move({ workspace = '20', follow = false, window = 'address:$(clients | jq -r '.[] | select(.class=="b") | .address')' })" >/dev/null
hyprctl dispatch "hl.dsp.focus({ monitor = 'TB' })" >/dev/null; sleep 0.3
hyprctl eval 'henri_tablet.set(true)' >/dev/null; sleep 0.5
want W16 "on: a gathered on one workspace" "$(clients | jq '[.[] | select(.class=="a") | .workspace.id] | unique | length')" "1"
want W17 "on: one app per workspace" "$(clients | jq '[group_by(.workspace.id)[] | map(.class) | unique | length] | max')" "1"
want W18 "on: one fullscreen window per workspace" "$(clients | jq -c '[group_by(.workspace.id)[] | map(select(.fullscreen != 0)) | length] | unique')" "[1]"
want W19 "on: every window the screen's size" "$(clients | jq -c '[.[].size] | unique')" "[$(tbsize)]"

# off: the layout and the gaps come back
hyprctl eval 'henri_tablet.set(false)' >/dev/null; sleep 0.3
want W20 "off: layout back" "$(hyprctl getoption general:layout -j | jq -r .str)" "dwindle"

# Omarchy's per-workspace layout (SUPER+L) gives way to monocle while on, and comes back off
# (off reads Omarchy's files from the live state dir: the expected layout is that file's, else dwindle)
wsc=$(clients | jq '.[] | select(.class=="c") | .workspace.id')
hyprctl eval "hl.workspace_rule({ workspace = '$wsc', layout = 'scrolling' })" >/dev/null; sleep 0.2
layout_of() { hyprctl workspaces -j | jq -r --argjson w "$1" '.[] | select(.id == $w) | .tiledLayout'; }
hyprctl eval 'henri_tablet.set(true)' >/dev/null; sleep 0.5
want W21 "on: a workspace Omarchy set to scrolling is monocle" "$(layout_of "$wsc")" "monocle"
want W22 "on: c fills the screen there" "$(clients | jq -c '[.[] | select(.class=="c") | .size] | unique')" "[$(tbsize)]"
hyprctl eval 'henri_tablet.set(false)' >/dev/null; sleep 0.3
f=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workspace-layouts/$wsc.lua
want W23 "off: Omarchy's layout of that workspace again" "$(layout_of "$wsc")" "$( [[ -f $f ]] && grep -o 'layout = "[a-z]*"' "$f" | cut -d'"' -f2 || echo dwindle)"

echo "$pass passed, $fail failed${failed[*]:+: ${failed[*]}}"
[[ -n ${KEEP:-} ]] || rig/rig.sh stop >/dev/null 2>&1
[[ $fail == 0 ]]
