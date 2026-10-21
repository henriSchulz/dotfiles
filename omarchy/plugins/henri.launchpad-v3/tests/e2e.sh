#!/bin/bash
# End-to-end tests for henri.launchpad-v3 in its own nested rig, with real input:
# keys through wtype and a virtual pointer (tests/vptr), both on the NESTED
# compositor's socket — never the live session. Assertions read the plugin's
# `state` / `layoutJson` calls. Inside the rig, launches are recorded, not run.
#
#   tests/e2e.sh            run every case (starts the rig if needed)
#   tests/e2e.sh F03        only cases whose id starts with F03
#   KEEP=1 tests/e2e.sh     leave the rig running afterwards
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export VELUM_RIG_ID=launchpad VELUM_RIG_PLUGINS="henri.launchpad-v3"
R=rig/state/launchpad
F=$R/home/.config/omarchy
FILTER=${1:-}
W=1920 H=1080
out=~/Projects/launchpad/replica/clone-screens/test; mkdir -p "$out"

[[ -x $here/vptr/vptr ]] || "$here/vptr/build.sh"

# ---- rig ---------------------------------------------------------------
sig() { cat $R/sig 2>/dev/null; }
up() { [[ -n $(sig) ]] && HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl version >/dev/null 2>&1; }
if ! up; then rig/rig.sh start >/dev/null || exit 1; fi
rig/rig.sh sync >/dev/null
export HYPRLAND_INSTANCE_SIGNATURE=$(sig)
NWL=$(hyprctl instances -j | jq -r --arg s "$HYPRLAND_INSTANCE_SIGNATURE" '.[] | select(.instance==$s) | .wl_socket')
hyprctl monitors -j | jq -e '.[] | select(.name=="LP")' >/dev/null || hyprctl output create headless LP >/dev/null
sleep 0.5
hyprctl monitors -j | jq -e '.[] | select(.name=="LP" and .width==1920)' >/dev/null || { echo "no LP output"; exit 1; }

fresh() {                      # clean layout, plugin copied in, shell restarted
  rm -rf "$F/launchpad"
  "$here/rig-reload.sh" >/dev/null
}
c() { rig/rig.sh call shell call henri.launchpad-v3 "$@" 2>/dev/null; }
st() { c state ""; }
lay() { c layoutJson ""; }
open() { rig/rig.sh call shell summon henri.launchpad-v3 "{\"screen\":\"LP\"$1}" >/dev/null; sleep 0.7; }
shut() { rig/rig.sh call shell hide henri.launchpad-v3 >/dev/null; sleep 0.4; }
key() { WAYLAND_DISPLAY=$NWL wtype "$@"; sleep 0.25; }
pt() { WAYLAND_DISPLAY=$NWL "$here/vptr/vptr" LP $W $H "$@"; sleep 0.25; }
at() { c tileCenter "$1"; }
shot() { HYPRLAND_INSTANCE_SIGNATURE=$(sig) WAYLAND_DISPLAY=$NWL timeout 5 grim -o LP "$out/$1.png" 2>/dev/null; }
pageItem() { lay | jq -r --argjson p "$1" --argjson i "$2" '.pages[$p][$i]'; }

pass=0 fail=0 skip=0 failed=()
want() {                       # want CASE "description" JQ-EXPR [json]
  local id=$1 desc=$2 expr=$3 json=${4:-$(st)}
  if [[ -n $FILTER && $id != $FILTER* ]]; then return; fi
  if jq -e "$expr" >/dev/null 2>&1 <<<"$json"; then pass=$((pass + 1)); printf '  ok    %-8s %s\n' "$id" "$desc"
  else fail=$((fail + 1)); failed+=("$id"); printf '  FAIL  %-8s %s\n        got: %s\n' "$id" "$desc" "$(head -c 400 <<<"$json")"; shot "FAIL-$id"; fi
}
runs() { [[ -z $FILTER || $1 == $FILTER* ]]; }

fresh

# ---- F01 launch by clicking -------------------------------------------
if runs F01; then
  open ""
  a=$(pageItem 0 2); read -r x y <<<"$(at "$a")"
  pt m "$x" "$y" d s 60 u; sleep 0.5
  want F01-H1 "click an app launches it and closes" ".lastLaunch == \"$a\" and .opened == false"
  open ""
  pt m 960 1000 w 1 1 0; sleep 0.6
  want F01-E1 "mouse wheel down turns to page 2" '.page == 1'
  b=$(pageItem 1 0); read -r x y <<<"$(at "$b")"
  pt m "$x" "$y" d s 60 u; sleep 0.5
  want F01-E2 "click an app on page 2 launches it" ".lastLaunch == \"$b\""
  open ""
  pt m 960 1000 w -1 1 0; sleep 0.6
  want F01-E3 "wheel up goes back to page 1" '.page == 0'
  pt m 960 1000 f 900 0 12 12; sleep 0.8
  p1=$(st | jq .page)
  pt m 960 1000 f -900 0 12 12; sleep 0.8
  p2=$(st | jq .page)
  want F01-E4 "two-finger swipe turns the page and back" '.p1 == 1 and .p2 == 0' "{\"p1\":$p1,\"p2\":$p2}"
  pt m 1100 1000 d g 300 1000 10 10 u; sleep 0.8
  want F01-E5 "dragging the empty background turns the page" '.page == 1'
  pt m 300 1000 d g 1700 1000 10 10 u; sleep 0.8
  want F01-E6 "drag back returns to page 1" '.page == 0'
  pt m 100 500 d g 1800 500 10 10 u; sleep 0.8
  want F01-E7 "rubber band: no page before the first" '.page == 0'
  shut
fi

# ---- F02 launch by typing ---------------------------------------------
if runs F02; then
  open ""
  key "chrom"
  want F02-H1 "typing searches" '.query == "chrom" and .results >= 1 and .selected == 0'
  shot F02-search
  key -k Return; sleep 0.5
  want F02-H2 "Enter launches the first result" '.lastLaunch == "app:chromium" and .opened == false'
  open ""
  key "zzqxv"
  want F02-E1 "no match shows no results" '.results == 0'
  key -k Escape
  want F02-E2 "Esc clears the query first" '.query == "" and .opened == true'
  key "o"
  key -k Down
  want F02-E3 "arrow down moves the selection" '.selected == 1'
  key -k BackSpace
  key "é😀"
  want F02-E4 "accents and emoji do not break search" '.opened == true and (.results | type == "number")'
  key -k Escape; key -k Escape
  want F02-E5 "second Esc closes" '.opened == false'
  open ',"query":"brow"'
  want F02-E6 "payload query opens with a search" '.query == "brow" and .results >= 1'
  shut
fi

# ---- F07 close without launching --------------------------------------
if runs F07; then
  fresh; open ""
  pt m 960 1060 d s 50 u; sleep 0.5
  want F07-H1 "click on empty space closes" '.opened == false and .lastLaunch == ""'
  open ""
  key -k Escape; sleep 0.3
  want F07-H2 "Esc closes" '.opened == false'
  open ""
  want F07-E1 "reopening starts clean" '.query == "" and .editing == false and .folder == "" and .selected == -1'
  shut
fi

# ---- keyboard grid navigation -----------------------------------------
if runs K01; then
  open ""
  key -k Right; key -k Right; key -k Right
  want K01-H1 "arrows select tiles" '.selected == 2'
  key -k Down
  want K01-H2 "down moves one row" '.selected == 9'
  for _ in $(seq 30); do WAYLAND_DISPLAY=$NWL wtype -k Right; done; sleep 0.3
  want K01-E1 "right past the page end goes to the next page" '.page == 1'
  key -k Return; sleep 0.4
  want K01-H3 "Enter launches the selected app" '.lastLaunch != "" and .opened == false'
  shut
fi

# ---- F03 folders ------------------------------------------------------
if runs F03; then
  fresh; open ""
  a=$(pageItem 0 0); b=$(pageItem 0 3)
  read -r ax ay <<<"$(at "$a")"; read -r bx by <<<"$(at "$b")"
  pt m "$ax" "$ay" d s 700
  want F03-H1 "long press enters edit mode and picks the app up" ".editing == true and .dragId == \"$a\""
  pt g "$bx" "$by" 12 15 s 650
  want F03-H2 "holding over another app arms a folder" ".armed == \"$b\""
  shot F03-armed
  pt u; sleep 0.6
  want F03-H3 "drop makes a folder with both apps" "(.folders | length) == 1 and (.folders[] .items | sort) == ([\"$a\", \"$b\"] | sort)" "$(lay)"
  fid=$(lay | jq -r '.folders | keys[0]')
  read -r fx fy <<<"$(at "folder:$fid")"
  pt m "$fx" "$fy" d s 60 u; sleep 0.8
  want F03-H4 "click on a folder in edit mode opens it" ".folder == \"folder:$fid\""
  shot F03-open
  key -k Escape; key -k Escape; sleep 0.6
  want F03-E1 "Esc closes the folder, then leaves edit mode" '.folder == "" and .editing == false'
  read -r fx fy <<<"$(at "folder:$fid")"
  pt m "$fx" "$fy" d s 60 u; sleep 0.8
  want F03-H5 "click opens the folder outside edit mode" ".folder == \"folder:$fid\""
  read -r cx cy <<<"$(at "$a")"
  pt m "$cx" "$cy" d s 60 u; sleep 0.5
  want F03-H6 "click an app in a folder launches it" ".lastLaunch == \"$a\""
  open ""; c folderOpen "folder:$fid" >/dev/null; sleep 0.8
  pt m 960 395 d s 50 u; sleep 0.3
  key -M ctrl a -m ctrl "Tools" -k Return; sleep 0.5
  want F03-H7 "click the title renames the folder" '.folderTitle == "Tools"'
  key -k Escape; sleep 0.5
  want F03-E2 "a rename survives in the file" '(.folders[] .name) == "Tools"' "$(lay)"
  # drag an app out of the folder
  c edit true >/dev/null; c folderOpen "folder:$fid" >/dev/null; sleep 0.8
  read -r cx cy <<<"$(at "$b")"
  pt m "$cx" "$cy" d s 60 g "$cx" 950 14 15 s 300
  want F03-H8 "dragging an app out of the panel closes the folder" ".folder == \"\" and .dragId == \"$b\""
  pt g 400 900 8 15 s 200 u; sleep 0.6
  want F03-H9 "the app lands on the grid; the folder keeps one app" "(.pages | flatten | index(\"$b\")) != null and ([.folders[] .items | length] == [1])" "$(lay)"
  shut
fi

# ---- F04 move between pages / reorder ---------------------------------
if runs F04; then
  fresh; open ""
  c edit true >/dev/null
  a=$(pageItem 0 0); t=$(pageItem 0 4)
  read -r ax ay <<<"$(at "$a")"; read -r tx ty <<<"$(at "$t")"
  # the gap between two tiles, below the folder zone: a reorder, not a folder
  pt m "$ax" "$ay" d s 60 g "$tx" $((ty + 55)) 14 20 s 150 u; sleep 0.6
  want F04-H1 "dragging reorders on the page" "(.pages[0] | index(\"$a\")) == 4" "$(lay)"
  read -r ax ay <<<"$(at "$a")"
  pt m "$ax" "$ay" d s 60 g 1905 540 16 15 s 450
  want F04-H2 "holding at the right edge turns the page" '.page == 1'
  pt g 700 400 10 15 s 200 u; sleep 0.6
  want F04-H3 "dropping places the app on page 2" "(.pages[1] | index(\"$a\")) != null" "$(lay)"
  want F04-E1 "no app is lost or doubled" '(.pages | flatten | length) == (.pages | flatten | unique | length)' "$(lay)"
  shut
fi

# ---- F06 hide ---------------------------------------------------------
if runs F06; then
  fresh; open ""
  a=$(pageItem 0 1); read -r x y <<<"$(at "$a")"
  pt m "$x" "$y" rd s 50 ru; sleep 0.4
  want F06-H1 "right click shows the app menu" '.menu == true and (.menuItems | index("Hide")) != null'
  shot F06-menu
  key -k Down; key -k Down; key -k Return; sleep 0.4
  want F06-H2 "Hide from the menu hides the app" ".hidden == 1 and .menu == false"
  want F06-H3 "the hidden app is off the grid" "(.pages | flatten | index(\"$a\")) == null and .hidden == [\"$a\"]" "$(lay)"
  key "$(c entryInfo "$a" | jq -r '.name' | cut -c1-5)"
  want F06-E1 "a hidden app is still found by search" '.results >= 1'
  key -k Escape
  c edit true >/dev/null; sleep 0.3
  b=$(pageItem 0 1); read -r x y <<<"$(at "$b")"
  pt m $((x - 30)) $((y - 30)) d s 50 u; sleep 0.4
  want F06-H4 "the edit badge hides an app" '.hidden == 2'
  key -k Escape
  pt m 960 1060 rd s 50 ru; sleep 0.4
  want F06-H5 "right click on empty space shows the layout menu" '(.menuItems | index("Settings…")) != null'
  key -k Down; key -k Down; key -k Return; sleep 0.8
  want F06-H6 "Settings… opens the settings sheet" '.settingsOpen == true'
  shot F06-settings
  key -k Escape; sleep 0.5
  want F06-E2 "Esc closes the sheet, the Launchpad stays" '.settingsOpen == false and .opened == true'
  shut
fi

# ---- persistence ------------------------------------------------------
if runs P01; then
  open ""; c testMove "$(pageItem 0 0) 0 6" >/dev/null; sleep 0.6
  before=$(lay | jq -c .pages)
  "$here/rig-reload.sh" >/dev/null
  want P01-H1 "the layout survives a shell restart" ".pages == $before" "$(lay)"
  echo "{nope" > "$F/launchpad/layout.json"
  "$here/rig-reload.sh" >/dev/null
  want P01-N1 "an unreadable file runs read-only" '.readOnly == true and (.error | length) > 0'
  open ""; c testMove "$(pageItem 0 0) 0 3" >/dev/null; sleep 0.8
  want P01-N2 "read-only never overwrites the file" '. == "{nope\n"' "$(jq -Rs . "$F/launchpad/layout.json")"
  fresh
fi

echo
echo "passed $pass  failed $fail${failed:+  (${failed[*]})}"
[[ ${KEEP:-0} == 1 ]] || rig/rig.sh stop >/dev/null
[[ $fail -eq 0 ]]
