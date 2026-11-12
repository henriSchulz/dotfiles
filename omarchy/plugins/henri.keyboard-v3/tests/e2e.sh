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
# the rig loads the live henri.tablet-v3: its own edge socket, or it takes the live shell's
export VELUM_EDGE_SOCKET="${VELUM_EDGE_SOCKET:-$XDG_RUNTIME_DIR/velum-edge-kbrig.sock}"
R=rig/state/kb
W=1080 H=720                                   # the cast screen's logical size (1620 × 1080 at scale 1.5)
vptr=$shell/henri.launchpad-v3/tests/vptr
[[ -x $vptr/vptr ]] || "$vptr/build.sh"

sig() { cat $R/sig 2>/dev/null; }
up() { [[ -n $(sig) ]] && HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl version >/dev/null 2>&1; }
if ! up; then rig/rig.sh start >/dev/null || exit 1; fi
rig/rig.sh sync >/dev/null
# the rig's copy takes THIS checkout's Velum module (the plugin imports it by an absolute path, which
# is the live checkout)
d=$R/home/.config/omarchy/plugins/henri.keyboard-v3
[[ -d $d && ! -L $d ]] && grep -rl "file:///home/henri/.local/share/velum" "$d" --include=*.qml --include=*.js | xargs -r sed -i "s|file:///home/henri/.local/share/velum|file://$(dirname "$shell")|g"
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
sent() { st | jq -r '.sent | map(select(. != "arm")) | join("|")'; }   # "arm": tablet mode, autoopen-e2e.sh

# geometry as Layout.placeDock lays the docked board out (surface.keyboard.dock: toolbar 46, keys 50
# high on a 14.5-column grid, gap 7, pad 6/6/26): full width along the bottom edge
KBH=$((46 + 6 + 5 * 50 + 4 * 7 + 26))          # the board's height (toolbar + keys)
top=$((H - KBH))
pitch=$(python3 -c "print(($W - 12 + 7) / 14.5)")
row() { echo $((top + 46 + 6 + $1 * 57 + 25)); }                         # centre of key row N
col() { python3 -c "print(int(6 + $1 * $pitch + ($2 * $pitch - 7) / 2))"; }   # centre of a key at column C, span S
TY=$((top + 8 + 19))                                                       # the toolbar buttons' centre
tool() { echo $((8 + $1 * 46 + 23)); }                                     # the Nth button from the left
rtool() { echo $((W - 8 - $1 * 46 - 23)); }                                # the Nth from the right (0 = hide)

want K01 "starts hidden, no surface" "$(st | jq .shown),$(layer)" "false,false"
reservedBottom() { hyprctl monitors -j | jq '.[] | select(.name == "TB") | .reserved[3]'; }
rb0=$(reservedBottom)
hyprctl dispatch 'hl.dsp.event("velum-touch TB")' >/dev/null; sleep 0.4
want K02 "a lifted finger opens nothing" "$(st | jq .shown),$(sent)" "false,"
want K03 "but names the screen" "$(st | jq -r .screen)" "TB"

hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.7
want K04 "the window bar's keyboard button opens it" "$(st | jq .shown),$(layer),$(sent)" "true,true,open"
shot K04-letters
lay() { hyprctl layers -j | jq -c '[.TB.levels[][] | select(.namespace == "velum-surface" and .h < 400)][0]'; }
want K24 "it lies full width along the bottom edge" "$(lay | jq '.w'),$(lay | jq '.h'),$(lay | jq '.y + .h')" "$W,$KBH,$H"
want K25 "it reserves nothing: the app keeps its size" "$(reservedBottom)" "$rb0"
want K26 "the caret is kept above its top edge (hyprcaret caretlift LINE MARGIN)" "$(c omarchy.keyboard lifts | jq -r '.[-1]')" "$(( $(hyprctl monitors -j | jq '.[] | select(.name == "TB") | .y') + top )) 12"
# q: row 1, after tab (1.5 columns)
qx=$(col 1.5 1)
pt m "$qx" "$(row 1)" d s 40 u
want K05 "a tap on q types q" "$(sent | awk -F'|' '{print $NF}')" "text q"
# shift: row 3, first key (1.25 columns); then q: capital, shift drops again
pt m "$(col 0 1.25)" "$(row 3)" d s 40 u
want K06 "shift lights" "$(st | jq .shift)" "true"
pt m "$qx" "$(row 1)" d s 40 u
want K07 "shifted q is Q, then shift is off" "$(sent | awk -F'|' '{print $NF}'),$(st | jq .shift)" "text Q,false"
# Shift types the character written over a key: ! over 1
pt m "$(col 0 1.25)" "$(row 3)" d s 40 u; pt m "$(col 1 1)" "$(row 0)" d s 40 u
want K27 "shift and 1 type !" "$(sent | awk -F'|' '{print $NF}'),$(st | jq .shift)" "text !,false"
# delete: last key of row 0 (column 13, 1.5 wide)
pt m "$(col 13 1.5)" "$(row 0)" d s 40 u
want K08 "delete presses BackSpace" "$(sent | awk -F'|' '{print $NF}')" "key BackSpace"
# tab: first key of row 1
pt m "$(col 0 1.5)" "$(row 1)" d s 40 u
want K20 "tab presses Tab" "$(sent | awk -F'|' '{print $NF}')" "key Tab"
# the mic: the toolbar's second button from the right (hide, mic; a terminal adds paste before them)
calls() { tail -1 "$R/home/.cache/voxtype-stub/calls" 2>/dev/null; }
pt m "$(rtool 1)" "$TY" d s 40 u; sleep 0.4
want K21 "the toolbar's mic starts a dictation and holds the bridge" "$(calls),$(st | jq -r .voxState),$(sent | awk -F'|' '{print $NF}')" "record start,recording,hold on"
shot K21-dictating
pt m "$(rtool 1)" "$TY" d s 40 u; sleep 1
want K22 "tapped again it stops; idle lets the bridge go" "$(calls),$(st | jq -r .voxState),$(sent | awk -F'|' '{print $NF}'),$(st | jq .shown)" "record stop,idle,hold off,true"
# .?123: first key of the bottom row (2 columns)
pt m "$(col 0 2)" "$(row 4)" d s 40 u
want K09 ".?123 turns the page" "$(st | jq -r .page)" "symbols"
shot K09-symbols
pt m "$(col 1.5 1)" "$(row 1)" d s 40 u
want K10 "where q was it types @" "$(sent | awk -F'|' '{print $NF}')" "text @"
pt m "$(col 0 2)" "$(row 4)" d s 40 u
# the toolbar's ⌘ (after esc, tab, ctrl in a terminal; after undo, redo elsewhere) opens the shortcuts page
cmdn=$([[ $(st | jq .terminal) == true ]] && echo 3 || echo 2)
pt m "$(tool $cmdn)" "$TY" d s 40 u
want K14 "the toolbar's command key opens the shortcuts page" "$(st | jq -r .page)" "shortcuts"
shot K14-shortcuts
c omarchy.keyboard tap Copy >/dev/null
want K15 "Copy sends Control-C and turns back" "$(sent | awk -F'|' '{print $NF}'),$(st | jq -r .page)" "combo ctrl c,letters"
pt m "$(tool $cmdn)" "$TY" d s 40 u
c omarchy.keyboard tap mod:ctrl >/dev/null
want K16 "a latched modifier goes back to the letters" "$(st | jq -r .page),$(st | jq -c .mods)" 'letters,{"ctrl":"once"}'
shot K16-latched
pt m "$qx" "$(row 1)" d s 40 u
want K17 "the next key makes the combo, the latch lets go" "$(sent | awk -F'|' '{print $NF}'),$(st | jq -c .mods)" "combo ctrl q,{}"
pt m $((W / 2)) $((top - 40)) d s 40 u
want K18 "a tap above the board types nothing" "$(sent | awk -F'|' '{print $NF}')" "combo ctrl q"
# the toolbar pulled down far enough closes it
pt m $((W / 2)) "$TY" d s 40 g $((W / 2)) $((TY + 110)) 12 16 s 40 u
sleep 0.6
want K19 "the toolbar pulled down closes it" "$(st | jq .shown),$(sent | awk -F'|' '{print $NF}'),$(c omarchy.keyboard lifts | jq -r '.[-1]')" "false,close,off"
hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.7
# hide: last key of the bottom row
pt m "$(col 12.5 2)" "$(row 4)" d s 40 u
sleep 0.6
want K11 "the hide key closes it and tells the bridge" "$(st | jq .shown),$(sent | awk -F'|' '{print $NF}'),$(layer)" "false,close,false"
hyprctl dispatch 'hl.dsp.event("velum-touch TB")' >/dev/null; sleep 0.5
want K12 "a finger after closing does not bring it back" "$(st | jq .shown),$(layer)" "false,false"
hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.4
hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 0.6
want K13 "the button toggles: open, then closed again" "$(st | jq .shown),$(sent | awk -F'|' '{print $NF}')" "false,close"
# the window bar's Keyboard button: its plate's rect comes along and grows into the toolbar
hyprctl dispatch 'hl.dsp.event("velum-keyboard morph TB 300 600 400 60")' >/dev/null; sleep 0.1
shot K28-morph
sleep 0.6
want K28 "a morph from the window bar opens it on that screen" "$(st | jq .shown),$(st | jq -r .screen),$(st | jq .morph),$(sent | awk -F'|' '{print $NF}')" "true,TB,false,open"
hyprctl dispatch 'hl.dsp.event("velum-keyboard morph TB 300 600 400 60")' >/dev/null; sleep 0.3
want K29 "a second morph while it is up changes nothing" "$(st | jq .shown)" "true"
pt m "$(rtool 0)" "$TY" d s 40 u; sleep 0.6
want K23 "the toolbar's hide button closes it" "$(st | jq .shown),$(sent | awk -F'|' '{print $NF}')" "false,close"

# ---- the edit menu: a long press in a text field (the rig has no bridge: hold says what it would answer)
ms() { c omarchy.keyboard menuState; }
# other plugins have full-screen surfaces of the same namespace: the menu's is one more than before
fullLayers() { hyprctl layers -j | jq '[.TB.levels[][] | select(.namespace == "velum-surface" and .h == '$H')] | length'; }
base=$(fullLayers)
WAYLAND_DISPLAY=$NWL wl-copy --clear 2>/dev/null
menuLayer() { [[ $(fullLayers) -gt $base ]] && echo true || echo false; }
# a window with a text field under the finger (an app neither a terminal nor one with its own menu)
hyprctl dispatch "hl.dsp.exec_cmd('foot --app-id velum-text', { workspace = '$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .activeWorkspace.id')' })" >/dev/null; sleep 1.5
c omarchy.keyboard hold TB 500 400 touch 0 >/dev/null; sleep 0.5
want M01 "no text field: no menu" "$(ms | jq .open),$(menuLayer)" "false,false"
c omarchy.keyboard hold TB 500 400 touch 1 >/dev/null; sleep 0.5
want M02 "in a text field the menu opens" "$(ms | jq .open),$(menuLayer),$(ms | jq -c .items)" 'true,true,["Cut","Copy","Select All"]'
shot M02-menu
c omarchy.keyboard menuTap Copy >/dev/null; sleep 0.6
want M03 "Copy sends Control-C and the menu goes" "$(sent | awk -F'|' '{print $NF}'),$(ms | jq .open),$(menuLayer)" "combo ctrl c,false,false"
WAYLAND_DISPLAY=$NWL wl-copy "e2e" 2>/dev/null; sleep 0.3
c omarchy.keyboard hold TB 520 60 touch 1 >/dev/null; sleep 0.5
want M04 "with something to paste, Paste; near the top it opens below the finger" "$(ms | jq -c .items)" '["Cut","Copy","Paste","Select All"]'
shot M04-below
pt m 900 650 d s 40 u; sleep 0.6
want M05 "a tap beside it closes it and types nothing" "$(ms | jq .open),$(menuLayer),$(sent | awk -F'|' '{print $NF}')" "false,false,combo ctrl c"
hyprctl dispatch 'hl.dsp.window.close()' >/dev/null; sleep 0.5
# apps: a terminal copies with Shift and has no Cut; an app with its own long-press menu keeps a finger's
hyprctl dispatch "hl.dsp.exec_cmd('foot --app-id foot', { workspace = '$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .activeWorkspace.id')' })" >/dev/null; sleep 1.5
c omarchy.keyboard hold TB 500 400 touch 1 >/dev/null; sleep 0.5
want M06 "a terminal: Copy and Paste with Shift" "$(ms | jq -r .app),$(ms | jq -c .items)" 'foot,["Copy","Paste"]'
c omarchy.keyboard menuTap Paste >/dev/null; sleep 0.6
want M07 "Paste in a terminal sends Control-Shift-V" "$(sent | awk -F'|' '{print $NF}')" "combo ctrl+shift v"
hyprctl dispatch 'hl.dsp.window.close()' >/dev/null; sleep 0.5
hyprctl dispatch "hl.dsp.exec_cmd('foot --app-id chromium', { workspace = '$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .activeWorkspace.id')' })" >/dev/null; sleep 1.5
c omarchy.keyboard hold TB 500 400 touch 1 >/dev/null; sleep 0.5
want M08 "an app with its own menu keeps a finger's long press" "$(ms | jq -r .app),$(ms | jq .open)" "chromium,false"
c omarchy.keyboard hold TB 500 400 pointer 1 >/dev/null; sleep 0.5
want M09 "but a pointer hold (the iPad) gets the menu" "$(ms | jq .open)" "true"
hyprctl dispatch 'hl.dsp.window.close()' >/dev/null; sleep 0.6
want M10 "the app going closes the menu" "$(ms | jq .open)" "false"
# the home screen of tablet mode: an empty workspace, though fcitx5 still names the last text field
hyprctl dispatch "hl.dsp.focus({ workspace = 'emptynm' })" >/dev/null; sleep 0.5
c omarchy.keyboard hold TB 500 400 touch 1 >/dev/null; sleep 0.6
want M11 "no window under the finger (empty workspace): no menu, whatever fcitx5 says" "$(ms | jq .open),$(menuLayer)" "false,false"

# ---- only near the caret: hyprcaret (~/Projects/hyprcaret) in this rig's Hyprland and an input method of its
# own (fcitx5 in a session bus of its own, a fake HOME: never the session's), so foot reports its cursor
caretso=$HOME/Projects/hyprcaret/build/hyprcaret.so
if [[ -f $caretso ]] && hyprctl plugin load "$caretso" >/dev/null 2>&1; then
  im=$R/imhome; mkdir -p "$im"
  WAYLAND_DISPLAY=$NWL HOME=$im XDG_CONFIG_HOME=$im/.config XDG_DATA_HOME=$im/.local/share XDG_CACHE_HOME=$im/.cache \
    setsid -f dbus-run-session -- fcitx5 --disable=all --enable=wayland,waylandim,keyboard >/dev/null 2>&1
  sleep 2
  # loading a plugin reloads the config: TB back to the cast screen's size
  hyprctl eval "hl.monitor({ output = 'TB', mode = '${W}x${H}@60', position = '2000x0', scale = 1 })" >/dev/null; sleep 0.5
  hyprctl dispatch "hl.dsp.focus({ monitor = 'TB' })" >/dev/null
  # 200 lines first: the prompt sits at the bottom, where the keyboard will lie
  hyprctl dispatch "hl.dsp.exec_cmd('foot --app-id velum-text sh -c \"seq 200; exec bash --norc\"', { workspace = '$(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .activeWorkspace.id')' })" >/dev/null; sleep 1.5
  tb=$(hyprctl monitors -j | jq -c '.[] | select(.name=="TB") | [.x, .y]')
  car=$(hyprctl -j caret)
  cx=$(jq -n --argjson c "$car" --argjson m "$tb" '($c.x - $m[0] + $c.w / 2) | floor')
  cy=$(jq -n --argjson c "$car" --argjson m "$tb" '($c.y - $m[1] + $c.h / 2) | floor')
  want M12 "the plugin names foot's cursor" "$(jq -r '.enabled and .rect' <<<"$car")" "true"
  c omarchy.keyboard hold TB 700 500 touch 1 >/dev/null; sleep 0.6
  want M13 "a finger held in the window but away from the caret: no menu" "$(ms | jq .open),$(menuLayer)" "false,false"
  c omarchy.keyboard hold TB $((cx + 40)) $cy touch 1 >/dev/null; sleep 0.6
  want M14 "held beside the caret, on its line: the menu" "$(ms | jq .open),$(menuLayer)" "true,true"
  pt m 900 650 d s 40 u; sleep 0.6
  # the keyboard over foot: its prompt would be under the board, so hyprcaret slides foot up until the
  # caret stands above the board's top edge (LINE − 12), and back when the board goes
  line=$(( $(hyprctl monitors -j | jq '.[] | select(.name=="TB") | .y') + top ))
  wy() { hyprctl activewindow -j | jq '.at[1]'; }
  y0=$(wy)
  hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 1.2
  car=$(hyprctl -j caret); lift=$(hyprctl -j caretlift)
  want M15 "the keyboard lifts foot so its caret stays above the board" "$(jq .active <<<"$lift"),$(jq --argjson l "$line" '.y + .h <= $l - 12 and .y + .h > $l - 12 - .h * 3' <<<"$car"),$(( $(wy) < y0 ))" "true,true,1"
  shot M15-lifted
  hyprctl dispatch 'hl.dsp.event("velum-keyboard toggle TB")' >/dev/null; sleep 1.2
  want M16 "and lets it down again when it goes" "$(hyprctl -j caretlift | jq .active),$(wy)" "false,$y0"
  hyprctl dispatch 'hl.dsp.window.close()' >/dev/null; sleep 0.5
  hyprctl plugin unload "$caretso" >/dev/null 2>&1
else
  echo "skip M12-M14: no hyprcaret build for this Hyprland ($caretso)"
fi

echo "keyboard e2e: $pass ok, $fail failed"
[[ -n ${KEEP:-} ]] || rig/rig.sh stop >/dev/null
[[ $fail == 0 ]]
