#!/bin/bash
# ~/Projects the same on the M1 and the tablet: every project is a Syncthing
# folder of its own (projects-sync), build output stays out (projects-stignore),
# and committed changes are rebuilt where needed (projects-rebuild,
# projects/rebuild.conf). Needs install/47-syncthing.sh first.
#
# Before the first run on a second machine, its ~/Projects must hold the same
# commits and .git contents as the first one — Syncthing would otherwise mix
# two different .git directories file by file.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Projects sync"

systemctl --user is-enabled -q syncthing.service 2>/dev/null || { skip "Syncthing not set up (step 47)"; exit 0; }
if systemctl --user is-enabled -q projects-sync.timer 2>/dev/null; then
  skip "projects-sync.timer already enabled"
else
  run systemctl --user daemon-reload
  run systemctl --user enable --now projects-sync.timer
fi
