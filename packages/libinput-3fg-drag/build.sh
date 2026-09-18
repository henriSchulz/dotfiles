#!/bin/bash
# Baut libinput in der aktuellen Arch-Version mit dem 3-Finger-Ziehen-Patch
# und installiert es. Nach jedem libinput-Update erneut ausführen
# (der pacman-Hook erinnert daran).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

ver=$(pacman -Si libinput | awk -F': ' '/^Version/ {print $2; exit}')
sed -i "s/^pkgver=.*/pkgver=${ver%-*}/; s/^pkgrel=.*/pkgrel=${ver##*-}.1/" PKGBUILD

makepkg -sfci --noconfirm --cleanbuild
sudo install -Dm644 libinput-3fg-drag.hook /etc/pacman.d/hooks/libinput-3fg-drag.hook
rm -rf src pkg libinput ./*.pkg.tar.zst
echo "Fertig. Ab- und wieder anmelden, damit Hyprland das neue libinput lädt."
