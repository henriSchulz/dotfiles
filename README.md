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

Every file was diffed against `/usr/share/omarchy/config/`, and only real
differences were committed:

| Tracked | Why |
|---|---|
| `stow/hypr/.config/hypr/input.lua` | +8 lines: German keyboard layout |
| `stow/hypr/.config/hypr/looknfeel.lua` | +7 lines: `rounding = 12` |
| `stow/bin/.local/bin/` | `omarchy-{launch-,}screensaver-themed` — the themed screensaver `henri.idle` shells out to. Without these that plugin is inert |
| `stow/nvim/.config/nvim/` | own LazyVim config; Omarchy ships none |
| `stow/git/.config/git/config` | identity + credential helper |
| `omarchy/shell.json` | bar layout, widget order, idle timers |
| `omarchy/keystroke.json`, `omadock.json`, `dock.json`, `defaults/agent` | small real settings |
| `omarchy/plugins/henri.menu/` | 658-line divergence from built-in `omarchy.menu`, plus its own `FuzzySearch.js` |
| `omarchy/plugins/henri.idle/` | clone of `omarchy.idle` that launches the themed screensaver instead of the stock one |
| `omarchy/themes/cupertino{,-dark}`, `img-7075` | hand-built, no upstream remote |
| `obsidian/home/**/.obsidian/` | vault settings, 4 community plugins, the `Crafted` and `Things` themes |
| `packages/packages.txt` | the packages added on top of Omarchy's own lists |

**Not tracked, on purpose:**

- `alacritty`, `btop`, `foot`, `ghostty`, `kitty`, `lazygit`, `tmux` and 7 of
  the 9 files in `hypr/` — all byte-identical to Omarchy's defaults. Committing
  them would freeze today's defaults as symlinks and stop package updates from
  ever improving them.
- **`hypr/omasettings.lua` and `omarchy/omasettings.json`** — machine-specific.
  Both pin a monitor profile for `desc:Messeltronik Dresden GmbH MD20461` at
  1920x1080@60. OmaSettings writes them per machine from whatever hardware is
  actually attached; copying them to a second laptop would force a resolution
  onto a display that does not have it.
- `hooks/post-update.d/*.hook` — all three are byte-identical to
  `/usr/share/omarchy/install/user/first-run/`. Installer artifacts, not
  configuration. There is no hooks step because there is nothing to install.
- `extensions/omarchy-menu.jsonc` — the shipped template, comments only, zero
  active entries.
- `branding/about.txt`, `branding/screensaver.txt` — copies of the package's
  own `icon.txt` and `logo.txt`.
- `themes/aether` — empty; `aether` is a pacman package, not a user theme.
- The Shibumi suite's 25 `hancore.shibumi.*` plugin directories — the suite
  installer owns them, see step 60.
- Omarchy's own base packages, plus `efibootmgr`, `intel-ucode`, `mkinitcpio`
  and `sudo`. The Omarchy installer owns those; reinstalling boot packages from
  a dotfiles repo is the wrong layer.
- No hyprpm step: the hyprpm state store was never initialised on this machine,
  so there are no plugins to restore.

## Ordering: why `shell.json` is restored last

`shibumi-suite install` (step 60) rewrites `~/.config/omarchy/shell.json` to
the suite's own default layout. Anything written there earlier is lost. So the
file is restored *after* Shibumi, in step 70 — that is the only reason that
step is separate from step 50. It carries the slot assignment (`henri.menu` in
the left group), the widgets switched off, the accent and radius, and the idle
timers (screensaver 150s, lock 300s).

## Obsidian

Two vaults: `~/Documents` and `~/Documents/obsidian_sandbox`. Step 80 restores
their `.obsidian/` config, registers them in `~/.config/obsidian/obsidian.json`
so Obsidian and `omarchy-theme-set-obsidian` can both find them, then
regenerates the auto-synced `Omarchy` theme inside each.

Obsidian has no CLI for reinstalling a community plugin, so the four in use
ship as source at pinned versions: `obsidian-icon-folder` 2.14.7,
`obsidian-latex-suite` 1.13.1, `pdf-plus` 0.40.31, `svg-viewer` 0.1.0. The
`Crafted` theme is mine and has no remote; `Things` 2.2.4 is vendored for the
same reason the plugins are. `workspace.json` is not tracked — it is runtime
state, and it would publish note titles to a public repo. Neither are the notes
themselves.

## Wallpaper

`cupertino` and `img-7075` both reference `IMG_7075.png`, a 32 MB personal
photo. It is kept out of this public repo. Step 40 looks for it at
`~/Pictures/Wallpaper/`, `~/Pictures/Wallpapers/` and `~/Wallpapers/`, or
wherever `IMG_7075_PATH=<path>` points, and copies it into both themes; without
it, those themes fall back to their remaining backgrounds. Copy it across from
the other machine — nothing in this repo can restore it.

Keeping it out is also what holds the repo at ~4 MB instead of 237 MB.

## Layout

```
install_all.sh              runs install/[0-9][0-9]-*.sh in order
install/
  lib.sh                    logging, DRY_RUN, stow-conflict handling
  10-packages.sh            yay -S --noconfirm --needed
  20-stow.sh                symlink stow/ into $HOME
  30-omarchy-plugins.sh     re-add upstream plugins; sync henri.menu, henri.idle
  40-omarchy-themes.sh      install themes, place wallpaper, apply theme
  50-omarchy-config.sh      copy keystroke/dock settings into place
  60-shibumi.sh             install/update the Shibumi shell suite
  70-omarchy-shell.sh       restore shell.json — after Shibumi, on purpose
  80-obsidian.sh            vault config, plugins, themes, vault registration
packages/packages.txt
stow/                       symlinked into $HOME
omarchy/                    copied into ~/.config/omarchy
obsidian/home/              copied into $HOME, mirroring vault paths
```

`20-stow.sh` clears whatever sits where a symlink needs to go. A file identical
to the repo copy is removed outright; one that genuinely differs is preserved as
`<name>.pre-dotfiles.<timestamp>`.
