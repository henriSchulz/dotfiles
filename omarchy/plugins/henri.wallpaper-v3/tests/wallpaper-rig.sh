#!/bin/bash
# A rig for the wallpaper picker (henri.wallpaper-v3) and the renderer (henri.background-v3) with
# its own state, so a test never touches the live wallpaper:
#   - its own ~/.local/state/omarchy/current (the background link henri-wallpaper and
#     omarchy-theme-bg-set rewrite) and ~/.local/state/velum/settings.json (appearance),
#   - its own ~/.config/omarchy/global-wallpaper (a copy, never a link to the live file),
#   - its own henri-wallpaper cache, seeded with reflink copies of the live thumbnails and display copies
#     (HENRI_WALLPAPER_DIR is the real folder, so the hashes match and nothing is rebuilt),
#   - ~/.local/share/velum = THIS checkout (the plugins import Velum by absolute path).
# Screenshots on a headless output SHOT inside the nested Hyprland (the hidden rig screen renders black).
#   tests/wallpaper-rig.sh up [light|dark] | appearance light|dark | reduce on|off | shot NAME |
#                          frames NAME CALL… | call ARGS… | log | down
set -u
here=$(cd "$(dirname "$0")" && pwd); shell=$(cd "$here/../.." && pwd); repo=$(dirname "$shell")
cd "$shell"
export VELUM_RIG_ID=wallpaper
export VELUM_RIG_PLUGINS="henri.bar-v3 henri.control-center-v3 henri.wallpaper-v3 henri.background-v3"
R=rig/state/wallpaper F=$PWD/$R/home W=1440 H=900
# its own state: XDG_STATE_HOME is set in the session and would point the shell at the live files
export XDG_STATE_HOME=$F/.local/state
export HENRI_WALLPAPER_DIR=/home/henri/Pictures/Wallpaper
# tablet-v3's edge socket: without its own path a rig shell takes over the live one
export VELUM_EDGE_SOCKET=$PWD/$R/edge.sock
sig() { cat $R/sig 2>/dev/null; }
nwl() { HYPRLAND_INSTANCE_SIGNATURE= hyprctl instances -j | jq -r --arg s "$(sig)" '.[] | select(.instance==$s) | .wl_socket'; }
VARIANT=${VELUM_VARIANT:-$(jq -r '.variant // "pearl"' /home/henri/.local/state/velum/settings.json 2>/dev/null || echo pearl)}
settings() {   # appearance reduceMotion (variant: the live one, or VELUM_VARIANT)
  printf '{ "variant": "'"$VARIANT"'", "appearance": "%s", "icons": "sf", "reduceMotion": %s, "reduceTransparency": false, "tablet": false }\n' \
    "$1" "$2" > "$F/.local/state/velum/settings.json.tmp" && mv "$F/.local/state/velum/settings.json.tmp" "$F/.local/state/velum/settings.json"
}
own_local() {
  [[ -L $F/.local ]] && rm -f "$F/.local"
  mkdir -p "$F/.local/share" "$F/.local/state/velum" "$F/.local/state/omarchy/current"
  for e in /home/henri/.local/*; do b=$(basename "$e"); [[ $b == share || $b == state ]] || ln -sfn "$e" "$F/.local/$b"; done
  rm -f "$F/.local/.local"   # rig.sh sync links the real .local into the directory once it is one
  for e in /home/henri/.local/share/*; do b=$(basename "$e"); [[ $b == velum ]] || ln -sfn "$e" "$F/.local/share/$b"; done
  ln -sfn "$repo" "$F/.local/share/velum"
  for e in /home/henri/.local/state/*; do b=$(basename "$e"); [[ $b == velum || $b == omarchy ]] || ln -sfn "$e" "$F/.local/state/$b"; done
  for e in /home/henri/.local/state/omarchy/*; do b=$(basename "$e"); [[ $b == current ]] || ln -sfn "$e" "$F/.local/state/omarchy/$b"; done
  for e in /home/henri/.local/state/omarchy/current/*; do b=$(basename "$e"); [[ $b == background ]] || ln -sfn "$e" "$F/.local/state/omarchy/current/$b"; done
  # the background link: the rig's own, pointing where the live one points (a copy of the link, not the file)
  # (a display copy in the live cache becomes the same copy in the rig's cache, so `displayed` maps it back)
  if [[ ! -L $F/.local/state/omarchy/current/background ]]; then
    t=$(readlink -f /home/henri/.local/state/omarchy/current/background)
    [[ $t == /home/henri/.cache/henri-wallpaper/* ]] && t=$F/.cache/henri-wallpaper/${t#/home/henri/.cache/henri-wallpaper/}
    ln -sfn "$t" "$F/.local/state/omarchy/current/background"
  fi
  [[ -f $F/.local/state/velum/settings.json ]] || settings light false
  # the pin: a real file of the rig's own (rig.sh sync links the live one)
  if [[ -L $F/.config/omarchy/global-wallpaper ]]; then
    rm -f "$F/.config/omarchy/global-wallpaper"
    cp /home/henri/.config/omarchy/global-wallpaper "$F/.config/omarchy/global-wallpaper" 2>/dev/null || true
  fi
  # henri-wallpaper's cache: rig.sh sync gives the rig its own directory; seed it once
  if [[ -z $(ls -A "$F/.cache/henri-wallpaper" 2>/dev/null) ]]; then
    cp -a --reflink=auto /home/henri/.cache/henri-wallpaper/. "$F/.cache/henri-wallpaper/"
  fi
  # only what this test needs besides the bar: no idle (it could lock or suspend), dock, tablet, lock, auth …
  jq '.plugins = [ .plugins[] | select(.id == "henri.wallpaper-v3" or .id == "henri.background-v3") ]' \
    "$F/.config/omarchy/shell.json" > "$F/.config/omarchy/shell.json.new" && mv "$F/.config/omarchy/shell.json.new" "$F/.config/omarchy/shell.json"
  # the plugins import Velum by an absolute path: the rig's copies take this checkout's module
  for p in $VELUM_RIG_PLUGINS; do
    d="$F/.config/omarchy/plugins/$p"; [[ -d $d && ! -L $d ]] || continue
    grep -rl "file:///home/henri/.local/share/velum" "$d" --include=*.qml --include=*.js | xargs -r sed -i "s|file:///home/henri/.local/share/velum|file://$repo|g"
  done
}
# refuse to run if a path the rig writes would resolve into the live state
guard() {
  local p
  for p in "$F/.local/state/omarchy/current" "$F/.local/state/velum" "$F/.config/omarchy/global-wallpaper" "$F/.cache/henri-wallpaper"; do
    case "$(readlink -f "$p")" in /home/henri/.local/state/*|/home/henri/.config/*|/home/henri/.cache/henri-wallpaper*) echo "guard: $p resolves into the live state"; exit 1 ;; esac
  done
}
case "${1:-}" in
  up)
    if ! { [[ -n $(sig) ]] && HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl version >/dev/null 2>&1; }; then rig/rig.sh start >/dev/null || exit 1; fi
    rig/rig.sh sync >/dev/null; own_local; guard
    [[ -n ${2:-} ]] && settings "$2" false
    export HYPRLAND_INSTANCE_SIGNATURE=$(sig)
    hyprctl monitors -j | jq -e '.[] | select(.name=="SHOT")' >/dev/null || hyprctl output create headless SHOT >/dev/null
    sleep 0.5
    hyprctl eval "hl.monitor({ output = 'SHOT', mode = '${W}x${H}@60', position = '2000x0', scale = 1 })" >/dev/null
    hyprctl dispatch "hl.dsp.focus({ monitor = 'SHOT' })" >/dev/null
    rig/rig.sh shell >/dev/null
    for _ in $(seq 20); do sleep 0.5; [[ $(rig/rig.sh call wallpaper status 2>/dev/null) == *'"images":'[1-9]* ]] && break; done
    rig/rig.sh call wallpaper status; echo ;;
  appearance) guard; settings "$2" false; echo "appearance $2" ;;
  reduce) guard; settings light "$([[ $2 == on ]] && echo true || echo false)"; echo "reduceMotion $2" ;;
  shot) WAYLAND_DISPLAY=$(nwl) timeout 5 grim -o SHOT "$R/$2.png" && echo "$R/$2.png" ;;
  frames)   # NAME CALL… : at 10× slow motion (rigSpeed), N=12 frames STEP=0.12 s apart from the call on
    name=$2; shift 2; wl=$(nwl); n=${N:-12} step=${STEP:-0.12}
    rig/rig.sh call wallpaper rigSpeed 10 >/dev/null
    find "${R:?}" -maxdepth 1 -name "${name:?}-[0-9]*.png" -delete
    rig/rig.sh call "$@" >/dev/null
    for i in $(seq -w 1 "$n"); do WAYLAND_DISPLAY=$wl timeout 5 grim -l 0 -o SHOT "$R/$name-$i.png"; sleep "$step"; done
    rig/rig.sh call wallpaper rigSpeed 1 >/dev/null
    ls "$R/$name"-[0-9]*.png ;;
  call) shift; guard; rig/rig.sh call "$@" ;;
  log) rig/rig.sh log "${2:-}" ;;
  down) rig/rig.sh stop ;;
  *) echo "usage: wallpaper-rig.sh up [light|dark] | appearance A | reduce on|off | shot NAME | frames NAME CALL… | call ARGS… | log | down"; exit 2 ;;
esac
