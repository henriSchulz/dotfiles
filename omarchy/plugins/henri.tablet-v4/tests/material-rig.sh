#!/bin/bash
# A tablet rig for henri.tablet-v4 (the Material home screen) with its own state, after v3's
# tests/folders-rig.sh: the fake HOME gets its own ~/.local/state/velum (a copy of home-layout.json,
# never the live one), ~/.local/share/velum points at THIS checkout, and the rig's shell.json runs
# henri.tablet-v4 instead of henri.tablet-v3 (both would draw a home screen). Then IPC and screenshots.
#   tests/material-rig.sh up | shell | shot NAME | call ARGS… | ptr ARGS… | foot N | clients | log | down
#   RIG=NAME …   another rig with its own state; NO_LAUNCH=1 starts no app
set -u
here=$(cd "$(dirname "$0")" && pwd); shell=$(cd "$here/../.." && pwd); repo=$(dirname "$shell")
cd "$shell"
ID=${RIG:-material}
export VELUM_RIG_ID=$ID VELUM_TOUCH=1 VELUM_TABLET_LAUNCH=1
# a hidden workspace of its own: name:spare can be the screen Henri looks at (the cast)
export VELUM_RIG_WS=${VELUM_RIG_WS:-name:velum-rig}
[[ -n ${NO_LAUNCH:-} ]] && unset VELUM_TABLET_LAUNCH
# its own state: XDG_STATE_HOME is set in the session and would point the shell at the live file
export XDG_STATE_HOME=$PWD/rig/state/$ID/home/.local/state
export VELUM_EDGE_SOCKET=$PWD/rig/state/$ID/edge.sock
export VELUM_RIG_PLUGINS="henri.bar-v3 henri.control-center-v3 henri.clock-v3 henri.power-v3 henri.dock-v3 henri.tablet-v4 henri.menu-v3 henri.wallpaper-v3"
R=rig/state/$ID F=$R/home W=${RIG_W:-1440} H=${RIG_H:-960}
vptr=$shell/henri.launchpad-v3/tests/vptr
sig() { cat $R/sig 2>/dev/null; }
. "$shell/rig/nested-guard.sh"
nwl() { nested_wl "$(sig)"; }   # never the live compositor (an empty one fell back to the live Xwayland)
own_local() {
  [[ -L $F/.local ]] && rm -f "$F/.local"; mkdir -p "$F/.local/share" "$F/.local/state/velum"
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
  # v4 instead of v3 in the rig's shell.json (a plain file there, written by rig.sh sync)
  local sj=$F/.config/omarchy/shell.json
  jq '.plugins = ([.plugins[] | select(.id != "henri.tablet-v3" and .id != "henri.tablet-v4")] + [{id: "henri.tablet-v4"}])' "$sj" > "$sj.new" && mv "$sj.new" "$sj"
}
up_shell() {
  rig/rig.sh shell >/dev/null
  for _ in $(seq 20); do sleep 0.5; [[ $(rig/rig.sh call henri.tablet4 state 2>/dev/null) == *'"active":true'* ]] && break; done
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
    up_shell
    rig/rig.sh call henri.tablet4 state | head -c 200; echo ;;
  # a new shell with this rig's own state (rig.sh alone would take the session's XDG_STATE_HOME)
  shell) up_shell ;;
  # the plugin's files again (after an edit), then a new shell
  sync) rig/rig.sh sync >/dev/null; own_local; up_shell ;;
  shot) WAYLAND_DISPLAY=$(nwl) timeout 5 grim -o TB "$R/$2.png" && echo "$R/$2.png" ;;
  call) shift; rig/rig.sh call "$@" ;;
  ptr) shift; WAYLAND_DISPLAY=$(nwl) "$vptr/vptr" TB $W $H "$@" ;;
  # N foot windows on TB, each on a workspace of its own (tablet mode: one app per workspace), told apart by
  # colour; they carry the rig's marker, so `down` (rig.sh stop) ends them with the rest
  foot)
    nested_check "$(sig)" || exit 1
    cols=(1e3a5f 5f1e3a 1e5f3a 5f4b1e 3a1e5f 1e5f5f)
    for i in $(seq 1 "${2:-3}"); do
      ws=$((20 + i))
      HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl dispatch "hl.dsp.focus({ workspace = '$ws' })" >/dev/null
      env -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY="$(nwl)" HYPRLAND_INSTANCE_SIGNATURE="$(sig)" VELUM_SHELL_RIG="$ID-hidden" \
        setsid -f foot -o "colors-dark.background=${cols[$(( (i - 1) % 6 ))]}" -T "Window $i" \
        sh -c "printf '\n\n   Window $i  (workspace $ws)\n'; exec sleep infinity" >/dev/null 2>&1
      sleep 0.6
    done ;;
  clients) HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl clients -j | jq -c '[.[] | select(.monitor >= 0) | {address, class, title, ws: .workspace.name, f: .focusHistoryID}]' ;;
  log) rig/rig.sh log "${2:-}" ;;
  down) rig/rig.sh stop ;;
esac
