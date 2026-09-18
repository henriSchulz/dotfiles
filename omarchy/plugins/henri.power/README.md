# henri.power

Battery menu for the Omarchy bar in the henri-ui style. Fork of
[io.github.nipsen.dell-power](https://github.com/NIPSEN/omarchy-dell-power)
(MIT, see `LICENSE`) — same backend, rebuilt popup.

- **Always visible:** charge level with the charge-threshold markers (drag to
  change), battery size, time left / to full, charge cycles, current draw.
- **Advanced** (collapsed on every open): power profile, Dell/Alienware
  thermal mode, fans & temperatures, power flow, charge mode, USB ports.

Bar: left click opens the menu, right click toggles the percentage.
Keyboard: ↓ / ⏎ open Advanced, ←/→ + ⏎ pick a power profile, ↑ folds it, Esc closes.

The privileged helper (`/usr/local/bin/dell-charge-limit`) is installed from
a fresh upstream checkout (the installer verifies itself against it):

    git clone https://github.com/NIPSEN/omarchy-dell-power /tmp/dell-power && /tmp/dell-power/install-system.sh
