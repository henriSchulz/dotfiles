#!/bin/bash
# A tablet rig for the home screen's folders, with its own state: the fake HOME gets its own
# ~/.local/state/velum (a copy of home-layout.json, never the live one) and ~/.local/share/velum
# points at THIS checkout (a worktree's tokens, not the main repo's). Then IPC and screenshots.
#   tests/folders-rig.sh up | shot NAME | call ARGS… | ptr ARGS… | down
set -u
here=$(cd "$(dirname "$0")" && pwd); shell=$(cd "$here/../.." && pwd); repo=$(dirname "$shell")
cd "$shell"
export VELUM_RIG_ID=folders VELUM_TOUCH=1 VELUM_TABLET_LAUNCH=1
# its own state: XDG_STATE_HOME is set in the session and would point the shell at the live file
export XDG_STATE_HOME=$PWD/rig/state/folders/home/.local/state
export VELUM_EDGE_SOCKET=$PWD/rig/state/folders/edge.sock
export VELUM_RIG_PLUGINS="henri.bar-v3 henri.control-center-v3 henri.clock-v3 henri.power-v3 henri.dock-v3 henri.tablet-v3 henri.menu-v3"
R=rig/state/folders F=$R/home W=1440 H=960
vptr=$shell/henri.launchpad-v3/tests/vptr
sig() { cat $R/sig 2>/dev/null; }
nwl() { HYPRLAND_INSTANCE_SIGNATURE= hyprctl instances -j | jq -r --arg s "$(sig)" '.[] | select(.instance==$s) | .wl_socket'; }
own_local() {
  rm -f "$F/.local"; mkdir -p "$F/.local/share" "$F/.local/state/velum"
  for e in /home/henri/.local/*; do b=$(basename "$e"); [[ $b == share || $b == state ]] || ln -sfn "$e" "$F/.local/$b"; done
  for e in /home/henri/.local/share/*; do b=$(basename "$e"); [[ $b == velum ]] || ln -sfn "$e" "$F/.local/share/$b"; done
  ln -sfn "$repo" "$F/.local/share/velum"
  for e in /home/henri/.local/state/*; do b=$(basename "$e"); [[ $b == velum ]] || ln -sfn "$e" "$F/.local/state/$b"; done
  for e in /home/henri/.local/state/velum/*; do b=$(basename "$e"); [[ $b == home-layout.json ]] || ln -sfn "$e" "$F/.local/state/velum/$b"; done
  # the plugins import Velum by an absolute path: the rig's copies take this checkout's module
  for p in $VELUM_RIG_PLUGINS; do
    d="$F/.config/omarchy/plugins/$p"; [[ -d $d && ! -L $d ]] || continue
    grep -rl "file:///home/henri/.local/share/velum" "$d" --include=*.qml --include=*.js | xargs -r sed -i "s|file:///home/henri/.local/share/velum|file://$repo|g"
  done
  [[ -f $F/.local/state/velum/home-layout.json ]] || cp /home/henri/.local/state/velum/home-layout.json "$F/.local/state/velum/" 2>/dev/null || true
}
case "${1:-}" in
  up)
    [[ -x $vptr/vptr ]] || "$vptr/build.sh"
    if ! { [[ -n $(sig) ]] && HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl version >/dev/null 2>&1; }; then rig/rig.sh start >/dev/null || exit 1; fi
    rig/rig.sh sync >/dev/null; own_local
    export HYPRLAND_INSTANCE_SIGNATURE=$(sig)
    hyprctl monitors -j | jq -e '.[] | select(.name=="TB")' >/dev/null || hyprctl output create headless TB >/dev/null
    sleep 0.5
    hyprctl eval "hl.monitor({ output = 'TB', mode = '${W}x${H}@60', position = '2000x0', scale = 1 })" >/dev/null
    hyprctl dispatch "hl.dsp.focus({ monitor = 'TB' })" >/dev/null
    rig/rig.sh shell >/dev/null
    for _ in $(seq 20); do sleep 0.5; [[ $(rig/rig.sh call henri.tablet state 2>/dev/null) == *'"active":true'* ]] && break; done
    rig/rig.sh call henri.tablet state | head -c 200; echo ;;
  shot) WAYLAND_DISPLAY=$(nwl) timeout 5 grim -o TB "$R/$2.png" && echo "$R/$2.png" ;;
  call) shift; rig/rig.sh call "$@" ;;
  ptr) shift; WAYLAND_DISPLAY=$(nwl) "$vptr/vptr" TB $W $H "$@" ;;
  log) rig/rig.sh log "${2:-}" ;;
  down) rig/rig.sh stop ;;
esac
