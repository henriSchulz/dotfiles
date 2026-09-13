#!/bin/bash
# Install or update the Shibumi shell suite.
#
# Two paths, preferred first:
#   AUR      omarchy pkg aur add shibumi-shell && shibumi-shell install --yes
#   source   ~/Projects/Shibumi-Shell/scripts/shibumi-suite install --yes
# The AUR package for the 0.1.1-beta candidate is not published yet, so today
# every machine takes the source path. Once it lands, this step switches over
# on its own — nothing to edit here.
#
# Shibumi's runtime packages live in packages/packages.txt, so 10-packages.sh
# has already put them in place by the time this runs.
#
# Runs LAST on purpose: Shibumi rewrites ~/.config/omarchy/shell.json to its
# own plugin layout, so it has to be the final writer, after
# 50-omarchy-config.sh has restored the plain Omarchy one.
# Set SHIBUMI_SKIP=1 to keep a machine on the Omarchy bar instead.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "Shibumi shell"

if [[ ${SHIBUMI_SKIP:-0} == 1 ]]; then
  skip "SHIBUMI_SKIP=1"
  exit 0
fi

need_cmd omarchy "run this on a provisioned Omarchy system"
need_cmd git

src="${SHIBUMI_SRC:-$HOME/Projects/Shibumi-Shell}"
url="${SHIBUMI_URL:-https://github.com/HANCORE-linux/Shibumi-Shell.git}"
state="${SHIBUMI_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/shibumi}/install.json"

# Pull the package in only when it actually exists in the AUR; asking
# `omarchy pkg aur add` for a package that was never published just fails.
if ! have shibumi-shell && have yay && yay -Si shibumi-shell &>/dev/null; then
  info "installing shibumi-shell from the AUR"
  run omarchy pkg aur add shibumi-shell
fi

if have shibumi-shell; then
  info "using the packaged shibumi-shell"
  suite=(shibumi-shell)
else
  if [[ -d $src/.git ]]; then
    # This checkout is also where Shibumi gets developed, so never touch a
    # dirty or detached tree — a failed pull would abort the whole run.
    if [[ -n $(git -C "$src" status --porcelain) ]]; then
      warn "${src/#$HOME/~} has local changes — installing it as-is, no pull"
    elif ! git -C "$src" rev-parse --abbrev-ref '@{upstream}' &>/dev/null; then
      warn "${src/#$HOME/~} has no upstream branch — installing it as-is, no pull"
    else
      info "updating ${src/#$HOME/~}"
      run git -C "$src" pull --ff-only
    fi
  else
    info "cloning Shibumi into ${src/#$HOME/~}"
    run git clone "$url" "$src"
  fi
  suite=("$src/scripts/shibumi-suite")
  [[ -x ${suite[0]} || $DRY_RUN == 1 ]] || die "missing ${suite[0]}"
fi

# `install` refuses to run twice — once the state file exists, `update` is the
# command that keeps an existing installation current.
if [[ -f $state ]]; then
  info "already installed — updating plugin set"
  run "${suite[@]}" update --yes
else
  info "installing and activating the suite"
  run "${suite[@]}" install --yes
fi

info "restart the shell (omarchy-restart-shell) or re-login to pick up the bar"
