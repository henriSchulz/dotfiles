# henri.power

Battery menu for the Omarchy bar in the henri-ui style. Fork of
[io.github.nipsen.dell-power](https://github.com/NIPSEN/omarchy-dell-power)
(MIT, see `LICENSE`) — same backend, rebuilt popup.

- **Always visible:** charge level with the charge-threshold markers (drag to
  change), battery size, time left / to full, charge cycles, current draw.
- **History** (a drill-in page, opened from the overview): the charge level
  — or, with the Charge/Power switch, the power draw on a round watt scale —
  over 15 or 30 min, 1, 3, 6, 12 or 24 h, 3 or 7 days (pop-up menu in the
  page header; ⏎ opens it too; both remembered — settings `historyRange`,
  default `6h`, and `historyMetric`, `percent` or `watts`) as 30–84 bars,
  accent on battery, pale while plugged in, red at 20 % and below (charge
  only), empty while asleep or off; hover a bar for its time, charge and
  draw — plus time and energy on battery, average draw, how long a full
  charge lasts and the current discharge. Reads the `akku-YYYY-MM-DD.csv`
  files the `akku-aufzeichnung` logger writes (setting `historyDir`, default
  `~/Documents/akku-test/verlauf`); off with `showHistory`.
- **Advanced** (a drill-in page; scrolls when taller than the screen): power profile, Dell/Alienware
  thermal mode, fans & temperatures, power flow, charge mode, USB ports.

Bar: left click opens the menu, right click toggles the percentage.
`omarchy-shell henri.power history` opens the menu on History;
`historyRange <15m|30m|1h|3h|6h|12h|24h|3d|7d>` and `historyMetric <percent|watts>` switch it.
Keyboard: → opens History (← back), ↓ / ⏎ open Advanced (there ←/→ + ⏎ pick a power profile); Esc goes back one page, and closes on the overview.

The privileged helper (`/usr/local/bin/dell-charge-limit`) is installed from
a fresh upstream checkout (the installer verifies itself against it):

    git clone https://github.com/NIPSEN/omarchy-dell-power /tmp/dell-power && /tmp/dell-power/install-system.sh
