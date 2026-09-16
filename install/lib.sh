#!/bin/bash
# Shared helpers. Sourced by every install/*.sh script.

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTFILES_ROOT

# Set DRY_RUN=1 to print actions without changing anything.
: "${DRY_RUN:=0}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
skip() { printf '    \033[2mskip\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  ! \033[0m%s\n' "$*" >&2; }
die()  { printf '\033[1;31m  ✗ \033[0m%s\n' "$*" >&2; exit 1; }

run() {
  if [[ $DRY_RUN == 1 ]]; then
    printf '    \033[2m[dry-run]\033[0m %s\n' "$*"
  else
    "$@"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Shorten $HOME to ~ for display. $HOME must be quoted inside the pattern:
# unquoted, it expands to /home/<user> and bash then reads the pattern as
# ending at its first slash, so the substitution silently does nothing.
tilde() { local p="$1"; printf '%s' "${p/#"$HOME"/\~}"; }

# Clear an existing real file so stow can put its symlink there.
# Identical content is simply removed (nothing to preserve); genuinely
# different content is kept as a timestamped backup.
#   $1 = target path in $HOME   $2 = corresponding file in the repo
clear_for_stow() {
  local target="$1" source="$2"
  [[ -e $target || -L $target ]] || return 0
  [[ -L $target ]] && return 0   # already a symlink; stow will re-point it

  if cmp -s "$target" "$source"; then
    run rm -f "$target"
    return 0
  fi

  local bak="${target}.pre-dotfiles.$(date +%s)"
  warn "differs from the repo copy: $(tilde "$target")"
  info "kept as ${bak##*/}"
  run mv "$target" "$bak"
}

# Require a command. In a real run a missing tool is fatal; in a dry run it
# only warns, so the preview can continue through the remaining steps.
need_cmd() {
  local cmd="$1" hint="${2:-}"
  have "$cmd" && return 0
  if [[ $DRY_RUN == 1 ]]; then
    warn "$cmd not installed — continuing dry run anyway"
    return 0
  fi
  die "$cmd not installed${hint:+ — $hint}"
}
