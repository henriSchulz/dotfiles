# henri.power

Battery menu for the Omarchy bar in the henri-ui style. Fork of
[io.github.nipsen.dell-power](https://github.com/NIPSEN/omarchy-dell-power)
(MIT, see `LICENSE`) — same backend, rebuilt popup.

- **Always visible:** charge level with the charge-threshold markers (drag to
  change), battery size, time left / to full, charge cycles, current draw.
- **History** (a drill-in page, opened from the overview): the charge level
  — or, with the Charge/Power/Voltage/Current switch, the power draw, the
  pack voltage or the current on their own axis — over 15 or 30 min, 1, 3, 6,
  12 or 24 h, 3 or 7 days (pop-up menu in the page header; ⏎ opens it too;
  both remembered — settings `historyRange`, default `6h`, and
  `historyMetric`, `percent`, `watts`, `volts` or `amps`) as 30–84 bars,
  accent on battery, pale while plugged in, red at 20 % and below (charge
  only), empty while asleep or off; hover a bar for its time and value —
  plus time and energy on battery, average draw, how long a full charge
  lasts and the current discharge. Power and current start at zero; the
  voltage axis fits the window, since the pack only swings about a volt. Reads the `akku-YYYY-MM-DD.csv`
  files the `akku-aufzeichnung` logger writes (setting `historyDir`, default
  `~/Documents/akku-test/verlauf`); off with `showHistory`.
- **Power profile** (on the overview, right under the stat tiles): the
  power-profiles-daemon profiles as a segmented switch.
- **Advanced** (a drill-in page; scrolls when taller than the screen): fans &
  temperatures, power flow, charge mode, USB ports.

Bar: left click opens the menu, right click toggles the percentage.
`omarchy-shell henri.power history` opens the menu on History;
`historyRange <15m|30m|1h|3h|6h|12h|24h|3d|7d>` and
`historyMetric <percent|watts|volts|amps>` (or `charge|power|voltage|current`) switch it.
Keyboard: ←/→ + ⏎ pick a power profile, ↑ opens History (← back), ↓ opens Advanced; Esc goes back one page, and closes on the overview.

The privileged helper (`/usr/local/bin/dell-charge-limit`) is installed from
a fresh upstream checkout (the installer verifies itself against it):

    git clone https://github.com/NIPSEN/omarchy-dell-power /tmp/dell-power && /tmp/dell-power/install-system.sh
