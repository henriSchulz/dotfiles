#!/bin/bash
# Facts for the "About This Computer" card, one key=value per line.

# df prints "494G"; macOS writes "494 GB".
disk() { df -h --output="$1" / | tail -1 | tr -d ' ' | sed -E 's/([KMGT])$/ \1B/'; }

vendor=$(</sys/class/dmi/id/sys_vendor)
product=$(</sys/class/dmi/id/product_name)
model="${vendor%% Inc.} $product"
# Apple model identifiers as macOS names them
case "$product" in
  MacBookAir10,1) model="MacBook Air (M1, 2020)" ;; MacBookPro17,1) model="MacBook Pro (13-inch, M1, 2020)" ;;
  Macmini9,1) model="Mac mini (M1, 2020)" ;; iMac21,1|iMac21,2) model="iMac (24-inch, M1, 2021)" ;;
esac
echo "model=$model"
echo "host=$(hostnamectl --pretty 2>/dev/null | grep . || cat /etc/hostname)"
cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed -E 's/^ +//; s/\((R|TM)\)//g; s/ @.*//; s/ CPU//; s/[0-9]+th Gen //')
# Apple silicon (Asahi): no model name in /proc/cpuinfo, no PCI GPU — the SoC from the device tree.
if [[ -z $cpu && -r /sys/firmware/devicetree/base/compatible ]]; then
  case "$(tr '\0' ' ' < /sys/firmware/devicetree/base/compatible)" in
    *t8103*) soc="Apple M1" ;; *t6000*) soc="Apple M1 Pro" ;; *t6001*) soc="Apple M1 Max" ;; *t6002*) soc="Apple M1 Ultra" ;;
    *t8112*) soc="Apple M2" ;; *t6020*) soc="Apple M2 Pro" ;; *t6021*) soc="Apple M2 Max" ;;
  esac
  cpu=$soc
fi
echo "cpu=$cpu"
echo "memory=$(awk '/MemTotal/{printf "%.0f GB", $2/1000/1000}' /proc/meminfo)"
gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -1 | sed -E 's/.*: //; s/Corporation //; s/ \(rev .*//; s/.*\[(.*)\].*/\1/')
[[ -z $gpu && -n ${soc:-} ]] && gpu="$soc GPU"
echo "gpu=$gpu"
echo "disk=$(disk avail) available of $(disk size)"
echo "omarchy=$(omarchy-version 2>/dev/null)"
echo "kernel=$(uname -r)"
echo "uptime=$(uptime -p | sed -E 's/^up //; s/ weeks?/ wk/; s/ days?/ d/; s/ hours?/ h/; s/ minutes?/ min/')"
