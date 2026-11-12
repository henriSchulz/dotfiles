#!/bin/bash
# The Quick Settings harness (henri.tablet-v4/qs) in a nested Hyprland, never on Henri's screen:
#   - the nested compositor of shell/rig/rig.sh (VELUM_RIG_ID=v4qs, hidden on the live workspace name:spare),
#   - a headless output QS inside it (QS_W × QS_H, default the Acer's 1440 × 960) for grim,
#   - a plain Quickshell running tests/qs-harness/shell.qml with a copy of qs/ whose Velum import points at
#     THIS checkout, its own XDG_STATE_HOME (tablet-qs.json) and XDG_CACHE_HOME,
#   - the backend never live: every command is only logged.
#   QS_RIG_ID (default v4qs) names the rig, its state and the harness's process marker: a second checkout
#   (a worktree) runs its own harness beside this one.
#
#   harness.sh up [light|dark]   start (or restart the harness shell in) the rig
#   harness.sh call METHOD ARGS…  IPC to the harness (target "qs")
#   harness.sh shot NAME         grim of the QS output → shots/NAME.png
#   harness.sh frames NAME CALL… N=12 STEP=0.06 frames from the call on (Theme.speed SPEED, default 4)
#   harness.sh pt CMDS…          the virtual pointer on QS (henri.launchpad-v3/tests/vptr: m X Y, d, u, g X Y STEPS MS …)
#   harness.sh log | down
set -u
here=$(cd "$(dirname "$0")" && pwd); plugin=$(cd "$here/../.." && pwd); shell=$(dirname "$plugin"); repo=$(dirname "$shell")
export VELUM_RIG_ID=${QS_RIG_ID:-v4qs}
R=$shell/rig/state/$VELUM_RIG_ID; RUN=$R/qs-run; SHOTS=${SHOTS:-$R/shots}
W=${QS_W:-1440} H=${QS_H:-960}
MARK="qs-harness-$VELUM_RIG_ID"
vptr=$shell/henri.launchpad-v3/tests/vptr
sig() { cat "$R/sig" 2>/dev/null; }
. "$shell/rig/nested-guard.sh"
nwl() { nested_wl "$(sig)"; }   # never the live compositor (an empty one fell back to the live Xwayland)
hpid() { for p in $(pgrep -x quickshell; pgrep -x qs); do grep -qz "^QS_HARNESS=$MARK\$" /proc/$p/environ 2>/dev/null && echo $p; done; }
up_nested() { [[ -n $(sig) ]] && HYPRLAND_INSTANCE_SIGNATURE=$(sig) hyprctl version >/dev/null 2>&1; }
roboto=$plugin/fonts      # the plugin's own Roboto (Home.qml loads the same files in the shell)
case "${1:-}" in
  up)
    up_nested || "$shell/rig/rig.sh" start >/dev/null || exit 1
    export HYPRLAND_INSTANCE_SIGNATURE=$(sig)
    hyprctl monitors -j | jq -e '.[] | select(.name=="QS")' >/dev/null || hyprctl output create headless QS >/dev/null
    sleep 0.5
    hyprctl eval "hl.monitor({ output = 'QS', mode = '${W}x${H}@60', position = '2000x0', scale = 1 })" >/dev/null
    sleep 0.3
    nested_check "$(sig)" || exit 1
    for p in $(hpid); do kill "$p"; done
    rm -rf "${RUN:?}"; mkdir -p "$RUN" "$R/state" "$R/cache" "$SHOTS"
    cp "$here/shell.qml" "$RUN/"; cp -r "$plugin/qs" "$RUN/qs"
    grep -rl "file:///home/henri/.local/share/velum" "$RUN" --include=*.qml | xargs -r sed -i "s|file:///home/henri/.local/share/velum|file://$repo|g"
    wall=$(readlink -f /home/henri/.local/state/omarchy/current/background)
    env -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY="$(nwl)" HYPRLAND_INSTANCE_SIGNATURE="$(sig)" QT_QPA_PLATFORM=wayland \
      XDG_STATE_HOME="$R/state" XDG_CACHE_HOME="$R/cache" QS_HARNESS=$MARK VELUM_SHELL_RIG=$MARK \
      QS_OUTPUT=QS QS_APPEARANCE="${2:-light}" QS_VARIANT="${QS_VARIANT:-opal}" QS_WALLPAPER="$wall" \
      QS_ROBOTO_400="$roboto/Roboto-Regular.ttf" QS_ROBOTO_500="$roboto/Roboto-Medium.ttf" \
      setsid -f quickshell -p "$RUN" > "$R/qs.log" 2>&1
    for _ in $(seq 30); do sleep 0.3; [[ -n $(hpid) ]] && "$0" call state >/dev/null 2>&1 && break; done
    "$0" call state ;;
  call) shift; p=$(hpid | head -1); [[ -n $p ]] || { echo "no harness"; exit 1; }
    timeout 3 quickshell ipc --pid "$p" call qs "$@" ;;
  shot) WAYLAND_DISPLAY=$(nwl) timeout 5 grim -o QS "$SHOTS/$2.png" && echo "$SHOTS/$2.png" ;;
  frames)
    name=$2; shift 2; wl=$(nwl); n=${N:-12} step=${STEP:-0.06}
    "$0" call speed "${SPEED:-4}" >/dev/null
    find "${SHOTS:?}" -maxdepth 1 -name "${name:?}-[0-9]*.png" -delete
    "$0" call "$@" >/dev/null
    for i in $(seq -w 1 "$n"); do WAYLAND_DISPLAY=$wl timeout 5 grim -l 0 -o QS "$SHOTS/$name-$i.png"; sleep "$step"; done
    "$0" call speed 1 >/dev/null
    ls "$SHOTS/$name"-[0-9]*.png ;;
  pt) shift; [[ -x $vptr/vptr ]] || "$vptr/build.sh" >/dev/null
    WAYLAND_DISPLAY=$(nwl) "$vptr/vptr" QS "$W" "$H" "$@" ;;
  log) sed 's/\x1b\[[0-9;]*m//g' "$R/qs.log" | grep -iE "${2:-warn|error|qs dry-run|not a type|undefined}" | tail -40 ;;
  down) for p in $(hpid); do kill "$p"; done; "$shell/rig/rig.sh" stop ;;
  *) sed -n 2,16p "$0"; exit 2 ;;
esac
