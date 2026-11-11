#!/bin/bash
# End-to-end tests for removing items from the tablet home screen and putting them back
# (HomeScreen.qml: Remove from Home Screen in a grid icon's context menu, the minus badge on every
# icon, folder and widget in edit mode, the add button's menu), in the rig of tests/folders-rig.sh
# with its own state (RIG=remove): the fake HOME's home-layout.json is the seed below, never the
# live one. Apps are never launched (NO_LAUNCH). The virtual pointer stands in for a finger.
#   tests/remove-e2e.sh        every case      tests/remove-e2e.sh R3    only R3…
#   KEEP=1 …                   leave the rig running; shots in rig/state/remove/remove-*.png
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export RIG=remove NO_LAUNCH=1 VELUM_RIG_WS=${VELUM_RIG_WS:-name:velum-rig}
R=rig/state/remove
FILTER=${1:-}
rigctl() { "$here/folders-rig.sh" "$@"; }

# a known layout: the Photos widget, two apps, a folder of two, the rest after it
layout=$R/home/.local/state/velum/home-layout.json
mkdir -p "$(dirname "$layout")"
rm -f "$layout"
rigctl up >/dev/null || exit 1
cat >"$layout" <<'EOF'
{
 "order": ["widget:photos", "keepass", "localsend", "folder:t1", "signal"],
 "folders": { "t1": { "name": "Tools", "items": ["omacut", "omacalc"] } }
}
EOF
# read the seed: the shell reads home-layout.json once at its start
rigctl shell
sleep 1.5
[[ $(jq -r '.order[1]' "$layout") == keepass ]] || { echo "the seed was overwritten"; exit 1; }
export HYPRLAND_INSTANCE_SIGNATURE=$(cat $R/sig)

c() { rigctl call "$@" 2>/dev/null; }
pt() { rigctl ptr "$@"; sleep 0.3; }
shot() { rigctl shot "remove-$1" >/dev/null 2>&1; }
hm() { c henri.tablet home; }
lay() { c henri.tablet homeLayout; }
xy() { jq -r 'if . == null then "" else "\(.x | floor) \(.y | floor)" end' <<<"$1"; }
icon() { jq -r 'if . == null then "" else "\((.x + .w / 2) | floor) \((.y + .w / 2) | floor)" end' <<<"$(c henri.tablet homeIcon TB "$1")"; }
badge() { xy "$(c henri.tablet homeBadge TB "$1")"; }
row() { xy "$(c henri.tablet homeMenuRow TB "$1")"; }
tap() { pt m "$1" "$2" d s 60 u; }
pass=0 fail=0 failed=()
want() {
  [[ -n $FILTER && $1 != $FILTER* ]] && return
  if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-6s %s\n' "$1" "$2"
  else fail=$((fail + 1)); failed+=("$1"); printf '  FAIL  %-6s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; shot "FAIL-$1"; fi
}

# the home screen on TB
hyprctl dispatch "hl.dsp.focus({ workspace = 'emptynm' })" >/dev/null; sleep 1.2
c henri.tablet clearLog >/dev/null
want R0 "the seed is read: widget, apps and folder on the grid" "$(lay | jq -c '.tiles | map(select(. == "widget:photos" or . == "keepass" or . == "folder:t1")) | sort')" '["folder:t1","keepass","widget:photos"]'

# ---- the context menu of a grid icon
read -r kx ky < <(icon keepass)
pt m "$kx" "$ky" d s 650 u; sleep 0.7; shot R1-menu
want R1 "a grid icon's menu ends with Remove from Home Screen" "$(hm | jq -r .menu),$( [[ -n $(row 'Remove from Home Screen') ]] && echo yes)" "keepass,yes"
read -r rx ry < <(row 'Remove from Home Screen')
tap "$rx" "$ry"; sleep 1.6; shot R2-removed
want R2 "chosen: it leaves the grid, saved as hidden" "$(lay | jq -r '(.tiles | index("keepass") == null | tostring) + "," + (.hidden | join(" "))')" "true,keepass"
want R2b "the file has it" "$(jq -r '.hidden | join(" ")' "$layout")" "keepass"
want R2c "the saved order keeps its place" "$(jq -r '.order | index("keepass")' "$layout")" "1"

read -r dx dy < <(icon foot)
if [[ -n ${dx:-} ]]; then
  pt m "$dx" "$dy" d s 650 u; sleep 0.7
  want R3 "a dock icon's menu has no Remove row" "$(hm | jq -r .menu),$(row 'Remove from Home Screen')" "foot,"
  tap 700 400; sleep 0.7
fi

# ---- edit mode: badges
read -r lx ly < <(icon localsend)
pt m "$lx" "$ly" d s 650 u; sleep 0.7
read -r ex ey < <(row 'Edit Home Screen')
tap "$ex" "$ey"; sleep 1
shot R4-edit
want R4 "edit mode: every tile carries a badge" "$(hm | jq -r .editing),$(c henri.tablet homeBadge TB localsend | jq -r .shown),$(c henri.tablet homeBadge TB folder:t1 | jq -r .shown),$(c henri.tablet homeBadge TB widget:photos | jq -r .shown)" "true,true,true,true"
want R4b "the add button shows (something is hidden)" "$( [[ $(c henri.tablet homeAdd TB) != null ]] && echo yes)" "yes"

read -r bx by < <(badge localsend)
tap "$bx" "$by"; sleep 1.6; shot R5-badge
want R5 "a tap on the badge removes the app, edit mode stays" "$(lay | jq -r '(.tiles | index("localsend") == null | tostring) + "," + (.hidden | sort | join(" "))'),$(hm | jq -r .editing)" "true,keepass localsend,true"

read -r bx by < <(badge folder:t1)
tap "$bx" "$by"; sleep 1.6
want R6 "a folder's badge removes the folder with its apps" "$(lay | jq -r '(.tiles | index("folder:t1") == null | tostring) + "," + (.hidden | sort | join(" "))')" "true,keepass localsend omacalc omacut"

read -r bx by < <(badge widget:photos)
tap "$bx" "$by"; sleep 1.6; shot R7-widget
want R7 "the widget's badge removes the widget" "$(lay | jq -r '(.tiles | index("widget:photos") == null | tostring) + "," + (.hidden | index("widget:photos") != null | tostring)')" "true,true"

# ---- the add button puts them back
read -r ax ay < <(xy "$(c henri.tablet homeAdd TB)")
tap "$ax" "$ay"; sleep 0.8; shot R9-add
kname=$(lay | jq -r '.offer[] | select(.id == "keepass") | .name')
read -r ox oy < <(row "$kname")
want R9 "the add menu lists what was removed" "$(lay | jq -r '.offer | map(.id) | sort | join(" ")'),$( [[ -n ${ox:-} ]] && echo row)" "keepass localsend omacalc omacut widget:photos,row"
tap "$ox" "$oy"; sleep 1.4; shot R10-back
want R10 "chosen: the app is back in its old place (first, with the widget hidden)" "$(lay | jq -r '(.order[0]) + "," + (.hidden | index("keepass") == null | tostring)')" "keepass,true"

tap "$ax" "$ay"; sleep 0.8
read -r ox oy < <(row "$(lay | jq -r '.offer[] | select(.id == "omacut") | .name')")
tap "$ox" "$oy"; sleep 1.4
want R11 "an app of a removed folder goes back into that folder" "$(lay | jq -c '.folders.t1.items')" '["omacut"]'

tap "$ax" "$ay"; sleep 0.8
read -r ox oy < <(row "Photos Widget")
tap "$ox" "$oy"; sleep 1.4
want R12 "the widget comes back at the top left" "$(lay | jq -r '.order[0]')" "widget:photos"

tap "$ax" "$ay"; sleep 0.8
tap 700 450; sleep 0.8
want R13 "a tap beside the add menu closes it, edit mode stays" "$(row "$(lay | jq -r '.offer[0].name')"),$(hm | jq -r .editing)" ",true"

# a finger that moves off a badge drags the icon instead (and that drop saves the order anew:
# from here on a put-back item goes to the end, as on iPadOS)
read -r bx by < <(badge signal)
pt m "$bx" "$by" d g $((bx + 60)) $((by + 60)) 6 16 s 300 u; sleep 1.2
want R8 "a finger sliding off a badge removes nothing" "$(lay | jq -r '(.tiles | index("signal") != null | tostring) + "," + (.hidden | index("signal") == null | tostring)')" "true,true"

# ---- the open folder: its only app removed, the folder closes
c henri.tablet homeFolder folder:t1 >/dev/null; sleep 1
read -r bx by < <(badge omacut)
tap "$bx" "$by"; sleep 1.8; shot R14-folder
want R14 "the open folder's last app removed: the folder goes and closes" "$(lay | jq -r '.open + "," + (.tiles | index("folder:t1") == null | tostring)')" ",true"

c henri.tablet clearLog >/dev/null
want R15 "no error on the way" "$(rigctl log 2>/dev/null | grep -c 'henri.tablet-v3.*\(Error\|TypeError\|ReferenceError\|undefined\)')" "0"

echo "passed $pass, failed $fail${failed[*]:+: ${failed[*]}}"
[[ -n ${KEEP:-} ]] || rigctl down >/dev/null 2>&1
[[ $fail == 0 ]]
