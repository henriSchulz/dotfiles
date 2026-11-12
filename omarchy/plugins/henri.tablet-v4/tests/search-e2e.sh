#!/bin/bash
# e2e for SearchView.qml and AppDrawer.qml in their own rig (tests/search-rig.sh): a virtual pointer
# and wtype into the NESTED compositor only (never the live session), results read over IPC.
# Light and dark screenshots land in the rig's shots/. Launches nothing: the harness only records.
#   tests/search-e2e.sh            (starts the rig if needed, leaves it up; tests/search-rig.sh down)
set -u
here=$(cd "$(dirname "$0")" && pwd)
T=$here/search-rig.sh
R=${RIG_DIR:-$HOME/.cache/velum-v4-search-rig}
pass=0 fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1: $2"; }
check() { local name=$1 got=$2 want=$3; [[ $got == "$want" ]] && ok "$name" || bad "$name" "got [$got] want [$want]"; }
call() { "$T" call "$@"; }
ptr() { "$T" ptr "$@"; }
st() { call searchState | jq -r "$1"; }
dr() { call drawerState | jq -r "$1"; }
ev() { call events | jq -r '.[-1] // ""'; }
tap() { ptr m "$1" "$2" d s 60 u; }
hold() { ptr m "$1" "$2" d s 600 u; }
. "$here/../../rig/nested-guard.sh"
nwl() { nested_wl "$(cat "$R/sig" 2>/dev/null)"; }   # wtype never types into the live compositor
key() { WAYLAND_DISPLAY=$(nwl) wtype "$@"; }
settle() { sleep "${1:-0.8}"; }

"$T" up >/dev/null || { echo "rig did not come up"; exit 1; }
call dark false >/dev/null; call speed 1 >/dev/null; call reduceMotion false >/dev/null
call searchClose >/dev/null; call drawerClose >/dev/null; settle; call clearEvents >/dev/null

# ---- search
key t; settle
check "S1 a typed letter opens the view with it" "$(st '[.shown, .text] | join(" ")')" "true t"
call searchType "term" >/dev/null; settle 0.3
first=$(st '.first')
[[ $first == app:* ]] && ok "S2 a name start ranks an app first ($first)" || bad "S2 first result" "$first"
key -k Return; settle
check "S3 Enter opens the first result and closes" "$(ev) $(st .shown)" "search closed false"
call events | jq -e --arg id "${first#app:}" 'any(.[]; . == "search open " + $id)' >/dev/null && ok "S3b the owner got openApp(${first#app:})" || bad "S3b" "$(call events)"
key c; settle; key -k Escape; settle
check "S4 Escape closes" "$(st .shown)" "false"
call searchOpen "" >/dev/null; settle
check "S5 empty: suggested apps" "$(st '(.apps | length) > 0 and .first == null')" "true"
read -r x y id <<<"$(call searchTile 1)"
call clearEvents >/dev/null; tap "$x" "$y"; settle
check "S6 a tap on a result opens it" "$(call events | jq -r '.[0]')" "search open $id"
call searchOpen "" >/dev/null; settle; call clearEvents >/dev/null
tap 640 700; settle
check "S7 a tap beside closes, nothing opens" "$(call events | jq -c .)" '["search closed"]'
call searchOpen "x" >/dev/null; settle
read -r bx by < <(call searchState | jq -r '"\(.view[0] + .view[2] - 28) \(.view[1] + 28)"')
tap "$bx" "$by"; settle 0.3
check "S8 clear empties the query and stays open" "$(st '[.shown, .text] | join(" ")')" "true "
call clearEvents >/dev/null; tap "$bx" "$by"; settle
check "S9 the mic asks for voice" "$(call events | jq -r '.[0]')" "search voice"
call searchOpen "zzqx" >/dev/null; settle
check "S10 nothing matches: the web row is first" "$(st .first)" "web:zzqx"
read -r wx wy <<<"$(call searchLastRow)"; call clearEvents >/dev/null; tap "$wx" "$wy"; settle
check "S11 a tap on the web row searches the web" "$(call events | jq -r '.[0]')" "search web zzqx"
call searchOpen "o" >/dev/null; settle
"$T" shot e2e-search-o-light >/dev/null; call dark true >/dev/null; settle 0.3; "$T" shot e2e-search-o-dark >/dev/null
call dark false >/dev/null; call searchClose >/dev/null; settle

# ---- drawer
call clearEvents >/dev/null
ptr m 640 600 d g 640 520 10 40 s 200 u; settle
check "D1 a short slow swipe up falls back" "$(dr .position)" "0"
ptr m 640 600 d g 640 450 6 12 u; settle
check "D2 a flick up opens the drawer" "$(dr .position)" "1"
"$T" shot e2e-drawer-light >/dev/null
ptr m 640 20 d g 640 120 10 40 s 200 u; settle
check "D3 a short slow pull on the handle springs back" "$(dr .position)" "1"
ptr m 640 20 d g 640 90 4 10 u; settle 1.2
check "D4 a flick down on the handle closes it" "$(dr '[.position, .active] | join(" ")')" "0 false"
check "D4b closed() reached the owner" "$(ev)" "drawer closed"
call drawerOpen >/dev/null; settle
read -r x y id <<<"$(call drawerCell 8)"
call clearEvents >/dev/null; hold "$x" "$y"; settle
check "D5 a long press opens the menu and the lift neither closes nor opens" "$(dr '[.menu, .last] | join(" ")') $(call events | jq length)" "true  0"
"$T" shot e2e-drawer-menu-light >/dev/null; call dark true >/dev/null; settle 0.3; "$T" shot e2e-drawer-menu-dark >/dev/null; call dark false >/dev/null
read -r mx my key0 <<<"$(call menuTile 0)"; tap "$mx" "$my"; settle
check "D6 Add to Home" "$(ev) $(dr .menu)" "drawer add $id false"
hold "$x" "$y"; settle; read -r mx my key1 <<<"$(call menuTile 1)"; tap "$mx" "$my"; settle
check "D7 App info" "$(ev)" "drawer info $id"
hold "$x" "$y"; settle; read -r x2 y2 id2 <<<"$(call drawerCell 20)"; call clearEvents >/dev/null; tap "$x2" "$y2"; settle
check "D8 a tap beside the menu closes it and is swallowed" "$(dr .menu) $(call events | jq length)" "false 0"
tap "$x2" "$y2"; settle 0.4
check "D9 a tap opens the app" "$(ev)" "drawer open $id2"
tap 640 72; key zzqx; settle 0.4
check "D10 the field filters (nothing matches)" "$(dr .count)" "0"
call drawerQuery "" >/dev/null; hold "$x" "$y"; settle
key -k Escape; settle 0.5
check "D11 Escape closes the menu first" "$(dr '[.menu, .active] | join(" ")')" "false true"
key -k Escape; settle 1.2
check "D12 then the drawer" "$(dr .active)" "false"
call drawerOpen >/dev/null; call dark true >/dev/null; settle; "$T" shot e2e-drawer-dark >/dev/null
call drawerClose >/dev/null; call dark false >/dev/null; settle

errors=$("$T" log 400 | grep -E "ERROR|TypeError|ReferenceError|is not a type|Cannot assign|Unable to assign|binding loop" | grep -v qmlscanner)
[[ -z $errors ]] && ok "no QML errors in the harness log" || bad "QML errors" "$errors"
echo "$pass passed, $fail failed — shots in $R/shots"
[[ $fail -eq 0 ]]
