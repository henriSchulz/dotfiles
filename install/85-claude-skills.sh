#!/bin/bash
# Third-party Claude Code skills, cloned at a pinned commit.
#
# These are NOT vendored into this repo: apple-design carries Apple's Human
# Interface Guidelines text verbatim (no license to redistribute), and this
# repo is public. Cloning from upstream keeps the restore reproducible
# without republishing it. Own skills live in stow/claude-skills instead.
#
# Bump a pin: change the commit below, run this step, check the skill still
# fits henri-ui (it is the reviewer; henri-ui stays the source of truth).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Claude Code skills (third-party, pinned)"

need_cmd git "run install/10-packages.sh first"

skills_dir="$HOME/.claude/skills"
run mkdir -p "$skills_dir"

# name  repo  commit
skills=(
  "apple-design https://github.com/dickwu/apple-design-skill da2da6d"
)

for entry in "${skills[@]}"; do
  read -r name repo commit <<<"$entry"
  dest="$skills_dir/$name"
  if [[ ! -d $dest/.git ]]; then
    info "cloning $name"
    run git clone --quiet "$repo" "$dest"
  fi
  if [[ $DRY_RUN != 1 ]] && [[ $(git -C "$dest" rev-parse --short HEAD) == "$commit"* ]]; then
    skip "$name already at $commit"
    continue
  fi
  run git -C "$dest" fetch --quiet origin
  run git -C "$dest" -c advice.detachedHead=false checkout --quiet "$commit"
  info "$name → $commit"
done
