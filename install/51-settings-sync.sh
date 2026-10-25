#!/bin/bash
# Desktop settings shared between the M1 and the tablet: settings-sync
# (settings/sync.json says which files, which keys stay on each machine). The
# shared copies travel in the Syncthing folder henri-settings, cable only like
# step 47. Needs install/47-syncthing.sh first. On a new pair, run it on the
# primary machine (the M1) first: it fills the shared copies, the other one
# only takes from them.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Settings sync"

systemctl --user is-enabled -q syncthing.service 2>/dev/null || { skip "Syncthing not set up (step 47)"; exit 0; }
case "$HOST" in m1) peer=tablet ;; tablet) peer=m1 ;; *) skip "not m1 or tablet"; exit 0 ;; esac

shared="$HOME/.local/state/henri/settings-shared"
cfg="$HOME/.local/state/syncthing/config.xml"
if grep -q 'id="henri-settings"' "$cfg"; then
  skip "Syncthing folder henri-settings exists"
else
  run mkdir -p "$shared"
  key=$(grep -oP '(?<=<apikey>)[^<]+' "$cfg")
  if [[ $DRY_RUN == 1 ]]; then
    info "[dry-run] add Syncthing folder henri-settings -> $(tilde "$shared")"
  else
    python3 - "$key" "$peer" "$shared" <<'PY'
import json, sys, urllib.request
key, peer_name, path = sys.argv[1:]
def api(p, method="GET", body=None):
    r = urllib.request.Request("http://127.0.0.1:8384" + p, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"X-API-Key": key, "Content-Type": "application/json"})
    with urllib.request.urlopen(r) as h:
        d = h.read(); return json.loads(d) if d else None
own = api("/rest/system/status")["myID"]
peer = next(d["deviceID"] for d in api("/rest/config/devices") if d["name"] == peer_name)
f = api("/rest/config/defaults/folder")
f.update({"id": "henri-settings", "label": "Settings", "path": path, "type": "sendreceive",
          "devices": [{"deviceID": own}, {"deviceID": peer}], "fsWatcherEnabled": True,
          "fsWatcherDelayS": 1, "rescanIntervalS": 600,
          "versioning": {"type": "trashcan", "params": {"cleanoutDays": "30"}, "cleanupIntervalS": 3600}})
api("/rest/config/folders", "POST", f)
PY
    info "added Syncthing folder henri-settings"
  fi
fi

if systemctl --user is-enabled -q settings-sync.service 2>/dev/null; then
  skip "settings-sync.service already enabled"
else
  run systemctl --user daemon-reload
  run systemctl --user enable --now settings-sync.service
fi
