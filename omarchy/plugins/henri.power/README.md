# henri.power

Battery menu for the Omarchy bar in the henri-ui style. Fork of
[io.github.nipsen.dell-power](https://github.com/NIPSEN/omarchy-dell-power)
(MIT, see `LICENSE`) — same backend, rebuilt popup.

- **Always visible:** charge level with the charge-threshold markers (drag to
  change), battery size, time left / to full, charge cycles, current draw.
- **History** (a drill-in page, opened from the overview): the charge level
  over the last 6, 12 or 24 h (switch in the page header, remembered;
  setting `historyHours`, default 6) as 72 bars, accent on battery, pale
  while plugged in, red at 20 % and below, empty while asleep or off; hover a
  bar for its time, charge and draw — plus time and energy on battery,
  average draw, how long a full charge lasts and the current discharge. Reads
  the `akku-YYYY-MM-DD.csv` files the `akku-aufzeichnung` logger writes
  (setting `historyDir`, default `~/Documents/akku-test/verlauf`); off with
  `showHistory`.
- **Advanced** (a drill-in page; scrolls when taller than the screen): power profile, Dell/Alienware
  thermal mode, fans & temperatures, power flow, charge mode, USB ports.

Bar: left click opens the menu, right click toggles the percentage.
`omarchy-shell henri.power history` opens the menu on History.
Keyboard: → opens History (← back), ↓ / ⏎ open Advanced (there ←/→ + ⏎ pick a power profile); Esc goes back one page, and closes on the overview.

The privileged helper (`/usr/local/bin/dell-charge-limit`) is installed from
a fresh upstream checkout (the installer verifies itself against it):

    git clone https://github.com/NIPSEN/omarchy-dell-power /tmp/dell-power && /tmp/dell-power/install-system.sh
