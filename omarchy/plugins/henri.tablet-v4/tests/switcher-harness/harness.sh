#!/bin/bash
# The App Switcher / widgets harness: a nested Hyprland of its own (shell/rig/rig.sh with VELUM_RIG_ID=v4sw,
# parked hidden on name:spare) with a headless output SW (1440 × 960, the Acer's size), a few foot windows
# on its workspaces, and a plain Quickshell running shell.qml with this checkout's switcher/ and widgets/
# (their Velum import rewritten to THIS checkout's module, so the worktree's tokens count). Every process
# carries the rig's marker (rig.sh stop ends them); nothing touches the live shell or ~/.config.
#   harness.sh up | qs | foot N | call FN ARGS… | shot NAME | ptr ARGS… | clients | log | down
set -u
here=$(cd "$(dirname "$0")" && pwd); plugin=$(cd "$here/../.." && pwd); shell=$(dirname "$plugin"); repo=$(dirname "$shell")
export VELUM_RIG_ID=${HARNESS_ID:-v4sw}
R=$shell/rig/state/$VELUM_RIG_ID B=$R/harness W=1440 H=960 OUT=SW
MARK="VELUM_SHELL_RIG=$VELUM_RIG_ID-hidden"
FONTS=${HARNESS_FONTS:-$plugin/fonts}   # the plugin's own Roboto (400/500/700 + 300 for the clock)
vptr=$shell/henri.launchpad-v3/tests/vptr
sig() { cat "$R/sig" 2>/dev/null; }
. "$shell/rig/nested-guard.sh"
nwl() { nested_wl "$(sig)"; }   # never the live compositor (an empty one fell back to the live Xwayland)
nhy() { HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl "$@"; }
nenv() { nested_check "$(sig)" || return 1; env -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY="$(nwl)" HYPRLAND_INSTANCE_SIGNATURE="$(sig)" QT_QPA_PLATFORM=wayland "$MARK" "$@"; }
qspid() { for p in $(pgrep -x quickshell; pgrep -x qs); do grep -qz "^$MARK\$" /proc/$p/environ 2>/dev/null && echo $p; done | head -1; }
assemble() {
  rm -rf "$B"; mkdir -p "$B"
  cp "$here/shell.qml" "$B/"; cp -r "$plugin/switcher" "$plugin/widgets" "$B/"
  grep -rl "file:///home/henri/.local/share/velum" "$B" --include=*.qml --include=*.js | xargs -r sed -i "s|file:///home/henri/.local/share/velum|file://$repo|g"
}
case "${1:-}" in
  up)
    if ! { [[ -n $(sig) ]] && nhy version >/dev/null 2>&1; }; then "$shell/rig/rig.sh" start >/dev/null || exit 1; fi
    nhy monitors -j | jq -e ".[] | select(.name==\"$OUT\")" >/dev/null || nhy output create headless $OUT >/dev/null
    sleep 0.5
    nhy eval "hl.monitor({ output = '$OUT', mode = '${W}x${H}@60', position = '2000x0', scale = 1 })" >/dev/null
    nhy dispatch "hl.dsp.focus({ monitor = '$OUT' })" >/dev/null
    [[ -x $vptr/vptr ]] || "$vptr/build.sh" >/dev/null
    "$0" qs ;;
  qs)
    p=$(qspid); [[ -n $p ]] && kill "$p" && sleep 0.5
    assemble
    nenv HARNESS_FONTS="$FONTS" HARNESS_WALLPAPER="$(readlink -f /home/henri/.local/state/omarchy/current/background)" \
      setsid -f quickshell -n -p "$B" > "$R/harness.log" 2>&1
    for _ in $(seq 20); do sleep 0.3; [[ -n $(qspid) ]] && "$0" call state >/dev/null 2>&1 && break; done
    echo "harness qs $(qspid)" ;;
  # N foot windows, each on its own workspace of SW (tablet mode: one app per workspace), told apart by colour
  foot)
    cols=(1e3a5f 5f1e3a 1e5f3a 5f4b1e 3a1e5f 1e5f5f)
    for i in $(seq 1 "${2:-3}"); do
      ws=$((10 + i))
      nhy dispatch "hl.dsp.focus({ workspace = '$ws' })" >/dev/null
      nenv setsid -f foot -o "colors-dark.background=${cols[$(( (i - 1) % 6 ))]}" -T "Window $i" \
        sh -c "printf '\n\n   Window $i  (workspace $ws)\n'; exec sleep infinity" >/dev/null 2>&1
      sleep 0.6
    done ;;
  clients) nhy clients -j | jq -c '[.[] | {address, class, title, ws: .workspace.name, mon: .monitor, f: .focusHistoryID}]' ;;
  call) shift; p=$(qspid); [[ -n $p ]] || { echo "no harness qs"; exit 1; }
    nenv timeout 3 quickshell ipc --pid "$p" call harness "$@" ;;
  shot) mkdir -p "$R/shots"; WAYLAND_DISPLAY=$(nwl) timeout 5 grim -o $OUT "$R/shots/$2.png" && echo "$R/shots/$2.png" ;;
  ptr) shift; WAYLAND_DISPLAY=$(nwl) "$vptr/vptr" $OUT $W $H "$@" ;;
  log) sed 's/\x1b\[[0-9;]*m//g' "$R/harness.log" | grep -iE "${2:-warn|error|fail|not a type|undefined}" | tail -30 ;;
  down) "$shell/rig/rig.sh" stop ;;
  *) echo "usage: harness.sh up | qs | foot N | call FN ARGS… | shot NAME | ptr ARGS… | clients | log | down"; exit 2 ;;
esac
