#!/bin/bash
# Dictation (voxtype), set up for speed on this laptop.
#
# The package default is Whisper `small` on the CPU, which costs ~10 s per
# recording on the i7-1185G7 no matter how short the recording is: whisper
# always pushes a padded 30 s window through its encoder. Parakeet TDT v3
# (int8) covers German among 25 European languages and does the same 10 s of
# audio in ~1 s, because its cost scales with the actual length.
#
# Two things have to line up for that:
#   1. the ONNX build of voxtype must be the one that runs — /usr/bin/voxtype
#      points at the Whisper-only build, and repointing it needs root, so the
#      systemd drop-in from stow/voxtype overrides ExecStart instead;
#   2. engine + model in ~/.config/voxtype/config.toml.
#
# config.toml is rewritten by `voxtype config set` and `voxtype configure`, so
# by this repo's rule it is generated here, never symlinked.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Dictation (voxtype)"

need_cmd voxtype "run install/10-packages.sh first"

onnx=/usr/lib/voxtype/voxtype-onnx-avx512
model=parakeet-tdt-0.6b-v3-int8

if [[ ! -x $onnx ]]; then
  warn "$onnx missing — voxtype-bin may have dropped the ONNX build"
  exit 0
fi

# ~650 MB, only fetched when it is not already there.
if [[ -f "$HOME/.local/share/voxtype/models/$model/encoder-model.int8.onnx" ]]; then
  skip "model $model already downloaded"
else
  info "downloading $model (~650 MB)"
  run "$onnx" setup --download --model "$model"
fi

# set only what differs from the package defaults
run "$onnx" config set engine parakeet
run "$onnx" config set parakeet.model "$model"
# voxtype's own hotkey reads /dev/input directly, which needs the 'input'
# group. Without it the built-in hotkey silently never fires, so the key is
# bound in Hyprland instead (stow/hypr/.config/hypr/bindings.lua, Control_R).
run "$onnx" config set hotkey.enabled false

run systemctl --user daemon-reload
run systemctl --user enable --now voxtype.service
run systemctl --user restart voxtype.service
