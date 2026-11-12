#!/bin/bash
# A rig for SearchView.qml / AppDrawer.qml alone: its own nested Hyprland (parked on the live
# workspace name:spare, in agents.slice), a headless output SV inside it (nothing on the host's
# outputs), and the harness (tests/search-harness/shell.qml) staged beside copies of the components
# with THIS checkout's Velum module. Its own XDG cache/state dirs; nothing of the live shell is touched.
#   tests/search-rig.sh up | stage | shell | call FN [ARGS…] | ptr CMDS… | shot NAME | log | down
#   RIG_DIR (default ~/.cache/velum-v4-search-rig) holds stage, state, logs and shots.
set -u
here=$(cd "$(dirname "$0")" && pwd); plugin=$(cd "$here/.." && pwd); repo=$(cd "$plugin/../.." && pwd)
R=${RIG_DIR:-$HOME/.cache/velum-v4-search-rig}
OUT=SV W=${RIG_W:-1280} H=${RIG_H:-800}
S=$R/stage; mkdir -p "$R/shots" "$R/home/cache" "$R/home/state"
HY=$XDG_RUNTIME_DIR/hypr
vptr=$repo/shell/henri.launchpad-v3/tests/vptr
sig() { cat "$R/sig" 2>/dev/null; }
. "$repo/shell/rig/nested-guard.sh"
nwl() { nested_wl "$(sig)"; }   # never the live compositor (an empty one fell back to the live Xwayland)
alive() { [[ -n $(sig) ]] && HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl version >/dev/null 2>&1; }
nh() { HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl "$@"; }
nenv() { env -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY="$(nwl)" HYPRLAND_INSTANCE_SIGNATURE="$(sig)" QT_QPA_PLATFORM=wayland \
  XDG_CACHE_HOME="$R/home/cache" XDG_STATE_HOME="$R/home/state" HARNESS_OUTPUT=$OUT VELUM_V4_SEARCH_RIG=1 "$@"; }
# the harness's quickshell, found by its marker (never by a pattern of this command line)
qspid() { for p in $(pgrep -x quickshell; pgrep -x qs); do grep -qz '^VELUM_V4_SEARCH_RIG=1$' /proc/$p/environ 2>/dev/null && echo $p; done; }

stage() {
  rm -rf "$S"; mkdir -p "$S"
  cp "$here/search-harness/shell.qml" "$plugin"/SearchView.qml "$plugin"/AppDrawer.qml "$plugin"/DrawerMenu.qml "$plugin"/SearchScore.js "$S/"
  # Roboto: the plugin's own copy (phase 1 bundles it); else the main checkout's; else none (Theme.font)
  for f in "$plugin/fonts" "$HOME/Projects/velum/shell/henri.tablet-v4/fonts"; do
    [[ -f $f/Roboto-Regular.ttf ]] && { cp -r "$f" "$S/fonts"; break; }
  done
  # the plugin imports Velum by an absolute path (the live link): the staged copies take this checkout's
  sed -i "s|file:///home/henri/.local/share/velum/qml/Velum|file://$repo/qml/Velum|" "$S"/*.qml
  python3 "$repo/build/velum_build.py" >/dev/null || { echo "token build failed"; exit 1; }
}

case "${1:-}" in
  up)
    [[ -x $vptr/vptr ]] || "$vptr/build.sh"
    if ! alive; then
      python3 "$repo/build/velum_build.py" >/dev/null || exit 1
      ls "$HY" | sort > "$R/.before"
      env="systemd-run --user --scope --quiet --slice=agents.slice -p CPUWeight=20 env HYPRLAND_NO_SD_VARS=1 HYPRLAND_NO_SD_NOTIFY=1 HYPRLAND_NO_CRASHREPORTER=1 VELUM_SCALE=1"
      hyprctl eval "hl.exec_cmd('$env Hyprland -c $repo/lab/rig/nested.lua', { workspace = 'name:spare silent', float = true, size = '960 640' })" >/dev/null
      rm -f "$R/sig"
      for _ in $(seq 50); do
        sleep 0.2; new=$(comm -13 "$R/.before" <(ls "$HY" | sort) | head -1)
        if [[ -n $new ]] && HYPRLAND_INSTANCE_SIGNATURE=$new hyprctl version >/dev/null 2>&1; then echo "$new" > "$R/sig"; break; fi
      done
      alive || { echo "nested did not come up"; exit 1; }
    fi
    nh monitors -j | jq -e ".[] | select(.name==\"$OUT\")" >/dev/null || nh output create headless $OUT >/dev/null
    sleep 0.5
    nh eval "hl.monitor({ output = '$OUT', mode = '${W}x${H}@60', position = '2000x0', scale = 1 })" >/dev/null
    nh dispatch "hl.dsp.focus({ monitor = '$OUT' })" >/dev/null
    "$0" shell ;;
  stage) stage; echo "$S" ;;
  shell)
    for p in $(qspid); do kill "$p"; done; sleep 0.3
    stage
    nenv setsid -f quickshell -p "$S/shell.qml" > "$R/harness.log" 2>&1
    for _ in $(seq 30); do sleep 0.3; [[ $("$0" call apps 2>/dev/null) == *count* ]] && break; done
    echo "harness pid $(qspid) on $(nwl)"; "$0" call apps | head -c 300; echo ;;
  call) shift; nenv timeout 5 quickshell ipc -p "$S/shell.qml" call search-harness "$@" ;;
  ptr) shift; WAYLAND_DISPLAY=$(nwl) "$vptr/vptr" $OUT $W $H "$@" ;;
  shot) WAYLAND_DISPLAY=$(nwl) timeout 5 grim -o $OUT "$R/shots/$2.png" && echo "$R/shots/$2.png" ;;
  log) sed 's/\x1b\[[0-9;]*m//g' "$R/harness.log" | tail -${2:-40} ;;
  down)
    for p in $(qspid); do kill "$p"; done
    alive && nh dispatch "hl.dsp.exit()" >/dev/null 2>&1
    rm -f "$R/sig"; echo stopped ;;
  *) echo "usage: search-rig.sh up | stage | shell | call FN [ARGS…] | ptr CMDS… | shot NAME | log | down"; exit 2 ;;
esac
