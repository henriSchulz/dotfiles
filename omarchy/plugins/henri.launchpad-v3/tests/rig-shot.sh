#!/bin/bash
# shot NAME: grab the nested headless output LP into replica/clone-screens/NAME.png
cd ~/Projects/velum/shell
out=~/Projects/launchpad/replica/clone-screens; mkdir -p $out
HYPRLAND_INSTANCE_SIGNATURE=$(cat rig/state/launchpad/sig) WAYLAND_DISPLAY=$(HYPRLAND_INSTANCE_SIGNATURE=$(cat rig/state/launchpad/sig) hyprctl instances -j | jq -r --arg s "$(cat rig/state/launchpad/sig)" '.[] | select(.instance==$s) | .wl_socket') timeout 5 grim -o LP "$out/$1.png" && echo "$out/$1.png"
