# Manual steps

`./install_all.sh` brings back everything that is a file or a package. This
file is the rest: the things that need a secret, a licensed download, physical
hardware, or a decision that is different on every machine.

Order on a fresh Omarchy install:

```bash
# 1. auth first — install/28 clones private repos
gh auth login                       # or: put an SSH key GitHub knows in ~/.ssh

# 2. this repo
git clone https://github.com/henriSchulz/dotfiles ~/Projects/dotfiles
cd ~/Projects/dotfiles && DRY_RUN=1 ./install_all.sh   # read it once
./install_all.sh

# 3. the private half (Claude config, machine notes)
git clone git@github.com:henriSchulz/dotfiles-private ~/Projects/dotfiles-private
~/Projects/dotfiles-private/install.sh
```

Then work through the sections below.

## 1. Keys and secrets

Nothing in either repo carries a key, and that is deliberate — a private repo
is still a copy on someone else's disk, and a key that only ever existed on
one machine cannot leak from a backup that does not hold it.

| What | How to get it back |
|---|---|
| SSH key | Generate a **new** one (`ssh-keygen -t ed25519`) and add it to GitHub; then delete the old key there. Carrying the old private key over is the only alternative, and it turns one compromised backup into access to everything. |
| GPG | Same: a fresh key unless an old signature has to stay verifiable. The old secret key, if it must survive, belongs in Bitwarden or on the encrypted external SSD — not in a repo. |
| Passwords / logins | Bitwarden, which `install/10-packages.sh` installs. Nothing else in this setup stores a password; the LUKS passphrase and the login password are typed, never stored. |
| Wi-Fi, VPN | NetworkManager keeps these under `/etc/NetworkManager/system-connections/` with the PSKs in cleartext. Retype them, or copy that directory over from the old machine as root. |
| Keyring | `~/.local/share/keyrings/` is unlocked by the login password. It is re-created empty; apps ask again on first use. |

## 2. Fonts: SF Pro and SF Symbols

Used by the shell plugins for icons (`font.family: ".SF Symbols Fallback"`,
codepoints in `stow/apple-ui/.local/share/apple-ui/Apple.js`). Apple's license
does not allow redistributing the files, so they are in neither repo — and they
do not have to be, because they are a free download:

1. SF Pro and the SF Symbols app: <https://developer.apple.com/fonts/>
   (the Symbols app is a macOS `.dmg`, so open it on the Mac).
2. Copy `SF-Pro.ttf` and `SFSymbolsFallback.otf` into
   `~/.local/share/fonts/sf/`, then `fc-cache -f`.
3. `omarchy-restart-shell` — Quickshell caches the font list at startup, so
   the icons stay blank until it restarts.
4. Optional, for finding new codepoints: rsync
   `/Applications/SF Symbols.app/Contents/Resources/` off the Mac into
   `~/.local/share/sf-symbols/` (NOT into a fontconfig directory, or the older
   bundled font shadows the installed one). `Metadata/name_availability.plist`
   in there is Apple's full symbol-name list.

## 3. Fingerprint reader

None on this machine: Touch ID on the M1 MacBook Air has no Linux driver
under Asahi. The Goodix setup for the XPS 13 9310 (libfprint-tod, the Dell
blob, PAM lines) is in this file's git history before the M1 move.

## 4. Claude Code

`~/.claude/CLAUDE.md`, `settings.json` and the memory directory come from
`dotfiles-private` (its `install.sh` symlinks them). The `henri-ui` skill is
stowed from this repo (`stow/claude-skills`) and needs no extra step.
Logging in (`claude` → browser) is per machine.

## 5. Display and per-machine settings

| File | Why it is not restored |
|---|---|
| `~/.config/omarchy/omasettings.json` | pins a monitor profile by model name. OmaSettings writes it per machine. |
| `stow/hypr/.config/hypr/monitors.lua` | `gdk_scale` / `monitor_scale` were measured for the XPS 13's 16:10 panel. Set them for the new panel and commit that change. |
| `~/.config/hypr/hyprsunset.conf`, `.luarc.json` | Omarchy generates them. |

An `omarchy update` can reset `~/.config/hypr/*.lua` to stock defaults — it
writes `*.bak.<epoch>` next to them first. Because those paths are stow
symlinks, the damage shows up as a huge deletion in `git status` here; recover
with `git restore`, and check `hyprland.lua` (not tracked) for the
`require("hypr.omasettings")` / `require("hypr.settings")` lines it drops.

## 6. After every Hyprland update

`hyprswipe` is a compiled Hyprland plugin and is tied to the exact build:

```bash
~/Projects/hyprswipe/scripts/install.sh   # rebuilds and reinstalls the .so
```

Without it the 4-finger horizontal swipe is simply off — `input.lua` guards the
call, so nothing breaks.

## 7. Personal data

Deliberately in neither repo. From the external SSD (`OMARCHY_BACKUP` is a
bootable btrfs clone, `Daten` holds the archives):

`~/Documents` (three Obsidian vaults), `~/Uni`, `~/Work`, `~/Pictures`
(`Pictures/Wallpaper` is 645 MB of personal wallpapers — the `cupertino` and
`img-7075` themes want `IMG_7075.png` from there; step 40 warns and carries on
if it is missing),
`~/.local/share/calendars` (or let `vdirsyncer` re-sync), `~/.local/share/henri-finder/tags.json`
(Finder's tags), `~/Projects/akku-test/verlauf/` (the battery measurements).

`~/.local/share/voxtype/` (1.3 GB of models) is not worth copying — step 45
downloads it again.

## 8. Check afterwards

```bash
hyprctl reload                       # config loaded without errors
omarchy-restart-shell                # bar, dock, Mission Control come up
systemctl --user status voxtype akku-aufzeichnung
~/Projects/finder/bin/finder         # own apps start
omarchy-settings
```
