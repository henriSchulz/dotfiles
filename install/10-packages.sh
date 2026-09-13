#!/bin/bash
# Install the packages listed in packages/packages.txt.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Packages"

need_cmd yay "run this on a provisioned Omarchy system"

list="$DOTFILES_ROOT/packages/packages.txt"
[[ -f $list ]] || die "missing $list"

mapfile -t wanted < <(sed 's/#.*//' "$list" | tr -s ' \t' '\n' | grep -v '^$' | sort -u)
((${#wanted[@]})) || { skip "no packages listed"; exit 0; }

# --needed already makes yay idempotent, but filtering first keeps the output
# quiet and avoids touching the network when there is nothing to do.
missing=()
for p in "${wanted[@]}"; do
  pacman -Qq "$p" &>/dev/null || missing+=("$p")
done

if ((${#missing[@]} == 0)); then
  skip "all ${#wanted[@]} packages already installed"
  exit 0
fi

info "installing ${#missing[@]} of ${#wanted[@]}: ${missing[*]}"
run yay -S --noconfirm --needed "${missing[@]}"
