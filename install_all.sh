#!/bin/bash
# Bring this machine to the configured state. Idempotent — safe to re-run.
#
#   ./install_all.sh              run everything
#   DRY_RUN=1 ./install_all.sh    show what would change, touch nothing
#   ./install_all.sh 20 40        run only the steps whose number matches
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
source install/lib.sh

[[ -r /etc/arch-release ]] || warn "this does not look like an Arch system — continuing anyway"

mapfile -t steps < <(find install -maxdepth 1 -name '[0-9][0-9]-*.sh' -printf '%f\n' | sort)
((${#steps[@]})) || die "no install steps found under install/"

# Optional numeric filters, e.g. `./install_all.sh 20 40`.
if (($# > 0)); then
  filtered=()
  for step in "${steps[@]}"; do
    for want in "$@"; do
      [[ $step == "$want"-* ]] && filtered+=("$step")
    done
  done
  ((${#filtered[@]})) || die "no steps matched: $*"
  steps=("${filtered[@]}")
fi

[[ ${DRY_RUN:-0} == 1 ]] && log "DRY RUN — no changes will be made"

for step in "${steps[@]}"; do
  bash "install/$step"
done

log "Done."
