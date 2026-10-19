# henri.power-v3

The battery in the Omarchy bar on Velum: "84 %" (right click shows or hides it)
and the drawn battery (VBattery). A left click grows the right island of the bar
into the battery menu (VIslandWindow, `align: "right"`).

Since 2026-10-19 the menu itself belongs to the Control Center:
`henri.control-center-v3/PowerService.qml` (everything it knows: UPower, the omarchy
battery/profile tools, the root helper `/usr/local/bin/dell-charge-limit`, the
akku-test history log) and `PowerPages.qml` (Overview, History). This
plugin loads both from `../henri.control-center-v3/`, so the island shows the very
pages of Control Center → Battery. Without that plugin the bar glyph still works.
Fork of [io.github.nipsen.dell-power](https://github.com/NIPSEN/omarchy-dell-power)
(MIT, see `LICENSE`).

- **Overview:** the battery picture, level and what it is doing; the charge limit
  with its two markers (drag to change, Dell helper only); the last hours as a chart
  (opens History); time, flow, health, capacity, cycles, power source; the power
  profiles as cards; History.
- **History:** charge, power, voltage or current as bars over 15 min … 7 days
  (pop-up menu in the head), hover reads a bar; time and energy on battery, average
  draw, how long a full charge lasts, this discharge, last charge. Reads the
  `akku-YYYY-MM-DD.csv` files of the akku-aufzeichnung logger.

History range, metric, `chargeLimitStep` and `historyDir` live in
`~/.local/state/velum/power.json`, shared by the Control Center and the island.

IPC `henri.power`: `open|close|toggle|togglePercentage`, `history`,
`historyRange <15m|30m|1h|3h|6h|12h|24h|3d|7d>`, `historyMetric <percent|watts|volts|amps>`,
`rangeMenu true|false`, `state`.
Keyboard in the island: ↑ History, ← back; Esc goes back one page, and closes on the overview.
