#!/bin/bash
# End-to-end tests for henri.tablet-v4's Material home screen (MaterialHome.qml), in the rig of
# tests/material-rig.sh with its own state (RIG=material-e2e): the fake HOME's home-layout.json is the
# seed below, never the live one. Apps are never launched (NO_LAUNCH), nothing is uninstalled (the
# dialog only says what it would run). The virtual pointer stands in for a finger; a finger still
# down is probed while vptr runs in the background.
#   tests/material-e2e.sh        every case      tests/material-e2e.sh M5   only M5…
#   KEEP=1 …                     leave the rig running; shots in rig/state/material-e2e/e2e-*.png
set -u
here=$(cd "$(dirname "$0")" && pwd)
shell=$(cd "$here/../.." && pwd)
cd "$shell"
export RIG=material-e2e NO_LAUNCH=1 VELUM_RIG_WS=${VELUM_RIG_WS:-name:velum-rig}
R=rig/state/$RIG
FILTER=${1:-}
rigctl() { "$here/material-rig.sh" "$@"; }

KEEP_IDS='["keepass","localsend","signal","com.github.xournalpp.xournalpp","foto","foot","chromium"]'
layout=$R/home/.local/state/velum/home-layout.json
mkdir -p "$(dirname "$layout")"
rm -f "$layout"
rigctl up >/dev/null || exit 1
seed() {
  cat >"$layout" <<'JSON'
{
 "order": ["keepass", "localsend", "signal", "com.github.xournalpp.xournalpp", "page", "foto"],
 "folders": {},
 "hidden": ["widget:photos"],
 "hotseat": ["foot", "chromium"]
}
JSON
}
seed
rigctl shell
sleep 1.5
export HYPRLAND_INSTANCE_SIGNATURE=$(cat $R/sig)
# only these on the home screen: every other tile of this machine hidden, then read anew
others=$(rigctl call henri.tablet4 homeLayout 2>/dev/null | jq -c --argjson k "$KEEP_IDS" '[.tiles[] | select(. as $t | $k | index($t) | not) | select(startswith("folder:") | not)] + ["widget:photos"] | unique')
folded=$(rigctl call henri.tablet4 homeLayout 2>/dev/null | jq -c --argjson k "$KEEP_IDS" '[.folders[]?.items[]] | map(select(. as $t | $k | index($t) | not))')
jq --argjson h "$others" --argjson f "$folded" '.hidden = ($h + $f | unique)' "$layout" >"$layout.new" && mv "$layout.new" "$layout"
rigctl shell
sleep 1.5

c() { rigctl call henri.tablet4 "$@" 2>/dev/null; }
pt() { rigctl ptr "$@"; sleep 0.3; }
# a finger that stays down: vptr in the background, probed meanwhile
ptbg() { rigctl ptr "$@" & PTR=$!; }
ptwait() { wait $PTR 2>/dev/null; sleep 0.3; }
shot() { rigctl shot "e2e-$1" >/dev/null 2>&1; }
probe() { c homeProbe TB; }
q() { probe | jq -c "$@"; }
at() { c homePoint TB "$1" | jq -r 'if . == null then "" else "\(.x | floor) \(.y | floor)" end'; }
tap() { pt m "$1" "$2" d s 60 u; }
pass=0 fail=0 failed=()
want() {
  [[ -n $FILTER && $1 != $FILTER* ]] && return
  if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-5s %s\n' "$1" "$2"
  else fail=$((fail + 1)); failed+=("$1"); printf '  FAIL  %-5s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; shot "FAIL-$1"; fi
}
order() { q '.saved.order'; }

hyprctl dispatch "hl.dsp.focus({ workspace = 'emptynm' })" >/dev/null; sleep 1.2
c clearLog >/dev/null
c rigDark false >/dev/null; sleep 0.6; shot M0-light
c rigDark true >/dev/null; sleep 0.6; shot M0-dark
want M0 "renders from the seed: tokens' grid, hotseat, two pages" \
  "$(q '[.geo.cols, .geo.rows, .geo.top, .hotseat, .pages, .order]')" \
  '[6,5,56,["foot","chromium"],2,["keepass","localsend","signal","com.github.xournalpp.xournalpp","page","foto"]]'

# ---- the long-press menu stays when the finger lifts; a tap beside closes it
read -r kx ky < <(at tile:keepass)
pt m "$kx" "$ky" d s 600 u; sleep 0.5; shot M1-menu
want M1 "long press: the app's menu, still open after the lift" "$(q '[.menu.open, .menu.kind, .menu.id, .menu.keys]')" '[true,"app","keepass",["new","info"]]'
tap 700 700; sleep 0.5
want M2 "a tap beside closes it" "$(q '.menu.open')" "false"

# ---- into the hand past slop, Remove, Undo
# (the drop bar is the top of the home screen's window, below the menu bar: over the bar a pointer leaves the surface)
read -r rx ry < <(at drop:remove)
ptbg m "$kx" "$ky" d s 600 g 600 300 8 16 g "$rx" "$ry" 8 16 s 2000 u
sleep 1.7; shot M3-drag
want M3 "pulled away: the menu goes, the drop bar is there, Remove under the finger" "$(q '[.menu.open, .drag.id, .drag.targets, .drag.target, (.dropBar > 0.9)]')" '[false,"keepass",["remove","uninstall"],"remove",true]'
ptwait; sleep 0.6; shot M4-removed
want M4 "dropped on Remove: hidden, a snackbar with Undo" "$(q '[(.hidden | index("keepass") != null), .snackState.undo, (.order | index("keepass"))]')" '[true,true,null]'
read -r ux uy < <(at snack:undo)
tap "$ux" "$uy"; sleep 0.8
want M5 "Undo: back in its place" "$(q '[(.hidden | index("keepass")), .order[0], .snackState]')" '[null,"keepass",null]'

# ---- a folder: localsend resting on signal
read -r lx ly < <(at tile:localsend)
read -r sx sy < <(at tile:signal)
ptbg m "$lx" "$ly" d s 600 g $(( (lx + sx) / 2 )) $(( ly - 40 )) 6 16 g "$sx" "$sy" 8 16 s 2000 u
sleep 1.8
want M6 "resting on another app arms a folder" "$(q '[.drag.aim, .drag.armed]')" '["signal",true]'
ptwait; sleep 0.8
want M7 "dropped: a folder of both where signal was" "$(q '[.saved.order[0:3], ([.saved.folders[]] | map(.items))]')" '[["keepass","folder:f1","com.github.xournalpp.xournalpp"],[["signal","localsend"]]]'
read -r fx fy < <(at tile:folder:f1)
tap "$fx" "$fy"; sleep 0.8; shot M8-folder
want M8 "a tap opens it" "$(q '[.folder.open, .folder.items, (.folder.shown > 0.99)]')" '["folder:f1",["signal","localsend"],true]'
# rename: the name takes the keyboard (OnDemand) — typed into the nested compositor; the IPC path if no key arrives
read -r nx ny < <(at folder:name)
tap "$nx" "$ny"; sleep 0.4
WAYLAND_DISPLAY=$(HYPRLAND_INSTANCE_SIGNATURE= hyprctl instances -j | jq -r --arg s "$(cat $R/sig)" '.[] | select(.instance==$s) | .wl_socket') timeout 3 wtype -s 30 "Tools" -k Return 2>/dev/null
sleep 0.6
typed=$(q '.saved.folders.f1.name')
[[ $typed == '"Tools"' ]] && how=typed || { c homeRename "Tools" >/dev/null; how=ipc; sleep 0.4; }
shot M9-renamed
want M9 "renamed ($how)" "$(q '.saved.folders.f1.name')" '"Tools"'
# carry localsend out of the folder: it closes, the app stays in the hand, the folder of one becomes signal
read -r ix iy < <(c homeIcon TB localsend | jq -r '"\((.x + .w / 2) | floor) \((.y + .w / 2) | floor)"')
ptbg m "$ix" "$iy" d s 600 g "$ix" $(( iy - 60 )) 6 16 g 1200 200 10 16 s 2000 u
sleep 1.8; shot M10-out
want M10 "carried out of the folder: closed, still in the hand, the folder of one gone" "$(q '[.folder.open, .drag.id, (.saved.folders | length), (.saved.order | index("signal") != null)]')" '["","localsend",0,true]'
ptwait; sleep 0.8
want M11 "dropped on the grid" "$(q '[(.saved.order | index("localsend") != null), (.saved.order | map(select(startswith("folder:"))) | length)]')" '[true,0]'

# ---- the hotseat takes an app and gives one back
read -r xx xy < <(at tile:com.github.xournalpp.xournalpp)
read -r hx hy < <(at hotseat:2)
pt m "$xx" "$xy" d s 600 g 700 500 8 16 g "$hx" "$hy" 10 16 s 700 u; sleep 0.8
want M12 "dropped on the hotseat" "$(q '[.saved.hotseat, (.saved.order | index("com.github.xournalpp.xournalpp"))]')" '[["foot","chromium","com.github.xournalpp.xournalpp"],null]'
read -r cx cy < <(c homeIcon TB chromium | jq -r '"\((.x + .w / 2) | floor) \((.y + .w / 2) | floor)"')
pt m "$cx" "$cy" d s 600 g 700 500 8 16 g 600 300 8 16 s 700 u; sleep 0.8
want M13 "given back to the grid" "$(q '[.saved.hotseat, (.saved.order | index("chromium") != null)]')" '[["foot","com.github.xournalpp.xournalpp"],true]'

# ---- a page break: held at the right edge, past the last page a new one
read -r gx gy < <(at tile:signal)
ptbg m "$gx" "$gy" d s 600 g 1430 "$gy" 10 16 s 1700 u
sleep 2.9; shot M14-newpage
want M14 "held past the last page: a third page opens and turns" "$(q '[.page, .pages]')" '[2,3]'
ptwait; sleep 0.8
want M15 "dropped there: a break before it, saved" "$(q '.saved.order[-2:]')" '["page","signal"]'
pt m 200 400 d g 1300 400 8 16 u; sleep 0.8   # back to page 2
pt m 200 400 d g 1300 400 8 16 u; sleep 0.8   # and to page 1

# ---- Uninstall asks and runs nothing
read -r ox oy < <(c homeIcon TB foot | jq -r '"\((.x + .w / 2) | floor) \((.y + .w / 2) | floor)"')
read -r dx dy < <(at drop:uninstall)
pt m "$ox" "$oy" d s 600 g 900 300 8 16 g "$dx" "$dy" 8 16 s 500 u; sleep 1.2; shot M16-dialog
want M16 "dropped on Uninstall: the dialog, with what it would run" "$(q '[.confirm.id, (.confirm.plan | test("omarchy-remove-launcher-entry foot"))]')" '["foot",true]'
read -r okx oky < <(at dialog:ok)
tap "$okx" "$oky"; sleep 0.6
want M17 "OK: nothing uninstalled, foot stays, a snackbar says what it would run" "$(q '[.confirm, (.hotseat | index("foot") != null), (.snackState.text | test("Nothing was uninstalled"))]')" '[null,true,true]'

# ---- the wallpaper's menu and the search bar
pt m 1000 640 d s 600 u; sleep 0.5; shot M18-home-menu
want M18 "a long press on the wallpaper: the home menu" "$(q '[.menu.kind, .menu.keys]')" '["home",["wallpaper","widgets","settings"]]'
read -r wx wy < <(at "menu:Wallpaper & style")
tap "$wx" "$wy"; sleep 1.2
want M19 "Wallpaper & style opens the wallpaper picker" "$(rigctl call wallpaper status 2>/dev/null | jq -c '.opened')" "true"
rigctl call wallpaper close >/dev/null 2>&1; sleep 0.6
# ================================================================ the integrated parts (phases 2, 3, 5, 6)
. "$shell/rig/nested-guard.sh"
nwl() { nested_wl "$(cat $R/sig 2>/dev/null)"; }   # wtype never types into the live compositor
key() { WAYLAND_DISPLAY=$(nwl) timeout 3 wtype "$@" 2>/dev/null; }
parts() { c homeParts TB | jq -c "$1"; }
find() { c homeFind TB "$1" | jq -r 'if . == null then "" else "\(.x) \(.y)" end'; }
# the overlay lets go after a launch that never comes (NO_LAUNCH): wait until it rests again
rest() { for _ in $(seq 40); do m=$(c home | jq -r .mode); [[ $m == idle || $m == home ]] && return; sleep 0.25; done; }
homelog() { c home | jq -c "$1"; }

# ---- search (phase 2): the bar, a typed key, Enter, the web row
read -r qx qy < <(at search)
tap "$qx" "$qy"; sleep 0.8
want M20 "the search bar opens the search view, which takes the keyboard" "$(parts '[.search.shown, .keys]')" '[true,"exclusive"]'
key -s 30 sig; sleep 0.6; shot I1-search
want I1 "typed into it: Signal first" "$(parts '[.search.text, .search.first]')" '["sig","app:signal"]'
key -k Return; sleep 0.6
want I2 "Enter opens it (v3's openApp with its card) and closes the view" "$(parts '.search.shown')|$(homelog '[.log[] | select(. == "tap signal")] | length')" 'false|1'
rest
pt m 700 640; key x; sleep 0.6
want I3 "a key typed while the home screen shows opens the view with it" "$(parts '[.search.shown, .search.text]')" '[true,"x"]'
key -k BackSpace -s 30 "x y&z"; sleep 0.5
want I4 "nothing matches: the web row first" "$(parts '.search.first')" '"web:x y&z"'
key -k Return; sleep 0.6
want I5 "the web row opens the browser with the query encoded" "$(homelog '.log[-1]')" '"web https://www.google.com/search?q=x%20y%26z"'
key c; sleep 0.4; key -k Escape; sleep 0.6
want I6 "Escape closes; the home screen keeps the keyboard on demand" "$(parts '[.search.shown, .keys]')" '[false,"ondemand"]'

# ---- All apps (phase 3): a swipe up on the grid, Add to Home
pt m 700 640 s 50 d g 700 600 3 16 g 700 330 10 16 u; sleep 1.2; shot I7-drawer
want I7 "a swipe up on the grid brings All apps" "$(parts '[.drawer.active, .drawer.position]')" '[true,1]'
pick=$(parts '.drawer.ids' | jq -r --argjson k "$KEEP_IDS" '[.[] | select(. as $t | $k | index($t) | not)][0]')
read -r px py < <(find "drawer:$pick")
pt m "$px" "$py" s 50 d s 700 u; sleep 0.8; shot I8-drawer-menu
want I8 "a long press on $pick: its menu" "$(parts '.drawer.menu')" 'true'
read -r ax ay < <(find drawermenu:add)
tap "$ax" "$ay"; sleep 1.2; shot I9-added
tp=$(c homePoint TB "tile:$pick" | jq -r '.page // -1')
want I9 "Add to Home: on the grid, saved, the drawer gone, its page ($tp) shown" "$(q --arg p "$pick" '(.saved.order | index($p) != null)')|$(parts '[.drawer.active, .page]')" "true|[false,$tp]"
want I9b "the snackbar says it" "$(q '.snackState.text | test("added to the Home screen")')" 'true'

# ---- the App Switcher and gesture navigation (phase 5): three rig windows
rigctl foot 3 >/dev/null; sleep 1
hyprctl dispatch "hl.dsp.focus({ workspace = 'emptynm' })" >/dev/null; sleep 1.2
# the strip: after a workspace change the virtual pointer's first gesture on the home zone arrives as a tap
# (no moves; also with phase 1's keyboard-less home window, so a rig artifact of the synthetic pointer, not
# of the touch path): every zone gesture is preceded by a move of its own over the home screen (zmove)
zmove() { pt m 720 600 s 100; }
zmove; pt m 720 950 s 400 d s 100 g 720 935 2 16 g 720 760 3 10 u; sleep 1.2
want I10a "on another page a flick from the strip goes home: the first page, no switcher" "$(parts '[.switcher.nav, .switcher.open, .page]')" '["home",false,0]'
c clearLog >/dev/null
zmove; pt m 720 950 s 400 d s 100 g 720 930 4 30 s 100 g 720 760 10 30 s 500 u; sleep 1.4; shot I10-switcher
want I10 "home screen: up and rest from the bottom strip opens the Material App Switcher" "$(parts '[.switcher.open, .switcher.nav, .switcher.info.n, .switcher.info.centred]')" '[true,"switcher",3,2]'
read -r W2 step cw < <(parts '[1440, .switcher.info.step, .switcher.info.cardW] | @tsv' | jq -r .)
want_addr=$(parts '.switcher.info.windows[1].address' | jq -r .)
lx=$(( (720 - step + cw / 2) / 2 ))
pt m "$lx" 480 s 50 d s 60 u; sleep 1.2
got=$(hyprctl activewindow -j | jq -r .address)
want I11 "a tap on the card beside switches to that window" "$(parts '.switcher.open')|$got" "false|$want_addr"
rest
c clearLog >/dev/null
zmove; pt m 720 950 s 400 d s 100 g 720 930 4 30 s 100 g 720 700 10 30 s 700 u; sleep 0.25; shot I12-handoff; sleep 1.4
want I12 "over an app: pull and pause hands the v3 card over to the Material switcher" "$(parts '[.switcher.open, .switcher.info.n]')|$(homelog '[.log[] | select(. == "material switcher")] | length')|$(homelog .mode)" '[true,3]|1|"idle"'
pt m 720 480 s 50 d g 725 250 4 16 u; sleep 1.5
want I13 "a card flicked up closes its window for real" "$(rigctl clients | jq 'length')|$(parts '.switcher.info.n')" '2|2'
key -k Escape; sleep 0.8
want I14 "Escape closes the switcher" "$(parts '.switcher.open')" 'false'
hyprctl dispatch "hl.dsp.focus({ workspace = 'emptynm' })" >/dev/null; sleep 1.2; rest
zmove; pt m 720 950 s 400 d s 100 g 720 935 2 16 g 720 760 3 10 u; sleep 1.2
want I15 "a flick with no way home (first page, nothing open) only opens the switcher" "$(parts '[.switcher.nav, .switcher.open]')" '["switcher",true]'
key -k Escape; sleep 0.8
pt m 700 640 s 50 d g 700 600 3 16 g 700 330 10 16 u; sleep 1.2
zmove; pt m 720 950 s 400 d s 100 g 720 935 2 16 g 720 760 3 10 u; sleep 1.2
want I16 "with All apps open the flick goes home: the drawer closes, no switcher" "$(parts '[.switcher.nav, .switcher.open, .drawer.active, .page]')" '["home",false,false,0]'

# ---- widgets (phase 6): the wallpaper's menu, the picker, a real widget added
pt m 1000 640 s 50 d s 650 u; sleep 0.6
read -r wx wy < <(at "menu:Widgets")
tap "$wx" "$wy"; sleep 1.2; shot I17-picker
want I17 "Widgets opens the picker (it takes the keyboard)" "$(parts '[.picker.open, .keys]')" '[true,"exclusive"]'
read -r bx by < <(find picker:battery)
tap "$bx" "$by"; sleep 1.2; shot I18-widget
want I18 "a tap puts the Battery widget on the home screen, saved, its page shown" "$(parts '[.picker.open, (.widgets | index("widget:battery") != null)]')|$(q '(.saved.order | index("widget:battery") != null)')" '[false,true]|true'
c rigDark false >/dev/null; sleep 0.6; shot I19-widgets-light
c rigDark true >/dev/null; sleep 0.6; shot I19-widgets-dark
read -r qx qy < <(at search); tap "$qx" "$qy"; sleep 0.8; key -s 30 o; sleep 0.5; shot I20-search-dark
c rigDark false >/dev/null; sleep 0.6; shot I20-search-light; key -k Escape; sleep 0.6

# ---- Quick Settings (phase 4): the top-edge pull in tablet mode opens the Material shade, not FullCenter
sp() { c shadeProbe TB | jq -c "$1"; }
sfind() { c shadeFind TB "$1" | jq -r 'if . == null then "" else "\(.x) \(.y)" end'; }
want Q1 "henri.tablet-v4 claims the Control Center pull for its shade" "$(sp '[.claimed, .live, .mapped]')" '[true,false,false]'
# bar-v3's DragHandler (the menu bar's right share), as a finger pulls it
pt m 1300 600 s 100; pt m 1300 12 s 100 d s 60 g 1300 120 4 16 g 1300 560 10 16 s 80 u; sleep 1.2; shot Q2-shade-light
want Q2 "a pull down from the menu bar's right share opens the shade, mapped" "$(sp '[.open, .progress, .mapped]')" '[true,1,true]'
want Q3 "…and not FullCenter" "$(rigctl call henri.control-center-v3 fullState 2>/dev/null | jq -c '.open')" 'false'
want Q4 "the shade takes the keyboard once the finger is off it" "$(sp '.focus')" 'true'
read -r tx ty < <(sfind tile-bluetooth)
tap "$tx" "$ty"; sleep 0.6
want Q5 "a tile switches through the backend, a dry run in the rig" "$(sp '.commands[-1] | test("^dry omarchy-bluetooth-power (on|off)$")')" 'true'
tap "$tx" "$ty"; sleep 0.4
# Wi-Fi off while the iPad casts over Wi-Fi asks first (the real cast state: either way is checked)
# (the cast state is read before the tap: the shade decides on what it knows at that moment)
n0=$(sp '.commands | length') casting=$(sp '.castOverWifi')
read -r tx ty < <(sfind tile-wifi)
tap "$tx" "$ty"; sleep 0.6
if [[ $casting == true ]]; then
  shot Q5b-wifi-confirm
  read -r kx ky < <(sfind confirm-cancel); tap "$kx" "$ky"; sleep 0.6
  want Q5b "Wi-Fi off while casting over Wi-Fi: a confirm, Cancel runs nothing" "$(sp '[.confirm, (.commands | length)]')" "[false,$n0]"
else
  want Q5b "Wi-Fi off (no cast over Wi-Fi): a dry run" "$(sp '.commands[-1]')" '"dry nmcli radio wifi off"'
  tap "$tx" "$ty"; sleep 0.4
fi
c rigDark true >/dev/null; sleep 0.6; shot Q6-shade-dark
read -r gx gy < <(sfind tab-3); tap "$gx" "$gy"; sleep 0.8; shot Q6-power-dark
c rigDark false >/dev/null; sleep 0.6; shot Q6-power-light
key -k Escape; sleep 1
want Q6 "Escape closes it; the window unmaps" "$(sp '[.open, .mapped, .progress]')" '[false,false,0]'
# a cast screen's top edge (velum-edge, the same route)
ev() { hyprctl dispatch "hl.dsp.event(\"velum-edge TB top $1 1300 $2\")" >/dev/null; }
ev down 0; for y in 40 120 220 330 450; do ev move $y; sleep 0.03; done; ev up 450; sleep 1.2
want Q7 "a cast edge pull from the right share opens the shade too" "$(sp '.open')|$(rigctl call henri.control-center-v3 fullState 2>/dev/null | jq -c '.open')" 'true|false'
c shadeClose TB >/dev/null; sleep 1

want M21 "no error on the way" "$(rigctl log tablet-v4 2>/dev/null | grep -c 'henri.tablet-v4.*\(Error\|TypeError\|ReferenceError\|undefined\)')" "0"

echo "passed $pass, failed $fail${failed[*]:+: ${failed[*]}}"
[[ -n ${KEEP:-} ]] || rigctl down >/dev/null 2>&1
[[ $fail == 0 ]]
