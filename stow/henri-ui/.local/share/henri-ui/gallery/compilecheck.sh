#!/bin/bash
# Compile-check QML files or whole plugin dirs against the real shell modules.
#   compilecheck.sh <file-or-dir>...
set -euo pipefail
files=()
for a in "$@"; do
  if [[ -d $a ]]; then
    while IFS= read -r f; do files+=("$(realpath "$f")"); done < <(find "$a" -name '*.qml' -not -path '*/node_modules/*' -not -path '*/site/*' | sort)
  else files+=("$(realpath "$a")"); fi
done
IFS=:; list="${files[*]}"; unset IFS
# Needs the real Wayland session: layer-shell types (PanelWindow) only compile
# with a Wayland backend. Nothing is shown — components are compiled, not created.
HUI_CHECK="$list" timeout 60 quickshell -p "$(dirname "$0")/compilecheck.qml" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'COMPILE (FAIL|RESULT)'
