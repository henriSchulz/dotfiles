#!/bin/bash
# usage: VELUM_RIG_ID=launchpad VELUM_RIG_PLUGINS=henri.launchpad-v3 shell/rig/rig.sh start && … sync, then this script; the nested rig needs a headless output LP:
#   HYPRLAND_INSTANCE_SIGNATURE=$(cat shell/rig/state/launchpad/sig) hyprctl output create headless LP
# launchpad rig: copy the plugin in, keep it enabled, restart the rig shell
cd ~/Projects/velum/shell
export VELUM_RIG_ID=launchpad VELUM_RIG_PLUGINS="henri.launchpad-v3"
F=rig/state/launchpad/home/.config/omarchy
rm -rf $F/plugins/henri.launchpad-v3 && cp -r henri.launchpad-v3 $F/plugins/
jq -e '.plugins | map(.id) | index("henri.launchpad-v3")' $F/shell.json >/dev/null || { jq '.plugins += [{"id":"henri.launchpad-v3"}]' $F/shell.json > $F/shell.json.tmp && mv $F/shell.json.tmp $F/shell.json; }
rig/rig.sh shell >/dev/null
for _ in $(seq 20); do sleep 0.5; r=$(rig/rig.sh call shell call henri.launchpad-v3 state "" 2>/dev/null); [[ $r == "{"* && $r != *'"apps":0'* ]] && break; done
echo "$r"
