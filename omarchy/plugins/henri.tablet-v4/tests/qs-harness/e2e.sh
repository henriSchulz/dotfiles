#!/bin/bash
# End-to-end tests of the tablet's Quick Settings in the harness (harness.sh: nested Hyprland, headless output
# QS 1440 × 960, the backend never live) with a real pointer — the virtual pointer of
# henri.launchpad-v3/tests/vptr. A finger reaches Quickshell as a mouse here; real touch only on the device.
# Positions are the landscape layout at 1440 × 960 (panel at 24,24, 480 wide); the S cases restart the harness at
# 1024 × 768 (the iPad cast) and find everything by name. The A cases (sound) read the real volume and default
# devices before and after (wpctl get-volume, pactl get-default-sink|source) and expect them unchanged.
#   tests/qs-harness/e2e.sh [CASE-PREFIX]      KEEP=1 leaves the harness running; QS_RIG_ID=x a rig of its own
set -u
here=$(cd "$(dirname "$0")" && pwd)
H="$here/harness.sh"
FILTER=${1:-}
STATE=$here/../../../rig/state/${QS_RIG_ID:-v4qs}/state/velum/tablet-qs.json
# a tile order saved before the Sound tile existed (version 1, no `known`): read at the start below (V01)
mkdir -p "$(dirname "$STATE")"
printf '{ "version": 1, "tiles": ["dnd", "wifi", "bluetooth", "night", "cast"] }\n' > "$STATE"
"$H" up light >/dev/null || { echo "harness did not come up"; exit 1; }
v1tiles=$("$H" call tiles 2>/dev/null)
"$H" call setTiles "wifi bluetooth dnd dark night airplane saver rotate cast" >/dev/null
sleep 0.5

c() { "$H" call "$@" 2>/dev/null; }
st() { c state | jq -r "$1"; }
pt() { "$H" pt "$@" >/dev/null; sleep 0.35; }
tap() { pt m "$1" "$2" d s 60 u; }
at() { c xy "$1"; }                       # the centre of a named item (objectName), "X Y"
tapAt() { local p; p=$(at "$1"); [[ -n $p ]] || { echo "        (no $1 on screen)"; return 1; }; tap $p; }
settle() { sleep "${1:-0.9}"; }
logs() { c log | jq -r '.[]'; }
opened() { c open >/dev/null; settle; }
closed() { c close >/dev/null; settle; c clearEvents >/dev/null; }
pass=0 fail=0 failed=()
want() {   # want CASE "what" ACTUAL EXPECTED
  [[ -n $FILTER && $1 != $FILTER* ]] && return
  if [[ $3 == "$4" ]]; then pass=$((pass + 1)); printf '  ok    %-5s %s\n' "$1" "$2"
  else fail=$((fail + 1)); failed+=("$1"); printf '  FAIL  %-5s %s\n        got: %s  want: %s\n' "$1" "$2" "$3" "$4"; "$H" shot "FAIL-$1" >/dev/null; fi
}
runs() { [[ -z $FILTER || $1 == $FILTER* ]]; }

# ---- the shade follows the finger from the top edge
if runs Q01; then closed
  pt m 700 6 d g 700 520 14 16 s 250 u; settle
  want Q01 "a pull past a third opens the shade" "$(st .open),$(st .progress)" "true,1"
fi
if runs Q02; then closed
  pt m 700 6 d g 700 90 10 30 s 300 u; settle
  want Q02 "a short slow pull springs back closed" "$(st .open),$(st .progress)" "false,0"
fi
if runs Q03; then closed
  pt m 700 6 d g 700 130 3 8 u; settle
  want Q03 "a short fast fling opens" "$(st .open)" "true"
fi
if runs Q04; then opened; c clearEvents >/dev/null
  tap 1000 800; settle
  want Q04 "a tap beside the panels closes (closed emitted)" "$(st .open),$(st '.events | join(",")')" "false,closed"
fi
if runs Q05; then opened
  pt m 264 600 d g 264 230 10 16 u; settle
  want Q05 "a push up on the panel closes" "$(st .open)" "false"
fi
if runs Q06; then opened
  pt m 264 600 d g 264 540 6 60 s 300 u; settle
  want Q06 "a short push up springs back open" "$(st .open),$(st .progress)" "true,1"
fi

# ---- pages: tabs and a sideways swipe; the tile under a swipe is not toggled
if runs Q07; then opened; n=$(st .log)
  pt m 420 352 d g 120 352 10 16 u; settle
  want Q07 "a swipe left on the tiles turns to Battery, toggles nothing" "$(st .tab),$(st .log)" "1,$n"
  pt m 120 300 d g 440 300 10 16 u; settle
  want Q08 "a swipe right turns back to Controls" "$(st .tab)" "0"
  pt m 300 352 d g 260 352 6 16 u; settle
  want Q09 "a short swipe stays on the page" "$(st .tab),$(st .pagePos)" "0,0"
  tapAt tab-3; settle
  want Q10 "a tap on the Power tab" "$(st .tab)" "3"
  pt m 264 290 d g 520 290 10 16 u; settle
  want Q11 "past the last page gives way only (resisted)" "$(st .tab)" "2"
  tapAt tab-0; settle
fi
if runs Q12; then opened; c tab 0 >/dev/null; settle
  b0=$(st .brightness)
  pt m 400 200 d g 150 200 8 16 u; settle 0.4
  want Q12 "the slider takes a sideways finger, the page stays" "$(st .tab),$([[ $(st .brightness) -lt $b0 ]] && echo lower)" "0,lower"
  # the way control-center-v3 goes: the casting tablet's backlight, this machine's panel (the OSD's grid) or
  # omarchy-brightness-display; the harness's nested Hyprland has no eDP, so cast or display here
  path=$(st .brightPath)
  case $path in
    cast) pre="dry brightnessctl -q -d $(c brightCmd cast 0.5 | awk '{print $4}') set " ;;
    dim) pre='dry hyprctl dispatch hl.dsp.event("osd set ' ;;
    *) pre="dry omarchy-brightness-display --no-osd " ;;
  esac
  want Q13 "brightness is logged once, on release, on its way ($path)" "$(logs | grep -cF "$pre")" "1"
  want B01 "while a tablet casts the slider moves the backlight it follows" "$path" "$([[ $(st .cast) == true ]] && echo cast || echo display)"
  want B02 "the panel's way: the OSD's grid as an event (control-center-v3)" "$(c brightCmd dim 0.5)" 'hyprctl dispatch hl.dsp.event("osd set 0.5000")'
  want B03 "no panel, no cast: omarchy-brightness-display" "$(c brightCmd display 0.42)" "omarchy-brightness-display --no-osd 42%"
  want B04 "the cast's way names the backlight device" "$(c brightCmd cast 0.42 | sed 's/-d [^ ]*/-d DEV/')" "brightnessctl -q -d DEV set 42%"
fi

# ---- tiles
if runs Q14; then opened; c tab 0 >/dev/null; settle; d=$(st .dnd)
  tapAt tile-dnd; settle 0.4
  want Q14 "a tap on Do Not Disturb switches it" "$(st .dnd)" "$([[ $d == true ]] && echo false || echo true)"
  want Q15 "…and only logs its command" "$(logs | tail -1)" "dry omarchy-shell notifications setDnd $([[ $d == true ]] && echo off || echo on)"
  tapAt tile-night; settle 0.4
  want Q16 "Night Light logs omarchy-toggle-nightlight" "$(logs | tail -1)" "dry omarchy-toggle-nightlight"
fi
if runs Q17; then opened; c tab 0 >/dev/null; settle
  read -r x y <<<"$(at tile-wifi)"; pt m "$x" "$y" d s 700 u; settle
  want Q17 "holding Internet opens its details" "$(st .detail)" "wifi"
  tapAt btn-back; settle
  want Q18 "back leaves the details" "$(st .detail)" ""
  read -r x y <<<"$(at tile-bluetooth)"; tap $((x + 85)) "$y"; settle
  want Q19 "the chevron on Bluetooth opens its details" "$(st .detail)" "bluetooth"
  tapAt btn-back; settle
fi
if runs Q20; then opened; c tab 0 >/dev/null; settle
  if [[ $(st .castWifi) == true && $(c state | jq -r .wifi) == true ]]; then
    tapAt tile-wifi; settle 0.5
    want Q20 "Wi-Fi off while the iPad casts over Wi-Fi asks first" "$(st .confirm)" "true"
    tapAt confirm-cancel; settle 0.5
    want Q21 "Cancel leaves Wi-Fi on, nothing logged" "$(st .confirm),$(st .wifi),$(logs | grep -c 'nmcli radio')" "false,true,0"
  else echo "  skip  Q20   no Wi-Fi cast right now"; fi
fi

# ---- editing
if runs Q22; then opened; c tab 0 >/dev/null; settle
  tapAt btn-edit; settle
  want Q22 "the pencil starts editing" "$(st .editing)" "true"
  tapAt badge-wifi; settle                # the remove badge of Internet
  want Q23 "the badge removes the tile and saves the order" "$(jq -c .tiles "$STATE")" '["bluetooth","dnd","dark","night","airplane","saver","rotate","cast"]'
  read -r x y <<<"$(at tile-bluetooth)"; read -r x2 y2 <<<"$(at tile-night)"
  pt m "$x" "$y" d g $((x + 10)) "$y" 2 30 g "$((x2 + 228))" "$y2" 12 30 s 200 u; settle     # Bluetooth (now first) beside Night Light
  want Q24 "a held tile goes to the slot under the finger" "$(jq -c .tiles "$STATE")" '["dnd","dark","night","bluetooth","airplane","saver","rotate","cast"]'
  tapAt spare-wifi; settle
  want Q25 "a tap on a tile to add puts it back at the end" "$(jq -c .tiles "$STATE" | jq -r '.[-1]')" "wifi"
  tapAt btn-done; settle
  want Q26 "Done ends editing" "$(st .editing)" "false"
fi

# ---- power: the three that end the session ask first; nothing ever runs
if runs Q27; then opened; c tab 3 >/dev/null; settle
  tapAt power-restart; settle 0.5
  want Q27 "Restart asks first" "$(st .confirm)" "true"
  tapAt confirm-cancel; settle 0.5
  want Q28 "Cancel: nothing logged" "$(st .confirm),$(logs | grep -c reboot)" "false,0"
  tapAt power-lock; settle
  want Q29 "Lock closes the shade and logs omarchy-system-lock (dry)" "$(st .open),$(logs | tail -1)" "false,dry omarchy-system-lock"
  opened; c tab 3 >/dev/null; settle
  tapAt power-off; settle 0.5
  tapAt confirm-go; settle
  want Q30 "Shut down confirmed: logged dry, shade closed" "$(st .open),$(logs | tail -1)" "false,dry omarchy-system-shutdown"
fi

# ---- notifications (the history; hidden here only)
if runs Q31; then opened; n=$(st .notifications)
  if [[ $n -gt 0 ]]; then
    read -r x y <<<"$(at card-0)"; pt m "$x" "$y" d g $((x + 400)) "$y" 10 16 u; settle 1.2
    want Q31 "a card swiped sideways goes (here only)" "$(st .notifications)" "$((n - 1))"
    want Q32 "the history files stay" "$(ls ~/.local/state/omarchy/notifications/history/*.json | wc -l)" "$(ls ~/.local/state/omarchy/notifications/history/*.json | wc -l)"
  else echo "  skip  Q31   no notification in the history"; fi
fi

# ---- Wi-Fi details: a rescan when they open, "Scanning…", the list read again; the list scrolls under the finger
if runs W01; then opened; c tab 0 >/dev/null; settle
  if [[ $(st .wifi) == true && $(st .airplane) == false ]]; then
    n0=$(logs | grep -c 'wifi rescan')
    c detail wifi >/dev/null; sleep 0.3
    want W01 "opening the Wi-Fi details asks NetworkManager for a scan (a read)" "$(logs | grep -c '^read nmcli device wifi rescan$'),$(st .scanning)" "$((n0 + 1)),true"
    want W02 "…and says Scanning… meanwhile" "$([[ -n $(at scanning) ]] && echo shown)" "shown"
    for _ in $(seq 25); do [[ $(st .scanning) == false ]] && break; sleep 0.3; done
    want W03 "the list is read again (nmcli … --rescan no), Scanning… goes" "$(st .scanning),$([[ $(st .scanned) -ge 1 && $(st .networks) -ge $(st .scanned) ]] && echo read)" "false,read"
    tapAt btn-rescan; sleep 0.3
    want W04 "the refresh button scans again (NetworkManager may refuse: quiet)" "$(logs | grep -c '^read nmcli device wifi rescan$')" "$((n0 + 2))"
    for _ in $(seq 25); do [[ $(st .scanning) == false ]] && break; sleep 0.3; done
    max=$(c scroll | jq -r .now.max)
    if [[ $max -gt 0 ]]; then
      read -r x y <<<"$(at btn-back)"
      pt m "$((x + 200))" "$((y + 260))" d g "$((x + 200))" "$((y + 120))" 8 16 u; settle 1.2
      want W05 "a push up on a longer list scrolls it, the shade stays" "$(c scroll | jq -r '.now.y > 0'),$(st .open),$(st .detail)" "true,true,wifi"
      pt m "$((x + 200))" "$((y + 120))" d g "$((x + 200))" "$((y + 300))" 8 16 u; settle 1.2
      want W06 "…and a pull down brings it back to the top" "$(c scroll | jq -r .now.y)" "0"
    else echo "  skip  W05   the list fits (fewer than six networks around)"; fi
    c detail "" >/dev/null; settle 0.4
  else echo "  skip  W01   Wi-Fi is off here"; fi
fi

# ---- the casting tablet's name: ipad-link's journal, else "Tablet"
if runs T01; then opened; settle
  if [[ $(st .cast) == true ]]; then
    name=$(journalctl --user -u ipad-link.service -g '^casting to the ' -n 1 -o cat --no-pager 2>/dev/null | tail -1 | sed 's/^casting to the //')
    want T01 "the Tablet page names the casting tablet (ipad-link's journal)" "$(st .tabletName)" "${name:-Tablet}"
    [[ -n $name ]] && want T02 "its history is the file named after it" "$(st .tabletLog)" "$(tr 'A-Z ' 'a-z-' <<<"$name")"
  else echo "  skip  T01   no tablet casts right now"; fi
fi

# ---- sound: the volume slider under brightness, the Sound tile (mute, its details), outputs / inputs / Sound
# settings in the details — all dry: Henri's volume, mute and default devices stay as they are
if runs V01; then
  want V01 "a version-1 tile order gets the new Sound tile after Bluetooth" "$v1tiles" '["dnd","wifi","bluetooth","sound","night","cast"]'
fi
if runs A01; then
  real() { echo "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)|$(pactl get-default-sink 2>/dev/null)|$(pactl get-default-source 2>/dev/null)"; }
  sound() { c sound | jq -r "$1"; }
  before=$(real)
  c setTiles "wifi bluetooth sound dnd dark night airplane saver rotate cast" >/dev/null
  opened; c tab 0 >/dev/null; settle
  read -r bx by <<<"$(at slider)"; read -r vx vy <<<"$(at volume)"
  want A01 "the volume slider stands under the brightness slider" "$([[ -n $vy && $vy -gt $by && $vx == "$bx" ]] && echo below)" "below"
  want A02 "it shows the default output's volume" "$(st .volume)" "$(sound '.reported * 100 | round')"
  n=$(logs | grep -c 'wpctl set-volume')
  pt m $((vx + 120)) "$vy" d g $((vx - 120)) "$vy" 8 16 u; settle 0.4
  want A03 "a finger drags it lower; logged once, on release (dry wpctl set-volume)" \
    "$([[ $(st .volume) -lt $(sound '.reported * 100 | round') ]] && echo lower),$(( $(logs | grep -c '^dry wpctl set-volume ') - n ))" "lower,1"
  read -r x y <<<"$(at tile-sound)"
  tap "$x" "$y"; settle 0.4
  want A04 "a tap on the Sound tile mutes (dry wpctl set-mute … 1), the slider shows the muted symbol" \
    "$(st .muted),$(logs | tail -1 | sed 's/set-mute [^ ]* /set-mute ID /'),$(sound .icon)" "true,dry wpctl set-mute ID 1,sound.mute"
  pt m $((vx - 100)) "$vy" d g $((vx + 60)) "$vy" 6 16 u; settle 0.4
  want A05 "moving the slider up unmutes" "$(st .muted),$(logs | grep -c 'set-mute [^ ]* 0$')" "false,1"
  scans=$(logs | grep -c 'wifi rescan')
  tap $((x + 85)) "$y"; settle
  want A06 "the chevron on Sound opens its details (and nothing of Wi-Fi's: no scan)" "$(st .detail),$(logs | grep -c 'wifi rescan')" "sound,$scans"
  rows=$(c sound)
  if pactl list sinks short 2>/dev/null | grep -q ipad_speakers; then
    want A07 "the casting iPad's speakers are an output, with the tablet symbol" \
      "$(jq -r '.outputs[] | select(.name == "ipad_speakers") | .icon' <<<"$rows"),$([[ -n $(at output-ipad_speakers) ]] && echo shown)" "tablet,shown"
  else echo "  skip  A07   no ipad_speakers sink (no cast)"; fi
  # unplugged outputs (every port "not available") and virtual ones stay out unless they are the default
  gone=$(pactl -f json list sinks | jq -r --arg d "$(pactl get-default-sink)" '.[] | select(.name != $d) | select(((.ports | length) > 0 and all(.ports[]; .availability == "not available")) or .properties["node.virtual"] == "true") | .name' | sort)
  shown=$(jq -r '.outputs[].name' <<<"$rows" | sort)
  want A08 "unplugged and virtual outputs are not listed (Easy Effects, the mic chain)" "$(comm -12 <(echo "$gone") <(echo "$shown") | wc -l)" "0"
  want A09 "the default output and input are marked" "$(jq -r '[.outputs[] | select(.active)] | length' <<<"$rows"),$(jq -r '[.inputs[] | select(.active)] | length' <<<"$rows")" "1,1"
  other=$(jq -r '[.outputs[] | select(.active | not)][0] | "\(.id) \(.name)"' <<<"$rows")
  if [[ $other != "null null" ]]; then
    tapAt "output-${other#* }"; settle 0.4
    want A10 "a tap on another output picks it (dry omarchy-audio-output-set-default ID NAME)" \
      "$(logs | tail -1),$(sound .sink)" "dry omarchy-audio-output-set-default $other,${other#* }"
  else echo "  skip  A10   one output only"; fi
  inrow=$(jq -c '[.inputs[] | select(.active | not)][0]' <<<"$rows")
  if [[ $inrow != null ]]; then
    name=$(jq -r .name <<<"$inrow"); mon=$(jq -r 'if .monitor then .name + ".monitor" else .name end' <<<"$inrow")
    tapAt "input-$name"; settle 0.4
    want A11 "a tap on another input picks it (dry pactl set-default-source)" "$(logs | tail -1),$(sound .source)" "dry pactl set-default-source $mon,$name"
  else echo "  skip  A11   one input only"; fi
  tapAt sound-switch; settle 0.4
  want A12 "the switch in the details mutes" "$(st .muted),$(logs | tail -1 | sed 's/set-mute [^ ]* /set-mute ID /')" "true,dry wpctl set-mute ID 1"
  tapAt sound-settings; settle
  want A13 "Sound settings: System Settings on its Sound page (dry), the shade closes" \
    "$(logs | tail -1),$(st .open)" "dry uwsm-app -- omarchy-settings open sound,false"
  opened; c tab 0 >/dev/null; settle
  read -r x y <<<"$(at tile-sound)"; pt m "$x" "$y" d s 700 u; settle
  want A14 "holding the Sound tile opens its details" "$(st .detail)" "sound"
  c detail "" >/dev/null; c close >/dev/null; settle
  want A15 "nothing reached the system: volume, mute, default output and input as before" "$(real)" "$before"
  c setTiles "wifi bluetooth dnd dark night airplane saver rotate cast" >/dev/null
fi

# ---- the dry run: nothing reached the system (reads asked for something, they changed nothing)
if runs Q33; then
  want Q33 "every logged command is a dry run or a read" "$(logs | grep -vcE '^(dry|read) ')" "0"
fi

# ---- 1024 × 768 (the iPad cast): the Controls page scrolls when it is taller than the shade can show
if runs S01; then
  c close >/dev/null; c setTiles "wifi bluetooth dnd dark night airplane saver rotate cast" >/dev/null
  export QS_W=1024 QS_H=768                # the virtual pointer maps onto this size too
  "$H" up light >/dev/null || echo "harness did not come up at 1024 × 768"
  opened; c tab 0 >/dev/null; c edit true >/dev/null; settle
  # all tiles fit at 1024 × 768 with the panels right under the status bar: hang them lower (the owner's
  # topInset) until the page is taller than the room left
  inset=0
  while [[ $(c scroll | jq -r .now.max) == 0 && $inset -lt 300 ]]; do inset=$((inset + 40)); c inset $inset >/dev/null; sleep 0.3; done
  sc=$(c scroll)
  want S01 "editing: the page is as tall as the room left and scrolls (inset $inset)" "$(jq -r '.now.h == .pagesMax and .now.max > 0' <<<"$sc")" "true"
  t0=$(jq -c .tiles "$STATE")
  read -r x y <<<"$(at tile-saver)"
  pt m "$x" "$y" d g "$x" "$((y - 200))" 8 16 u; settle 1.2
  want S02 "a quick push up on a tile scrolls the page to the end; the shade stays, still editing, no tile moved" \
    "$(c scroll | jq -r '.now.y == .now.max'),$(st .open),$(st .editing),$(jq -c .tiles "$STATE")" "true,true,true,$t0"
  read -r x y <<<"$(at tile-cast)"; read -r _ ty <<<"$(at tab-0)"
  pt m "$x" "$y" d s 550 g "$((x + 10))" "$y" 2 30 g "$x" "$((ty + 52))" 10 30 s 1000 u; settle      # held, then to the top edge
  want S03 "a held tile dragged to the top edge scrolls the page up and lands first" "$(c scroll | jq -r .now.y),$(jq -r '.tiles[0]' "$STATE")" "0,cast"
  tapAt btn-done; settle
  c inset $((inset + 120)) >/dev/null; settle 0.4
  if [[ $(c scroll | jq -r .now.max) -gt 0 ]]; then
    read -r _ y <<<"$(at tile-dark)"; read -r x0 _ <<<"$(at tab-0)"; read -r x3 _ <<<"$(at tab-3)"
    pt m "$x3" "$y" d g "$x0" "$y" 10 16 u; settle
    want S04 "on a page that scrolls, a sideways swipe still turns to Battery" "$(st .tab)" "1"
    pt m "$x0" "$y" d g "$x3" "$y" 10 16 u; settle
    want S05 "…and back" "$(st .tab)" "0"
    read -r x y <<<"$(at tile-dark)"
    pt m "$x" "$y" d g "$x" "$((y - 300))" 8 16 u; settle 1.2
    pt m "$x" "$y" d g "$x" "$((y - 300))" 8 16 u; settle 1.2
    want S06 "at the end of the page a push up closes the shade" "$(st .open)" "false"
  else echo "  skip  S04   the page fits without editing"; fi
  c inset 0 >/dev/null
fi

c close >/dev/null
c inset 0 >/dev/null
c setTiles "wifi bluetooth dnd dark night airplane saver rotate cast" >/dev/null
echo "e2e: $pass passed, $fail failed${failed:+ (${failed[*]})}"
[[ ${KEEP:-} == 1 ]] || true
[[ $fail == 0 ]]
