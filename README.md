# dotfiles

Reproducible setup for an Omarchy / Hyprland machine. Idempotent — run it as
often as you like.

```bash
git clone https://github.com/henriSchulz/dotfiles ~/Projects/dotfiles
cd ~/Projects/dotfiles
DRY_RUN=1 ./install_all.sh   # preview, changes nothing
./install_all.sh             # apply
```

Run a single step by number: `./install_all.sh 40`.

Method follows [`omarchy_setup_guide.md`](omarchy_setup_guide.md); the
inventory that produced this layout is in [`SETUP_NOTES.md`](SETUP_NOTES.md).

## The rule that shapes this repo

> **Symlink what only I write. Generate what Omarchy writes.**

`~/.config/omarchy/` is rewritten at runtime — `omarchy theme set` writes into
it, the shell rewrites `shell.json` on save. A read-only stow symlink there
breaks those writes, so that tree is **copied** by a script, never linked.
Everything under `stow/` is safe to symlink.

## What is here — and what deliberately is not

This machine's `~/.config` turned out to be overwhelmingly *stock*. Every file
was diffed against `/usr/share/omarchy/config/`, and only real differences were
committed:

| Tracked | Why |
|---|---|
| `stow/hypr/.config/hypr/input.lua` | +8 lines: German keyboard layout |
| `stow/nvim/.config/nvim/` | own LazyVim config; Omarchy ships none |
| `stow/git/.config/git/config` | identity + credential helper |
| `omarchy/shell.json` | bar layout, widget order, idle timers |
| `omarchy/keystroke.json`, `omarchy/defaults/agent` | small real settings |
| `omarchy/plugins/henri.menu/` | 658-line divergence from built-in `omarchy.menu`, plus its own `FuzzySearch.js` |
| `omarchy/themes/cupertino{,-dark}`, `img-7075` | hand-built, no upstream remote |
| `packages/packages.txt` | the 13 packages added on top of Omarchy's own lists |

**Not tracked, on purpose:**

- `alacritty`, `btop`, `foot`, `ghostty`, `kitty`, `lazygit`, `tmux` and 8 of
  the 9 files in `hypr/` — all byte-identical to Omarchy's defaults. Committing
  them would freeze today's defaults as symlinks and stop package updates from
  ever improving them.
- `hooks/post-update.d/*.hook` — all three are byte-identical to
  `/usr/share/omarchy/install/user/first-run/`. Installer artifacts, not
  configuration. There is no hooks step because there is nothing to install.
- `extensions/omarchy-menu.jsonc` — the shipped template, comments only, zero
  active entries.
- `branding/about.txt`, `branding/screensaver.txt` — copies of the package's
  own `icon.txt` and `logo.txt`.
- `themes/aether` — empty; `aether` is a pacman package, not a user theme.
- Omarchy's own base packages, plus `efibootmgr`, `intel-ucode`, `mkinitcpio`
  and `sudo`. The Omarchy installer owns those; reinstalling boot packages from
  a dotfiles repo is the wrong layer.
- No hyprpm step: the hyprpm state store was never initialised on this machine,
  so there are no plugins to restore.

## Wallpaper

`cupertino` and `img-7075` both reference `IMG_7075.png`, a 32 MB personal
photo. It is kept out of this public repo. Put it at `~/Wallpapers/IMG_7075.png`
(or pass `IMG_7075_PATH=<path>`) and step 40 copies it into both themes; without
it, those themes fall back to their remaining backgrounds.

Keeping it out is also what holds the repo at ~1.8 MB instead of 237 MB.

## Open item: `henri.keystroke`

`~/.config/omarchy/plugins/henri.keystroke` is a clean two-commit fork of
`evindor.keystroke` 1.4.2 that swaps the Codex integration for Claude Code:

```
bb76719 Replace the Codex integration with Claude Code
3c2159a Fork evindor.keystroke 1.4.2 as henri.keystroke baseline
```

It has **no git remote**, so it cannot be restored on a new machine. At 22 MB
with its own history it does not belong vendored in here — it wants its own
repository. Once it is pushed:

```bash
HENRI_KEYSTROKE_URL=https://github.com/henriSchulz/keystroke ./install_all.sh 30
```

Until then step 30 warns and carries on rather than failing the run.

## Layout

```
install_all.sh              runs install/[0-9][0-9]-*.sh in order
install/
  lib.sh                    logging, DRY_RUN, stow-conflict handling
  10-packages.sh            yay -S --noconfirm --needed
  20-stow.sh                symlink stow/ into $HOME
  30-omarchy-plugins.sh     re-add upstream plugins; sync henri.menu
  40-omarchy-themes.sh      install themes, place wallpaper, apply theme
  50-omarchy-config.sh      copy shell.json & friends into place
  60-shibumi.sh             install/update the Shibumi shell suite
packages/packages.txt
stow/                       symlinked into $HOME
omarchy/                    copied into ~/.config/omarchy
```

`20-stow.sh` clears whatever sits where a symlink needs to go. A file identical
to the repo copy is removed outright; one that genuinely differs is preserved as
`<name>.pre-dotfiles.<timestamp>`.
