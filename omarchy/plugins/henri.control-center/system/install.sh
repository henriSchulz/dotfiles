#!/bin/bash
# Installs the Hardware page helper: a root-owned copy in /usr/local/bin and a
# sudoers rule so the Control Center can call it without a password prompt.
# The plugin copy stays user-writable, which is why sudo never points at it.
set -euo pipefail

src="$(dirname "$(readlink -f "$0")")/henri-hwctl"
user="${SUDO_USER:-$USER}"
rule=/etc/sudoers.d/henri-hwctl

(( EUID == 0 )) || exec sudo "$0" "$@"

install -o root -g root -m 0755 "$src" /usr/local/bin/henri-hwctl

tmp=$(mktemp)
printf '%s ALL=(root) NOPASSWD: /usr/local/bin/henri-hwctl\n' "$user" > "$tmp"
visudo -cqf "$tmp"
install -o root -g root -m 0440 "$tmp" "$rule"
rm -f "$tmp"

echo "Installed /usr/local/bin/henri-hwctl and $rule"
