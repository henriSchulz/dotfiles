#!/bin/bash
# Continuous battery logging: one CSV per day under ~/Projects/akku-test/verlauf,
# a line every 30 s. The Battery History page (henri.control-center-v3, also
# shown by henri.power-v3) and the settings backend both read that folder.
#
#   unit     akku-aufzeichnung.service — stowed by 20-stow.sh
#   enable   here
#   script   ~/Projects/akku-test/hintergrund.py — in the akku-test project,
#            NOT in this repo: it comes with a 180 MB venv (matplotlib, for
#            grafik_mpl.py) and the recorded CSVs, which are measurements, not
#            configuration. On a machine without it the unit's
#            ConditionPathExists skips the service cleanly instead of letting
#            Restart=always retry every 10 s.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Akku-Aufzeichnung"

script="$HOME/Projects/akku-test/hintergrund.py"
if [[ ! -f $script ]]; then
  warn "missing $(tilde "$script") — enabling the service anyway;"
  warn "it stays inactive (ConditionPathExists) until the akku-test project is there"
fi

info "enabling akku-aufzeichnung.service"
run systemctl --user enable --now akku-aufzeichnung.service
