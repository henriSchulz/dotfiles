#!/bin/bash
# Facts for the "Über diesen Computer" card, one key=value per line.

# df prints "494G"; macOS writes "494 GB".
disk() { df -h --output="$1" / | tail -1 | tr -d ' ' | sed -E 's/([KMGT])$/ \1B/'; }

vendor=$(</sys/class/dmi/id/sys_vendor)
product=$(</sys/class/dmi/id/product_name)
echo "model=${vendor%% Inc.} $product"
echo "host=$(hostnamectl --pretty 2>/dev/null | grep . || cat /etc/hostname)"
cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed -E 's/^ +//; s/\((R|TM)\)//g; s/ @.*//; s/ CPU//; s/[0-9]+th Gen //')
echo "cpu=$cpu"
echo "memory=$(awk '/MemTotal/{printf "%.0f GB", $2/1000/1000}' /proc/meminfo)"
echo "gpu=$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -1 | sed -E 's/.*: //; s/Corporation //; s/ \(rev .*//; s/.*\[(.*)\].*/\1/')"
echo "disk=$(disk avail) frei von $(disk size)"
echo "omarchy=$(omarchy-version 2>/dev/null)"
echo "kernel=$(uname -r)"
echo "uptime=$(uptime -p | sed -E 's/^up //; s/weeks?/Wo./; s/days?/T./; s/hours?/Std./; s/minutes?/Min./')"
